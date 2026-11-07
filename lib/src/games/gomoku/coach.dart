/// The coach: ranks the moves for the side to move, says which wins and
/// losses are proven, gives short reasons, and grades the move played.
///
/// Gomoku hides nothing, so the coach's label is "Best move" (not "GTO",
/// which is about hidden cards). It is honest about certainty: "Sure win
/// (wins in N)" and "Loses in N" come only from the threat solver's proofs;
/// everything else is the search's estimate, shown as a win chance.
library;

import 'dart:math';

import 'board.dart';
import 'game.dart';
import 'patterns.dart';
import 'rules.dart';
import 'search.dart';
import 'threats.dart';

/// A short, machine-readable reason for a move, which the app turns into a
/// one-line explanation in the player's language.
enum MoveReason {
  /// Makes five in a row: wins.
  makesFive,

  /// Makes an open four, which can't be stopped.
  makesOpenFour,

  /// Makes two fours at once, which can't both be stopped.
  makesDoubleFour,

  /// Makes a four and an open three at once (4-3).
  makesFourThree,

  /// Makes a four: the opponent must block it.
  makesFour,

  /// Makes two open threes at once (3-3).
  makesDoubleThree,

  /// Makes an open three: the opponent must answer it.
  makesOpenThree,

  /// Blocks the opponent's four (which would have made five).
  blocksFour,

  /// Stops the opponent's open three (or double-four point).
  blocksOpenThree,

  /// Takes the point where the opponent would make a four-three.
  blocksFourThree,

  /// Takes the point where the opponent would make a double three.
  blocksDoubleThree,

  /// The first move of a proven forced win.
  startsForcedWin,

  /// There was a proven forced win, and this move doesn't play it: no win
  /// after it could be proven. Every candidate is checked for a win when
  /// one is on the board, so a threat that keeps the win, or a quiet move
  /// against a ready open four, is proven and never gets this reason. A
  /// quiet move otherwise gives the opponent a free move to defend with,
  /// and the solvers can't prove what happens then; the move may in rare
  /// cases still win by a slower plan, so its grade goes by the estimate
  /// (see [GomokuAnalysis.grade]).
  missesForcedWin,

  /// After this move the opponent has a proven forced win (and a better
  /// move would have avoided that).
  allowsForcedWin,

  /// Leaves the opponent's four on the board: it makes five next.
  ignoresFour,

  /// Leaves the opponent's open three alone without making a four.
  ignoresOpenThree,

  /// Renju: every empty point is forbidden to Black, so Black must pass.
  mustPass,
}

/// How good the move played was, compared with the coach's best.
enum MoveGrade {
  /// The best move, or as good as it (any move that keeps a proven win).
  best,

  /// Nearly as good.
  good,

  /// A small loss of winning chances.
  inaccuracy,

  /// A clear loss of winning chances.
  mistake,

  /// Allows a proven loss that a better move avoids, or loses a lot of
  /// winning chances (by the estimate).
  blunder,
}

/// The coach's view of one candidate move.
class MoveAnalysis {
  /// See the fields.
  const MoveAnalysis({
    required this.move,
    required this.winChance,
    required this.score,
    required this.reasons,
    required this.line,
    this.winsIn,
    this.losesIn,
  });

  /// The move.
  final GomokuMove move;

  /// Proven: with this move, the mover makes five within this many of its
  /// own moves (this one included), whatever the opponent does. Null when
  /// no such proof was found.
  final int? winsIn;

  /// Proven: after this move, the opponent makes five within this many of
  /// its own moves, whatever the mover does. Null when no such proof was
  /// found.
  final int? losesIn;

  /// The mover's chance of winning after this move, 0–1: 1 or 0 when
  /// proven, otherwise an estimate from the search.
  final double winChance;

  /// The search's score for the mover (positive is good); the basis of
  /// [winChance] when nothing is proven.
  final int score;

  /// Why the move is good or bad, most important first.
  final List<MoveReason> reasons;

