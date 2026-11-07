/// Soft reading of the opponents' moves: weighs each guessed deal by how
/// well it explains what the others actually played.
///
/// Passing is always allowed, so no move rules a card out for certain. But
/// players don't pass on a cheap play for no reason, and they don't split a
/// pair when they hold a lone card that would do. This replays the deal
/// from each guess and checks, for every opponent decision, whether the
/// heuristic player would have made the same move with those cards. Each
/// mismatch multiplies the guess's weight by [InferenceModel.miss], so
/// guesses that make the opponents look sensible count more.
library;

import 'policy.dart';
import 'random.dart';
import 'state.dart';

/// How strongly to trust that opponents play like the heuristic.
class InferenceModel {
  /// A model where each move the heuristic would not have made multiplies a
  /// guess's weight by [miss].
  const InferenceModel({this.miss = 0.35, this.policy = const HeuristicPolicy()});

  /// Weight factor per unexplained move (1 = ignore the moves entirely).
  final double miss;

  /// The player the opponents are compared with.
  final HeuristicPolicy policy;

  /// The weight of guess [hands] (codes per seat, as from a sampler) for
  /// [view]: 1 when every opponent move is what the heuristic would play.
  double weight(BigTwoView view, List<List<int>> hands) {
    final history = view.history;
    if (history.isEmpty || miss >= 1) return 1;
    final n = view.players;
    final start = [for (var s = 0; s < n; s++) List<int>.of(hands[s])];
    for (final t in history) {
      if (!t.play.isPass) start[t.seat].addAll(t.play.codes);
    }
    var lowest = 52, lowSeat = -1;
    for (var s = 0; s < n; s++) {
      for (final c in start[s]) {
        if (c < lowest) {
          lowest = c;
          lowSeat = s;
        }
      }
    }
    // A chosen leader is public; otherwise the guess's lowest card starts
    // (a guess that contradicts the first player replays as a chosen lead).
    final first = history.first.seat;
    final state = BigTwoState.fromCodes(view.rules, start,
        leader: view.leaderChosen || first != lowSeat ? first : null);
    final rng = GameRandom(0);
    var w = 1.0;
    for (final t in history) {
      if (t.seat != view.seat) {
        final legal = state.legalMoves();
        if (legal.length > 1 && policy.chooseFrom(state, legal, rng) != t.play) w *= miss;
      }
      state.applyTrusted(t.play);
    }
    return w;
  }
}

/// A pool of guessed deals with their weights, drawn once per decision and
/// then sampled by weight.
class WeightedDeals {
  /// Draws [size] guesses from [sample] and weighs each with [model].
  WeightedDeals(BigTwoView view, List<List<int>> Function() sample, InferenceModel model, int size) {
    var total = 0.0;
    for (var i = 0; i < size; i++) {
      final hands = sample();
      final w = model.weight(view, hands);
      deals.add(hands);
      total += w;
      _cumulative.add(total);
    }
    _total = total;
  }

  /// The guesses.
  final List<List<List<int>>> deals = [];
  final List<double> _cumulative = [];
  late final double _total;

  /// Effective sample size: how many equally weighted guesses the pool is
  /// worth (low when a few guesses explain the moves far better).
  double get effectiveSize {
    var sum = 0.0, sumSq = 0.0, prev = 0.0;
    for (final c in _cumulative) {
      final w = c - prev;
      prev = c;
      sum += w;
      sumSq += w * w;
    }
    return sumSq == 0 ? 0 : sum * sum / sumSq;
  }

  /// One guess, picked with probability proportional to its weight.
  List<List<int>> pick(GameRandom rng) {
    final x = rng.nextDouble() * _total;
    var lo = 0, hi = _cumulative.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_cumulative[mid] > x) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return deals[lo];
  }
}
