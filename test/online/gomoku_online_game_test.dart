import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/gomoku/gomoku.dart';
import 'package:pokerfection/src/games/gomoku/online/gomoku_runner.dart';
import 'package:pokerfection/src/games/gomoku/online/gomoku_view_codec.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/ui/game_menu.dart';
import 'package:pokerfection/src/ui/games.dart';
import 'package:pokerfection/src/ui/games/gomoku/online/gomoku_online_table.dart';
import 'package:pokerfection/src/ui/games/gomoku/online/gomoku_online_ui.dart';
import 'package:pokerfection/src/ui/home_screen.dart';
import 'package:pokerfection/src/ui/kit/coach_panel.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';
import 'package:pokerfection/src/ui/online/online_game_screen.dart';
import 'package:pokerfection/src/ui/online/online_game_uis.dart';
import 'package:pokerfection/src/ui/online/room_lobby_screen.dart';
import 'package:pokerfection/src/ui/online/room_widgets.dart' show roomGameKey;
import 'package:pokerfection/src/ui/online/room_scope.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;
import 'package:pokerfection/src/ui/widgets/gomoku_board.dart';

import '../ui/games/gomoku/gomoku_harness.dart' show boardPainter;
import '../widget_test.dart' show setScreen;
import 'room_app.dart';
import 'room_kit.dart';

/// Gomoku in a room, on the app's side, through the fake room (a real
/// RoomRegistry on a clock the test moves): the host picks it from Home
/// and its menu's Play, sets its rules and seats on the room's table, and
/// plays a whole game against a seated guest while a spectator watches;
/// then against a bot, the spectator's coach on, with the host's switch
/// off and on.

final _kit = KitStrings.forLanguage(AppLanguage.english);

RoomService _rooms(String name) => RoomService(
  settings: AppSettings()
    ..nickname = name
    ..speed = PlaybackSpeed.instant,
  gameUis: onlineGameUis,
  newJobs: () => Jobs.inline(),
);

Future<void> _show(WidgetTester tester, RoomService rooms, {Widget home = const HomeScreen()}) async {
  await tester.pumpWidget(roomApp(home, rooms: rooms));
  await tester.pump();
}

