import 'dart:async';
import 'dart:convert';

import 'clock.dart';
import 'online_socket.dart';
import 'rtc.dart';
import 'seat_proof.dart';

/// A connection to the game over a direct connection's data channel, as a
/// guest's app sees it (and, as ChannelLink, as the host's room sees it):
/// text messages both ways, like a WebSocket.
///
/// A data channel can't be trusted to say when it ends: a browser never
/// hears that the other end closed it, and a device that loses its network
/// just goes quiet. So both ends keep the connection in their own words,
/// small messages the game never sees:
/// - each end says it is there every [pingEvery]; a connection silent for
///   [silence] has ended;
/// - an end that leaves says bye first ([close]), and the other end ends
///   the connection at once;
/// - it ends too when the channel closes, when the peer connection fails,
///   or when it is disconnected for [disconnectedWait] (it may come back by
///   itself sooner).
///
/// Those messages look like the game's (`{"t":"_rtc","op":"ping"}`), but no
/// game message's type starts with `_`, so they can't be mistaken.
class ChannelSocket implements OnlineSocket, BoundConnection {
  ChannelSocket(this.peer, this.channel, {Clock? clock, this.maxIncoming, this.binding})
    : _clock = clock ?? SystemClock() {
    _lastHeard = _clock.nowMs;
    // First, so a peer connection that can't be watched (its onState must
    // be a broadcast stream: whoever set the connection up may still be
    // listening) fails here, before anything else waits on the channel.
    _stateWatch = peer.onState.listen(_onState);
    channel.onText.listen(_onText, onDone: _end);
    unawaited(channel.onClosed.then((_) => _end()));
    _onState(peer.state);
    _schedulePing();
  }

  /// The peer connection, and its data channel (open).
  final RtcPeer peer;
  final RtcChannel channel;

  /// Longest message taken from the other end; a longer one ends the
  /// connection. Null: any (a guest takes whatever the host sends).
  final int? maxIncoming;

  /// Both ends' certificates, as the offer and answer named them
  /// (connectionBinding): a player coming back proves their seat for this
  /// connection only. Null when they weren't known.
  @override
  final String? binding;

  final Clock _clock;

  /// How often each end says it is there, and how long a connection may be
  /// silent before it has ended.
  static const pingEvery = Duration(seconds: 2);
  static const silence = Duration(seconds: 6);

  /// How long a disconnected peer connection is given to come back.
  static const disconnectedWait = Duration(seconds: 5);

  /// The connection's own messages: "still here", and "leaving".
  static const pingFrame = '{"t":"_rtc","op":"ping"}';
  static const byeFrame = '{"t":"_rtc","op":"bye"}';

  final StreamController<String> _incoming = StreamController();
  StreamSubscription<RtcState>? _stateWatch;
  late int _lastHeard;
  Timer? _ping, _disconnected;
  bool _ended = false;

  /// Whether the connection has ended.
  bool get isClosed => _ended;

  @override
  Stream<String> get messages => _incoming.stream;

  @override
  void send(String message) {
    if (_ended) return;
    channel.send(message);
  }

  /// Leaves: says bye (so the other end needn't wait for the silence), then
  /// closes the channel and the peer connection.
  @override
  Future<void> close() async {
    if (_ended) return;
    channel.send(byeFrame);
    await _end();
  }

  void _onText(String text) {
    if (_ended) return;
    _lastHeard = _clock.nowMs;
    if (maxIncoming case final max? when text.length > max) {
      unawaited(_end());
      return;
    }
    if (_isOwnFrame(text)) {
      // Only the bye needs doing: any message says the other end is there.
      if (text.contains('"bye"')) unawaited(_end());
      return;
    }
    _incoming.add(text);
  }

  /// Whether [text] is one of the connection's own messages, not the game's.
  static bool _isOwnFrame(String text) {
    if (text.length > 64 || !text.startsWith('{"t":"_')) return false;
    try {
      final json = jsonDecode(text);
      return json is Map && json['t'] == '_rtc';
    } on FormatException {
      return false;
    }
  }

  void _onState(RtcState state) {
    switch (state) {
      case RtcState.disconnected:
        _disconnected ??= _clock.schedule(disconnectedWait, () => unawaited(_end()));
      case RtcState.failed || RtcState.closed:
        unawaited(_end());
      case RtcState.connected || RtcState.connecting:
        _disconnected?.cancel();
        _disconnected = null;
    }
  }

  void _schedulePing() {
    _ping = _clock.schedule(pingEvery, () {
      if (_ended) return;
      if (_clock.nowMs - _lastHeard >= silence.inMilliseconds) {
        unawaited(_end());
        return;
      }
      channel.send(pingFrame);
      _schedulePing();
    });
  }

  /// The connection has ended: the game hears so, and the channel and peer
  /// connection close.
  Future<void> _end() async {
    if (_ended) return;
    _ended = true;
    _ping?.cancel();
    _disconnected?.cancel();
    unawaited(_stateWatch?.cancel());
    // Completes only once someone has read to the end: don't wait.
    unawaited(_incoming.close());
    await channel.close();
    await peer.close();
  }
}
