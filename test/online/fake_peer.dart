/// Stand-ins for the internet helpers of direct play, so tests run hosts and
/// guests in one process, on a clock the test moves: [FakeBroker] for the
/// public meeting service, [FakeRtc] for WebRTC itself.
library;

import 'dart:async';
import 'dart:convert';

import 'package:pokerfection/src/online/clock.dart';
import 'package:pokerfection/src/online/memory_link.dart';
import 'package:pokerfection/src/online/online_socket.dart';
import 'package:pokerfection/src/online/peer_config.dart';
import 'package:pokerfection/src/online/rtc.dart';

/// The public meeting service (0.peerjs.com), with the rules live tests
/// found it to have (October 2026):
/// - A connection names itself in its URL (`id` and `token`; without them
///   there is no WebSocket at all). The first message is OPEN; or, when
///   another token holds the name, ID-TAKEN and the connection is closed.
///   The same name with the same token takes it over: a fresh OPEN, and the
///   old connection is closed.
/// - Only OFFER, ANSWER and CANDIDATE shaped like the official client's are
///   passed on (with `src` set to the sender), and HEARTBEAT is taken.
///   Anything else, or more than [maxBytes], and the sender is closed.
/// - A message to a name nobody holds is dropped, and the sender gets EXPIRE
///   back at once, but at most once per [expireGap] for the same pair.
/// - A connection that sends nothing for [idleCut] is closed.
/// - A connection that closes gives its name back at once.
class FakeBroker {
  FakeBroker(this.clock);

  final Clock clock;

  static const maxBytes = 20000;
  static const idleCut = Duration(seconds: 99);
  static const expireGap = Duration(seconds: 3);

  /// Whether it can be reached at all (false: no network).
  bool reachable = true;

  /// Whether it answers new connections (false: they get no OPEN, as when
  /// the service is having one of its slow moments).
  bool answers = true;

  /// Who holds which name now.
  final Map<String, _Client> _names = {};

  /// When each connection was asked for (ms), and by which name.
  final List<({int at, String id})> connects = [];

  /// Why the service closed connections, in order (`<name>: <why>`).
  final List<String> closed = [];

  /// Everything taken from the connections (`<name>: <message>`).
  final List<String> received = [];

  /// Every EXPIRE sent (`<to> about <missing name>`).
  final List<String> expires = [];

  final Map<String, int> _expiredAt = {};

  /// Whether [id] is held now.
  bool holds(String id) => _names.containsKey(id);

  /// How many messages of [type] [id] has sent.
  int count(String id, String type) =>
      received.where((r) => r.startsWith('$id: ') && r.contains('"type":"$type"')).length;

  /// Opens a connection to the service, as a WebSocket to [url] would.
  Future<OnlineSocket> connect(String url) async {
    if (!reachable) throw StateError('No network');
    final query = Uri.parse(url).queryParameters;
    final id = query['id'] ?? '', token = query['token'] ?? '';
    if (id.isEmpty || token.isEmpty) throw StateError('HTTP 403 (error code: 1020)');
    connects.add((at: clock.nowMs, id: id));
    final (server, device) = MemoryLink.pair(address: id);
    final client = _Client(id, token, server);
    client.messages = server.messages.listen(
      (text) => _onText(client, text),
      // A dead connection's close never reaches the service: it holds the name until cut.
      onDone: () {
        if (!client.dead) _gone(client);
      },
    );
    if (answers) _register(client);
    return device;
  }

  /// Closes [id]'s connection (as the network dropping it would).
  void drop(String id) {
    final client = _names[id];
    if (client != null) _close(client, 'dropped');
  }

  /// [id]'s connection goes dead without either end hearing of it (a
  /// network that vanished): the service still holds the name, but nothing
  /// goes either way any more.
  void deafen(String id) => _names[id]?.dead = true;

  void _register(_Client client) {
    final holder = _names[client.id];
    if (holder != null && holder.token != client.token) {
      client.link.send(jsonEncode({'type': 'ID-TAKEN', 'payload': {'msg': 'ID is taken'}}));
      _close(client, 'ID-TAKEN');
      return;
    }
    if (holder != null) _close(holder, 'taken over');
    _names[client.id] = client;
    client.registered = true;
    client.link.send('{"type":"OPEN"}');
    _watchIdle(client);
  }

  void _watchIdle(_Client client) {
    client.idle?.cancel();
    client.idle = clock.schedule(idleCut, () => _close(client, 'idle'));
  }

