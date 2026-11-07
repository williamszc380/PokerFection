/// The room's chat and the keyboard: the soft keyboard never covers the
/// box being typed in (the bar's panel, the docked panel, the game's Room
/// tab), and the docked room never takes the keyboard focus from the
/// screen beside it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/main.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/ui/home_screen.dart';
import 'package:pokerfection/src/ui/online/room_scope.dart';
import 'package:pokerfection/src/ui/online/room_shell.dart';
import 'package:pokerfection/src/ui/table_controller.dart';
import 'package:pokerfection/src/ui/table_screen.dart';

import '../kit/shots.dart' show loadShotFonts;
import '../widget_test.dart' show testSolutions;
import 'room_app.dart';
import 'room_kit.dart';

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _frames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The soft keyboard comes up, [height] tall.
void _keyboard(WidgetTester tester, double height) {
  tester.view.viewInsets = FakeViewPadding(bottom: height);
}

Future<void> _enterRoom(WidgetTester tester, TestServer server, RoomService rooms) async {
  final client = server.client();
  await server.open(tester, client, const CreateRoom(name: 'Ann'));
  rooms.enter(client);
  await _frames(tester, 3);
}

bool _hasFocus(WidgetTester tester, Finder box) => tester
    .state<EditableTextState>(find.descendant(of: box, matching: find.byType(EditableText)))
    .widget
    .focusNode
    .hasFocus;

/// A screen with letter keys, as the solo table and the kit's GameScaffold
/// have them (CallbackShortcuts over an autofocused Focus).
class _KeyPage extends StatelessWidget {
  const _KeyPage({required this.onN});

  final VoidCallback onN;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.keyN): onN},
      child: const Focus(autofocus: true, child: SizedBox.expand()),
    ),
  );
}

