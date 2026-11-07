/// Exact solving of small endgames with every hand known.
///
/// When few cards are left, the coach stops guessing how the deal will be
/// played out and searches every line instead: the landlord picks the play
/// that wins if any does, the peasants (one team, playing together) pick
/// the play that stops the landlord if any does. A table of solved
/// positions keeps the search small, since the same hands are reached in
/// many orders.
///
/// The table key is a hash made of two 26-bit halves, joined by arithmetic
/// into one integer below 2^52: exact on both the native and the
/// JavaScript builds (which have 53-bit numbers and 32-bit bit operations).
library;

import 'dart:math';

import 'cards.dart';
import 'play_gen.dart';
import 'plays.dart';
import 'rules.dart';
import 'sim.dart';

const int _mask26 = 0x3FFFFFF;
const int _two26 = 0x4000000;

/// Random 26-bit numbers per (seat, rank, count), two tables, made once
/// from a fixed seed so every build hashes the same way.
final List<List<int>> _zobrist = () {
  final rnd = Random(0x5EED);
  return [
    for (var t = 0; t < 2; t++) [for (var i = 0; i < 3 * Rank.count * 5; i++) rnd.nextInt(_two26)],
  ];
}();

/// Mixes a small number (below 2^20) into 26 bits. The product stays below
/// 2^50, so it is exact in JavaScript too.
int _mix(int x, int salt) => ((x + salt) * 0x2545F491) & _mask26;

/// Solves endgames exactly. One solver can be reused for many positions of
/// the same deal; its table then carries over.
class DdzEndgameSolver {
  DdzEndgameSolver({this.nodeLimit = 200000});

  /// One call gives up (returns null) after searching this many positions.
  final int nodeLimit;

  /// Positions searched by the last call.
  int nodes = 0;

  /// Positions searched by all calls since the solver was made.
  int totalNodes = 0;

  final Map<int, bool> _table = {};

  late List<List<int>> _hands;
  late List<int> _sizes;
  late int _lord;
  late int _rulesFourWithTwo;
  late DdzRules _rules;
  int _h1 = 0, _h2 = 0;

  /// Clears the table (call when switching to an unrelated deal).
  void clear() {
    _table.clear();
    nodes = 0;
    totalNodes = 0;
  }

  /// Whether the landlord's side wins [sim] with best play by everyone, or
  /// null when the position is too big for [nodeLimit].
  bool? landlordWins(DdzSim sim) {
    if (sim.over) return sim.winner == sim.landlord;
    _hands = [for (final h in sim.hands) List<int>.of(h)];
    _sizes = List<int>.of(sim.sizes);
    _lord = sim.landlord;
    _rules = sim.rules;
    _rulesFourWithTwo = sim.rules.fourWithTwo ? 1 : 0;
    _h1 = 0;
    _h2 = 0;
    for (var s = 0; s < 3; s++) {
      for (var r = 0; r < Rank.count; r++) {
        _h1 ^= _zobrist[0][_zi(s, r, _hands[s][r])];
        _h2 ^= _zobrist[1][_zi(s, r, _hands[s][r])];
      }
    }
    nodes = 0;
    try {
      return _solve(sim.toAct, sim.current, sim.currentPlayer);
    } on _Abort {
      return null;
    } finally {
      totalNodes += nodes;
    }
  }

  static int _zi(int seat, int rank, int count) => (seat * Rank.count + rank) * 5 + count;

  int _key(int toAct, Play? current, int currentPlayer) {
    final trick = current == null
        ? toAct
        : 3 + toAct + 3 * (currentPlayer + 3 * (current.length + 16 * (current.rank + 16 * (current.type.index + 1))));
    final salt = _rulesFourWithTwo;
    return ((_h1 ^ _mix(trick, salt)) & _mask26) * _two26 + ((_h2 ^ _mix(trick, 7 + salt)) & _mask26);
  }

