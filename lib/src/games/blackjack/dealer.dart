/// Exact dealer outcome probabilities for an upcard and the unseen cards.
///
/// The dealer has no choices, so the chance of each final total (17, 18,
/// 19, 20, 21, bust, or a blackjack) is a sum over every way the draws can
/// go. Two facts make this cheap:
///
/// 1. What the dealer does next depends only on which cards were drawn,
///    not their order, so draws that reach the same set of cards (2 then
///    5, or 5 then 2) can share one node. The nodes and their links are
///    the same for every shoe, so they are built once per upcard and
///    soft-17 rule ([DealerGraph]).
/// 2. For a given shoe, one pass over the nodes in order of cards drawn
///    pushes each node's probability to its children with the exact
///    without-replacement chance (cards of that rank left / cards left).
///
/// A pass costs a few thousand multiply-adds (see the tool's timing), so
/// the solver can afford one for every hand it considers.
///
/// The blackjack outcome is the probability that the hole card (the
/// first card drawn) makes 21. It is a joint probability: the other
/// outcomes are "this total and no blackjack". For a dealer who has
/// peeked, divide the non-blackjack outcomes by `1 - blackjack` to get the
/// conditional chances published tables show.
library;

import 'dart:typed_data';

import 'cards.dart';

/// Index of "the dealer ends on 17" in an outcome list; 18..21 follow.
const int dealer17 = 0;

/// Index of "the dealer busts" in an outcome list.
const int dealerBust = 5;

/// Index of "the dealer has blackjack" in an outcome list.
const int dealerBlackjack = 6;

/// The length of an outcome list: 17, 18, 19, 20, 21, bust, blackjack.
const int dealerOutcomeCount = 7;

/// The dealer's possible draws for one upcard and soft-17 rule, merged by
/// the set of cards drawn, in the order they can be reached.
class DealerGraph {
  DealerGraph._(this.upcard, this.hitsSoft17, this._drawnCount, this._drawn, this._target);

  /// The graph for [upcard] (a rank index) when the dealer [hitsSoft17]
  /// or not. Built on first use and then shared.
  factory DealerGraph.of(int upcard, bool hitsSoft17) =>
      _cache[upcard * 2 + (hitsSoft17 ? 1 : 0)] ??= DealerGraph._build(upcard, hitsSoft17);

  static final List<DealerGraph?> _cache = List<DealerGraph?>.filled(rankCount * 2, null);

  factory DealerGraph._build(int upcard, bool hitsSoft17) {
    final drawnCount = <int>[0];
    final drawn = <int>[for (var r = 0; r < rankCount; r++) 0];
    final hard = <int>[rankPoints(upcard)];
    final ace = <bool>[upcard == aceIndex];
    final index = <String, int>{'': 0};
    final target = <int>[];
    for (var s = 0; s < drawnCount.length; s++) {
      for (var r = 0; r < rankCount; r++) {
        final h = hard[s] + rankPoints(r);
        final a = ace[s] || r == aceIndex;
        final k = drawnCount[s] + 1;
        final t = totalOf(h, a);
        int edge;
        if (k == 1 && t.value == 21) {
          edge = -(dealerBlackjack + 1);
        } else if (t.value > 21) {
          edge = -(dealerBust + 1);
        } else if (t.value >= 17 && !(hitsSoft17 && t.soft && t.value == 17)) {
          edge = -(t.value - 17 + 1);
        } else {
          final d = [for (var q = 0; q < rankCount; q++) drawn[s * rankCount + q] + (q == r ? 1 : 0)];
          final key = d.join(',');
          var id = index[key];
          if (id == null) {
            id = drawnCount.length;
            index[key] = id;
            drawnCount.add(k);
            drawn.addAll(d);
            hard.add(h);
            ace.add(a);
          }
          edge = id;
        }
        target.add(edge);
      }
    }
    return DealerGraph._(
      upcard,
      hitsSoft17,
      Int32List.fromList(drawnCount),
      Int32List.fromList(drawn),
      Int32List.fromList(target),
    );
  }

  /// The upcard's rank index.
  final int upcard;

  /// Whether the dealer hits soft 17.
  final bool hitsSoft17;

  final Int32List _drawnCount;
  final Int32List _drawn;
  final Int32List _target;

  /// The number of merged nodes (dealer hands that still draw).
  int get nodeCount => _drawnCount.length;

  /// Fills [out] (length [dealerOutcomeCount]) with the outcome
  /// probabilities when the unseen cards have these [counts] (by rank
  /// index; [total] cards in all, the upcard not among them). [work] is a
  /// scratch list of at least [nodeCount] numbers.
  void outcomes(Int32List counts, int total, Float64List out, Float64List work) {
    for (var i = 0; i < dealerOutcomeCount; i++) {
      out[i] = 0;
    }
    final n = nodeCount;
    for (var i = 1; i < n; i++) {
      work[i] = 0;
    }
    work[0] = 1;
    for (var s = 0; s < n; s++) {
      final p = work[s];
      if (p == 0) continue;
      final left = total - _drawnCount[s];
      if (left <= 0) continue;
      final scale = p / left;
      final base = s * rankCount;
      for (var r = 0; r < rankCount; r++) {
        final avail = counts[r] - _drawn[base + r];
        if (avail <= 0) continue;
        final q = scale * avail;
        final t = _target[base + r];
        if (t >= 0) {
          work[t] += q;
        } else {
          out[-t - 1] += q;
        }
      }
    }
  }
}

/// The dealer's outcome probabilities, as a list of [dealerOutcomeCount]
/// numbers (17, 18, 19, 20, 21, bust, blackjack), for an [upcard] (rank
/// index) when [unseen] are the cards the dealer will draw from (the hole
/// card included, the upcard not).
///
/// With [peeked] the dealer has checked and has no blackjack: the
/// blackjack entry is 0 and the others are conditional on that, which is
/// what published tables such as Wizard of Odds' "Dealer Odds in
/// Blackjack under US Rules" show.
List<double> dealerOutcomes(int upcard, Composition unseen, {required bool hitsSoft17, bool peeked = false}) {
  final graph = DealerGraph.of(upcard, hitsSoft17);
  final out = Float64List(dealerOutcomeCount);
  graph.outcomes(Int32List.fromList(unseen.counts), unseen.total, out, Float64List(graph.nodeCount));
  if (peeked) {
    final noBj = 1 - out[dealerBlackjack];
    for (var i = 0; i < dealerBlackjack; i++) {
      out[i] /= noBj;
    }
    out[dealerBlackjack] = 0;
  }
  return out;
}
