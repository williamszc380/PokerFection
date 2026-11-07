/// Screenshots of Gomoku in a room, at a sideways phone, a small browser, a
/// PC and an upright phone, in every language: Home in a room (Gomoku not
/// greyed out), the host's rules on the
/// room's table, the game seated (the host as Black under Renju, its
/// forbidden points marked, and the guest waiting), a spectator with the
/// coach on, and the end of a game for a player and a spectator. PNGs are
/// written only with `--dart-define=SHOTS=<folder>` (see test/kit/shots.dart);
/// without it the test still lays every screen out and checks that nothing
/// overflows.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/gomoku/gomoku.dart';
import 'package:pokerfection/src/games/gomoku/online/gomoku_view_codec.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/ui/home_screen.dart';
import 'package:pokerfection/src/ui/online/online_game_uis.dart';
import 'package:pokerfection/src/ui/online/room_scope.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import '../kit/shots.dart' show loadShotFonts, shotTag, shotTheme, shotsFolder;
import 'room_app.dart';
import 'room_kit.dart';

const _sizes = [Size(568, 320), Size(900, 420), Size(1280, 800), Size(390, 844)];

final _boundary = GlobalKey();

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

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// [name] for [rooms]'s app at every size in every language.
Future<void> _everywhere(
  WidgetTester tester,
  RoomService rooms,
  String name, {
  Future<void> Function()? prepare,
}) async {
  for (final language in AppLanguage.values) {
    rooms.settings.update((s) => s.language = language);
    await _pumpApp(tester, rooms);
    for (final size in _sizes) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await _settle(tester);
      await prepare?.call();
      await _settle(tester);
      await _shot(tester, '${name}_${shotTag(size, language)}');
      expect(tester.takeException(), isNull, reason: '$name ${shotTag(size, language)}');
    }
  }
  rooms.settings.update((s) => s.language = AppLanguage.english);
}

void main() {
  setUpAll(loadShotFonts);

  testWidgets('Gomoku in the room: the rules, the game seated and watched (the coach on), and its end', (tester) async {
    addTearDown(tester.view.reset);
    final server = TestServer();
    RoomService roomsFor(String name) => RoomService(
      settings: AppSettings()
        ..nickname = name
        ..speed = PlaybackSpeed.instant,
      gameUis: onlineGameUis,
      newJobs: () => Jobs.inline(),
    );
    final ann = roomsFor('Ann'), ben = roomsFor('Ben'), cy = roomsFor('Cy');
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
    // Home in the room: Gomoku is no longer greyed out (the games without their online part still are).
    await server.wait(tester, const Duration(seconds: 1));
    await _everywhere(tester, ann, 'gomoku_home_in_room');
    const renju = GomokuOnlineRules(rules: GomokuRules.renju, black: GomokuBlackRule.loser);
    own.send(ChooseGame(game: 'gomoku', setup: {'seats': 2, 'turnLimit': 30, 'rules': renju.toJson()}));
    await server.wait(tester, const Duration(seconds: 1));

    // The host's rules, opened on the room's table.
    await _everywhere(
      tester,
      ann,
      'gomoku_room_rules_host',
      prepare: () async {
        if (find.byKey(const ValueKey('gomoku rules'), skipOffstage: false).evaluate().isEmpty) {
          final rules = find.byKey(const ValueKey('rules'), skipOffstage: false);
          await tester.ensureVisible(rules);
          await tester.pump();
          await tester.tap(rules);
          await _settle(tester);
        }
        await tester.ensureVisible(find.byKey(const ValueKey('gomoku black'), skipOffstage: false));
        await _settle(tester);
      },
    );

    // Ann (Black) and Ben sit; a Renju position where Black may not play i8 (a double three).
    own.send(const TakeSeat(0));
    benClient.send(const TakeSeat(1));
    await server.until(tester, () => own.room!.taken == 2, 'seated');
    own.send(const StartGame());
    await server.until(tester, () => ann.runner?.state != null && ben.runner?.state != null, 'the game');
    for (final move in 'h8 a1 j8 a2 i9 a3 i10 a4'.split(' ')) {
      final mover = [ann, ben][GomokuOnlineView.fromJson(ann.runner!.view!).seatToAct!];
      await server.until(tester, () => mover.runner!.myTurn, 'a turn');
      mover.runner!.move(move);
      await server.wait(tester, const Duration(milliseconds: 500));
    }
    await server.until(tester, () => ann.runner!.myTurn, "Ann's turn");
    await _everywhere(tester, ann, 'gomoku_game_host_seated', prepare: () async => ann.watch());
    await _everywhere(tester, ben, 'gomoku_game_guest_seated', prepare: () async => ben.watch());
    cy.runner!.setCoach(true);
    await _everywhere(
      tester,
      cy,
      'gomoku_game_spectator_coach',
      prepare: () async {
        cy.watch();
        for (var i = 0; i < 20 && (cy.runner!.coach == null || cy.runner!.coachThinking); i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(cy.runner!.coach, isNotNull);
      },
    );

    // White makes five: the end for a player and for the spectator.
    ann.runner!.move('m13');
    await server.until(tester, () => ben.runner!.myTurn, "Ben's turn");
    ben.runner!.move('a5');
    await server.until(tester, () => ann.runner!.over != null && cy.runner!.over != null, 'the five');
    await _everywhere(tester, ann, 'gomoku_game_over_host', prepare: () async => ann.watch());
    await _everywhere(tester, cy, 'gomoku_game_over_spectator', prepare: () async => cy.watch());
    for (final r in [ann, ben, cy]) {
      unawaited(r.leave());
    }
    await server.wait(tester, const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
    await server.wait(tester, const Duration(seconds: 6));
  });
}
