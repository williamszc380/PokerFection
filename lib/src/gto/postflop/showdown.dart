import 'dart:typed_data';

import '../../engine/hand_evaluator.dart';

/// Hands on one complete five-card board, sorted from weakest to strongest,
/// so that showdown results against a whole range take a single pass.
///
/// Hands are "compact" indices into the caller's list of combinations, whose
/// cards are given by `cardA`/`cardB`.
class RunoutRanking {
  RunoutRanking._(this.order, this.groupStart, this.sortedA, this.sortedB);

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
    return RunoutRanking._sorted(hands, strength, cardA, cardB);
  }

  /// For a turn [board] and [rivers] of one rank, none of which can give
  /// anyone a flush: every hand ranks the same on each of them (only which
  /// hands are possible differs), so one ranking serves them all. It holds
  /// every hand that doesn't use a [board] card, on a river it doesn't
  /// hold; a hand holding all of them comes first (it never gets there).
  factory RunoutRanking.sameRank(List<int> board, List<int> rivers, Int32List cardA, Int32List cardB) {
    assert(board.length == 4 && rivers.every((r) => r >> 2 == rivers.first >> 2));
    final used = List<bool>.filled(52, false);
    for (final c in board) {
      used[c] = true;
    }
    final seven = List<int>.filled(7, 0)..setRange(2, 6, board);
    final hands = <int>[];
    final strength = <int, int>{};
    for (var c = 0; c < cardA.length; c++) {
      if (used[cardA[c]] || used[cardB[c]]) continue;
      final river = rivers.where((r) => r != cardA[c] && r != cardB[c]).firstOrNull;
      if (river == null) {
        strength[c] = -1;
      } else {
        seven[0] = cardA[c];
        seven[1] = cardB[c];
        seven[6] = river;
        strength[c] = evaluateIndices(seven);
      }
      hands.add(c);
    }
    return RunoutRanking._sorted(hands, strength, cardA, cardB);
  }

  factory RunoutRanking._sorted(List<int> hands, Map<int, int> strength, Int32List cardA, Int32List cardB) {
    hands.sort((x, y) => strength[x]!.compareTo(strength[y]!));
    final starts = <int>[];
    for (var k = 0; k < hands.length; k++) {
      if (k == 0 || strength[hands[k]] != strength[hands[k - 1]]) starts.add(k);
    }
    starts.add(hands.length);
    return RunoutRanking._(
      Int32List.fromList(hands),
      Int32List.fromList(starts),
      Int32List.fromList([for (final c in hands) cardA[c]]),
      Int32List.fromList([for (final c in hands) cardB[c]]),
    );
  }

  /// Hands, weakest first.
  final Int32List order;

  /// Where each group of equally strong hands starts in [order], plus a
  /// final entry equal to `order.length`.
  final Int32List groupStart;

  /// The cards of the hands in [order] (`sortedA[k]` is `cardA[order[k]]`).
  final Int32List sortedA;
  final Int32List sortedB;
}

/// Scratch arrays for [addShowdownWinsForBoth]: 52 entries each, all zero
/// between calls.
class ShowdownScratch {
  final belowP = Float64List(52);
  final belowQ = Float64List(52);
  final groupP = Float64List(52);
  final groupQ = Float64List(52);
}

/// [addShowdownWins] for two players in one pass: adds to `winsP[c]` how
/// much of [weightsQ] hand `c` beats, and to `winsQ[c]` how much of
/// [weightsP] it beats (ties half), each times `scale[c]` when [scale] is
/// given. The sums come out exactly as with two separate calls.
void addShowdownWinsForBoth(
  RunoutRanking ranking,
  Float64List weightsP,
  Float64List weightsQ,
  Float64List winsP,
  Float64List winsQ,
  ShowdownScratch scratch, {
  Float64List? scale,
}) {
  final order = ranking.order, starts = ranking.groupStart;
  final sortedA = ranking.sortedA, sortedB = ranking.sortedB;
  final belowP = scratch.belowP, belowQ = scratch.belowQ;
  final groupP = scratch.groupP, groupQ = scratch.groupQ;
  // Totals of the weaker hands: P's range (what Q's hands beat) and Q's.
  var totalP = 0.0, totalQ = 0.0;
  for (var g = 0; g + 1 < starts.length; g++) {
    final from = starts[g], to = starts[g + 1];
    if (to == from + 1) {
      // A hand of its own strength: no ties.
      final c = order[from], a = sortedA[from], b = sortedB[from];
      final wp = weightsP[c], wq = weightsQ[c];
      final beatsQ = totalQ - belowQ[a] - belowQ[b];
      final beatsP = totalP - belowP[a] - belowP[b];
      if (scale == null) {
        winsP[c] += beatsQ;
        winsQ[c] += beatsP;
      } else {
        winsP[c] += beatsQ * scale[c];
        winsQ[c] += beatsP * scale[c];
      }
      totalP += wp;
      totalQ += wq;
      belowP[a] += wp;
      belowP[b] += wp;
      belowQ[a] += wq;
      belowQ[b] += wq;
      continue;
    }
    var sameP = 0.0, sameQ = 0.0;
    for (var k = from; k < to; k++) {
      final c = order[k], a = sortedA[k], b = sortedB[k];
      final wp = weightsP[c], wq = weightsQ[c];
      sameP += wp;
      sameQ += wq;
      groupP[a] += wp;
      groupP[b] += wp;
      groupQ[a] += wq;
      groupQ[b] += wq;
    }
    for (var k = from; k < to; k++) {
      final c = order[k], a = sortedA[k], b = sortedB[k];
      final vsQ = totalQ - belowQ[a] - belowQ[b] + 0.5 * (sameQ - groupQ[a] - groupQ[b] + weightsQ[c]);
      final vsP = totalP - belowP[a] - belowP[b] + 0.5 * (sameP - groupP[a] - groupP[b] + weightsP[c]);
      if (scale == null) {
        winsP[c] += vsQ;
        winsQ[c] += vsP;
      } else {
        winsP[c] += vsQ * scale[c];
        winsQ[c] += vsP * scale[c];
      }
    }
    for (var k = from; k < to; k++) {
      final c = order[k], a = sortedA[k], b = sortedB[k];
      final wp = weightsP[c], wq = weightsQ[c];
      totalP += wp;
      totalQ += wq;
      belowP[a] += wp;
      belowP[b] += wp;
      belowQ[a] += wq;
      belowQ[b] += wq;
      groupP[a] = 0;
      groupP[b] = 0;
      groupQ[a] = 0;
      groupQ[b] = 0;
    }
  }
  belowP.fillRange(0, 52, 0);
  belowQ.fillRange(0, 52, 0);
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
