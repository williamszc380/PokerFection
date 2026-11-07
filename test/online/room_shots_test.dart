/// Screenshots of the room beside the app's screens and of the room's
/// table (rooms v2.1), at phone, tablet and PC sizes in every language.
/// PNGs are written only with `--dart-define=SHOTS=<folder>` (see
/// test/kit/shots.dart); without it the test still lays every screen out
/// and checks that nothing overflows.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/online/online_client.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/ui/game_menu.dart';
import 'package:pokerfection/src/ui/games.dart';
import 'package:pokerfection/src/ui/home_screen.dart';
import 'package:pokerfection/src/ui/online/room_lobby_screen.dart';
import 'package:pokerfection/src/ui/online/room_scope.dart';
import 'package:pokerfection/src/ui/setup_screen.dart';
import 'package:pokerfection/src/ui/table_controller.dart';
import 'package:pokerfection/src/ui/table_screen.dart';

import '../kit/shots.dart' show loadShotFonts, shotTag, shotTheme, shotsFolder;
import '../widget_test.dart' show testSolutions;
import 'room_app.dart';
import 'room_kit.dart';

const _sizes = [Size(512, 320), Size(568, 320), Size(900, 420), Size(1280, 800), Size(390, 844)];

final _boundary = GlobalKey();
final _problems = <String>[];

/// The app of [rooms] (its settings: name, language), Home first.
Future<void> _pumpApp(WidgetTester tester, RoomService rooms) async {
  await tester.pumpWidget(RepaintBoundary(key: _boundary, child: roomApp(const HomeScreen(), rooms: rooms, theme: shotTheme())));
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

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
}

/// Lets the screens settle (without moving the room's time on).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Every size and language of [rooms]'s app as it is now: `<name>_<tag>.png`.
/// [prepare] runs at each size first (to open the room's panel, say), and
/// [cleanup] after its shot.
Future<void> _everywhere(
  WidgetTester tester,
  RoomService rooms,
  String name, {
  List<Size> sizes = _sizes,
  Future<void> Function(Size size)? prepare,
  Future<void> Function(Size size)? cleanup,
}) async {
  for (final language in AppLanguage.values) {
    rooms.settings.update((s) => s.language = language);
    await _pumpApp(tester, rooms);
    for (final size in sizes) {
      _size(tester, size);
      await _settle(tester);
      await prepare?.call(size);
      await _settle(tester);
      await _shot(tester, '${name}_${shotTag(size, language)}');
      final problem = tester.takeException();
      if (problem != null) _problems.add('$name ${shotTag(size, language)}: $problem');
      await cleanup?.call(size);
      await _settle(tester);
    }
  }
  rooms.settings.update((s) => s.language = AppLanguage.english);
}

