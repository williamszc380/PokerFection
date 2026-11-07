import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_analysis.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_grading.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/gto/spot_strategy.dart' show DecisionGrade;
import 'package:pokerfection/src/kit/coach_answer.dart';
import 'package:pokerfection/src/kit/grading.dart';

DdzAdviceLine line(String move, double win, {double points = 0, int n = 100, bool proven = false, List<DdzReason> r = const []}) =>
    DdzAdviceLine(move: move, winChance: win, points: points, samples: n, proven: proven, reasons: r);

DdzAdvice play(List<DdzAdviceLine> lines) =>
    DdzAdvice(seat: 0, bidding: false, objective: DdzObjective.winChance, legalMoves: lines.length, lines: lines);

void main() {
  group('the coach\'s advice as the kit\'s answer', () {
    test('in play the value is the win chance, with the points beside it; the pick is the coach\'s first move', () {
      final answer = ddzAnswer(play([
        line('0:xpair:77', 0.62, points: 1.4, r: [DdzReason.keepsBomb]),
        line('0:p', 0.55, points: 0.8),
      ]));
      expect(answer.unit, ValueUnit.winChance);
      expect(answer.pick, '0:xpair:77');
      expect(answer.lines.first.value, 0.62);
      expect(answer.lines.first.points, 1.4);
      expect(answer.lines.first.winChance, 0.62);
      expect(answer.lines.first.reasons, ['keepsBomb']);
      expect(answer.detail, isA<DdzAdvice>());
    });

    test('in the auction the value is points, because a higher bid only pays when the hand wins enough', () {
      final answer = ddzAnswer(DdzAdvice(
        seat: 1,
        bidding: true,
        objective: DdzObjective.points,
        legalMoves: 2,
        lines: [line('1:b0', 0.4, points: -0.2), line('1:b3', 0.6, points: -0.5)],
      ));
      expect(answer.unit, ValueUnit.points);
      expect(answer.lines.map((l) => l.value), [-0.2, -0.5]);
      expect(ddzMark(answer, '1:b3')!.loss, closeTo(0.3, 1e-9));
    });

    test("each mark says its unit, so a bid's loss shows in points and a play's in win chance", () {
      final bid = ddzAnswer(DdzAdvice(
        seat: 0,
        bidding: true,
        objective: DdzObjective.points,
        legalMoves: 2,
        lines: [line('0:b0', 0.4, points: -0.2), line('0:b3', 0.6, points: -0.5)],
      ));
      expect(ddzMark(bid, '0:b3')!.unit, ValueUnit.points);
      final card = ddzAnswer(play([line('0:xsolo:3', 0.6), line('0:xsolo:4', 0.5)]));
      expect(ddzMark(card, '0:xsolo:4|4')!.unit, ValueUnit.winChance);
      // Kept in the saved game, for the review.
      expect(MoveMark.fromJson(ddzMark(bid, '0:b3')!.toJson())!.unit, ValueUnit.points);
    });

    test('a certain result is a proof: a sure win or a sure loss', () {
      final answer = ddzAnswer(play([line('0:xsolo:3', 1, proven: true), line('0:p', 0, proven: true), line('0:xsolo:4', 0.5)]));
      expect(answer.lines.map((l) => l.proof), [ddzSureWin, ddzSureLoss, null]);
    });
  });

  group('grades', () {
    test('the pick is Best; a move is graded by what it gives up from the pick', () {
      final answer = ddzAnswer(play([line('0:xsolo:3', 0.60), line('0:xsolo:5', 0.585), line('0:xsolo:9', 0.50), line('0:p', 0.30)]));
      expect(ddzMark(answer, '0:xsolo:3|0')!.grade, DecisionGrade.best);
      expect(ddzMark(answer, '0:xsolo:5|20')!.grade, DecisionGrade.good);
      expect(ddzMark(answer, '0:xsolo:9|24')!.grade, DecisionGrade.mistake);
      expect(ddzMark(answer, '0:p')!.grade, DecisionGrade.blunder);
      expect(ddzMark(answer, '0:xsolo:3|0')!.score, 100);
    });

    test('which suit the player picked does not matter: the mark keeps the move without its cards', () {
      final answer = ddzAnswer(play([line('0:xpair:77', 0.6)]));
      final mark = ddzMark(answer, '0:xpair:77|20,23')!;
      expect(mark.played, '0:xpair:77');
      expect(mark.best, '0:xpair:77');
    });

    test('a loss within the coach\'s noise (1%) is still Best', () {
      final answer = ddzAnswer(play([line('0:xsolo:3', 0.600), line('0:xsolo:4', 0.592)]));
      expect(ddzMark(answer, '0:xsolo:4')!.grade, DecisionGrade.best);
    });

    test('a move the coach dropped early is at best Good, even with a lucky higher average', () {
      final answer = ddzAnswer(play([line('0:xsolo:3', 0.60, n: 400), line('0:xsolo:K', 0.70, n: 50), line('0:xsolo:9', 0.55, n: 400)]));
      expect(ddzMark(answer, '0:xsolo:K')!.grade, DecisionGrade.good);
      // And it doesn't raise the bar for the others: measured from the pick.
      expect(ddzMark(answer, '0:xsolo:9')!.loss, closeTo(0.05, 1e-9));
    });

    test('a move the coach did not rate is not graded (the controller asks again with it included)', () {
      final answer = ddzAnswer(play([line('0:xsolo:3', 0.6)]));
      expect(ddzMark(answer, '0:xsolo:4|4'), isNull);
    });
  });
}
