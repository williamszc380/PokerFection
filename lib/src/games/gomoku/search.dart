/// The game-tree search: principal-variation alpha-beta with iterative
/// deepening, a transposition table and killer/history move ordering.
///
/// Gomoku's branching factor is large (every empty point near the stones),
/// so the search is selective: it looks at the most promising points only
/// (by their line shapes, for both colors), and when the opponent threatens
/// to win (a four, or an open three) it looks only at the moves that stop
/// it or answer with a four. That forced-reply pruning is what lets a
/// fraction of a second reach a useful depth. Its scores are estimates; the
/// threat solver (threats.dart) is what proves wins.
library;

import 'dart:typed_data';

import 'board.dart';
import 'patterns.dart';

/// When a search must stop. A node limit alone makes the search
/// deterministic (the same position always gets the same answer); a time
/// limit keeps the app responsive on slow devices.
class SearchLimits {
  /// At most [maxDepth] plies, [maxNodes] positions and [maxTime].
  const SearchLimits({this.maxDepth = 30, this.maxNodes, this.maxTime});

  /// The deepest iteration to start.
  final int maxDepth;

  /// The most positions to visit, or null for no limit.
  final int? maxNodes;

  /// The longest to search, or null for no limit.
  final Duration? maxTime;
}

/// How wide the selective search is: how many of the best-looking moves it
/// tries at each depth.
class SearchWidth {
  /// [root] moves at the root, [first] one ply down, then [step] fewer per
  /// ply, never fewer than [min].
  const SearchWidth({this.root = 24, this.first = 14, this.step = 2, this.min = 6});

  /// Moves tried at the root.
  final int root;

  /// Moves tried one ply below the root.
  final int first;

  /// How many fewer moves each further ply tries.
  final int step;

  /// The fewest moves any ply tries.
  final int min;

  /// The number of moves to try at [ply].
  int at(int ply) {
    if (ply == 0) return root;
    final w = first - step * (ply - 1);
    return w < min ? min : w;
  }
}

/// What a search found.
class SearchResult {
  /// A result; see the fields.
  const SearchResult({
    required this.move,
    required this.score,
    required this.depth,
    required this.nodes,
    required this.elapsed,
    required this.pv,
    required this.rootScores,
  });

  /// The best move (a point number), or −1 if there was none.
  final int move;

  /// Its score for the side to move: positive is good. Beyond
  /// [Searcher.winBound] it means a win (or below −[Searcher.winBound] a
  /// loss) found by the search, in [Searcher.win] minus the number of plies.
  final int score;

  /// The deepest iteration completed.
  final int depth;

  /// Positions visited.
  final int nodes;

  /// Time taken.
  final Duration elapsed;

  /// The expected line, starting with [move].
  final List<int> pv;

  /// The score of each root move searched in the last completed iteration.
  /// Exact for the best few (as many as the search was asked for); the
  /// others are upper bounds.
  final Map<int, int> rootScores;
}

/// Searches positions on one [Board]. Reusable: the transposition table and
/// move-ordering statistics carry over from one search to the next.
final class Searcher {
  /// A searcher for [board], with a transposition table of 2^[ttBits]
  /// entries and the given [width].
  Searcher(this.board, {int ttBits = 18, this.width = const SearchWidth()})
      : _ttMask = (1 << ttBits) - 1,
        _ttLo = Uint32List(1 << ttBits),
        _ttHi = Uint32List(1 << ttBits),
        _ttScore = Int32List(1 << ttBits),
        _ttDepth = Int8List(1 << ttBits),
        _ttFlag = Uint8List(1 << ttBits),
        _ttMove = Int16List(1 << ttBits),
        _history = Int32List(board.area * 2),
        _killers = Int16List(maxPly * 2)..fillRange(0, maxPly * 2, -1),
        _moveBuf = List.generate(maxPly, (_) => Int32List(board.area)),
        _keyBuf = List.generate(maxPly, (_) => Int32List(board.area));

  /// The board searched (left as it was found).
  final Board board;

  /// How many moves each ply tries.
  final SearchWidth width;

  /// The score of making five right now.
  static const win = 30000;