  /// The forcing line when a win or loss is proven, otherwise the expected
  /// line, starting with [move].
  final List<GomokuMove> line;

  /// Whether a forced win is proven.
  bool get isProvenWin => winsIn != null;

  /// Whether a forced loss is proven.
  bool get isProvenLoss => losesIn != null;

  /// For sending between devices or workers.
  Map<String, Object?> toJson() => {
        'move': move.notation,
        'winsIn': winsIn,
        'losesIn': losesIn,
        'winChance': winChance,
        'score': score,
        'reasons': [for (final r in reasons) r.name],
        'line': [for (final m in line) m.notation].join(' '),
      };

  /// The analysis [toJson] wrote.
  static MoveAnalysis fromJson(Map<String, Object?> json) => MoveAnalysis(
        move: GomokuMove.parse(json['move'] as String),
        winsIn: json['winsIn'] as int?,
        losesIn: json['losesIn'] as int?,
        winChance: (json['winChance'] as num).toDouble(),
        score: json['score'] as int,
        reasons: [
          for (final r in json['reasons'] as List) MoveReason.values.byName(r as String),
        ],
        line: GomokuGame.parseMoves(json['line'] as String),
      );
}

/// The coach's answer for one position.
class GomokuAnalysis {
  /// See the fields.
  const GomokuAnalysis({
    required this.toMove,
    required this.moves,
    required this.depth,
    required this.nodes,
    required this.elapsed,
    this.winsIn,
    this.losesIn,
  });

  /// The color the analysis is for.
  final Stone toMove;

  /// The candidate moves, best first.
  final List<MoveAnalysis> moves;

  /// Proven: the side to move can force five within this many moves.
  final int? winsIn;

  /// Proven: whatever the side to move does (among the moves analysed),
  /// the opponent forces five within this many of its moves.
  final int? losesIn;

  /// The search depth reached.
  final int depth;

  /// Positions visited (search and solvers).
  final int nodes;

  /// Time taken.
  final Duration elapsed;

  /// The best move's analysis (null only when the game is over).
  MoveAnalysis? get best => moves.isEmpty ? null : moves.first;

  /// The analysis of [move], or null if it wasn't analysed.
  MoveAnalysis? of(GomokuMove move) => moves.where((m) => m.move == move).firstOrNull;

  /// How good [played] was. A move that wasn't analysed counts as a little
  /// worse than the worst one analysed (analyse it with
  /// `GomokuCoach.analyze(view, include: played)` for an exact grade).
  ///
  /// Proofs decide first: any move that keeps a proven win is Best, and
  /// allowing a proven loss that a better move avoids is a Blunder.
  /// Everything else is graded by how much of the best move's win chance
  /// it gives up, by the estimate. Giving up a proven win
  /// ([MoveReason.missesForcedWin]) for a position that is not proven lost
  /// is graded the same way, but never better than an Inaccuracy: the
  /// solvers can't prove the move loses the win, and the search still
  /// rates it, so it is not called a Blunder unless the estimate drops a
  /// lot (as chess sites grade a lost forced mate by the evaluation left).
  MoveGrade grade(GomokuMove played) {
    final top = best;
    if (top == null) return MoveGrade.best;
    final a = of(played);
    if (a == null) {
      final worst = moves.last.winChance;
      return _byLoss(top.winChance - max(0, worst - 0.05));
    }
    if (a.move == top.move) return MoveGrade.best;
    if (a.isProvenWin) return MoveGrade.best;
    if (a.reasons.contains(MoveReason.missesForcedWin) && !a.isProvenLoss) {
      final byEstimate = _byLoss(top.winChance - a.winChance);
      return byEstimate.index < MoveGrade.inaccuracy.index ? MoveGrade.inaccuracy : byEstimate;
    }
    if (a.isProvenLoss) {
      if (!top.isProvenLoss) return MoveGrade.blunder;
      // Everything loses: holding out longer is better.
      final shorter = top.losesIn! - a.losesIn!;
      return shorter <= 0 ? MoveGrade.best : (shorter <= 2 ? MoveGrade.good : MoveGrade.inaccuracy);
    }
    return _byLoss(top.winChance - a.winChance);
  }

