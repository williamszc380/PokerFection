// The loopback test's checks, in a browser: two direct connections inside
// one page, through the web version's WebRTC (flutter_webrtc on the
// browser's RTCPeerConnection), built the way the website is built.
// `flutter test --platform chrome` can't run it on this machine (its test
// host never loads), so it is a page of its own:
//
//   flutter build web --wasm -t integration_test/rtc_browser_check.dart -o <folder>
//   (or without --wasm for the JavaScript version)
//
// then open the folder's index.html over http. When it is done the page's
// title becomes "RTC PASS" or "RTC FAIL", and the page shows the details
// (also printed to the console) as JSON.
import 'dart:convert';
import 'dart:js_interop';

import 'package:pokerfection/src/online/channel_link.dart';
import 'package:pokerfection/src/online/rtc.dart';
import 'package:web/web.dart' as web;

import 'support/loopback.dart';

Future<void> main() async {
  final report = <String, Object?>{'wasm': const bool.fromEnvironment('dart.tool.dart2wasm')};
  final failures = <String>[];
  void check(bool ok, String what) {
    if (!ok) failures.add(what);
  }

  try {
    final rtc = platformRtc();
    final setups = <int>[];
    Future<LoopbackPair> connect({bool candidatesFirst = false}) async {
      final p = await LoopbackPair.connect(rtc, candidatesFirst: candidatesFirst);
      setups.add(p.setupMs);
      return p;
    }

    // Connects, with only a data channel in the offer.
    var p = await connect();
    check(RegExp(r'^m=', multiLine: true).allMatches(p.offerSdp).length == 1, 'one part in the offer');
    check(p.offerSdp.contains('m=application'), 'a data channel in the offer');
    check(
      [...p.guestCandidates, ...p.hostCandidates].every((c) => c.sdpMid == '0' && c.sdpMLineIndex == 0),
      "every candidate is for part '0'",
    );
    report['candidates'] = {'guest': p.guestCandidates.length, 'host': p.hostCandidates.length};

    // Text both ways, whole.
    final messages = sampleMessages(ChannelLink.maxMessage);
    for (final (from, to, name) in [
      (p.guestChannel, p.hostInbox, 'guestToHost'),
      (p.hostChannel, p.guestInbox, 'hostToGuest'),
    ]) {
      final start = Stopwatch()..start();
      messages.forEach(from.send);
      final got = await to.take(messages.length);
      report['textMs.$name'] = start.elapsedMilliseconds;
      check(jsonEncode(got) == jsonEncode(messages), 'text $name arrived whole');
    }

    // A burst, all of it, in order.
    final burst = burstMessages();
    for (final (from, to, name) in [
      (p.guestChannel, p.hostInbox, 'guestToHost'),
      (p.hostChannel, p.guestInbox, 'hostToGuest'),
    ]) {
      final start = Stopwatch()..start();
      burst.forEach(from.send);
      final got = await to.take(burst.length);
      report['burstMs.$name'] = start.elapsedMilliseconds;
      check(jsonEncode(got) == jsonEncode(burst), 'burst $name in order');
    }

    // A close at either end is seen at the other.
    for (final guestCloses in [true, false]) {
      if (!guestCloses) p = await connect();
      final closer = guestCloses ? p.guest : p.host;
      final otherChannel = guestCloses ? p.hostChannel : p.guestChannel;
      final start = Stopwatch()..start();
      final closing = closer.close();
      try {
        await otherChannel.onClosed.timeout(const Duration(seconds: 10));
        report['closeSeenMs.${guestCloses ? 'guest' : 'host'}Closes'] = start.elapsedMilliseconds;
      } on Object {
        check(false, '${guestCloses ? 'guest' : 'host'} closing seen at the other end');
      }
      await closing;
      await closer.close();
      await p.close();
    }

    // Candidates before the description wait for it.
    p = await connect(candidatesFirst: true);
    check(p.guestChannel.isOpen && p.hostChannel.isOpen, 'early candidates');
    await p.close();
    report['setupMs'] = setups;
  } on Object catch (e) {
    failures.add('error: $e');
  }

  report['failures'] = failures;
  final text = const JsonEncoder.withIndent('  ').convert(report);
  web.console.log('RTC: $text'.toJS);
  final pre = web.document.createElement('pre')..textContent = text;
  web.document.body?.appendChild(pre);
  web.document.title = failures.isEmpty ? 'RTC PASS' : 'RTC FAIL';
}
