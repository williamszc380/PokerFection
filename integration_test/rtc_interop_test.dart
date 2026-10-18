// The Windows app hosting, a browser joining: this app's WebRTC (Google's,
// through flutter_webrtc) and a browser's (Chrome's and Edge's, through the
// web version's code) must understand each other, since friends without
// the app join a PC's room from a browser.
//
// The test serves the page built from rtc_browser_guest.dart, opens it in
// each browser installed (headless), and acts as the host: it answers each
// offer, sends back every message it gets, and checks what arrived. The
// offer, answer and candidates go through the test's own WebSocket, not
// the meeting service. First build the page:
//
//   flutter build web --wasm -t integration_test/rtc_browser_guest.dart -o build/rtc_browser_guest
//   flutter test integration_test/rtc_interop_test.dart -d windows
//
// Without the page, or on a system other than Windows, the test is skipped.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pokerfection/src/online/channel_link.dart';
import 'package:pokerfection/src/online/rtc.dart';

import 'support/browser.dart';
import 'support/loopback.dart';

/// Where the page is built (see above).
const pageFolder = 'build/rtc_browser_guest';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final page = _findPage();
  final skip = !Platform.isWindows
      ? 'Windows only'
      : !File('${page.path}/index.html').existsSync()
      ? 'build the page first: $pageFolder'
      : null;

  for (final MapEntry(key: name, value: exe) in browsers.entries) {
    test(
      'a guest in $name connects to this app, both ways whole, and each end sees the other close',
      () async {
        final host = _Host(page);
        await host.start();
        final browser = await HeadlessBrowser.open(exe, 'http://127.0.0.1:${host.port}/index.html');
        try {
          final report = await host.done.future.timeout(const Duration(seconds: 90));
          debugPrint('RTC: $name: ${jsonEncode(report)}');
          debugPrint('RTC: $name: host saw the guest close after ${host.guestCloseSeenMs} ms');
          expect(report['failures'], isEmpty);
          expect(host.problems, isEmpty);
          expect(host.rounds, 2);
          expect(host.guestCloseSeenMs, isNotNull);
        } finally {
          await browser.close();
          await host.stop();
        }
      },
      skip: skip ?? (File(exe).existsSync() ? null : '$name is not installed'),
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}

/// The built page: from the project folder, which is where the app runs
/// from under flutter test, or found from the app itself
/// (`build/windows/x64/runner/<mode>/PokerFection.exe`).
Directory _findPage() {
  final here = Directory(pageFolder);
  if (here.existsSync()) return here;
  var root = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 5; i++) {
    root = root.parent;
  }
  return Directory('${root.path}/$pageFolder');
}

/// The host's side: a small web server for the page and the signaling
/// WebSocket, and one peer connection per offer.
class _Host {
  _Host(this.page);

  final Directory page;
  late final HttpServer _server;
  WebSocket? _socket;
  final Completer<Map<String, Object?>> done = Completer();
  final List<String> problems = [];
  final Map<int, RtcPeer> _peers = {};
  final Map<int, List<String>> _received = {};
  int rounds = 0;
  int? guestCloseSeenMs;

  int get port => _server.port;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_serve);
  }

  Future<void> _serve(HttpRequest request) async {
    if (request.uri.path == '/signal') {
      final socket = _socket = await WebSocketTransformer.upgrade(request);
      socket.listen((data) => _onSignal((jsonDecode(data as String) as Map).cast()));
      return;
    }
    final path = request.uri.path == '/' ? '/index.html' : request.uri.path;
    final file = File('${page.path}$path');
    if (!file.existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    request.response.headers.contentType = switch (path.split('.').last) {
      'html' => ContentType.html,
      'js' || 'mjs' => ContentType('text', 'javascript'),
      'wasm' => ContentType('application', 'wasm'),
      'json' => ContentType.json,
      _ => ContentType.binary,
    };
    await request.response.addStream(file.openRead());
    await request.response.close();
  }

  void _send(Map<String, Object?> message) => _socket?.add(jsonEncode(message));

  Future<void> _onSignal(Map<String, Object?> m) async {
    final round = m['r'] as int?;
    switch (m['k']) {
      case 'offer':
        await _answer(round!, m['sdp']! as String);
      case 'cand':
        _peers[round]?.addRemoteCandidate(
          RtcCandidate(m['candidate']! as String, sdpMid: m['sdpMid'] as String?, sdpMLineIndex: m['sdpMLineIndex'] as int?),
        );
      case 'closing':
        final start = Stopwatch()..start();
        final channel = await _peers[round]!.channel;
        unawaited(channel.onClosed.then((_) => guestCloseSeenMs = start.elapsedMilliseconds));
      case 'done':
        if (!done.isCompleted) done.complete((m['report']! as Map).cast());
    }
  }

  /// Answers the guest's offer for [round], then sends back each message,
  /// and closes when asked to.
  Future<void> _answer(int round, String offer) async {
    final peer = _peers[round] = platformRtc().create();
    final got = _received[round] = [];
    var answered = false;
    final early = <RtcCandidate>[];
    void sendCandidate(RtcCandidate c) =>
        _send({'k': 'cand', 'r': round, 'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex});
    peer.onLocalCandidate.listen((c) => answered ? sendCandidate(c) : early.add(c));
    try {
      _send({'k': 'answer', 'r': round, 'sdp': await peer.answer(offer)});
      answered = true;
      early.forEach(sendCandidate);
      final channel = await peer.channel;
      await channel.onOpen;
      rounds++;
      final expected = [...sampleMessages(ChannelLink.maxMessage), ...burstMessages()];
      channel.onText.listen((text) {
        if (text == '{"t":"close-me"}') {
          if (jsonEncode(got) != jsonEncode(expected)) problems.add('round $round: the host got changed messages');
          unawaited(peer.close());
          return;
        }
        got.add(text);
        channel.send(text);
      });
      unawaited(
        channel.onClosed.then((_) {
          if (round == 0 && jsonEncode(got) != jsonEncode(expected)) {
            problems.add('round $round: the host got ${got.length} of ${expected.length} messages, or changed');
          }
        }),
      );
    } on Object catch (e) {
      problems.add('round $round: $e');
    }
  }

  Future<void> stop() async {
    for (final peer in _peers.values) {
      await peer.close();
    }
    await _socket?.close();
    await _server.close(force: true);
  }
}
