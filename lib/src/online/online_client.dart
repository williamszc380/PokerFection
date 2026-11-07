import 'dart:async';
import 'dart:math';

import 'clock.dart';
import 'connect.dart';
import 'online_socket.dart';
import 'peer_config.dart';
import 'peer_socket.dart' show PeerConnector;
import 'protocol.dart';
import 'room_host.dart';
import 'rtc.dart' show NoDirectRoute;
import 'seat_proof.dart';
import 'timing.dart';

/// Where the connection is at.
enum OnlineStatus {
  connecting,
  open,

  /// The connection dropped (or went silent): getting it back, while the
  /// server keeps the seat.
  reconnecting,

  /// The connection dropped and couldn't be got back in time.
  lost,

  /// Ended on purpose: the player left, the server closed the room, or it
  /// wouldn't let the player back in ([OnlineClient.failure]).
  closed,
}

/// Creating or joining a room failed: the server said why ([error]), or it
/// couldn't be reached (null; [refused] when nothing listens there,
/// [noDirectRoute] when the host answered through the meeting service but
/// the two devices' networks won't let them connect directly).
class OnlineFailure implements Exception {
  const OnlineFailure([this.error]) : refused = false, noDirectRoute = false;
  const OnlineFailure.refused() : error = null, refused = true, noDirectRoute = false;
  const OnlineFailure.noDirectRoute() : error = null, refused = false, noDirectRoute = true;

  final JoinError? error;
  final bool refused;

  /// The room is there, but this device can't reach its host from the
  /// network it is on (often mobile data): another network may work, the
  /// same Wi-Fi always does. Its own message, not "can't connect".
  final bool noDirectRoute;

  @override
  String toString() => 'OnlineFailure(${error?.name ?? (noDirectRoute ? 'no direct route' : "can't connect")})';
}

/// What a device needs to come back to a room after the app was closed
/// (or the page reloaded): where, which room, and the token that proves
/// who the player is. Kept with the settings while the player is in a room.
class RejoinRecord {
  const RejoinRecord({
    required this.server,
    this.alsoTry = const [],
    required this.code,
    required this.token,
    required this.savedAt,
  });

  /// Where the room was last reached.
  final String server;

  /// Other ways to the room when [server] can't be reached: the room
  /// through the meeting service, for a guest who came in on the host's
  /// Wi-Fi and is elsewhere now.
  final List<String> alsoTry;
  final String code;
  final String token;

  /// When it was last saved (ms since 1970): once a hand, and whenever the
  /// room changes.
  final int savedAt;

  /// Whether it may still work: the server keeps a seat only a while
  /// after the connection drops (this is a guess; the server says).
  bool get fresh => DateTime.now().millisecondsSinceEpoch - savedAt < const Duration(minutes: 10).inMilliseconds;

  Map<String, Object?> toJson() => {
    'server': server,
    if (alsoTry.isNotEmpty) 'alsoTry': alsoTry,
    'code': code,
    'token': token,
    'savedAt': savedAt,
  };

  static RejoinRecord? fromJson(Object? json) => switch (json) {
    {'server': final String server, 'code': final String code, 'token': final String token, 'savedAt': final num at} =>
      RejoinRecord(
        server: server,
        alsoTry: [
          if (json['alsoTry'] case final List<Object?> more)
            for (final s in more)
              if (s is String) s,
        ],
        code: code,
        token: token,
        savedAt: at.toInt(),
      ),
    _ => null,
  };
}

