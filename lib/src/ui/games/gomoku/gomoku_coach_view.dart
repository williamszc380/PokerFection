import 'package:flutter/material.dart';

import '../../../games/gomoku/app/gomoku_analysis.dart';
import '../../../games/gomoku/gomoku.dart';
import '../../kit/coach_panel.dart';
import 'l10n/gomoku_strings.dart';

/// How the coach's moves read in Gomoku: "h8" (or the word for a pass),
/// one short reason, a "Wins in 3" / "Loses in 2" badge for a proof.
/// Hovering a row previews its line on the board; a single click on a row
/// aims at its point ([onSelect], the row of the point aimed at is lit:
/// [selected]) and a double click places the stone there ([onPlay]), as
/// in every game's coach list. Hovering the grade card's best move
/// ([onPickHover]) rings it.
CoachLook gomokuCoachLook(
  GomokuStrings strings, {
  void Function(String? move)? onHover,
  void Function(String move)? onSelect,
  void Function(String move)? onPlay,
  String? selected,
  void Function(String? move)? onPickHover,
}) => CoachLook(
  moveText: strings.moveName,
  reasonText: (code) => switch (MoveReason.values.where((r) => r.name == code).firstOrNull) {
    final reason? => strings.reason(reason),
    null => null,
  },
  proofText: (proof) => gomokuProofText(strings, proof),
  onHover: onHover,
  onSelect: onSelect,
  onPlay: onPlay,
  selected: selected,
  onPickHover: onPickHover,
);

/// A proof code ('win:3', 'loss:2') as its badge, or null.
String? gomokuProofText(GomokuStrings strings, String proof) => switch (parseGomokuProof(proof)) {
  (true, final n) => strings.winsIn(n),
  (false, final n) => strings.losesIn(n),
  null => null,
};

/// What the position is proven to be for the player, for the status line:
/// "Wins in 3", "Loses in 2", or null when nothing is proven.
String? gomokuPositionProof(GomokuStrings strings, GomokuAnalysis? analysis) => switch (analysis) {
  GomokuAnalysis(:final winsIn?) => strings.winsIn(winsIn),
  GomokuAnalysis(:final losesIn?) => strings.losesIn(losesIn),
  _ => null,
};

/// The line a coach row stands for, numbered as on the board: "1 h8  2 h9
/// 3 j10" (shown under the coach's moves while the row is hovered).
class GomokuLineText extends StatelessWidget {
  const GomokuLineText({super.key, required this.line, required this.strings});

  final List<GomokuMove> line;
  final GomokuStrings strings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Text(
        [for (final (i, m) in line.indexed) '${i + 1} ${strings.moveName(m.notation)}'].join('  '),
        key: const ValueKey('gomoku line'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: Colors.white70, fontFeatures: [FontFeature.tabularFigures()]),
      ),
    );
  }
}