  bool _solve(int toAct, Play? current, int currentPlayer) {
    final key = _key(toAct, current, currentPlayer);
    final known = _table[key];
    if (known != null) return known;
    if (++nodes > nodeLimit) throw const _Abort();

    final hand = _hands[toAct];
    final lordToMove = toAct == _lord;
    final moves = current == null ? leadPlays(hand, _rules) : beatingPlays(hand, current, _rules);

    // Going out ends the deal at once.
    for (final p in moves) {
      if (p.size == _sizes[toAct]) {
        _table[key] = lordToMove;
        return lordToMove;
      }
    }
    // Bigger plays first: they usually decide a short endgame.
    moves.sort((a, b) {
      final d = b.size - a.size;
      return d != 0 ? d : comparePlays(a, b);
    });
    final next = toAct == 2 ? 0 : toAct + 1;
    var result = !lordToMove; // what the side to move gets if nothing works
    for (final p in moves) {
      _take(toAct, p, -1);
      final childLordWins = _solve(next, p, toAct);
      _take(toAct, p, 1);
      if (childLordWins == lordToMove) {
        result = lordToMove;
        break;
      }
    }
    if (result != lordToMove && current != null) {
      // Passing: after the second pass in a row the last player leads.
      final passesSoFar = (toAct - currentPlayer + 2) % 3; // 0 or 1
      final childLordWins = passesSoFar == 1 ? _solve(next, null, -1) : _solve(next, current, currentPlayer);
      if (childLordWins == lordToMove) result = lordToMove;
    }
    _table[key] = result;
    return result;
  }

  void _take(int seat, Play p, int sign) {
    final h = _hands[seat];
    final z1 = _zobrist[0], z2 = _zobrist[1];
    for (final r in p.ranks) {
      final before = h[r];
      final after = before + sign;
      _h1 ^= z1[_zi(seat, r, before)] ^ z1[_zi(seat, r, after)];
      _h2 ^= z2[_zi(seat, r, before)] ^ z2[_zi(seat, r, after)];
      h[r] = after;
    }
    _sizes[seat] += sign * p.size;
  }
}

class _Abort implements Exception {
  const _Abort();
}

/// Whether the landlord can force a win without seeing how the peasants'
/// cards are split between them.
///
/// [DdzEndgameSolver] lets every player see every hand. That is fair to
/// the peasants once the landlord holds only shown kitty cards (each
/// peasant can then work out both other hands), but not to the landlord:
/// he sees the peasants' cards only as one pile. A win the solver finds for
/// him may need a different play for each way the pile could be split, and
/// he can't know which split he faces. So a peasant's loss is only certain
/// when one line of play wins for the landlord against every split he
/// can't rule out, whatever the peasants do.
///
/// This searches exactly that: at the landlord's turns one play must work
/// for every split still possible; at a peasant's turn, every play the
/// peasant could make in any possible split must still lose for the
/// peasants, and after it only the splits where that play was possible
/// remain. It assumes the landlord learns nothing from the peasants'
/// style, so a "yes" holds against any play by the peasants.
///
/// One check can answer several positions of the same deal (its table of
/// solved positions carries over); make a new one for another deal.
class DdzBlindLandlordCheck {
  DdzBlindLandlordCheck({this.nodeLimit = 100000, this.maxSplits = 256})
    : _open = DdzEndgameSolver(nodeLimit: nodeLimit);

  /// The check gives up (answers null) after this many positions, all
  /// calls together.
  final int nodeLimit;

  /// The check gives up when the peasants' cards can be split more ways
  /// than this: the search would be too big to finish in time anyway.
  final int maxSplits;

  /// Positions searched so far.
  int nodes = 0;

  final DdzEndgameSolver _open;
  final Map<String, bool> _table = {};
  late DdzRules _rules;
  late int _lord, _a, _b;

  /// Whether the landlord wins [sim] against every split of the peasants'
  /// cards (with the same hand sizes) by one line of play, or null when
  /// the search is too big.
  ///
  /// [known] (rank counts by seat, as DdzCardCount.knownInHand) are cards
  /// the landlord knows a peasant holds: the face-up card, which everyone
  /// saw dealt to that peasant. A split that puts one on the other peasant
  /// can't be the deal, so it is left out. The real split always stays, so
  /// a "yes" still holds; it is only found more often.
  bool? landlordWins(DdzSim sim, {List<List<int>>? known}) {
    if (sim.over) return sim.winner == sim.landlord;
    _rules = sim.rules;
    _lord = sim.landlord;
    _a = (_lord + 1) % 3;
    _b = (_lord + 2) % 3;
    final pool = [for (var r = 0; r < Rank.count; r++) sim.hands[_a][r] + sim.hands[_b][r]];
    final splits = <List<int>>[];
    final pick = List<int>.filled(Rank.count, 0);
    final atLeastA = known?[_a] ?? List<int>.filled(Rank.count, 0);
    final atLeastB = known?[_b] ?? List<int>.filled(Rank.count, 0);
    void build(int r, int left) {
      if (r == Rank.count) {
        if (left == 0) splits.add(List<int>.of(pick));
        return;
      }
      // Seat _a holds at least its known cards, and leaves seat _b its own.
      for (var n = atLeastA[r]; n <= pool[r] - atLeastB[r] && n <= left; n++) {
        pick[r] = n;
        build(r + 1, left - n);
      }
      pick[r] = 0;
    }

    build(0, sim.sizes[_a]);
    if (splits.length > maxSplits) return null;
    try {
      // Quick refusal: a split where the landlord loses even seeing every
      // card is one he can't beat blind either.
      for (final s in splits) {
        if (!_openWins(sim, s, pool)) return false;
      }
      return _solve(
        List<int>.of(sim.hands[_lord]),
        pool,
        List<int>.of(sim.sizes),
        splits,
        sim.toAct,
        sim.current,
        sim.currentPlayer,
        sim.passes,
      );
    } on _Abort {
      return null;
    }
  }

