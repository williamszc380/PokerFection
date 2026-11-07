import 'dart:async';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/games/big_two/online/big_two_runner.dart';
import 'package:pokerfection/src/games/big_two/online/big_two_view_codec.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/ui/game_menu.dart';
import 'package:pokerfection/src/ui/games.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_coach_view.dart' show bigTwoFace;
import 'package:pokerfection/src/ui/games/big_two/online/big_two_online_ui.dart';
import 'package:pokerfection/src/ui/home_screen.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';
import 'package:pokerfection/src/ui/online/online_game_screen.dart';
import 'package:pokerfection/src/ui/online/online_game_uis.dart';
import 'package:pokerfection/src/ui/online/room_lobby_screen.dart';
import 'package:pokerfection/src/ui/online/room_scope.dart';
import 'package:pokerfection/src/ui/online/room_widgets.dart' show roomGameKey;
import 'package:pokerfection/src/ui/online/runner_client.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import '../widget_test.dart' show setScreen;
import 'room_app.dart';
import 'room_kit.dart';

/// Big Two in a room, on the app's side, through the fake room (a real
/// RoomRegistry on a clock the test moves): the host picks it from Home
/// and its menu's Play, sets its rules in the setup's own rows and sits on
/// the room's table, and plays a whole deal against a seated guest by
/// picking cards in the fanned hand while a spectator watches both hands;
/// then a spectator watches a person play two bots, the coach off at
/// first, the bots' cards hidden until the host's switch is on.

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

/// The legal moves of the seat [r] plays, at its turn.
List<Play> _legal(RunnerClient r) => bigTwoEngineView(r.view!).legalMoves();

/// [r]'s player plays the first legal play (or passes when leading isn't
/// theirs and they can't play), as a quick opponent.
void _autoPlay(RunnerClient? r) {
  if (r == null || !r.myTurn) return;
  final legal = _legal(r);
  r.move(bigTwoMove(r.you!, legal.firstWhere((p) => !p.isPass, orElse: () => Play.pass)));
}

/// The hand's card for [card] (the kit's fan keys a card by its face).
Finder _card(Card card) => find.byKey(ValueKey('${bigTwoFace(card)}#1'));

bool _enabled(WidgetTester tester, String key) =>
    tester.widget<ButtonStyleButton>(find.byKey(ValueKey(key))).onPressed != null;

Future<void> _end(WidgetTester tester, TestServer server, List<RoomService> rooms) async {
  for (final r in rooms) {
    unawaited(r.leave());
  }
  await server.wait(tester, const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox());
  await server.wait(tester, const Duration(seconds: 6));
}

