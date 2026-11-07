// What the coach and the bots report about their own search, for the app:
// which moves the search dropped early (graded at best Good), how sure it
// is of each gap to its pick (the fair comparison), the analysis a bot's
// move came from (for online spectators), and the time cap.
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';

import 'helpers.dart';

void main() {
  final standard = BigTwoRules.standard();

  /// The opening position of seeded deal [seed], for the seat that leads.
  BigTwoView opening(int seed) {
    final s = BigTwoState.deal(standard, seed: seed);
    return s.viewFor(s.toMove);
  }

  /// A mid-game position with many legal moves: seat 0 leads freely.
  BigTwoView freeLead() => dealOf(standard, [
    '3d 4c 5h 6s 7d 9c 9h Js Qd Kd As 2c',
    '3c 4d 5c',
    '6c 7c 8h',
    '8c 9s Th',
  ], leader: 0).viewFor(0);

  group('moves dropped early', () {
    test('successive halving marks the round each dropped move went out in, and keeps the rest unmarked', () {
      const halving = CoachBudget(playouts: 400, tree: false, inferencePool: 0);
      final a = const BigTwoCoach(budget: halving).analyze(freeLead(), seed: 3);
      final kept = a.candidates.where((c) => !c.droppedEarly).toList();
      final dropped = a.candidates.where((c) => c.droppedEarly).toList();
      expect(kept.length, inInclusiveRange(1, 3), reason: 'halving keeps up to three moves to the end');
      expect(dropped, isNotEmpty, reason: 'more than three legal moves, so some were dropped');
      expect(a.best.droppedEarly, isFalse, reason: 'the pick always stays to the end');
      expect(
        a.candidates.take(kept.length).every((c) => !c.droppedEarly),
        isTrue,
        reason: 'moves kept to the end rank above dropped ones',
      );
      for (final c in dropped) {
        expect(c.eliminatedAt, greaterThanOrEqualTo(0));
        expect(c.samples, lessThan(a.best.samples), reason: 'a dropped move has fewer play-outs');
      }
    });

    test('the tree search marks the moves it visited less than a quarter as often as its most visited one', () {
      final a = const BigTwoCoach(budget: CoachBudget(playouts: 600)).analyze(freeLead(), seed: 5);
      final most = a.candidates.map((c) => c.samples).reduce((x, y) => x > y ? x : y);
      for (final c in a.candidates) {
        expect(c.droppedEarly, c.samples * 4 < most, reason: '$c');
        if (c.droppedEarly) expect(c.eliminatedAt, 0);
      }
      expect(a.candidates.any((c) => c.droppedEarly), isTrue, reason: 'the search settles on a few moves');
      expect(a.best.droppedEarly, isFalse);
    });

    test('a proven win is never marked as dropped, however few play-outs it got', () {
      final s = dealOf(standard, ['3d 2s', '4c', '6c 7c Qh', '8c 9c Jh'], leader: 0);
      for (final tree in [true, false]) {
        final a = BigTwoCoach(budget: CoachBudget(playouts: 400, tree: tree)).analyze(s.viewFor(0));
        for (final c in a.candidates.where((c) => c.sureWin)) {
          expect(c.droppedEarly, isFalse, reason: 'tree $tree: $c');
        }
      }
    });

    test('a forced move is not marked', () {
      final s = dealOf(standard, ['3d', '4c 5c', '6c 7c', '8c 9c'], leader: 0);
      final a = const BigTwoCoach(budget: CoachBudget(playouts: 100)).analyze(s.viewFor(0));
      expect(a.candidates.single.droppedEarly, isFalse);
    });
  });

  group("the fair comparison (the coach panel's budget)", () {
    const budget = CoachBudget(playouts: 900, compareShare: 1 / 3);

    test('every move is played on the same deals, so each has the same play-outs behind its numbers', () {
      final a = const BigTwoCoach(budget: budget).analyze(freeLead(), seed: 5);
      final samples = a.candidates.map((c) => c.samples).toSet();
      expect(samples, hasLength(1), reason: 'the tree alone gives its favourite far more: ${a.candidates}');
      expect(samples.single, greaterThanOrEqualTo(24), reason: 'at least 24 deals each');
    });

    test('the pick has no gap to itself; every other move has an error on its gap', () {
      final a = const BigTwoCoach(budget: budget).analyze(freeLead(), seed: 5);
      expect(a.best.pointsError, 0);
      for (final c in a.candidates.skip(1)) {
        expect(c.pointsError, greaterThanOrEqualTo(0), reason: '$c');
        expect(c.pointsError.isFinite, isTrue, reason: '$c');
      }
      expect(a.candidates.skip(1).any((c) => c.pointsError > 0), isTrue);
    });

    test('no move scores clearly more than the pick: the tree keeps its pick only while the comparison agrees', () {
      for (final seed in [1, 2, 3, 4]) {
        for (final view in [freeLead(), opening(seed)]) {
          final a = const BigTwoCoach(budget: budget).analyze(view, seed: seed);
          for (final c in a.candidates.skip(1)) {
            expect(
              c.expectedPoints - a.best.expectedPoints,
              lessThanOrEqualTo(2 * c.pointsError + 1e-9),
              reason: 'seed $seed: $c against the pick ${a.best}',
            );
          }
          expect(a.best.droppedEarly, isFalse, reason: 'the pick is never marked as dropped');
        }
      }
    });

    test('after the pick, the moves follow by points', () {
      final a = const BigTwoCoach(budget: budget).analyze(freeLead(), seed: 2);
      final rest = a.candidates.skip(1).where((c) => !c.sureWin).map((c) => c.expectedPoints).toList();
      expect(rest, [...rest]..sort((x, y) => y.compareTo(x)));
    });

    test("successive halving compares on shared deals too: a dropped move's error is measured on the deals it shared with the pick", () {
      const halving = CoachBudget(playouts: 400, tree: false, inferencePool: 0);
      final a = const BigTwoCoach(budget: halving).analyze(freeLead(), seed: 3);
      expect(a.best.pointsError, 0);
      for (final c in a.candidates.skip(1)) {
        expect(c.pointsError.isFinite, isTrue, reason: '$c');
      }
    });

    test("the Hard bot's budget makes no comparison: all its play-outs go to finding its move", () {
      expect(CoachBudget.standard.compareShare, 0);
      expect(CoachBudget.coach.compareShare, closeTo(1 / 3, 1e-9));
      final a = const BigTwoCoach(budget: CoachBudget(playouts: 600)).analyze(freeLead(), seed: 5);
      expect(a.candidates.map((c) => c.samples).toSet().length, greaterThan(1), reason: 'the tree visits unevenly');
    });
  });

  group("a bot's decision", () {
    test('Medium and Hard give the analysis their move came from; it is the move chooseMove makes', () {
      for (final level in [BotLevel.medium, BotLevel.hard]) {
        final view = opening(8);
        final budget = level == BotLevel.hard ? const CoachBudget(playouts: 300) : null;
        final decision = BigTwoBot(level, seed: 4, budget: budget).decide(view);
        expect(decision.analysis, isNotNull, reason: '$level');
        expect(decision.play, decision.analysis!.best.play, reason: '$level plays the analysis\'s pick');
        expect(
          BigTwoBot(level, seed: 4, budget: budget).chooseMove(view),
          decision.play,
          reason: '$level: the same seed, the same move',
        );
        expect(
          decision.analysis!.candidates.map((c) => c.play).toSet(),
          view.legalMoves().toSet(),
          reason: 'every legal move is rated',
        );
      }
    });

    test('Easy, and any bot with a forced move, gives no analysis', () {
      expect(BigTwoBot(BotLevel.easy, seed: 2).decide(opening(8)).analysis, isNull);
      final forced = dealOf(standard, ['3d', '4c 5c', '6c 7c', '8c 9c'], leader: 0).viewFor(0);
      final decision = BigTwoBot(BotLevel.hard, seed: 2).decide(forced);
      expect(decision.analysis, isNull);
      expect(decision.play, play(standard, '3d'));
    });
  });

  test('a time cap of 0 ms still rates every legal move, each from at least one play-out', () {
    final view = opening(11);
    for (final tree in [true, false]) {
      final a = BigTwoCoach(budget: CoachBudget(maxMillis: 0, tree: tree, compareShare: 1 / 3)).analyze(view, seed: 1);
      expect(a.candidates.map((c) => c.play).toSet(), view.legalMoves().toSet());
      expect(a.playouts, lessThan(CoachBudget.standard.playouts), reason: 'it stopped early');
      for (final c in a.candidates) {
        expect(c.samples, greaterThanOrEqualTo(1), reason: 'tree $tree: $c');
        final numbers = [c.expectedPoints, c.pointsLost, c.pointsError];
        expect(numbers.every((x) => x.isFinite), isTrue, reason: 'tree $tree: $c');
      }
    }
  });
}
