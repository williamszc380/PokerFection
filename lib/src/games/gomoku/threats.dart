/// Threat-space search: proving forced wins.
///
/// A forced win in Gomoku is a chain of threats the defender must answer
/// each time, ending in five. Allis ("Go-Moku and Threat-Space Search",
/// 1994) showed that searching only those threats finds wins far deeper
/// than a normal search can. Two kinds are searched here:
/// - VCF (victory by continuous fours): every attacking move is a four, so
///   the defender's reply is forced (block the five point). Very cheap.
/// - VCT (victory by continuous threats): fours and threes. After a three
///   the defender may block in any of several ways, or answer with fours of
///   its own; the win is proven only if every one of those replies loses.
///
/// Every answer is a proof: the defender's replies are never pruned (only
/// moves that provably can't stop the threat are skipped), so "wins in N"
/// is shown only when it is true. N counts the attacker's own moves, the
/// five included, and is the shortest win the solver can find (it tries
/// 1, 2, 3… moves in turn).
library;

import 'board.dart';
import 'patterns.dart';

/// A proven forced win.
class ThreatProof {
  /// A win in [movesToWin] of the attacker's moves, along [line].
  const ThreatProof(this.movesToWin, this.line, {required this.foursOnly});

  /// The attacker's moves to make five, counting the five itself.
  final int movesToWin;

  /// One forcing line, attacker first, alternating with the defender's
  /// replies and ending with the five (point numbers). The defender's
  /// moves are one of its options; all of them lose.
  final List<int> line;

  /// Whether every attacking move is a four (VCF).
  final bool foursOnly;
}

/// Proves forced wins on a [Board]. Keeps what it learned between calls, so
/// the coach's many related questions about one position share the work.
/// The board is left as it was found.
final class ThreatSolver {
  /// A solver working on [board].
  ThreatSolver(this.board);

  /// The board searched. Positions are told apart by its hash.
  final Board board;

  /// The positions visited so far, over all calls.
  int nodes = 0;

  /// Whether the last call ran out of nodes before it could finish (so a
  /// missing proof means "not found", not "none exists").
  bool aborted = false;

  int _limit = 0;
  bool _foursOnly = false;
  Stopwatch? _clock;
  Duration _deadline = Duration.zero;

  /// Makes every later call give up (as if out of nodes, see [aborted]) once
  /// [clock] reaches [deadline]: the coach's safety cap on slow devices.
  /// Node limits alone keep answers the same on every device; the deadline
  /// trades that for responsiveness, so it should rarely be reached.
  void stopAt(Stopwatch clock, Duration deadline) {
    _clock = clock;
    _deadline = deadline;
  }

  // Per mode (0 VCT, 1 VCF): the deepest search that failed from each
  // attacker position, and the fastest win found from each won one (moves
  // to win × 1024 + the move).
  final _fail = [<int, int>{}, <int, int>{}];
  final _win = [<int, int>{}, <int, int>{}];

  /// A VCF for the side to move: a win by fours alone in at most
  /// [maxDepth] of its moves, within [maxNodes] positions. Null if none.
  ThreatProof? vcf({int maxDepth = 30, int maxNodes = 50000}) =>
      _solve(true, maxDepth, maxNodes);

  /// A VCT for the side to move: a win by fours and threes in at most
  /// [maxDepth] of its moves, within [maxNodes] positions. Null if none
  /// was found (see [aborted]).
  ThreatProof? vct({int maxDepth = 10, int maxNodes = 50000}) =>
      _solve(false, maxDepth, maxNodes);

  /// A forced win that starts with the side to move playing [move]: after
  /// it, every reply loses. Null if none was found.
  ThreatProof? winAfter(int move, {bool foursOnly = false, int maxDepth = 10, int maxNodes = 20000}) {
    if (!board.isLegal(move)) return null;
    _start(foursOnly, maxNodes);
    final me = board.side;
    if (board.combo(me, move) == Combo.five) return ThreatProof(1, [move], foursOnly: true);
    board.play(move);
    var found = 0;
    for (var depth = 1; depth < maxDepth && found == 0 && !aborted; depth++) {
      found = _defend(depth);
    }
    ThreatProof? proof;
    if (found > 0) proof = ThreatProof(found + 1, [move, ..._line(false)], foursOnly: foursOnly);
    board.undo();
    return proof;
  }

  void _start(bool foursOnly, int maxNodes) {
    _foursOnly = foursOnly;
    _limit = nodes + maxNodes;
    aborted = false;
  }

  ThreatProof? _solve(bool foursOnly, int maxDepth, int maxNodes) {
    _start(foursOnly, maxNodes);
    for (var depth = 1; depth <= maxDepth && !aborted; depth++) {
      final n = _attack(depth);
      if (n > 0) return ThreatProof(n, _line(true), foursOnly: foursOnly);
    }
    return null;
  }

  int get _mode => _foursOnly ? 1 : 0;

  // Keeps the fastest win from a position: the same position can be proven
  // again later with a bigger budget and a slower line, and the line shown
  // must match the proof's length.
  void _remember(int key, int move, int movesToWin) {
    final map = _win[_mode];
    final old = map[key];
    if (old == null || old ~/ 1024 > movesToWin) map[key] = movesToWin * 1024 + move;
  }

