import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/gto/spot_strategy.dart' show DecisionGrade;
import 'package:pokerfection/src/kit/coach_answer.dart';
import 'package:pokerfection/src/kit/grading.dart';

void main() {
  // Big Two's numbers from the design.
  const points = GradeScale(unit: ValueUnit.points, cutoffs: [0.15, 0.5, 1.2, 2.5], noise: 0.15, scoreScale: 1.0);

  test('each grade ends at its cutoff, and losses within the noise count as none', () {
    expect(
      [for (final loss in [0.0, 0.1, 0.15, 0.3, 0.5, 1.0, 2.0, 2.5, 3.0]) points.gradeFor(loss)],
      [
        DecisionGrade.best,
        DecisionGrade.best,
        DecisionGrade.best,
        DecisionGrade.good,
        DecisionGrade.good,
        DecisionGrade.inaccuracy,
        DecisionGrade.mistake,
        DecisionGrade.mistake,
        DecisionGrade.blunder,
      ],
    );
    expect(points.scoreFor(0.1), 100, reason: 'within the noise');
    expect(points.scoreFor(1.0), 37, reason: 'round(100 × e^−1)');
  });

  CoachAnswer answer({String? pick, Set<String> alsoBest = const {}}) => CoachAnswer(
        unit: ValueUnit.points,
        pick: pick,
        alsoBest: alsoBest,
        lines: const [
          CoachLine(move: 'a', value: 1.0, reasons: ['tempo']),
          CoachLine(move: 'b', value: 1.4),
          CoachLine(move: 'c', value: -0.6, reasons: ['breaksPair'], proof: 'loss:3'),
          CoachLine(move: 'd', value: 1.35, minLoss: 0.16),
        ],
      );

  test("the pick is the first line unless given; it is graded Best even when another line's value is higher", () {
    expect(answer().pick, 'a');
    final mark = points.mark(answer(), 'a')!;
    expect([mark.grade, mark.loss, mark.score, mark.best], [DecisionGrade.best, 0.0, 100, 'a']);
    expect(mark.reasons, ['tempo']);
  });

  test('other moves lose against the highest value of any line', () {
    final mark = points.mark(answer(), 'c')!;
    expect(mark.loss, closeTo(2.0, 1e-9), reason: '1.4 − (−0.6)');
    expect([mark.grade, mark.played, mark.best, mark.proof], [DecisionGrade.mistake, 'c', 'a', 'loss:3']);
    expect(points.mark(answer(), 'b')!.grade, DecisionGrade.best, reason: 'the highest value loses nothing');
  });

  test('alsoBest moves are Best too (Blackjack: the best play when the chart differs)', () {
    final mark = points.mark(answer(pick: 'b', alsoBest: {'c'}), 'c')!;
    expect([mark.grade, mark.loss, mark.best], [DecisionGrade.best, 0.0, 'b']);
  });

  test('minLoss floors a move dropped early in the search: at best Good', () {
    final mark = points.mark(answer(), 'd')!;
    expect(mark.loss, 0.16, reason: 'its own loss, 0.05, is below the floor');
    expect(mark.grade, DecisionGrade.good);
  });

  test('a move the answer did not rate gets no mark: grades are never guessed', () {
    expect(points.mark(answer(), 'z'), isNull);
  });

  test('marks are kept as JSON and read back; anything else reads as null', () {
    final mark = points.mark(answer(), 'c')!;
    expect(MoveMark.fromJson(mark.toJson()), mark);
    expect(MoveMark.fromJson({'grade': 'superb'}), isNull);
    expect(MoveMark.fromJson('best'), isNull);
  });

  group('a sampling coach (lines with an error)', () {
    // Big Two's: 2 errors count as nothing, each grade 2.5 more.
    const sampled = GradeScale(
      unit: ValueUnit.points,
      cutoffs: [0.15, 0.5, 1.2, 2.5],
      noise: 0.15,
      scoreScale: 1.0,
      noiseErrors: 2,
      stepErrors: 2.5,
      fromPick: true,
    );

    test('with no error, or a scale that allows none, the loss is the raw gap', () {
      expect(sampled.sureLoss(1.3, 0), 1.3);
      expect(points.sureLoss(1.3, 0.4), 1.3, reason: 'noiseErrors and stepErrors 0');
      expect(sampled.sureLoss(-0.2, 0.4), 0, reason: 'worth more than the pick: nothing lost');
    });

    test('up to noiseErrors errors are chance; each grade needs stepErrors more than the one before', () {
      expect(sampled.sureLoss(0.8, 0.4), 0, reason: '0.8 is 2 errors: chance');
      // Best ends at 0.15 + 2 × 0.4 = 0.95; Good at 0.5 + 4.5 × 0.4 = 2.3.
      expect(sampled.sureLoss(0.95, 0.4), closeTo(0.15, 1e-9));
      expect(sampled.sureLoss(2.3, 0.4), closeTo(0.5, 1e-9));
      expect(sampled.sureLoss(1.625, 0.4), closeTo(0.325, 1e-9), reason: 'straight between two cutoffs');
      // Past the last cutoff (2.5 + 9.5 × 0.4 = 6.3) it grows one for one.
      expect(sampled.sureLoss(7.3, 0.4), closeTo(3.5, 1e-9));
    });

    test("mark allows for each line's error, measured from the pick (fromPick)", () {
      final answer = CoachAnswer(
        unit: ValueUnit.points,
        pick: 'a',
        lines: const [
          CoachLine(move: 'a', value: 1.0),
          CoachLine(move: 'b', value: 1.4, error: 0.3),
          CoachLine(move: 'c', value: -0.3, error: 0.4),
          CoachLine(move: 'd', value: 0.2, error: 0.01, minLoss: 0.16),
        ],
      );
      expect(sampled.mark(answer, 'b')!.grade, DecisionGrade.best, reason: 'worth more than the pick');
      final c = sampled.mark(answer, 'c')!;
      expect(c.loss, closeTo(0.5 * (1.3 - 0.95) / (2.3 - 0.95) + 0.15 * (1 - (1.3 - 0.95) / (2.3 - 0.95)), 1e-9));
      expect(c.grade, DecisionGrade.good, reason: 'a raw gap of 1.3 would be a Mistake');
      expect(sampled.mark(answer, 'd')!.loss, greaterThan(0.16), reason: 'minLoss still floors it');
      expect(points.mark(answer, 'c')!.loss, closeTo(1.7, 1e-9), reason: 'the default: from the best value, raw');
    });
  });

  test("a mark keeps the unit it was graded in and whose best move it shows, when the game gives them", () {
    const mark = MoveMark(
      grade: DecisionGrade.mistake,
      loss: 0.8,
      score: 45,
      played: 'bid 3',
      best: 'pass',
      unit: ValueUnit.points,
      bestTag: 'count',
    );
    expect(MoveMark.fromJson(mark.toJson()), mark);
    expect(mark.toJson()['unit'], 'points');
    final plain = points.mark(answer(), 'c')!;
    expect(plain.toJson().containsKey('unit'), isFalse, reason: 'nothing new is saved unless a game sets it');
    expect([plain.unit, plain.bestTag], [null, null]);
  });

  group('values as shown', () {
    test('win chances as whole percentages; points with one decimal; bets with two; all signed', () {
      expect(formatValue(ValueUnit.winChance, 0.62), '62%');
      expect(formatValue(ValueUnit.winChance, -0.07), '−7%');
      expect(formatValue(ValueUnit.points, 1.4), '+1.4');
      expect(formatValue(ValueUnit.points, -0.25), '−0.3');
      expect(formatValue(ValueUnit.bets, -0.03), '−0.03');
      expect(formatValue(ValueUnit.bets, 0.5), '+0.50');
      expect(formatValue(ValueUnit.points, 0), '0.0');
    });

    test('a small amount that is not zero never reads as zero', () {
      expect(formatValue(ValueUnit.winChance, -0.004), '−0.4%');
      expect(formatValue(ValueUnit.bets, -0.004), '−0.004');
    });
  });
}
