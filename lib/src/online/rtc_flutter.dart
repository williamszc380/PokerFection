/// Direct connections (WebRTC) through the flutter_webrtc plugin: Google's
/// own WebRTC in the apps (Windows, Android, iOS, macOS), and the browser's
/// RTCPeerConnection in the web version. The rest of the app sees only the
/// interfaces of rtc.dart.
///
/// Only a data channel of text is ever made: no camera, no microphone, no
/// audio or video in the offer.
library;

import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'peer_config.dart';
import 'rtc.dart';
import 'rtc_support_io.dart' if (dart.library.js_interop) 'rtc_support_web.dart';

/// This device's direct connections. Where there is no WebRTC (see
/// rtcMissing), it throws UnsupportedError: hosting then says the internet
/// isn't available, and joining by code goes on to the next way in.
RtcFactory platformRtc() {
  final missing = rtcMissing();
  if (missing != null) throw UnsupportedError('peer-to-peer is not available here ($missing)');
  return const FlutterRtc();
}

/// Makes peer connections with flutter_webrtc. Holds nothing itself: each
/// connection is its own.
class FlutterRtc implements RtcFactory {
  const FlutterRtc();

  /// Most servers the apps' WebRTC takes (on Windows and Linux it keeps them
  /// in a fixed table of 8, and more would overrun it).
  static const maxServerUrls = 8;

  @override
  RtcPeer create({List<IceServer> servers = iceServers}) => FlutterRtcPeer._(servers);

  /// What a peer connection is given: every server address on its own (the
  /// apps' WebRTC keeps only one address per entry), all kinds of routes
  /// allowed (a relay is used only when there is one: turnServers).
  static Map<String, dynamic> configuration(List<IceServer> servers) => {
    'iceServers': [
      for (final server in servers)
        for (final url in server.urls)
          {
            'urls': [url],
            if (server.username != null) 'username': server.username,
            if (server.credential != null) 'credential': server.credential,
          },
    ].take(maxServerUrls).toList(),
    'iceTransportPolicy': 'all',
    'sdpSemantics': 'unified-plan',
  };

  /// The offer and answer carry the data channel only. Without this,
  /// flutter_webrtc asks to receive audio and video, which would put those
  /// first in the offer (and the data channel's candidates would no longer
  /// be for its first part, as the meeting service is told: signaling.dart).
  static const dataOnly = <String, dynamic>{
    'mandatory': {'OfferToReceiveAudio': false, 'OfferToReceiveVideo': false},
    'optional': [],
  };

  /// The data channel's name. Only the two ends see it.
  static const channelLabel = 'pokerfection';
}

/// One end of a connection, over a flutter_webrtc RTCPeerConnection.
///
/// The plugin's peer connection is made in the background (it takes a
/// moment, and [FlutterRtc.create] must answer at once): everything else
/// waits for it. Its callbacks only pass things on to this end's streams,
/// and never throw.
class FlutterRtcPeer implements RtcPeer {
  FlutterRtcPeer._(List<IceServer> servers) {
    _pc = _open(servers);
  }

  late final Future<RTCPeerConnection?> _pc;
  final StreamController<RtcCandidate> _local = StreamController();
  final StreamController<RtcState> _states = StreamController.broadcast();
  final Completer<RtcChannel> _channel = Completer();
  FlutterRtcChannel? _channelEnd;
  RtcState _state = RtcState.connecting;

  /// The other end's candidates that came before its description: WebRTC
  /// refuses them until then.
  final List<RtcCandidate> _early = [];
  bool _described = false;
  Future<void>? _closing;

  bool get _closed => _closing != null;

  Future<RTCPeerConnection?> _open(List<IceServer> servers) async {
    try {
      final pc = await createPeerConnection(FlutterRtc.configuration(servers));
      if (_closed) {
        // Closed while it was being made: nobody will use it.
        unawaited(_release(pc));
        return null;
      }
      pc.onIceCandidate = (c) => _guard(() => _onLocalCandidate(c));
      pc.onConnectionState = (s) => _guard(() => _onConnectionState(s));
      pc.onIceConnectionState = (s) => _guard(() => _onIceState(s));
      pc.onDataChannel = (dc) => _guard(() => _onDataChannel(dc));
      return pc;
    } on Object {
      // No WebRTC here (or it broke): the connection can't be made.
      _setState(RtcState.failed);
      return null;
    }
  }