void main() {
  // With 512x320 (the room's rail beside the narrowest Home), the About box and the ended room.
  setUpAll(loadShotFonts);
  tearDown(() => TestWidgetsFlutterBinding.instance.platformDispatcher.views.first.resetPhysicalSize());

  testWidgets("the slim room beside Home (greyed games), the host's room setup, the room's table with its seats (the "
      'host, and a guest who followed), the game with its Seats bar and sheet', (tester) async {
    addTearDown(tester.view.reset);
    final server = TestServer();
    AppSettings settingsFor(String name) => AppSettings()
      ..nickname = name
      ..speed = PlaybackSpeed.instant;
    final ann = RoomService(settings: settingsFor('Ann'), solutions: testSolutions());
    final ben = RoomService(settings: settingsFor('Ben'), solutions: testSolutions());
    _size(tester, const Size(1280, 800));
    await _pumpApp(tester, ann);

    // A room with no game: Ann hosts, Ben, Cy and Dee watch.
    final own = server.client();
    await server.open(tester, own, const CreateRoom(name: 'Ann'));
    ann.enter(own);
    final code = own.room!.code;
    final benClient = server.client();
    await server.open(tester, benClient, JoinRoom(code: code, name: 'Ben'));
    ben.enter(benClient);
    final cy = AutoGuest(server, 'Cy', think: const Duration(seconds: 4))..join(code);
    AutoGuest(server, 'Dee', think: const Duration(seconds: 4)).join(code);
    await server.until(tester, () => own.room!.members.length == 4, 'everyone in');
    cy.send(const Say('hi all!'));
    await server.wait(tester, const Duration(seconds: 1));
    // Home in a room: only Hold'em can be played online, the rest greyed out; the room shows people and chat.
    await _everywhere(tester, ann, 'home_host_nogame');
    await _everywhere(tester, ben, 'home_guest_nogame');

    // The rail's and the bar's room, opened.
    await _everywhere(
      tester,
      ann,
      'room_opened_host',
      sizes: const [Size(512, 320), Size(568, 320), Size(900, 420), Size(390, 844)],
      prepare: (_) async => ann.openPanel(),
      cleanup: (_) async => ann.navigatorKey.currentState!.popUntil((r) => r.isFirst),
    );

    // The host's Hold'em setup while hosting: the room's rules and Open Table.
    await _pumpApp(tester, ann);
    unawaited(ann.navigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => GameMenu(game: games.first))));
    unawaited(ann.navigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => const SetupScreen())));
    await _settle(tester);
    await _everywhere(tester, ann, 'setup_host_room');
    ann.navigatorKey.currentState!.popUntil((r) => r.isFirst);
    await _settle(tester);

    // Ben is on a game's menu when Ann opens Hold'em: he follows her to its table.
    _size(tester, const Size(1280, 800));
    await _pumpApp(tester, ben);
    unawaited(ben.navigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => GameMenu(game: games.first))));
    await _settle(tester);
    ann.hostPick(holdemKey, holdem: const RoomSettings(seats: 4, stackBb: 20, resetStacks: true, turnLimit: 15));
    await server.until(tester, () => find.byType(RoomLobbyScreen).evaluate().isNotEmpty, 'Ben follows');
    own.send(const AddBot(style: 'gto', seat: 1));
    cy.send(const TakeSeat(2));
    await server.until(tester, () => own.room!.taken == 2, 'seated');
    await _everywhere(tester, ben, 'table_seats_guest');
    // Ben types in the Room tab with the soft keyboard up: the box stays above it.
    await _everywhere(
      tester,
      ben,
      'table_room_keyboard',
      sizes: const [Size(568, 320), Size(900, 420), Size(390, 844)],
      prepare: (size) async {
        await tester.tap(find.byKey(const ValueKey('room tab')));
        await _settle(tester);
        final box = find.byKey(const ValueKey('chat box'));
        await tester.dragUntilVisible(box, find.byKey(const ValueKey('room panel')), const Offset(0, -120));
        await tester.pump();
        await tester.tap(box);
        await tester.enterText(box, 'one sec');
        tester.view.viewInsets = FakeViewPadding(bottom: size.width > size.height ? 180 : 300);
      },
      cleanup: (_) async {
        tester.view.resetViewInsets();
        FocusManager.instance.primaryFocus?.unfocus();
        ben.chatDraft.clear();
        await _settle(tester);
        await tester.tap(find.byKey(const ValueKey('game tab')));
      },
    );

    // Ann at the room's table: her seats (a bot to add or take away on each) and Start.
    await _pumpApp(tester, ann);
    ann.watch();
    await _settle(tester);
    await _everywhere(tester, ann, 'table_seats_host');
    await _everywhere(
      tester,
      ann,
      'table_seats_host_room',
      prepare: (_) async => tester.tap(find.byKey(const ValueKey('room tab'))),
      cleanup: (_) async => tester.tap(find.byKey(const ValueKey('game tab'))),
    );

    // Back on Home, Hold'em picked: the room's line and Watch.
    ann.navigatorKey.currentState!.popUntil((r) => r.isFirst);
    await _settle(tester);
    await _everywhere(tester, ann, 'home_host_game');

    // The game: Ben sits too; Dee watches. Ann (watching) has the coach on; the table's bar has Seats and End game.
    benClient.send(const TakeSeat(3));
    await server.until(tester, () => benClient.mySeat != null, 'Ben seated');
    _size(tester, const Size(1280, 800));
    await _pumpApp(tester, ann);
    own.send(const StartGame());
    await server.until(tester, () => ann.table != null && find.byType(TableScreen).evaluate().isNotEmpty, 'the table');
    ann.table!.setCoach(true);
    await server.until(tester, () {
      final t = ann.table!;
      final seat = t.view.actingSeat;
      return seat != null && !t.handOver && t.view.seats[seat].info.name == 'Cy' && t.spectatorCoach?.spot != null;
    }, "the coach's answer for Cy", limit: 3000);
    await _everywhere(tester, ann, 'table_spectator_coach');
    await _everywhere(
      tester,
      ann,
      'table_seats_sheet',
      prepare: (_) async => tester.tap(find.byKey(const ValueKey('seats button'))),
      cleanup: (_) async => tester.tap(find.byKey(const ValueKey('close seats'))),
    );

    // Ben at his turn: the seated player's Game tab.
    await _pumpApp(tester, ben);
    await server.until(tester, () => ben.table?.heroOptions != null, "Ben's turn", limit: 3000);
    if (find.byType(TableScreen).evaluate().isEmpty) ben.watch();
    await _everywhere(tester, ben, 'table_seated');

    // About, from Home's version.
    ben.navigatorKey.currentState!.popUntil((r) => r.isFirst);
    await _everywhere(
      tester,
      ben,
      'about',
      prepare: (_) async => tester.tap(find.byKey(const ValueKey('about'))),
      cleanup: (_) async => tester.tap(find.byKey(const ValueKey('about close'))),
    );
    // A guest at the seats' Room tab (before the next game would be the same screen): Ben, after the game.
    unawaited(ann.leave());
    await server.wait(tester, const Duration(seconds: 2));
    await _everywhere(tester, ben, 'home_guest_ended');
    unawaited(ben.leave());
    await server.wait(tester, const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
    await server.wait(tester, const Duration(seconds: 6));
    expect(benClient.status, OnlineStatus.closed);
    for (final p in _problems) {
      // ignore: avoid_print
      print('PROBLEM $p');
    }
    expect(_problems, isEmpty);
  });
}
