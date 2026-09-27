import 'dart:math';

import '../engine/cards.dart';

/// Number of distinct starting hands (AA, AKs, AKo, ...).
const handClassCount = 169;

/// Index (0-168) of a starting hand on a 13x13 grid: pairs on the diagonal,
/// suited hands at row = high rank, offsuit hands at row = low rank.
int handClassIndex(int rankA, int rankB, {required bool suited}) {
  final high = max(rankA, rankB), low = min(rankA, rankB);
  return suited || high == low ? high * 13 + low : low * 13 + high;
}

int handClassOf(PlayingCard a, PlayingCard b) =>
    handClassIndex(a.rank, b.rank, suited: a.suit == b.suit);

typedef HandClassInfo = ({int high, int low, bool suited, bool pair});

HandClassInfo describeHandClass(int index) {
  final row = index ~/ 13, col = index % 13;
  if (row == col) return (high: row, low: row, suited: false, pair: true);
  if (row > col) return (high: row, low: col, suited: true, pair: false);
  return (high: col, low: row, suited: false, pair: false);
}

/// How many two-card combinations make this starting hand: 6, 4 or 12.
int handClassCombos(int index) {
  final d = describeHandClass(index);
  return d.pair ? 6 : (d.suited ? 4 : 12);
}

/// Short name such as "AKs", "T9o" or "77".
String handClassName(int index) {
  final d = describeHandClass(index);
  const chars = PlayingCard.rankChars;
  if (d.pair) return '${chars[d.high]}${chars[d.low]}';
  return '${chars[d.high]}${chars[d.low]}${d.suited ? 's' : 'o'}';
}

/// Every two-card combination of the starting hand, as card indices (0-51).
List<(int, int)> handClassCards(int index) {
  final d = describeHandClass(index);
  return [
    if (d.pair)
      for (var s1 = 0; s1 < 4; s1++)
        for (var s2 = s1 + 1; s2 < 4; s2++) (d.high * 4 + s1, d.high * 4 + s2)
    else if (d.suited)
      for (var s = 0; s < 4; s++) (d.high * 4 + s, d.low * 4 + s)
    else
      for (var s1 = 0; s1 < 4; s1++)
        for (var s2 = 0; s2 < 4; s2++)
          if (s1 != s2) (d.high * 4 + s1, d.low * 4 + s2),
  ];
}
