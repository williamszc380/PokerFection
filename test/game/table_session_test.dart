import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/bots/bot.dart';
import 'package:pokerfection/src/bots/preflop_ranking.dart';
import 'package:pokerfection/src/engine/actions.dart';
import 'package:pokerfection/src/engine/cards.dart';
import 'package:pokerfection/src/engine/positions.dart';
import 'package:pokerfection/src/game/table_session.dart';

import '../helpers.dart';

void main() {
  test('bots only make legal decisions, across many table setups', () {
    for (var seed = 0; seed < 20; seed++) {
      final rng = Random(seed);
      final n = 2 + rng.nextInt(7);
      final positions = positionsForTable(n);
      final config = TableConfig.quick(
        playerCount: n,
        stackBb: const [10, 20, 40, 100, 200][rng.nextInt(5)],
        ante: rng.nextBool() ? 0 : 10,
        opponentStyle: rng.nextBool() ? null : BotStyle.values[rng.nextInt(BotStyle.values.length)],
        resetStacksEachHand: rng.nextBool(),
        heroPosition: rng.nextBool() ? null : positions[rng.nextInt(n)],
      );
      final session = TableSession(config, random: rng);
      for (var i = 0; i < 20; i++) {
        final hand = session.startHand();
        var steps = 0;
        while (!hand.isOver) {
          expect(++steps, lessThan(300), reason: 'seed $seed hand $i never finished');
          final action =
              session.isHeroTurn ? randomAction(hand.legalActions(), rng) : session.botDecision();
          hand.act(action); // throws if a bot chose something illegal
        }
        session.finishHand();
        var before = 0, after = 0;
        for (var s = 0; s < n; s++) {
          before += hand.startingStackOf(s);
          after += hand.stackOf(s);
        }
        expect(after, before, reason: 'seed $seed hand $i');
      }
      expect(session.handsFinished, 20);
    }
  });

  test('a fixed position keeps the user in that seat every hand', () {
    final session =
        TableSession(TableConfig.quick(playerCount: 6, heroPosition: Position.co), random: Random(3));
    for (var i = 0; i < 5; i++) {
      final hand = session.startHand();
      expect(hand.positionOf(TableSession.heroSeat), Position.co);
      while (!hand.isOver) {
        hand.act(session.isHeroTurn ? const PlayerAction.fold() : session.botDecision());
      }
    }
  });

  test('without a fixed position the button moves one seat per hand', () {
    final session = TableSession(TableConfig.quick(playerCount: 4), random: Random(5));
    int? previous;
    for (var i = 0; i < 6; i++) {
      final hand = session.startHand();
      if (previous != null) expect(hand.buttonSeat, (previous + 1) % 4);
      previous = hand.buttonSeat;
      while (!hand.isOver) {
        hand.act(session.isHeroTurn ? const PlayerAction.fold() : session.botDecision());
      }
    }
  });

  test('stacks carry over when they are not reset', () {
    final session = TableSession(
      TableConfig.quick(playerCount: 3, resetStacksEachHand: false),
      random: Random(9),
    );
    final hand = session.startHand();
    while (!hand.isOver) {
      hand.act(session.isHeroTurn ? const PlayerAction.fold() : session.botDecision());
    }
    session.finishHand();
    final next = session.startHand();
    for (var s = 0; s < 3; s++) {
      expect(next.startingStackOf(s), hand.stackOf(s) == 0 ? 10000 : hand.stackOf(s));
    }
  });

  test('starting hand ranking puts aces first and 7-2 offsuit near the end', () {
    double p(String cards) {
      final c = parseCards(cards);
      return preflopPercentile(c[0], c[1]);
    }

    expect(p('As Ah'), closeTo(6 / 1326, 1e-9));
    expect(p('As Ks'), lessThan(p('As Kd')));
    expect(p('Ks Kh'), lessThan(p('Qs Qh')));
    expect(p('7c 2d'), greaterThan(0.9));
    expect(handClassLabel(PlayingCard.parse('Ts'), PlayingCard.parse('9s')), 'T9s');
  });
}
