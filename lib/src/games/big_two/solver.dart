/// Exact endgame solving: can a player force going out first, whatever the
/// others do?
///
/// Two uses:
/// - On one guessed deal (all hands known), it plays the endgame perfectly
///   inside the coach's play-outs.
/// - Against "super-opponents" who may hold any of the cards the player
///   can't see (each limited only by how many cards they hold, and free to
///   play a card another opponent already played), a proven win is a real
///   proof: the actual opponents can only do less. This is how the coach
///   can say "you can't be beaten" without guessing.
///
/// The search assumes the opponents work together to stop the player (a
/// "paranoid" search), so a win it finds holds against anything. Positions
/// are remembered by a hash made of 32-bit parts, so it works the same in
/// JavaScript.
library;

import 'dart:typed_data';

import 'plays.dart';
import 'random.dart';
import 'state.dart';

/// The answer of one solve.
enum SolveOutcome {
  /// The player can force going out first.
  win,

  /// The opponents can stop the player.
  loss,

  /// The search ran out of its node budget.
  unknown,
}

/// A memoizing forced-win solver for small endgames.
class EndgameSolver {
  /// A solver that visits at most [nodeLimit] new positions per call.
  EndgameSolver({this.nodeLimit = 4000, this.maxMemo = 200000});

  /// Most new positions one call may visit before giving up.
  final int nodeLimit;

  /// Size at which the memo is cleared, to bound memory.
  final int maxMemo;

  final _memo = <int, bool>{};
  final _best = <int, Play>{};
  // Roots that ran out of budget: asking again would only repeat the work.
  final _gaveUp = <int>{};
  int _nodes = 0;
  bool _aborted = false;
  late int _me;
  late bool _shared;

  /// Positions visited over the solver's life, for benchmarks.
  int totalNodes = 0;

  static final Uint32List _z1 = _table(0x5eed01);
  static final Uint32List _z2 = _table(0x5eed02);
  static const _zCur = 4 * 13 * 16;
  static const _zCount = _zCur + 52;
  static const _zMisc = _zCount + 4 * 32;
  static const _zSize = _zMisc + 64;

  static Uint32List _table(int seed) {
    final rng = GameRandom(seed);
    return Uint32List.fromList(List.generate(_zSize, (_) => rng.nextUint32()));
  }

  /// Solves [s] with every hand known: can [me] force going out first?
  SolveOutcome solvePerfect(BigTwoState s, int me) {
    _me = me;
    _shared = false;
    return _run(s);
  }

  /// The move that forces the win found by the last [solvePerfect] or
  /// [solveShared] from position [s], if any.
  Play? bestMove(BigTwoState s) => _best[_key(s)];

  /// Solves against super-opponents: [s] must hold, in every opponent's
  /// seat, all the cards [me] cannot see (see [sharedState]).
  SolveOutcome solveShared(BigTwoState s, int me) {
    _me = me;
    _shared = true;
    return _run(s);
  }

  /// A copy of [s] in which every opponent holds every card [me] cannot
  /// see (keeping their real card counts), ready for [solveShared].
  ///
  /// A card everyone can place ([BigTwoState.knownCards]: the visible ones,
  /// and the card a three-player taker of the 52nd card must hold) stays
  /// with its holder only: the proof may not hand it to another opponent. In a
  /// two-player deal the cards below the starting card were never dealt,
  /// so nobody gets them. Each real hand is still inside its opponent's
  /// cards, so a proven win stays a proof.
  static BigTwoState sharedState(BigTwoState s, int me) {
    final t = s.copy();
    final masks = t.handMasks;
    final played = t.playedMasks;
    final undealt = t.players == 2 && t.startCode >= 0 && !t.leaderChosen ? t.startCode : 0;
    for (var r = 0; r < 13; r++) {
      var unseen = 15 & ~masks[me * 13 + r] & ~played[r];
      for (var c = r * 4; c < r * 4 + 4 && c < undealt; c++) {
        unseen &= ~(1 << (c & 3));
      }
      for (var o = 0; o < t.players; o++) {
        if (o != me) masks[o * 13 + r] = unseen;
      }
    }
    final shown = List.generate(t.players, (_) => <int>[]);
    for (final v in t.knownCards) {
      if (v.seat == me) continue;
      shown[v.seat].add(v.code);
      for (var o = 0; o < t.players; o++) {
        if (o != me && o != v.seat) masks[o * 13 + (v.code >> 2)] &= ~(1 << (v.code & 3));
      }
    }
    // An opponent whose every card is known holds exactly those.
    for (var o = 0; o < t.players; o++) {
      if (o == me || shown[o].isEmpty || shown[o].length != t.countOf(o)) continue;
      masks.fillRange(o * 13, o * 13 + 13, 0);
      for (final c in shown[o]) {
        masks[o * 13 + (c >> 2)] |= 1 << (c & 3);
      }
    }
    return t;
  }

