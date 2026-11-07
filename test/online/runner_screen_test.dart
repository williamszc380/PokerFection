import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/online/online_client.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/ui/game_menu.dart';
import 'package:pokerfection/src/ui/games.dart';
import 'package:pokerfection/src/ui/online/online_game_screen.dart';
import 'package:pokerfection/src/ui/online/room_game_frame.dart';
import 'package:pokerfection/src/ui/online/room_lobby_screen.dart';
import 'package:pokerfection/src/ui/online/room_panel.dart';
import 'package:pokerfection/src/ui/online/room_widgets.dart' show roomGameKey;
import 'package:pokerfection/src/ui/online/room_scope.dart';
import 'package:pokerfection/src/ui/online/runner_client.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import '../server/fake_runner.dart';
import '../widget_test.dart' show setScreen;
import 'fake_runner_ui.dart';
import 'room_app.dart';
import 'room_kit.dart';

/// The rooms' runner games on the app's side (R4), with the fake High card
/// game: the host picks it from its game menu (v2.1), the room's table
/// sets it up (seats, rules, bots, Start), the room service lands on its
/// screen and keeps it going off screen, the host's device plays the bots,
/// and the game's screen lays out its two tabs.

final _en = S.forLanguage(AppLanguage.english);

/// A server running High card ([game]), and an app's room service that
/// shows it.
(TestServer, HighCardGame) _server() {
  final game = HighCardGame();
  return (TestServer(games: {game.key: game}), game);
}

RoomService _rooms(HighCardGame game, {String name = 'Ben', AppLanguage language = AppLanguage.english}) => RoomService(
  settings: AppSettings()
    ..nickname = name
    ..language = language
    ..speed = PlaybackSpeed.instant,
  gameUis: {game.key: HighCardUi(game)},
  newJobs: highCardInlineJobs,
);

/// The app at [size] on its first screen, with [rooms].
Future<void> _app(WidgetTester tester, RoomService rooms, {Size size = const Size(1280, 800)}) async {
  setScreen(tester, size);
  await tester.pumpWidget(
    roomApp(
      const Scaffold(body: Center(child: Text('home'))),
      rooms: rooms,
    ),
  );
  await tester.pump();
}

