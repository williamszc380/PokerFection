/// How a move is graded against the coach's answer: Best / Good /
/// Inaccuracy / Mistake / Blunder (poker's DecisionGrade) with a 0–100
/// score.
library;

import 'dart:math';

import '../gto/spot_strategy.dart' show DecisionGrade;
import 'coach_answer.dart';

/// One game's grading: the losses where each grade ends, and how fast the
/// score falls.
class GradeScale {
  const GradeScale({
    required this.unit,
    required this.cutoffs,
    this.noise = 0,
    required this.scoreScale,
    this.noiseErrors = 0,
    this.stepErrors = 0,
    this.fromPick = false,
  });

  final ValueUnit unit;

  /// The highest loss of Best, Good, Inaccuracy and Mistake, in that order
  /// (four numbers; anything more is a Blunder).
  final List<double> cutoffs;

  /// Losses at or below this count as 0 (the coach's own noise).
  final double noise;

  /// score = round(100 * exp(-loss / scoreScale)).
  final double scoreScale;

  /// For a sampling coach whose lines carry an error (CoachLine.error): how
  /// many standard errors of a gap are put down to chance before any of it
  /// counts as lost (Big Two: 2, so a move is marked down only when the
  /// coach is about 98% sure it is worse). 0: the raw gap.
  final double noiseErrors;

  /// ... and how many more errors each grade below Best needs on top of the
  /// one before, so one grade step is wider than the coach's noise (Big
  /// Two: 2.5). See [sureLoss].
  final double stepErrors;

  /// Gaps are measured from the pick's value rather than from the highest
  /// value (Big Two: its pick ranks by survival in the search, so it need
  /// not have the highest points; a move worth at least the pick is Best).
  final bool fromPick;

  double _counted(double loss) => loss <= noise ? 0 : loss;

  DecisionGrade gradeFor(double loss) {
    final counted = _counted(loss);
    for (var i = 0; i < cutoffs.length; i++) {
      if (counted <= cutoffs[i]) return DecisionGrade.values[i];
    }
    return DecisionGrade.blunder;
  }

  int scoreFor(double loss) => (100 * exp(-_counted(loss) / scoreScale)).round();

  /// The loss [gap] is sure of, given the gap's standard error [error].
  ///
  /// With no error (or [noiseErrors] and [stepErrors] 0) this is the gap
  /// itself. Otherwise the gap that reaches each grade's cutoff grows: up
  /// to [noiseErrors] errors count as nothing, and grade k (Best 0, Good
  /// 1, ...) ends at its cutoff plus (noiseErrors + k * stepErrors) errors.
  /// In between the loss runs straight from one cutoff to the next, and
  /// past the last it grows one for one. So a move is graded as firmly as
  /// the coach can tell, and the same move graded from another seed of the
  /// coach moves one grade at most.
  double sureLoss(double gap, double error) {
    if (gap <= 0) return 0;
    if (error <= 0 || (noiseErrors == 0 && stepErrors == 0)) return gap;
    var fromGap = noiseErrors * error, fromLoss = 0.0;
    if (gap <= fromGap) return 0;
    for (var k = 0; k < cutoffs.length; k++) {
      final toGap = cutoffs[k] + (noiseErrors + k * stepErrors) * error;
      if (gap <= toGap) return fromLoss + (cutoffs[k] - fromLoss) * (gap - fromGap) / (toGap - fromGap);
      fromGap = toGap;
      fromLoss = cutoffs[k];
    }
    return fromLoss + gap - fromGap;
  }

  /// The mark for [played]: loss 0 for the answer's pick and its alsoBest
  /// moves; otherwise max(line.minLoss, the loss its gap is sure of), the
  /// gap running from the best value of any line (or, [fromPick], the
  /// pick's) down to the move's, allowing for the line's error (see
  /// [sureLoss]). Null when [played] is not rated: a move is never graded
  /// by guessing.
  MoveMark? mark(CoachAnswer answer, String played) {
    final line = answer.lineFor(played);
    final best = played == answer.pick || answer.alsoBest.contains(played);
    if (line == null && !best) return null;
    final top = fromPick ? (answer.lineFor(answer.pick)?.value ?? answer.bestValue) : answer.bestValue;
    final loss = best ? 0.0 : max(line!.minLoss, sureLoss(top! - line.value, line.error ?? 0));
    return MoveMark(
      grade: gradeFor(loss),
      loss: loss,
      score: scoreFor(loss),
      played: played,
      best: answer.pick,
      reasons: line?.reasons ?? const [],
      proof: line?.proof,
    );
  }
}

/// The grade of one move the player made, kept in the game's record.
class MoveMark {
  const MoveMark({
    required this.grade,
    required this.loss,
    required this.score,
    required this.played,
    required this.best,
    this.reasons = const [],
    this.proof,
    this.unit,
    this.bestTag,
  });

  final DecisionGrade grade;

  /// What the move gave up, in the game's unit (0 or more).
  final double loss;

  /// 0 to 100.
  final int score;

  /// The move made, and the coach's pick there.
  final String played;
  final String best;

  /// Reason codes for the move made (the game's strings give the text).
  final List<String> reasons;

  /// A proof behind the grade: 'missedWin:3' (Gomoku), 'sureWin'.
  final String? proof;

  /// The unit [loss] is in, when the game grades some moves in another unit
  /// than its GradeScale's (Fight the Landlord: the auction on points, the
  /// play on win chance); null: the scale's.
  final ValueUnit? unit;

  /// Whose move [best] is, as a GameStrings.tagLabel key ('count' in
  /// Blackjack's Cards seen mode), when it isn't the pick label's: the
  /// feedback then reads "Count: Stand"; null: the pick label.
  final String? bestTag;

  Map<String, Object?> toJson() => {
        'grade': grade.name,
        'loss': loss,
        'score': score,
        'played': played,
        'best': best,
        if (reasons.isNotEmpty) 'reasons': reasons,
        'proof': ?proof,
        'unit': ?unit?.name,
        'bestTag': ?bestTag,
      };

  /// The mark saved by [toJson], or null if [json] isn't one.
  static MoveMark? fromJson(Object? json) {
    try {
      if (json is! Map<String, Object?>) return null;
      return MoveMark(
        grade: DecisionGrade.values.byName(json['grade'] as String),
        loss: (json['loss'] as num).toDouble(),
        score: (json['score'] as num).toInt(),
        played: json['played'] as String,
        best: json['best'] as String,
        reasons: [for (final r in json['reasons'] as List? ?? const []) r as String],
        proof: json['proof'] as String?,
        unit: switch (json['unit']) {
          final String name => ValueUnit.values.byName(name),
          _ => null,
        },
        bestTag: json['bestTag'] as String?,
      );
    } on Object {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is MoveMark &&
      other.grade == grade &&
      other.loss == loss &&
      other.score == score &&
      other.played == played &&
      other.best == best &&
      other.proof == proof &&
      other.unit == unit &&
      other.bestTag == bestTag &&
      other.reasons.join('\u0000') == reasons.join('\u0000');

  @override
  int get hashCode => Object.hash(grade, loss, score, played, best, proof, unit, bestTag, reasons.length);

  @override
  String toString() => 'MoveMark(${grade.name} $played, best $best, loss $loss, score $score)';
}
