import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/main.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/online/games/online_games.dart';
import 'package:pokerfection/src/online/online_client.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/ui/game_menu.dart';
import 'package:pokerfection/src/ui/games.dart';
import 'package:pokerfection/src/ui/home_screen.dart';
import 'package:pokerfection/src/ui/online/online_game_uis.dart';
import 'package:pokerfection/src/ui/online/room_lobby_screen.dart';
import 'package:pokerfection/src/ui/online/room_panel.dart';
import 'package:pokerfection/src/ui/online/room_scope.dart';
import 'package:pokerfection/src/ui/setup_screen.dart';
import 'package:pokerfection/src/ui/table_controller.dart';
import 'package:pokerfection/src/ui/table_screen.dart';

import '../server/fake_runner.dart';
import '../widget_test.dart' show setScreen, testSolutions;
import 'fake_runner_ui.dart';
import 'room_kit.dart';

/// Rooms v2.1: the host picks games the usual way (Home, the game's menu,
/// Hold'em's setup), the guests follow the host to the room's table from
/// wherever they are, Home greys out the games not played online while in
/// a room, and the seats and the host's controls are on the room's table.

final _en = S.forLanguage(AppLanguage.english);

/// The app at [size] for [name], with its room ([gameUis]: the games other
/// than Hold'em it shows online; the app's registry by default).
Future<RoomService> _app(
  WidgetTester tester, {
  String name = 'Ben',
  Size size = const Size(1280, 800),
  HighCardGame? game,
}) async {
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
  await tester.pumpWidget(PokerFectionApp(settings: settings, rooms: rooms, newJobs: () => Jobs.inline()));
  await tester.pump();
  return rooms;
}

/// [name]'s client in room [code], handed to [rooms] as Play Online does.
Future<OnlineClient> _enter(WidgetTester tester, TestServer server, RoomService rooms, String code, {String name = 'Ben'}) async {
  final client = server.client();
  await server.open(tester, client, JoinRoom(code: code, name: name));
  rooms.enter(client);
  await tester.pump();
  return client;
}

/// Lets the screens' animations run, and the server's time with them.
Future<void> _settle(WidgetTester tester, TestServer server) => server.wait(tester, const Duration(milliseconds: 800));