  void _onText(_Client client, String text) {
    if (client.dead || client.link.isClosed) return;
    received.add('${client.id}: $text');
    if (!client.registered) return;
    _watchIdle(client);
    if (utf8.encode(text).length > maxBytes) return _close(client, 'too big (1009)');
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      return _close(client, 'not JSON');
    }
    if (json is! Map) return _close(client, 'not an object');
    final type = json['type'];
    if (type == 'HEARTBEAT') return;
    if (type != 'OFFER' && type != 'ANSWER' && type != 'CANDIDATE') return _close(client, 'type $type');
    final problem = _shapeProblem(type as String, json['payload']);
    if (problem != null) return _close(client, problem);
    final dst = json['dst'];
    if (dst is! String || dst.isEmpty) return;
    final target = _names[dst];
    if (target != null) {
      if (target.dead) return;
      target.link.send(jsonEncode({'dst': dst, 'payload': json['payload'], 'src': client.id, 'type': type}));
      return;
    }
    final pair = '${client.id} $dst', now = clock.nowMs;
    final last = _expiredAt[pair];
    if (last != null && now - last < expireGap.inMilliseconds) return;
    _expiredAt[pair] = now;
    expires.add('${client.id} about $dst');
    client.link.send(jsonEncode({'type': 'EXPIRE', 'src': dst, 'dst': client.id}));
  }

  /// What is wrong with the payload of a message of [type], or null.
  static String? _shapeProblem(String type, Object? payload) {
    if (payload is! Map) return 'no payload';
    if (payload['type'] != 'data' && payload['type'] != 'media') return 'payload type';
    final cid = payload['connectionId'];
    if (cid is! String || cid.isEmpty) return 'connectionId';
    switch (type) {
      case 'OFFER' || 'ANSWER':
        final sdp = payload['sdp'];
        if (sdp is! Map || sdp['type'] != type.toLowerCase()) return 'sdp type';
        if (!_isSdp(sdp['sdp'])) return 'sdp';
        if (type == 'OFFER' && payload['type'] == 'data') {
          if (payload['label'] is! String || payload['serialization'] is! String) return 'label or serialization';
        }
      case 'CANDIDATE':
        final candidate = payload['candidate'];
        if (candidate is! Map || candidate['candidate'] is! String) return 'candidate';
    }
    return null;
  }

  /// Whether [sdp] reads as SDP: lines like `v=0`, the first one `v=`.
  static bool _isSdp(Object? sdp) {
    if (sdp is! String || !sdp.startsWith('v=')) return false;
    return sdp.split(RegExp(r'\r?\n')).where((l) => l.isNotEmpty).every(RegExp(r'^[a-z]=').hasMatch);
  }

  void _close(_Client client, String why) {
    if (client.ended) return;
    client.ended = true;
    closed.add('${client.id}: $why');
    _gone(client);
    unawaited(client.link.close());
  }

  /// [client]'s connection has closed: its name is free at once.
  void _gone(_Client client) {
    client.idle?.cancel();
    if (identical(_names[client.id], client)) _names.remove(client.id);
  }
}

class _Client {
  _Client(this.id, this.token, this.link);

  final String id, token;
  final MemoryLink link;
  late final StreamSubscription<String> messages;
  bool registered = false;
  bool dead = false;
  bool ended = false;
  Timer? idle;
}

/// WebRTC in one process: each connection's data channel is a pair of
/// MemoryLinks. Hosts and guests share one FakeRtc (it is "the network"),
/// and an offer or answer names its peer connection, so the two ends find
/// each other.
///
/// A connection opens once both ends have the other's description and at
/// least one of its candidates, unless the test has made the network
/// [failIce] (the connection fails) or [stuck] (nothing ever happens).
class FakeRtc implements RtcFactory {
  /// Every peer connection made, in order.
  final List<FakeRtcPeer> peers = [];

  /// New connections find no way between the two ends: they fail.
  bool failIce = false;

  /// New connections never get anywhere: neither open nor failed.
  bool stuck = false;

  /// A channel closed at one end is not heard of at the other (as browsers
  /// never hear of it): only what was sent before arrives.
  bool quietCloses = false;

  @override
  RtcPeer create({List<IceServer> servers = iceServers}) {
    final peer = FakeRtcPeer._(this, peers.length + 1);
    peers.add(peer);
    return peer;
  }

  FakeRtcPeer? _described(String sdp) {
    final n = int.tryParse(RegExp(r'a=fake:(\d+)').firstMatch(sdp)?.group(1) ?? '');
    return n == null || n > peers.length ? null : peers[n - 1];
  }
}

/// One end of a fake connection.
class FakeRtcPeer implements RtcPeer {
  FakeRtcPeer._(this._net, this.serial);

  final FakeRtc _net;

  /// Which peer connection this is (1 for the first made).
  final int serial;

  FakeRtcPeer? _other;
  bool _described = false;
  final List<RtcCandidate> _early = [];

  /// The other end's candidates taken so far.
  final List<RtcCandidate> remoteCandidates = [];

  final StreamController<RtcCandidate> _local = StreamController();
  final StreamController<RtcState> _states = StreamController.broadcast();
  final Completer<RtcChannel> _channel = Completer();
  RtcState _state = RtcState.connecting;

  /// This end's data channel, once there is one.
  FakeRtcChannel? channelEnd;

  /// The other end, once both ends have each other's description.
  FakeRtcPeer? get other => _other;

