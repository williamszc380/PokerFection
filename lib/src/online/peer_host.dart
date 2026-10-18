import 'dart:async';
import 'dart:math';

import '../server/client_link.dart';
import '../server/room_registry.dart';
import 'channel_link.dart';
import 'clock.dart';
import 'peer_config.dart';
import 'peer_status.dart';
import 'rtc.dart';
import 'seat_proof.dart';
import 'signaling.dart';

export 'peer_status.dart';

/// Lets guests anywhere reach a room on this device, with no server of our
/// own: the room's code is its name at the meeting service (see
/// peer_config.dart), each guest's app offers a direct connection there,
/// and this answers.
///
/// [start] picks the room's code and takes its name (another code if the
/// name is someone else's); the room then gets that code (RoomRegistry's
/// nextCode: `() => peerHost.code`). Each offer gets a new peer connection;
/// once its data channel opens, it goes to [accept] as a ChannelLink, at
/// the address `peer:<the guest's name>`, and plays like any other
/// connection.
///
/// The meeting service authenticates nobody, so anyone can send offers:
/// each guest may have [pendingPerGuest] connections being set up at once,
/// all guests together [offersPerMinute] a minute, each connection
/// [candidatesPerConnection] candidates (each one makes WebRTC send checks
/// to the address in it, whoever's it is), and a connection not open after
/// [openWait] is closed. Who may sit where is still up to the room,
/// over the game's own protocol.
///
/// Someone who knows the code could use up that budget with made-up
/// offers. A player coming back to their seat shows a pass with their
/// offer (seatPass, made with their seat's token, which only the room and
/// they know): such offers have a budget of their own
/// ([seatOffersPerMinute]), so nobody can keep a seated player out.
class PeerHost {
  /// [rtc] makes the peer connections (this platform's when not given),
  /// [connectSignaling] opens the WebSocket to the meeting service
  /// (connectSocket when not given); tests give fakes of both, and a [clock].
  PeerHost({
    required this.accept,
    this._rtc,
    this._connectSignaling,
    this.broker = peerBroker,
    Clock? clock,
    Random? random,
    this._pickCode,
    this._seatTokens,
  }) : _clock = clock ?? SystemClock(),
       _random = random ?? Random.secure();

  /// Takes each guest's connection once it is open (RoomRegistry.accept).
  final void Function(ClientLink link) accept;

  /// The meeting service's address.
  final String broker;

  RtcFactory? _rtc;
  final SocketConnector? _connectSignaling;
  final Clock _clock;
  final Random _random;

  /// Picks the codes to try (tests); else they are random, as the server
  /// makes them.
  final String Function()? _pickCode;

  String _newCode() => _pickCode?.call() ?? RoomRegistry.randomCode(_random);

  /// The tokens of everyone with a seat now (RoomRegistry.seatTokens), to
  /// check the passes of players coming back; none when not given.
  final Iterable<String> Function()? _seatTokens;

  /// How many codes to try when their names are someone else's.
  static const codeTries = 5;

  /// How long [start] waits for the meeting service before it lets the room
  /// open anyway (it keeps trying, with that code, in the background).
  static const startWait = Duration(seconds: 3);

  /// Limits on offers (see the class comment).
  static const pendingPerGuest = 4;
  static const offersPerMinute = 30;

  /// Offers a minute from players coming back to their seats (with a pass):
  /// counted apart from everyone else's.
  static const seatOffersPerMinute = 30;
  static const openWait = Duration(seconds: 20);

  /// Most candidates a guest may send for one connection; one that sends
  /// more is given up. A real device sends a few per network it is on (a
  /// dozen or two at most, on a computer with many network adapters).
  static const candidatesPerConnection = 50;

  /// The room's code, once [start] has picked it.
  String? get code => _code;
  String? _code;

  /// The secret that goes with the room's name, for this session.
  late final String _token = sessionToken(_random);

  PeerStatus get status => _status;
  PeerStatus _status = PeerStatus.starting;
  final StreamController<PeerStatus> _statuses = StreamController.broadcast();

  /// [status] each time it changes.
  Stream<PeerStatus> get statuses => _statuses.stream;

  PeerSignaling? _signaling;
  StreamSubscription<SignalEvent>? _signals;

  bool _stopped = false;