void main() {
  testWidgets("Big Two is registered for rooms on both sides, at the same version: Home doesn't grey it out in a "
      'room any more', (tester) async {
    expect(onlineGameUis['big_two'], isA<BigTwoOnlineUi>());
    expect(bigTwoOnlineUi!.gv, bigTwoOnline!.gv);
    final server = TestServer(games: {'big_two': bigTwoOnline!});
    final ann = _rooms('Ann');
    setScreen(tester, const Size(1280, 800));
    await _show(tester, ann);
    final own = server.client();
    await server.open(tester, own, const CreateRoom(name: 'Ann'));
    ann.enter(own);
    await _settle(tester, server);
    expect(own.room!.games['big_two'], bigTwoOnline!.gv);
    final info = games.firstWhere((g) => g.id == GameId.bigTwo);
    expect(roomGameKey(info), 'big_two');
    expect(find.byKey(const ValueKey('game bigTwo')), findsOneWidget);
    expect(find.byKey(const ValueKey('online soon bigTwo')), findsNothing, reason: 'playable online');
    await _end(tester, server, [ann]);
  });

  testWidgets("a whole deal: the host picks Big Two with its menu's Play (2 seats), sets the rules in the setup's "
      'rows (the scoring brings its own target; 13, 17 or 21 cards each at two), sits; a guest takes the other seat; '
      'the host plays by picking cards in the fanned hand (Play greyed until they make a legal play) and passing, a '
      "pass that can't be avoided plays itself; a spectator sees both hands; the deal's winner and points show, and "
      'the next deal comes', (tester) async {
    final server = TestServer(games: {'big_two': bigTwoOnline!});
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

    // Home, Big Two's menu, Play: the room's game, with 2 seats.
    await tester.tap(find.byKey(const ValueKey('game bigTwo')));
    await _settle(tester, server);
    await tester.tap(find.descendant(of: find.byType(GameMenu), matching: find.byType(FilledButton)).first);
    await server.until(tester, () => own.room!.game?.key == 'big_two', 'Big Two picked');
    await _settle(tester, server);
    expect(find.byType(RoomLobbyScreen), findsOneWidget, reason: "the host is at the room's table");
    expect(own.room!.seats, hasLength(2));
    Map<String, Object?> rules() => (own.room!.game!.setup!['rules']! as Map).cast<String, Object?>();
    expect(BigTwoRoomRules.read(rules()).match.points, 100);

    // The rules: the solo setup's rows. Pusoy Dos scoring counts wins: its own target.
    await _tap(tester, find.byKey(const ValueKey('rules')));
    await _settle(tester, server);
    expect(find.byKey(const ValueKey('big two rules')), findsOneWidget);
    await _tap(tester, find.descendant(of: find.byKey(const ValueKey('scoring')), matching: find.text('Pusoy Dos')));
    await _settle(tester, server);
    expect(BigTwoRoomRules.read(rules()).rules.scoring, BigTwoScoring.pusoyDos);
    expect(BigTwoRoomRules.read(rules()).match.points, 10);
    await _tap(tester, find.descendant(of: find.byKey(const ValueKey('scoring')), matching: find.text('Penalty')));
    await _settle(tester, server);
    expect(BigTwoRoomRules.read(rules()).match.points, 100);
    // Two seats: any of 13, 17 and 21 cards each.
    await _tap(tester, find.descendant(of: find.byKey(const ValueKey('cards each')), matching: find.text('13')));
    await _settle(tester, server);
    expect(BigTwoRoomRules.read(rules()).cards2, 13);
    await _tap(tester, find.descendant(of: find.byKey(const ValueKey('cards each')), matching: find.text('17')));
    await _settle(tester, server);
    expect(BigTwoRoomRules.read(rules()).cards2, 17);
    expect(ben.client!.room!.game!.setup!['rules'], rules(), reason: "the guests see the host's rules");

    // Seats: the host sits from its empty seat's menu; Ben takes the other.
    await _tap(tester, find.byKey(const ValueKey('table seat 0')));
    await _settle(tester, server, 3);
    await tester.tap(find.byKey(const ValueKey('table sit 0')));
    await _settle(tester, server);
    benClient.send(const TakeSeat(1));
    await server.until(tester, () => own.room!.taken == 2, 'both seats taken');
    await _settle(tester, server);
    await _tap(tester, find.byKey(const ValueKey('start')));
    await server.until(tester, () => ann.runner?.state != null && ben.runner?.state != null, 'the deal');
    await _settle(tester, server);
    expect(find.byType(OnlineGameScreen), findsOneWidget);
    expect(find.byType(BigTwoOnlineTable), findsOneWidget);
    expect(find.byType(BigTwoOnlineHand), findsOneWidget);
    expect(cy.runner!.spectating, isTrue);
    expect(ann.runner!.view!['hand'], hasLength(17));

    // The deal: Ann plays from her hand, Ben answers at once.
    var plays = 0, forcedPasses = 0, buttonPasses = 0;
    for (var guard = 0; ann.runner!.over == null; guard++) {
      expect(guard, lessThan(400), reason: 'the deal ends');
      _autoPlay(ben.runner);
      await _settle(tester, server, 2);
      // The spectator holds both hands (both seats are people).
      if (cy.runner!.over == null) expect((cy.runner!.view!['hands']! as Map).keys, ['0', '1']);
      final r = ann.runner!;
      if (!r.myTurn) continue;
      await tester.pump();
      final legal = _legal(r);
      final cards = legal.where((p) => !p.isPass).toList();
      if (cards.isEmpty) {
        // Only Pass: "Can't beat", and it plays itself.
        expect(find.byKey(const ValueKey('cant beat')), findsOneWidget);
        final turn = r.turn!.turnId;
        await _settle(tester, server, 12);
        expect(r.turn?.turnId != turn || r.over != null, isTrue, reason: 'the forced pass played itself');
        forcedPasses++;
        continue;
      }
      if (legal.contains(Play.pass) && plays.isOdd) {
        // Pass now and then, with the button.
        expect(_enabled(tester, 'pass'), isTrue);
        await tester.tap(find.byKey(const ValueKey('pass')));
        await _settle(tester, server, 2);
        buttonPasses++;
        continue;
      }
      expect(_enabled(tester, 'play'), isFalse, reason: 'greyed out until the cards make a legal play');
      final play = cards.first;
      for (final card in play.cards) {
        await tester.tap(_card(card));
        await tester.pump();
      }
      expect(_enabled(tester, 'play'), isTrue);
      expect(_enabled(tester, 'clear'), isTrue);
      final before = (r.view!['history']! as List).length;
      await tester.tap(find.byKey(const ValueKey('play')));
      await _settle(tester, server, 2);
      expect((ann.runner!.view!['history']! as List).length, greaterThan(before));
      expect((ann.runner!.view!['history']! as List)[before], bigTwoMove(0, play));
      plays++;
    }
    expect(plays, greaterThan(0));
    expect(forcedPasses + buttonPasses, greaterThan(0));
    await tester.pump();
    final winner = ann.runner!.over!.result['winner']! as int;
    expect(find.text(winner == 0 ? _kit.youWin : _kit.wins('Ben')), findsOneWidget);
    // The deal's points: on the seats (the winner's in green) and in the room.
    final scores = [for (final s in own.room!.seats) s.score ?? 0];
    expect(scores.fold<num>(0, (a, b) => a + b), 0);
    expect(scores[winner], greaterThan(0));
    // Every hand is shown once the deal is over (to the spectator too).
    expect((cy.runner!.view!['hands']! as Map).keys, ['0', '1']);
    expect(find.byKey(const ValueKey('match chip')), findsOneWidget);

    // The next deal comes by itself, the match's totals carried on.
    await server.until(tester, () => ann.runner!.round == 2 && ann.runner!.over == null, 'the next deal', limit: 400);
    await tester.pump();
    final match = BigTwoWireView.read(ann.runner!.view!).match!;
    expect(match.deals, hasLength(1));
    expect(find.byKey(const ValueKey('match scores')), findsOneWidget);
    await _end(tester, server, [ann, ben, cy]);
  });

  testWidgets("a spectator watches a person play two bots: the coach starts off; on, it lists the person's moves with "
      'Pass whenever it is legal, and "—" for a bot while the host\'s switch is off (their cards face down); with '
      "the switch on the bots' hands show from the next deal and the coach works for them too", (tester) async {
    final server = TestServer(games: {'big_two': bigTwoOnline!});
    final ann = _rooms('Ann'), ben = _rooms('Ben'), cy = _rooms('Cy');
    setScreen(tester, const Size(1280, 800));
    await _show(tester, cy, home: const Scaffold(body: Text('home')));
    final own = server.client();
    await server.open(tester, own, const CreateRoom(name: 'Ann'));
    ann.enter(own);
    final benClient = server.client(), cyClient = server.client();
    await server.open(tester, benClient, JoinRoom(code: own.room!.code, name: 'Ben'));
    ben.enter(benClient);
    await server.open(tester, cyClient, JoinRoom(code: own.room!.code, name: 'Cy'));
    cy.enter(cyClient);
    own.send(ChooseGame(game: 'big_two', setup: {'seats': 3, 'turnLimit': 0, 'rules': bigTwoOnline!.defaultRules}));
    await _settle(tester, server);
    benClient.send(const TakeSeat(0));
    own.send(const AddBot(style: 'easy'));
    own.send(const AddBot(style: 'medium'));
    await server.until(tester, () => own.room!.taken == 3, 'three seats');
    own.send(const StartGame());
    await server.until(tester, () => cy.runner?.state != null, 'the deal');
    cy.watch();
    await _settle(tester, server);
    expect(find.byType(BigTwoOnlineTable), findsOneWidget);
    expect(find.byType(BigTwoOnlineHand), findsNothing, reason: 'a spectator has no hand of their own');
    // Ben's cards face up (seat 0, at the bottom), the bots' backs.
    expect(find.byKey(const ValueKey('seat faces')), findsOneWidget);
    expect(find.byKey(const ValueKey('seat backs')), findsNWidgets(2));
    // The coach starts off.
    expect(cy.runner!.coachOn, isFalse);
    expect(find.byKey(const ValueKey('coach on')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('coach chip')));
    await _settle(tester, server);
    expect(cy.runner!.coachOn, isTrue);

    var sawPerson = false, sawBot = false;
    for (var guard = 0; !(sawPerson && sawBot); guard++) {
      expect(guard, lessThan(300), reason: 'a turn of each');
      final turn = cy.runner!.turn;
      if (turn != null && !cy.runner!.coachThinking) {
        if (turn.seat == 0 && cy.runner!.coach != null && ben.runner!.myTurn) {
          await tester.pump();
          expect(find.byKey(const ValueKey('coach list')), findsOneWidget);
          final answer = cy.runner!.coach!;
          if (_legal(ben.runner!).contains(Play.pass)) {
            expect(answer.listed, {'0:pass'});
            expect(find.text('Pass'), findsWidgets);
          }
          sawPerson = true;
        } else if (turn.seat != 0) {
          await tester.pump();
          if (cy.runner!.coachHidden) {
            expect(find.byKey(const ValueKey('coach hidden')), findsOneWidget);
            sawBot = true;
          }
        }
      }
      _autoPlay(ben.runner);
      await _settle(tester, server, 1);
    }

    // The switch: from the next deal the bots' hands show, and the coach covers them.
    own.send(const HostSettings(seeBots: true));
    final round = cy.runner!.round;
    for (var guard = 0; !(cy.runner!.round > round && cy.runner!.over == null); guard++) {
      expect(guard, lessThan(800), reason: 'the next deal');
      _autoPlay(ben.runner);
      await _settle(tester, server, 1);
    }
    await tester.pump();
    expect(find.byKey(const ValueKey('seat faces')), findsNWidgets(3));
    expect(find.byKey(const ValueKey('seat backs')), findsNothing);
    var coached = false;
    for (var guard = 0; !coached; guard++) {
      expect(guard, lessThan(300), reason: "a bot's turn coached");
      final turn = cy.runner!.turn;
      if (turn != null && turn.seat != 0 && cy.runner!.coach != null && !cy.runner!.coachThinking) {
        expect(cy.runner!.coachHidden, isFalse);
        await tester.pump();
        expect(find.byKey(const ValueKey('coach list')), findsOneWidget);
        coached = true;
      }
      _autoPlay(ben.runner);
      await _settle(tester, server, 1);
    }
    await _end(tester, server, [ann, ben, cy]);
  });
}
