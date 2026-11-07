/// How Fight the Landlord grades a move against the coach's answer.
///
/// Play is judged on the chance of winning the deal, as the coach ranks it;
/// the auction on points, because bidding higher only pays when the hand
/// wins often enough (the coach ranks bids that way too).
library;

import 'dart:math';

import '../../../kit/coach_answer.dart';
import '../../../kit/grading.dart';
import 'doudizhu_analysis.dart';
import 'doudizhu_record.dart';

/// Grades in play, on win chance (0 to 1). The coach's estimates move by
/// about a point from run to run, so a loss up to 1% counts as none.
const ddzPlayScale = GradeScale(
  unit: ValueUnit.winChance,
  cutoffs: [0.01, 0.03, 0.07, 0.15],
  noise: 0.01,
  scoreScale: 0.05,
);

/// Grades in the auction, on expected points. A few hundred play-outs per
/// estimate leave about a tenth of a point of noise.
const ddzBidScale = GradeScale(
  unit: ValueUnit.points,
  cutoffs: [0.15, 0.4, 0.8, 1.6],
  noise: 0.1,
  scoreScale: 0.6,
);

/// The scale of an answer in [unit].
GradeScale ddzScaleFor(ValueUnit unit) => unit == ValueUnit.points ? ddzBidScale : ddzPlayScale;

/// The proofs a coach line can carry: a certain win or a certain loss.
const ddzSureWin = 'win', ddzSureLoss = 'loss';

/// The coach's advice as the kit's answer, ranked as the coach ranked it
/// (the pick is its first move). Each line's value is its win chance in
/// play and its points in the auction; the other number rides along.
///
/// The coach drops clearly worse moves early and stops dealing to them, so
/// a dropped move can show a lucky average above the pick's from its few
/// deals. Such a move is at best Good ([CoachLine.minLoss]), never Best.
CoachAnswer ddzAnswer(DdzAdvice advice) {
  final unit = advice.bidding ? ValueUnit.points : ValueUnit.winChance;
  final scale = ddzScaleFor(unit);
  final pickSamples = advice.lines.isEmpty ? 0 : advice.lines.first.samples;
  return CoachAnswer(
    unit: unit,
    detail: advice,
    lines: [
      for (final line in advice.lines)
        CoachLine(
          move: line.move,
          value: advice.bidding ? line.points : line.winChance,
          winChance: line.winChance,
          points: line.points,
          reasons: [for (final r in line.reasons) r.name],
          proof: line.proven ? (line.winChance >= 1 ? ddzSureWin : ddzSureLoss) : null,
          minLoss: line.samples < pickSamples ? scale.cutoffs.first + 0.001 : 0,
        ),
    ],
  );
}

/// The grade of [played] (a record move, card ids and all) against
/// [answer], or null when the coach didn't rate it. Its loss is in the
/// answer's unit, which the mark carries.
///
/// The loss is measured from the pick, as the engine's lossOf does, not
/// from the highest number on the list: a lucky early-dropped move must not
/// raise the bar for every other move.
MoveMark? ddzMark(CoachAnswer answer, String played) {
  final key = ddzMoveKey(played);
  final line = answer.lineFor(key);
  final pick = answer.lineFor(answer.pick);
  if (line == null || pick == null) return null;
  final scale = ddzScaleFor(answer.unit);
  final loss = key == answer.pick ? 0.0 : max(line.minLoss, max(0.0, pick.value - line.value));
  return MoveMark(
    grade: scale.gradeFor(loss),
    loss: loss,
    score: scale.scoreFor(loss),
    played: key,
    best: answer.pick,
    reasons: line.reasons,
    proof: line.proof,
    // The auction's losses are points, play's win chance: the mark says
    // which, so the grade card and the review show each in its own unit.
    unit: answer.unit,
  );
}
