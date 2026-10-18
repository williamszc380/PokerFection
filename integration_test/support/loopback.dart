/// Two ends of a direct connection inside one app, joined by passing the
/// offer, answer and candidates in memory instead of through the meeting
/// service. Shared by the app's test (rtc_loopback_test.dart) and the
/// browser's check (rtc_browser_check.dart), so it uses no test framework.
library;

import 'dart:async';

import 'package:pokerfection/src/online/rtc.dart';

/// A guest's end and a host's end, connected.
class LoopbackPair {
  LoopbackPair._(this.guest, this.host);

  final RtcPeer guest, host;
  late final RtcChannel guestChannel, hostChannel;
  late final Inbox guestInbox, hostInbox;
  late final String offerSdp, answerSdp;
  final List<RtcCandidate> guestCandidates = [], hostCandidates = [];

  /// From creating the two ends until both channels are open.
  late final int setupMs;

  /// Connects two new ends the way peer_socket.dart and peer_host.dart do,
  /// with the meeting service replaced by direct calls. With
  /// [candidatesFirst], the guest's candidates reach the host before its
  /// offer does.
  static Future<LoopbackPair> connect(RtcFactory rtc, {bool candidatesFirst = false}) async {
    final clock = Stopwatch()..start();
    final p = LoopbackPair._(rtc.create(), rtc.create());
    var answered = false;
    final early = <RtcCandidate>[];
    p.guest.onLocalCandidate.listen((c) {
      p.guestCandidates.add(c);
      p.host.addRemoteCandidate(c);
    });
    p.host.onLocalCandidate.listen((c) {
      p.hostCandidates.add(c);
      // None goes before the answer, as at the meeting service.
      answered ? p.guest.addRemoteCandidate(c) : early.add(c);
    });
    p.offerSdp = await p.guest.offer();
    if (candidatesFirst) {
      final waited = Stopwatch()..start();
      while (p.guestCandidates.isEmpty && waited.elapsed < const Duration(seconds: 5)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      if (p.guestCandidates.isEmpty) throw StateError('the guest found no candidate to send first');
    }
    p.answerSdp = await p.host.answer(p.offerSdp);
    await p.guest.acceptAnswer(p.answerSdp);
    answered = true;
    early.forEach(p.guest.addRemoteCandidate);
    const wait = Duration(seconds: 15);
    p.guestChannel = await p.guest.channel.timeout(wait);
    p.hostChannel = await p.host.channel.timeout(wait);
    p.guestInbox = Inbox(p.guestChannel);
    p.hostInbox = Inbox(p.hostChannel);
    await Future.wait([p.guestChannel.onOpen, p.hostChannel.onOpen]).timeout(wait);
    p.setupMs = clock.elapsedMilliseconds;
    // The peer connections may say "connected" a moment after the channels
    // open.
    final settled = Stopwatch()..start();
    while ((p.guest.state != RtcState.connected || p.host.state != RtcState.connected) &&
        settled.elapsed < const Duration(seconds: 5)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return p;
  }

  Future<void> close() async {
    await guest.close();
    await host.close();
  }
}

/// What one end's channel has received, in order.
class Inbox {
  Inbox(RtcChannel channel) {
    channel.onText.listen((text) {
      _got.add(text);
      final waiting = _waiting;
      if (waiting != null && !waiting.isCompleted) waiting.complete();
    });
  }

  final List<String> _got = [];
  Completer<void>? _waiting;

  /// The next [count] messages, once they have all come; a StateError after
  /// [within] if they haven't.
  Future<List<String>> take(int count, {Duration within = const Duration(seconds: 10)}) async {
    final deadline = Stopwatch()..start();
    while (_got.length < count) {
      final left = within - deadline.elapsed;
      if (left <= Duration.zero) throw StateError('only ${_got.length} of $count messages came');
      final waiting = _waiting = Completer();
      await waiting.future.timeout(left, onTimeout: () {});
    }
    final taken = _got.sublist(0, count);
    _got.removeRange(0, count);
    return taken;
  }
}

/// A JSON message of exactly [bytes] bytes in UTF-8, like a large game
/// message (a snapshot of the table).
String jsonOfSize(int bytes) {
  const head = '{"t":"snapshot","pad":"', tail = '"}';
  return '$head${'x' * (bytes - head.length - tail.length)}$tail';
}

/// Text with what a plain-English test would miss: card suits, emoji (two
/// UTF-16 units each, one with a skin tone), Japanese, accents.
const nonAsciiText = '♠♥♦♣ 🂡🃏 🙂👍🏽 日本 Ünïcödé';

/// The messages each check sends: a short one, the largest the game allows
/// (16 KB), and non-English text, bare and inside JSON.
List<String> sampleMessages(int maxMessage) =>
    ['{"t":"hello"}', jsonOfSize(maxMessage), nonAsciiText, '{"chat":"$nonAsciiText"}'];

/// A burst of [count] small messages, numbered, to check none is lost or
/// out of order.
List<String> burstMessages([int count = 500]) => [for (var i = 0; i < count; i++) '{"t":"n","i":$i}'];