Future<void> _back(WidgetTester tester, TestServer server) async {
  await tester.binding.handlePopRoute();
  await _settle(tester, server);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

/// The room's table shows the game's seats (no game running).
bool _atSeats() => find.byType(RoomLobbyScreen).evaluate().isNotEmpty;

/// Home's tile for [id] opens its menu.
bool _tileOpens(WidgetTester tester, GameId id) =>
    tester.widget<InkWell>(find.descendant(of: find.byKey(ValueKey('game ${id.name}')), matching: find.byType(InkWell))).onTap !=
    null;

Future<void> _end(WidgetTester tester, TestServer server, List<RoomService> rooms) async {
  for (final r in rooms) {
    unawaited(r.leave());
  }
  await server.wait(tester, const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox());
  await server.wait(tester, const Duration(seconds: 6));
}

void main() {
  testWidgets("Home: out of a room every built game opens; in a room (a guest, or the host) only the games played "
      "online do, the rest greyed out with \"Online soon\"; a game in the online registry is playable, and its "
      "menu's Play makes it the room's game for the host", (tester) async {
    final game = HighCardGame();
    final server = TestServer(games: {game.key: game});
    final ready = [for (final g in games) if (g.ready) g.id];
    expect(ready.length, greaterThan(2), reason: "games besides Hold'em to play and to grey out");
    // A room that runs every game the app has online but Blackjack (a
    // room from an older build, say): Blackjack is greyed out there.
    final realServer = TestServer(games: {...onlineGames}..remove(GameId.blackjack.key));

    // A guest in today's app.
    final rooms = await _app(tester);
    for (final g in games) {
      expect(_tileOpens(tester, g.id), g.ready, reason: '${g.id.name} out of a room');
    }
    expect(find.text(_en.onlineSoon), findsNothing);
    final realHost = realServer.client();
    await realServer.open(tester, realHost, const CreateRoom(name: 'Ann'));
    await _enter(tester, realServer, rooms, realHost.room!.code);
    await _settle(tester, realServer);
    for (final g in games) {
      final online = g.id == GameId.holdem || (onlineGameUis.containsKey(g.id.key) && g.id != GameId.blackjack);
      expect(_tileOpens(tester, g.id), g.ready && online, reason: '${g.id.name} in a room');
      if (g.ready && !online) {
        expect(find.byKey(ValueKey('online soon ${g.id.name}')), findsOneWidget, reason: g.id.name);
      }
    }
    expect(find.byKey(const ValueKey('online soon blackjack')), findsOneWidget, reason: 'the room does not run it');
    expect(find.byKey(const ValueKey('online soon gomoku')), findsNothing, reason: 'registered and run by the room');
    // Out of the room: Home as before.
    unawaited(rooms.leave());
    unawaited(realHost.close());
    await _settle(tester, realServer);
    for (final g in games) {
      expect(_tileOpens(tester, g.id), g.ready, reason: '${g.id.name} out of the room again');
    }
    await tester.pumpWidget(const SizedBox());

    // The host, with High card (it has Gomoku's key) in the registry: that game is playable online too.
    final hostRooms = await _app(tester, name: 'Ann', game: game);
    final own = server.client();
    await server.open(tester, own, const CreateRoom(name: 'Ann'));
    hostRooms.enter(own);
    await _settle(tester, server);
    expect(_tileOpens(tester, GameId.holdem), isTrue);
    expect(_tileOpens(tester, GameId.gomoku), isTrue, reason: 'in the registry, at the version the room runs');
    for (final id in ready.where((id) => id != GameId.holdem && id != GameId.gomoku)) {
      expect(_tileOpens(tester, id), isFalse, reason: id.name);
      expect(find.byKey(ValueKey('online soon ${id.name}')), findsOneWidget, reason: 'not in the registry: ${id.name}');
    }
    await tester.tap(find.byKey(const ValueKey('game gomoku')));
    await _settle(tester, server);
    await tester.tap(find.descendant(of: find.byType(GameMenu), matching: find.byType(FilledButton)).first);
    await server.until(tester, () => own.room!.game?.key == game.key, 'the room plays it');
    await _settle(tester, server);
    expect(_atSeats(), isTrue, reason: "the host is at the room's table");
    expect(find.byType(GameMenu, skipOffstage: false), findsOneWidget, reason: 'the menu under it');
    await _end(tester, server, [hostRooms]);
  });

  testWidgets("a guest follows the host to the room's table from Home, from a game's menu and from a solo game (which "
      "stays under it); Back leaves the table; Start takes the guest to the game", (tester) async {
    final game = HighCardGame();
    final server = TestServer(games: {game.key: game});
    final host = server.client();
    await server.open(tester, host, const CreateRoom(name: 'Ann'));
    final rooms = await _app(tester, game: game);
    await _enter(tester, server, rooms, host.room!.code);
    await _settle(tester, server);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(_atSeats(), isFalse, reason: 'no game yet');

    // From Home.
    host.send(const ChooseGame(game: holdemKey));
    await server.until(tester, _atSeats, 'at the table from Home');
    await _settle(tester, server);
    expect(rooms.gameOnScreen, isTrue);
    expect(tester.widget<Text>(find.byKey(const ValueKey('lobby title'))).data, _en.holdem);
    await _back(tester, server);
    expect(_atSeats(), isFalse);
    expect(find.byType(HomeScreen), findsOneWidget);

    // From a game's menu: the host picks another game.
    unawaited(rooms.navigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => GameMenu(game: games.first))));
    await _settle(tester, server);
    host.send(ChooseGame(game: game.key));
    await server.until(tester, _atSeats, 'at the table from the menu');
    await _settle(tester, server);
    expect(find.byType(GameMenu, skipOffstage: false), findsOneWidget, reason: 'the menu under it');
    await _back(tester, server);
    expect(find.byType(GameMenu), findsOneWidget);

    // From a solo game: a guest's Play is the usual solo game.
    await tester.tap(find.text(_en.play));
    await _settle(tester, server);
    expect(find.byType(SetupScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('room setup')), findsNothing, reason: "a guest's setup is the usual one");
    await tester.scrollUntilVisible(find.text(_en.start), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text(_en.start));
    await _settle(tester, server);
    expect(find.byType(TableScreen), findsOneWidget, reason: 'the solo table');
    host.send(const ChooseGame(game: holdemKey));
    await server.until(tester, _atSeats, 'at the table from the solo game');
    await _settle(tester, server);
    expect(find.byType(TableScreen, skipOffstage: false), findsOneWidget, reason: 'the solo table stays under it');
    await _back(tester, server);
    expect(_atSeats(), isFalse);
    expect(find.byType(TableScreen), findsOneWidget, reason: 'back at the solo table');

    // Start: to the game, over the solo table.
    host.send(const AddBot(style: 'tag'));
    host.send(const AddBot(style: 'tag'));
    await server.until(tester, () => host.room!.taken == 2, 'two bots');
    host.send(const StartGame());
    await server.until(tester, () => rooms.table != null && rooms.gameOnScreen, 'at the game');
    await _settle(tester, server);
    expect(find.byType(TableScreen, skipOffstage: false), findsNWidgets(2), reason: 'the room\'s and, under it, the solo one');
    expect(rooms.table!.spectating, isTrue);
    await _end(tester, server, [rooms]);
  });

  testWidgets("the host's table: Hold'em picked with Home's Play (the room's setup: 3 players), a bot added on an "
      "empty seat of the felt and taken away, a seat taken there and given up in the Game tab, the switch, Start; "
      "during the game Seats and End game on the table's bar; then the seats again; the docked room has only the "
      'people and the chat', (tester) async {
    final server = TestServer();
    final rooms = await _app(tester, name: 'Ann');
    final own = server.client();
    await server.open(tester, own, const CreateRoom(name: 'Ann'));
    rooms.enter(own);
    final cy = AutoGuest(server, 'Cy')..join(own.room!.code);
    await server.until(tester, () => own.room!.members.length == 2, 'Cy in');
    await _settle(tester, server);

    // Home, Hold'em, Play: the room's setup; 3 players; Open Table.
    await tester.tap(find.byKey(const ValueKey('game holdem')));
    await _settle(tester, server);
    await tester.tap(find.text(_en.play));
    await _settle(tester, server);
    final setup = find.byKey(const ValueKey('room setup'));
    expect(setup, findsOneWidget);
    await tester.tap(find.descendant(of: setup, matching: find.text('3')).first);
    // Stacks reset every hand: the game goes on until the host ends it.
    final reset = find.descendant(of: setup, matching: find.text(_en.resetStacks));
    await tester.scrollUntilVisible(reset, 200, scrollable: find.descendant(of: setup, matching: find.byType(Scrollable)));
    await tester.tap(reset);
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('open table')),
      200,
      scrollable: find.descendant(of: setup, matching: find.byType(Scrollable)),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('open table')));
    await server.until(tester, () => own.room!.game?.key == holdemKey, "Hold'em picked");
    await _settle(tester, server);
    expect(_atSeats(), isTrue);
    expect(own.room!.seats, hasLength(3));
    expect(own.room!.settings!.resetStacks, isTrue, reason: "the setup's rules");

    // A bot on seat 0, from the felt; then taken away with its ×.
    await tester.tap(find.byKey(const ValueKey('table seat 0')));
    await _settle(tester, server);
    await tester.tap(find.byKey(const ValueKey('table bot 0')));
    await server.until(tester, () => own.room!.seats[0].kind == SeatKind.bot, 'a bot on seat 0');
    await _settle(tester, server);
    await tester.tap(find.byKey(const ValueKey('table remove bot 0')));
    await server.until(tester, () => own.room!.seats[0].isEmpty, 'the bot gone');
    await _settle(tester, server);

    // The host sits on seat 1 from the felt, then gives it up in the Game tab.
    await tester.tap(find.byKey(const ValueKey('table seat 1')));
    await _settle(tester, server);
    await tester.tap(find.byKey(const ValueKey('table sit 1')));
    await server.until(tester, () => own.mySeat == 1, 'the host seated');
    await _settle(tester, server);
    await _tap(tester, find.byKey(const ValueKey('leave seat')));
    await server.until(tester, () => own.mySeat == null, 'the seat given up');
    await _settle(tester, server);

    // A bot on seat 0 again; Cy sits; the switch.
    await tester.tap(find.byKey(const ValueKey('table seat 0')));
    await _settle(tester, server);
    await tester.tap(find.byKey(const ValueKey('table bot 0')));
    cy.send(const TakeSeat(2));
    await server.until(tester, () => own.room!.taken == 2, 'two seated');
    await _settle(tester, server);
    await _tap(tester, find.byKey(const ValueKey('see bots')));
    await server.until(tester, () => own.room!.seeBots, 'spectators see the bots');

    // Start, in the Game tab.
    await _tap(tester, find.byKey(const ValueKey('start')));
    await server.until(tester, () => rooms.table != null && find.byType(TableScreen).evaluate().isNotEmpty, 'the game');
    await _settle(tester, server);
    expect(rooms.gameOnScreen, isTrue);
    expect(find.byKey(const ValueKey('seats button')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('seats button')));
    await _settle(tester, server);
    expect(find.byKey(const ValueKey('seats sheet')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('seats sheet')), matching: find.byKey(const ValueKey('seat 1'))), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('seats sheet')), matching: find.byKey(const ValueKey('end game'))), findsNothing);
    await tester.tap(find.byKey(const ValueKey('close seats')));
    await _settle(tester, server);
    await tester.tap(find.byKey(const ValueKey('end game')));
    await server.until(tester, () => own.room!.phase == RoomPhase.lobby, 'the game over');
    await server.wait(tester, const Duration(seconds: 5));
    await _settle(tester, server);
    expect(_atSeats(), isTrue, reason: 'the seats again, for the next game');

    // Back on Home: the docked room shows the people and the chat, and Watch; nothing of the game's controls.
    await _back(tester, server);
    final panel = find.byType(RoomPanel);
    expect(panel, findsOneWidget);
    for (final key in ['start', 'end game', 'see bots', 'add bot', 'join game', 'seat 0', 'rules']) {
      expect(find.descendant(of: panel, matching: find.byKey(ValueKey(key))), findsNothing, reason: key);
    }
    expect(find.descendant(of: panel, matching: find.byType(ChoiceChip)), findsNothing);
    expect(find.descendant(of: panel, matching: find.byKey(const ValueKey('watch'))), findsOneWidget);
    expect(find.descendant(of: panel, matching: find.byKey(const ValueKey('person bot 0'))), findsOneWidget);
    expect(find.descendant(of: panel, matching: find.text(_en.chat)), findsOneWidget);
    await _end(tester, server, [rooms]);
  });

  testWidgets("Hold'em's setup while hosting a room whose game is being played: Open Table greyed out, with why",
      (tester) async {
    final server = TestServer();
    final rooms = await _app(tester, name: 'Ann');
    final own = server.client();
    await server.open(
      tester,
      own,
      const CreateRoom(name: 'Ann', game: holdemKey, settings: RoomSettings(seats: 3), bots: {0: 'tag', 1: 'tag'}),
    );
    rooms.enter(own);
    await _settle(tester, server);
    own.send(const StartGame());
    await server.until(tester, () => own.room!.phase == RoomPhase.playing, 'playing');
    await _settle(tester, server);
    rooms.navigatorKey.currentState!.popUntil((r) => r.isFirst);
    unawaited(rooms.navigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => const SetupScreen())));
    await _settle(tester, server);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('open table')),
      200,
      scrollable: find.descendant(of: find.byKey(const ValueKey('room setup')), matching: find.byType(Scrollable)),
    );
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('open table'))).onPressed, isNull);
    expect(find.text(_en.endGameFirst), findsOneWidget);
    await _end(tester, server, [rooms]);
  });
}
