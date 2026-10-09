import 'dart:typed_data';

import 'showdown.dart';

/// Scratch space for [addSameRankWins], for [hands] hands.
class SameRankScratch {
  SameRankScratch(int hands) : weights = Float32x4List(hands);

  final Float32x4List weights;
  final below = Float32x4List(52);
  final group = Float32x4List(52);
}

/// A group of rivers ranking every hand alike ([RunoutRanking.sameRank]),
/// shown down at once for two players: adds to `winsP[c]` how much of
/// [weightsQ] hand `c` beats (ties half) summed over the group's rivers,
/// that is on the `seen[c]` rivers `c` doesn't hold, less, for each
/// opponent hand, the `held` rivers that one holds; and the same for
/// `winsQ` against [weightsP].
///
/// One pass, four sums at a time: against each player's weights, and
/// against them times `held`.
void addSameRankWins(
  RunoutRanking ranking,
  Float64List weightsP,
  Float64List weightsQ,
  Float64List held,
  Float64List seen,
  Float64List winsP,
  Float64List winsQ,
  SameRankScratch scratch,
) {
  final weights = scratch.weights, below = scratch.below, group = scratch.group;
  final order = ranking.order, starts = ranking.groupStart;
  final sortedA = ranking.sortedA, sortedB = ranking.sortedB;
  for (var c = 0; c < weights.length; c++) {
    final p = weightsP[c], q = weightsQ[c], h = held[c];
    weights[c] = Float32x4(q, p, q * h, p * h);
  }
  final zero = Float32x4.zero(), half = Float32x4.splat(0.5);
  var total = zero;
  for (var g = 0; g + 1 < starts.length; g++) {
    final from = starts[g], to = starts[g + 1];
    if (to == from + 1) {
      // A hand of its own strength: no ties.
      final c = order[from], a = sortedA[from], b = sortedB[from];
      final w = weights[c];
      final s = total - below[a] - below[b];
      final m = seen[c];
      winsP[c] += m * s.x - s.z;
      winsQ[c] += m * s.y - s.w;
      total += w;
      below[a] += w;
      below[b] += w;
      continue;
    }
    var same = zero;
    for (var k = from; k < to; k++) {
      final w = weights[order[k]];
      same += w;
      group[sortedA[k]] += w;
      group[sortedB[k]] += w;
    }
    for (var k = from; k < to; k++) {
      final c = order[k], a = sortedA[k], b = sortedB[k];
      final s = total - below[a] - below[b] + half * (same - group[a] - group[b] + weights[c]);
      final m = seen[c];
      winsP[c] += m * s.x - s.z;
      winsQ[c] += m * s.y - s.w;
    }
    for (var k = from; k < to; k++) {
      final w = weights[order[k]];
      final a = sortedA[k], b = sortedB[k];
      total += w;
      below[a] += w;
      below[b] += w;
      group[a] = zero;
      group[b] = zero;
    }
  }
  for (var k = 0; k < 52; k++) {
    below[k] = zero;
  }
}
