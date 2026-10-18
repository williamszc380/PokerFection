import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../engine/rules.dart';
import '../online/clock.dart';
import '../online/protocol.dart';
import '../online/seat_proof.dart';
import '../online/timing.dart';
import 'client_link.dart';
import 'room.dart';

/// Every room on the server, and every connection until it is in one.
///
/// A connection's first message creates, joins or rejoins a room (a player
/// coming back after their connection dropped, with their token); after
/// that its messages go to that room. A player the host removed can't join
/// or rejoin it. Each connection is limited: so many
/// messages a second, a few malformed ones, and it is dropped when silent
/// for too long, or when it hasn't asked for a room within [joinWait]
/// (anyone who knows a room's code can open connections to its host
/// through the meeting service: they mustn't pile up). Each address may
/// only open so many rooms a minute.
///
/// A player coming back over a direct connection proves their seat rather
/// than naming its token (RejoinRoom.proved, see seat_proof.dart).
class RoomRegistry {
  RoomRegistry({
    Clock? clock,
    Random? random,
    this.maxRooms = 200,
    this.joinsPerMinute = 20,
    this.onRoomClosed,
    this.nextCode,
    this.atMeetingService,
    void Function(String message)? log,
  }) : _clock = clock ?? SystemClock(),
       _random = random ?? Random.secure(),
       _log = log ?? ((_) {});

  final Clock _clock;

  /// Deals the cards and makes the room codes and tokens.
  final Random _random;
  final void Function(String message) _log;

  /// Most rooms open at once.
  final int maxRooms;

  /// Most rooms one address may create or join per minute.
  final int joinsPerMinute;

  /// Told whenever a room closes (a host on its own device then stops).
  final void Function(Room room)? onRoomClosed;

  /// The code the next room should have, when one is already decided (a
  /// host reserves its room's code at the meeting service before the room
  /// exists, see PeerHost); null, or a code a room has already, and a
  /// random one is made.
  final String? Function()? nextCode;

  /// Whether room [code] can be reached through the meeting service now
  /// (its host holds the name, see PeerHost): its welcomes say so, so
  /// guests know they may come back that way. Null: no room can (a server
  /// of its own).
  final bool Function(String code)? atMeetingService;

  /// How long a new connection has to create, join or rejoin a room before
  /// it is dropped: a device asks at once.
  static const joinWait = Duration(seconds: 15);

  final Map<String, Room> _rooms = {};
  final Map<String, List<int>> _joins = {};
  final Set<_Connection> _connections = {};

  /// Room codes: easy to read out, with no 0/O or 1/I/L to mix up.
  static const codeLetters = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const codeLength = 5;

  int get roomCount => _rooms.length;
  Room? room(String code) => _rooms[code];

  /// Starts serving a new connection.
  void accept(ClientLink link) => _connections.add(_Connection(this, link));

  /// Connections open now (in a room or not yet).
  int get connectionCount => _connections.length;

  /// The tokens of everyone with a seat in a room now (not left, not
  /// removed): a guest coming back shows a pass made with one (seatPass),
  /// so a host flooded with made-up offers still lets them in.
  Iterable<String> get seatTokens sync* {
    for (final room in _rooms.values) {
      yield* room.tokensSeated;
    }
  }

  /// The server is stopping: every room ends, for [reason].
  void shutdown([CloseReason reason = CloseReason.serverRestart]) {
    for (final room in [..._rooms.values]) {
      room.close(reason);
    }
    for (final c in [..._connections]) {
      c.drop();
    }
  }

  /// A random room code: [codeLength] of the [codeLetters], never all
  /// digits. An invite names a room through the meeting service as
  /// `peer:CODE`, and older apps (and the old invite page) read
  /// `peer:23456` as the server "peer" at port 23456 and would try it.
  static String randomCode(Random random) {
    while (true) {
      final code = String.fromCharCodes([
        for (var i = 0; i < codeLength; i++) codeLetters.codeUnitAt(random.nextInt(codeLetters.length)),
      ]);
      if (!_allDigits.hasMatch(code)) return code;
    }
  }

  static final _allDigits = RegExp(r'^\d+$');

  String _newCode() {
    final wanted = nextCode?.call();
    if (wanted != null && !_rooms.containsKey(wanted)) return wanted;
    while (true) {
      final code = randomCode(_random);
      if (!_rooms.containsKey(code)) return code;
    }
  }

  /// 128 random bits, as text.
  String _newToken() => base64Url.encode([for (var i = 0; i < 16; i++) _random.nextInt(256)]).replaceAll('=', '');

  /// Whether [address] may create or join one more room this minute.
  bool _mayJoin(String address) {
    final now = _clock.nowMs;
    // Addresses not seen for a minute are forgotten.
    if (_joins.length > 500) _joins.removeWhere((_, times) => times.every((t) => now - t >= 60000));
    final recent = _joins.putIfAbsent(address, () => [])..removeWhere((t) => now - t >= 60000);
    if (recent.length >= joinsPerMinute) return false;
    recent.add(now);
    return true;
  }

