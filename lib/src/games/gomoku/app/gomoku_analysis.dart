/// The coach's analysis as a job sends it, and as the kit shows it.
///
/// The job output is the engine's own `GomokuAnalysis.toJson()` without its
/// time ('micros') and with its win chances rounded, so the same position
/// always gives the same output, on every platform. The
/// kit's [CoachAnswer] keeps the decoded analysis in `detail`, because
/// Gomoku grades with the engine's own rules (see gomoku_grading.dart).
library;

import '../../../kit/coach_answer.dart';
import '../gomoku.dart';

/// [analysis] as a job's output: the engine's JSON without timing, and
/// with each win chance rounded (see [roundWinChance]).
Map<String, Object?> encodeGomokuAnalysis(GomokuAnalysis analysis) {
  final json = analysis.toJson()..remove('micros');
  json['moves'] = [
    for (final move in json['moves']! as List)
      {...(move as Map<String, Object?>), 'winChance': roundWinChance((move['winChance']! as num).toDouble())},
  ];
  return json;
}

/// A win chance to 4 decimal places. The chance comes from `exp`, whose
/// last binary digit can differ between the apps and a browser (JavaScript
/// or WebAssembly), and a job must answer the same everywhere; 0.01% is far
/// finer than the panel shows or any grade's band.
double roundWinChance(double chance) => (chance * 10000).round() / 10000;

/// The analysis [encodeGomokuAnalysis] wrote.
GomokuAnalysis decodeGomokuAnalysis(Object? json) => GomokuAnalysis.fromJson((json! as Map).cast<String, Object?>());

/// A proven result as the kit's proof code: 'win:3' (the mover makes five
/// within 3 of its own moves), 'loss:2' (the opponent does within 2 of
/// its), or null when nothing is proven.
String? gomokuProof(MoveAnalysis move) => switch (move) {
  MoveAnalysis(:final winsIn?) => 'win:$winsIn',
  MoveAnalysis(:final losesIn?) => 'loss:$losesIn',
  _ => null,
};

/// A proof code read back: (true, 3) for 'win:3', (false, 2) for 'loss:2';
/// null for anything else.
(bool win, int moves)? parseGomokuProof(String proof) {
  final parts = proof.split(':');
  if (parts.length != 2) return null;
  final n = int.tryParse(parts[1]);
  if (n == null) return null;
  return switch (parts[0]) {
    'win' => (true, n),
    'loss' => (false, n),
    _ => null,
  };
}

/// The coach's lines for the panel: every analysed move, best first, its
/// value the win chance, its reasons the engine's reason names, and the
/// engine's best move as the pick.
CoachAnswer gomokuAnswer(GomokuAnalysis analysis) => CoachAnswer(
  unit: ValueUnit.winChance,
  lines: [
    for (final move in analysis.moves)
      CoachLine(
        move: move.move.notation,
        value: move.winChance,
        reasons: [for (final r in move.reasons) r.name],
        proof: gomokuProof(move),
      ),
  ],
  pick: analysis.best?.move.notation,
  detail: analysis,
);

/// The choices besides a point that the coach list always shows in [game]
/// (TurnController.listedMoves): a pass, when it is legal (Renju, when
/// Black has no point left). The game and its review share it.
List<String> gomokuListedMoves(GomokuGame game) => [if (game.mustPass) GomokuMove.pass.notation];
