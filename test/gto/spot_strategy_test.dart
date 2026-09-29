import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/engine/actions.dart';
import 'package:pokerfection/src/engine/events.dart';
import 'package:pokerfection/src/engine/poker_hand.dart';
import 'package:pokerfection/src/gto/preflop/preflop_advisor.dart';
import 'package:pokerfection/src/gto/preflop/preflop_equity.dart';
import 'package:pokerfection/src/gto/preflop/preflop_solver.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tracker.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tree.dart';
import 'package:pokerfection/src/gto/spot_strategy.dart';

SpotStrategy exampleSpot() => const SpotStrategy(
      handName: 'AJo',
      actions: [
        SpotAction(kind: SpotActionKind.fold, amount: 0, action: PlayerAction.fold()),
        SpotAction(kind: SpotActionKind.call, amount: 250, action: PlayerAction.call()),
        SpotAction(kind: SpotActionKind.raise, amount: 750, action: PlayerAction.raiseTo(750)),
        SpotAction(kind: SpotActionKind.allIn, amount: 10000, action: PlayerAction.raiseTo(10000)),
      ],
      frequencies: [0, 0.35, 0.65, 0],
      evs: [0, 1.21, 1.24, -0.85],
    );

void main() {
  test('scores the example from our discussion', () {
    final score = scoreDecision(exampleSpot(), [0.3, 0.2, 0.4, 0.1]);
    // Counted from GTO's own mix, which gives up 0.0105 BB against the best action.
    expect(score.evLoss, closeTo(0.587 - 0.0105, 0.001));
    // Fold / call / raise: 0.3 / 0.2 / 0.5 against 0 / 0.35 / 0.65 (70% alike);
    // raises split 80/20 against 100/0 (80% alike), counting a tenth.
    expect(score.mixMatch, closeTo(0.9 * 0.7 + 0.1 * 0.8, 1e-9));
    // The all-in's 0.209 BB lost to the better size counts a tenth.
    expect(score.scoredLoss, closeTo(0.378 + 0.0209 - 0.0105, 0.001));
    expect(score.grade, DecisionGrade.mistake);
  });

  test('matching GTO exactly scores 100', () {
    final score = scoreDecision(exampleSpot(), [0, 0.35, 0.65, 0]);
    expect(score.mixMatch, 1);
    expect(score.evLoss, 0, reason: 'playing GTO''s own mix loses nothing');
    expect(score.grade, DecisionGrade.best);
    expect(score.score, greaterThanOrEqualTo(98));
  });

  test('a pure strategy inside the GTO mix loses little EV but misses the mix', () {
    final score = scoreDecision(exampleSpot(), [0, 0, 1, 0]);
    expect(score.evLoss, 0);
    expect(score.mixMatch, closeTo(0.9 * 0.65 + 0.1, 1e-9));
  });

  test('fold, check or call, and raise count most; raise sizes little', () {
    const spot = SpotStrategy(
      handName: 'KQs',
      actions: [
        SpotAction(kind: SpotActionKind.fold, amount: 0, action: PlayerAction.fold()),
        SpotAction(kind: SpotActionKind.call, amount: 250, action: PlayerAction.call()),
        SpotAction(kind: SpotActionKind.raise, amount: 750, action: PlayerAction.raiseTo(750)),
        SpotAction(kind: SpotActionKind.raise, amount: 1000, action: PlayerAction.raiseTo(1000)),
      ],
      frequencies: [0, 0.4, 0.6, 0],
      evs: [0, 1.0, 1.0, 0.8],
    );
    // Right choices, all raises with the other size: small cost.
    final sizes = scoreDecision(spot, [0, 0.4, 0, 0.6]);
    expect(sizes.evLoss, closeTo(0.12, 1e-9));
    expect(sizes.grade, DecisionGrade.best);
    expect(sizes.score, greaterThanOrEqualTo(90));
    // Folding instead of calling: big cost.
    final choice = scoreDecision(spot, [0.4, 0, 0.6, 0]);
    expect(choice.score, lessThan(50));
    expect(choice.grade, DecisionGrade.mistake);
  });

  test('rebalancing keeps the total at 100, in steps of 1% by default', () {
    expect(rebalancePercents([25, 25, 25, 25], 0, 40), [40, 20, 20, 20]);
    expect(rebalancePercents([100, 0, 0], 0, 60), [60, 40, 0]);
    expect(rebalancePercents([0, 50, 50], 2, 100), [0, 0, 100]);
    expect(rebalancePercents([30, 70], 1, 33), [67, 33]);
    expect(rebalancePercents([30, 70], 1, 33, step: 5), [65, 35]);
    final rng = Random(3);
    for (var trial = 0; trial < 500; trial++) {
      var values = [100, 0, 0, 0, 0];
      final step = trial.isEven ? 1 : 5;
      for (var move = 0; move < 10; move++) {
        values = rebalancePercents(values, rng.nextInt(5), rng.nextInt(101), step: step);
        expect(values.reduce((a, b) => a + b), 100);
        expect(values.every((v) => v >= 0 && v % step == 0), isTrue);
      }
    }
  });

  test('a choice GTO never makes is never shown as better than what it does', () {
    final spot = SpotStrategy.normalized(
      handName: 'AA',
      actions: exampleSpot().actions,
      frequencies: [0, 0, 2, 0],
      evs: [0, 5.0, 4.0, 7.0],
    );
    expect(spot.frequencies, [0, 0, 1, 0]);
    expect(spot.evs, [0, 4.0, 4.0, 4.0]);
  });

  test("the user's answers cover every choice, the same ones every time", () async {
    final equity =
        PreflopEquity.fromBytes(ByteData.sublistView(File('assets/preflop_equity.bin').readAsBytesSync()));
    final stacks = [2000, 3500, 1200, 5000];
    const multiples = PreflopSettings.defaultRaiseMultiples;
    final rng = Random(7);
    Future<PreflopSolution> solveSubgame(PreflopSpec spec, Float64List? ranges) async =>
        PreflopSolver(PreflopTree(spec), equity, ranges: ranges).solve(iterations: 30);
    var answers = 0;
    for (var button = 0; button < stacks.length; button++) {
      final spec = PreflopAdvisor.specFor(
          stacksBySeat: stacks, buttonSeat: button, smallBlind: 50, bigBlind: 100, ante: 10);
      final blueprint = PreflopAdvisor(PreflopSolver(PreflopTree(spec), equity).solve(iterations: 40));
      for (var i = 0; i < 8; i++) {
        const hero = 0;
        final tracker = PreflopTracker(blueprint: blueprint, solveSubgame: solveSubgame, heroSeat: hero);
        final hand = PokerHand(
          stacks: stacks,
          buttonSeat: button,
          smallBlind: 50,
          bigBlind: 100,
          ante: 10,
          random: rng,
        );
        while (!hand.isOver && hand.street == Street.preflop) {
          if (hand.toAct != hero) {
            final move = tracker.sample(hand, rng);
            expect(move, isNotNull, reason: 'button $button hand $i left the solved lines');
            hand.act(move!);
            continue;
          }
          await tracker.prepare(hand);
          final spot = tracker.spotFor(hand)!;
          answers++;
          final legal = hand.legalActions();
          expect([for (final a in spot.actions) a.kind], [
            SpotActionKind.fold,
            legal.canCheck ? SpotActionKind.check : SpotActionKind.call,
            // Sizes bigger than the stack are left out.
            for (final m in multiples)
              if (PreflopTree.raiseSize(legal.currentBet, m) < legal.maxRaiseTo) SpotActionKind.raise,
            SpotActionKind.allIn,
          ]);
          expect(spot.frequencies.reduce((a, b) => a + b), closeTo(1, 1e-9));
          expect(spot.actions[0].available, legal.canFold);
          expect(spot.actions[1].available, isTrue);
          expect(spot.actions.last.available, legal.canRaise);
          for (var k = 0; k < spot.actions.length; k++) {
            final a = spot.actions[k];
            expect(spot.evs[k].isFinite, a.available, reason: '${a.kind} ${a.unavailable} ${spot.evs[k]}');
            if (!a.available) expect(spot.frequencies[k], 0);
            if (a.kind == SpotActionKind.fold && a.available) expect(spot.evs[k], closeTo(0, 1e-9));
            if (a.kind == SpotActionKind.raise && a.available) {
              expect(a.amount, inInclusiveRange(legal.minRaiseTo, legal.maxRaiseTo - 1));
            }
          }
          hand.act(drawAction(spot, rng));
        }
      }
    }
    expect(answers, greaterThan(20));
  });
}
