/// Talking to the meeting service (PeerJS's free public server, see
/// peer_config.dart), which passes the messages that set up a direct
/// connection between two devices: the guest's offer, the host's answer,
/// and both ends' candidates. Nothing else goes through it.
///
/// The public server is not the open-source peerjs-server: live tests
/// (October 2026) found it stricter, and [PeerSignaling] keeps to what they
/// found:
/// - Only messages shaped exactly like the official PeerJS client's are
///   passed on (OFFER, ANSWER, CANDIDATE, HEARTBEAT). Anything else, a
///   missing field, a LEAVE or a message over 20,000 bytes, and the server
///   closes the sender's connection without a word.
/// - Nothing waits for a device that isn't there: a message to a name nobody
///   holds comes straight back as EXPIRE, at most once every 3 s or so for
///   the same sender and target.
/// - A connection that sends nothing for about 99 s is cut.
/// - The same name with the same token takes the name over (the new
///   connection gets OPEN, the old one is closed); with another token the
///   server answers ID-TAKEN and closes.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'clock.dart';
import 'online_socket.dart';
import 'peer_config.dart';
import 'protocol.dart' show protocolVersion;
import 'rtc.dart' show RtcCandidate;
import 'socket.dart';

/// Opens a WebSocket to a URL (connectSocket, or a fake in tests).
typedef SocketConnector = Future<OnlineSocket> Function(String url);

/// Something that happened at the meeting service.
sealed class SignalEvent {
  const SignalEvent();
}

/// The server took our name: at first, or again after the connection
/// dropped ([reconnected]).
class SignalOpen extends SignalEvent {
  const SignalOpen({required this.reconnected});
  final bool reconnected;
}

/// The connection dropped. With [reconnecting], tries to get it back (same
/// name and token) follow; [SignalOpen] says when one worked.
class SignalClosed extends SignalEvent {
  const SignalClosed({required this.reconnecting});
  final bool reconnecting;
}

/// A try to get the connection back failed (the service can't be reached);
/// the next comes after [wait].
class SignalRetrying extends SignalEvent {
  const SignalRetrying(this.wait);
  final Duration wait;
}

/// Coming back, the name was someone else's: it is lost, and no more tries
/// follow, unless the connection was made to take it back
/// ([PeerSignaling.retake]: then [SignalOpen] once it is free again).
class SignalIdTaken extends SignalEvent {
  const SignalIdTaken();
}

/// Nobody holds the name [peer] (any more): our message to it went nowhere.
class SignalExpire extends SignalEvent {
  const SignalExpire(this.peer);
  final String peer;
}

/// A guest ([from]) offers a connection ([connectionId], new for each try).
/// [metadata] says what app it comes from (see [PeerSignaling.offerMetadata]).
class SignalOffer extends SignalEvent {
  const SignalOffer(this.from, this.connectionId, this.sdp, this.metadata);
  final String from, connectionId, sdp;
  final Object? metadata;
}

/// The host ([from]) answers our offer for [connectionId].
class SignalAnswer extends SignalEvent {
  const SignalAnswer(this.from, this.connectionId, this.sdp);
  final String from, connectionId, sdp;
}

/// One of [from]'s candidates, for the connection [connectionId].
class SignalCandidate extends SignalEvent {
  const SignalCandidate(this.from, this.connectionId, this.candidate);
  final String from, connectionId;
  final RtcCandidate candidate;
}

/// The name asked for is someone else's (held with another token).
class PeerIdTaken implements Exception {
  const PeerIdTaken(this.id);
  final String id;

  @override
  String toString() => 'PeerIdTaken($id)';
}

/// The meeting service couldn't be reached, or didn't take our name in time
/// (it is sometimes minutes late: peerjs issue #1350).
class SignalingUnavailable implements Exception {
  const SignalingUnavailable(this.why);
  final String why;

  @override
  String toString() => 'SignalingUnavailable($why)';
}