  /// Scores beyond this (in size) are wins or losses, not estimates.
  static const winBound = 29000;

  /// The deepest ply the search goes, extensions included.
  static const maxPly = 64;

  static const _inf = 32000;
  static const _exact = 1, _lower = 2, _upper = 3;

  final int _ttMask;
  final Uint32List _ttLo, _ttHi;
  final Int32List _ttScore;
  final Int8List _ttDepth;
  final Uint8List _ttFlag;
  final Int16List _ttMove;
  final Int32List _history;
  final Int16List _killers;
  final List<Int32List> _moveBuf, _keyBuf;

  /// Positions visited by the current or last search.
  int nodes = 0;

  bool _aborted = false;
  int _nextCheck = 0;
  int? _maxNodes;
  Duration? _maxTime;
  final _clock = Stopwatch();

  /// Searches the position for the side to move, deepening one ply at a
  /// time until [limits] are reached. [rootMoves] restricts (and orders) the
  /// moves considered at the root. [exactRoots]: how many of the best root
  /// moves get an exact score (the coach shows several); the others only
  /// get an upper bound, which is much cheaper. [stopEarly]: stop deepening
  /// once a win is found or only one move is left (right for playing, not
  /// for measuring a move's score).
  SearchResult search(SearchLimits limits, {List<int>? rootMoves, int exactRoots = 1, bool stopEarly = true}) {
    nodes = 0;
    _nextCheck = 1024;
    _aborted = false;
    _maxNodes = limits.maxNodes;
    _maxTime = limits.maxTime;
    _clock
      ..reset()
      ..start();
    for (var i = 0; i < _history.length; i++) {
      _history[i] >>= 2;
    }

    final roots = rootMoves != null ? [...rootMoves] : _rootMoves();
    if (roots.isEmpty) {
      return SearchResult(move: -1, score: 0, depth: 0, nodes: 0, elapsed: _clock.elapsed, pv: const [], rootScores: const {});
    }
    var bestMove = roots.first, bestScore = 0, completed = 0;
    var scores = <int, int>{};

    for (var depth = 1; depth <= limits.maxDepth; depth++) {
      final iteration = <int, int>{};
      // The best exact scores so far, highest first (at most exactRoots).
      final top = <int>[];
      var iterBest = -_inf, iterMove = roots.first;
      for (var i = 0; i < roots.length; i++) {
        final m = roots[i];
        board.play(m);
        int s;
        if (top.length < exactRoots) {
          s = -_search(depth - 1, -_inf, _inf, 1);
        } else {
          // Only an exact score above the worst of the top ones matters.
          final bar = top.last;
          s = -_search(depth - 1, -bar - 1, -bar, 1);
          if (s > bar && !_aborted) s = -_search(depth - 1, -_inf, -bar, 1);
        }
        board.undo();
        if (_aborted) break;
        iteration[m] = s;
        if (top.length < exactRoots || s > top.last) {
          top.add(s);
          top.sort((a, b) => b.compareTo(a));
          if (top.length > exactRoots) top.removeLast();
        }
        if (s > iterBest) {
          iterBest = s;
          iterMove = m;
        }
      }
      if (_aborted) break;
      completed = depth;
      bestMove = iterMove;
      bestScore = iterBest;
      scores = iteration;
      // Best first next time (a stable sort keeps the old order for ties).
      final order = [...roots];
      roots
        ..clear()
        ..addAll((order.indexed.toList()
              ..sort((a, b) {
                final c = iteration[b.$2]!.compareTo(iteration[a.$2]!);
                return c != 0 ? c : a.$1.compareTo(b.$1);
              }))
            .map((e) => e.$2));
      // A win (or a loss everywhere) found: deeper won't change the move.
      if (stopEarly && (bestScore.abs() >= winBound || roots.length == 1)) break;
    }
    _clock.stop();
    return SearchResult(
      move: bestMove,
      score: bestScore,
      depth: completed,
      nodes: nodes,
      elapsed: _clock.elapsed,
      pv: _pv(bestMove),
      rootScores: scores,
    );
  }

  /// The moves the search considers at the root, best-looking first.
  List<int> rootMoves() => _rootMoves();

