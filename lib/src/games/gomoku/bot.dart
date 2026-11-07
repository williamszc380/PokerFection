/// Computer opponents at three levels.
library;

import 'dart:math';

import 'board.dart';
import 'game.dart';
import 'patterns.dart';
import 'rules.dart';
import 'search.dart';
import 'threats.dart';

/// How strong a bot plays.
enum BotLevel {
  /// For beginners: a shallow look, no threat solvers, some randomness.
  /// It always makes five when it can and always blocks a four, but it
  /// sometimes misses an open three, so a learner's attacks can work.
  easy,

  /// A club player: a four-ply search and the VCF solver (wins by fours).
  medium,

  /// The full engine: deep search, VCF and VCT solvers, and a check that
  /// its move doesn't hand the opponent a forced win.
  hard,
}

/// What the bot looked at for its last move (for the match tool and
/// debugging).
class BotStats {
  /// See the fields.
  const BotStats({required this.how, required this.nodes, required this.depth, required this.score});

  /// How the move was chosen: "five", "block", "vcf", "vct", "search", "random"…
  final String how;

  /// Positions visited (search and solvers).
  final int nodes;

  /// The search depth reached (0 if there was no search).
  final int depth;

  /// The search score for the bot (0 if there was no search).
  final int score;
}

/// A computer player. Deterministic for a given [seed] (with no time
/// limit), so tests and replays repeat exactly.
class GomokuBot {
  /// A bot at [level]. [maxTime] caps each move's thinking time (the node
  /// budgets usually stop it first on a desktop; on a slow phone or in the
  /// browser the cap keeps it responsive).
  GomokuBot(this.level, {int seed = 0, this.maxTime}) : _rng = Random(seed);

  /// How strong it plays.
  final BotLevel level;

  /// The longest it may think about one move, or null for no limit.
  final Duration? maxTime;

  final Random _rng;

  /// What the last [chooseMove] did.
  BotStats? lastStats;

  /// The bot's move in [view] (whose game must not be over).
  GomokuMove chooseMove(GomokuView view) {
    final game = view.game;
    if (game.isOver) throw StateError('The game is over');
    if (game.mustPass) {
      lastStats = const BotStats(how: 'pass', nodes: 0, depth: 0, score: 0);
      return GomokuMove.pass;
    }
    final size = game.rules.size;
    final board = Board.fromMoves(game.rules, [for (final m in game.moves) m.index(size)]);
    return GomokuMove.fromIndex(_choose(board), size);
  }

  int _choose(Board board) {
    final me = board.side, opp = 3 - me;
    if (board.moveCount == 0) {
      lastStats = const BotStats(how: 'center', nodes: 0, depth: 0, score: 0);
      return board.center;
    }
    final five = board.firstFivePoint(me);
    if (five >= 0) {
      lastStats = const BotStats(how: 'five', nodes: 0, depth: 0, score: Searcher.win);
      return five;
    }
    if (board.count(opp, Combo.five) > 0) {
      final blocks = <int>[];
      board.fivePoints(opp, blocks);
      final legal = blocks.where(board.isLegal).toList();
      if (legal.isNotEmpty) {
        lastStats = const BotStats(how: 'block', nodes: 0, depth: 0, score: 0);
        return legal.first;
      }
    }
    switch (level) {
      case BotLevel.easy:
        return _easy(board);
      case BotLevel.medium:
        return _medium(board);
      case BotLevel.hard:
        return _hard(board);
    }
  }