  // The attacker (the side to move) has depth moves left, counting the
  // five. Returns the moves it needs to win, or 0.
  int _attack(int depth) {
    nodes++;
    final me = board.side, opp = 3 - me;
    final five = board.firstFivePoint(me);
    if (five >= 0) {
      _remember(board.key53, five, 1);
      return 1;
    }
    if (nodes > _limit || (nodes & 255 == 0 && _clock != null && _clock!.elapsed >= _deadline)) {
      aborted = true;
      return 0;
    }
    final moves = <int>[];
    if (board.count(opp, Combo.five) > 0) {
      // The defender has a four: blocking it is the only move.
      final blocks = <int>[];
      board.fivePoints(opp, blocks);
      if (blocks.length > 1 || !board.isLegal(blocks[0]) || depth < 2) return 0;
      moves.add(blocks[0]);
    } else {
      if (board.hasWinIn2(me)) {
        if (depth < 2) return 0;
        _remember(board.key53, _winIn2Point(me), 2);
        return 2;
      }
      if (depth < 2) return 0;
      // A three takes at least three moves to win; and against the
      // opponent's open three only fours keep the initiative.
      final foursOnly = _foursOnly || depth < 3 || board.hasWinIn2(opp);
      final set = board.threats[me - 1];
      for (var i = 0; i < set.length; i++) {
        final c = set[i];
        final k = board.combo(me, c);
        if (k == Combo.four || k == Combo.fourThree || (!foursOnly && k < Combo.four)) moves.add(c);
      }
      if (moves.isEmpty) return 0;
      _sort(moves, me);
    }
    final key = board.key53;
    final failed = _fail[_mode][key];
    if (failed != null && failed >= depth) return 0;

    for (final m in moves) {
      if (!board.isLegal(m)) continue;
      board.play(m);
      final r = _defend(depth - 1);
      board.undo();
      if (r > 0) {
        _remember(key, m, r + 1);
        return r + 1;
      }
      if (aborted) return 0;
    }
    if (!aborted) _fail[_mode][key] = depth;
    return 0;
  }

  // The attacker has just moved and has depth moves left; the defender is
  // to move. Returns the attacker's moves still needed, or 0.
  int _defend(int depth) {
    final def = board.side, att = 3 - def;
    if (depth < 1 || board.count(def, Combo.five) > 0) return 0;
    if (board.count(att, Combo.five) > 0) {
      final points = <int>[];
      board.fivePoints(att, points);
      if (points.length > 1) return 1;
      final f = points[0];
      if (!board.isLegal(f)) return 1; // Renju: Black can't block on a forbidden point
      board.play(f);
      final r = _attack(depth);
      board.undo();
      return r;
    }
    if (_foursOnly || depth < 2 || !board.hasWinIn2(att)) return 0;
    final replies = board.defenses(att);
    if (replies.isEmpty) return 2;
    var worst = 0;
    for (final d in replies) {
      board.play(d);
      final r = _attack(depth);
      board.undo();
      if (r == 0) return 0;
      if (r > worst) worst = r;
    }
    return worst;
  }

  int _winIn2Point(int color) {
    final set = board.threats[color - 1];
    final cells = [
      for (var i = 0; i < set.length; i++)
        if (board.combo(color, set[i]) == Combo.winIn2) set[i],
    ];
    return cells.firstWhere((c) => board.isLegalFor(color, c), orElse: () => -1);
  }

  // Strongest threats first: fours before threes, then by point value.
  void _sort(List<int> moves, int me) {
    final keys = [for (final m in moves) board.combo(me, m) * 100000 + board.value(me, m) + board.value(3 - me, m)];
    for (var i = 1; i < moves.length; i++) {
      final m = moves[i], k = keys[i];
      var j = i - 1;
      while (j >= 0 && keys[j] < k) {
        moves[j + 1] = moves[j];
        keys[j + 1] = keys[j];
        j--;
      }
      moves[j + 1] = m;
      keys[j + 1] = k;
    }
  }

  // Replays a proven win from the current position to show it: the stored
  // winning moves for the attacker, and for the defender a block or the
  // first defense. attackerToMove: whether the attacker moves first.
  List<int> _line(bool attackerToMove) {
    final line = <int>[];
    final att = attackerToMove ? board.side : 3 - board.side;
    var played = 0;
    while (played < 60) {
      int move;
      if (board.side == att) {
        final five = board.firstFivePoint(att);
        if (five >= 0) {
          line.add(five);
          break;
        }
        final known = _win[_mode][board.key53];
        move = known != null ? known % 1024 : _winIn2Point(att);
        if (move < 0 || !board.isLegal(move)) break;
      } else {
        move = board.firstFivePoint(att);
        if (move < 0) {
          // The defense that holds out longest, so the line shows the
          // proof's full length.
          var longest = -1;
          move = _anyMove();
          for (final reply in board.defenses(att)) {
            board.play(reply);
            final known = _win[_mode][board.key53];
            final n = board.firstFivePoint(att) >= 0 ? 1 : (known != null ? known ~/ 1024 : 2);
            board.undo();
            if (n > longest) {
              longest = n;
              move = reply;
            }
          }
        }
        if (move < 0 || !board.isLegal(move)) break;
      }
      line.add(move);
      board.play(move);
      played++;
    }
    for (var i = 0; i < played; i++) {
      board.undo();
    }
    return line;
  }

  int _anyMove() {
    var best = -1, bestValue = -1;
    final me = board.side;
    final cells = [for (var i = 0; i < board.nearby.length; i++) board.nearby[i]];
    for (final c in cells) {
      final v = board.value(me, c);
      if (v > bestValue && board.isLegal(c)) {
        best = c;
        bestValue = v;
      }
    }
    return best;
  }
}