  static MoveGrade _byLoss(double loss) {
    if (loss <= 0.02) return MoveGrade.best;
    if (loss <= 0.07) return MoveGrade.good;
    if (loss <= 0.15) return MoveGrade.inaccuracy;
    if (loss <= 0.30) return MoveGrade.mistake;
    return MoveGrade.blunder;
  }

  /// For sending between devices or workers.
  Map<String, Object?> toJson() => {
        'toMove': toMove.name,
        'moves': [for (final m in moves) m.toJson()],
        'winsIn': winsIn,
        'losesIn': losesIn,
        'depth': depth,
        'nodes': nodes,
        'micros': elapsed.inMicroseconds,
      };

  /// The analysis [toJson] wrote. Without 'micros' (a background job's
  /// output leaves the time out, so the same position always gives the
  /// same output) [elapsed] is zero.
  static GomokuAnalysis fromJson(Map<String, Object?> json) => GomokuAnalysis(
        toMove: Stone.values.byName(json['toMove'] as String),
        moves: [
          for (final m in json['moves'] as List) MoveAnalysis.fromJson((m as Map).cast<String, Object?>()),
        ],
        winsIn: json['winsIn'] as int?,
        losesIn: json['losesIn'] as int?,
        depth: json['depth'] as int,
        nodes: json['nodes'] as int,
        elapsed: Duration(microseconds: json['micros'] as int? ?? 0),
      );
}

/// How much work the coach may do for one position. The node limits make
/// the answer the same every time; [maxTime] is a safety cap for slow
/// devices, covering every step of the analysis (when it is reached the
/// answer is shallower and may differ from one device to another).
///
/// The default is sized so the cap is not reached in practice, under every
/// rule and in the browser: on a desktop PC it takes under 0.15 s on
/// average and about 0.3 s at worst natively, for Freestyle, Standard and
/// Renju on either board, and roughly twice that as JavaScript or
/// WebAssembly (see tool/games/gomoku_bench.dart).
class CoachBudget {
  /// See the fields.
  const CoachBudget({
    this.searchNodes = 40000,
    this.proofNodes = 12000,
    this.checkNodes = 2000,
    this.checkPool = 14000,
    this.topN = 8,
    this.maxTime = const Duration(milliseconds: 900),
  });

  /// A quick look, for hints while playing fast.
  static const quick = CoachBudget(searchNodes: 15000, proofNodes: 6000, checkNodes: 1000, checkPool: 5000, topN: 5);

  /// "Think longer".
  static const deep = CoachBudget(
      searchNodes: 400000,
      proofNodes: 200000,
      checkNodes: 15000,
      checkPool: 150000,
      topN: 12,
      maxTime: Duration(seconds: 6));

  /// Positions the search may visit.
  final int searchNodes;

  /// Positions the solvers may visit proving a win from the position (and
  /// as many again looking for the opponent's threats).
  final int proofNodes;

  /// Positions the solvers may visit checking one candidate move (for a
  /// win after it, or a loss).
  final int checkNodes;

  /// Positions the solvers may visit checking all the candidates together.
  /// The move asked about is checked first, then the best-looking ones;
  /// once the pool is spent the rest keep their estimates.
  final int checkPool;

  /// How many moves to analyse (plus the one asked about, if any).
  final int topN;

  /// The longest the whole analysis may take.
  final Duration maxTime;

  /// The same budget with another time cap (a background job passes what is
  /// left of its own cap, or a day when it has none).
  CoachBudget withTime(Duration maxTime) => CoachBudget(
        searchNodes: searchNodes,
        proofNodes: proofNodes,
        checkNodes: checkNodes,
        checkPool: checkPool,
        topN: topN,
        maxTime: maxTime,
      );
}

