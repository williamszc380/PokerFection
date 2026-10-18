import 'dart:async';
import 'dart:math';

import 'channel_socket.dart';
import 'clock.dart';
import 'online_socket.dart';
import 'peer_config.dart';
import 'rtc.dart';
import 'seat_proof.dart';
import 'signaling.dart';

/// Connects to the room with [code] directly, wherever its host is (see
/// [PeerConnector]); [via] one made for the purpose (tests), else the app's.
/// A player coming back to their seat gives its token as [seat].
Future<OnlineSocket> connectPeer(String code, {PeerConnector? via, String? seat}) =>
    (via ?? (_appConnector ??= PeerConnector())).connect(code, seat: seat);

PeerConnector? _appConnector;

/// A guest's way to a room's host over the internet, with no server of our
/// own: it takes a name at the meeting service (see peer_config.dart),
/// offers a direct connection to the host's name there (the room's code),
/// and passes candidates both ways until the connection's data channel
/// opens. The game then goes over that channel ([ChannelSocket]).
///
/// One name at the meeting service serves every try while they come one
/// after another (getting a dropped connection back, say), and is given
/// back [linger] after the last one has settled: nothing more comes
/// through it once connected.
class PeerConnector {
  /// [rtc] makes the peer connections (this platform's when not given),
  /// [connectSignaling] opens the WebSocket to the meeting service
  /// (connectSocket when not given); tests give fakes of both, and a [clock].
  PeerConnector({
    this._rtc,
    this._connectSignaling,
    this.broker = peerBroker,
    Clock? clock,
    Random? random,
  }) : _clock = clock ?? SystemClock(),
       _random = random ?? Random.secure();

  /// The meeting service's address.
  final String broker;

  RtcFactory? _rtc;
  final SocketConnector? _connectSignaling;
  final Clock _clock;
  final Random _random;

  /// Longest a try may take, from start to open channel.
  static const timeout = Duration(seconds: 20);

  /// How long the name at the meeting service is kept after the last try.
  static const linger = Duration(seconds: 5);

  /// How many random names to try when one is (very rarely) taken.
  static const nameTries = 3;

  PeerSignaling? _signaling;
  Future<PeerSignaling>? _opening;
  int _active = 0;
  Timer? _linger;

  /// Whether it holds a name at the meeting service now.
  bool get hasSignaling => _signaling?.isOpen ?? false;

  /// Connects to the host of room [code]; completes once the data channel
  /// is open. Throws [ConnectionRefused] when nobody holds the room's name
  /// before the host has answered (no such room, or its host has gone),
  /// [NoDirectRoute] when the host
  /// answered but no way between the devices was found, and something else
  /// when the meeting service can't be reached or it took too long.
  ///
  /// A player coming back to their seat gives its token as [seat]: the
  /// offer then carries a pass made with it (seatPass, never the token), so
  /// a host flooded with made-up offers still answers.
  Future<OnlineSocket> connect(String code, {String? seat}) async {
    _active++;
    _linger?.cancel();
    final attempt = _Attempt(hostPeerId(code), 'dc_${randomLetters(12, _random)}', seat: seat);
    final deadline = _clock.schedule(
      timeout,
      () => attempt.fail(attempt.answered ? const NoDirectRoute() : TimeoutException('No answer from room $code')),
    );
    unawaited(_run(attempt));
    try {
      return await attempt.result.future;
    } finally {
      deadline.cancel();
      attempt.cleanUp();
      if (--_active == 0) {
        _linger = _clock.schedule(linger, () {
          if (_active > 0) return;
          final signaling = _signaling;
          _signaling = null;
          unawaited(signaling?.close());
        });
      }
    }
  }