/// The app's connection to the game server, for one room: opens it with a
/// create, join or rejoin message, says it is still there every few
/// seconds, and notices when the server goes silent.
///
/// A room may be reached at several addresses (the host's on the same
/// network, then on the internet): they are tried in order, each for a
/// short while, until one has the room.
///
/// When the connection drops, it comes back by itself ([reconnecting]):
/// it tries again and again, less often as time goes on, and the server
/// gives the seat back with the token it gave ([Welcome]), then a snapshot
/// to catch up with. Each try goes to the address that had the room, then
/// the other ways back: where the room was first reached and, when it can
/// be reached through the meeting service ([Welcome.peer]), there. So a
/// phone that left the host's Wi-Fi gets back in over mobile data. It
/// gives up when the server can't have kept the seat any longer
/// ([noDirectRoute] says when the last tries found the host but couldn't
/// connect to it), or at once when nobody listens at the address any more
/// (the host's app has stopped: the room is gone; reached through the
/// meeting service, once the room has been missing there for
/// [peerRefusalSpan]).
///
/// Over a direct connection, a seat is proven without naming its token
/// (RejoinRoom.proved): whoever holds the room's name at the meeting
/// service may not be its host.
///
/// Messages are read in order and kept until someone takes them ([attach]),
/// so none are lost while the screens change from the lobby to the table.
/// The room as last sent ([room]) and who this player is ([welcome]) are
/// kept here too, and [changes] fires whenever they (or [status]) change.
///
/// So is the room's chat ([chat]), which goes on from the lobby to the
/// table and back: its messages are taken as they come, never kept
/// waiting behind the hand's.
class OnlineClient {
  OnlineClient(
    this.url, {
    List<String> alsoTry = const [],
    this.host,
    this.onRecord,
    this._connect,
    this._peer,
    Clock? clock,
    Random? random,
  }) : _servers = {url, ...alsoTry}.toList(),
       _clock = clock ?? SystemClock(),
       _random = random ?? Random();

  /// The game server: the first to try, then the one that had the room.
  String url;
  final List<String> _servers;

  /// The game server running on this device, when this player hosts the
  /// room: it stops when the connection closes.
  final RoomHost? host;

  /// Told what to keep to come back to the room after the app is closed
  /// (null once there is nothing to come back to). Not for the host: the
  /// room ends with the host's app.
  final void Function(RejoinRecord? record)? onRecord;

  /// Opens a connection to a server (tests); when not given, connectAny,
  /// through [_peer] when given (tests), with the seat's token when coming
  /// back to a seat (for the pass that goes with an offer).
  final Future<OnlineSocket> Function(String url)? _connect;
  final PeerConnector? _peer;
  final Clock _clock;
  final Random _random;

  OnlineSocket? _socket;
  OnlineStatus status = OnlineStatus.connecting;

  /// Who this player is, once in a room.
  Welcome? welcome;

  /// The room as the server last sent it.
  RoomState? room;

  /// Why the server ended the room, if it did.
  CloseReason? closeReason;

  /// Why the server wouldn't let this player back in, if it didn't.
  JoinError? failure;

  /// The connection was [OnlineStatus.lost] because this network can't
  /// reach the host directly: the last tries found the host through the
  /// meeting service, but no way between the devices (another network may
  /// work, the same Wi-Fi does).
  bool noDirectRoute = false;

  /// The token of the seat being come back to (while rejoining or
  /// reconnecting), for the pass that goes with an offer through the
  /// meeting service.
  String? _seat;

  /// Where the room was first reached: a way back too, when a later
  /// address stops working.
  String? _home;

  /// The app's key this member joined with (see JoinRoom.device): a
  /// spectator who joins again ([_comeBack]) gives it again.
  String? _device;

  final StreamController<void> _changes = StreamController.broadcast();
  Stream<void> get changes => _changes.stream;

  /// The room's chat, oldest first: its last [chatKept] messages.
  final List<ChatLine> chat = [];

  /// Each chat message as it comes (once: not again when the room sends
  /// the whole chat to a device coming back).
  Stream<ChatLine> get said => _said.stream;
  final StreamController<ChatLine> _said = StreamController.broadcast();

  /// When this player said something lately (ms), oldest first.
  final List<int> _saidAt = [];

  final List<ServerMessage> _inbox = [];
  void Function(ServerMessage message)? _handler;

  Completer<Welcome>? _opening;
  int _lastHeard = 0;
  int _pings = 0;
  Timer? _pingTimer;

  /// Getting the connection back: since when, tries so far, and how many
  /// found nobody listening, in a row (since when).
  int _droppedAt = 0;
  int _tries = 0;
  int _refusals = 0;
  int _refusedSince = 0;

