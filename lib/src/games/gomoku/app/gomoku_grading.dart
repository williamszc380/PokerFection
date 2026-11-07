/// How Gomoku grades the player's moves: with the engine's own grading
/// (GomokuAnalysis.grade, proofs first, then how much win chance the move
/// gives up), mapped one to one onto the app's grades.
library;

import 'dart:math';

import '../../../gto/spot_strategy.dart' show DecisionGrade;
import '../../../kit/coach_answer.dart';
import '../../../kit/grading.dart';
import '../gomoku.dart';

/// The loss cutoffs are the engine's (2%, 7%, 15%, 30% of win chance); the
/// score falls to 37 at a 10% loss.
const gomokuScale = GradeScale(unit: ValueUnit.winChance, cutoffs: [0.02, 0.07, 0.15, 0.30], scoreScale: 0.10);

/// The app's grade for the engine's.
DecisionGrade gomokuDecision(MoveGrade grade) => switch (grade) {
  MoveGrade.best => DecisionGrade.best,
  MoveGrade.good => DecisionGrade.good,
  MoveGrade.inaccuracy => DecisionGrade.inaccuracy,
  MoveGrade.mistake => DecisionGrade.mistake,
  MoveGrade.blunder => DecisionGrade.blunder,
};

/// The mark for [played] (Renju notation) by [analysis], or null when the
/// coach didn't analyse that move: the kit then asks again with the move
/// included, rather than guess.
///
/// - The grade is the engine's.
/// - The loss is the win chance given up against the best move (none for a
///   Best move: a slower proven win gives up nothing). When proofs decided
///   the grade, the estimate can say less than the grade does: two proven
///   losses are both 0%, and a missed forced win the search still rates
///   may cost 1%. Then the loss is the middle of the grade's band, so the
///   card never reads "Good 0%" and a mistake never scores 100.
/// - The score follows the loss, except a Blunder that allows a proven loss
///   scores 0.
/// - The proof says why when a proof decided: 'missedWin:3' (a forced win in
///   3 was there), 'allowsLoss:2' (the opponent now wins in 2), 'win:4'.
MoveMark? gomokuMark(GomokuAnalysis analysis, String played) {
  final GomokuMove move;
  try {
    move = GomokuMove.parse(played);
  } on FormatException {
    return null;
  }
  final top = analysis.best;
  final mine = analysis.of(move);
  if (top == null || mine == null) return null;
  final grade = gomokuDecision(analysis.grade(move));
  final loss = _lossFor(grade, max(0.0, top.winChance - mine.winChance));
  final provenLoss = mine.isProvenLoss && !top.isProvenLoss;
  final proof = switch (mine) {
    MoveAnalysis(:final winsIn?) => 'win:$winsIn',
    _ when mine.reasons.contains(MoveReason.missesForcedWin) => 'missedWin:${analysis.winsIn ?? top.winsIn ?? 0}',
    MoveAnalysis(:final losesIn?) when provenLoss => 'allowsLoss:$losesIn',
    _ => null,
  };
  return MoveMark(
    grade: grade,
    loss: loss,
    score: grade == DecisionGrade.blunder && provenLoss ? 0 : gomokuScale.scoreFor(loss),
    played: move.notation,
    best: top.move.notation,
    reasons: [for (final r in mine.reasons) r.name],
    proof: proof,
  );
}

/// [estimate] if it lies inside [grade]'s band of [gomokuScale], else the
/// middle of the band (a Blunder's band has no top: half a Mistake band
/// past its start). Best always loses nothing.
double _lossFor(DecisionGrade grade, double estimate) {
  if (grade == DecisionGrade.best) return 0;
  final cutoffs = gomokuScale.cutoffs;
  final i = grade.index;
  final low = cutoffs[i - 1];
  final high = i < cutoffs.length ? cutoffs[i] : low + (low - cutoffs[i - 2]);
  return estimate > low ? estimate : (low + high) / 2;
}