  /// The plugin's peer connection, for a step of setting up.
  Future<RTCPeerConnection> _ready() async {
    final pc = await _pc;
    if (pc == null || _closed) throw StateError('The peer connection is closed');
    return pc;
  }

  @override
  Future<String> offer() => _step(() async {
    final pc = await _ready();
    final dc = await pc.createDataChannel(
      FlutterRtc.channelLabel,
      RTCDataChannelInit()
        ..ordered = true
        ..binaryType = 'text',
    );
    _setChannel(FlutterRtcChannel._(dc));
    final offer = await pc.createOffer(FlutterRtc.dataOnly);
    await pc.setLocalDescription(offer);
    return offer.sdp!;
  });

  @override
  Future<String> answer(String offerSdp) => _step(() async {
    final pc = await _ready();
    await pc.setRemoteDescription(RTCSessionDescription(offerSdp, 'offer'));
    _setDescribed(pc);
    final answer = await pc.createAnswer(FlutterRtc.dataOnly);
    await pc.setLocalDescription(answer);
    return answer.sdp!;
  });

  @override
  Future<void> acceptAnswer(String answerSdp) => _step(() async {
    final pc = await _ready();
    await pc.setRemoteDescription(RTCSessionDescription(answerSdp, 'answer'));
    _setDescribed(pc);
  });

  @override
  void addRemoteCandidate(RtcCandidate candidate) {
    if (candidate.isEmpty || _closed) return;
    if (!_described) {
      _early.add(candidate);
      return;
    }
    unawaited(_addCandidate(candidate));
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
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _setState(RtcState.closed);
    _early.clear();
    await _channelEnd?.close();
    final pc = await _pc;
    if (pc != null) await _release(pc);
    unawaited(_local.close());
    unawaited(_states.close());
  }

  /// Ends [pc] and frees what the plugin holds for it (its channels too).
  static Future<void> _release(RTCPeerConnection pc) async {
    try {
      await pc.close();
    } on Object {
      // Already gone on the plugin's side: nothing more to free there.
    }
    try {
      await pc.dispose();
    } on Object {
      // As above.
    }
  }

  /// Runs a step of setting up; its failure reaches the caller as a
  /// StateError (the plugin throws plain strings).
  Future<T> _step<T>(Future<T> Function() step) async {
    try {
      return await step();
    } on StateError {
      rethrow;
    } on Object catch (e) {
      throw StateError('WebRTC: $e');
    }
  }

  /// The other end's description is set: the candidates that waited go in.
  void _setDescribed(RTCPeerConnection pc) {
    _described = true;
    final early = [..._early];
    _early.clear();
    for (final c in early) {
      unawaited(_addCandidate(c));
    }
  }

  Future<void> _addCandidate(RtcCandidate c) async {
    try {
      final pc = await _ready();
      // The plugin, like browsers, needs to know which part of the offer
      // it is for: the data channel's, the only one.
      await pc.addCandidate(RTCIceCandidate(c.candidate, c.sdpMid ?? '0', c.sdpMLineIndex ?? 0));
    } on Object {
      // A candidate WebRTC can't use (or the connection closed meanwhile):
      // the others may still do.
    }
  }

  void _onLocalCandidate(RTCIceCandidate c) {
    final line = c.candidate;
    // An empty one says there are no more: the other end doesn't need it.
    if (line == null || line.trim().isEmpty || _closed || _local.isClosed) return;
    _local.add(RtcCandidate(line, sdpMid: c.sdpMid, sdpMLineIndex: c.sdpMLineIndex));
  }

  void _onConnectionState(RTCPeerConnectionState s) {
    switch (s) {
      case RTCPeerConnectionState.RTCPeerConnectionStateNew || RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        _setState(RtcState.connecting);
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _setState(RtcState.connected);
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        _setState(RtcState.disconnected);
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        _setState(RtcState.failed);
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        _setState(RtcState.closed);
    }
  }