  /// Nobody holding a room's name at the meeting service (a [peerEntry])
  /// may only mean its host's connection to the service is being made
  /// again (which takes up to half a minute, see PeerSignaling.backoff):
  /// such a room counts as closed only once it has been missing this long.
  static const peerRefusalSpan = Duration(seconds: 45);
  bool _trying = false;
  Timer? _retry;

  /// The player gave up the seat ([close] with leave).
  bool _left = false;

  bool get isHost => welcome?.isHost ?? false;

  /// This member as the room last listed them (null before the room says).
  RoomMember? get myMember => room?.me;

  /// This member watches: no seat, or only waiting for one (the seat is
  /// theirs from the next hand: until then they get the spectator's view,
  /// see RoomMember.spectator). True until the room says otherwise.
  bool get isSpectator => myMember?.spectator ?? true;

  /// This member's seat, once it is theirs: null for a spectator, and for
  /// a member only waiting for a seat ([queuedSeat]), which may still be a
  /// leaving player's or a bot's that gives way until the hand ends.
  int? get mySeat => switch (myMember) {
    RoomMember(:final seat?, waiting: false) => seat,
    _ => null,
  };

  /// The seat this member waits for (theirs from the next hand), if any.
  int? get queuedSeat => switch (myMember) {
    RoomMember(:final seat?, waiting: true) => seat,
    _ => null,
  };

  /// Connects and sends [opening] (a [CreateRoom], [JoinRoom] or
  /// [RejoinRoom]), trying each server in turn while they can't be reached
  /// or don't have the room. Completes with the server's welcome; throws an
  /// [OnlineFailure]: no direct route if the host answered through the
  /// meeting service but couldn't be reached (the room is there: that says
  /// the most), else room not found if any server said so (or nobody held
  /// the room's name at the meeting service), else can't connect.
  Future<Welcome> open(ClientMessage opening) async {
    if (opening is RejoinRoom && opening.proof == null) _seat = opening.token;
    if (opening is JoinRoom) _device = opening.device;
    var failure = const OnlineFailure();
    for (final server in _servers) {
      try {
        return await _openAt(server, opening);
      } on OnlineFailure catch (e) {
        if (e.noDirectRoute) {
          failure = e;
        } else if (!failure.noDirectRoute && (e.error != null || (e.refused && isPeerEntry(server)))) {
          failure = e.error != null ? e : const OnlineFailure(JoinError.roomNotFound);
        }
        // Any other answer is the room's own: no use trying elsewhere.
        if (e.error != null && e.error != JoinError.roomNotFound) {
          failure = e;
          break;
        }
      }
    }
    status = OnlineStatus.closed;
    throw failure;
  }

  /// Connects to [server] and sends [opening]; completes with the welcome.
  /// While [reconnecting], the status stays so until the welcome comes.
  Future<Welcome> _openAt(String server, ClientMessage opening) async {
    final OnlineSocket socket;
    Future<OnlineSocket>? connecting;
    try {
      // Some ways in fail before there is a Future (a browser's WebSocket
      // refuses a ws:// address from the https site, or a badly typed one
      // at once): that is a failure like any other, and the next is tried.
      connecting = Future.sync(() => _connectTo(server));
      socket = await connecting.timeout(connectTimeout(server));
    } on ConnectionRefused {
      throw const OnlineFailure.refused();
    } on NoDirectRoute {
      throw const OnlineFailure.noDirectRoute();
    } catch (_) {
      // A connection that comes after all is nobody's: closed, or it would
      // keep its ports (a direct connection's, several) open for nothing.
      unawaited(connecting?.then((orphan) => orphan.close(), onError: (Object _) {}));
      throw const OnlineFailure();
    }
    url = server;
    if (status != OnlineStatus.reconnecting) status = OnlineStatus.connecting;
    _socket = socket;
    final opened = _opening = Completer<Welcome>();
    _lastHeard = _clock.nowMs;
    // Only the latest try's socket counts (an earlier one may still close).
    socket.messages.listen(
      (text) {
        if (_socket == socket) _onText(text);
      },
      onDone: () {
        if (_socket == socket) _onDone();
      },
    );
    final (sealed, unsafe) = _sealed(opening, socket);
    if (unsafe != null) {
      if (_socket == socket) _socket = null;
      unawaited(socket.close());
      throw unsafe;
    }
    socket.send(sealed.encode());
    _schedulePing();
    try {
      return await opened.future.timeout(const Duration(seconds: 10));
    } on Object catch (e) {
      _pingTimer?.cancel();
      if (_socket == socket) _socket = null;
      unawaited(socket.close());
      throw e is OnlineFailure ? e : const OnlineFailure();
    }
  }