  SolveOutcome _run(BigTwoState s) {
    if (_memo.length > maxMemo) {
      _memo.clear();
      _best.clear();
      _gaveUp.clear();
    }
    final rootKey = _key(s);
    if (_gaveUp.contains(rootKey)) return SolveOutcome.unknown;
    _nodes = 0;
    _aborted = false;
    final r = _search(s);
    totalNodes += _nodes;
    if (r < 0) _gaveUp.add(rootKey);
    if (r == 1) return SolveOutcome.win;
    if (r == 0) return SolveOutcome.loss;
    return SolveOutcome.unknown;
  }

  // 1 = win for _me, 0 = loss, -1 = unknown (budget).
  int _search(BigTwoState s) {
    if (s.winner >= 0) return s.winner == _me ? 1 : 0;
    final key = _key(s);
    final known = _memo[key];
    if (known != null) return known ? 1 : 0;
    if (++_nodes > nodeLimit) {
      _aborted = true;
      return -1;
    }
    final mine = s.toMove == _me;
    final moves = mine ? s.legalMoves() : _opponentMoves(s);
    _order(moves, s.countOf(s.toMove));
    var unknown = false;
    int result;
    if (mine) {
      result = 0;
      for (final m in moves) {
        final r = _search(_child(s, m));
        if (r == 1) {
          result = 1;
          _best[key] = m;
          break;
        }
        if (r < 0) unknown = true;
        if (_aborted) break;
      }
      if (result == 0 && unknown) result = -1;
    } else {
      result = 1;
      for (final m in moves) {
        final r = _search(_child(s, m));
        if (r == 0) {
          result = 0;
          break;
        }
        if (r < 0) unknown = true;
        if (_aborted) break;
      }
      if (result == 1 && unknown) result = -1;
    }
    if (result >= 0) _memo[key] = result == 1;
    return result;
  }

  List<Play> _opponentMoves(BigTwoState s) {
    if (!_shared) return s.legalMoves();
    final seat = s.toMove;
    if (s.rules.passLockout && s.lockedMask & (1 << seat) != 0) return [Play.pass];
    // Any play from the cards the player can't see, no bigger than the
    // opponent's hand. The last-card rule is left out: it only ever limits
    // a real opponent, so ignoring it keeps the proof sound.
    final plays = s.rules.playsFrom(s.handMasks, seat * 13, s.current, maxSize: s.countOf(seat));
    if (s.current != null) plays.add(Play.pass);
    return plays;
  }

  // In shared mode the cards an opponent plays stay in the pool: the
  // super-opponents only get stronger (a real opponent can't play a card
  // twice), so a proof stays sound, and positions that differ only in
  // which unseen cards went where become one position for the memo.
  BigTwoState _child(BigTwoState s, Play m) {
    final c = s.copy();
    c.applyTrusted(m);
    return c;
  }

  // Going out first, then bigger and higher plays; passing last. Finding a
  // winning (or refuting) move early cuts the search short.
  // Ties are broken on the cards, so the order is total and the Dart VM
  // and JavaScript (whose sorts treat equal elements differently) agree.
  static void _order(List<Play> moves, int handSize) {
    int rank(Play p) => p.isPass ? -1 : (p.size == handSize ? 1 << 30 : 0) + p.size * 10000000 + p.key;
    moves.sort((a, b) {
      final c = rank(b).compareTo(rank(a));
      if (c != 0) return c;
      for (var i = 0; i < a.codes.length; i++) {
        final d = b.codes[i].compareTo(a.codes[i]);
        if (d != 0) return d;
      }
      return 0;
    });
  }

  int _key(BigTwoState s) {
    var h1 = _shared ? _z1[_zMisc + 48] : 0, h2 = _shared ? _z2[_zMisc + 48] : 0;
    final masks = s.handMasks;
    for (var seat = 0; seat < s.players; seat++) {
      for (var r = 0; r < 13; r++) {
        final m = masks[seat * 13 + r];
        if (m == 0) continue;
        final i = (seat * 13 + r) * 16 + m;
        h1 ^= _z1[i];
        h2 ^= _z2[i];
      }
      final cnt = s.countOf(seat) & 31;
      h1 ^= _z1[_zCount + seat * 32 + cnt];
      h2 ^= _z2[_zCount + seat * 32 + cnt];
    }
    final cur = s.current;
    if (cur != null) {
      for (final c in cur.codes) {
        h1 ^= _z1[_zCur + c];
        h2 ^= _z2[_zCur + c];
      }
      h1 ^= _z1[_zMisc + 8 + s.lastPlayer];
      h2 ^= _z2[_zMisc + 8 + s.lastPlayer];
    }
    h1 ^= _z1[_zMisc + s.toMove];
    h2 ^= _z2[_zMisc + s.toMove];
    h1 ^= _z1[_zMisc + 16 + s.passesInRow];
    h2 ^= _z2[_zMisc + 16 + s.passesInRow];
    h1 ^= _z1[_zMisc + 32 + (s.lockedMask & 15)];
    h2 ^= _z2[_zMisc + 32 + (s.lockedMask & 15)];
    // 32 + 21 bits: an exact integer in JavaScript as well.
    return h1 * 2097152 + (h2 & 0x1fffff);
  }
}