/// The coach. Stateless apart from its budget: create one and call
/// [analyze] as often as needed.
class GomokuCoach {
  /// A coach with [budget].
  const GomokuCoach({this.budget = const CoachBudget()});

  /// How much work each analysis may do.
  final CoachBudget budget;

  /// The win chance for a search score: a logistic curve, so an open three
  /// ahead (about 700) is roughly 75% and a sure-looking attack near 95%.
  static double winChanceOf(int score) {
    if (score >= Searcher.winBound) return 0.97;
    if (score <= -Searcher.winBound) return 0.03;
    final p = 1 / (1 + exp(-score / 600));
    return p.clamp(0.04, 0.96);
  }

  /// Analyses the position in [view] for the side to move. [include] makes
  /// sure that move is analysed too (to grade a move just played).
  GomokuAnalysis analyze(GomokuView view, {GomokuMove? include}) {
    final game = view.game;
    final clock = Stopwatch()..start();
    if (game.isOver) {
      return GomokuAnalysis(toMove: game.toMove, moves: const [], depth: 0, nodes: 0, elapsed: Duration.zero);
    }
    final size = game.rules.size;
    final board = Board.fromMoves(game.rules, [for (final m in game.moves) m.index(size)]);
    final me = board.side, opp = 3 - me;
    if (game.mustPass) {
      final score = board.evaluate();
      return GomokuAnalysis(
        toMove: game.toMove,
        moves: [
          MoveAnalysis(
            move: GomokuMove.pass,
            winChance: winChanceOf(score),
            score: score,
            reasons: const [MoveReason.mustPass],
            line: const [GomokuMove.pass],
          ),
        ],
        depth: 0,
        nodes: 0,
        elapsed: clock.elapsed,
      );
    }
    // Every step stops at the safety cap.
    final solver = ThreatSolver(board)..stopAt(clock, budget.maxTime);
    final searcher = Searcher(board, width: const SearchWidth(root: 30, first: 12, min: 6));

    // Can the side to move force a win?
    final posWin = solver.vcf(maxNodes: budget.proofNodes ~/ 3) ?? solver.vct(maxNodes: budget.proofNodes);

    // The candidates: what the search would consider, plus the proof's
    // first move and the move asked about.
    final includeCell = include != null && game.isLegal(include) ? include.index(size) : -1;
    // And what could the opponent force with a free move? Without such a
    // threat no move can lose by force (in Freestyle an extra stone of ours
    // never helps the opponent), so the per-move loss checks are skipped.
    final threat = posWin == null ? _threatIfWePass(board, budget.proofNodes, clock, budget.maxTime) : null;
    final checkLosses = threat != null || game.rules.winRule != WinRule.freestyle;
    final candidates = searcher.rootMoves();
    if (posWin != null && !candidates.contains(posWin.line.first)) candidates.insert(0, posWin.line.first);
    if (threat != null && board.count(opp, Combo.five) == 0 && !board.hasWinIn2(opp)) {
      // The points of the opponent's plan are the natural defenses.
      for (var i = 0; i < threat.line.length; i += 2) {
        final c = threat.line[i];
        if (board.isLegal(c) && !candidates.contains(c)) candidates.add(c);
      }
    }
    if (includeCell >= 0 && !candidates.contains(includeCell)) candidates.add(includeCell);

    // The search gets what is left of 60% of the time, but at least 10%.
    final searchTime = budget.maxTime * 0.6 - clock.elapsed;
    final floor = budget.maxTime * 0.1;
    final result = searcher.search(SearchLimits(maxNodes: budget.searchNodes, maxTime: searchTime < floor ? floor : searchTime),
        rootMoves: candidates, exactRoots: budget.topN);
    final scores = Map.of(result.rootScores);
    int scoreOf(int m) => scores[m] ?? _quickScore(board, m);

    final ranked = [...candidates]
      ..sort((a, b) {
        final c = scoreOf(b).compareTo(scoreOf(a));
        return c != 0 ? c : a.compareTo(b);
      });
    final chosen = ranked.take(budget.topN).toList();
    if (posWin != null && !chosen.contains(posWin.line.first)) chosen.insert(0, posWin.line.first);
    if (includeCell >= 0 && !chosen.contains(includeCell)) {
      // Below the top few the search only knows a bound: score it exactly.
      chosen.add(includeCell);
      final own = searcher.search(
        SearchLimits(maxDepth: max(1, result.depth), maxNodes: budget.searchNodes ~/ 4, maxTime: budget.maxTime * 0.1),
        rootMoves: [includeCell],
        stopEarly: false,
      );
      if (own.depth > 0) scores[includeCell] = own.score;
    }

    // What the opponent threatens before our move.
    final oppFives = <int>[];
    board.fivePoints(opp, oppFives);
    final oppThree = board.hasWinIn2(opp);

    // The move asked about is checked first, so it gets its share of the
    // pool; the order of the list shown is decided below.
    final order = [if (includeCell >= 0) includeCell, ...chosen.where((c) => c != includeCell)];
    final poolEnd = solver.nodes + budget.checkPool;
    // Nodes for one check: what is left of the pool, up to checkNodes; zero
    // (skip the check) once the pool or the time is spent.
    int allowance() {
      final left = min(budget.checkNodes, poolEnd - solver.nodes);
      return left < 100 || clock.elapsed >= budget.maxTime ? 0 : left;
    }

    final analyses = <_Draft>[];
    for (final m in order) {
      final d = _Draft(m, scoreOf(m));
      final myCombo = board.combo(me, m);
      // Proofs. With a forced win on the board every move is checked, quiet
      // ones too (a quiet move against a ready open four still wins, and
      // the solver settles that at once); otherwise only threats can be
      // proven wins.
      if (myCombo == Combo.five) {
        d.winsIn = 1;
        d.line = [m];
      } else if (posWin != null && m == posWin.line.first) {
        d.winsIn = posWin.movesToWin;
        d.line = posWin.line;
      } else if ((myCombo >= Combo.threatening || posWin != null) && allowance() > 0) {
        final p = solver.winAfter(m, maxNodes: allowance());
        if (p != null) {
          d.winsIn = p.movesToWin;
          d.line = p.line;
        }
      }
      board.play(m);
      if (d.winsIn == null) {
        if (board.count(opp, Combo.five) > 0) {
          d.losesIn = 1;
          d.line = [m, board.firstFivePoint(opp)];
        } else if (board.count(me, Combo.five) == 0 && board.hasWinIn2(opp)) {
          final p = solver.vcf(maxNodes: 50);
          d.losesIn = p?.movesToWin ?? 2;
          if (p != null) d.line = [m, ...p.line];
        } else if (checkLosses && allowance() > 0) {
          final p = solver.vcf(maxNodes: allowance() ~/ 3) ?? solver.vct(maxNodes: allowance());
          if (p != null) {
            d.losesIn = p.movesToWin;
            d.line = [m, ...p.line];
          }
        }
      }
      final stillThree = board.hasWinIn2(opp);
      board.undo();
      d.line ??= searcher.principalVariation(m);

      // Reasons, from the shapes before the move.
      final r = d.reasons;
      switch (myCombo) {
        case Combo.five:
          r.add(MoveReason.makesFive);
        case Combo.winIn2:
          r.add(_hasLine(board, me, m, Line.flex4) ? MoveReason.makesOpenFour : MoveReason.makesDoubleFour);
        case Combo.fourThree:
          r.add(MoveReason.makesFourThree);
        case Combo.four:
          r.add(MoveReason.makesFour);
        case Combo.doubleThree:
          r.add(MoveReason.makesDoubleThree);
        case Combo.flex3:
        case Combo.flex3Plus:
          if (_hasLine(board, me, m, Line.flex3)) r.add(MoveReason.makesOpenThree);
      }
      final oppCombo = board.combo(opp, m);
      if (oppFives.contains(m)) {
        r.add(MoveReason.blocksFour);
      } else if (oppFives.isNotEmpty && myCombo != Combo.five) {
        r.add(MoveReason.ignoresFour);
      } else if (oppThree && !stillThree) {
        r.add(MoveReason.blocksOpenThree);
      } else if (oppThree && myCombo < Combo.four) {
        r.add(MoveReason.ignoresOpenThree);
      } else if (oppCombo == Combo.fourThree) {
        r.add(MoveReason.blocksFourThree);
      } else if (oppCombo == Combo.doubleThree) {
        r.add(MoveReason.blocksDoubleThree);
      }
      if (d.winsIn != null && myCombo != Combo.five) r.insert(0, MoveReason.startsForcedWin);
      // Not proven to keep the win (see MoveReason.missesForcedWin for
      // what that does and doesn't claim).
      if (posWin != null && d.winsIn == null) r.insert(0, MoveReason.missesForcedWin);
      analyses.add(d);
    }

    final everyMoveLoses = analyses.every((d) => d.losesIn != null);
    if (!everyMoveLoses) {
      for (final d in analyses) {
        if (d.losesIn != null) d.reasons.insert(0, MoveReason.allowsForcedWin);
      }
    }
    analyses.sort((a, b) {
      final c = b.rank.compareTo(a.rank);
      return c != 0 ? c : a.cell.compareTo(b.cell);
    });
    clock.stop();
    GomokuMove mv(int c) => GomokuMove.fromIndex(c, size);
    return GomokuAnalysis(
      toMove: Stone.fromCode(me),
      moves: [
        for (final d in analyses)
          MoveAnalysis(
            move: mv(d.cell),
            winsIn: d.winsIn,
            losesIn: d.losesIn,
            winChance: d.winsIn != null ? 1 : (d.losesIn != null ? 0 : winChanceOf(d.score)),
            score: d.score,
            reasons: List.unmodifiable(d.reasons),
            line: [for (final c in d.line!) mv(c)],
          ),
      ],
      winsIn: posWin?.movesToWin ?? (analyses.isNotEmpty ? analyses.first.winsIn : null),
      losesIn: everyMoveLoses && analyses.isNotEmpty ? analyses.map((d) => d.losesIn!).reduce(max) : null,
      depth: result.depth,
      nodes: result.nodes + solver.nodes,
      elapsed: clock.elapsed,
    );
  }