/// One device's connection to the meeting service, under the name [id].
///
/// [open] takes the name. While it is held, a heartbeat goes every
/// [heartbeatEvery] so the server doesn't cut the connection, and the
/// messages for us come on [events]. If the connection drops, it comes back
/// by itself with the same name and token, less often as time goes on
/// ([backoff]), unless [reconnect] is off (a guest only needs the service
/// for a moment) or the name has meanwhile been taken.
///
/// A host's connection must never miss a guest, yet a connection can die
/// without either end hearing of it. So with [watch] on, it sends itself a
/// candidate every [probeEvery] (and on [probe]): if it doesn't come back
/// within [probeWait], the connection counts as dead and is made again.
///
/// Only one connection per name and token may ever reconnect: two would take
/// the name from each other over and over.
///
/// A name taken by someone else while the connection was being made again
/// is lost, unless [retake] is on (a host's: its room has that code, and
/// whoever took the name may only have meant to catch its guests): then it
/// keeps trying every [retakeWait] and takes the name back once it is free.
class PeerSignaling {
  /// [token] is made at random when not given. [connect] opens the
  /// WebSocket (connectSocket, which serves the apps and browsers alike);
  /// tests give a fake of it, a [clock] and a [random] for the waits.
  PeerSignaling(
    this.id, {
    String? token,
    this.broker = peerBroker,
    SocketConnector? connect,
    Clock? clock,
    Random? random,
    this.watch = false,
    this.reconnect = true,
    this.retake = false,
  }) : token = token ?? sessionToken(),
       _connect = connect ?? connectSocket,
       _clock = clock ?? SystemClock(),
       _random = random ?? Random();

  /// Our name at the service ([hostPeerId] or [guestPeerId]).
  final String id;

  /// The secret that goes with [id] for this session: kept, so a reconnect
  /// takes the name back.
  final String token;

  /// The service's WebSocket address (without the query).
  final String broker;

  /// Whether to check the connection really works now and then (the host's).
  final bool watch;

  /// Whether to get the connection back when it drops.
  final bool reconnect;

  /// Whether to keep trying for the name when someone else took it.
  final bool retake;

  /// How often to try for the name again while someone else holds it.
  static const retakeWait = Duration(seconds: 15);

  final SocketConnector _connect;
  final Clock _clock;
  final Random _random;

  /// Heartbeats keep the connection: the server cuts one silent for ~99 s.
  static const heartbeatEvery = Duration(seconds: 20);

  /// How often the host checks its connection, and how long the check may
  /// take before the connection counts as dead.
  static const probeEvery = Duration(seconds: 60);
  static const probeWait = Duration(seconds: 8);

  /// How long the server may take to say OPEN (or ID-TAKEN).
  static const openWait = Duration(seconds: 10);

