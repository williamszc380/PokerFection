/// What the coach says about one position, in a shape every game shares:
/// ranked moves with a value each, and the coach's pick.
library;

import 'dart:math';

/// The unit of a coach line's value (and of a move's loss).
enum ValueUnit {
  /// A chance of winning the game, 0 to 1 (Gomoku, Fight the Landlord).
  winChance,

  /// Points scored or lost in the deal (Big Two).
  points,

  /// Bets won or lost, in units of the bet (Blackjack).
  bets,
}

/// The coach's answer for one position.
class CoachAnswer {
  CoachAnswer({
    required this.lines,
    required this.unit,
    String? pick,
    this.alsoBest = const {},
    this.detail,
    this.listed = const {},
  }) : pick = pick ?? lines.firstOrNull?.move ?? '';

  /// The moves the coach rated, ranked as the game shows them.
  final List<CoachLine> lines;
  final ValueUnit unit;

  /// The move tagged with the game's pick label ("GTO", "Best move",
  /// "Basic strategy"); by default the first line's. Big Two's pick need not
  /// have the highest value, and Blackjack's is the chart's play.
  final String pick;

  /// Other moves graded Best too (Blackjack: the best play when it differs
  /// from the chart's).
  final Set<String> alsoBest;

  /// In memory only: the game's decoded engine analysis (Gomoku grades
  /// with it).
  final Object? detail;

  /// Moves the list always shows when they are rated, however low they
  /// rank: the choices that aren't card plays (Pass, No bid). The kit sets
  /// them (TurnController.listedMoves); a game's own answer leaves them out.
  final Set<String> listed;

  CoachLine? lineFor(String move) => lines.where((line) => line.move == move).firstOrNull;

  /// Whether [move] was rated.
  bool rates(String move) => lineFor(move) != null;

  /// The highest value of any line (null without lines).
  double? get bestValue => lines.isEmpty ? null : lines.map((line) => line.value).reduce(max);

  /// This answer with [listed] as the moves always shown.
  CoachAnswer withListed(Set<String> listed) =>
      CoachAnswer(lines: lines, unit: unit, pick: pick, alsoBest: alsoBest, detail: detail, listed: listed);

  /// This answer with [line] rated too (it replaces a line for the same
  /// move), placed before the first line worth less, so the ranking reads
  /// the same way as before. The pick and the rest stay as they were: the
  /// kit adds a Pass the first answer left out this way.
  CoachAnswer withLine(CoachLine line) {
    final rest = [for (final l in lines) if (l.move != line.move) l];
    final at = rest.indexWhere((l) => l.value < line.value);
    return CoachAnswer(
      lines: [...rest]..insert(at < 0 ? rest.length : at, line),
      unit: unit,
      pick: pick,
      alsoBest: alsoBest,
      detail: detail,
      listed: listed,
    );
  }

  /// The lines a list of [maxRows] rows shows: the first ones, except that
  /// every rated [listed] move is among them (it takes the place of the
  /// lowest other line), still in ranking order. So Pass is always there to
  /// pick, even when it ranks seventh. The pick always shows too; listed
  /// moves never push it out (with more of them than rows, the list is
  /// longer than [maxRows] and the panel scrolls).
  List<CoachLine> shown(int maxRows) {
    if (lines.length <= maxRows) return lines;
    final pinned = {for (final l in lines) if (listed.contains(l.move) || l.move == pick) l.move};
    var room = maxRows - pinned.length;
    final keep = <String>{...pinned};
    for (final l in lines) {
      if (room <= 0) break;
      if (keep.add(l.move)) room--;
    }
    return [for (final l in lines) if (keep.contains(l.move)) l];
  }
}

/// One move the coach rated.
class CoachLine {
  const CoachLine({
    required this.move,
    required this.value,
    this.winChance,
    this.points,
    this.reasons = const [],
    this.proof,
    this.tag,
    this.minLoss = 0,
    this.error,
  });

  /// The move in the game's own notation.
  final String move;

  /// What the move is worth, in the answer's unit (higher is better).
  final double value;

  /// Extra numbers a game may show beside the value.
  final double? winChance;
  final double? points;

  /// Machine-readable reason codes; each game's strings turn them into text.
  final List<String> reasons;

  /// A proven result: 'win:5' / 'loss:3' / 'sure'.
  final String? proof;

  /// A tag other than the pick ('count' in Blackjack); its text comes from
  /// GameStrings.tagLabel.
  final String? tag;

  /// The least loss a move made here is graded with: Big Two's moves dropped
  /// early in the search have few samples, so they are at best Good.
  final double minLoss;

  /// A sampling coach's standard error of this line's gap to the line it is
  /// graded against (see GradeScale.noiseErrors); null: exact. With it, the
  /// same move in the same position keeps its grade whatever the coach's seed.
  final double? error;
}

/// [v] in [unit] as shown everywhere, with its sign (a real minus) and the
/// right decimals: "62%" and "−7%" for win chances, "+1.4" points, "−0.03"
/// bets. A small amount that isn't zero never reads as zero: it gets one
/// more decimal ("−0.4%", "−0.004"). The strings only place the number.
String formatValue(ValueUnit unit, double v) => switch (unit) {
      ValueUnit.winChance => '${_number(v * 100, 0, sign: false)}%',
      ValueUnit.points => _number(v, 1, sign: true),
      ValueUnit.bets => _number(v, 2, sign: true),
    };

String _number(double v, int decimals, {required bool sign}) {
  var places = decimals;
  // One more decimal for a small amount that would round to zero.
  if (v != 0 && double.parse(v.abs().toStringAsFixed(places)) == 0) places++;
  final text = v.abs().toStringAsFixed(places);
  if (double.parse(text) == 0) return text;
  if (v < 0) return '−$text';
  return sign ? '+$text' : text;
}
