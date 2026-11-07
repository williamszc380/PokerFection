/// Splitting a hand into the plays it will most likely be played as.
///
/// Good players think of a hand as a plan: "a straight, two trios carrying
/// my small solos, a pair of kings and a bomb", and judge it by how many
/// turns it needs and how many of those turns it can win. This file finds
/// the best such plan with a small search over the chains, then attaches
/// kickers greedily. The heuristic bot, the rollouts of the coach and the
/// bidding advice all use it.
///
/// The score: every group costs a turn (−7) and is worth its main rank
/// (3 → −7 up to the big joker → +7), so a hand with fewer, higher groups
/// scores higher. Bombs and the rocket don't cost a turn (they win a trick
/// and give the lead back), so they only add. This is the usual "hand
/// value minus seven per turn" evaluation from Dou Dizhu AI write-ups.
library;

import 'cards.dart';
import 'plays.dart';
import 'rules.dart';

/// What one turn of a plan costs.
const double turnCost = 7;

/// A hand's best plan: its plays and its score.
class HandPlan {
  HandPlan(this.plays, this.score);

  /// The groups the hand will be played as, kickers attached.
  final List<Play> plays;

  /// Higher is better. See the library comment.
  final double score;

  /// Turns the hand needs if nothing is beaten, bombs and rocket included.
  int get turns => plays.length;

  /// Turns that aren't bombs or the rocket.
  int get plainTurns => plays.where((p) => !p.isBombLike).length;

  @override
  String toString() => '${plays.join(' ')} (${score.toStringAsFixed(1)})';
}

/// The value of a group by its kind and main rank, before the turn cost.
double groupValue(PlayType type, int rank, int length) {
  final top = rank + length - 1;
  return switch (type) {
    PlayType.bomb => turnCost + 6 + rank * 0.25,
    PlayType.rocket => turnCost + 10,
    PlayType.straight || PlayType.pairStraight => top - 7.0 + 1,
    PlayType.airplane || PlayType.airplaneSolos || PlayType.airplanePairs => top - 7.0 + 2,
    PlayType.fourTwoSolos || PlayType.fourTwoPairs => rank - 7.0 + 1,
    _ => rank - 7.0,
  };
}

/// The score of a single play as one group of a plan.
double playScore(Play p) => groupValue(p.type, p.rank, p.length) - turnCost;

/// Finds the best plan for [counts]. Bombs and the rocket are kept whole.
HandPlan planHand(List<int> counts, [DdzRules rules = DdzRules.standard]) {
  final s = _Planner(counts);
  s.search();
  return s.buildPlan();
}

/// Only the score of [planHand], a little faster (no plays are built).
double handScore(List<int> counts) {
  final s = _Planner(counts);
  s.search();
  return s.bestScore;
}

/// Chain kinds the search tries, as codes on its stack.
const _straight = 0, _pairs = 1, _planes = 2;

class _Planner {
  _Planner(List<int> counts) : r = List<int>.of(counts, growable: false) {
    for (var x = 0; x <= Rank.two; x++) {
      if (r[x] == 4) {
        _bombs.add(x);
        r[x] = 0;
        fixed += groupValue(PlayType.bomb, x, 1) - turnCost;
      }
    }
    if (r[Rank.littleJoker] > 0 && r[Rank.bigJoker] > 0) {
      rocket = true;
      r[Rank.littleJoker] = 0;
      r[Rank.bigJoker] = 0;
      fixed += groupValue(PlayType.rocket, 0, 1) - turnCost;
    }
  }

  final List<int> r;
  final List<int> _bombs = [];
  bool rocket = false;
  double fixed = 0;

  // Chains on the stack: kind, start, length, 3 ints each (12 at most).
  final List<int> _stack = List<int>.filled(36, 0);
  int _depth = 0;
  double bestScore = double.negativeInfinity;
  List<int> _best = const [];
  int _bestDepth = 0;

  void search() {
    _dfs(0, 0);
  }

  /// Tries every set of chains whose lowest rank is at least [p]. [minOption]
  /// keeps chains starting at the same rank in one order, so each set of
  /// chains is visited once.
  void _dfs(int p, int minOption) {
    while (p <= Rank.highestInChain && r[p] == 0) {
      p++;
      minOption = 0;
    }
    if (p > Rank.highestInChain) {
      final score = _leaf();
      if (score > bestScore) {
        bestScore = score;
        _best = _stack.sublist(0, _depth * 3);
        _bestDepth = _depth;
      }
      return;
    }
    // No (more) chains start at p.
    _dfs(p + 1, 0);
    if (_depth >= 12) return;
    // Options are numbered kind * 16 + length.
    for (var kind = _straight; kind <= _planes; kind++) {
      final copies = kind + 1;
      final minLen = kind == _straight ? 5 : (kind == _pairs ? 3 : 2);
      var run = 0;
      while (p + run <= Rank.highestInChain && r[p + run] >= copies) {
        run++;
      }
      for (var len = minLen; len <= run; len++) {
        final option = kind * 16 + len;
        if (option < minOption) continue;
        for (var x = p; x < p + len; x++) {
          r[x] -= copies;
        }
        _stack[_depth * 3] = kind;
        _stack[_depth * 3 + 1] = p;
        _stack[_depth * 3 + 2] = len;
        _depth++;
        _dfs(p, option);
        _depth--;
        for (var x = p; x < p + len; x++) {
          r[x] += copies;
        }
      }
    }
  }

