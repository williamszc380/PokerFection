// A guest in a browser, for rtc_interop_test.dart: the web version's WebRTC
// connecting to the Windows app's (Google's WebRTC through flutter_webrtc),
// the way a friend playing in a browser joins a room hosted on a PC. The
// test serves this page and passes the offer, answer and candidates through
// its own small server (a WebSocket at /signal) instead of the meeting
// service.
//
//   flutter build web --wasm -t integration_test/rtc_browser_guest.dart -o build/rtc_browser_guest
//
// Two connections, one after the other: in the first the guest closes, in
// the second it asks the host to close. Each carries the sample messages
// and a burst of 500 both ways (the host sends back everything it gets).
// At the end the page sends its findings to the test ("done").
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:pokerfection/src/online/channel_link.dart';
import 'package:pokerfection/src/online/rtc.dart';
import 'package:web/web.dart' as web;

import 'support/loopback.dart';

/// What the guest sends over the channel to ask the host to close.
const closeMe = '{"t":"close-me"}';

Future<void> main() async {
  final report = <String, Object?>{
    'wasm': const bool.fromEnvironment('dart.tool.dart2wasm'),
    'browser': web.window.navigator.userAgent,
  };
  final failures = <String>[];
  final socket = web.WebSocket('ws://${web.window.location.host}/signal');
  final incoming = StreamController<Map<String, Object?>>.broadcast();
  socket.onmessage = ((web.MessageEvent e) {
    incoming.add((jsonDecode((e.data as JSString).toDart) as Map).cast());
  }).toJS;
  void signal(Map<String, Object?> message) => socket.send(jsonEncode(message).toJS);
  final opened = Completer<void>();
  socket.onopen = ((web.Event _) => opened.complete()).toJS;
  await opened.future;

  try {
    final rtc = platformRtc();
    for (final round in [0, 1]) {
      final guestCloses = round == 0;
      final setup = Stopwatch()..start();
      final peer = rtc.create();
      final signals = incoming.stream.where((m) => m['r'] == round).listen((m) {
        switch (m['k']) {
          case 'answer':
            peer.acceptAnswer(m['sdp']! as String).catchError((Object e) => failures.add('answer: $e'));
          case 'cand':
            peer.addRemoteCandidate(
              RtcCandidate(m['candidate']! as String, sdpMid: m['sdpMid'] as String?, sdpMLineIndex: m['sdpMLineIndex'] as int?),
            );
        }
      });
      final sdp = await peer.offer();
      signal({'k': 'offer', 'r': round, 'sdp': sdp});
      peer.onLocalCandidate.listen((c) {
        signal({'k': 'cand', 'r': round, 'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex});
      });
      final channel = await peer.channel;
      final inbox = Inbox(channel);
      await channel.onOpen.timeout(const Duration(seconds: 15));
      report['setupMs.$round'] = setup.elapsedMilliseconds;

      final samples = sampleMessages(ChannelLink.maxMessage), burst = burstMessages();
      for (final (name, list) in [('samples', samples), ('burst', burst)]) {
        final start = Stopwatch()..start();
        list.forEach(channel.send);
        final back = await inbox.take(list.length);
        report['roundTripMs.$round.$name'] = start.elapsedMilliseconds;
        if (jsonEncode(back) != jsonEncode(list)) failures.add('round $round: $name came back changed');
      }

      final start = Stopwatch()..start();
      if (guestCloses) {
        signal({'k': 'closing', 'r': round});
        await peer.close();
      } else {
        channel.send(closeMe);
        try {
          await channel.onClosed.timeout(const Duration(seconds: 10));
          report['hostCloseSeenMs'] = start.elapsedMilliseconds;
        } on TimeoutException {
          failures.add("the host's close wasn't seen in 10 s");
        }
        await peer.close();
      }
      await signals.cancel();
    }
  } on Object catch (e) {
    failures.add('error: $e');
  }
  report['failures'] = failures;
  signal({'k': 'done', 'report': report});
  web.document.title = failures.isEmpty ? 'RTC PASS' : 'RTC FAIL';
}
