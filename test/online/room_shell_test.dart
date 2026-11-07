import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/main.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/ui/game_menu.dart';
import 'package:pokerfection/src/ui/games.dart';
import 'package:pokerfection/src/ui/glossary.dart';
import 'package:pokerfection/src/ui/home_screen.dart';
import 'package:pokerfection/src/ui/online/online_screen.dart';
import 'package:pokerfection/src/ui/online/room_game_frame.dart';
import 'package:pokerfection/src/ui/online/room_panel.dart';
import 'package:pokerfection/src/ui/online/room_scope.dart';
import 'package:pokerfection/src/ui/online/room_shell.dart';
import 'package:pokerfection/src/ui/settings_screen.dart';

import '../kit/shots.dart' show loadShotFonts, shotTag, shotTheme;
import 'room_app.dart';
import 'room_kit.dart';

/// The room beside every screen (RoomShell): docked, a rail or a bar by the
/// window's size; the screens get the rest of the window and keep their
/// state; dialogs from the docked room open over the screen; the game's
/// own screen hides it.

void _size(WidgetTester tester, Size size, {EdgeInsets padding = EdgeInsets.zero}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(left: padding.left, top: padding.top, right: padding.right, bottom: padding.bottom);
  addTearDown(tester.view.reset);
}

/// [rooms] in a room (no game yet) on [server], as Play Online leaves it.
Future<void> _enterRoom(WidgetTester tester, TestServer server, RoomService rooms, {String name = 'Ann'}) async {
  final client = server.client();
  await server.open(tester, client, CreateRoom(name: name));
  rooms.enter(client);
  await tester.pump();
  await tester.pump();
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The screens get this much of the window.
Size _appArea(WidgetTester tester) => tester.getSize(find.byType(Navigator).first);

void main() {
  setUpAll(loadShotFonts);

  const table = [
    (size: Size(568, 320), mode: RoomShellMode.rail, app: Size(512, 320)),
    (size: Size(800, 360), mode: RoomShellMode.rail, app: Size(744, 360)),
    (size: Size(932, 430), mode: RoomShellMode.rail, app: Size(876, 430)),
    (size: Size(1024, 600), mode: RoomShellMode.docked, app: Size(1024 - 286.72, 600)),
    (size: Size(1280, 800), mode: RoomShellMode.docked, app: Size(1280 - 358.4, 800)),
    (size: Size(390, 844), mode: RoomShellMode.bar, app: Size(390, 796)),
    (size: Size(820, 1180), mode: RoomShellMode.bar, app: Size(820, 1132)),
  ];

  testWidgets('in a room, the app shows it docked from 960 px wide, as a rail when narrower and sideways, as a bar '
      'at the bottom when upright; the screens get the rest of the window', (tester) async {
    final server = TestServer();
    final settings = AppSettings()..nickname = 'Ann';
    final rooms = RoomService(settings: settings);
    _size(tester, const Size(1280, 800));
    await tester.pumpWidget(PokerFectionApp(settings: settings, rooms: rooms, newJobs: () => Jobs.inline()));
    expect(find.byType(RoomRail), findsNothing);
    expect(find.byType(RoomPanel), findsNothing);
    expect(tester.getSize(find.byType(HomeScreen)), const Size(1280, 800), reason: 'no room: the whole window');
    await _enterRoom(tester, server, rooms);
    for (final row in table) {
      _size(tester, row.size);
      await _settle(tester);
      expect(RoomShell.modeFor(row.size, rooms), row.mode, reason: '${row.size}');
      expect(rooms.shellMode, row.mode, reason: '${row.size}');
      final area = tester.getSize(find.byType(HomeScreen));
      expect(area.width, closeTo(row.app.width, 0.01), reason: '${row.size}');
      expect(area.height, closeTo(row.app.height, 0.01), reason: '${row.size}');
      expect(find.byType(RoomRail), row.mode == RoomShellMode.rail ? findsOneWidget : findsNothing);
      expect(find.byType(RoomBar), row.mode == RoomShellMode.bar ? findsOneWidget : findsNothing);
      expect(find.byType(RoomPanel), row.mode == RoomShellMode.docked ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull, reason: '${row.size}');
    }
    await tester.pumpWidget(const SizedBox());
  });

  for (final language in AppLanguage.values) {
    testWidgets('in a room, Home fits beside the room at every size (${language.code}): nothing overflows', (tester) async {
      final server = TestServer();
      final rooms = RoomService(settings: AppSettings()
        ..nickname = 'Ann'
        ..language = language);
      _size(tester, const Size(1280, 800));
      await tester.pumpWidget(roomApp(const HomeScreen(), rooms: rooms, theme: shotTheme()));
      await _enterRoom(tester, server, rooms);
      for (final row in table) {
        _size(tester, row.size);
        await _settle(tester);
        expect(tester.takeException(), isNull, reason: shotTag(row.size, language));
        expect(find.text(S.forLanguage(language).room(rooms.room!.code)), findsOneWidget, reason: "Home's room button");
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('beside the rail on the smallest phone (an app area of 512×320, ${language.code}): Play Online, '
        "Settings and the glossary don't overflow; the game menus are measured", (tester) async {
      final server = TestServer();
      final rooms = RoomService(settings: AppSettings()
        ..nickname = 'Ann'
        ..language = language);
      _size(tester, const Size(568, 320));
      await tester.pumpWidget(roomApp(const HomeScreen(), rooms: rooms, theme: shotTheme()));
      await _enterRoom(tester, server, rooms);
      expect(_appArea(tester), const Size(512, 320));
      for (final screen in <Widget>[const OnlineScreen(), const SettingsScreen(), const GlossaryScreen()]) {
        rooms.navigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => screen));
        await _settle(tester);
        expect(tester.takeException(), isNull, reason: '${screen.runtimeType} (${language.code})');
        rooms.navigatorKey.currentState!.pop();
        await _settle(tester);
      }
      // The game menus belong to the games' own work: measured here, not required.
      for (final game in games.where((g) => g.ready)) {
        rooms.navigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => GameMenu(game: game)));
        await _settle(tester);
        final problem = tester.takeException();
        if (problem != null) {
          // ignore: avoid_print
          print('REPORT ${language.code} game menu ${game.id.name} at 512x320: $problem');
        }
        rooms.navigatorKey.currentState!.pop();
        await _settle(tester);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets("on a notched phone held sideways (44 px of safe area on the right), the rail keeps its 56 px and the "
      'screens get the window less both', (tester) async {
    final server = TestServer();
    final rooms = RoomService(settings: AppSettings()..nickname = 'Ann');
    _size(tester, const Size(812, 375), padding: const EdgeInsets.only(right: 44));
    await tester.pumpWidget(roomApp(const HomeScreen(), rooms: rooms));
    await _enterRoom(tester, server, rooms);
    expect(rooms.shellMode, RoomShellMode.rail);
    expect(tester.getSize(find.byKey(const ValueKey('open room'))).width, RoomShell.railWidth);
    expect(tester.getSize(find.byType(HomeScreen)).width, 812 - 100);
    expect(MediaQuery.of(tester.element(find.byType(HomeScreen))).padding.right, 0, reason: 'the rail covers it');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a screen opened before the room is still there, as it was, once in the room and once out of it',
      (tester) async {
    final server = TestServer();
    final rooms = RoomService(settings: AppSettings()..nickname = 'Ann');
    _size(tester, const Size(1280, 800));
    await tester.pumpWidget(roomApp(const HomeScreen(), rooms: rooms));
    rooms.navigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
    await _settle(tester);
    final before = tester.element(find.byType(SettingsScreen));
    await _enterRoom(tester, server, rooms);
    await _settle(tester);
    expect(find.byType(RoomPanel), findsOneWidget);
    expect(tester.element(find.byType(SettingsScreen)), same(before));
    _size(tester, const Size(568, 320));
    await _settle(tester);
    expect(find.byType(RoomRail), findsOneWidget);
    expect(tester.element(find.byType(SettingsScreen)), same(before));
    await rooms.leave();
    await _settle(tester);
    expect(find.byType(RoomRail), findsNothing);
    expect(tester.element(find.byType(SettingsScreen)), same(before));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the rail opens the whole room over the screen; Back closes it', (tester) async {
    final server = TestServer();
    final rooms = RoomService(settings: AppSettings()..nickname = 'Ann');
    _size(tester, const Size(568, 320));
    await tester.pumpWidget(roomApp(const HomeScreen(), rooms: rooms));
    await _enterRoom(tester, server, rooms);
    await tester.tap(find.byKey(const ValueKey('open room')));
    await _settle(tester);
    expect(find.byType(RoomPanel), findsOneWidget);
    expect(find.byType(RoomRail), findsOneWidget, reason: 'the rail stays beside it');
    final panel = tester.getRect(find.byKey(const ValueKey('room panel sheet')));
    expect(panel.right, closeTo(512, 0.01), reason: 'from the rail');
    expect(panel.width, closeTo(360, 0.01));
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.byType(RoomPanel), findsNothing);

    // Upright (a browser): from the bottom bar.
    _size(tester, const Size(390, 844));
    await _settle(tester);
    expect(find.byType(RoomBar), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('open room')));
    await _settle(tester);
    final sheet = tester.getRect(find.byKey(const ValueKey('room panel sheet')));
    expect(sheet.width, 390);
    expect(sheet.bottom, closeTo(796, 0.01), reason: 'above the bar');
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.byType(RoomPanel), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("a \"?\" in the docked room opens its explanation over the screen beside it (not squeezed into the "
      'dock); Back closes it', (tester) async {
    final server = TestServer();
    final rooms = RoomService(settings: AppSettings()..nickname = 'Ann');
    _size(tester, const Size(1280, 800));
    await tester.pumpWidget(roomApp(const HomeScreen(), rooms: rooms));
    await _enterRoom(tester, server, rooms);
    final dockLeft = 1280 - RoomShell.dockWidth(1280);
    await tester.tap(find.descendant(of: find.byType(RoomPanel), matching: find.byType(HelpButton)).first);
    await _settle(tester);
    final dialog = tester.getRect(find.byType(AlertDialog));
    expect(dialog.right, lessThanOrEqualTo(dockLeft), reason: 'over the screen, left of the dock');
    expect(dialog.width, greaterThan(400));
    expect(find.text(S.forLanguage(AppLanguage.english).term(GlossaryTerm.roomStays)), findsOneWidget);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(RoomPanel), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("the dock steps aside while the game's own screen (with its Room tab) is on top, and is back after",
      (tester) async {
    final server = TestServer();
    final rooms = RoomService(settings: AppSettings()..nickname = 'Ann');
    _size(tester, const Size(1280, 800));
    await tester.pumpWidget(roomApp(const HomeScreen(), rooms: rooms));
    await _enterRoom(tester, server, rooms);
    expect(find.byType(RoomPanel), findsOneWidget);
    rooms.navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold(body: RoomTabHost(child: Text('the game')))),
    );
    await _settle(tester);
    expect(rooms.gameOnScreen, isTrue);
    expect(find.byType(RoomPanel), findsNothing);
    expect(tester.getSize(find.text('the game')).width, lessThanOrEqualTo(1280));
    expect(_appArea(tester).width, 1280, reason: 'the whole window');
    // Something over it (a page of its own): the dock is back.
    rooms.navigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
    await _settle(tester);
    expect(find.byType(RoomPanel), findsOneWidget);
    rooms.navigatorKey.currentState!.pop();
    await _settle(tester);
    expect(find.byType(RoomPanel), findsNothing);
    rooms.navigatorKey.currentState!.pop();
    await _settle(tester);
    expect(rooms.gameOnScreen, isFalse);
    expect(find.byType(RoomPanel), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