  /// Scores the leftovers once the chains are chosen: solos, pairs and
  /// trios, with trios and airplanes carrying the lowest kickers.
  double _leaf() {
    var score = fixed;
    // Leftover groups by rank: 1 solo, 2 pair, 3 trio. Kickers taken get
    // marked in [used] (a bit per rank).
    var used = 0;
    var planesWanting = 0;
    for (var i = 0; i < _depth; i++) {
      final kind = _stack[i * 3];
      final start = _stack[i * 3 + 1];
      final len = _stack[i * 3 + 2];
      final type = kind == _straight ? PlayType.straight : (kind == _pairs ? PlayType.pairStraight : PlayType.airplane);
      score += groupValue(type, start, len) - turnCost;
      if (kind == _planes) planesWanting += len;
    }
    // Airplanes carry the lowest solos (or pairs) one per trio.
    if (planesWanting > 0) {
      var solos = 0, pairs = 0;
      for (var x = 0; x < Rank.two; x++) {
        if (r[x] == 1) solos++;
        if (r[x] == 2) pairs++;
      }
      final kind = solos >= planesWanting ? 1 : (pairs >= planesWanting ? 2 : 0);
      if (kind != 0) {
        var need = planesWanting;
        for (var x = 0; x < Rank.two && need > 0; x++) {
          if (r[x] == kind) {
            used |= 1 << x;
            need--;
          }
        }
      }
    }
    // Each trio carries the lowest free solo or pair below the 2.
    for (var t = 0; t <= Rank.two; t++) {
      if (r[t] != 3) continue;
      score += groupValue(PlayType.trio, t, 1) - turnCost;
      for (var x = 0; x < Rank.two; x++) {
        if (x != t && (r[x] == 1 || r[x] == 2) && (used & (1 << x)) == 0) {
          used |= 1 << x;
          break;
        }
      }
    }
    for (var x = 0; x < Rank.count; x++) {
      if ((r[x] == 1 || r[x] == 2) && (used & (1 << x)) == 0) {
        score += groupValue(PlayType.solo, x, 1) - turnCost;
      }
    }
    return score;
  }

  /// Rebuilds the best plan's plays, attaching kickers as [_leaf] did.
  HandPlan buildPlan() {
    final plays = <Play>[];
    final rest = List<int>.of(r);
    final planes = <(int, int)>[];
    for (var i = 0; i < _bestDepth; i++) {
      final kind = _best[i * 3];
      final start = _best[i * 3 + 1];
      final len = _best[i * 3 + 2];
      for (var x = start; x < start + len; x++) {
        rest[x] -= kind + 1;
      }
      if (kind == _planes) {
        planes.add((start, len));
      } else {
        final type = kind == _straight ? PlayType.straight : PlayType.pairStraight;
        plays.add(Play(type, start, len, [
          for (var x = start; x < start + len; x++)
            for (var c = 0; c <= kind; c++) x,
        ]));
      }
    }
    var wanting = 0;
    for (final (_, len) in planes) {
      wanting += len;
    }
    var used = 0;
    var planeKickers = <int>[];
    var planeKind = 0;
    if (wanting > 0) {
      var solos = 0, pairs = 0;
      for (var x = 0; x < Rank.two; x++) {
        if (rest[x] == 1) solos++;
        if (rest[x] == 2) pairs++;
      }
      planeKind = solos >= wanting ? 1 : (pairs >= wanting ? 2 : 0);
      if (planeKind != 0) {
        var need = wanting;
        for (var x = 0; x < Rank.two && need > 0; x++) {
          if (rest[x] == planeKind) {
            used |= 1 << x;
            planeKickers.add(x);
            need--;
          }
        }
      }
    }
    var k = 0;
    for (final (start, len) in planes) {
      final main = [
        for (var x = start; x < start + len; x++) ...[x, x, x],
      ];
      if (planeKind == 0) {
        plays.add(Play(PlayType.airplane, start, len, main));
      } else {
        final wings = planeKickers.sublist(k, k + len);
        k += len;
        plays.add(Play(planeKind == 1 ? PlayType.airplaneSolos : PlayType.airplanePairs, start, len, [
          ...main,
          for (final w in wings) ...List.filled(planeKind, w),
        ]));
      }
    }
    final trioKicker = <int, int>{};
    for (var t = 0; t <= Rank.two; t++) {
      if (rest[t] != 3) continue;
      for (var x = 0; x < Rank.two; x++) {
        if (x != t && (rest[x] == 1 || rest[x] == 2) && (used & (1 << x)) == 0) {
          used |= 1 << x;
          trioKicker[t] = x;
          break;
        }
      }
    }
    for (var t = 0; t <= Rank.two; t++) {
      if (rest[t] != 3) continue;
      final kx = trioKicker[t];
      if (kx == null) {
        plays.add(Play(PlayType.trio, t, 1, [t, t, t]));
      } else {
        final n = rest[kx];
        plays.add(Play(n == 1 ? PlayType.trioSolo : PlayType.trioPair, t, 1, [t, t, t, ...List.filled(n, kx)]));
      }
    }
    for (var x = 0; x < Rank.count; x++) {
      if ((used & (1 << x)) != 0) continue;
      if (rest[x] == 1) plays.add(Play(PlayType.solo, x, 1, [x]));
      if (rest[x] == 2) plays.add(Play(PlayType.pair, x, 1, [x, x]));
    }
    for (final b in _bombs) {
      plays.add(Play(PlayType.bomb, b, 1, [b, b, b, b]));
    }
    if (rocket) plays.add(Play(PlayType.rocket, Rank.littleJoker, 1, [Rank.littleJoker, Rank.bigJoker]));
    return HandPlan(plays, bestScore);
  }
}
