import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/main.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/engine/actions.dart';
import 'package:pokerfection/src/gto/gto_solutions.dart';
import 'package:pokerfection/src/gto/preflop/preflop_equity.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/online/online_client.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/ui/decision_panel.dart';
import 'package:pokerfection/src/ui/online/room_game_frame.dart';
import 'package:pokerfection/src/ui/online/room_panel.dart';
import 'package:pokerfection/src/ui/online/room_scope.dart';
import 'package:pokerfection/src/ui/online/spectator_coach.dart';
import 'package:pokerfection/src/ui/table_controller.dart';
import 'package:pokerfection/src/ui/table_screen.dart';

import '../kit/shots.dart';
import '../widget_test.dart' show setScreen, testSolutions;
import 'room_kit.dart';

/// The room's game on screen (poker): the table with the Game and Room
/// tabs, for a spectator (the coach, off until asked for) and a seated
/// player (the choices); who sees which cards; Leave seat; and the chat
/// in the Room tab, whose typing never plays a move.

final _en = S.forLanguage(AppLanguage.english);

/// The app for [name] at [size], with its room.
Future<RoomService> _app(WidgetTester tester, {String name = 'Ann', Size size = const Size(1280, 800), GtoSolutions? solutions}) async {
  setScreen(tester, size);
  final settings = AppSettings()
    ..nickname = name
    ..speed = PlaybackSpeed.instant;
  final rooms = RoomService(settings: settings, solutions: solutions ?? testSolutions());
  await tester.pumpWidget(PokerFectionApp(settings: settings, rooms: rooms, newJobs: () => Jobs.inline()));
  await tester.pump();
  return rooms;
}

/// Lets animations run, and the server's time with them.
Future<void> _settle(WidgetTester tester, TestServer server) => server.wait(tester, const Duration(milliseconds: 600));

/// Scrolls [finder] into view and taps it.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

/// Scrolls the room's panel until [finder] is built and shows.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.dragUntilVisible(finder, find.byKey(const ValueKey('room panel')), const Offset(0, -120));
  await tester.pump();
}

/// Guests who play by themselves, seated.
Future<List<AutoGuest>> _players(WidgetTester tester, TestServer server, String code, List<String> names, {Duration think = Duration.zero}) async {
  final guests = [for (final name in names) AutoGuest(server, name, think: think)];
  for (final guest in guests) {
    guest.join(code);
    await server.until(tester, () => guest.room != null, '${guest.name} in');
    guest.send(const TakeSeat());
    await server.until(tester, () => guest.room?.me?.seat != null, '${guest.name} seated');
  }
  return guests;
}

/// [rooms]'s user hosts a Hold'em room on [server] (a spectator, as everyone enters).
Future<OnlineClient> _host(WidgetTester tester, TestServer server, RoomService rooms, {int seats = 3, Map<int, String> bots = const {}, HelpLevel help = HelpLevel.none}) async {
  final own = server.client(record: true);
  await server.open(
    tester,
    own,
    CreateRoom(name: 'Ann', game: holdemKey, settings: RoomSettings(seats: seats, stackBb: 20, resetStacks: true, help: help), bots: bots),
  );
  rooms.enter(own);
  await tester.pump();
  return own;
}

bool _atTable() => find.byType(TableScreen).evaluate().isNotEmpty;

/// The action buttons of a player's turn.
bool _actionButtons() => [
  'quick fold',
  'quick call',
  'quick raise',
  'play',
].any((key) => find.byKey(ValueKey(key), skipOffstage: false).evaluate().isNotEmpty);

Future<void> _end(WidgetTester tester, TestServer server, RoomService rooms) async {
  unawaited(rooms.leave());
  await server.wait(tester, const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox());
  await server.wait(tester, const Duration(seconds: 6));
}

