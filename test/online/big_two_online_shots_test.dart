/// Screenshots of Big Two in a room: the host's rules on the room's table,
/// a seated player's screen (cards picked in the hand), a spectator's with
/// the host's switch off and on (the coach on), and a deal's end, at a
/// sideways phone, a browser, a PC and an upright phone, in every
/// language. PNGs are written only with `--dart-define=SHOTS=<folder>`
/// (see test/kit/shots.dart); without it the test still lays every screen
/// out and checks that nothing overflows.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/games/big_two/online/big_two_runner.dart';
import 'package:pokerfection/src/games/big_two/online/big_two_view_codec.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_coach_view.dart' show bigTwoFace;
import 'package:pokerfection/src/ui/home_screen.dart';
import 'package:pokerfection/src/ui/online/online_game_uis.dart';
import 'package:pokerfection/src/ui/online/room_scope.dart';
import 'package:pokerfection/src/ui/online/runner_client.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import '../kit/shots.dart' show loadShotFonts, shotTag, shotTheme, shotsFolder;
import 'room_app.dart';
import 'room_kit.dart';

const _sizes = [Size(568, 320), Size(900, 420), Size(1280, 800), Size(390, 844)];

final _boundary = GlobalKey();

RoomService _rooms(String name) => RoomService(
  settings: AppSettings()
    ..nickname = name
    ..speed = PlaybackSpeed.instant,
  gameUis: onlineGameUis,
  newJobs: () => Jobs.inline(),
);

Future<void> _pumpApp(WidgetTester tester, RoomService rooms) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      child: roomApp(const HomeScreen(), rooms: rooms, theme: shotTheme()),
    ),
  );
  await tester.pump();
}