  bool _openWins(DdzSim sim, List<int> a, List<int> pool) {
    final hands = List<List<int>>.filled(3, const []);
    hands[_lord] = List<int>.of(sim.hands[_lord]);
    hands[_a] = List<int>.of(a);
    hands[_b] = [for (var r = 0; r < Rank.count; r++) pool[r] - a[r]];
    final s = DdzSim(
      rules: sim.rules,
      hands: hands,
      landlord: _lord,
      toAct: sim.toAct,
      stake: sim.stake,
      bombs: sim.bombs,
      current: sim.current,
      currentPlayer: sim.currentPlayer,
      passes: sim.passes,
    );
    final wins = _open.landlordWins(s);
    nodes += _open.nodes;
    if (wins == null || nodes > nodeLimit) throw const _Abort();
    return wins;
  }

  // [splits] are the first peasant's (seat [_a]) possible hands; the
  // second's is [pool] minus that.
  bool _solve(
    List<int> lordHand,
    List<int> pool,
    List<int> sizes,
    List<List<int>> splits,
    int toAct,
    Play? current,
    int currentPlayer,
    int passes,
  ) {
    final key =
        '$toAct|$currentPlayer|$passes|${current?.encode()}|${lordHand.join()}|${pool.join()}|'
        '${splits.map((s) => s.join()).join(',')}';
    final known = _table[key];
    if (known != null) return known;
    if (++nodes > nodeLimit) throw const _Abort();
    final next = toAct == 2 ? 0 : toAct + 1;

    bool afterPass() => passes == 1
        ? _solve(lordHand, pool, sizes, splits, next, null, -1, 0)
        : _solve(lordHand, pool, sizes, splits, next, current, currentPlayer, passes + 1);

    bool result;
    if (toAct == _lord) {
      final moves = current == null ? leadPlays(lordHand, _rules) : beatingPlays(lordHand, current, _rules);
      result = moves.any((p) => p.size == sizes[_lord]);
      for (final p in moves) {
        if (result) break;
        for (final r in p.ranks) {
          lordHand[r]--;
        }
        sizes[_lord] -= p.size;
        result = _solve(lordHand, pool, sizes, splits, next, p, toAct, 0);
        sizes[_lord] += p.size;
        for (final r in p.ranks) {
          lordHand[r]++;
        }
      }
      if (!result && current != null) result = afterPass();
    } else {
      // Every play the peasant could make in some split, and the splits
      // where it could.
      final options = <Play, List<List<int>>>{};
      for (final a in splits) {
        final hand = toAct == _a ? a : [for (var r = 0; r < Rank.count; r++) pool[r] - a[r]];
        final moves = current == null ? leadPlays(hand, _rules) : beatingPlays(hand, current, _rules);
        for (final p in moves) {
          (options[p] ??= []).add(a);
        }
      }
      result = !options.keys.any((p) => p.size == sizes[toAct]);
      final plays = options.keys.toList()..sort(comparePlays);
      for (final p in plays) {
        if (!result) break;
        final counts = p.counts;
        final left = [
          for (final a in options[p]!) toAct == _a ? [for (var r = 0; r < Rank.count; r++) a[r] - counts[r]] : a,
        ];
        for (var r = 0; r < Rank.count; r++) {
          pool[r] -= counts[r];
        }
        sizes[toAct] -= p.size;
        result = _solve(lordHand, pool, sizes, left, next, p, toAct, 0);
        sizes[toAct] += p.size;
        for (var r = 0; r < Rank.count; r++) {
          pool[r] += counts[r];
        }
      }
      if (result && current != null) result = afterPass();
    }
    _table[key] = result;
    return result;
  }
}