  /// Its description, with a certificate fingerprint of its own (as every
  /// real one has: a seat proof is tied to the two).
  String get _sdp =>
      'v=0\r\no=- $serial 0 IN IP4 127.0.0.1\r\ns=-\r\na=fingerprint:sha-256 FA:CE:$serial\r\na=fake:$serial\r\n';

  @override
  Future<String> offer() async {
    channelEnd = FakeRtcChannel._(_net);
    _channel.complete(channelEnd);
    _gather();
    return _sdp;
  }

  @override
  Future<String> answer(String offerSdp) async {
    // An offer from no peer connection here (made up, or from another
    // network): answered, but nothing will ever connect.
    _other = _net._described(offerSdp);
    _setDescribed();
    _gather();
    return _sdp;
  }

  @override
  Future<void> acceptAnswer(String answerSdp) async {
    final other = _net._described(answerSdp);
    if (other == null) throw ArgumentError('No such answer');
    _other = other;
    _setDescribed();
  }

  @override
  void addRemoteCandidate(RtcCandidate candidate) {
    if (candidate.isEmpty || _state == RtcState.closed) return;
    if (!_described) {
      _early.add(candidate);
      return;
    }
    remoteCandidates.add(candidate);
    _check();
  }

  @override
  Stream<RtcCandidate> get onLocalCandidate => _local.stream;

  @override
  Stream<RtcState> get onState => _states.stream;

  @override
  RtcState get state => _state;

  @override
  Future<RtcChannel> get channel => _channel.future;

  @override
  Future<void> close() async {
    if (_state == RtcState.closed) return;
    _setState(RtcState.closed);
    await channelEnd?.close();
    unawaited(_local.close());
  }

  /// The data channel closes, at both ends.
  Future<void> dropChannel() async => channelEnd?.close();

  /// Nothing goes between the two ends any more, and neither hears of it
  /// (a network gone, no goodbye).
  void goSilent() {
    channelEnd?.silent = true;
    _other?.channelEnd?.silent = true;
  }

  /// This end's connection changes to [state] (disconnected, failed...).
  void becomes(RtcState state) => _setState(state);

  /// This end finds one more candidate for the other end, as a late answer
  /// from a STUN server brings.
  void gatherMore() => _gather();

  void _setDescribed() {
    _described = true;
    final early = [..._early];
    _early.clear();
    early.forEach(addRemoteCandidate);
    _check();
  }

  void _gather() {
    scheduleMicrotask(() {
      if (_state == RtcState.closed || _local.isClosed) return;
      _local.add(
        RtcCandidate(
          'candidate:$serial 1 udp 2122260223 10.0.0.${serial % 250 + 1} 50000 typ host',
          sdpMid: '0',
          sdpMLineIndex: 0,
        ),
      );
    });
  }

  /// Opens the connection once both ends have all they need.
  void _check() {
    final other = _other;
    if (other == null || !identical(other._other, this)) return;
    final ready = [this, other].every(
      (p) => p._described && p.remoteCandidates.isNotEmpty && p._state == RtcState.connecting,
    );
    if (!ready || _net.stuck) return;
    if (_net.failIce) {
      _setState(RtcState.failed);
      other._setState(RtcState.failed);
      return;
    }
    final offerer = channelEnd != null ? this : other, answerer = identical(offerer, this) ? other : this;
    final (a, b) = MemoryLink.pair(address: 'rtc', record: true);
    offerer.channelEnd!._attach(a);
    answerer.channelEnd = FakeRtcChannel._(_net).._attach(b);
    answerer._channel.complete(answerer.channelEnd);
    _setState(RtcState.connected);
    other._setState(RtcState.connected);
  }

  void _setState(RtcState state) {
    if (_state == state || _state == RtcState.closed) return;
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }
}

/// One end of a fake data channel: a MemoryLink once open.
class FakeRtcChannel implements RtcChannel {
  FakeRtcChannel._(this._net);

  final FakeRtc _net;

  MemoryLink? _link;
  final Completer<void> _opened = Completer(), _closed = Completer();
  final StreamController<String> _text = StreamController();

  /// Nothing goes either way (see [FakeRtcPeer.goSilent]).
  bool silent = false;

  /// Everything this end has sent (also the connection's own messages).
  List<String> get sent => _link?.sent ?? const [];

  void _attach(MemoryLink link) {
    _link = link;
    link.messages.listen(
      (text) {
        if (!silent && !_text.isClosed) _text.add(text);
      },
      onDone: _ended,
    );
    _opened.complete();
  }

  @override
  bool get isOpen => _link != null && !_closed.isCompleted;

  @override
  Future<void> get onOpen => _opened.future;

  @override
  Future<void> get onClosed => _closed.future;

  @override
  Stream<String> get onText => _text.stream;

  @override
  void send(String text) {
    if (!isOpen || silent) return;
    _link!.send(text);
  }

  @override
  Future<void> close() async {
    if (_closed.isCompleted) return;
    if (!_net.quietCloses) await _link?.close();
    _ended();
  }

  void _ended() {
    if (!_closed.isCompleted) _closed.complete();
    unawaited(_text.close());
  }
}