  List<int> _rootMoves() {
    final me = board.side, opp = 3 - me;
    final five = board.firstFivePoint(me);
    if (five >= 0) return [five];
    if (board.count(opp, Combo.five) > 0) {
      final blocks = <int>[];
      board.fivePoints(opp, blocks);
      final legal = blocks.where(board.isLegal).toList();
      return legal.isNotEmpty ? [legal.first] : instinctMoves(1);
    }
    if (board.moveCount == 0) return [board.center];
    final n = _generate(0, -1);
    return [for (var i = 0; i < n; i++) _moveBuf[0][i]];
  }

  /// The [n] best-looking legal points by their line shapes alone,
  /// ignoring whatever the opponent threatens (the easy bot's "instinct").
  List<int> instinctMoves(int n) {
    final me = board.side, opp = 3 - me;
    final near = board.nearby;
    final cells = [for (var i = 0; i < near.length; i++) near[i]]
      ..sort((a, b) {
        // Ties broken by point, so every platform sorts alike.
        final c = _key(b, me, opp, 0, -1).compareTo(_key(a, me, opp, 0, -1));
        return c != 0 ? c : a.compareTo(b);
      });
    final legal = cells.where(board.isLegal).take(n).toList();
    return legal.isNotEmpty ? legal : _anyMoves(1);
  }

  /// The expected line after the side to move plays [move], from what the
  /// last search stored.
  List<int> principalVariation(int move) => _pv(move);

  List<int> _anyMoves(int n) {
    final out = <int>[];
    for (var c = 0; c < board.area && out.length < n; c++) {
      if (board.isLegal(c)) out.add(c);
    }
    return out;
  }

  int _search(int depth, int alpha, int beta, int ply) {
    if (++nodes >= _nextCheck) {
      _nextCheck = nodes + 1024;
      _checkLimits();
    }
    if (_aborted) return 0;
    final me = board.side, opp = 3 - me;
    if (board.count(me, Combo.five) > 0) return win - ply - 1;
    var forced = -1;
    if (board.count(opp, Combo.five) > 0) {
      final f = board.firstFivePoint(opp);
      if (board.count(opp, Combo.five) > 1 || !board.isLegal(f)) return -(win - ply - 2);
      forced = f;
    } else if (board.hasWinIn2(me)) {
      return win - ply - 3;
    }
    if (ply >= maxPly - 1 || (forced < 0 && depth <= 0)) return board.evaluate();

    final idx = board.hashLo & _ttMask;
    var ttMove = -1;
    if (_ttLo[idx] == board.hashLo && _ttHi[idx] == board.hashHi) {
      ttMove = _ttMove[idx];
      if (_ttDepth[idx] >= depth) {
        var s = _ttScore[idx];
        if (s > winBound) s -= ply;
        if (s < -winBound) s += ply;
        final flag = _ttFlag[idx];
        if (flag == _exact || (flag == _lower && s >= beta) || (flag == _upper && s <= alpha)) return s;
      }
    }

    final moves = _moveBuf[ply];
    int n;
    if (forced >= 0) {
      moves[0] = forced;
      n = 1;
    } else {
      n = _generate(ply, ttMove);
      if (n == 0) return 0; // the board is full
    }
    final next = forced >= 0 ? depth : depth - 1;

    var best = -_inf, bestMove = moves[0], flag = _upper;
    final alpha0 = alpha;
    for (var i = 0; i < n; i++) {
      final m = moves[i];
      board.play(m);
      int s;
      if (i == 0) {
        s = -_search(next, -beta, -alpha, ply + 1);
      } else {
        s = -_search(next, -alpha - 1, -alpha, ply + 1);
        if (s > alpha && s < beta && !_aborted) s = -_search(next, -beta, -alpha, ply + 1);
      }
      board.undo();
      if (_aborted) return 0;
      if (s > best) {
        best = s;
        bestMove = m;
        if (s > alpha) {
          alpha = s;
          if (s >= beta) {
            flag = _lower;
            if (forced < 0) {
              _history[m * 2 + me - 1] += depth * depth;
              final k = ply * 2;
              if (_killers[k] != m) {
                _killers[k + 1] = _killers[k];
                _killers[k] = m;
              }
            }
            break;
          }
        }
      }
    }
    if (flag != _lower) flag = best > alpha0 ? _exact : _upper;
    var stored = best;
    if (stored > winBound) stored += ply;
    if (stored < -winBound) stored -= ply;
    _ttLo[idx] = board.hashLo;
    _ttHi[idx] = board.hashHi;
    _ttScore[idx] = stored;
    _ttDepth[idx] = depth < 0 ? 0 : (depth > 127 ? 127 : depth);
    _ttFlag[idx] = flag;
    _ttMove[idx] = bestMove;
    return best;
  }

