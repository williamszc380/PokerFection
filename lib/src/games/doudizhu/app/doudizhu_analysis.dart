/// The coach's answer as plain JSON: what the coach job sends back, and
/// what the screen turns into coach rows.
///
/// It keeps every number the panel shows and drops what the screen doesn't
/// need or what would vary from run to run (the time taken, the deals
/// played): the same input gives the same JSON on every platform.
library;

import '../doudizhu.dart';
import 'doudizhu_record.dart';

/// One rated move.
class DdzAdviceLine {
  const DdzAdviceLine({
    required this.move,
    required this.winChance,
    required this.points,
    required this.samples,
    required this.proven,
    required this.reasons,
  });

  /// The move as a record move without card ids (see ddzMoveKey):
  /// `"0:xpair:77"`, `"1:b2"`, `"2:p"`.
  final String move;

  /// The chance (0 to 1) that the mover's side wins after it.
  final double winChance;

  /// The points the mover expects (stake and bombs counted).
  final double points;

  /// Deals it was played on (1 when solved exactly).
  final int samples;

  /// The result is certain (see DdzCandidate.proven).
  final bool proven;

  /// Why, best first.
  final List<DdzReason> reasons;

  Map<String, Object?> toJson() => {
        'm': move,
        'w': winChance,
        'p': points,
        'n': samples,
        if (proven) 'proven': true,
        if (reasons.isNotEmpty) 'r': [for (final r in reasons) r.name],
      };

  factory DdzAdviceLine.fromJson(Object? json) {
    final map = json! as Map<String, Object?>;
    final names = DdzReason.values.asNameMap();
    return DdzAdviceLine(
      move: map['m']! as String,
      winChance: (map['w']! as num).toDouble(),
      points: (map['p']! as num).toDouble(),
      samples: (map['n']! as num).toInt(),
      proven: map['proven'] == true,
      // A reason this build doesn't know (a newer worker) is skipped.
      reasons: [for (final r in map['r'] as List? ?? const []) ?names[r]],
    );
  }
}

/// The coach's answer for one decision, best first.
class DdzAdvice {
  const DdzAdvice({
    required this.seat,
    required this.bidding,
    required this.objective,
    required this.legalMoves,
    required this.lines,
  });

  /// The engine's analysis of [view] as advice.
  factory DdzAdvice.of(DdzAnalysis analysis, DdzView view) => DdzAdvice(
        seat: analysis.seat,
        bidding: view.phase == DdzPhase.bidding,
        objective: analysis.objective,
        legalMoves: analysis.legalMoveCount,
        lines: [
          for (final c in analysis.candidates)
            DdzAdviceLine(
              move: ddzMoveKey(ddzMoveText(analysis.seat, c.move)),
              winChance: c.winChance,
              points: c.expectedPoints,
              samples: c.samples,
              proven: c.proven,
              reasons: c.reasons,
            ),
        ],
      );

  final int seat;

  /// An auction decision (rated on points: the stake differs by bid).
  final bool bidding;

  /// What the ranking maximises: win chance in play, points in bidding.
  final DdzObjective objective;

  /// How many legal moves there were (more than [lines] on a big lead).
  final int legalMoves;
  final List<DdzAdviceLine> lines;

  DdzAdviceLine? lineFor(String move) {
    final key = ddzMoveKey(move);
    for (final line in lines) {
      if (line.move == key) return line;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
        'seat': seat,
        if (bidding) 'bidding': true,
        'objective': objective.name,
        'legal': legalMoves,
        'lines': [for (final line in lines) line.toJson()],
      };

  factory DdzAdvice.fromJson(Object? json) {
    final map = json! as Map<String, Object?>;
    return DdzAdvice(
      seat: (map['seat']! as num).toInt(),
      bidding: map['bidding'] == true,
      objective: DdzObjective.values.byName(map['objective']! as String),
      legalMoves: (map['legal']! as num).toInt(),
      lines: [for (final line in map['lines']! as List) DdzAdviceLine.fromJson(line)],
    );
  }
}
