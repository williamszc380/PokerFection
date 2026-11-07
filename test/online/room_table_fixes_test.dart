/// The room's table and Home, as fixed after the v2.1 review: the felt's
/// seats light up under the mouse, the Room tab keeps the chat box above
/// the keyboard, the screen beside the dock keeps its keys after following
/// the host and coming back, the host's room setup never sends older rules,
/// Home gives the solo games back once the room ends, a guest's chat draft
/// and tab outlast the game starting, and the table keeps clear of a notch.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/main.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/online/games/online_games.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/ui/game_menu.dart';
import 'package:pokerfection/src/ui/games.dart';
import 'package:pokerfection/src/ui/online/room_lobby_screen.dart';
import 'package:pokerfection/src/ui/online/room_scope.dart';
import 'package:pokerfection/src/ui/online/room_shell.dart';
import 'package:pokerfection/src/ui/setup_screen.dart';
import 'package:pokerfection/src/ui/table_controller.dart';
import 'package:pokerfection/src/ui/table_screen.dart';

import '../kit/shots.dart' show loadShotFonts;
import '../server/fake_runner.dart';
import '../widget_test.dart' show setScreen, testSolutions;
import 'fake_runner_ui.dart';
import 'room_kit.dart';

final _boundary = GlobalKey();

Future<RoomService> _app(WidgetTester tester, String name, Size size, {HighCardGame? game}) async {
  setScreen(tester, size);
  final settings = AppSettings()
    ..nickname = name
    ..speed = PlaybackSpeed.instant;
  final rooms = RoomService(
    settings: settings,
    solutions: testSolutions(),
    gameUis: game == null ? null : {game.key: HighCardUi(game)},
    newJobs: game == null ? null : highCardInlineJobs,
  );
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      child: PokerFectionApp(settings: settings, rooms: rooms, newJobs: () => Jobs.inline()),
    ),
  );
  await tester.pump();
  return rooms;
}

Future<void> _settle(WidgetTester tester, TestServer server) => server.wait(tester, const Duration(milliseconds: 800));

Future<void> _done(WidgetTester tester, TestServer server, List<RoomService> rooms) async {
  for (final r in rooms) {
    unawaited(r.leave());
  }
  await server.wait(tester, const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox());
  await server.wait(tester, const Duration(seconds: 6));
}

Future<Uint8List> _pixels(WidgetTester tester) async {
  late Uint8List bytes;
  await tester.runAsync(() async {
    final boundary = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  });
  return bytes;
}

/// The biggest change of one colour channel inside [rect] between [a] and [b] (an image [width] wide).
int _maxDiff(Uint8List a, Uint8List b, Rect rect, int width) {
  var most = 0;
  for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
    for (var x = rect.left.ceil(); x < rect.right.floor(); x++) {
      final i = (y * width + x) * 4;
      for (var c = 0; c < 3; c++) {
        final d = (a[i + c] - b[i + c]).abs();
        if (d > most) most = d;
      }
    }
  }
  return most;
}

bool _hasFocus(WidgetTester tester, Finder box) => tester
    .state<EditableTextState>(find.descendant(of: box, matching: find.byType(EditableText)))
    .widget
    .focusNode
    .hasFocus;