void main() {
  setUpAll(loadShotFonts);

  testWidgets("upright browser: the bar's room keeps the chat box (its focus and text) when the keyboard comes up",
      (tester) async {
    _size(tester, const Size(390, 844));
    final server = TestServer();
    final rooms = RoomService(settings: AppSettings()..nickname = 'Ann');
    await tester.pumpWidget(roomApp(const HomeScreen(), rooms: rooms));
    await _enterRoom(tester, server, rooms);
    expect(rooms.shellMode, RoomShellMode.bar);
    await tester.tap(find.byKey(const ValueKey('open room')));
    await _frames(tester);
    final box = find.byKey(const ValueKey('chat box'));
    await tester.ensureVisible(box);
    await tester.pump();
    await tester.tap(box);
    await tester.pump();
    await tester.enterText(box, 'hello');
    await tester.pump();
    expect(_hasFocus(tester, box), isTrue);
    // The phone's keyboard opens (a browser reports it as the view's inset).
    _keyboard(tester, 300);
    await _frames(tester);
    expect(box, findsOneWidget);
    expect(tester.widget<TextField>(box).controller!.text, 'hello', reason: 'what was typed is kept');
    expect(_hasFocus(tester, box), isTrue, reason: 'the box keeps the focus (else the keyboard closes again)');
    expect(tester.getRect(box).bottom, lessThanOrEqualTo(844 - 300 + 0.5), reason: 'above the keyboard');
    unawaited(rooms.leave());
    await server.wait(tester, const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a tablet (1280x800): the docked room\'s chat box stays above the keyboard', (tester) async {
    _size(tester, const Size(1280, 800));
    final server = TestServer();
    final rooms = RoomService(settings: AppSettings()..nickname = 'Ann');
    await tester.pumpWidget(roomApp(const HomeScreen(), rooms: rooms));
    await _enterRoom(tester, server, rooms);
    expect(rooms.shellMode, RoomShellMode.docked);
    final box = find.byKey(const ValueKey('chat box'));
    await tester.tap(box);
    await tester.pump();
    _keyboard(tester, 340);
    await _frames(tester);
    expect(_hasFocus(tester, box), isTrue);
    expect(tester.getRect(box).bottom, lessThanOrEqualTo(800 - 340 + 0.5), reason: 'the box is under the keyboard');
    unawaited(rooms.leave());
    await server.wait(tester, const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in const [Size(568, 320), Size(390, 844)]) {
    testWidgets("at the room's table (${size.width.toInt()}x${size.height.toInt()}): the Room tab's chat box stays "
        'above the keyboard', (tester) async {
      _size(tester, size);
      final server = TestServer();
      final settings = AppSettings()
        ..nickname = 'Ann'
        ..speed = PlaybackSpeed.instant;
      final rooms = RoomService(settings: settings, solutions: testSolutions());
      await tester.pumpWidget(PokerFectionApp(settings: settings, rooms: rooms, newJobs: () => Jobs.inline()));
      await tester.pump();
      final own = server.client();
      await server.open(
        tester,
        own,
        const CreateRoom(name: 'Ann', game: holdemKey, settings: RoomSettings(seats: 3, stackBb: 20, resetStacks: true)),
      );
      rooms.enter(own);
      await tester.pump();
      for (final name in ['Cy', 'Di']) {
        final guest = AutoGuest(server, name, think: const Duration(seconds: 2))..join(own.room!.code);
        await server.until(tester, () => guest.room != null, '$name in');
        guest.send(const TakeSeat());
        await server.until(tester, () => guest.room?.me?.seat != null, '$name seated');
      }
      rooms.expectGame();
      own.send(const StartGame());
      await server.until(tester, () => find.byType(TableScreen).evaluate().isNotEmpty, 'at the table');
      await server.wait(tester, const Duration(milliseconds: 600));
      await tester.tap(find.byKey(const ValueKey('room tab')));
      await server.wait(tester, const Duration(milliseconds: 600));
      final box = find.byKey(const ValueKey('chat box'));
      await tester.dragUntilVisible(box, find.byKey(const ValueKey('room panel')), const Offset(0, -120));
      await tester.pump();
      await tester.tap(box);
      await tester.pump();
      final keyboard = size.width > size.height ? 180.0 : 300.0;
      _keyboard(tester, keyboard);
      await server.wait(tester, const Duration(milliseconds: 600));
      expect(_hasFocus(tester, box), isTrue);
      expect(tester.getRect(box).bottom, lessThanOrEqualTo(size.height - keyboard + 0.5),
          reason: 'the box the user types in is under the keyboard');
      unawaited(rooms.leave());
      await server.wait(tester, const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
      await server.wait(tester, const Duration(seconds: 6));
    });
  }

  testWidgets("the docked room doesn't take the keyboard from the screen beside it (a screen's letter keys keep "
      'working when the room docks)', (tester) async {
    _size(tester, const Size(1280, 800));
    final server = TestServer();
    final rooms = RoomService(settings: AppSettings()..nickname = 'Ann');
    var presses = 0;
    await tester.pumpWidget(roomApp(const HomeScreen(), rooms: rooms));
    unawaited(rooms.navigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => _KeyPage(onN: () => presses++))));
    await _frames(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    expect(presses, 1, reason: 'the page has the keyboard');
    // The room appears beside the page (docked).
    await _enterRoom(tester, server, rooms);
    await _frames(tester);
    expect(rooms.shellMode, RoomShellMode.docked);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    expect(presses, 2, reason: "the page's keys still work with the room docked beside it");
    unawaited(rooms.leave());
    await server.wait(tester, const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a desktop window widened past 960 px (rail to dock) keeps the keyboard on the screen', (tester) async {
    _size(tester, const Size(900, 600));
    final server = TestServer();
    final rooms = RoomService(settings: AppSettings()..nickname = 'Ann');
    var presses = 0;
    await tester.pumpWidget(roomApp(const HomeScreen(), rooms: rooms));
    await _enterRoom(tester, server, rooms);
    expect(rooms.shellMode, RoomShellMode.rail);
    unawaited(rooms.navigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => _KeyPage(onN: () => presses++))));
    await _frames(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    expect(presses, 1);
    _size(tester, const Size(1280, 800));
    await _frames(tester);
    expect(rooms.shellMode, RoomShellMode.docked);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    expect(presses, 2, reason: "the page's keys still work after the room docks");
    unawaited(rooms.leave());
    await server.wait(tester, const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
  });
}
