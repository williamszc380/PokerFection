import 'package:flutter/material.dart';

import '../../../games/gomoku/gomoku.dart';
import '../../../l10n/strings.dart';
import '../../kit/guide_kit.dart';
import '../../widgets/gomoku_board.dart' show BoardMark, BoardStone, GomokuBoard;
import 'l10n/gomoku_strings.dart';

/// Gomoku's rules (Guides > Rules; ☰ Rules shows the same sections).
class GomokuRulesGuide extends StatelessWidget {
  const GomokuRulesGuide({super.key});

  @override
  Widget build(BuildContext context) =>
      GuidePage(title: S.of(context).rules, sections: GomokuStrings.of(context).rulesSections);
}

/// One figure of the Threats guide: a 9×9 cut-out of the board around h8,
/// in Renju notation ("h8" is the centre of the 15×15 board). A test plays
/// each one on the engine and checks it shows what its caption says.
class GomokuFigureSpec {
  const GomokuFigureSpec(
    this.figure, {
    required this.black,
    this.white = '',
    this.key,
    this.dots = '',
    this.forbidden = '',
    this.sequence = '',
    this.rules = GomokuRules.freestyle,
  });

  final GomokuFigure figure;

  /// The stones on the board, space separated.
  final String black;
  final String white;

  /// The Black stone just played (marked as the last move).
  final String? key;

  /// Empty points to point at: where five, or an open four, comes next.
  final String dots;

  /// Renju: points Black may not take (crossed out).
  final String forbidden;

  /// Moves played from the position, numbered 1, 2, 3... (Black first).
  final String sequence;

  /// The rules the figure is checked under.
  final GomokuRules rules;

  /// The cut-out's size and its top-left corner on the 15×15 board.
  static const lines = 9;
  static const left = 3, top = 11;

  /// [move]'s point in the cut-out (column, row from the top).
  static (int, int) point(GomokuMove move) => (move.x - left, top - move.y);

  static List<GomokuMove> moves(String text) => GomokuGame.parseMoves(text);
}

/// The Threats guide's figures, in order. Black always attacks.
const gomokuFigures = [
  GomokuFigureSpec(GomokuFigure.five, black: 'f8 g8 h8 i8 j8', white: 'g9 i9 h7', key: 'j8'),
  GomokuFigureSpec(GomokuFigure.openFour, black: 'f8 g8 h8 i8', white: 'g9 h7', key: 'i8', dots: 'e8 j8'),
  GomokuFigureSpec(GomokuFigure.four, black: 'f8 g8 h8 i8', white: 'e8 h9', key: 'i8', dots: 'j8'),
  GomokuFigureSpec(GomokuFigure.openThree, black: 'g8 h8 i8', white: 'h9', key: 'i8', dots: 'f8 j8'),
  GomokuFigureSpec(GomokuFigure.brokenThree, black: 'g8 h8 j8', white: 'h9', key: 'j8', dots: 'i8'),
  GomokuFigureSpec(GomokuFigure.fourThree, black: 'f8 g8 h8 i8 i9 i10', white: 'e8 h9 j10', key: 'i8', dots: 'j8'),
  GomokuFigureSpec(GomokuFigure.doubleThree, black: 'f8 g8 h8 h9 h10', white: 'e7 j10', key: 'h8'),
  GomokuFigureSpec(
    GomokuFigure.doubleFour,
    black: 'e8 f8 g8 h8 h9 h10 h11',
    white: 'd8 h12 f10',
    key: 'h8',
    dots: 'i8 h7',
  ),
  GomokuFigureSpec(
    GomokuFigure.vcf,
    black: 'h8 j6 f6 j10 h7 f10',
    white: 'k8 i6 e7 h9 h10 e5',
    sequence: 'i7 g9 g7 i9 j7 f7 k7',
  ),
  GomokuFigureSpec(
    GomokuFigure.forbiddenThree,
    black: 'f8 g8 h9 h10',
    white: 'e7 j10',
    forbidden: 'h8',
    rules: GomokuRules.renju,
  ),
  GomokuFigureSpec(
    GomokuFigure.forbiddenFour,
    black: 'e8 f8 g8 h9 h10 h11',
    white: 'd8 h12 f10',
    forbidden: 'h8',
    rules: GomokuRules.renju,
  ),
  GomokuFigureSpec(
    GomokuFigure.forbiddenOverline,
    black: 'd8 e8 f8 h8 i8',
    white: 'g9 g7',
    forbidden: 'g8',
    rules: GomokuRules.renju,
  ),
];

/// The Threats guide: the shapes that win games, each on a small board
/// with a one-line caption.
class GomokuThreatsGuide extends StatelessWidget {
  const GomokuThreatsGuide({super.key});

  @override
  Widget build(BuildContext context) {
    final g = GomokuStrings.of(context);
    return GuidePage(
      title: g.threats,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            // As many columns of figures as fit at about 190 wide each.
            final columns = (constraints.maxWidth / 190).floor().clamp(1, 3);
            final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final spec in gomokuFigures)
                  SizedBox(
                    width: width,
                    child: GomokuFigureCard(spec: spec, strings: g),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// One figure: its title, the board, the caption.
class GomokuFigureCard extends StatelessWidget {
  const GomokuFigureCard({super.key, required this.spec, required this.strings});

  final GomokuFigureSpec spec;
  final GomokuStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final point = GomokuFigureSpec.point;
    final moves = GomokuFigureSpec.moves;
    final key = spec.key;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.figureTitle(spec.figure),
            style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: GomokuBoard(
                key: ValueKey('figure ${spec.figure.name}'),
                lines: GomokuFigureSpec.lines,
                showStars: false,
                stones: {
                  for (final m in moves(spec.black)) point(m): Stone.black,
                  for (final m in moves(spec.white)) point(m): Stone.white,
                },
                lastMove: key == null ? null : point(GomokuMove.parse(key)),
                marks: {
                  for (final m in moves(spec.dots)) point(m): const BoardMark('', fill: Color(0xE6FF8F00), radius: 0.2),
                },
                forbidden: [for (final m in moves(spec.forbidden)) point(m)],
                sequence: [
                  for (final (i, m) in moves(spec.sequence).indexed)
                    BoardStone(point(m), i.isEven ? Stone.black : Stone.white, '${i + 1}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(strings.figureCaption(spec.figure), style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