/// A screen with a letter key, as the solo table and the kit's games have them.
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

  testWidgets("the host's empty seats on the room's felt light up under the mouse (a guest's Sit seat does)", (
    tester,
  ) async {
    final server = TestServer();
    const size = Size(1280, 800);
    final ann = await _app(tester, 'Ann', size);
    final own = server.client();
    await server.open(
      tester,
      own,
      const CreateRoom(name: 'Ann', game: holdemKey, settings: RoomSettings(seats: 4, stackBb: 20, resetStacks: true)),
    );
    ann.enter(own);
    await _settle(tester, server);
    expect(find.byType(RoomLobbyScreen), findsOneWidget);
    final seat = find.byKey(const ValueKey('table seat 1'));
    expect(seat, findsOneWidget);
    final rect = tester.getRect(seat);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(2, 2));
    await tester.pump(const Duration(milliseconds: 300));
    final before = await _pixels(tester);
    await mouse.moveTo(rect.center);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    final after = await _pixels(tester);
    final hostChange = _maxDiff(before, after, rect.deflate(3), size.width.toInt());
    await mouse.moveTo(const Offset(2, 2));
    await tester.pump(const Duration(milliseconds: 300));

    // A guest's empty seat (Sit) for comparison.
    final ben = await _app(tester, 'Ben', size);
    final benClient = server.client();
    await server.open(tester, benClient, JoinRoom(code: own.room!.code, name: 'Ben'));
    ben.enter(benClient);
    await _settle(tester, server);
    final sit = find.byKey(const ValueKey('table seat 2'));
    final sitRect = tester.getRect(sit);
    final before2 = await _pixels(tester);
    await mouse.moveTo(sitRect.center);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    final after2 = await _pixels(tester);
    final guestChange = _maxDiff(before2, after2, sitRect.deflate(3), size.width.toInt());
    await mouse.removePointer();
    // ignore: avoid_print
    print('hover change: host empty seat $hostChange, guest Sit seat $guestChange');
    expect(guestChange, greaterThan(12), reason: "the guest's seat lights up");
    expect(
      hostChange,
      greaterThan(12),
      reason: "the host's empty seat (Sit / Add Bot) doesn't light up under the mouse",
    );
    await _done(tester, server, [ann, ben]);
  });

  for (final size in const [Size(568, 320), Size(390, 844)]) {
    testWidgets("before the game (${size.width.toInt()}x${size.height.toInt()}): the room's table's Room tab keeps the "
        'chat box above the keyboard', (tester) async {
      final server = TestServer();
      final ben = await _app(tester, 'Ben', size);
      final own = server.client();
      await server.open(
        tester,
        own,
        const CreateRoom(name: 'Ann', game: holdemKey, settings: RoomSettings(seats: 4, stackBb: 20)),
      );
      final benClient = server.client();
      await server.open(tester, benClient, JoinRoom(code: own.room!.code, name: 'Ben'));
      ben.enter(benClient);
      await _settle(tester, server);
      expect(find.byType(RoomLobbyScreen), findsOneWidget, reason: 'Ben followed to the seats');
      await tester.tap(find.byKey(const ValueKey('room tab')));
      await _settle(tester, server);
      final box = find.byKey(const ValueKey('chat box'));
      await tester.dragUntilVisible(box, find.byKey(const ValueKey('room panel')), const Offset(0, -120));
      await tester.pump();
      await tester.tap(box);
      await tester.pump();
      final keyboard = size.width > size.height ? 180.0 : 300.0;
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      await _settle(tester, server);
      expect(_hasFocus(tester, box), isTrue);
      expect(
        tester.getRect(box).bottom,
        lessThanOrEqualTo(size.height - keyboard + 0.5),
        reason: 'the chat box the guest types in is under the keyboard',
      );
      tester.view.resetViewInsets();
      await _done(tester, server, [ben]);
    });
  }

  testWidgets("a PC: a guest's screen keeps its keys after following the host to the room's table and coming back "
      '(Back)', (tester) async {
    final server = TestServer();
    final ben = await _app(tester, 'Ben', const Size(1280, 800));
    final own = server.client();
    await server.open(tester, own, const CreateRoom(name: 'Ann'));
    final benClient = server.client();
    await server.open(tester, benClient, JoinRoom(code: own.room!.code, name: 'Ben'));
    ben.enter(benClient);
    await _settle(tester, server);
    var presses = 0;
    unawaited(
      ben.navigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => _KeyPage(onN: () => presses++))),
    );
    await _settle(tester, server);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    expect(presses, 1, reason: 'the page has the keys');
    // The host opens Hold'em: Ben follows; then he goes back to his page.
    own.send(const ChooseGame(game: holdemKey));
    await _settle(tester, server);
    expect(find.byType(RoomLobbyScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await _settle(tester, server);
    expect(find.byType(_KeyPage), findsOneWidget);
    expect(ben.shellMode, RoomShellMode.docked);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    expect(
      presses,
      2,
      reason: "back from the room's table, the page's keys no longer work (the docked room took them)",
    );
    await _done(tester, server, [ben]);
  });

  testWidgets("the host's Hold'em setup left under the room's table: back to it and Open Table again doesn't undo the "
      "rules changed on the table", (tester) async {
    final server = TestServer();
    final ann = await _app(tester, 'Ann', const Size(1280, 800));
    final own = server.client();
    await server.open(tester, own, const CreateRoom(name: 'Ann'));
    ann.enter(own);
    await _settle(tester, server);
    unawaited(
      ann.navigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => GameMenu(game: games.first))),
    );
    await _settle(tester, server);
    unawaited(ann.navigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => const SetupScreen())));
    await _settle(tester, server);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('open table')),
      200,
      scrollable: find
          .descendant(of: find.byKey(const ValueKey('room setup')), matching: find.byType(Scrollable))
          .first,
    );
    await tester.tap(find.byKey(const ValueKey('open table')));
    await _settle(tester, server);
    expect(find.byType(RoomLobbyScreen), findsOneWidget);
    final first = own.room!.settings!;
    // On the table's Rules the host doubles the stack (as the Rules tile sends it).
    own.send(ChangeSettings(settings: first.copyWith(stackBb: first.stackBb * 2)));
    await _settle(tester, server);
    expect(own.room!.settings!.stackBb, first.stackBb * 2);
    // Back (to the setup under the table), then Open Table again.
    await tester.binding.handlePopRoute();
    await _settle(tester, server);
    expect(find.byKey(const ValueKey('room setup')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('open table')),
      200,
      scrollable: find
          .descendant(of: find.byKey(const ValueKey('room setup')), matching: find.byType(Scrollable))
          .first,
    );
    await tester.tap(find.byKey(const ValueKey('open table')));
    await _settle(tester, server);
    expect(
      own.room!.settings!.stackBb,
      first.stackBb * 2,
      reason: "the setup still shows the rules it was opened with and sends them back: the table's change is undone",
    );
    await _done(tester, server, [ann]);
  });

  testWidgets('the room ended (the host closed it): Home gives the solo games back at once', (tester) async {
    // A room that doesn't run Gomoku (a room from an older build, say), so
    // Home greys Gomoku out while Ben is in it.
    final server = TestServer(games: {...onlineGames}..remove(GameId.gomoku.key));
    final ben = await _app(tester, 'Ben', const Size(1280, 800));
    final own = server.client();
    await server.open(tester, own, const CreateRoom(name: 'Ann'));
    final benClient = server.client();
    await server.open(tester, benClient, JoinRoom(code: own.room!.code, name: 'Ben'));
    ben.enter(benClient);
    await _settle(tester, server);
    expect(find.byKey(const ValueKey('online soon gomoku')), findsOneWidget, reason: 'greyed in the room');
    unawaited(own.close(leave: true));
    await server.wait(tester, const Duration(seconds: 2));
    expect(ben.stage, RoomStage.ended);
    expect(
      find.byKey(const ValueKey('online soon gomoku')),
      findsNothing,
      reason: 'the room is over, yet Gomoku stays greyed out "Online soon" until OK on its card',
    );
    await _done(tester, server, [ben]);
  });

  testWidgets("a guest typing in the room's table's Room tab keeps the text (and the tab) when the host starts", (
    tester,
  ) async {
    final server = TestServer();
    final ben = await _app(tester, 'Ben', const Size(1280, 800));
    final own = server.client();
    await server.open(
      tester,
      own,
      const CreateRoom(name: 'Ann', game: holdemKey, settings: RoomSettings(seats: 3, stackBb: 20, resetStacks: true)),
    );
    final benClient = server.client();
    await server.open(tester, benClient, JoinRoom(code: own.room!.code, name: 'Ben'));
    ben.enter(benClient);
    await _settle(tester, server);
    own.send(const AddBot(style: 'gto'));
    own.send(const AddBot(style: 'gto'));
    await server.until(tester, () => own.room!.taken == 2, 'bots');
    await tester.tap(find.byKey(const ValueKey('room tab')));
    await _settle(tester, server);
    final box = find.byKey(const ValueKey('chat box'));
    await tester.ensureVisible(box);
    await tester.tap(box);
    await tester.enterText(box, 'one sec, getting');
    await tester.pump();
    own.send(const StartGame());
    await server.until(tester, () => find.byType(TableScreen).evaluate().isNotEmpty, 'the game');
    await _settle(tester, server);
    final boxes = find.byKey(const ValueKey('chat box'), skipOffstage: false);
    final texts = [for (final e in boxes.evaluate()) (e.widget as TextField).controller?.text];
    expect(texts, contains('one sec, getting'), reason: 'what Ben was typing is gone when the game starts');
    expect(
      tester.widget<TabBar>(find.byType(TabBar)).controller!.index,
      1,
      reason: 'the Room tab Ben had open went back to the Game tab',
    );
    await _done(tester, server, [ben]);
  });

  testWidgets("an iPhone held sideways (844x390, the notch's safe area 47 each side): the room's table keeps its seats "
      'and buttons clear of the notch', (tester) async {
    final server = TestServer();
    tester.view.padding = const FakeViewPadding(left: 47, right: 47, bottom: 21);
    tester.view.viewPadding = const FakeViewPadding(left: 47, right: 47, bottom: 21);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    final ann = await _app(tester, 'Ann', const Size(844, 390));
    final own = server.client();
    await server.open(
      tester,
      own,
      const CreateRoom(name: 'Ann', game: holdemKey, settings: RoomSettings(seats: 4, stackBb: 20)),
    );
    ann.enter(own);
    await _settle(tester, server);
    own.send(const AddBot(style: 'gto', seat: 1));
    await server.until(tester, () => own.room!.taken == 1, 'a bot');
    await _settle(tester, server);
    expect(find.byType(RoomLobbyScreen), findsOneWidget);
    final problems = <String>[];
    void inside(String what, Finder finder) {
      final r = tester.getRect(finder);
      if (r.left < 47 || r.right > 844 - 47 || r.bottom > 390 - 21) problems.add('$what at $r');
    }

    inside('the bot on the felt (seat 1)', find.byKey(const ValueKey('table seat 1')));
    inside("the bot's × on the felt", find.byKey(const ValueKey('table remove bot 1')));
    inside("the seat list's ×", find.byKey(const ValueKey('remove bot 1')));
    inside('Start', find.byKey(const ValueKey('start')));
    expect(problems, isEmpty, reason: 'under the notch');
    await _done(tester, server, [ann]);
  });

  /// The members' rows of the room's People list.
  Finder memberRows() => find.byWidgetPredicate(
    (w) => switch (w.key) {
      ValueKey<String>(:final value) => value.startsWith('member '),
      _ => false,
    },
  );

  /// The rows of [rows] wholly inside the room panel's people list (above the pinned chat).
  int shownRows(WidgetTester tester, Finder rows) {
    final list = tester.getRect(
      find.descendant(of: find.byKey(const ValueKey('room panel')), matching: find.byType(Scrollable)).first,
    );
    return [
      for (final e in rows.evaluate())
        if (list.contains(tester.getRect(find.byWidget(e.widget)).topLeft) &&
            tester.getRect(find.byWidget(e.widget)).bottom <= list.bottom + 0.5)
          e,
    ].length;
  }

  Future<(TestServer, RoomService)> fiveInRoom(WidgetTester tester, Size size) async {
    final server = TestServer();
    final ann = await _app(tester, 'Ann', size);
    final own = server.client();
    await server.open(tester, own, const CreateRoom(name: 'Ann'));
    ann.enter(own);
    for (final name in ['Ben', 'Cy', 'Dee', 'Eve']) {
      AutoGuest(server, name).join(own.room!.code);
    }
    await server.until(tester, () => own.room!.members.length == 5, 'everyone in');
    await _settle(tester, server);
    return (server, ann);
  }

  testWidgets('a PC (1280x800): the docked lobby shows all five people above the chat, not two', (tester) async {
    final (server, ann) = await fiveInRoom(tester, const Size(1280, 800));
    expect(ann.shellMode, RoomShellMode.docked);
    expect(memberRows(), findsNWidgets(5));
    expect(shownRows(tester, memberRows()), 5, reason: 'the pinned chat pushes people below the fold');
    await _done(tester, server, [ann]);
  });

  testWidgets("an upright browser (390x844): the bar's lobby shows most of the people, not one cut row", (
    tester,
  ) async {
    final (server, ann) = await fiveInRoom(tester, const Size(390, 844));
    expect(ann.shellMode, RoomShellMode.bar);
    ann.openPanel();
    await _settle(tester, server);
    expect(shownRows(tester, memberRows()), greaterThanOrEqualTo(3), reason: 'People squeezed by the pinned chat');
    await _done(tester, server, [ann]);
  });

  for (final host in [false, true]) {
    testWidgets("the smallest phone (568x320) in Spanish: the felt's empty seat says Sit in full "
        '(${host ? 'the host' : 'a guest'})', (tester) async {
      final server = TestServer();
      final rooms = await _app(tester, host ? 'Ann' : 'Ben', const Size(568, 320));
      rooms.settings.update((s) => s.language = AppLanguage.spanish);
      await tester.pump();
      final own = server.client();
      await server.open(
        tester,
        own,
        const CreateRoom(name: 'Ann', game: holdemKey, settings: RoomSettings(seats: 4, stackBb: 20)),
      );
      if (host) {
        rooms.enter(own);
      } else {
        final client = server.client();
        await server.open(tester, client, JoinRoom(code: own.room!.code, name: 'Ben'));
        rooms.enter(client);
      }
      await _settle(tester, server);
      expect(find.byType(RoomLobbyScreen), findsOneWidget);
      final sit = S.forLanguage(AppLanguage.spanish).sit;
      final word = find.descendant(of: find.byKey(const ValueKey('table seat 2')), matching: find.text(sit));
      expect(word, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(word);
      expect(paragraph.didExceedMaxLines, isFalse, reason: '"$sit" is cut short');
      final seat = tester.getRect(find.byKey(const ValueKey('table seat 2')));
      final text = tester.getRect(word);
      expect(seat.left <= text.left && text.right <= seat.right, isTrue, reason: '"$sit" at $text in $seat');
      await _done(tester, server, [rooms]);
    });
  }
}