void main() {
  setUpAll(loadShotFonts);

  testWidgets("a spectator's table: the Game tab (the coach starts off: its button and the chip turn it on) and the "
      'Room tab, which shows how many messages came while the Game tab was on', (tester) async {
    final server = TestServer();
    final rooms = await _app(tester);
    final own = await _host(tester, server, rooms);
    final players = await _players(tester, server, own.room!.code, ['Cy', 'Di'], think: const Duration(seconds: 1));
    await _tap(tester, find.byKey(const ValueKey('start')));
    await server.until(tester, _atTable, 'at the table');
    await _settle(tester, server);
    final table = rooms.table!;
    expect(table.spectating, isTrue);
    expect(find.byType(RoomGameFrame), findsOneWidget);
    expect(find.byKey(const ValueKey('game tab')), findsOneWidget);
    expect(find.byKey(const ValueKey('room tab')), findsOneWidget);
    expect(find.byType(SpectatorPanel), findsOneWidget);
    expect(_actionButtons(), isFalse);

    // The coach is off: the Game tab offers it, and so does the chip.
    expect(table.coachOn, isFalse);
    expect(tester.widget<FilterChip>(find.byKey(const ValueKey('coach chip'))).selected, isFalse);
    expect(find.byKey(const ValueKey('coach on')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('coach on')));
    await _settle(tester, server);
    expect(table.coachOn, isTrue);
    expect(tester.widget<FilterChip>(find.byKey(const ValueKey('coach chip'))).selected, isTrue);
    expect(find.byKey(const ValueKey('coach on')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('coach chip')));
    await _settle(tester, server);
    expect(table.coachOn, isFalse);
    expect(find.byKey(const ValueKey('coach on')), findsOneWidget);

    // Chat while the Game tab shows: the Room tab says how many.
    players.first.send(const Say('nice hand'));
    players.last.send(const Say('ty'));
    await _settle(tester, server);
    final badge = find.descendant(of: find.byKey(const ValueKey('room tab')), matching: find.byKey(const ValueKey('unread')));
    expect(badge, findsOneWidget);
    expect(find.descendant(of: badge, matching: find.text('2')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('room tab')));
    await _settle(tester, server);
    expect(badge, findsNothing);
    expect(find.byType(RoomPanel), findsOneWidget);
    // In the Room tab's chat (the table's note may still show it too).
    final line = find.descendant(of: find.byType(RoomPanel), matching: find.textContaining('nice hand'));
    await _reveal(tester, line);
    expect(line, findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('game tab')));
    await _settle(tester, server);
    expect(find.byType(SpectatorPanel), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _end(tester, server, rooms);
  });

  testWidgets("the host spectating with GTO bots (one in seat 0) and a guest: the deal waits for the host's solve; "
      "no action buttons on the host's screen; with the switch off, a bot's turn shows \"—\" and no bot card face "
      "up; the guest's cards show and the coach answers for them", (tester) async {
    final server = TestServer();
    final slow = GtoSolutions(
      iterations: 30,
      postflopIterations: 5,
      inBackground: false,
      loadEquity: () async {
        await Future<void>.delayed(const Duration(seconds: 2));
        return PreflopEquity.fromBytes(ByteData.sublistView(File('assets/preflop_equity.bin').readAsBytesSync()));
      },
    );
    final rooms = await _app(tester, solutions: slow);
    final own = await _host(tester, server, rooms, bots: const {0: 'gto', 1: 'gto'});
    final cy = (await _players(tester, server, own.room!.code, ['Cy'], think: const Duration(seconds: 3))).single;
    final link = server.links.first;
    int? readyAt, dealtAt;
    void note() {
      readyAt ??= link.sent.any((m) => m.contains('"t":"ready"')) ? server.clock.nowMs : null;
      dealtAt ??= cy.seen.whereType<HandDealt>().isNotEmpty ? server.clock.nowMs : null;
    }

    await _tap(tester, find.byKey(const ValueKey('start')));
    await server.until(tester, () {
      note();
      return dealtAt != null;
    }, 'the deal');
    expect(readyAt, isNotNull);
    expect(dealtAt!, greaterThanOrEqualTo(readyAt!), reason: "the first hand has no wait of its own: it waited for the host's Ready");
    await _settle(tester, server);
    expect(_atTable(), isTrue);
    final table = rooms.table!;
    expect(table.spectating, isTrue);
    await tester.tap(find.byKey(const ValueKey('coach chip')));

    var botTurns = 0, cyAnswers = 0;
    for (var step = 0; step < 1500 && (botTurns < 2 || cyAnswers < 1); step++) {
      await server.wait(tester);
      expect(_actionButtons(), isFalse, reason: "the host doesn't play");
      final seat = table.view.actingSeat;
      if (seat == null || table.handOver) continue;
      final acting = table.view.seats[seat];
      for (final other in table.view.seats.where((v) => v.info.isBot)) {
        expect(other.faceUp, isFalse, reason: "a bot's cards stay hidden (the switch is off)");
      }
      if (acting.info.isBot) {
        if (find.byKey(const ValueKey('coach hidden')).evaluate().isNotEmpty) botTurns++;
      } else {
        expect(acting.faceUp, isTrue, reason: "a person's cards show to spectators");
        if (find.byKey(const ValueKey('coach answer')).evaluate().isNotEmpty) cyAnswers++;
      }
    }
    expect(botTurns, greaterThanOrEqualTo(2), reason: 'a bot\'s turn shows "—"');
    expect(cyAnswers, greaterThanOrEqualTo(1), reason: "the coach answers for the guest's turn");
    await server.until(tester, () => link.sent.any((m) => m.contains('"t":"botAct"')), "the host's app plays the bots");
    expect(tester.takeException(), isNull);
    await _end(tester, server, rooms);
  });

  testWidgets('Join game during a hand: queued (no Sit out or Rebuy offered meanwhile), then dealt the next hand, '
      'with the choices in the Game tab', (tester) async {
    final server = TestServer();
    final host = server.client();
    await server.open(tester, host, const CreateRoom(name: 'Ann', game: holdemKey, settings: RoomSettings(seats: 3, stackBb: 20, resetStacks: true)));
    final code = host.room!.code;
    await _players(tester, server, code, ['Cy', 'Di'], think: const Duration(seconds: 2));
    final rooms = await _app(tester, name: 'Ben');
    final ben = server.client(record: true);
    await server.open(tester, ben, JoinRoom(code: code, name: 'Ben'));
    rooms.enter(ben);
    host.send(const StartGame());
    await server.until(tester, () => rooms.gameRunning && !rooms.table!.handOver, 'a hand on');
    await _settle(tester, server);
    expect(_atTable(), isTrue);
    final table = rooms.table!;
    // A guest's coach starts off too.
    expect(table.coachOn, isFalse);
    expect(find.byKey(const ValueKey('coach on')), findsOneWidget);
    await _tap(tester, find.descendant(of: find.byType(SpectatorPanel), matching: find.byKey(const ValueKey('join game'))));
    await server.until(tester, () => ben.queuedSeat != null, 'queued');
    expect(table.spectating, isTrue);
    expect(table.canSitOut, isFalse);
    expect(table.canRebuy, isFalse);
    await tester.tap(find.byIcon(Icons.menu));
    await _settle(tester, server);
    final sitOut = tester.widget<PopupMenuItem<String>>(
      find.ancestor(of: find.text(_en.sitOut), matching: find.byType(PopupMenuItem<String>)),
    );
    expect(sitOut.enabled, isFalse, reason: 'greyed out while waiting for the seat');
    await tester.tapAt(const Offset(10, 400));
    await _settle(tester, server);
    // The leave-seat button while queued (and no Rebuy).
    expect(find.byKey(const ValueKey('rebuy')), findsNothing);
    expect(find.descendant(of: find.byType(SpectatorPanel), matching: find.byKey(const ValueKey('leave seat'))), findsOneWidget);

    await server.until(tester, () => !table.spectating && !table.handOver, 'dealt in');
    await _settle(tester, server);
    expect(find.byType(DecisionPanel), findsOneWidget);
    expect(find.byType(SpectatorPanel), findsNothing);
    expect(find.byKey(const ValueKey('coach chip')), findsNothing);
    expect(ben.mySeat, isNotNull);
    expect(tester.takeException(), isNull);
    await _end(tester, server, rooms);
  });

  testWidgets('a seated player: typing "fcn" and Enter in the Room tab\'s chat sends it and plays nothing; Back asks '
      'Leave seat, the table stays through the hand, and goes once the seat is free', (tester) async {
    final server = TestServer();
    final host = server.client();
    await server.open(tester, host, const CreateRoom(name: 'Ann', game: holdemKey, settings: RoomSettings(seats: 3, stackBb: 20, resetStacks: true)));
    final code = host.room!.code;
    await _players(tester, server, code, ['Cy'], think: const Duration(milliseconds: 500));
    final rooms = await _app(tester, name: 'Ben');
    final ben = server.client(record: true);
    await server.open(tester, ben, JoinRoom(code: code, name: 'Ben'));
    rooms.enter(ben);
    ben.send(const TakeSeat());
    await server.until(tester, () => ben.mySeat != null, 'seated');
    host.send(const StartGame());
    await server.until(tester, () => rooms.table?.heroOptions != null, "Ben's turn");
    await _settle(tester, server);
    final table = rooms.table!;
    final link = server.links.last;
    int acts() => link.sent.where((m) => m.contains('"t":"act"')).length;
    final before = acts();
    final hand = table.handNumber;

    await tester.tap(find.byKey(const ValueKey('room tab')));
    await _settle(tester, server);
    final box = find.byKey(const ValueKey('chat box'));
    await _reveal(tester, box);
    await tester.tap(box);
    await tester.pump();
    for (final key in [LogicalKeyboardKey.keyF, LogicalKeyboardKey.keyC, LogicalKeyboardKey.keyN, LogicalKeyboardKey.enter]) {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }
    await tester.enterText(box, 'fcn');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await _settle(tester, server);
    expect(ben.chat.map((l) => l.text), contains('fcn'));
    expect(acts(), before, reason: 'no fold, no call');
    expect(table.heroOptions, isNotNull, reason: 'still their turn');
    expect(table.handNumber, hand, reason: 'no next hand');

    // Back: asked first.
    await tester.tap(find.byKey(const ValueKey('game tab')));
    await _settle(tester, server);
    await tester.binding.handlePopRoute();
    await _settle(tester, server);
    expect(find.text(_en.leaveSeatQuestion), findsOneWidget);
    expect(find.text(_en.leaveSeatWarning), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('leave seat sure')));
    await _settle(tester, server);
    expect(_atTable(), isTrue, reason: 'the hand is played out first');
    // They play the hand out; the table goes once the seat is free.
    for (var step = 0; step < 600 && _atTable(); step++) {
      await server.wait(tester);
      final options = rooms.table?.heroOptions;
      if (options != null) {
        await rooms.table!.heroAct(options.canCheck ? const PlayerAction.check() : const PlayerAction.call());
      }
    }
    await _settle(tester, server);
    expect(_atTable(), isFalse);
    expect(ben.mySeat, isNull);
    expect(rooms.stage, RoomStage.open, reason: 'still in the room');
    expect(rooms.gameRunning, isTrue, reason: 'the game goes on');
    await _end(tester, server, rooms);
  });

  // The seated player's Game tab at phone sizes, in every mode of help and language.
  for (final help in [HelpLevel.none, HelpLevel.simple, HelpLevel.advanced]) {
    testWidgets("the seated player's Game tab fits a phone's 280 px panel (${help.name})", (tester) async {
      final server = TestServer();
      final own = server.client();
      await server.open(
        tester,
        own,
        CreateRoom(name: 'Ann', game: holdemKey, settings: RoomSettings(seats: 3, stackBb: 20, resetStacks: true, help: help)),
      );
      await _players(tester, server, own.room!.code, ['Cy', 'Di'], think: const Duration(seconds: 1));
      own.send(const TakeSeat());
      await server.until(tester, () => own.mySeat != null, 'seated');
      NextHand? first;
      own.attach((m) => first ??= m is NextHand ? m : null);
      own.send(const StartGame());
      await server.until(tester, () => first != null, 'the first hand');
      own.detach();
      final controller = OnlineTableController(own, first!, speed: PlaybackSpeed.instant, solutions: testSolutions());
      await tester.pumpWidget(MaterialApp(home: TableScreen.online(controller: controller, ownsController: false)));
      await server.until(tester, () => controller.heroOptions != null, 'their turn');
      await server.wait(tester, const Duration(seconds: 1));
      for (final language in AppLanguage.values) {
        for (final size in const [Size(568, 320), Size(640, 360), Size(390, 844)]) {
          await pumpShot(tester, TableScreen.online(controller: controller, ownsController: false), size: size, language: language);
          await tester.pump();
          await tester.pump();
          await shot(tester, 'seated_${help.name}_${shotTag(size, language)}');
          expect(tester.takeException(), isNull, reason: '${help.name} ${shotTag(size, language)}');
          expect(find.byType(DecisionPanel), findsOneWidget);
        }
      }
      await tester.pumpWidget(const SizedBox());
      controller.handBack();
      controller.dispose();
      unawaited(own.close());
      await server.wait(tester, const Duration(seconds: 1));
    });
  }
}
