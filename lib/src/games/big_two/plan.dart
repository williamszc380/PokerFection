/// The hand plan: the fewest plays that empty a hand.
///
/// Splitting your cards into as few plays as possible, and knowing which of
/// them can't be beaten, is the core skill of Big Two: every play beyond
/// those you can follow with needs you to win the lead first.
library;

import 'dart:typed_data';

import 'cards.dart';
import 'plays.dart';
import 'rules.dart';
import 'state.dart';

/// A way to empty a hand in the fewest plays.
class HandPlan {
  /// A plan of [plays].
  const HandPlan(this.plays, this.unbeatable);

  /// The plays, lowest first. Ties between equally short plans go to the
  /// one with fewer singles, which are the hardest to get rid of.
  final List<Play> plays;

  /// For each play, whether no cards still unseen could beat it (so playing
  /// it wins the lead back). All false when no view was given.
  final List<bool> unbeatable;

  /// Number of plays needed.
  int get count => plays.length;

  /// How many plays are sure to win the lead back.
  int get controls => unbeatable.where((u) => u).length;

  /// Singles in the plan.
  int get singles => plays.where((p) => p.size == 1).length;

  /// Plays that can be beaten: each needs a lead of your own (or a chance
  /// to follow), so this is how many times you must get the lead back.
  int get weakPlays => count - controls;
}

/// Finds fewest-play plans, remembering sub-hands so related hands (the
/// hand after each candidate play) are cheap to plan too.
class HandPlanner {
  /// A planner for [rules].
  HandPlanner(this.rules);

  /// The rules deciding which combinations exist.
  final BigTwoRules rules;

  final _memo = <int, int>{};
  final _choice = <int, Play>{};
  List<Play>? _allPlays;
  List<List<Play>>? _byLowest;
  Uint8List? _root;

  /// The fewest plays to empty the hand of [codes]. [view] lets the plan
  /// mark which plays are unbeatable by the unseen cards.
  HandPlan plan(List<int> input, {BigTwoView? view}) {
    if (input.isEmpty) return const HandPlan([], []);
    final codes = List<int>.of(input)..sort();
    _prepare(codes);
    final key = _keyOf(codes);
    _solve(key, codes);
    final plays = <Play>[];
    var k = key;
    var rest = codes;
    while (rest.isNotEmpty) {
      final p = _choice[k]!;
      plays.add(p);
      rest = [for (final c in rest) if (!p.containsCode(c)) c];
      k = _keyOf(rest);
    }
    plays.sort((a, b) => a.codes.first.compareTo(b.codes.first));
    final unbeatable = [for (final p in plays) view != null && !_beatableByUnseen(p, view)];
    return HandPlan(plays, unbeatable);
  }

  /// Just the number of plays (faster than [plan]); codes must be a subset
  /// of the hand last passed to [plan] or [count].
  int count(List<int> input) {
    if (input.isEmpty) return 0;
    final codes = List<int>.of(input)..sort();
    _prepare(codes);
    return _solve(_keyOf(codes), codes) >> 6;
  }

  void _prepare(List<int> codes) {
    final masks = masksOf(codes);
    final root = _root;
    if (root != null) {
      var subset = true;
      for (var r = 0; r < 13; r++) {
        if (masks[r] & ~root[r] != 0) subset = false;
      }
      if (subset) return;
    }
    _root = masks;
    _memo.clear();
    _choice.clear();
    _allPlays = rules.playsFrom(masks, 0, null);
    final by = List.generate(52, (_) => <Play>[]);
    for (final p in _allPlays!) {
      by[p.codes.first].add(p);
    }
    _byLowest = by;
  }

  // Cost = plays * 64 + singles; lower is better.
  int _solve(int key, List<int> codes) {
    if (codes.isEmpty) return 0;
    final known = _memo[key];
    if (known != null) return known;
    final lowest = codes.first;
    var best = 1 << 30;
    Play? bestPlay;
    for (final p in _byLowest![lowest]) {
      if (!_isSubset(p, codes)) continue;
      final rest = [for (final c in codes) if (!p.containsCode(c)) c];
      final v = _solve(_keyOf(rest), rest) + 64 + (p.size == 1 ? 1 : 0);
      if (v < best) {
        best = v;
        bestPlay = p;
      }
    }
    _memo[key] = best;
    _choice[key] = bestPlay!;
    return best;
  }

  static bool _isSubset(Play p, List<int> sortedCodes) {
    for (final c in p.codes) {
      if (!sortedCodes.contains(c)) return false;
    }
    return true;
  }

  // 52 bits as an exact integer (also exact in JavaScript, below 2^53).
  static int _keyOf(List<int> codes) {
    var lo = 0, hi = 0;
    for (final c in codes) {
      if (c < 26) {
        lo |= 1 << c;
      } else {
        hi |= 1 << (c - 26);
      }
    }
    return hi * 67108864 + lo;
  }

  bool _beatableByUnseen(Play p, BigTwoView view) {
    final unseen = masksOf(view.opponentCodes);
    var maxOpp = 0;
    for (var s = 0; s < view.players; s++) {
      if (s != view.seat && view.counts[s] > maxOpp) maxOpp = view.counts[s];
    }
    return rules.playsFrom(unseen, 0, p, maxSize: maxOpp).isNotEmpty;
  }
}

/// Convenience: the plan for a list of cards.
HandPlan planHand(BigTwoRules rules, List<Card> cards, {BigTwoView? view}) =>
    HandPlanner(rules).plan([for (final c in cards) rules.codeOf(c)]..sort(), view: view);
