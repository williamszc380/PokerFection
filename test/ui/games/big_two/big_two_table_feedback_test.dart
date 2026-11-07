// What the user asked of the Big Two table: the coach waits to be asked
// for, two players by default, the played cards fly from the hand (or a
// bot's seat) to a messy pile in the middle, and the pile opens the deal's
// history.
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_record.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_controller.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_table.dart';
import 'package:pokerfection/src/ui/games/big_two/l10n/big_two_strings.dart';
import 'package:pokerfection/src/ui/kit/card_flights.dart';
import 'package:pokerfection/src/ui/kit/coach_panel.dart';
import 'package:pokerfection/src/ui/kit/table_pile.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import '../../../kit/shots.dart';
import 'big_two_test_util.dart';

Finder byKey(String key) => find.byKey(ValueKey(key));

/// Plays on (the player making the first legal play, or passing) until the
/// deal has at least [turns] turns.
Future<void> playTurns(WidgetTester tester, BigTwoController game, int turns) async {
  for (var guard = 0; guard < 300 && game.state.history.length < turns && !game.isOver; guard++) {
    await settleGame(tester);
    if (!game.myTurn) continue;
    final legal = game.state.legalMoves();
    game.humanMove(bigTwoMoveText(0, legal.firstWhere((p) => !p.isPass, orElse: () => legal.first)));
  }
  await settleGame(tester);
}

/// Pumps time in small steps until [done] (at most [limit]).
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration limit = const Duration(seconds: 20),
}) async {
  var waited = Duration.zero;
  const step = Duration(milliseconds: 40);
  while (!done() && waited < limit) {
    await tester.pump(step);
    waited += step;
  }
  expect(done(), isTrue, reason: 'timed out');
}

