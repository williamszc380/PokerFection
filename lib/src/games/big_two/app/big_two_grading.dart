/// How Big Two moves are graded: by the points the coach expects a move to
/// give up this deal, against its pick, allowing for the coach's noise.
library;

import '../../../kit/coach_answer.dart';
import '../../../kit/grading.dart';
import '../big_two.dart';
import 'big_two_analysis.dart';

/// How many standard errors of a move's gap to the pick are put down to
/// chance before any of it counts as points lost: 2, so a move is marked
/// down only when the coach is about 98% sure it is worse.
///
/// The coach's numbers come from a few thousand play-outs, so a gap of a
/// point or more can be chance; graded on the raw gap, the same move in the
/// same position went from Best to Blunder with another seed.
const bigTwoNoiseErrors = 2.0;

/// How many more standard errors each grade below Best needs on top of the
/// one before, so one grade step is wider than the coach's noise. Measured
/// over the coach job's 30 check positions, four coach seeds each at the
/// desktop budget (tool/games/big_two_grade_spread.dart): with 2.5, 3 of
/// 182 moves changed grade by two steps between seeds (none by more);
/// graded on the raw gap, about one in ten did, some from Best to Blunder.
const bigTwoStepErrors = 2.5;

/// Penalty scoring (each loser pays per card left): points run from about
/// −39 to +39 a deal. The steps apply to the points a move is sure to lose
/// once the coach's noise is allowed for (GradeScale.sureLoss). Gaps run
/// from the pick, which ranks by survival in the search first and so need
/// not have the most points: a move worth at least as much is Best too.
const bigTwoPenaltyScale = GradeScale(
  unit: ValueUnit.points,
  cutoffs: [0.15, 0.5, 1.2, 2.5],
  noise: 0.15,
  scoreScale: 1.0,
  noiseErrors: bigTwoNoiseErrors,
  stepErrors: bigTwoStepErrors,
  fromPick: true,
);

/// Pusoy Dos scoring (only the winner scores, 1 point doubled per 2 in the
/// last play): a deal is worth about one point, so the same steps are ten
/// times smaller.
const bigTwoPusoyScale = GradeScale(
  unit: ValueUnit.points,
  cutoffs: [0.015, 0.05, 0.12, 0.25],
  noise: 0.015,
  scoreScale: 0.1,
  noiseErrors: bigTwoNoiseErrors,
  stepErrors: bigTwoStepErrors,
  fromPick: true,
);

/// The grading for a game under [rules]. Anything that grades a Big Two
/// answer (the game, a review, the tools) grades through this scale's
/// `mark`, which allows for each line's error.
GradeScale bigTwoScale(BigTwoRules rules) =>
    rules.scoring == BigTwoScoring.pusoyDos ? bigTwoPusoyScale : bigTwoPenaltyScale;

/// The coach's [report] as the kit's answer, graded on [scale]:
/// - the pick is the coach's first move (it ranks by survival in the
///   search first, so it need not have the highest points);
/// - each line's value is its expected points, with its win chance beside,
///   and the standard error of its gap to the pick (measured on the deals
///   all moves were played on), so the grade allows for the coach's noise;
/// - a move the search dropped early has few play-outs behind it, and its
///   points lost (floored at 0) can flatter it: it is graded at best Good;
/// - a proven win carries the proof 'sure'.
CoachAnswer bigTwoAnswer(BigTwoReport report, GradeScale scale) => CoachAnswer(
  unit: ValueUnit.points,
  pick: report.moves.isEmpty ? null : report.pick.move,
  detail: report,
  lines: [
    for (final m in report.moves)
      CoachLine(
        move: m.move,
        value: m.points,
        winChance: m.winChance,
        reasons: m.reasons,
        proof: m.sure ? 'sure' : null,
        minLoss: m.droppedEarly ? scale.cutoffs.first + 0.01 : 0,
        error: m.error,
      ),
  ],
);
