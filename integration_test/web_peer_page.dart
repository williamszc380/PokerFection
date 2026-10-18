// A browser playing online through the PUBLIC meeting service, for
// web_peer_test.dart: the web version's own joining and hosting code, run
// in headless Chrome or Edge, against the Windows app on the other end.
//
//   flutter build web --wasm -t integration_test/web_peer_page.dart -o build/web_peer_wasm
//   flutter build web -t integration_test/web_peer_page.dart -o build/web_peer_js
//
// (the first runs as WebAssembly in Chrome and Edge, the second as
// JavaScript). Opened at `?room=CODE`, the page:
//   1. joins the app's room CODE as a guest, by code alone (peer:CODE,
//      as the website does from an invite), waits for the host to deal a
//      hand, says something in the chat, and leaves;
//   2. hosts a room itself, as Create Room does in a browser (hostHere:
//      the room in the page, its code taken at the meeting service, the
//      page's own app joining in memory), tells the test its code, waits
//      for the app to sit down, deals a hand (cards shuffled with
//      Random.secure, here in the browser), waits for the app's chat
//      line, and closes the room.
// It reports each step and its findings to the test over a WebSocket at
// /report, and sets the title to "WEB PASS" or "WEB FAIL".
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';

import 'package:pokerfection/src/online/host_here.dart';
import 'package:pokerfection/src/online/online_client.dart';
import 'package:pokerfection/src/online/peer_config.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/online/room_host.dart';
import 'package:web/web.dart' as web;

import 'support/web_peer_words.dart';

Future<void> main() async {
  final failures = <String>[];
  final report = <String, Object?>{
    'wasm': const bool.fromEnvironment('dart.tool.dart2wasm'),
    'browser': web.window.navigator.userAgent,
  };
  final socket = web.WebSocket('ws://${web.window.location.host}/report');
  final opened = Completer<void>();
  socket.onopen = ((web.Event _) => opened.complete()).toJS;
  await opened.future;
  void tell(Map<String, Object?> message) => socket.send(jsonEncode(message).toJS);

  Future<void> step(String name, Future<void> Function() body) async {
    final watch = Stopwatch()..start();
    try {
      await body();
      report['$name.ms'] = watch.elapsedMilliseconds;
      tell({'k': 'step', 'name': name, 'ms': watch.elapsedMilliseconds});
    } on Object catch (e) {
      failures.add('$name: $e');
      tell({'k': 'step', 'name': name, 'error': '$e'});
      rethrow;
    }
  }

  try {
    // Cards are dealt with Random.secure: it must work in this build.
    await step('secureRandom', () async {
      final random = Random.secure();
      report['secureRandom'] = [for (var i = 0; i < 4; i++) random.nextInt(1000000000)];
    });
    report['canHostHere'] = canHostHere;

    // 1. A guest in the app's room.
    final room = Uri.base.queryParameters['room']!;
    final guest = OnlineClient(peerEntry(room));
    await step('guestJoined', () async {
      await guest.open(JoinRoom(code: room, name: 'Web')).timeout(const Duration(seconds: 30));
    });
    await step('guestDealt', () => _next<NextHand>(guest, const Duration(seconds: 30)));
    await step('guestSaid', () async {
      if (!guest.say(fromPage)) throw StateError('the chat line could not go');
    });
    await guest.close();

    // 2. Hosting in the page.
    late final RoomHost host;
    late final OnlineClient own;
    await step('hosted', () async {
      host = await hostHere();
      own = OnlineClient(host.ownServer, host: host);
      await own.open(const CreateRoom(name: 'WebHost')).timeout(const Duration(seconds: 10));
      for (var i = 0; i < 100 && host.internet != PeerStatus.ready; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      report['internet'] = '${host.internet}';
      report['inBrowser'] = host.inBrowser;
      if (host.internet != PeerStatus.ready) throw StateError('not ready at the meeting service: ${host.internet}');
    });
    final code = own.welcome!.code;
    tell({'k': 'hosted', 'code': code});
    await step('appSeated', () async {
      for (var i = 0; (own.room?.taken ?? 0) < 2; i++) {
        if (i > 400) throw TimeoutException('the app never sat down');
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    final heard = own.said.firstWhere((line) => line.text == fromApp);
    own.send(const StartGame());
    await step('appSaid', () async {
      final line = await heard.timeout(const Duration(seconds: 30));
      if (line.name != 'App') throw StateError('the line came from ${line.name}');
    });
    await step('closed', () => own.close());
  } on Object catch (e) {
    if (failures.isEmpty) failures.add('$e');
  }
  report['failures'] = failures;
  tell({'k': 'done', 'report': report});
  web.document.title = failures.isEmpty ? 'WEB PASS' : 'WEB FAIL';
}

/// The next [T] the room sends [client] (others are skipped).
Future<void> _next<T extends ServerMessage>(OnlineClient client, Duration within) {
  final got = Completer<void>();
  client.attach((message) {
    if (message is T && !got.isCompleted) got.complete();
  });
  return got.future.timeout(within).whenComplete(client.detach);
}