/// Closes a game played at Normal speed, letting its bots' pauses run out.
Future<void> closeSlowGame(WidgetTester tester) async {
  await closeGame(tester);
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  setUpAll(loadShotFonts);

  group('the coach waits to be asked for', () {
    testWidgets('a fresh game hides the best moves, yet still grades each move; the coach chip shows them', (
      tester,
    ) async {
      final game = seededGame();
      await pumpGame(tester, game);
      await toMyPlayableTurn(tester, game);
      expect(game.coachVisible, isFalse);
      expect(find.byType(CoachList), findsNothing, reason: 'hidden until the player asks');
      game.humanMove(game.coach!.pick);
      await settleGame(tester);
      expect(game.lastMark, isNotNull, reason: 'Training still grades the move');
      await tester.tap(byKey('coach chip'));
      await tester.pump();
      expect(game.coachVisible, isTrue);
      await toMyPlayableTurn(tester, game);
      expect(find.byType(CoachList), findsOneWidget);
      await closeGame(tester);
    });

    test('the next game starts as the last one left it: hidden until the chip was turned on', () {
      final record = seededGame().deal();
      expect(BigTwoSetup.from(record).toggles.containsKey('coach'), isFalse);
      final shown = seededGame().deal().withExtra('coach', true);
      expect(BigTwoSetup.from(shown).toggles['coach'], isTrue, reason: 'the chip turned on carries over');
    });
  });

  group('two players by default', () {
    test('the default setup is the standard game for 2: Player and one bot, 17 cards each', () {
      final setup = BigTwoSetup.from(null);
      expect((setup.rules.players, setup.rules.cardsEach), (2, 17));
      expect(setup.seats.where((s) => !s.human), hasLength(1));
    });

    for (final size in bigTwoSizes) {
      for (final language in AppLanguage.values) {
        testWidgets('a two-player game with the coach on fits: ${shotTag(size, language)}', (tester) async {
          final game = seededGame(rules: BigTwoSetup.from(null).rules, toggles: const {'coach': true}, seed: 4);
          await pumpGame(tester, game, size: size, language: language);
          await toMyPlayableTurn(tester, game);
          expect(game.coach, isNotNull, reason: 'the coach reads a two-player deal');
          expect(find.byType(CoachList), findsOneWidget);
          for (final key in ['seat 0', 'seat 1', 'hand', 'play']) {
            final rect = tester.getRect(byKey(key));
            expect((Offset.zero & size).inflate(0.5).contains(rect.bottomRight), isTrue, reason: key);
          }
          expect(byKey('seat 2'), findsNothing);
          await closeGame(tester);
        });
      }
    }
  });

  group('the pile', () {
    test('each turn belongs to the trick it was played in; a trick ends when everyone else has passed', () {
      for (final rules in [
        BigTwoRules.standard(),
        BigTwoRules.standard(players: 3),
        BigTwoRules.hongKong(players: 2, cardsEach: 13),
        BigTwoRules.taiwan().copyWith(passLockout: true),
      ]) {
        for (var seed = 1; seed <= 6; seed++) {
          final state = BigTwoState.deal(rules, seed: seed);
          final ended = <bool>[];
          final bots = [for (var s = 0; s < rules.players; s++) BigTwoBot(BotLevel.easy, seed: seed * 10 + s)];
          while (!state.isOver) {
            final before = state.current;
            state.apply(bots[state.toMove].chooseMove(state.viewFor(state.toMove)));
            ended.add(before != null && state.current == null);
          }
          final tricks = state.trickOfTurns;
          expect(tricks, hasLength(state.history.length));
          expect(tricks.first, 0);
          for (var i = 1; i < tricks.length; i++) {
            expect(tricks[i], tricks[i - 1] + (ended[i - 1] ? 1 : 0), reason: '${rules.players}p seed $seed turn $i');
          }
        }
      }
    });

    testWidgets('earlier plays stay in sight under the latest, each a little askew, and stay put on a redraw', (
      tester,
    ) async {
      final game = seededGame(training: false, seed: 5);
      await pumpGame(tester, game);
      await playTurns(tester, game, 10);
      final history = game.state.history;
      final onTable = [
        for (var i = 0; i < history.length; i++)
          if (!history[i].play.isPass) i,
      ];
      expect(onTable.length, greaterThanOrEqualTo(3));
      final shown = onTable.sublist(onTable.length > 6 ? onTable.length - 6 : 0);
      for (final i in shown) {
        expect(byKey('pile play $i'), findsOneWidget, reason: 'play $i in sight');
      }
      final rects = {for (final i in shown) i: tester.getRect(byKey('pile play $i'))};
      expect(rects.values.map((r) => r.center).toSet(), hasLength(shown.length), reason: 'no two lie alike');
      // The latest is named under the pile: its kind and who played it.
      final last = history[onTable.last];
      final strings = BigTwoStrings.forLanguage(AppLanguage.english);
      final name = last.seat == 0 ? S.forLanguage(AppLanguage.english).you : game.record.seats[last.seat].name;
      expect(find.text('${strings.kind(last.play.kind)} · $name'), findsOneWidget);
      // A redraw (the Sort button) moves nothing.
      game.sortTap();
      await tester.pump();
      for (final i in shown) {
        expect(tester.getRect(byKey('pile play $i')), rects[i]);
      }
      await closeGame(tester);
    });

    testWidgets('a tap on the middle opens the history: every play and pass in order, with names and tricks', (
      tester,
    ) async {
      final game = seededGame(training: false, seed: 5);
      await pumpGame(tester, game);
      await playTurns(tester, game, 9);
      final history = game.state.history;
      expect(history.length, inInclusiveRange(9, 16));
      await tester.tap(byKey('pile'));
      await tester.pumpAndSettle();
      expect(byKey('pile history'), findsOneWidget);
      for (var i = 0; i < history.length; i++) {
        expect(byKey('history $i'), findsOneWidget, reason: 'turn $i');
      }
      final inHistory = find.descendant(
        of: byKey('pile history'),
        matching: find.text(S.forLanguage(AppLanguage.english).you),
      );
      expect(inHistory, findsWidgets, reason: 'the player\'s turns are "Player"');
      final strings = BigTwoStrings.forLanguage(AppLanguage.english);
      if (history.any((t) => t.play.isPass)) {
        expect(find.descendant(of: byKey('pile history'), matching: find.text(strings.pass)), findsWidgets);
      }
      await tester.tap(byKey('close history'));
      await tester.pumpAndSettle();
      expect(byKey('pile history'), findsNothing);
      await closeGame(tester);
    });

    testWidgets('the review shows the same pile, lying the same way', (tester) async {
      final game = seededGame(training: false, seed: 5);
      await pumpGame(tester, game);
      await playTurns(tester, game, 8);
      final state = BigTwoRecord.replay(game.record);
      final strings = BigTwoStrings.forLanguage(AppLanguage.english);
      final plays = BigTwoTable.pilePlays(state, strings);
      expect(plays, hasLength(state.history.length));
      expect([for (final p in plays) p.trick], state.trickOfTurns);
      expect(plays.where((p) => p.pass).length, state.history.where((t) => t.play.isPass).length);
      await closeGame(tester);
    });
  });

  group('cards fly to the table', () {
    testWidgets("the player's play flies from the hand to the pile, at the Animations setting's speed", (tester) async {
      final game = seededGame(training: false, speed: PlaybackSpeed.normal, seed: 5);
      await pumpGame(tester, game);
      await pumpUntil(tester, () => game.myTurn);
      await tester.pump(const Duration(seconds: 1)); // the bots' cards have landed
      final play = game.state.legalMoves().firstWhere((p) => !p.isPass);
      final turn = game.state.history.length;
      final firstCard = byKey('${bigTwoFaceKey(play.cards.first)}#1');
      final from = tester.getCenter(firstCard);
      game.selectMove(bigTwoMoveText(0, play));
      await tester.pump();
      await tester.tap(byKey('play'));
      await tester.pump(); // the move is on the screen; its cards take off
      await tester.pump(); // launched
      final flying = find.byKey(CardFlights.flyingKey(TablePile.flightTag(turn, 0)));
      expect(flying, findsOneWidget, reason: 'in the air');
      expect((tester.getCenter(flying) - from).distance, lessThan(30), reason: 'it leaves from the hand');
      await tester.pump(const Duration(milliseconds: 200));
      expect(flying, findsOneWidget, reason: 'still on its way');
      await tester.pump(const Duration(seconds: 1));
      expect(flying, findsNothing, reason: 'landed');
      expect(byKey('pile play $turn'), findsOneWidget);
      await closeSlowGame(tester);
    });

    testWidgets('a card the player dragged to a new place flies from that place', (tester) async {
      final game = seededGame(training: false, speed: PlaybackSpeed.normal, seed: 5);
      await pumpGame(tester, game);
      await pumpUntil(tester, () => game.myTurn);
      await tester.pump(const Duration(seconds: 1)); // the bots' cards have landed
      final play = game.state.legalMoves().firstWhere((p) => !p.isPass);
      final card = play.cards.first;
      // The card dragged to the far end of the hand.
      final from = game.hand.indexOf(card), to = from == game.hand.length - 1 ? 0 : game.hand.length - 1;
      final start = tester.getCenter(byKey('${bigTwoFaceKey(card)}#1'));
      final end = tester.getCenter(byKey('${bigTwoFaceKey(game.hand[to])}#1'));
      final gesture = await tester.startGesture(start);
      for (var i = 1; i <= 8; i++) {
        await gesture.moveTo(Offset.lerp(start, end, i / 8)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400)); // settled
      expect(game.hand.indexOf(card), to);
      final place = tester.getCenter(byKey('${bigTwoFaceKey(card)}#1'));
      expect((place - start).distance, greaterThan(60), reason: 'it lies somewhere else now');
      final turn = game.state.history.length;
      game.selectMove(bigTwoMoveText(0, play));
      await tester.pump();
      await tester.tap(byKey('play'));
      await tester.pump();
      await tester.pump();
      final flying = find.byKey(CardFlights.flyingKey(TablePile.flightTag(turn, 0)));
      expect(flying, findsOneWidget, reason: 'in the air');
      expect(
        (tester.getCenter(flying) - place).distance,
        lessThan(30),
        reason: 'it leaves from where the player put it',
      );
      await tester.pump(const Duration(seconds: 1));
      await closeSlowGame(tester);
    });

    testWidgets("a bot's play flies from its seat; a pass shows at the seat", (tester) async {
      final game = seededGame(training: false, speed: PlaybackSpeed.normal, seed: 5);
      await pumpGame(tester, game);
      var flew = false, passed = false;
      for (var guard = 0; guard < 2000 && !(flew && passed) && !game.isOver; guard++) {
        final before = game.state.history.length;
        if (game.myTurn) {
          final legal = game.state.legalMoves();
          game.humanMove(bigTwoMoveText(0, legal.firstWhere((p) => !p.isPass, orElse: () => legal.first)));
        }
        await tester.pump(const Duration(milliseconds: 40));
        final history = game.state.history;
        if (history.length == before || history.last.seat == 0) continue;
        final turn = history.length - 1;
        await tester.pump();
        final flying = find.byKey(CardFlights.flyingKey(TablePile.flightTag(turn, 0)));
        if (history.last.play.isPass) {
          expect(flying, findsNothing, reason: 'a pass flies nothing');
          if (game.state.passedSince.contains(history.last.seat)) {
            expect(
              find.descendant(
                of: byKey('seat ${history.last.seat}'),
                // A chip under a side seat's badge, or in the badge.
                matching: find.byWidgetPredicate(
                  (w) => w.key == const ValueKey('pass chip') || w.key == const ValueKey('pass in badge'),
                ),
              ),
              findsOneWidget,
              reason: 'Pass shows at the seat',
            );
            passed = true;
          }
        } else if (!flew) {
          expect(flying, findsOneWidget);
          final seat = tester.getCenter(byKey('seat ${history.last.seat}'));
          expect((tester.getCenter(flying) - seat).distance, lessThan(60), reason: 'it leaves from the seat');
          flew = true;
        }
      }
      expect((flew, passed), (true, true));
      await closeSlowGame(tester);
    });

    testWidgets('Instant: nothing flies, the cards are on the table at once', (tester) async {
      final game = seededGame(training: false, seed: 5);
      await pumpGame(tester, game);
      await toMyPlayableTurn(tester, game);
      final play = game.state.legalMoves().firstWhere((p) => !p.isPass);
      final turn = game.state.history.length;
      game.humanMove(bigTwoMoveText(0, play));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(CardFlights.flyingKey(TablePile.flightTag(turn, 0))), findsNothing);
      expect(byKey('pile play $turn'), findsOneWidget);
      await closeGame(tester);
    });
  });
}