  final Map<String, _Negotiation> _pending = {};
  final List<int> _offerTimes = [], _seatOfferTimes = [];

  /// Connections being set up now.
  int get pendingCount => _pending.length;

  /// Picks the room's code and takes its name at the meeting service.
  /// Completes with the code once that is done, or failed (see [status]),
  /// or after [startWait] at most (still [PeerPhase.starting]).
  Future<String> start() async {
    try {
      _rtc ??= platformRtc();
    } on UnsupportedError {
      _setStatus(const PeerStatus.unavailable(PeerTrouble.unsupported));
      return _fix(_newCode());
    }
    for (var tries = 1; ; tries++) {
      final code = _code = _newCode();
      final signaling = _signaling = PeerSignaling(
        hostPeerId(code),
        token: _token,
        broker: broker,
        connect: _connectSignaling,
        clock: _clock,
        random: _random,
        watch: true,
        // The room has this code: a name someone took while this device was reconnecting is taken back once free.
        retake: true,
      );
      _signals = signaling.events.listen(_onSignal);
      final opening = signaling.open();
      try {
        if (!await _within(opening, startWait)) {
          // Slow (the service sometimes is): the room opens anyway, and the
          // name may still come.
          unawaited(opening.then((_) {}, onError: _lateFailure));
        }
        return _fix(code);
      } on PeerIdTaken {
        unawaited(_signals?.cancel());
        await signaling.close();
        if (tries >= codeTries) {
          _setStatus(const PeerStatus.unavailable(PeerTrouble.codeTaken));
          return _fix(code);
        }
      } on SignalingUnavailable {
        _setStatus(const PeerStatus.unavailable(PeerTrouble.unreachable));
        signaling.keepTrying();
        return _fix(code);
      }
    }
  }

  /// Checks the connection to the meeting service now (the app is back on
  /// screen: it may have died meanwhile), and makes it again if needed.
  void checkSignaling() => _signaling?.probe();