  /// Opens a connection to [server]: the host's own app's in memory when
  /// its room runs inside the app ([RoomHost.connectOwn], a browser
  /// hosting), else as [_connect] does.
  Future<OnlineSocket> _connectTo(String server) {
    final host = this.host;
    if (host != null && server == host.ownServer) {
      if (host.connectOwn() case final own?) return Future.value(own);
    }
    return _connect?.call(server) ?? connectAny(server, peer: _peer, seat: _seat);
  }

  /// [opening] as it may go on [socket]: over a direct connection, a
  /// rejoin proves the seat for that connection rather than naming its
  /// token (whoever answered may not be the room's host). A direct
  /// connection that can't say which it is gets no token at all: then the
  /// failure to throw instead.
  (ClientMessage, OnlineFailure?) _sealed(ClientMessage opening, OnlineSocket socket) {
    if (opening is! RejoinRoom || opening.proof != null || socket is! BoundConnection) return (opening, null);
    final binding = (socket as BoundConnection).binding;
    if (binding == null) return (opening, const OnlineFailure());
    return (RejoinRoom.proved(code: opening.code, proof: seatProof(opening.token, binding)), null);
  }

  /// Sends [message], while connected (while reconnecting it is lost: the
  /// snapshot that comes back says what still needs doing).
  void send(ClientMessage message) {
    if (status == OnlineStatus.open) _socket?.send(message.encode());
  }

  /// How long until the player may say something again in the chat: zero
  /// when they may now. The server takes [chatBurst] messages each
  /// [OnlineTiming.chatWindow]; this waits a little more, for the network.
  Duration get chatWait {
    final now = _clock.nowMs, window = (OnlineTiming.chatWindow + OnlineTiming.grace).inMilliseconds;
    _saidAt.removeWhere((at) => now - at >= window);
    return _saidAt.length < chatBurst ? Duration.zero : Duration(milliseconds: window - (now - _saidAt.first));
  }

  /// Says [text] to everyone in the room (see [cleanChat]). False when it
  /// can't go: nothing is left of it, the connection is down, or the player
  /// must wait ([chatWait]).
  bool say(String text) {
    final clean = cleanChat(text);
    if (clean == null || status != OnlineStatus.open || chatWait > Duration.zero) return false;
    _saidAt.add(_clock.nowMs);
    send(Say(clean));
    return true;
  }

  /// Hands every message (those kept so far first) to [handler], in order.
  void attach(void Function(ServerMessage message) handler) {
    _handler = handler;
    while (_inbox.isNotEmpty && _handler == handler) {
      handler(_inbox.removeAt(0));
    }
  }

  /// Keeps messages again until the next [attach].
  void detach() => _handler = null;

  /// Puts [message] back in front, for the next [attach].
  void pushBack(ServerMessage message) => _inbox.insert(0, message);

  /// Ends the connection; with [leave], gives up the seat first. A host's
  /// server stops too (the room closes for everyone).
  Future<void> close({bool leave = true}) async {
    if (leave) send(const Leave());
    _left = leave;
    if (status != OnlineStatus.lost) status = OnlineStatus.closed;
    _pingTimer?.cancel();
    _retry?.cancel();
    _handler = null;
    _remember(null);
    try {
      await _socket?.close().timeout(const Duration(seconds: 2));
    } on Object {
      // Gone anyway.
    }
    _changed();
    await host?.stop();
  }

