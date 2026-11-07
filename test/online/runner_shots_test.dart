/// Screenshots of a game other than Hold'em in the room (the fake High card
/// game, drawn with plain widgets): the room's panel with the game's rules,
/// and the game's screen with its two tabs, spectating (the coach on) and
/// seated, at phone, browser and PC sizes in every language. PNGs are
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
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/ui/home_screen.dart';
import 'package:pokerfection/src/ui/online/room_scope.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import '../kit/shots.dart' show loadShotFonts, shotTag, shotTheme, shotsFolder;
import '../server/fake_runner.dart';
import 'fake_runner_ui.dart';
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

  testWidgets('High card in the room: the panel with its rules, and its screen spectating and seated', (tester) async {
    addTearDown(tester.view.reset);
    final game = HighCardGame();
    final server = TestServer(games: {game.key: game});
    RoomService roomsFor(String name) => RoomService(
      settings: AppSettings()
        ..nickname = name
        ..speed = PlaybackSpeed.instant,
      gameUis: {game.key: HighCardUi(game)},
      newJobs: highCardInlineJobs,
    );
    final ann = roomsFor('Ann'), ben = roomsFor('Ben');
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    await _pumpApp(tester, ann);
    final own = server.client();
    await server.open(tester, own, const CreateRoom(name: 'Ann'));
    ann.enter(own);
    final benClient = server.client();
    await server.open(tester, benClient, JoinRoom(code: own.room!.code, name: 'Ben'));
    ben.enter(benClient);
    own.send(ChooseGame(game: game.key, setup: const {'seats': 3, 'turnLimit': 30, 'rules': {}}));
    own.send(const AddBot(style: 'medium'));
    await server.wait(tester, const Duration(seconds: 1));
    await _everywhere(tester, ann, 'runner_room_host');
    // The game's rules, open in the narrowest dock (1024 wide: 287 px), in every language.
    for (final language in AppLanguage.values) {
      ann.settings.update((s) => s.language = language);
      await _pumpApp(tester, ann);
      tester.view.physicalSize = const Size(1024, 600);
      await _settle(tester);
      final rules = find.byKey(const ValueKey('rules'));
      await tester.ensureVisible(rules);
      await tester.pump();
      await tester.tap(rules);
      await _settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('hc pad')));
      await _settle(tester);
      await _shot(tester, 'runner_rules_host_${shotTag(const Size(1024, 600), language)}');
      expect(tester.takeException(), isNull);
    }
    ann.settings.update((s) => s.language = AppLanguage.english);

    // Ben sits; Ann watches with the coach on, the bots' cards shown to spectators.
    benClient.send(const TakeSeat());
    own.send(const AddBot(style: 'hard'));
    own.send(const HostSettings(seeBots: true));
    await server.until(tester, () => own.room!.taken == 3, 'seated');
    ann.expectGame();
    own.send(const StartGame());
    await server.until(tester, () => ann.runner != null && ben.runner != null, 'the game');
    // Ben takes his time: his turn shows.
    await server.until(tester, () => ben.runner!.myTurn || (ann.runner!.turn?.seat ?? -1) == 1, 'a turn');
    ann.runner!.setCoach(true);
    await _everywhere(tester, ann, 'runner_game_spectator', prepare: () async => ann.watch());
    await _everywhere(tester, ben, 'runner_game_seated', prepare: () async => ben.watch());
    for (final r in [ann, ben]) {
      unawaited(r.leave());
    }
    await server.wait(tester, const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
    await server.wait(tester, const Duration(seconds: 6));
  });
}
