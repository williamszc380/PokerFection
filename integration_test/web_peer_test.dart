// The web version and the Windows app playing together through the PUBLIC
// meeting service (wss://0.peerjs.com) and public STUN, for real: a
// browser joins a room this app hosts, by its code alone, as the website
// does from an invite; then the browser hosts a room in its page and this
// app joins it. Both ends run the app's own code (the page is
// web_peer_page.dart, see there); the browser is headless Chrome or Edge,
// served from http://localhost (a secure context, as the https website).
//
// First build the page (WebAssembly, and JavaScript):
//
//   flutter build web --wasm -t integration_test/web_peer_page.dart -o build/web_peer_wasm
//   flutter build web -t integration_test/web_peer_page.dart -o build/web_peer_js
//   flutter test integration_test/web_peer_test.dart -d windows --dart-define=PEER_LIVE=1
//
// It goes on the internet, so it runs only when asked; each browser takes
// two new room names at the service and sends a few dozen short messages:
// run it now and then, not in a loop. The room here listens on this
// computer only, and the router is left alone. Without the page, or on a
// system other than Windows, it is skipped. Lines starting with "WEB:" are
// measurements, for the record.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pokerfection/src/online/host_here.dart';
import 'package:pokerfection/src/online/online_client.dart';
import 'package:pokerfection/src/online/online_socket.dart';
import 'package:pokerfection/src/online/peer_config.dart';
import 'package:pokerfection/src/online/peer_socket.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/online/room_host.dart';

import 'support/browser.dart';
import 'support/web_peer_words.dart';

/// Whether to go on the internet: `--dart-define=PEER_LIVE=1`.
const _live = String.fromEnvironment('PEER_LIVE') == '1';

/// The builds of the page to try, each in the browsers named.
const _runs = [
  (build: 'build/web_peer_wasm', browser: 'Chrome', wasm: true),
  (build: 'build/web_peer_wasm', browser: 'Edge', wasm: true),
  (build: 'build/web_peer_js', browser: 'Chrome', wasm: false),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final run in _runs) {
    final page = _find(run.build);
    final exe = browsers[run.browser]!;
    final skip = !_live
        ? 'goes on the internet: run with --dart-define=PEER_LIVE=1'
        : !Platform.isWindows
        ? 'Windows only'
        : !File('${page.path}/index.html').existsSync()
        ? 'build the page first: ${run.build}'
        : !File(exe).existsSync()
        ? '${run.browser} is not installed'
        : null;
    test(
      '${run.browser} (${run.wasm ? 'WebAssembly' : 'JavaScript'}) joins a room hosted by this app with its code '
      'alone, then hosts a room in the page that this app joins; cards are dealt in the browser, chat goes both '
      'ways, and closing the room tells this app at once and gives the code back',
      () => _play(page, exe, run.browser, wasm: run.wasm),
      skip: skip,
      timeout: const Timeout(Duration(minutes: 4)),
    );
  }
}

Future<void> _play(Directory page, String exe, String name, {required bool wasm}) async {
  final site = _Site(page);
  await site.start();
  // 1. This app hosts; the browser joins.
  final host = await hostHere(openRouter: false, loopbackOnly: true);
  final own = OnlineClient(host.ownServer, host: host);
  HeadlessBrowser? browser;
  OnlineClient? app;
  try {
    expect(host.internet, PeerStatus.ready, reason: 'the code taken at the public meeting service');
    final room = (await own.open(const CreateRoom(name: 'Ann'))).code;
    final heardPage = own.said.firstWhere((line) => line.text == fromPage);
    browser = await HeadlessBrowser.open(exe, 'http://localhost:${site.port}/index.html?room=$room');
    await _until(() => (own.room?.taken ?? 0) == 2, 'the browser seated in the room', const Duration(seconds: 60));
    own.send(const StartGame());
    expect((await heardPage.timeout(const Duration(seconds: 30))).name, 'Web');
    await own.close();

    // 2. The browser hosts; this app joins.
    final code = await site.hosted.future.timeout(const Duration(seconds: 30));
    final joining = Stopwatch()..start();
    app = OnlineClient(peerEntry(code));
    await app.open(JoinRoom(code: code, name: 'App')).timeout(const Duration(seconds: 30));
    debugPrint('WEB: $name: this app joined the browser\'s room in ${joining.elapsedMilliseconds} ms');
    final dealt = Completer<NextHand>();
    app.attach((message) {
      if (message is NextHand && !dealt.isCompleted) dealt.complete(message);
    });
    final hand = await dealt.future.timeout(const Duration(seconds: 30));
    debugPrint('WEB: $name: dealt by the browser: hand ${hand.hand}, ${hand.seats.length} players');
    expect(app.say(fromApp), isTrue);
    await _until(
      () => app!.status == OnlineStatus.closed,
      "this app hearing the browser's room closed",
      const Duration(seconds: 30),
    );
    expect(app.closeReason, CloseReason.roomClosed);

    final report = await site.done.future.timeout(const Duration(seconds: 30));
    debugPrint('WEB: $name: ${jsonEncode(report)}');
    expect(report['failures'], isEmpty);
    expect(report['wasm'], wasm);
    expect(report['canHostHere'], isTrue);
    expect(report['inBrowser'], isTrue);
    expect((report['secureRandom']! as List).toSet(), hasLength(greaterThan(1)), reason: 'random numbers');

    // The page gave the code back: nobody holds it at the meeting service now.
    await expectLater(connectPeer(code), throwsA(isA<ConnectionRefused>()));
  } finally {
    await app?.close(leave: false);
    await own.close();
    await host.stop();
    await browser?.close();
    await site.stop();
  }
}

/// Waits until [done], at most [within].
Future<void> _until(bool Function() done, String what, Duration within) async {
  final watch = Stopwatch()..start();
  while (!done()) {
    if (watch.elapsed > within) fail('never: $what');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// A build of the page: from the project folder, which is where the app
/// runs from under flutter test, or found from the app itself
/// (`build/windows/x64/runner/<mode>/PokerFection.exe`).
Directory _find(String folder) {
  final here = Directory(folder);
  if (here.existsSync()) return here;
  var root = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 5; i++) {
    root = root.parent;
  }
  return Directory('${root.path}/$folder');
}

/// A small web server on this computer only: the page's files, and the
/// WebSocket at /report where the page says how it is going.
class _Site {
  _Site(this.page);

  final Directory page;
  late final HttpServer _server;
  final Completer<String> hosted = Completer();
  final Completer<Map<String, Object?>> done = Completer();

  int get port => _server.port;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_serve);
  }

  Future<void> _serve(HttpRequest request) async {
    if (request.uri.path == '/report') {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((data) {
        final m = (jsonDecode(data as String) as Map).cast<String, Object?>();
        switch (m['k']) {
          case 'step':
            debugPrint('WEB: page step ${m['name']}: ${m['error'] ?? '${m['ms']} ms'}');
          case 'hosted':
            if (!hosted.isCompleted) hosted.complete(m['code']! as String);
          case 'done':
            final report = (m['report']! as Map).cast<String, Object?>();
            if (!hosted.isCompleted) hosted.completeError(StateError('the page failed: ${report['failures']}'));
            if (!done.isCompleted) done.complete(report);
        }
      });
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
      'png' => ContentType('image', 'png'),
      _ => ContentType.binary,
    };
    await request.response.addStream(file.openRead());
    await request.response.close();
  }

  Future<void> stop() => _server.close(force: true);
}