  /// Tries to reconnect right away (the app is back on screen), rather
  /// than at the next try. A host also checks its way in from the internet
  /// (its connection to the meeting service may have died meanwhile).
  void reconnectNow() {
    host?.checkInternet();
    if (status != OnlineStatus.reconnecting || _trying) return;
    _retry?.cancel();
    unawaited(_reconnect());
  }

  void _onText(String text) {
    _lastHeard = _clock.nowMs;
    final ServerMessage message;
    try {
      message = ServerMessage.decode(text);
    } on ProtocolError {
      // Nothing this app can read: skip it.
      return;
    }
    switch (message) {
      case Welcome() when status == OnlineStatus.closed:
        // Back in after the player left meanwhile (a try to reconnect was on its way): out again.
        if (_left) _socket?.send(const Leave().encode());
        unawaited(_socket?.close());
        final opening = _opening;
        if (opening != null && !opening.isCompleted) opening.complete(message);
      case Welcome():
        welcome = message;
        _home ??= url;
        status = OnlineStatus.open;
        _opening?.complete(message);
        _remember(message);
        _changed();
      case ServerError():
        final opening = _opening;
        if (opening != null && !opening.isCompleted) opening.completeError(OnlineFailure(message.code));
        status = OnlineStatus.closed;
        _changed();
      case RoomState():
        room = message;
        // The record to come back with is still good.
        _remember(welcome);
        _changed();
        _deliver(message);
      case Closing():
        closeReason = message.reason;
        status = OnlineStatus.closed;
        _remember(null);
        _changed();
        _deliver(message);
      case Pong():
        break;
      case ChatLines():
        _onChat(message);
      case NextHand():
        _remember(welcome);
        _deliver(message);
      default:
        _deliver(message);
    }
  }

  /// New chat messages, or the whole chat (coming back: what was missed
  /// meanwhile is new).
  void _onChat(ChatLines m) {
    final last = chat.lastOrNull?.n ?? 0;
    if (m.all) chat.clear();
    chat.addAll(m.lines);
    if (chat.length > chatKept) chat.removeRange(0, chat.length - chatKept);
    for (final line in m.lines) {
      if (line.n > last && !_said.isClosed) _said.add(line);
    }
    _changed();
  }

  void _deliver(ServerMessage message) {
    final handler = _handler;
    if (handler == null) {
      _inbox.add(message);
    } else {
      handler(message);
    }
  }

  void _onDone() {
    _pingTimer?.cancel();
    final opening = _opening;
    if (opening != null && !opening.isCompleted) {
      // A try that failed: whoever made it decides what's next.
      opening.completeError(const OnlineFailure());
      return;
    }
    _dropped();
  }

  /// The connection dropped (or went silent): in a room, starts getting it
  /// back; otherwise it is lost.
  void _dropped() {
    _pingTimer?.cancel();
    final socket = _socket;
    _socket = null;
    unawaited(socket?.close());
    if (status == OnlineStatus.closed || status == OnlineStatus.lost || status == OnlineStatus.reconnecting) return;
    if (status != OnlineStatus.open || welcome == null) {
      status = OnlineStatus.lost;
      _changed();
      return;
    }
    status = OnlineStatus.reconnecting;
    _droppedAt = _clock.nowMs;
    _tries = 0;
    _refusals = 0;
    _changed();
    _scheduleRetry();
  }

  /// The next try: soon at first, then less and less often (with a little
  /// chance, so devices don't all come back at the same moment).
  void _scheduleRetry() {
    _retry?.cancel();
    final wait = OnlineTiming.backoff[min(_tries, OnlineTiming.backoff.length - 1)];
    final jitter = Duration(milliseconds: _random.nextInt(OnlineTiming.backoffJitter.inMilliseconds + 1));
    _retry = _clock.schedule(wait + jitter, () => unawaited(_reconnect()));
  }

  /// The ways back to the room, in order: where it was reached last, then
  /// where it was first reached, then (for a guest) the room through the
  /// meeting service when it can be reached there ([Welcome.peer]). The
  /// host's own app is on the room's device: it never goes round.
  List<String> _waysBack(Welcome welcome) => {
    url,
    ?_home,
    if (welcome.peer && host == null) peerEntry(welcome.code),
  }.toList();