Future<void> _shot(WidgetTester tester, String name) async {
  if (shotsFolder.isEmpty) return;
  await tester.runAsync(() async {
    final boundary = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(shotsFolder).createSync(recursive: true);
    File('$shotsFolder/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _pumps(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// [name] shot for [rooms]'s app at every size in every language
/// ([prepare] runs after each layout).
Future<void> _everywhere(
  WidgetTester tester,
  RoomService rooms,
  String name, {
  Future<void> Function()? prepare,
  List<Size> sizes = _sizes,
}) async {
  for (final language in AppLanguage.values) {
    rooms.settings.update((s) => s.language = language);
    await _pumpApp(tester, rooms);
    for (final size in sizes) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await _pumps(tester);
      await prepare?.call();
      await _pumps(tester);
      await _shot(tester, '${name}_${shotTag(size, language)}');
      expect(tester.takeException(), isNull, reason: '$name ${shotTag(size, language)}');
    }
  }
  rooms.settings.update((s) => s.language = AppLanguage.english);
}

/// [r]'s player plays the first legal play (or passes), as a quick opponent.
void _autoPlay(RunnerClient? r) {
  if (r == null || !r.myTurn) return;
  final legal = bigTwoEngineView(r.view!).legalMoves();
  r.move(bigTwoMove(r.you!, legal.firstWhere((p) => !p.isPass, orElse: () => Play.pass)));
}

void main() {
  setUpAll(loadShotFonts);

  testWidgets(
    'Big Two in the room: the rules, a seated player, a spectator with the switch off and on, a deal\'s end',
    (tester) async {
      addTearDown(tester.view.reset);
      final server = TestServer(games: {'big_two': bigTwoOnline!});
      final ann = _rooms('Ann'), ben = _rooms('Ben'), cy = _rooms('Cy');
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      await _pumpApp(tester, ann);
      final own = server.client();
      await server.open(tester, own, const CreateRoom(name: 'Ann'));
      ann.enter(own);
      final benClient = server.client(), cyClient = server.client();
      await server.open(tester, benClient, JoinRoom(code: own.room!.code, name: 'Ben'));
      ben.enter(benClient);
      await server.open(tester, cyClient, JoinRoom(code: own.room!.code, name: 'Cy'));
      cy.enter(cyClient);
      own.send(ChooseGame(game: 'big_two', setup: {'seats': 3, 'turnLimit': 30, 'rules': bigTwoOnline!.defaultRules}));
      await server.wait(tester, const Duration(seconds: 1));

      // The host's rules, opened on the room's table.
      await _everywhere(
        tester,
        ann,
        'b2o_rules_host',
        prepare: () async {
          final rules = find.byKey(const ValueKey('rules'));
          if (rules.evaluate().isEmpty) return;
          if (find.byKey(const ValueKey('big two rules')).evaluate().isEmpty) {
            await tester.ensureVisible(rules);
            await tester.pump();
            await tester.tap(rules);
            await _pumps(tester);
          }
          await tester.ensureVisible(find.byKey(const ValueKey('scoring')));
        },
      );

      // Ann and Ben sit with a bot; Cy watches, the coach on.
      own.send(const TakeSeat(0));
      benClient.send(const TakeSeat(1));
      own.send(const AddBot(style: 'medium'));
      await server.until(tester, () => own.room!.taken == 3, 'seated');
      own.send(const StartGame());
      await server.until(tester, () => ann.runner?.state != null && cy.runner?.state != null, 'the deal');
      // A few moves in, to Ann's turn with something on the table.
      for (var guard = 0; ; guard++) {
        expect(guard, lessThan(400));
        final r = ann.runner!;
        if (r.myTurn && (r.view!['history']! as List).length >= 3) break;
        if (r.myTurn) _autoPlay(r);
        _autoPlay(ben.runner);
        await server.wait(tester);
      }
      cy.runner!.setCoach(true);
      // Ann picks the cards of a play: they pop up, Play lights.
      final legal = bigTwoEngineView(ann.runner!.view!).legalMoves().where((p) => !p.isPass).toList();
      var picked = false;
      await _everywhere(
        tester,
        ann,
        'b2o_seated',
        prepare: () async {
          ann.watch();
          await _pumps(tester);
          if (!picked && legal.isNotEmpty) {
            picked = true;
            for (final card in legal.last.cards) {
              await tester.tap(find.byKey(ValueKey('${bigTwoFace(card)}#1')));
              await tester.pump();
            }
          }
        },
      );
      await _everywhere(tester, cy, 'b2o_spectator_switch_off', prepare: () async => cy.watch());

      // The switch on: from the next deal the bots' hands show to spectators.
      own.send(const HostSettings(seeBots: true));
      final round = cy.runner!.round;
      for (var guard = 0; !(cy.runner!.round > round && (cy.runner!.view!['history']! as List).length >= 4); guard++) {
        expect(guard, lessThan(2000));
        _autoPlay(ann.runner);
        _autoPlay(ben.runner);
        await server.wait(tester);
      }
      // The coach's answer for whoever is on turn.
      await server.until(tester, () => cy.runner!.coach != null || cy.runner!.turn == null, 'the coach');
      await _everywhere(tester, cy, 'b2o_spectator_switch_on', prepare: () async => cy.watch());

      // A deal's end: every hand face up, each seat's points, the winner.
      while (ann.runner!.over == null) {
        _autoPlay(ann.runner);
        _autoPlay(ben.runner);
        await server.wait(tester);
      }
      await _everywhere(tester, ann, 'b2o_deal_over', prepare: () async => ann.watch());
      await _everywhere(tester, cy, 'b2o_deal_over_spectator', prepare: () async => cy.watch());

      for (final r in [ann, ben, cy]) {
        unawaited(r.leave());
      }
      await server.wait(tester, const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
      await server.wait(tester, const Duration(seconds: 6));
    },
  );

  testWidgets('Big Two in the room at four seats (two people, two bots, the switch on) and at two', (tester) async {
    addTearDown(tester.view.reset);
    for (final seats in [4, 2]) {
      final server = TestServer(games: {'big_two': bigTwoOnline!});
      final ann = _rooms('Ann'), ben = _rooms('Ben'), cy = _rooms('Cy');
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      await _pumpApp(tester, ann);
      final own = server.client();
      await server.open(tester, own, const CreateRoom(name: 'Ann'));
      ann.enter(own);
      final benClient = server.client(), cyClient = server.client();
      await server.open(tester, benClient, JoinRoom(code: own.room!.code, name: 'Ben'));
      ben.enter(benClient);
      await server.open(tester, cyClient, JoinRoom(code: own.room!.code, name: 'Cy'));
      cy.enter(cyClient);
      own.send(
        ChooseGame(game: 'big_two', setup: {'seats': seats, 'turnLimit': 0, 'rules': bigTwoOnline!.defaultRules}),
      );
      await server.wait(tester, const Duration(seconds: 1));
      own.send(const HostSettings(seeBots: true));
      own.send(const TakeSeat(0));
      benClient.send(const TakeSeat(1));
      for (var b = 2; b < seats; b++) {
        own.send(const AddBot(style: 'easy'));
      }
      await server.until(tester, () => own.room!.taken == seats, 'seated');
      own.send(const StartGame());
      await server.until(tester, () => ann.runner?.state != null && cy.runner?.state != null, 'the deal');
      for (var guard = 0; ; guard++) {
        expect(guard, lessThan(600));
        final r = ann.runner!;
        if (r.myTurn && (r.view!['history']! as List).length >= 4) break;
        if (r.myTurn) _autoPlay(r);
        _autoPlay(ben.runner);
        await server.wait(tester);
      }
      // The coach works while the spectator's screen is open: its answer comes during their shots.
      cy.runner!.setCoach(true);
      await _everywhere(tester, ann, 'b2o_seated_${seats}p', prepare: () async => ann.watch());
      await _everywhere(tester, cy, 'b2o_spectator_${seats}p', prepare: () async => cy.watch());
      for (final r in [ann, ben, cy]) {
        unawaited(r.leave());
      }
      await server.wait(tester, const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
      await server.wait(tester, const Duration(seconds: 6));
    }
  });
}