  /// Waits before each try to reconnect (the last repeats), each give or
  /// take [backoffJitter] of it, so devices don't all come back at once.
  static const backoff = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 15),
  ];
  static const backoffJitter = 0.2;

  /// The server tells about a missing peer at most once per ~3 s for the
  /// same sender and target: an offer to a peer that was missing goes at
  /// least this long after it was found missing, or no answer would come.
  static const expireSpacing = Duration(milliseconds: 3500);

  /// Longest message sent (in UTF-8 bytes). The server closes the sender on
  /// one over 20,000; ours are well under (an offer is about 500 bytes).
  static const maxMessage = 16 * 1024;

  /// What every offer says about where it comes from: this app, the format
  /// of these messages, and the game's protocol (checked again, properly,
  /// once connected).
  static const offerMetadata = {'app': 'pokerfection', 'v': 1, 'proto': protocolVersion};

  /// The address to open: the official client's, whose `key` the public
  /// server ignores.
  String get url =>
      '$broker?key=peerjs&id=${Uri.encodeQueryComponent(id)}'
      '&token=${Uri.encodeQueryComponent(token)}&version=1.5.5';

  final StreamController<SignalEvent> _events = StreamController.broadcast();

  /// What happens at the service, from the moment it happens.
  Stream<SignalEvent> get events => _events.stream;

  OnlineSocket? _socket;
  bool _closed = false, _everOpened = false, _idTaken = false;
  int _tries = 0, _probes = 0;
  Timer? _heartbeat, _probeTimer, _probeDeadline, _retry;
  String? _probeId;

  /// When each peer was last found missing (ms), for [expireSpacing].
  final Map<String, int> _expiredAt = {};

  /// Whether the name is held now.
  bool get isOpen => _socket != null;

  /// Whether the name was lost to someone else while coming back (and,
  /// with [retake], isn't back yet).
  bool get idTaken => _idTaken;

  /// Whether it is waiting to try to reconnect.
  bool get retrying => _retry?.isActive ?? false;

  /// Takes the name: completes on the server's OPEN. Throws [PeerIdTaken]
  /// when someone else holds it, or [SignalingUnavailable]; then nothing
  /// more happens unless asked ([open] again, or [keepTrying]).
  Future<void> open() async {
    if (_closed) throw const SignalingUnavailable('closed');
    if (isOpen) return;
    _retry?.cancel();
    await _attempt();
  }

  /// After [open] failed: keeps trying in the background, as after a dropped
  /// connection ([SignalOpen] when it works). Also after it failed because
  /// the name was someone else's, with [retake] (every [retakeWait]).
  void keepTrying() {
    if (_closed || isOpen || (_idTaken && !retake) || retrying) return;
    _scheduleRetry();
  }

  /// Sends the guest's offer to the host [to], with [offerMetadata] and
  /// [extra] (a seated player's pass). Waits first if [to] was just found
  /// missing ([expireSpacing]). False if it couldn't go.
  Future<bool> sendOffer(
    String to, {
    required String connectionId,
    required String sdp,
    Map<String, Object> extra = const {},
  }) async {
    final missing = _expiredAt[to];
    if (missing != null) {
      final left = expireSpacing.inMilliseconds - (_clock.nowMs - missing);
      if (left > 0) {
        final waited = Completer<void>();
        _clock.schedule(Duration(milliseconds: left), waited.complete);
        await waited.future;
      }
    }
    return _send({
      'type': 'OFFER',
      'payload': {
        'sdp': {'type': 'offer', 'sdp': sdp},
        'type': 'data',
        'connectionId': connectionId,
        // Required by the server for a data connection (any text will do).
        'label': connectionId,
        'reliable': true,
        'serialization': 'raw',
        'metadata': {...offerMetadata, ...extra},
      },
      'dst': to,
    });
  }

  /// Sends the host's answer to the guest [to]. False if it couldn't go.
  bool sendAnswer(String to, {required String connectionId, required String sdp}) => _send({
    'type': 'ANSWER',
    'payload': {
      'sdp': {'type': 'answer', 'sdp': sdp},
      'type': 'data',
      'connectionId': connectionId,
    },
    'dst': to,
  });

  /// Sends one of our candidates to [to]. Always with the media section
  /// (the data channel's, `'0'` and 0, when the candidate doesn't say):
  /// browsers refuse a candidate without it. False if it couldn't go.
  bool sendCandidate(String to, {required String connectionId, required RtcCandidate candidate}) => _send({
    'type': 'CANDIDATE',
    'payload': {
      // Must be an object: a bare string gets the sender closed.
      'candidate': {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid ?? '0',
        'sdpMLineIndex': candidate.sdpMLineIndex ?? 0,
      },
      'type': 'data',
      'connectionId': connectionId,
    },
    'dst': to,
  });

  /// Checks now that the connection really works (the app is back on
  /// screen, say): a candidate to ourselves, which the server sends back.
  /// No answer within [probeWait], and the connection is made again.
  void probe() {
    if (!isOpen || _probeId != null) return;
    final probe = _probeId = 'probe-${++_probes}';
    sendCandidate(id, connectionId: probe, candidate: const RtcCandidate(''));
    _probeDeadline = _clock.schedule(probeWait, () {
      if (_probeId == probe) _dead();
    });
  }

  /// Gives the name back and stops (no more tries, no more events).
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _stopTimers();
    _retry?.cancel();
    final socket = _socket;
    _socket = null;
    unawaited(_events.close());
    await socket?.close();
  }

  /// One try: connects, and completes on the server's first word.
  Future<void> _attempt() async {
    final OnlineSocket socket;
    try {
      socket = await _connect(url);
    } on Object catch (e) {
      throw SignalingUnavailable("can't connect: $e");
    }
    if (_closed) {
      unawaited(socket.close());
      throw const SignalingUnavailable('closed');
    }
    final first = Completer<void>();
    Timer? wait;
    void fail(Object error) {
      if (first.isCompleted) return;
      wait?.cancel();
      first.completeError(error);
      unawaited(socket.close());
    }

    socket.messages.listen(
      (text) {
        if (!first.isCompleted) {
          // Taken here at once, so nothing that follows is missed.
          switch (_typeOf(text)) {
            case 'OPEN':
              wait?.cancel();
              first.complete();
              _opened(socket);
            case 'ID-TAKEN':
              fail(PeerIdTaken(id));
            default:
              fail(SignalingUnavailable('unexpected first message: $text'));
          }
        } else if (identical(_socket, socket)) {
          _onText(text);
        }
      },
      onDone: () {
        fail(const SignalingUnavailable('closed before OPEN'));
        if (identical(_socket, socket)) _lost();
      },
    );
    wait = _clock.schedule(openWait, () => fail(const SignalingUnavailable('no OPEN in time')));
    return first.future;
  }

  void _opened(OnlineSocket socket) {
    if (_closed) {
      unawaited(socket.close());
      return;
    }
    _socket = socket;
    _tries = 0;
    _idTaken = false;
    _scheduleHeartbeat();
    if (watch) _scheduleProbe();
    _emit(SignalOpen(reconnected: _everOpened));
    _everOpened = true;
  }

  void _scheduleHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = _clock.schedule(heartbeatEvery, () {
      if (_sendRaw('{"type":"HEARTBEAT"}')) _scheduleHeartbeat();
    });
  }

  void _scheduleProbe() {
    _probeTimer?.cancel();
    _probeTimer = _clock.schedule(probeEvery, () {
      if (!isOpen) return;
      probe();
      _scheduleProbe();
    });
  }

  /// The connection dropped (or went dead).
  void _lost() {
    _socket = null;
    _stopTimers();
    if (_closed) return;
    _emit(SignalClosed(reconnecting: reconnect));
    if (reconnect) _scheduleRetry();
  }

  /// The connection looks open but our own message didn't come back: it is
  /// dead. Closed, and made again.
  void _dead() {
    final socket = _socket;
    _lost();
    unawaited(socket?.close());
  }

  /// Schedules the next try; returns how long until it.
  Duration _scheduleRetry() {
    _retry?.cancel();
    final base = backoff[min(_tries, backoff.length - 1)];
    _tries++;
    final jitter = 1 - backoffJitter + 2 * backoffJitter * _random.nextDouble();
    final wait = Duration(milliseconds: (base.inMilliseconds * jitter).round());
    _retry = _clock.schedule(wait, () => unawaited(_tryAgain()));
    return wait;
  }

  Future<void> _tryAgain() async {
    if (_closed || isOpen) return;
    try {
      await _attempt();
    } on PeerIdTaken {
      if (!_idTaken) _emit(const SignalIdTaken());
      _idTaken = true;
      if (retake && !_closed) _retry = _clock.schedule(retakeWait, () => unawaited(_tryAgain()));
    } on SignalingUnavailable {
      if (_closed) return;
      _emit(SignalRetrying(_scheduleRetry()));
    }
  }

  void _onText(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      return;
    }
    if (json is! Map) return;
    final src = json['src'], payload = json['payload'];
    final from = src is String ? src : '';
    final p = payload is Map ? payload : const {};
    final cid = p['connectionId'] is String ? p['connectionId'] as String : '';
    switch (json['type']) {
      case 'OFFER':
        final sdp = p['sdp'] is Map ? (p['sdp'] as Map)['sdp'] : null;
        if (sdp is String && cid.isNotEmpty && from.isNotEmpty) _emit(SignalOffer(from, cid, sdp, p['metadata']));
      case 'ANSWER':
        final sdp = p['sdp'] is Map ? (p['sdp'] as Map)['sdp'] : null;
        if (sdp is String && cid.isNotEmpty && from.isNotEmpty) _emit(SignalAnswer(from, cid, sdp));
      case 'CANDIDATE':
        if (from == id) {
          // Our own check came back: the connection works.
          if (cid == _probeId) {
            _probeId = null;
            _probeDeadline?.cancel();
          }
          return;
        }
        final c = p['candidate'];
        if (c is Map && c['candidate'] is String && cid.isNotEmpty && from.isNotEmpty) {
          final mid = c['sdpMid'], index = c['sdpMLineIndex'];
          _emit(
            SignalCandidate(
              from,
              cid,
              RtcCandidate(
                c['candidate'] as String,
                sdpMid: mid is String ? mid : null,
                sdpMLineIndex: index is num ? index.toInt() : null,
              ),
            ),
          );
        }
      case 'EXPIRE':
        if (from.isEmpty) return;
        final now = _clock.nowMs;
        _expiredAt.removeWhere((_, at) => now - at >= expireSpacing.inMilliseconds);
        _expiredAt[from] = now;
        _emit(SignalExpire(from));
      default:
        // HEARTBEAT, LEAVE, ERROR: nothing to do.
        break;
    }
  }

  bool _send(Map<String, Object?> message) {
    final text = jsonEncode(message);
    if (utf8.encode(text).length > maxMessage) return false;
    return _sendRaw(text);
  }

  bool _sendRaw(String text) {
    final socket = _socket;
    if (socket == null || _closed) return false;
    socket.send(text);
    return true;
  }

  void _emit(SignalEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  void _stopTimers() {
    _heartbeat?.cancel();
    _probeTimer?.cancel();
    _probeDeadline?.cancel();
    _probeId = null;
  }

  static String? _typeOf(String text) {
    try {
      final json = jsonDecode(text);
      return json is Map && json['type'] is String ? json['type'] as String : null;
    } on FormatException {
      return null;
    }
  }
}
