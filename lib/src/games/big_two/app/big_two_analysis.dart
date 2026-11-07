/// The coach's analysis as plain JSON: what a coach job sends back, what a
/// bot job may carry beside its move (for online spectators), and what the
/// screen reads its coach lines and hand plan from.
///
/// Moves are in the record's notation ([bigTwoMoveText]), so a rated move
/// compares as text with the move the player makes. Timing is left out,
/// so the same input always gives the same output.
library;

import '../big_two.dart';
import 'big_two_record.dart';

/// One rated move.
class BigTwoRating {
  const BigTwoRating({
    required this.move,
    required this.winChance,
    required this.points,
    required this.samples,
    this.sure = false,
    this.reasons = const [],
    this.pointsLost = 0,
    this.error = 0,
    this.eliminatedAt,
  });

  /// The move, `"<seat>:<cards>"` or `"<seat>:pass"`.
  final String move;

  /// Chance of going out first, 0 to 1.
  final double winChance;

  /// Average points won or lost this deal.
  final double points;

  /// Play-outs behind the numbers.
  final int samples;

  /// Proven to win whatever the others hold.
  final bool sure;

  /// [CoachReason] names, in the engine's order.
  final List<String> reasons;

  /// Points given up against the coach's pick (0 or more).
  final double pointsLost;

  /// The standard error of [points] (BigTwoCandidate.pointsError): the
  /// grading looks past gaps this small.
  final double error;

  /// The search dropped this move early (BigTwoCandidate.eliminatedAt), so
  /// its numbers rest on few play-outs; null: kept to the end.
  final int? eliminatedAt;

  bool get droppedEarly => eliminatedAt != null;

  Map<String, Object?> toJson() => {
    'move': move,
    'win': _round(winChance),
    'pts': _round(points),
    'n': samples,
    if (sure) 'sure': true,
    if (reasons.isNotEmpty) 'why': reasons,
    if (pointsLost != 0) 'lost': _round(pointsLost),
    if (error != 0) 'se': _round(error),
    'out': ?eliminatedAt,
  };

  factory BigTwoRating.fromJson(Object? json) {
    final map = json! as Map<String, Object?>;
    return BigTwoRating(
      move: map['move']! as String,
      winChance: (map['win']! as num).toDouble(),
      points: (map['pts']! as num).toDouble(),
      samples: map['n']! as int,
      sure: map['sure'] as bool? ?? false,
      reasons: [for (final r in map['why'] as List? ?? const []) r as String],
      pointsLost: (map['lost'] as num? ?? 0).toDouble(),
      error: (map['se'] as num? ?? 0).toDouble(),
      eliminatedAt: map['out'] as int?,
    );
  }
}

/// The coach's answer for one position, as the app keeps it.
class BigTwoReport {
  const BigTwoReport({
    required this.moves,
    this.plan = const [],
    this.planSure = const [],
    this.playouts = 0,
    this.deals = 0,
  });

  /// [analysis] for the player at [seat], in the record's notation.
  factory BigTwoReport.fromAnalysis(BigTwoAnalysis analysis, int seat) => BigTwoReport(
    moves: [
      for (final c in analysis.candidates)
        BigTwoRating(
          move: bigTwoMoveText(seat, c.play),
          winChance: c.winChance,
          points: c.expectedPoints,
          samples: c.samples,
          sure: c.sureWin,
          reasons: [for (final r in c.reasons) r.name],
          pointsLost: c.pointsLost,
          error: c.pointsError,
          eliminatedAt: c.eliminatedAt,
        ),
    ],
    plan: [for (final p in analysis.plan.plays) bigTwoMoveText(seat, p)],
    planSure: analysis.plan.unbeatable,
    playouts: analysis.playouts,
    deals: analysis.deals,
  );

  /// Every legal move, the coach's pick first.
  final List<BigTwoRating> moves;

  /// The hand plan: the fewest plays that empty the hand as it is, lowest
  /// first, as moves.
  final List<String> plan;

  /// For each play of [plan], whether no unseen cards could beat it (it
  /// wins the lead back).
  final List<bool> planSure;

  /// Play-outs and guessed deals in all.
  final int playouts;
  final int deals;

  BigTwoRating get pick => moves.first;

  Map<String, Object?> toJson() => {
    'moves': [for (final m in moves) m.toJson()],
    'plan': plan,
    'planSure': planSure,
    'playouts': playouts,
    'deals': deals,
  };

  factory BigTwoReport.fromJson(Object? json) {
    final map = json! as Map<String, Object?>;
    return BigTwoReport(
      moves: [for (final m in map['moves']! as List) BigTwoRating.fromJson(m)],
      plan: [for (final p in map['plan'] as List? ?? const []) p as String],
      planSure: [for (final s in map['planSure'] as List? ?? const []) s as bool],
      playouts: map['playouts'] as int? ?? 0,
      deals: map['deals'] as int? ?? 0,
    );
  }
}

/// Four decimals are plenty for the panel and grading, and keep messages
/// short.
double _round(double v) => (v * 10000).round() / 10000;
