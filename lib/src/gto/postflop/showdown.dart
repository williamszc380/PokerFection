import 'dart:typed_data';

import '../../engine/hand_evaluator.dart';

/// Hands on one complete five-card board, sorted from weakest to strongest,
/// so that showdown results against a whole range take a single pass.
///
/// Hands are "compact" indices into the caller's list of combinations, whose
/// cards are given by `cardA`/`cardB`.
class RunoutRanking {
  RunoutRanking._(this.order, this.groupStart);

  /// Ranks the hands that don't use any of the [board] cards.
  factory RunoutRanking(List<int> board, Int32List cardA, Int32List cardB) {
    assert(board.length == 5);
    final used = List<bool>.filled(52, false);
    for (final c in board) {
      used[c] = true;
    }
    final seven = List<int>.filled(7, 0)..setRange(2, 7, board);
    final hands = <int>[];
    final strength = <int, int>{};
    for (var c = 0; c < cardA.length; c++) {
      if (used[cardA[c]] || used[cardB[c]]) continue;
      seven[0] = cardA[c];
      seven[1] = cardB[c];
      strength[c] = evaluateIndices(seven);
      hands.add(c);
    }
    hands.sort((x, y) => strength[x]!.compareTo(strength[y]!));
    final starts = <int>[];
    for (var k = 0; k < hands.length; k++) {
      if (k == 0 || strength[hands[k]] != strength[hands[k - 1]]) starts.add(k);
    }
    starts.add(hands.length);
    return RunoutRanking._(Int32List.fromList(hands), Int32List.fromList(starts));
  }

  /// Hands, weakest first.
  final Int32List order;

  /// Where each group of equally strong hands starts in [order], plus a
  /// final entry equal to `order.length`.
  final Int32List groupStart;
}

/// Adds to `out[c]`, for every hand `c` on the runout, how much of the
/// opponent's range [weights] it beats: the weight of every opponent hand
/// sharing no card with `c` that it beats, plus half for ties.
///
/// [below] and [group] are scratch arrays of 52 entries that must be all
/// zero; they are left all zero.
void addShowdownWins(
  RunoutRanking ranking,
  Float64List weights,
  Float64List out,
  Int32List cardA,
  Int32List cardB,
  Float64List below,
  Float64List group,
) {
  final order = ranking.order, starts = ranking.groupStart;
  var belowTotal = 0.0;
  for (var g = 0; g + 1 < starts.length; g++) {
    final from = starts[g], to = starts[g + 1];
    var groupTotal = 0.0;
    for (var k = from; k < to; k++) {
      final c = order[k];
      final w = weights[c];
      groupTotal += w;
      group[cardA[c]] += w;
      group[cardB[c]] += w;
    }
    for (var k = from; k < to; k++) {
      final c = order[k];
      final a = cardA[c], b = cardB[c];
      // Weaker hands that don't share a card with c ...
      final wins = belowTotal - below[a] - below[b];
      // ... and equal hands (c itself is subtracted twice, so add it back once).
      final ties = groupTotal - group[a] - group[b] + weights[c];
      out[c] += wins + 0.5 * ties;
    }
    for (var k = from; k < to; k++) {
      final c = order[k];
      final w = weights[c];
      final a = cardA[c], b = cardB[c];
      belowTotal += w;
      below[a] += w;
      below[b] += w;
      group[a] = 0;
      group[b] = 0;
    }
  }
  below.fillRange(0, 52, 0);
}