/// Lets the screens' animations and the server's time run.
Future<void> _settle(WidgetTester tester, TestServer server, [int steps = 8]) async {
  for (var i = 0; i < steps; i++) {
    server.clock.advance(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tapInPanel(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

/// A room with High card picked, hosted by a client off screen whose
/// device plays its bots ([RunnerClient] on it, as its app's room would).
Future<(OnlineClient, RunnerClient)> _hostOffScreen(
  WidgetTester tester,
  TestServer server,
  HighCardGame game, {
  int bots = 2,
}) async {
  final host = server.client();
  await server.open(tester, host, const CreateRoom(name: 'Ann'));
  host.send(ChooseGame(game: game.key));
  for (var i = 0; i < bots; i++) {
    host.send(const AddBot(style: 'easy'));
  }
  await server.wait(tester);
  final runner = RunnerClient(host, ui: HighCardUi(game), newJobs: highCardInlineJobs);
  return (host, runner);
}

Future<OnlineClient> _enter(
  WidgetTester tester,
  TestServer server,
  RoomService rooms,
  String code, {
  String name = 'Ben',
}) async {
  final client = server.client();
  await server.open(tester, client, JoinRoom(code: code, name: name));
  rooms.enter(client);
  await tester.pump();
  return client;
}

bool _atGame() => find.byType(OnlineGameScreen).evaluate().isNotEmpty;

/// The room's table shows the game's seats (no game running).
bool _atSeats() => find.byType(RoomLobbyScreen).evaluate().isNotEmpty;

/// The system's Back.
Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pump();
}

Future<void> _end(
  WidgetTester tester,
  TestServer server,
  List<RoomService> rooms, [
  List<RunnerClient> runners = const [],
]) async {
  for (final r in rooms) {
    unawaited(r.leave());
  }
  for (final r in runners) {
    r.dispose();
  }
  await server.wait(tester, const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox());
  await server.wait(tester, const Duration(seconds: 6));
}

void main() {
  testWidgets("the host picks High card with its game menu's Play in a room with no game: the room's table opens "
      '(2 seats, its rules under Rules); the host adds bots and starts there; it lands on the game, and off it its '
      'device keeps playing the bots; Watch is back', (
    tester,
  ) async {
    final (server, game) = _server();
    final rooms = _rooms(game, name: 'Ann');
    await _app(tester, rooms);
    final host = server.client();
    await server.open(tester, host, const CreateRoom(name: 'Ann'));
    rooms.enter(host);
    await _settle(tester, server);
    expect(find.byType(RoomPanel), findsOneWidget);

    // The game's menu (High card stands in for the game whose key it has): Play makes it the room's game.
    final info = games.firstWhere((g) => roomGameKey(g) == game.key);
    unawaited(rooms.navigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => GameMenu(game: info))));
    await _settle(tester, server);
    await tester.tap(find.descendant(of: find.byType(GameMenu), matching: find.byType(FilledButton)).first);
    await _settle(tester, server);
    expect(host.room!.game!.key, game.key);
    expect(_atSeats(), isTrue, reason: "the host is at the room's table");
    expect(host.room!.seats, hasLength(2), reason: 'High card starts with 2 of its 2–3 seats');
    // Start is greyed out with why until every seat is taken.
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('start'))).onPressed, isNull);
    expect(find.text(_en.needSeats(2)), findsOneWidget);
    // The game's rules: its seats and time, and its own form.
    await _tapInPanel(tester, find.byKey(const ValueKey('rules')));
    await _settle(tester, server);
    await _tapInPanel(tester, find.text('3').last);
    await _settle(tester, server);
    expect(host.room!.seats, hasLength(3));
    expect(host.room!.game!.setup!['seats'], 3);
    await _tapInPanel(tester, find.text('2').last);
    await _settle(tester, server);
    expect(host.room!.seats, hasLength(2));
    // The bots: the game's levels.
    for (var i = 0; i < 2; i++) {
      await _tapInPanel(tester, find.byKey(const ValueKey('add bot')));
      await _settle(tester, server);
    }
    expect(host.room!.seats.map((s) => (s.kind, s.style)), [(SeatKind.bot, 'easy'), (SeatKind.bot, 'easy')]);
    expect(find.text(_en.needSeats(2)), findsNothing);
    await _tapInPanel(tester, find.byKey(const ValueKey('start')));
    await _settle(tester, server);
    expect(_atGame(), isTrue, reason: 'Start takes the host to the game');
    expect(rooms.runner, isNotNull);
    expect(rooms.gameOnScreen, isTrue);
    expect(find.byType(RoomGameFrame), findsOneWidget);

    // Back: the host (a spectator) leaves the game at once; on Home its device keeps playing the bots.
    await _back(tester);
    await _settle(tester, server);
    expect(_atGame(), isFalse);
    expect(rooms.runner!.onScreen, isFalse);
    final runner = game.runners.single;
    final moves = runner.moves.length, asked = HighCardBotJob.asked.length;
    await _settle(tester, server, 120);
    expect(runner.moves.length, greaterThan(moves + 4), reason: 'the bots play on');
    expect(HighCardBotJob.asked.length, greaterThan(asked + 4), reason: "by the host's device");
    // Watch: back to the game.
    await _tapInPanel(tester, find.byKey(const ValueKey('watch')));
    await _settle(tester, server);
    expect(_atGame(), isTrue);
    await _end(tester, server, [rooms]);
  });

  testWidgets("a spectator follows the host: at the room's table on entering, and from another screen to the game "
      "when it starts; the coach starts off and shows '—' for a bot (the switch off); Join game takes a bot's seat, "
      "and the seated player plays with the game's buttons; Back asks Leave seat (the round first)", (tester) async {
    final (server, game) = _server();
    final (host, hostRunner) = await _hostOffScreen(tester, server, game);
    final rooms = _rooms(game);
    await _app(tester, rooms);
    final ben = await _enter(tester, server, rooms, host.welcome!.code);
    await _settle(tester, server);
    expect(_atSeats(), isTrue, reason: "the room's game is picked: its table opens");
    // Off it, to a game menu, say.
    await _back(tester);
    await _settle(tester, server);
    unawaited(
      rooms.navigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('menu'))),
      ),
    );
    await _settle(tester, server);
    host.send(const StartGame());
    await _settle(tester, server);
    expect(rooms.runner, isNotNull);
    expect(_atGame(), isTrue, reason: 'everyone follows the host to the game');
    expect(find.text('menu', skipOffstage: false), findsOneWidget, reason: 'the menu stays under it');
    expect(rooms.runner!.spectating, isTrue);
    // The coach is off until asked for: then "—" for a bot whose card is hidden.
    expect(find.byKey(const ValueKey('coach on')), findsOneWidget);
    expect(rooms.runner!.coachOn, isFalse);
    await tester.tap(find.byKey(const ValueKey('coach on')));
    await _settle(tester, server, 2);
    expect(rooms.runner!.coachOn, isTrue);
    if (rooms.runner!.turn != null) expect(find.byKey(const ValueKey('coach hidden')), findsOneWidget);
    expect(find.byKey(const ValueKey('hc card 0')), findsOneWidget);
    // A spectator leaves at once.
    await _back(tester);
    await _settle(tester, server);
    expect(_atGame(), isFalse);
    expect(find.text('menu'), findsOneWidget);

    // Watch, then Join game in the Game tab: a bot gives its seat, seated from the next round.
    await _tapInPanel(tester, find.byKey(const ValueKey('watch')));
    await _settle(tester, server);
    expect(_atGame(), isTrue);
    await _tapInPanel(tester, find.byKey(const ValueKey('join game')));
    await _settle(tester, server);
    await server.until(tester, () => rooms.runner?.you != null, 'Ben dealt in');
    await server.until(tester, () => rooms.runner!.myTurn, "Ben's turn");
    await tester.pump();
    final raise = find.byKey(const ValueKey('hc raise'));
    expect(raise, findsOneWidget);
    expect(find.byKey(const ValueKey('hc my card')), findsOneWidget);
    await tester.tap(raise);
    await _settle(tester, server, 2);
    expect(game.runners.single.moves.where((m) => m.$2.endsWith('raise') && m.$1 == rooms.runner!.you), isNotEmpty);
    // Back while seated: Leave seat? (the round first). Cancel keeps everything.
    await _back(tester);
    await tester.pump();
    expect(find.text(_en.leaveSeatQuestion), findsOneWidget);
    expect(find.text(_en.leaveSeatWarningRound), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('leave seat sure')));
    await _settle(tester, server);
    await server.until(tester, () => ben.mySeat == null, 'the seat free');
    await _settle(tester, server);
    expect(_atGame(), isFalse, reason: 'the screen closes once the seat is free');
    await _end(tester, server, [rooms], [hostRunner]);
  });

  testWidgets("the host ends the game: the last result shows, then after 4 s the room's table shows the seats again, "
      'the game lets go of the connection and the room has it again', (tester) async {
    final (server, game) = _server();
    final (host, hostRunner) = await _hostOffScreen(tester, server, game);
    final rooms = _rooms(game);
    await _app(tester, rooms);
    final ben = await _enter(tester, server, rooms, host.welcome!.code);
    await _settle(tester, server);
    host.send(const StartGame());
    await _settle(tester, server);
    expect(_atGame(), isTrue, reason: "the room's table turns into the game");
    final runner = rooms.runner!;
    host.send(const EndGame());
    await server.until(tester, () => runner.gameOver, 'game over');
    await tester.pump();
    expect(find.text(_en.gameOver(null)), findsWidgets);
    await _settle(tester, server, 20);
    expect(_atGame(), isTrue, reason: 'the end shows a moment');
    await _settle(tester, server, 30);
    expect(_atGame(), isFalse);
    expect(_atSeats(), isTrue);
    expect(rooms.runner, isNull);
    expect(ben.status, OnlineStatus.open);
    // The room takes the connection back: a new game's first round lands again.
    host.send(const StartGame());
    await server.until(tester, () => rooms.runner != null, 'a new game');
    await _settle(tester, server);
    expect(_atGame(), isTrue);
    await _end(tester, server, [rooms], [hostRunner]);
  });

  testWidgets('the game screen fits a sideways phone, an upright browser and a PC, in every language, spectating '
      'and seated', (tester) async {
    final (server, game) = _server();
    final (host, hostRunner) = await _hostOffScreen(tester, server, game, bots: 1);
    final rooms = _rooms(game);
    await _app(tester, rooms);
    final ben = await _enter(tester, server, rooms, host.welcome!.code);
    await _settle(tester, server);
    ben.send(const TakeSeat());
    await _settle(tester, server);
    host.send(const StartGame());
    await _settle(tester, server);
    expect(_atGame(), isTrue, reason: 'a seated player always goes to the game');
    for (final seated in [true, false]) {
      if (!seated) {
        rooms.runner!.leaveSeat();
        // Ben plays the round out (folding) and watches from its end.
        await server.until(tester, () {
          final runner = rooms.runner;
          if (runner != null && runner.myTurn) runner.move('${runner.you}:fold');
          return ben.mySeat == null;
        }, 'a spectator');
        // A bot in the free seat: the game goes on, Ben watching.
        host.send(const AddBot(style: 'easy'));
        await server.until(tester, () => rooms.runner?.spectating ?? false, 'spectating');
        rooms.watch();
        await _settle(tester, server);
        rooms.runner!.setCoach(true);
      }
      for (final language in AppLanguage.values) {
        rooms.settings.language = language;
        for (final size in const [Size(568, 320), Size(640, 360), Size(390, 844), Size(1280, 800)]) {
          setScreen(tester, size);
          await tester.pumpWidget(
            roomApp(
              const Scaffold(body: Center(child: Text('home'))),
              rooms: rooms,
            ),
          );
          await _settle(tester, server, 2);
          expect(tester.takeException(), isNull, reason: '$size $language seated: $seated');
          expect(find.byKey(const ValueKey('game tab')), findsOneWidget);
          expect(find.byKey(const ValueKey('room tab')), findsOneWidget);
        }
      }
    }
    rooms.settings.language = AppLanguage.english;
    await _end(tester, server, [rooms], [hostRunner]);
  });

  testWidgets("the host's own device never draws a bot's card from the bot's turn it plays, with the switch off", (
    tester,
  ) async {
    final (server, game) = _server();
    final rooms = _rooms(game, name: 'Ann');
    await _app(tester, rooms);
    final host = server.client();
    await server.open(tester, host, const CreateRoom(name: 'Ann'));
    rooms.enter(host);
    await _settle(tester, server);
    host.send(ChooseGame(game: game.key));
    host.send(const AddBot(style: 'easy'));
    host.send(const AddBot(style: 'easy'));
    await _settle(tester, server);
    rooms.expectGame();
    host.send(const StartGame());
    await _settle(tester, server, 3);
    expect(_atGame(), isTrue);
    final runner = rooms.runner!;
    expect(runner.spectating, isTrue);
    // Whatever the bots were asked, no card shows face up (the spectators' view has none).
    for (var round = 0; round < 3; round++) {
      final state = runner.state!;
      if (state.over == null) {
        expect(find.text('??'), findsNWidgets(2), reason: 'round ${state.round}: both bots face down');
      }
      await server.until(tester, () => runner.state!.round > state.round || runner.gameOver, 'the next round');
      await tester.pump();
    }
    expect(HighCardBotJob.asked, isNotEmpty);
    await _end(tester, server, [rooms]);
  });
}