Future<void> _settle(WidgetTester tester, TestServer server, [int steps = 8]) async {
  for (var i = 0; i < steps; i++) {
    server.clock.advance(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

/// The centre of [notation]'s point on the board on screen.
Offset _at(WidgetTester tester, String notation) {
  final board = find.byKey(const ValueKey('gomoku board'));
  final painter = boardPainter(tester);
  final move = GomokuMove.parse(notation);
  final box = tester.getRect(board);
  final geometry = GomokuBoardGeometry(box.size, painter.lines, coordinates: painter.coordinates);
  return box.topLeft + geometry.at((move.x, painter.lines - 1 - move.y));
}

/// The moves of the game [rooms] shows.
String _moves(RoomService rooms) => (rooms.runner?.view?['moves'] as String?) ?? '';

bool _atGame() => find.byType(OnlineGameScreen).evaluate().isNotEmpty;

Future<void> _end(WidgetTester tester, TestServer server, List<RoomService> rooms) async {
  for (final r in rooms) {
    unawaited(r.leave());
  }
  await server.wait(tester, const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox());
  await server.wait(tester, const Duration(seconds: 6));
}

void main() {
  testWidgets("Gomoku is registered for rooms on both sides, at the same version: Home doesn't grey it out in a "
      'room (the games without their online part still are)', (tester) async {
    expect(onlineGameUis['gomoku'], isA<GomokuOnlineUi>());
    expect(gomokuOnlineUi!.gv, gomokuOnline!.gv);
    final server = TestServer();
    final ann = _rooms('Ann');
    setScreen(tester, const Size(1280, 800));
    await _show(tester, ann);
    final own = server.client();
    await server.open(tester, own, const CreateRoom(name: 'Ann'));
    ann.enter(own);
    await _settle(tester, server);
    expect(own.room!.games['gomoku'], gomokuOnlineGv);
    expect(find.byKey(const ValueKey('online soon gomoku')), findsNothing, reason: 'playable online');
    for (final g in games.where((g) => g.ready && g.id != GameId.holdem && g.id != GameId.gomoku)) {
      if (!onlineGameUis.containsKey(roomGameKey(g))) {
        expect(find.byKey(ValueKey('online soon ${g.id.name}')), findsOneWidget, reason: g.id.name);
      }
    }
    await _end(tester, server, [ann]);
  });

  testWidgets("a whole game: the host picks Gomoku with its menu's Play, sets the rules (19×19 greyed under Renju) "
      'and sits; a guest takes the other seat; the host (Black) plays by clicking the board, the guest replies; five '
      'in a row wins ("You win", the row lit, a point on the seat); the next game the guest has Black, and the host '
      'plays by touch (aim, then Place); a spectator watches the whole game', (tester) async {
    final server = TestServer();
    final ann = _rooms('Ann'), ben = _rooms('Ben'), cy = _rooms('Cy');
    setScreen(tester, const Size(1280, 800));
    await _show(tester, ann);
    final own = server.client();
    await server.open(tester, own, const CreateRoom(name: 'Ann'));
    ann.enter(own);
    final benClient = server.client(), cyClient = server.client();
    await server.open(tester, benClient, JoinRoom(code: own.room!.code, name: 'Ben'));
    ben.enter(benClient);
    await server.open(tester, cyClient, JoinRoom(code: own.room!.code, name: 'Cy'));
    cy.enter(cyClient);
    await _settle(tester, server);

    // Home, Gomoku's menu, Play: the room's game.
    await tester.tap(find.byKey(const ValueKey('game gomoku')));
    await _settle(tester, server);
    await tester.tap(find.descendant(of: find.byType(GameMenu), matching: find.byType(FilledButton)).first);
    await server.until(tester, () => own.room!.game?.key == 'gomoku', 'Gomoku picked');
    await _settle(tester, server);
    expect(find.byType(RoomLobbyScreen), findsOneWidget, reason: "the host is at the room's table");
    expect(own.room!.seats, hasLength(2));
    expect(own.room!.game!.setup!['rules'], {'size': 15, 'win': 'freestyle', 'black': 'turns'});

    // The rules: the solo setup's rows, and who plays Black.
    await _tap(tester, find.byKey(const ValueKey('rules')));
    await _settle(tester, server);
    expect(find.byKey(const ValueKey('gomoku rules')), findsOneWidget);
    await _tap(tester, find.text('Renju'));
    await _settle(tester, server);
    expect(own.room!.game!.setup!['rules'], {'size': 15, 'win': 'renju', 'black': 'turns'});
    final size19 = find.descendant(of: find.byKey(const ValueKey('gomoku board size')), matching: find.text('19×19'));
    expect(
      tester
          .widget<SegmentedButton<int>>(find.ancestor(of: size19, matching: find.byType(SegmentedButton<int>)))
          .segments
          .last
          .enabled,
      isFalse,
      reason: 'Renju is played on 15×15: 19×19 greyed out, not hidden',
    );
    await _tap(tester, find.text('Freestyle'));
    await _tap(tester, find.text('Loser'));
    await _tap(tester, find.text('Take turns'));
    await _settle(tester, server);
    expect(own.room!.game!.setup!['rules'], {'size': 15, 'win': 'freestyle', 'black': 'turns'});
    // The guests' copy of the form is greyed out.
    expect(ben.client!.room!.game!.setup!['rules'], own.room!.game!.setup!['rules']);

    // Seats: the host sits from its empty seat's menu; Ben takes the other.
    await _tap(tester, find.byKey(const ValueKey('table seat 0')));
    await _settle(tester, server, 3);
    await tester.tap(find.byKey(const ValueKey('table sit 0')));
    await _settle(tester, server);
    benClient.send(const TakeSeat(1));
    await server.until(tester, () => own.room!.taken == 2, 'both seats taken');
    await _settle(tester, server);
    await _tap(tester, find.byKey(const ValueKey('start')));
    await server.until(tester, () => ann.runner?.state != null && ben.runner?.state != null, 'the game');
    await _settle(tester, server);
    expect(_atGame(), isTrue);
    expect(find.byType(GomokuOnlineTable), findsOneWidget);
    expect(ann.runner!.you, 0);
    expect(ann.runner!.view!['black'], 0, reason: 'the first seat has Black in the first game');
    expect(cy.runner!.spectating, isTrue);
    expect(find.text(_kit.yourTurn), findsOneWidget);
    // The seated player's buttons: Place (greyed until a point is aimed at), no Pass outside Renju.
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('place'))).onPressed, isNull);
    expect(find.byKey(const ValueKey('pass')), findsNothing);

    // Ann (Black) clicks h8 i8 j8 k8 l8; Ben answers on the a file.
    final replies = ['a1', 'a3', 'a5', 'a7'];
    for (final (i, point) in ['h8', 'i8', 'j8', 'k8', 'l8'].indexed) {
      await server.until(tester, () => ann.runner!.myTurn, "Ann's turn");
      await tester.pump();
      await tester.tapAt(_at(tester, point), kind: PointerDeviceKind.mouse);
      await _settle(tester, server, 2);
      expect(_moves(ann).split(' ').last, point, reason: 'one click places the stone');
      if (i < replies.length) {
        await server.until(tester, () => ben.runner!.myTurn, "Ben's turn");
        expect(find.text('Ben…'), findsOneWidget);
        ben.runner!.move(replies[i]);
        await _settle(tester, server, 2);
      }
    }
    await server.until(tester, () => ann.runner!.over != null, 'the five');
    await tester.pump();
    expect(find.text(_kit.youWin), findsOneWidget);
    expect(boardPainter(tester).winLine, hasLength(5));
    expect(ben.runner!.over!.result, {'winner': 0});
    expect(cy.runner!.state!.view['moves'], 'h8 a1 i8 a3 j8 a5 k8 a7 l8', reason: 'the spectator saw every move');
    expect(own.room!.seats.map((s) => s.score), [1, 0]);
    expect(find.descendant(of: find.byKey(const ValueKey('gomoku tag 0')), matching: find.text('1')), findsOneWidget);

    // The next game: Ben has Black and opens; Ann plays by touch.
    await server.until(tester, () => ann.runner!.round == 2, 'the next game', limit: 400);
    expect(ann.runner!.view!['black'], 1);
    await server.until(tester, () => ben.runner!.myTurn, "Ben's first move");
    ben.runner!.move('h8');
    await server.until(tester, () => ann.runner!.myTurn, "Ann's turn");
    await tester.pump();
    await tester.tapAt(_at(tester, 'g7'));
    await tester.pump();
    expect(_moves(ann), 'h8', reason: 'a tap only aims');
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('place'))).onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('place')));
    await _settle(tester, server, 2);
    expect(_moves(ann), 'h8 g7');
    // A taken point can't be aimed at.
    await server.until(tester, () => ben.runner!.myTurn, "Ben's turn");
    ben.runner!.move('j9');
    await server.until(tester, () => ann.runner!.myTurn, "Ann's turn");
    await tester.pump();
    await tester.tapAt(_at(tester, 'h8'));
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('place'))).onPressed, isNull);
    await _end(tester, server, [ann, ben, cy]);
  });

  testWidgets("a spectator watches the host play a bot: the coach starts off; on, it lists the Best moves for "
      "whoever acts (the bot too, with the host's switch off: Gomoku hides nothing) and numbers them on the board; "
      'with the switch on the same', (tester) async {
    final server = TestServer();
    final ann = _rooms('Ann'), cy = _rooms('Cy');
    setScreen(tester, const Size(1280, 800));
    await _show(tester, cy, home: const Scaffold(body: Text('home')));
    final own = server.client();
    await server.open(tester, own, const CreateRoom(name: 'Ann'));
    ann.enter(own);
    final cyClient = server.client();
    await server.open(tester, cyClient, JoinRoom(code: own.room!.code, name: 'Cy'));
    cy.enter(cyClient);
    own.send(const ChooseGame(game: 'gomoku'));
    own.send(const TakeSeat(0));
    own.send(const AddBot(style: 'easy', seat: 1));
    await server.until(tester, () => own.room!.taken == 2, 'seated');
    own.send(const StartGame());
    await server.until(tester, () => cy.runner?.state != null, 'the game');
    await _settle(tester, server);
    expect(_atGame(), isTrue, reason: 'the spectator follows the host to the game');
    final runner = cy.runner!;
    expect(runner.coachOn, isFalse, reason: 'off until asked for');
    expect(find.byKey(const ValueKey('coach on')), findsOneWidget);
    expect(find.byKey(const ValueKey('coach chip')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('coach on')));
    await _settle(tester, server, 2);
    expect(runner.coachOn, isTrue);

    for (final seeBots in [false, true]) {
      own.send(HostSettings(seeBots: seeBots));
      await _settle(tester, server, 2);
      // Ann (Black) plays from her off-screen app; the host's device plays the bot.
      for (var turn = 0; turn < 6; turn++) {
        await server.until(tester, () => runner.turn != null, 'a turn');
        final seat = runner.turn!.seat;
        // The coach answers for whoever acts.
        await server.until(tester, () => runner.coach != null && !runner.coachThinking, 'the coach');
        await tester.pump();
        expect(runner.coachHidden, isFalse, reason: 'nothing is hidden in Gomoku (switch $seeBots)');
        expect(find.byType(CoachList), findsOneWidget);
        final best = runner.coach!.pick;
        expect(find.descendant(of: find.byType(CoachList), matching: find.text(best)), findsWidgets);
        expect(boardPainter(tester).marks, isNotEmpty, reason: "the coach's moves numbered on the board");
        if (seat == 0) {
          final view = GomokuOnlineView.fromJson(ann.runner!.view!);
          ann.runner!.move(view.game.legalMoves().firstWhere((m) => m.x > 2 && m.y > 2).notation);
        }
        final before = runner.state!.seq;
        await server.until(tester, () => runner.state!.seq > before, 'the move');
        if (runner.over != null) break;
      }
    }
    expect(runner.spectating, isTrue);
    await _end(tester, server, [ann, cy]);
  });
}