  Future<void> _run(_Attempt a) async {
    try {
      final rtc = _rtc ??= platformRtc();
      final signaling = await _openSignaling();
      if (a.over) return;
      a.signals = signaling.events.listen((event) {
        switch (event) {
          case SignalAnswer(:final from, :final connectionId, :final sdp) when from == a.host && connectionId == a.id:
            a.answered = true;
            a.answerSdp = sdp;
            a.peer?.acceptAnswer(sdp).catchError(a.fail);
          case SignalCandidate(:final from, :final connectionId, :final candidate)
              when from == a.host && connectionId == a.id:
            a.peer?.addRemoteCandidate(candidate);
          case SignalExpire(:final peer) when peer == a.host && !a.answered:
            // Nobody holds the room's name: no such room (any more). Once
            // the host has answered, the room is there: its connection to
            // the meeting service only dropped for a moment (it comes back
            // within seconds), and the candidates already passed on may
            // still be enough; the way is found, or the deadline decides.
            a.fail(const ConnectionRefused());
          case SignalClosed() when !a.answered:
            a.fail(const SignalingUnavailable('dropped'));
          default:
            break;
        }
      });
      final peer = a.peer = rtc.create();
      a.states = peer.onState.listen((state) {
        if (state == RtcState.failed) a.fail(const NoDirectRoute());
      });
      final sdp = await peer.offer();
      if (a.over) return;
      final queued = <RtcCandidate>[];
      var offered = false;
      a.candidates = peer.onLocalCandidate.listen((c) {
        // None goes before the offer: the host couldn't place it.
        if (offered) {
          signaling.sendCandidate(a.host, connectionId: a.id, candidate: c);
        } else {
          queued.add(c);
        }
      });
      final pass = switch (a.seat) {
        final token? => {'pass': seatPass(token, signaling.id, a.id)},
        null => const <String, Object>{},
      };
      if (!await signaling.sendOffer(a.host, connectionId: a.id, sdp: sdp, extra: pass)) {
        a.fail(const SignalingUnavailable("couldn't send the offer"));
        return;
      }
      offered = true;
      for (final c in queued) {
        signaling.sendCandidate(a.host, connectionId: a.id, candidate: c);
      }
      final channel = await peer.channel;
      await channel.onOpen;
      final answer = a.answerSdp;
      a.succeed(
        ChannelSocket(peer, channel, clock: _clock, binding: answer == null ? null : connectionBinding(sdp, answer)),
      );
    } on Object catch (e) {
      a.fail(e);
    }
  }

  /// The name at the meeting service, taken now unless held already.
  Future<PeerSignaling> _openSignaling() {
    final current = _signaling;
    if (current != null && current.isOpen) return Future.value(current);
    return _opening ??= _takeName().whenComplete(() => _opening = null);
  }

  Future<PeerSignaling> _takeName() async {
    final old = _signaling;
    _signaling = null;
    unawaited(old?.close());
    for (var tries = 1; ; tries++) {
      final signaling = PeerSignaling(
        guestPeerId(_random),
        token: sessionToken(_random),
        broker: broker,
        connect: _connectSignaling,
        clock: _clock,
        random: _random,
        // Only needed for a moment: a dropped one is made again next time.
        reconnect: false,
      );
      try {
        await signaling.open();
        return _signaling = signaling;
      } on PeerIdTaken {
        await signaling.close();
        if (tries >= nameTries) rethrow;
      } on Object {
        await signaling.close();
        rethrow;
      }
    }
  }
}

/// One try to connect: to the host [host], as connection [id].
class _Attempt {
  _Attempt(this.host, this.id, {this.seat});

  final String host, id;

  /// The seat's token of a player coming back, for the pass; null for
  /// anyone else.
  final String? seat;

  /// The host's answer, once it came (its certificate goes into the
  /// connection's binding).
  String? answerSdp;
  final Completer<OnlineSocket> result = Completer();
  RtcPeer? peer;
  bool answered = false;
  StreamSubscription<SignalEvent>? signals;
  StreamSubscription<RtcState>? states;
  StreamSubscription<RtcCandidate>? candidates;

  bool get over => result.isCompleted;

  /// Whether the try ended with the connection handed over.
  bool succeeded = false;

  void succeed(OnlineSocket socket) {
    if (over) {
      // Too late: whoever asked has gone.
      unawaited(socket.close());
    } else {
      succeeded = true;
      result.complete(socket);
    }
  }

  void fail(Object error) {
    if (!over) result.completeError(error);
  }

  /// The try has ended: stops listening, and on failure closes the peer
  /// connection.
  void cleanUp() {
    unawaited(signals?.cancel());
    unawaited(states?.cancel());
    unawaited(candidates?.cancel());
    if (!succeeded) unawaited(peer?.close());
  }
}