  /// Lets no more guests in: gives the room's name back, and drops the
  /// connections still being set up (open ones belong to the room).
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    for (final n in [..._pending.values]) {
      _drop(n);
    }
    unawaited(_signals?.cancel());
    await _signaling?.close();
    unawaited(_statuses.close());
  }

  String _fix(String code) {
    _code = code;
    return code;
  }

  /// Whether [future] completes within [wait] (throwing if it fails).
  Future<bool> _within(Future<void> future, Duration wait) {
    final done = Completer<bool>();
    final timer = _clock.schedule(wait, () {
      if (!done.isCompleted) done.complete(false);
    });
    future.then(
      (_) {
        timer.cancel();
        if (!done.isCompleted) done.complete(true);
      },
      onError: (Object e, StackTrace s) {
        timer.cancel();
        if (!done.isCompleted) done.completeError(e, s);
      },
    );
    return done.future;
  }

  /// The first try to take the name failed after [start] had given up
  /// waiting: the code is the room's now, whatever happens, so the name is
  /// tried for again (someone else's may be given up).
  void _lateFailure(Object error) {
    if (_stopped) return;
    _setStatus(
      PeerStatus.unavailable(error is PeerIdTaken ? PeerTrouble.codeTaken : PeerTrouble.unreachable),
    );
    _signaling?.keepTrying();
  }

  void _onSignal(SignalEvent event) {
    if (_stopped) return;
    switch (event) {
      case SignalOpen():
        _setStatus(PeerStatus.ready);
      case SignalClosed():
        _setStatus(PeerStatus.starting);
      case SignalRetrying():
        _setStatus(const PeerStatus.unavailable(PeerTrouble.unreachable));
      case SignalIdTaken():
        _setStatus(const PeerStatus.unavailable(PeerTrouble.codeTaken));
      case SignalOffer():
        _onOffer(event);
      case SignalCandidate(:final from, :final connectionId, :final candidate):
        final n = _pending[_key(from, connectionId)];
        if (n == null) return;
        if (++n.remoteCandidates > candidatesPerConnection) {
          _drop(n);
        } else {
          n.peer.addRemoteCandidate(candidate);
        }
      case SignalExpire(:final peer):
        // The guest has gone from the service: its connections still waiting
        // for the answer can't be finished. Those answered already may still
        // open with the candidates passed on (the guest's connection to the
        // service may only have dropped); [openWait] decides for them.
        for (final n in [..._pending.values]) {
          if (n.guest == peer && !n.answered) _drop(n);
        }
      case SignalAnswer():
        break;
    }
  }

  void _onOffer(SignalOffer offer) {
    final metadata = offer.metadata;
    if (metadata is! Map || metadata['app'] != PeerSignaling.offerMetadata['app']) return;
    final key = _key(offer.from, offer.connectionId);
    if (_pending.containsKey(key)) return;
    final seated = _hasSeat(metadata['pass'], offer.from, offer.connectionId);
    final times = seated ? _seatOfferTimes : _offerTimes;
    final now = _clock.nowMs;
    times.removeWhere((t) => now - t >= const Duration(minutes: 1).inMilliseconds);
    if (times.length >= (seated ? seatOffersPerMinute : offersPerMinute)) return;
    if (_pending.values.where((n) => n.guest == offer.from).length >= pendingPerGuest) return;
    times.add(now);
    final n = _pending[key] = _Negotiation(offer.from, offer.connectionId, _rtc!.create());
    n.deadline = _clock.schedule(openWait, () => _drop(n));
    unawaited(_answer(n, offer.sdp));
  }

  /// Whether [pass] (from an offer's metadata) is a seated player's for
  /// this offer (see seatPass).
  bool _hasSeat(Object? pass, String guest, String connectionId) {
    if (pass is! String || pass.length > 64) return false;
    final tokens = _seatTokens?.call() ?? const <String>[];
    return tokens.any((token) => sameProof(seatPass(token, guest, connectionId), pass));
  }

  /// Answers [n]'s offer, passes candidates on both ways, and hands the
  /// channel to the room once it opens.
  Future<void> _answer(_Negotiation n, String offerSdp) async {
    final queued = <RtcCandidate>[];
    var answered = false;
    n.candidates = n.peer.onLocalCandidate.listen((c) {
      // None goes before the answer: the guest couldn't place it.
      if (answered) {
        _signaling?.sendCandidate(n.guest, connectionId: n.id, candidate: c);
      } else {
        queued.add(c);
      }
    });
    n.states = n.peer.onState.listen((state) {
      if (state == RtcState.failed || state == RtcState.closed) _drop(n);
    });
    try {
      final answer = await n.peer.answer(offerSdp);
      if (n.done) return;
      n.answered = _signaling?.sendAnswer(n.guest, connectionId: n.id, sdp: answer) ?? false;
      answered = true;
      for (final c in queued) {
        _signaling?.sendCandidate(n.guest, connectionId: n.id, candidate: c);
      }
      queued.clear();
      final channel = await n.peer.channel;
      await channel.onOpen;
      if (n.done) return;
      final link = ChannelLink(
        n.peer,
        channel,
        address: 'peer:${n.guest}',
        clock: _clock,
        binding: connectionBinding(offerSdp, answer),
      );
      _finish(n);
      try {
        accept(link);
      } on Object {
        // The room couldn't take it: closed at both ends (the guest hears
        // bye), not left open to nobody.
        unawaited(link.close());
      }
    } on Object {
      _drop(n);
    }
  }

  /// [n] is set up: no longer pending (the connection is the room's now).
  void _finish(_Negotiation n) {
    n.done = true;
    _pending.remove(_key(n.guest, n.id));
    n.deadline?.cancel();
    unawaited(n.candidates?.cancel());
    unawaited(n.states?.cancel());
  }

  /// Gives up on [n]: it failed, or took too long.
  void _drop(_Negotiation n) {
    if (n.done) return;
    _finish(n);
    unawaited(n.peer.close());
  }

  void _setStatus(PeerStatus status) {
    if (status == _status || _statuses.isClosed) return;
    _status = status;
    _statuses.add(status);
  }

  static String _key(String guest, String connectionId) => '$guest $connectionId';
}

/// One guest's connection being set up ([id]: its connection id).
class _Negotiation {
  _Negotiation(this.guest, this.id, this.peer);

  final String guest, id;
  final RtcPeer peer;
  bool done = false;

  /// Whether the answer went to the meeting service.
  bool answered = false;

  /// How many candidates the guest has sent for it.
  int remoteCandidates = 0;

  Timer? deadline;
  StreamSubscription<RtcCandidate>? candidates;
  StreamSubscription<RtcState>? states;
}