  /// Analyses [view] including [played] and grades it: the one call the
  /// app needs after each move.
  MoveGrade grade(GomokuView view, GomokuMove played) => analyze(view, include: played).grade(played);

  // The opponent's forced win if it could move now, or null. A fresh
  // solver: its memory of positions assumes the usual side to move.
  static ThreatProof? _threatIfWePass(Board board, int nodes, Stopwatch clock, Duration maxTime) {
    board.side = 3 - board.side;
    final probe = ThreatSolver(board)..stopAt(clock, maxTime);
    final threat = probe.vcf(maxNodes: nodes ~/ 3) ?? probe.vct(maxNodes: nodes);
    board.side = 3 - board.side;
    return threat;
  }

  // A score for a move the search didn't reach: the position after it,
  // statically, for the mover.
  static int _quickScore(Board board, int m) {
    board.play(m);
    final s = -board.evaluate();
    board.undo();
    return s;
  }

  static bool _hasLine(Board board, int color, int cell, int shape) {
    for (var d = 0; d < 4; d++) {
      if (board.pattern(color, cell, d) == shape) return true;
    }
    return false;
  }
}

class _Draft {
  _Draft(this.cell, this.score);
  final int cell;
  final int score;
  int? winsIn;
  int? losesIn;
  List<int>? line;
  final reasons = <MoveReason>[];

  // Proven wins first (shorter first), then estimates, then proven losses
  // (longer first).
  int get rank {
    if (winsIn != null) return 1000000 - winsIn!;
    if (losesIn != null) return -1000000 + losesIn!;
    return score.clamp(-Searcher.win, Searcher.win);
  }
}