  /// A connection's first message: creates, joins or rejoins a room.
  /// Returns the room and the player, or null when it failed (the
  /// connection is told why and dropped).
  (Room, RoomPlayer)? _open(_Connection c, ClientMessage m) {
    final int version, rules;
    switch (m) {
      case CreateRoom():
        version = m.version;
        rules = m.rules;
      case JoinRoom():
        version = m.version;
        rules = m.rules;
      case RejoinRoom():
        version = m.version;
        rules = m.rules;
      default:
        c.reject(Rejection.badMessage);
        return null;
    }
    JoinError? error;
    (Room, RoomPlayer)? opened;
    if (version != protocolVersion || rules != rulesVersion) {
      error = JoinError.upgrade;
    } else if (!_mayJoin(c.link.address)) {
      error = JoinError.rateLimited;
    } else if (m is CreateRoom) {
      if (_rooms.length >= maxRooms) {
        error = JoinError.serverFull;
      } else {
        final code = _newCode();
        final room = Room(
          code: code,
          settings: m.settings,
          bots: m.bots,
          clock: _clock,
          random: _random,
          onClosed: (room) {
            _rooms.remove(room.code);
            onRoomClosed?.call(room);
          },
          atMeetingService: atMeetingService == null ? null : () => atMeetingService!(code),
          log: _log,
        );
        _rooms[room.code] = room;
        opened = (room, room.addHost(c.link, m.name, _newToken()));
      }
    } else if (m is JoinRoom) {
      final room = _rooms[m.code.trim().toUpperCase()];
      // A device the host removed a player from stays out.
      final barred = room != null && room.bars(device: m.device);
      final player = barred ? null : room?.join(c.link, m.name, _newToken(), device: m.device);
      if (room == null) {
        error = JoinError.roomNotFound;
      } else if (barred) {
        error = JoinError.removed;
      } else if (player == null) {
        error = JoinError.tableFull;
      } else {
        opened = (room, player);
      }
    } else if (m is RejoinRoom) {
      final room = _rooms[m.code.trim().toUpperCase()];
      final token = switch (m.proof) {
        null => m.token,
        // Proven for this connection only: one that can't say which it is proves nothing.
        final proof => switch (c.link) {
          BoundConnection(binding: final binding?) => room?.tokenProven((t) => sameProof(seatProof(t, binding), proof)),
          _ => null,
        },
      };
      final barred = room != null && token != null && room.bars(token: token);
      final player = barred || token == null ? null : room?.rejoin(c.link, token);
      if (room == null) {
        // Closed while the player was away (rooms live only in memory).
        error = JoinError.roomGone;
      } else if (barred) {
        error = JoinError.removed;
      } else if (player == null) {
        // Away too long: the seat may be someone else's now.
        error = JoinError.seatGone;
      } else {
        opened = (room, player);
      }
    }
    if (error != null) c.refuse(error);
    return opened;
  }
}

/// The server's side of one connection.
class _Connection {
  _Connection(this.registry, this.link) {
    _subscription = link.messages.listen(_onText, onDone: _onDone, onError: (Object _) => _onDone());
    _lastRefill = registry._clock.nowMs;
    _watchSilence();
    _joinDeadline = registry._clock.schedule(RoomRegistry.joinWait, () {
      if (_room == null) drop();
    });
  }

  final RoomRegistry registry;
  final ClientLink link;
  late final StreamSubscription<String> _subscription;

  Room? _room;
  RoomPlayer? _player;
  bool _done = false;

  /// Up to [_rate] messages a second, in bursts of up to [_burst].
  static const _rate = 30, _burst = 60;
  double _tokens = _burst.toDouble();
  late int _lastRefill;

  /// Malformed messages so far; the connection is dropped after a few.
  int _bad = 0;
  static const _maxBad = 5;

  Timer? _silence;

  /// Drops the connection if it hasn't got into a room by then (pings alone
  /// don't keep it).
  Timer? _joinDeadline;

  void _watchSilence() {
    _silence?.cancel();
    _silence = registry._clock.schedule(OnlineTiming.serverSilence, drop);
  }

  bool _withinRate() {
    final now = registry._clock.nowMs;
    _tokens = min(_burst.toDouble(), _tokens + (now - _lastRefill) * _rate / 1000);
    _lastRefill = now;
    if (_tokens < 1) return false;
    _tokens -= 1;
    return true;
  }

  void _onText(String text) {
    if (_done) return;
    _watchSilence();
    if (!_withinRate()) {
      reject(Rejection.rateLimited);
      return;
    }
    final ClientMessage message;
    try {
      message = ClientMessage.decode(text);
    } on ProtocolError {
      if (++_bad >= _maxBad) {
        drop();
      } else {
        reject(Rejection.badMessage);
      }
      return;
    }
    if (message is Ping) {
      link.send(Pong(message.n).encode());
      return;
    }
    final room = _room, player = _player;
    if (room == null || player == null) {
      final opened = registry._open(this, message);
      if (opened != null) {
        _room = opened.$1;
        _player = opened.$2;
        _joinDeadline?.cancel();
      }
      return;
    }
    // A newer connection of the same player took over: this one is done.
    if (player.link != link) {
      drop();
      return;
    }
    room.receive(player, message);
    // The room let the player go (they left, or it closed).
    if (room.isClosed || player.link != link) drop();
  }

  void _onDone() {
    if (_done) return;
    _done = true;
    _silence?.cancel();
    _joinDeadline?.cancel();
    registry._connections.remove(this);
    final room = _room, player = _player;
    // The player is away (unless they left, or came back on another connection).
    if (room != null && player != null) room.disconnected(player, link);
  }

  void reject(Rejection reason) => link.send(Rejected(reason).encode());

  /// The first message failed: says why, and ends the connection.
  void refuse(JoinError error) {
    link.send(ServerError(error).encode());
    drop();
  }

  /// Ends the connection.
  void drop() {
    _onDone();
    unawaited(_subscription.cancel());
    unawaited(link.close());
  }
}
