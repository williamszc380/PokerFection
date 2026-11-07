// The Game tab keeps the who-goes-first step's secret until the felt tells
// it: while the step plays (the cards going round in Fight the Landlord,
// low cards being called in a two-player Big Two deal) the tab neither
// names the player who opens ("Ann…") nor says "Your turn" over greyed-out
// buttons.
import 'dart:async';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/big_two/online/big_two_runner.dart';
import 'package:pokerfection/src/games/big_two/online/big_two_view_codec.dart';
import 'package:pokerfection/src/games/doudizhu/online/doudizhu_runner.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/ui/games/doudizhu/online/doudizhu_online_ui.dart';
import 'package:pokerfection/src/ui/home_screen.dart';
import 'package:pokerfection/src/ui/online/online_game_uis.dart';
import 'package:pokerfection/src/ui/online/room_scope.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import '../kit/shots.dart' show loadShotFonts, shotTheme;
import 'room_app.dart';
import 'room_kit.dart';

final _status = find.byKey(const ValueKey('game status'));
final _bigTwoStep = find.byKey(const ValueKey('opening step'));
final _bigTwoWords = find.byKey(const ValueKey('opening words'));

RoomService _rooms(String name) => RoomService(
  settings: AppSettings()
    ..nickname = name
    ..speed = PlaybackSpeed.normal,
  gameUis: onlineGameUis,
  newJobs: () => Jobs.inline(),
);

Future<void> _open(WidgetTester tester, RoomService rooms) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(roomApp(const HomeScreen(), rooms: rooms, theme: shotTheme()));
  await tester.pump();
  rooms.watch();
  await tester.pump();
  await tester.pump();
}

String? _statusText(WidgetTester tester) =>
    _status.evaluate().isEmpty ? null : (_status.evaluate().single.widget as Text).data;

Future<void> _end(WidgetTester tester, TestServer server, List<RoomService> rooms) async {
  for (final r in rooms) {
    unawaited(r.leave());
  }
  await server.wait(tester, const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox());
  await server.wait(tester, const Duration(seconds: 6));
}

void main() {
  setUpAll(loadShotFonts);

  testWidgets('Big Two, two people: while low cards are called, the Game tab names nobody', (tester) async {
    addTearDown(tester.view.reset);
    final server = TestServer(seed: 3, games: {'big_two': bigTwoOnline!});
    final ann = _rooms('Ann'), ben = _rooms('Ben'), cy = _rooms('Cy');
    final own = server.client(), benClient = server.client(), cyClient = server.client();
    await server.open(tester, own, const CreateRoom(name: 'Ann'));
    ann.enter(own);
    await server.open(tester, benClient, JoinRoom(code: own.room!.code, name: 'Ben'));
    ben.enter(benClient);
    await server.open(tester, cyClient, JoinRoom(code: own.room!.code, name: 'Cy'));
    cy.enter(cyClient);
    own.send(ChooseGame(game: 'big_two', setup: {'seats': 2, 'turnLimit': 0, 'rules': bigTwoOnline!.defaultRules}));
    await server.wait(tester, const Duration(seconds: 1));
    own.send(const TakeSeat(0));
    benClient.send(const TakeSeat(1));
    await server.until(tester, () => own.room!.taken == 2, 'seated');
    own.send(const StartGame());
    await server.until(tester, () => ann.runner?.view != null && cy.runner?.view != null, 'the deal');
    final start = BigTwoWireView.read(cy.runner!.view!).start!;
    final starter = start.seat == 0 ? 'Ann' : 'Ben';
    for (final (who, rooms) in [('the spectator', cy), ('a player', start.seat == 0 ? ben : ann)]) {
      await _open(tester, rooms);
      // The calls are still going: the felt names nobody yet.
      expect(_bigTwoStep, findsOneWidget);
      expect(_bigTwoWords, findsNothing, reason: 'the felt has not named the starter yet');
      expect(_statusText(tester), isNot(contains(starter)), reason: '$who\'s Game tab gives the starter away');
      await tester.pump(const Duration(milliseconds: 2100));
    }
    // The starter's own tab: no "Your turn" while Play is greyed out.
    await _open(tester, start.seat == 0 ? ann : ben);
    expect(_bigTwoStep, findsOneWidget);
    expect(_statusText(tester), isNot('Your turn'), reason: 'the step still plays, Play greyed out');
    await tester.pump(const Duration(milliseconds: 2100));
    await _end(tester, server, [ann, ben, cy]);
  });

  testWidgets('Fight the Landlord: while the cards go round, the Game tab names nobody', (tester) async {
    addTearDown(tester.view.reset);
    final server = TestServer(games: {'doudizhu': doudizhuOnline!});
    final ann = _rooms('Ann'), ben = _rooms('Ben'), cy = _rooms('Cy');
    final own = server.client(), benClient = server.client(), cyClient = server.client();
    await server.open(tester, own, const CreateRoom(name: 'Ann'));
    ann.enter(own);
    await server.open(tester, benClient, JoinRoom(code: own.room!.code, name: 'Ben'));
    ben.enter(benClient);
    await server.open(tester, cyClient, JoinRoom(code: own.room!.code, name: 'Cy'));
    cy.enter(cyClient);
    own.send(ChooseGame(game: 'doudizhu', setup: {'seats': 3, 'turnLimit': 0, 'rules': doudizhuOnline!.defaultRules}));
    await server.wait(tester, const Duration(seconds: 1));
    own.send(const TakeSeat(0));
    benClient.send(const TakeSeat(1));
    own.send(const AddBot(style: 'easy'));
    await server.until(tester, () => own.room!.taken == 3, 'seated');
    await _open(tester, cy);
    own.send(const StartGame());
    await server.until(tester, () => cy.runner?.state != null, 'the deal');
    await tester.pump();
    final seen = DdzOnlineSeen.of(cy.runner!);
    expect(seen.dealing, isNotNull, reason: 'the step runs on the spectator\'s device');
    expect(seen.dealing!.landed, isFalse, reason: 'the face-up card is still in the stack');
    final first = cy.runner!.turn?.seat;
    expect(first, isNotNull);
    final name = cy.runner!.nameOf(first!);
    expect(_statusText(tester), isNot(contains(name)), reason: 'the tab names the first bidder before the card lands');
    await server.wait(tester, const Duration(seconds: 3));
    await _end(tester, server, [ann, ben, cy]);
  });
}
