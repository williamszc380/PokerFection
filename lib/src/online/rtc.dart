/// A direct connection between two devices (WebRTC), as the rest of the app
/// sees it: a peer connection that carries one data channel of text
/// messages. The real one (rtc_flutter.dart: the flutter_webrtc plugin, in
/// the apps and in browsers) sits behind these few interfaces, so the
/// hosting and joining code is the same everywhere and runs in tests on a
/// fake.
///
/// Setting a connection up takes three kinds of messages, passed on by the
/// meeting service (signaling.dart): the guest's offer ([RtcPeer.offer]),
/// the host's answer ([RtcPeer.answer]), and both ends' candidates
/// ([RtcCandidate]): the addresses each end might be reached at, sent as
/// they are found.
library;

import 'dart:async';

import 'peer_config.dart';

// Flutter's (dart:ui) in the apps and the web version; none where Flutter
// isn't (a tool run with plain Dart, such as tool/host_check.dart).
export 'rtc_none.dart' if (dart.library.ui) 'rtc_flutter.dart';

/// Makes peer connections. One per device, for all its connections (it may
/// share things between them, such as the certificate that proves who this
/// end is).
abstract interface class RtcFactory {
  /// A new peer connection, using [servers] to find its way out.
  RtcPeer create({List<IceServer> servers = iceServers});
}

/// How a peer connection is doing.
enum RtcState {
  /// Being set up: the two ends look for a way to reach each other.
  connecting,

  /// The two ends reach each other.
  connected,

  /// The way between them stopped working, maybe for a moment (it may come
  /// back by itself: see ChannelLink for how long it is given).
  disconnected,

  /// No way between the two ends was found, or it broke for good.
  failed,

  /// Closed by this end.
  closed,
}

/// One end of a connection to another device.
///
/// The guest's end calls [offer], sends it, and gives the host's answer to
/// [acceptAnswer]; the host's end turns the offer into an answer with
/// [answer]. Both send every [onLocalCandidate] to the other end and give
/// the other end's to [addRemoteCandidate]. The data channel is then
/// [channel], once it opens.
abstract interface class RtcPeer {
  /// The guest's end: creates the data channel (ordered and reliable) and
  /// the offer that describes it; completes with the offer's SDP. The
  /// candidates follow on [onLocalCandidate].
  Future<String> offer();

  /// The host's end: takes the guest's offer ([offerSdp]) and completes with
  /// the answer's SDP. The data channel the guest made comes on [channel].
  Future<String> answer(String offerSdp);

  /// The guest's end: takes the host's answer.
  Future<void> acceptAnswer(String answerSdp);

  /// A candidate from the other end. It may come before the offer or answer
  /// is taken: then it waits. Empty ones (the other end found no more) are
  /// skipped.
  void addRemoteCandidate(RtcCandidate candidate);

  /// This end's candidates, as they are found, for the other end (with the
  /// sdpMid and sdpMLineIndex WebRTC gave them; never an empty one). Kept
  /// until someone listens (once).
  Stream<RtcCandidate> get onLocalCandidate;

  /// [state] each time it changes, from the moment someone listens (not
  /// kept before). A broadcast stream: the code that sets a connection up
  /// watches it, and the connection's ChannelSocket watches it too.
  Stream<RtcState> get onState;

  /// How the connection is doing now.
  RtcState get state;

  /// The data channel: the guest's as soon as [offer] made it, the host's
  /// once the guest's arrives. It may not be open yet ([RtcChannel.onOpen]).
  Future<RtcChannel> get channel;

  /// Ends the connection (and its channel). Safe to call more than once.
  Future<void> close();
}

/// The data channel of a peer connection: text messages, both ways, in
/// order, none lost.
abstract interface class RtcChannel {
  /// Whether it is open: messages sent now go.
  bool get isOpen;

  /// Completes when the channel opens (at once if it is open).
  Future<void> get onOpen;

  /// Completes when the channel has closed, from either end. The other end
  /// may never hear of a close (browsers often don't): ChannelLink says bye
  /// in its own words first.
  Future<void> get onClosed;

  /// The other end's messages, in order. Kept until someone listens (once);
  /// done when the channel closes.
  Stream<String> get onText;

  /// Sends [text]; does nothing unless open.
  void send(String text);

  /// Closes the channel, after what was sent before has gone.
  Future<void> close();
}

/// One address the other end might reach this one at, as WebRTC describes
/// it (`candidate:... typ host`), and which part of the offer it is for.
class RtcCandidate {
  const RtcCandidate(this.candidate, {this.sdpMid, this.sdpMLineIndex});

  /// The `candidate:` line; empty for "no more candidates".
  final String candidate;

  /// Which media section of the offer it belongs to: the data channel's
  /// (`'0'` and 0, the only one this app makes). Some ends leave them out;
  /// browsers refuse a candidate without them, so the meeting service is
  /// always sent both (see signaling.dart).
  final String? sdpMid;
  final int? sdpMLineIndex;

  bool get isEmpty => candidate.trim().isEmpty;

  @override
  bool operator ==(Object other) =>
      other is RtcCandidate &&
      other.candidate == candidate &&
      other.sdpMid == sdpMid &&
      other.sdpMLineIndex == sdpMLineIndex;

  @override
  int get hashCode => Object.hash(candidate, sdpMid, sdpMLineIndex);

  @override
  String toString() => 'RtcCandidate($candidate)';
}

/// No direct way between the two devices was found, though the other end
/// answered: their networks won't let them reach each other (and there is
/// no relay, see turnServers).
class NoDirectRoute implements Exception {
  const NoDirectRoute();

  @override
  String toString() => 'NoDirectRoute';
}