  int _easy(Board board) {
    final searcher = Searcher(board, ttBits: 12, width: const SearchWidth(root: 10, first: 6, min: 4));
    // Now and then it plays on instinct: one of the best-looking points,
    // without checking what the opponent threatens.
    if (_rng.nextDouble() < 0.3) {
      final instinct = searcher.instinctMoves(4);
      if (instinct.isNotEmpty) {
        final pick = instinct[_rng.nextInt(instinct.length)];
        lastStats = const BotStats(how: 'random', nodes: 0, depth: 0, score: 0);
        return pick;
      }
    }
    final result =
        searcher.search(SearchLimits(maxDepth: 2, maxNodes: 4000, maxTime: maxTime), exactRoots: 99);
    final good = [
      for (final e in result.rootScores.entries)
        if (e.value >= result.score - 120) e.key,
    ]..sort();
    final pick = good.isEmpty ? result.move : good[_rng.nextInt(good.length)];
    lastStats = BotStats(how: 'search', nodes: result.nodes, depth: result.depth, score: result.score);
    return pick;
  }

  int _medium(Board board) {
    final solver = ThreatSolver(board);
    final vcf = solver.vcf(maxNodes: 5000);
    if (vcf != null) {
      lastStats = BotStats(how: 'vcf', nodes: solver.nodes, depth: 0, score: Searcher.win);
      return vcf.line.first;
    }
    final searcher = Searcher(board, ttBits: 16, width: const SearchWidth(root: 16, first: 10, min: 5));
    final result = searcher.search(SearchLimits(maxDepth: 4, maxNodes: 8000, maxTime: maxTime));
    lastStats = BotStats(how: 'search', nodes: result.nodes + solver.nodes, depth: result.depth, score: result.score);
    return result.move;
  }

  int _hard(Board board) {
    final solver = ThreatSolver(board);
    final win = solver.vcf(maxNodes: 20000) ?? solver.vct(maxNodes: 40000);
    if (win != null) {
      lastStats = BotStats(how: win.foursOnly ? 'vcf' : 'vct', nodes: solver.nodes, depth: 0, score: Searcher.win);
      return win.line.first;
    }
    // What would the opponent do with a free move? If it has no forced win
    // even then, no move of ours can give it one (in Freestyle a stone of
    // ours never helps the opponent), and the search's choice is safe. Under
    // the other rules it can (an overline, a forbidden point), so we check
    // anyway.
    final threat = _threatIfWePass(board);
    final searcher = Searcher(board, ttBits: 18, width: const SearchWidth(root: 20, first: 12, min: 6));
    final result = searcher.search(SearchLimits(maxNodes: 150000, maxTime: maxTime));
    var pick = result.move;
    if (threat != null || board.rules.winRule != WinRule.freestyle) {
      // Check our best moves, then the points of the opponent's plan, for
      // one that leaves it no forced win.
      final ranked = result.rootScores.keys.toList()
        ..sort((a, b) {
          final c = result.rootScores[b]!.compareTo(result.rootScores[a]!);
          return c != 0 ? c : a.compareTo(b);
        });
      final tries = <int>[
        ...ranked.take(6),
        if (threat != null)
          for (final c in threat.line)
            if (board.isLegal(c)) c,
        ...ranked.skip(6),
      ];
      final seen = <int>{};
      for (final m in tries) {
        if (!seen.add(m) || seen.length > 14) continue;
        if (!_givesForcedWin(board, solver, m)) {
          pick = m;
          break;
        }
      }
    }
    lastStats = BotStats(how: 'search', nodes: result.nodes + solver.nodes, depth: result.depth, score: result.score);
    return pick;
  }

  // The opponent's forced win if it could move now, or null. A fresh
  // solver: its memory of positions assumes the usual side to move.
  ThreatProof? _threatIfWePass(Board board) {
    board.side = 3 - board.side;
    final probe = ThreatSolver(board);
    final threat = probe.vcf(maxNodes: 10000) ?? probe.vct(maxNodes: 30000);
    board.side = 3 - board.side;
    return threat;
  }

  // Whether the opponent has a proven forced win after we play m.
  bool _givesForcedWin(Board board, ThreatSolver solver, int m) {
    board.play(m);
    final lost = solver.vcf(maxNodes: 5000) != null || solver.vct(maxNodes: 15000) != null;
    board.undo();
    return lost;
  }
}