  /// The ICE state too, for where the connection's own state comes late or
  /// not at all (some browsers): a failed search for a route is a failure.
  void _onIceState(RTCIceConnectionState s) {
    if (s == RTCIceConnectionState.RTCIceConnectionStateFailed) _setState(RtcState.failed);
  }

  void _onDataChannel(RTCDataChannel dc) {
    // Only the guest makes a channel; another one isn't ours.
    if (_channel.isCompleted || _closed) {
      unawaited(dc.close().catchError((_) {}));
      return;
    }
    _setChannel(FlutterRtcChannel._(dc));
  }

  void _setChannel(FlutterRtcChannel channel) {
    _channelEnd = channel;
    if (!_channel.isCompleted) _channel.complete(channel);
  }

  void _setState(RtcState state) {
    if (_state == state || _state == RtcState.closed) return;
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }
}

/// The data channel of a [FlutterRtcPeer]: text only. What arrives is kept
/// from the start, since the plugin passes messages on only to whoever
/// listens at that moment.
class FlutterRtcChannel implements RtcChannel {
  FlutterRtcChannel._(this._dc) {
    _messages = _dc.messageStream.listen(
      (m) => _guard(() {
        // The game speaks only text; binary is no message of ours.
        if (!m.isBinary && !_text.isClosed) _text.add(m.text);
      }),
      onError: (Object _) {},
    );
    _states = _dc.stateChangeStream.listen((s) => _guard(() => _onState(s)), onError: (Object _) {});
    // The host's channel is open when it arrives.
    final initial = _dc.state;
    if (initial != null) _onState(initial);
  }

  final RTCDataChannel _dc;
  late final StreamSubscription<RTCDataChannelMessage> _messages;
  late final StreamSubscription<RTCDataChannelState> _states;
  final Completer<void> _opened = Completer(), _closed = Completer();
  final StreamController<String> _text = StreamController();
  Future<void>? _closing;

  /// Longest [close] waits for what was sent to go: a peer connection
  /// closed right after would otherwise drop it (and a "bye" with it).
  static const drainWait = Duration(seconds: 1);

  @override
  bool get isOpen => _opened.isCompleted && !_closed.isCompleted && _closing == null;

  @override
  Future<void> get onOpen => _opened.future;

  @override
  Future<void> get onClosed => _closed.future;

  @override
  Stream<String> get onText => _text.stream;

  @override
  void send(String text) {
    if (!isOpen) return;
    try {
      // Sends go to the plugin in order, and arrive in order.
      unawaited(_dc.send(RTCDataChannelMessage(text)).catchError((Object _) {}));
    } on Object {
      // Closing meanwhile: like any send after the close, it doesn't go.
    }
  }

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    if (_opened.isCompleted && !_closed.isCompleted) await _drain();
    try {
      await _dc.close();
    } on Object {
      // Already closed on the plugin's side.
    }
    _ended();
  }

  /// Waits until what was sent has left (or [drainWait] has passed).
  Future<void> _drain() async {
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < drainWait && !_closed.isCompleted) {
      try {
        if (await _dc.getBufferedAmount() <= 0) return;
      } on Object {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  void _onState(RTCDataChannelState s) {
    switch (s) {
      case RTCDataChannelState.RTCDataChannelOpen:
        if (!_opened.isCompleted && !_closed.isCompleted) _opened.complete();
      case RTCDataChannelState.RTCDataChannelClosing || RTCDataChannelState.RTCDataChannelClosed:
        _ended();
      case RTCDataChannelState.RTCDataChannelConnecting:
        break;
    }
  }

  void _ended() {
    if (_closed.isCompleted) return;
    _closed.complete();
    unawaited(_text.close());
    unawaited(_messages.cancel());
    unawaited(_states.cancel());
  }
}

/// Runs a plugin callback's work; nothing it throws may escape into the
/// plugin (which would report it as an unhandled error).
void _guard(void Function() work) {
  try {
    work();
  } on Object {
    // A callback after the end, on closed streams: nothing to tell.
  }
}