  /// One try to get the seat back: at the server that had the room, then
  /// the other ways back ([_waysBack]). Nobody listening counts only at the
  /// first, and not when another way found the host (it answered through
  /// the meeting service: it is there).
  Future<void> _reconnect() async {
    final welcome = this.welcome;
    if (status != OnlineStatus.reconnecting || _trying || welcome == null) return;
    _trying = true;
    _tries++;
    _seat = welcome.token;
    final first = url;
    var refused = false, noRoute = false;
    try {
      for (final (i, server) in _waysBack(welcome).indexed) {
        if (status != OnlineStatus.reconnecting) return;
        try {
          await _comeBack(server, welcome);
          // Back: the room and a snapshot follow.
          noDirectRoute = false;
          return;
        } on OnlineFailure catch (e) {
          if (e.error case final error?) {
            // The room is gone, or the seat was given up: nothing to come back to.
            failure = error;
            status = OnlineStatus.closed;
            _remember(null);
            _changed();
            return;
          }
          if (i == 0) refused = e.refused;
          if (e.noDirectRoute) {
            noRoute = true;
            refused = false;
          }
        }
      }
      // A way that connected but then failed made itself the server: the next try starts where this one did.
      url = first;
      _refusals = refused ? _refusals + 1 : 0;
      if (_refusals == 1) _refusedSince = _clock.nowMs;
      noDirectRoute = noRoute;
    } finally {
      _trying = false;
    }
    if (status != OnlineStatus.reconnecting) return;
    final span = isPeerEntry(first) ? peerRefusalSpan : Duration.zero;
    if (_refusals >= OnlineTiming.refusalsToGiveUp && _clock.nowMs - _refusedSince >= span.inMilliseconds) {
      // Nobody listens there any more: the host's app (and the room with it) has stopped.
      closeReason = CloseReason.roomClosed;
      status = OnlineStatus.closed;
    } else if (_clock.nowMs - _droppedAt >= OnlineTiming.giveUp.inMilliseconds) {
      status = OnlineStatus.lost;
    } else {
      _scheduleRetry();
      return;
    }
    _remember(null);
    _changed();
  }

  /// Back into the room at [server] with the member's token. A spectator
  /// away too long ([JoinError.seatGone]: the room let them go) joins
  /// again by name: they had nothing to keep but their place in the room,
  /// so there is no need to tell them (a seated player hears it). Removed
  /// or barred, they get the room's answer either way.
  Future<void> _comeBack(String server, Welcome welcome) async {
    try {
      await _openAt(server, RejoinRoom(code: welcome.code, token: welcome.token));
    } on OnlineFailure catch (e) {
      final me = myMember;
      if (e.error != JoinError.seatGone || me == null || !me.spectator) rethrow;
      await _openAt(server, JoinRoom(code: welcome.code, name: me.name, device: _device));
    }
  }

  /// Every few seconds: a ping, unless the server has been silent too long
  /// (then the connection counts as dropped).
  void _schedulePing() {
    _pingTimer?.cancel();
    _pingTimer = _clock.schedule(OnlineTiming.ping, () {
      if (status != OnlineStatus.open && status != OnlineStatus.connecting) return;
      if (_clock.nowMs - _lastHeard > OnlineTiming.clientSilence.inMilliseconds) {
        _dropped();
        return;
      }
      _socket?.send(Ping(++_pings).encode());
      _schedulePing();
    });
  }

  /// Saves what it takes to come back to the room ([w]'s), or forgets it:
  /// with every way back, not just the last address that worked.
  void _remember(Welcome? w) {
    if (host != null) return;
    onRecord?.call(
      w == null
          ? null
          : RejoinRecord(
              server: url,
              alsoTry: _waysBack(w).skip(1).toList(),
              code: w.code,
              token: w.token,
              savedAt: DateTime.now().millisecondsSinceEpoch,
            ),
    );
  }

  /// Whether the room can be reached through the meeting service (as its
  /// host said when this player came in): invites may name it then.
  bool get atMeetingService => welcome?.peer ?? false;

  void _changed() {
    if (!_changes.isClosed) _changes.add(null);
  }
}
