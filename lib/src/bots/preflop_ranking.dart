import 'dart:math';

import '../engine/cards.dart';
import '../gto/hand_classes.dart';

/// Where a starting hand ranks among all 1326 two-card combinations, from
/// just above 0 (aces) to 1 (the worst hands). A hand is "in the top 20%"
/// when this is at most 0.2.
///
/// The order comes from the Chen formula, a simple and well-known way to
/// score starting hands. It is only meant for the practice bots.
double preflopPercentile(PlayingCard a, PlayingCard b) => _percentiles[handClassOf(a, b)];

/// Short name of the starting hand, such as "AKs", "T9o" or "77".
String handClassLabel(PlayingCard a, PlayingCard b) => handClassName(handClassOf(a, b));

/// Chen formula score (higher is better).
double chenScore(int rankA, int rankB, {required bool suited}) {
  final high = max(rankA, rankB), low = min(rankA, rankB);
  double value(int rank) => switch (rank) {
        12 => 10,
        11 => 8,
        10 => 7,
        9 => 6,
        _ => (rank + 2) / 2,
      };
  if (high == low) return max(5, value(high) * 2);
  var score = value(high);
  if (suited) score += 2;
  final gap = high - low - 1;
  score -= switch (gap) { 0 => 0, 1 => 1, 2 => 2, 3 => 4, _ => 5 };
  if (gap <= 1 && high < 10) score += 1; // both cards below a queen
  return score.ceilToDouble();
}

final List<double> _percentiles = _buildPercentiles();

List<double> _buildPercentiles() {
  final classes = <({int high, int low, bool suited, double score, int combos})>[];
  for (var high = 0; high < 13; high++) {
    for (var low = 0; low <= high; low++) {
      if (high == low) {
        classes.add((high: high, low: low, suited: false, score: chenScore(high, low, suited: false), combos: 6));
      } else {
        classes.add((high: high, low: low, suited: true, score: chenScore(high, low, suited: true), combos: 4));
        classes.add((high: high, low: low, suited: false, score: chenScore(high, low, suited: false), combos: 12));
      }
    }
  }
  int rankOf(({int high, int low, bool suited, double score, int combos}) c) =>
      c.high == c.low ? 2 : (c.suited ? 1 : 0);
  classes.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    final byType = rankOf(b).compareTo(rankOf(a));
    if (byType != 0) return byType;
    final byHigh = b.high.compareTo(a.high);
    return byHigh != 0 ? byHigh : b.low.compareTo(a.low);
  });

  final result = List<double>.filled(169, 1);
  var cumulative = 0;
  for (final c in classes) {
    cumulative += c.combos;
    result[handClassIndex(c.high, c.low, suited: c.suited)] = cumulative / 1326;
  }
  return result;
}