  // Fills _moveBuf[ply] with the moves to try, best-looking first, and
  // returns how many. The side to move has no five and faces no four.
  int _generate(int ply, int ttMove) {
    final me = board.side, opp = 3 - me;
    final moves = _moveBuf[ply], keys = _keyBuf[ply];
    var n = 0;
    if (board.hasWinIn2(opp)) {
      // The opponent threatens an open four: only real defenses and our own
      // fours can matter.
      final replies = board.defenses(opp);
      if (replies.isEmpty) {
        // Lost whatever we do: block one threat anyway, as a person would.
        final open = board.threats[opp - 1];
        for (var i = 0; i < open.length && replies.isEmpty; i++) {
          if (board.combo(opp, open[i]) == Combo.winIn2 && board.isLegal(open[i])) replies.add(open[i]);
        }
        if (replies.isEmpty) replies.addAll(instinctMoves(1));
        if (replies.isEmpty) return 0;
      }
      for (final m in replies) {
        moves[n] = m;
        keys[n] = _key(m, me, opp, ply, ttMove);
        n++;
      }
    } else {
      final near = board.nearby;
      for (var i = 0; i < near.length; i++) {
        final c = near[i];
        moves[n] = c;
        keys[n] = _key(c, me, opp, ply, ttMove);
        n++;
      }
    }
    // Pick the best few that are legal (Renju forbids some for Black), best
    // first: a partial selection sort, since only the first few are kept.
    final limit = width.at(ply);
    var kept = 0;
    while (kept < limit && kept < n) {
      var bi = kept, bk = keys[kept];
      for (var j = kept + 1; j < n; j++) {
        if (keys[j] > bk) {
          bk = keys[j];
          bi = j;
        }
      }
      final m = moves[bi];
      moves[bi] = moves[kept];
      keys[bi] = keys[kept];
      if (board.isLegal(m)) {
        moves[kept] = m;
        keys[kept] = bk;
        kept++;
      } else {
        moves[kept] = moves[--n];
        keys[kept] = keys[n];
      }
    }
    return kept;
  }

  int _key(int c, int me, int opp, int ply, int ttMove) {
    if (c == ttMove) return 1 << 30;
    var k = board.value(me, c) * 4 + board.value(opp, c) * 3;
    final kill = ply * 2;
    if (_killers[kill] == c) k += 400;
    if (_killers[kill + 1] == c) k += 200;
    final h = _history[c * 2 + me - 1];
    return k + (h > 2000 ? 2000 : h);
  }

  void _checkLimits() {
    final maxNodes = _maxNodes, maxTime = _maxTime;
    if ((maxNodes != null && nodes >= maxNodes) || (maxTime != null && _clock.elapsed >= maxTime)) {
      _aborted = true;
    }
  }

  // The expected line, from the transposition table.
  List<int> _pv(int first) {
    final pv = <int>[];
    var m = first;
    while (m >= 0 && pv.length < 30 && board.isLegal(m)) {
      pv.add(m);
      board.play(m);
      if (board.winnerThrough(m) != 0) break;
      final idx = board.hashLo & _ttMask;
      m = _ttLo[idx] == board.hashLo && _ttHi[idx] == board.hashHi ? _ttMove[idx] : -1;
      if (m < 0) {
        // Forced moves are not always stored: follow fives and blocks.
        final me = board.side;
        m = board.firstFivePoint(me);
        if (m < 0) m = board.firstFivePoint(3 - me);
      }
    }
    for (var i = 0; i < pv.length; i++) {
      board.undo();
    }
    return pv;
  }
}
