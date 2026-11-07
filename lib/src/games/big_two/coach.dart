/// The coach: rates every legal move from one player's view by solving
/// many guessed deals, the way the poker solver averages over hidden cards.
///
/// Method (information-set Monte Carlo):
/// 1. Guess the hidden hands: deal the cards the player can't see to the
///    other seats at random, in ways that fit everything public
///    ([DealSampler]). By default a pool of guesses is first weighed by how
///    well each explains the opponents' moves so far ([InferenceModel]).
/// 2. Play each guessed deal out to the end. With the default [CoachBudget]
///    the player's own later moves are chosen by a small search tree that
///    is shared by all guesses (open-loop information-set Monte Carlo tree
///    search, after Cowling, Powley and Whitehouse 2012); everyone else
///    plays the fast [HeuristicPolicy]. Once few cards remain, the
///    player's endgame is solved exactly on that guess ([EndgameSolver]).
///    The light budget instead plays every candidate out on the same guesses
///    and drops weak ones in rounds (successive halving).
/// 3. Average the win rate and points per candidate. For the coach panel
///    the tree search is followed by a fair comparison: every candidate is
///    played out on the same guessed deals ([CoachBudget.compareShare]), and
///    the numbers come from that, with the standard error of each move's
///    gap to the pick ([BigTwoCandidate.pointsError]) so the app can tell a
///    real gap from chance.
///
/// Before sampling, small endgames are also checked against opponents who
/// might hold any unseen cards. A win proven there holds whatever the real
/// hands are, and the candidate is marked [BigTwoCandidate.sureWin].
///
/// Big Two has four players, so no strategy is provably unbeatable: the app
/// labels this coach's pick "GTO" as the user asked, meaning "the best
/// move the solver found", not a Nash equilibrium.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'cards.dart';
import 'plan.dart';
import 'plays.dart';
import 'policy.dart';
import 'inference.dart';
import 'random.dart';
import 'sampler.dart';
import 'solver.dart';
import 'state.dart';

/// How much work the coach may do for one decision.
class CoachBudget {
  /// A budget of [playouts] played-out deals (summed over all candidates),
  /// stopping early after [maxMillis] if given. Counting play-outs rather
  /// than time keeps answers identical for the same seed.
  const CoachBudget({
    this.playouts = 3000,
    this.maxMillis,
    this.exactEndgame = true,
    this.endgameNodes = 60000,
    this.proofNodes = 30000,
    this.tree = true,
    this.exploration = 1.0,
    this.inferencePool = 300,
    this.compareShare = 0,
  });

  /// The app's default for the coach panel and the Hard bot: on a desktop
  /// PC about 0.1 s per decision on average natively (at most about 0.3 s)
  /// and two to three times that in the browser's JavaScript build (at
  /// most about 0.6 s), for 2, 3 or 4 players (see
  /// tool/games/big_two_match.dart --coach-timing).
  static const standard = CoachBudget();

  /// A light budget, for hints and the Medium bot.
  static const quick =
      CoachBudget(playouts: 300, exactEndgame: false, proofNodes: 4000, tree: false, inferencePool: 0);

  /// The coach panel's budget: [standard] with a third of its play-outs
  /// spent comparing every move on shared deals ([compareShare]), so the
  /// points it shows and grades by are fair between moves.
  static const coach = CoachBudget(compareShare: 1 / 3);

  /// This budget with [playouts] or [compareShare] changed, or its time cap
  /// ([maxMillis] gives the new cap: null, no cap).
  CoachBudget copyWith({int? playouts, int? Function()? maxMillis, double? compareShare}) => CoachBudget(
        playouts: playouts ?? this.playouts,
        maxMillis: maxMillis == null ? this.maxMillis : maxMillis(),
        exactEndgame: exactEndgame,
        endgameNodes: endgameNodes,
        proofNodes: proofNodes,
        tree: tree,
        exploration: exploration,
        inferencePool: inferencePool,
        compareShare: compareShare ?? this.compareShare,
      );

  /// Deals played out in total, over all candidates, when every hand holds
  /// 13 cards or fewer. See [playoutsFor] for bigger hands.
  final int playouts;

  /// The play-outs for one decision: [playouts], cut to 200 for a forced
  /// move, and scaled down by (13 / biggest hand)³ when a hand holds more
  /// than 13 cards. Bigger hands make every play-out longer and give far
  /// more combinations to consider at each turn, so without this a
  /// three-player decision (17 or 18 cards) took over a second in the
  /// browser. It depends only on public counts, so answers stay
  /// reproducible.
  int playoutsFor(List<int> counts, int candidates) {
    var biggest = 0;
    for (final c in counts) {
      if (c > biggest) biggest = c;
    }
    var p = candidates == 1 ? math.min(playouts, 200) : playouts;
    if (biggest > 13) p = math.max(1, (p * 2197 / (biggest * biggest * biggest)).round());
    return p;
  }

  /// Optional wall-clock cap in milliseconds.
  final int? maxMillis;

  /// Solve the player's own endgame exactly inside play-outs.
  final bool exactEndgame;

  /// Most positions the [exactEndgame] solves may visit in one decision,
  /// over all play-outs; after that the play-outs use the policy. Small
  /// endgames reached in thousands of play-outs were the slowest part of a
  /// decision (over a second in the browser for some three-player
  /// endgames). Counting positions rather than time keeps answers
  /// reproducible.
  final int endgameNodes;

  /// Node budget for the "can't be beaten" proofs, over all candidates.
  final int proofNodes;

  /// Search a tree of the player's own later moves (information-set Monte
  /// Carlo tree search) instead of rating each move by plain play-outs.
  final bool tree;

  /// How much the tree search explores (the UCB constant).
  final double exploration;

  /// When above 0, draw this many guesses up front, weigh each by how well
  /// it explains the opponents' moves ([InferenceModel]), and sample from
  /// that pool by weight.
  final int inferencePool;

  /// With the [tree] search: the share of the play-outs (0 to 1) spent after
  /// it on a fair comparison of every move. The tree is good at finding the
  /// best move, but its points are not fair between moves: a move it visits
  /// often is played on by its learned later moves, one it gave up on by the
  /// fast policy, and how well the tree learns differs from seed to seed (in
  /// review the same move's points moved by up to 6 between seeds, while
  /// each seed's own sampling error said 0.4). The comparison plays every
  /// move on the same guessed deals with the same later play, so the gap
  /// between two moves is the moves' own; the candidates' points, win
  /// chances and errors then come from it. The successive halving search
  /// (tree off) compares this way already and ignores this. 0: no
  /// comparison (the Hard bot needs only the pick).
  final double compareShare;
}

/// Short, machine-readable reasons the app turns into one-line
/// explanations. Each one is a plain fact about the move.
enum CoachReason {
  /// Plays your last cards: you win the deal.
  goesOut,

  /// Proven: whatever the others hold, you go out first.
  sureWin,

  /// No cards you can't see could beat this play, so you'll lead next.
  cantBeBeaten,

  /// Clears five cards in one play.
  shedsFive,

  /// Gets rid of your lowest card.
  shedsLowest,

  /// Keeps your 2s for later (a play using a 2 was possible).
  keepsTwo,

  /// Spends a 2.
  usesTwo,

  /// Splits a pair.
  breaksPair,

  /// Splits a triple.
  breaksTriple,

  /// Splits a four of a kind.
  breaksFour,

  /// One play of your fewest-plays plan: the rest of your hand still
  /// needs one play fewer.
  followsPlan,

  /// Leaves your hand needing as many plays as before, or more.
  addsPlays,

  /// The next player has one card left and this stops them (a multi-card
  /// play, or your highest single).
  blocksLastCard,

  /// The next player has one card left and this single may let them out.
  lastCardDanger,

  /// Passing keeps your hand together: every play would split a group or
  /// spend a 2.
  passKeepsHand,

  /// Someone has two cards or fewer left.
  opponentNearlyOut,
}

/// The coach's rating of one move.
class BigTwoCandidate {
  /// A rated move.
  const BigTwoCandidate({
    required this.play,
    required this.winChance,
    required this.expectedPoints,
    required this.samples,
    required this.sureWin,
    required this.reasons,
    required this.pointsLost,
    this.pointsError = 0,
    this.eliminatedAt,
  });

  /// The move ([Play.pass] for passing).
  final Play play;

  /// Chance of going out first, 0 to 1.
  final double winChance;

  /// Average points won or lost this deal (see [BigTwoResult.scores]).
  final double expectedPoints;

  /// Played-out deals behind these numbers. Moves dropped early have few.
  final int samples;

  /// Proven to win against any hidden cards.
  final bool sureWin;

  /// Why, in short facts (see [CoachReason]).
  final List<CoachReason> reasons;

  /// Expected points given up compared with the best move (0 for the best).
  final double pointsLost;

  /// The standard error of the gap between this move's [expectedPoints]
  /// and the pick's: how much of that gap may be chance. Measured on the
  /// deals both moves were played on (the moves are compared on the same
  /// guessed deals), so the luck of the deal cancels out; 0 for the pick. A
  /// gap smaller than about twice this can't be told from noise, so the
  /// app grades a move by what is left of its gap beyond that.
  final double pointsError;

  /// When the search stopped looking at this move, or null if it kept it to
  /// the end. With successive halving ([CoachBudget.tree] off) it is the
  /// round that dropped the move (0 = the first). In the tree search it is 0
  /// for a move the search visited less than a quarter as often as its most
  /// visited move: it gave up on it early. Either way its numbers rest on
  /// few play-outs, so its [pointsLost] (floored at 0) can look better than
  /// the move is; the app grades such a move at best Good.
  final int? eliminatedAt;

  /// True when the search dropped this move early (see [eliminatedAt]).
  bool get droppedEarly => eliminatedAt != null;

  @override
  String toString() => '$play  win ${(winChance * 100).toStringAsFixed(1)}%  '
      'pts ${expectedPoints.toStringAsFixed(2)}±${pointsError.toStringAsFixed(2)}  '
      'n=$samples${sureWin ? '  SURE' : ''}'
      '${droppedEarly ? '  out@$eliminatedAt' : ''}  ${reasons.map((r) => r.name).join(',')}';
}

/// The coach's answer for one decision.
class BigTwoAnalysis {
  /// An answer.
  const BigTwoAnalysis({
    required this.candidates,
    required this.playouts,
    required this.deals,
    required this.elapsedMicros,
    required this.plan,
  });

  /// Every legal move (or the top N asked for), best first.
  final List<BigTwoCandidate> candidates;

  /// The best move.
  BigTwoCandidate get best => candidates.first;

  /// Deals played out in total.
  final int playouts;

  /// Guessed deals used.
  final int deals;

  /// Time taken, in microseconds.
  final int elapsedMicros;

  /// The fewest-plays plan for the hand as it is now.
  final HandPlan plan;
}

/// Rates moves from a [BigTwoView]. One coach can serve many decisions; it
/// keeps nothing between calls except its settings.
class BigTwoCoach {
  /// A coach with this [budget] and play-out [policy].
  const BigTwoCoach({this.budget = CoachBudget.standard, this.policy = const HeuristicPolicy(noise: 0.3)});

  /// Work allowed per decision.
  final CoachBudget budget;

  /// How everyone plays inside the play-outs.
  final HeuristicPolicy policy;

  /// Rates every legal move for the seat of [view], which must be on turn.
  /// [topN] trims the list (the best move is always included). The same
  /// [seed] gives the same answer.
  BigTwoAnalysis analyze(BigTwoView view, {int seed = 1, int? topN}) => _analyze(view, seed, topN, null);

  /// The same analysis with every hand known, for spectators, who see all
  /// the cards: the "true" chances of each move for the player on turn in
  /// [state]. Label it clearly in the app, since the player can't know
  /// what this answer is based on.
  BigTwoAnalysis analyzeAllKnown(BigTwoState state, {int seed = 1, int? topN}) => _analyze(
        state.viewFor(state.toMove),
        seed,
        topN,
        [for (var s = 0; s < state.players; s++) state.handCodesOf(s)],
      );

  BigTwoAnalysis _analyze(BigTwoView view, int seed, int? topN, List<List<int>>? knownHands) {
    final watch = Stopwatch()..start();
    final legal = view.legalMoves();
    if (legal.isEmpty) throw StateError('Seat ${view.seat} is not on turn');
    final me = view.seat;
    final rng = GameRandom(seed);
    final planner = HandPlanner(view.rules);
    final plan = planner.plan(view.handCodes, view: view);
    final solver = EndgameSolver(nodeLimit: 800);

    final n = legal.length;
    // A forced move needs only enough play-outs to show its chances.
    final playouts = budget.playoutsFor(view.counts, n);
    final stats = List.generate(n, (_) => _Stats());
    // Each guessed deal several candidates were played on together: its
    // points per candidate (NaN where one wasn't), for the paired errors.
    final shared = <Float64List>[];
    final sure = List<bool>.filled(n, false);
    final proved = List<bool>.filled(n, false);

    // Proofs against any hidden cards, for small endgames.
    final base = BigTwoState.fromView(view, null);
    final myCount = view.handCodes.length;
    var unseen = 0;
    for (var s = 0; s < view.players; s++) {
      if (s != me) unseen += view.counts[s];
    }
    for (var i = 0; i < n; i++) {
      if (legal[i].size == myCount) {
        sure[i] = true;
        proved[i] = true;
      }
    }
    if (budget.proofNodes > 0 && (myCount <= 3 || (myCount <= 8 && unseen <= 16))) {
      final proofSolver = EndgameSolver(nodeLimit: math.max(200, budget.proofNodes ~/ n));
      final shared = EndgameSolver.sharedState(base, me);
      for (var i = 0; i < n; i++) {
        if (sure[i]) continue;
        final child = shared.copy();
        child.applyTrusted(legal[i]);
        if (proofSolver.solveShared(child, me) == SolveOutcome.win) sure[i] = true;
      }
    }

    final sampler = DealSampler(view);
    final pool = (knownHands == null && budget.inferencePool > 0 && view.history.isNotEmpty)
        ? WeightedDeals(view, () => sampler.sample(rng), InferenceModel(policy: HeuristicPolicy(weights: policy.weights)),
            budget.inferencePool)
        : null;
    List<List<int>> guess() => knownHands ?? (pool != null ? pool.pick(rng) : sampler.sample(rng));
    bool outOfTime() => budget.maxMillis != null && watch.elapsedMilliseconds >= budget.maxMillis!;
    var used = 0, deals = 0;
    List<int> order;
    // Per move: the round the search dropped it in, or null (see
    // BigTwoCandidate.eliminatedAt).
    final dropped = List<int?>.filled(n, null);

    if (budget.tree) {
      // Open-loop information-set tree search over the player's own moves.
      final ctx = PolicyContext(base, policy.weights);
      final rootOrder = List<int>.generate(n, (i) => i)
        ..sort((a, b) {
          final c = ctx.score(legal[b]).compareTo(ctx.score(legal[a]));
          return c != 0 ? c : a.compareTo(b);
        });
      final children = List.generate(n, (_) => _TreeNode());
      // The comparison's share, but enough deals to measure every move's gap
      // (CoachBudget.compareShare), and two thirds of the play-outs at most.
      final comparePlayouts = n > 1 && budget.compareShare > 0
          ? math.min(playouts * 2 ~/ 3, math.max((playouts * budget.compareShare).round(), _compareDeals * n))
          : 0;
      for (var it = 0; it < playouts - comparePlayouts; it++) {
        // Every move gets one play-out before the time cap may stop the
        // search: a move with none would have no numbers at all.
        if (it >= n && outOfTime()) break;
        final st = BigTwoState.fromView(view, guess());
        final prng = GameRandom(rng.nextSeed());
        deals++;
        used++;
        var pick = -1;
        for (final i in rootOrder) {
          if (children[i].visits == 0) {
            pick = i;
            break;
          }
        }
        if (pick < 0) pick = _ucb(children, it + 1, budget.exploration);
        st.applyTrusted(legal[pick]);
        final r = (sure[pick] && !proved[pick])
            ? _playOut(st, me, prng, solver, proofMode: true)
            : _treePlayOut(st, me, prng, children[pick], solver, expandedAlready: children[pick].visits == 0);
        children[pick].update(r.$2);
        stats[pick].add(r.$1, r.$2);
      }
      // A move visited less than a quarter as often as the most visited one
      // was given up on early (a proven win never is).
      var most = 0;
      for (final child in children) {
        most = math.max(most, child.visits);
      }
      for (var i = 0; i < n; i++) {
        if (!sure[i] && children[i].visits * 4 < most) dropped[i] = 0;
      }
      order = List<int>.generate(n, (i) => i)
        ..sort((a, b) {
          if (sure[a] != sure[b]) return sure[a] ? -1 : 1;
          final v = children[b].visits.compareTo(children[a].visits);
          if (v != 0) return v;
          final c = _compare(stats[a], stats[b], false, false);
          return c != 0 ? c : a.compareTo(b);
        });
      if (comparePlayouts > 0) {
        // The fair comparison (CoachBudget.compareShare): from here on every
        // move's numbers come from the same deals, played on the same way.
        for (var i = 0; i < n; i++) {
          stats[i] = _Stats();
        }
        final all = List<int>.generate(n, (i) => i);
        final count = math.max(2, comparePlayouts ~/ n);
        for (var d = 0; d < count; d++) {
          // Two deals at least, so every move has a spread.
          if (d >= 2 && outOfTime()) break;
          used += _playShared(view, guess(), rng.nextSeed(), legal, all, me, solver, sure, proved, stats, shared);
          deals++;
        }
        // The tree's pick stays first unless the comparison clearly scores
        // another move higher: with many moves and few visits each, the
        // tree's favourite can be chance. The rest follow by points.
        final treePick = order.first;
        var pick = treePick;
        if (!sure[treePick]) {
          for (var i = 0; i < n; i++) {
            if (stats[i].points > stats[pick].points) pick = i;
          }
          if (pick != treePick) {
            final error = _pairedError(shared, pick, treePick, _pooledSpread(stats) * math.sqrt2)!;
            if (stats[pick].points - stats[treePick].points <= _clearGap * error) pick = treePick;
          }
        }
        dropped[pick] = null;
        order = [
          pick,
          ...List<int>.generate(n, (i) => i).where((i) => i != pick).toList()
            ..sort((a, b) {
              final c = _compare(stats[a], stats[b], sure[a], sure[b]);
              if (c != 0) return c;
              final v = children[b].visits.compareTo(children[a].visits);
              return v != 0 ? v : a.compareTo(b);
            }),
        ];
      }
    } else {
      // Successive halving over guessed deals.
      var alive = List<int>.generate(n, (i) => i);
      final keep = math.min(n, 3);
      var rounds = 0;
      while ((keep << rounds) < n) {
        rounds++;
      }
      final perPhase = playouts / (rounds + 1);
      final eliminatedAt = List<int>.filled(n, rounds + 1);

      void runDeals(List<int> who, int count) {
        for (var d = 0; d < count; d++) {
          if (deals > 0 && outOfTime()) return;
          used += _playShared(view, guess(), rng.nextSeed(), legal, who, me, solver, sure, proved, stats, shared);
          deals++;
        }
      }

      for (var round = 0; round < rounds && alive.length > keep; round++) {
        final count = math.max(2, (perPhase / alive.length).floor());
        runDeals(alive, count);
        alive.sort((a, b) {
          final c = _compare(stats[a], stats[b], sure[a], sure[b]);
          return c != 0 ? c : a.compareTo(b);
        });
        final next = math.max(keep, (alive.length / 2).ceil());
        for (final i in alive.sublist(next)) {
          eliminatedAt[i] = round;
        }
        alive = alive.sublist(0, next);
        if (outOfTime()) break;
      }
      final left = playouts - used;
      runDeals(alive, math.max(4, (left / alive.length).floor()));
      for (var i = 0; i < n; i++) {
        if (!sure[i] && eliminatedAt[i] <= rounds) dropped[i] = eliminatedAt[i];
      }

      order = List<int>.generate(n, (i) => i)
        ..sort((a, b) {
          if (eliminatedAt[a] != eliminatedAt[b]) return eliminatedAt[b].compareTo(eliminatedAt[a]);
          final c = _compare(stats[a], stats[b], sure[a], sure[b]);
          return c != 0 ? c : a.compareTo(b);
        });
    }

    final bestPoints = stats[order.first].points;
    final errors = _gapErrors(stats, shared, order.first);
    final reasons = _Reasons(view, legal, planner, plan);
    var result = [
      for (final i in order)
        BigTwoCandidate(
          play: legal[i],
          winChance: sure[i] ? 1.0 : stats[i].winRate,
          expectedPoints: stats[i].points,
          samples: stats[i].n,
          sureWin: sure[i],
          reasons: reasons.of(legal[i], sure[i]),
          pointsLost: math.max(0, bestPoints - stats[i].points),
          pointsError: errors[i],
          eliminatedAt: dropped[i],
        ),
    ];
    if (topN != null && topN < result.length) result = result.sublist(0, math.max(1, topN));
    return BigTwoAnalysis(
      candidates: result,
      playouts: used,
      deals: deals,
      elapsedMicros: watch.elapsedMicroseconds,
      plan: plan,
    );
  }

  /// Plays the moves [who] on one guessed deal ([hands]), each from the
  /// same play-out seed, adds each result to its [stats] and the deal's row
  /// to [shared]. Returns the play-outs played.
  int _playShared(BigTwoView view, List<List<int>> hands, int playSeed, List<Play> legal, List<int> who, int me,
      EndgameSolver solver, List<bool> sure, List<bool> proved, List<_Stats> stats, List<Float64List> shared) {
    final dealState = BigTwoState.fromView(view, hands);
    final row = Float64List(legal.length)..fillRange(0, legal.length, double.nan);
    for (final i in who) {
      final s = dealState.copy();
      s.applyTrusted(legal[i]);
      final r = _playOut(s, me, GameRandom(playSeed), solver, proofMode: sure[i] && !proved[i]);
      stats[i].add(r.$1, r.$2);
      row[i] = r.$2.toDouble();
    }
    shared.add(row);
    return who.length;
  }

  /// For each move, the standard error of the gap between its points and
  /// the [pick]'s (BigTwoCandidate.pointsError). Where the two were played
  /// on the same deals ([shared]) it is the error of the paired gaps, which
  /// leaves the luck of the deal out; otherwise (the tree search without a
  /// comparison) the two moves' own errors combined.
  static List<double> _gapErrors(List<_Stats> stats, List<Float64List> shared, int pick) {
    final fallback = _pooledSpread(stats);
    final pickError = stats[pick].error(fallback);
    return [
      for (var i = 0; i < stats.length; i++)
        if (i == pick)
          0
        else
          _pairedError(shared, i, pick, fallback * math.sqrt2) ?? _combined(pickError, stats[i].error(fallback)),
    ];
  }

  static double _combined(double a, double b) => math.sqrt(a * a + b * b);

  /// The spread of any one play-out of the decision: what a move with too
  /// few play-outs to measure its own is assumed to have.
  static double _pooledSpread(List<_Stats> stats) {
    final pooled = _Stats();
    for (final s in stats) {
      pooled
        ..n += s.n
        ..sum += s.sum
        ..sumSquares += s.sumSquares;
    }
    return pooled.spread ?? 0;
  }

  /// The standard error of move [i]'s points minus [pick]'s over the deals
  /// both were played on, or null if there were none. [fallback]: the
  /// spread of one gap to assume with too few deals to measure it.
  static double? _pairedError(List<Float64List> shared, int i, int pick, double fallback) {
    final gaps = _Stats();
    for (final row in shared) {
      final a = row[i], b = row[pick];
      if (a.isNaN || b.isNaN) continue;
      gaps
        ..n += 1
        ..sum += a - b
        ..sumSquares += (a - b) * (a - b);
    }
    if (gaps.n == 0) return null;
    return gaps.error(fallback);
  }

  // Every sort here ends with a tie-break on the move's index: the Dart VM
  // and JavaScript sort equal elements differently, and the same seed must
  // give the same answer on both.
  static int _compare(_Stats a, _Stats b, bool sureA, bool sureB) {
    if (sureA != sureB) return sureA ? -1 : 1;
    final c = b.points.compareTo(a.points);
    if (c != 0) return c;
    return b.winRate.compareTo(a.winRate);
  }

  (bool, int) _playOut(BigTwoState s, int me, GameRandom rng, EndgameSolver solver, {required bool proofMode}) {
    while (s.winner < 0) {
      Play? move;
      if (s.toMove == me) {
        if (proofMode) {
          final shared = EndgameSolver.sharedState(s, me);
          if (solver.solveShared(shared, me) == SolveOutcome.win) move = solver.bestMove(shared);
        } else if (budget.exactEndgame && solver.totalNodes < budget.endgameNodes && _small(s, me)) {
          if (solver.solvePerfect(s, me) == SolveOutcome.win) move = solver.bestMove(s);
        }
      }
      s.applyTrusted(move ?? policy.choose(s, rng));
    }
    final r = scoreDeal(s);
    return (s.winner == me, r.scores[me]);
  }

  // Plays one iteration on from [start] (the player's move just made): the
  // player's later moves go down the tree (picking with UCB among the moves
  // legal in this guessed deal, and adding one new node per iteration);
  // everyone else, and the player below the tree, plays the policy.
  (bool, int) _treePlayOut(BigTwoState s, int me, GameRandom rng, _TreeNode start, EndgameSolver solver,
      {required bool expandedAlready}) {
    var node = start;
    var expanded = expandedAlready;
    final path = <_TreeNode>[];
    while (s.winner < 0) {
      if (s.toMove == me && !expanded) {
        final moves = s.legalMoves();
        if (moves.length == 1) {
          s.applyTrusted(moves.first);
          continue;
        }
        final fresh = [for (final x in moves) if (node.child(x) == null) x];
        Play m;
        if (fresh.isNotEmpty) {
          // The policy's favourite among the moves not tried yet.
          m = fresh.length == 1 ? fresh.first : policy.chooseFrom(s, fresh, rng);
          expanded = true;
          node = node.add(m);
        } else {
          var best = -1.0e9;
          var bestNode = node;
          m = moves.first;
          for (final x in moves) {
            final c = node.child(x)!;
            c.available++;
            final v = c.mean + budget.exploration * math.sqrt(lnInt(c.available) / c.visits);
            if (v > best) {
              best = v;
              bestNode = c;
              m = x;
            }
          }
          node = bestNode;
        }
        path.add(node);
        s.applyTrusted(m);
      } else {
        Play? move;
        if (s.toMove == me && budget.exactEndgame && solver.totalNodes < budget.endgameNodes && _small(s, me)) {
          if (solver.solvePerfect(s, me) == SolveOutcome.win) move = solver.bestMove(s);
        }
        s.applyTrusted(move ?? policy.choose(s, rng));
      }
    }
    final points = scoreDeal(s).scores[me];
    for (final n in path) {
      n.update(points);
    }
    return (s.winner == me, points);
  }

  static int _ucb(List<_TreeNode> children, int total, double c) {
    var best = 0;
    var bestV = -1.0e9;
    final logN = lnInt(total);
    for (var i = 0; i < children.length; i++) {
      final ch = children[i];
      final v = ch.mean + c * math.sqrt(logN / ch.visits);
      if (v > bestV) {
        bestV = v;
        best = i;
      }
    }
    return best;
  }

  static bool _small(BigTwoState s, int me) {
    if (s.countOf(me) > 4) return false;
    var total = 0;
    for (var i = 0; i < s.players; i++) {
      total += s.countOf(i);
    }
    return total <= 12;
  }
}

/// One of the player's own decisions in the tree search. Rewards are
/// points scaled to about one standard deviation, so the exploration
/// constant stays near 1.
/// The natural log of a positive integer, from basic arithmetic only.
///
/// `math.log` may differ in the last bit between the Dart VM and
/// JavaScript, which could flip a near-tie in the tree search and make the
/// same seed give different answers on the web. Halving is exact, and the
/// series ln(m) = 2 atanh((m - 1) / (m + 1)) uses only +, *, /, which
/// round the same everywhere.
double lnInt(int n) {
  if (n <= 1) return 0;
  final cached = n < _lnCache.length ? _lnCache[n] : 0.0;
  if (cached != 0) return cached;
  var m = n.toDouble();
  var k = 0;
  while (m >= 2) {
    m /= 2;
    k++;
  }
  final z = (m - 1) / (m + 1);
  final z2 = z * z;
  var term = z, sum = 0.0;
  for (var i = 1; i < 60; i += 2) {
    sum += term / i;
    term *= z2;
  }
  final v = 2 * sum + k * 0.6931471805599453;
  if (n < _lnCache.length) _lnCache[n] = v;
  return v;
}

final _lnCache = Float64List(1 << 16);

class _TreeNode {
  int visits = 0;
  int available = 1;
  double sum = 0;
  final List<Play> _moves = [];
  final List<_TreeNode> _nodes = [];

  double get mean => visits == 0 ? 0 : sum / visits;

  void update(int points) {
    visits++;
    sum += points / 26.0;
  }

  _TreeNode? child(Play m) {
    for (var i = 0; i < _moves.length; i++) {
      if (_moves[i] == m) return _nodes[i];
    }
    return null;
  }

  _TreeNode add(Play m) {
    final n = _TreeNode();
    _moves.add(m);
    _nodes.add(n);
    return n;
  }
}

class _Stats {
  int n = 0;
  int wins = 0;
  double sum = 0;
  double sumSquares = 0;

  void add(bool won, int points) {
    n++;
    if (won) wins++;
    sum += points;
    sumSquares += points * points;
  }

  double get winRate => n == 0 ? 0 : wins / n;
  double get points => n == 0 ? double.negativeInfinity : sum / n;

  /// The spread of one play-out's points (sample standard deviation), or
  /// null with too few play-outs to tell.
  double? get spread {
    if (n < _minSpreadSamples) return null;
    final variance = (sumSquares - sum * sum / n) / (n - 1);
    return variance <= 0 ? 0 : math.sqrt(variance);
  }

  /// The standard error of [points]: how far it may sit from the move's true
  /// average, by chance alone. [fallback] is the spread to assume when this
  /// move has too few play-outs to measure its own.
  double error(double fallback) => (spread ?? fallback) / math.sqrt(math.max(1, n));
}

/// Fewer play-outs than this can't measure a move's own spread; it gets the
/// spread of every play-out of the decision instead.
const _minSpreadSamples = 10;

/// The fewest deals the fair comparison wants for each move (within two
/// thirds of the play-outs): with fewer, a 3-player opening's 39 moves got
/// 9 deals each, and the gaps between them were mostly chance.
const _compareDeals = 24;

/// How many standard errors one move must score above another before the
/// comparison overrules the tree's pick.
const _clearGap = 2.0;

/// Works out the [CoachReason]s for each move.
class _Reasons {
  _Reasons(this.view, this.legal, this.planner, this.plan)
      : ctx = PolicyContext(BigTwoState.fromView(view, null)) {
    _unseen = masksOf(view.opponentCodes);
    var maxOpp = 0, minOpp = 99;
    for (var s = 0; s < view.players; s++) {
      if (s == view.seat) continue;
      maxOpp = math.max(maxOpp, view.counts[s]);
      minOpp = math.min(minOpp, view.counts[s]);
    }
    _maxOpp = maxOpp;
    _minOpp = minOpp;
    _canUseTwo = legal.any((p) => p.twos > 0);
    _holdsTwo = view.handCodes.any((c) => c >> 2 == Ranks.two);
    final plays = legal.where((p) => !p.isPass);
    _everyPlayCostly = plays.isNotEmpty && plays.every((p) => ctx.breaks(p) > 0 || p.twos > 0);
  }

  final BigTwoView view;
  final List<Play> legal;
  final HandPlanner planner;
  final HandPlan plan;
  final PolicyContext ctx;
  late final Uint8List _unseen;
  late final int _maxOpp, _minOpp;
  late final bool _canUseTwo, _holdsTwo, _everyPlayCostly;

  List<CoachReason> of(Play p, bool sure) {
    final out = <CoachReason>[];
    final hand = view.handCodes;
    if (!p.isPass && p.size == hand.length) {
      out.add(CoachReason.goesOut);
      return out;
    }
    if (sure) out.add(CoachReason.sureWin);
    final nextCount = view.counts[(view.seat + 1) % view.players];
    if (p.isPass) {
      if (_everyPlayCostly) out.add(CoachReason.passKeepsHand);
      if (_holdsTwo && _canUseTwo) out.add(CoachReason.keepsTwo);
    } else {
      if (!view.rules.playsFrom(_unseen, 0, p, maxSize: _maxOpp).isNotEmpty) out.add(CoachReason.cantBeBeaten);
      if (p.size == 5) out.add(CoachReason.shedsFive);
      if (p.codes.first == hand.first) out.add(CoachReason.shedsLowest);
      if (p.twos > 0) {
        out.add(CoachReason.usesTwo);
      } else if (_holdsTwo && _canUseTwo) {
        out.add(CoachReason.keepsTwo);
      }
      _breakReasons(p, out);
      final before = plan.count;
      final rest = [for (final c in hand) if (!p.containsCode(c)) c];
      final after = planner.count(rest);
      if (after == before - 1) {
        out.add(CoachReason.followsPlan);
      } else if (after >= before) {
        out.add(CoachReason.addsPlays);
      }
      if (nextCount == 1) {
        if (p.size > 1 || p.codes.first == hand.last) {
          out.add(CoachReason.blocksLastCard);
        } else {
          out.add(CoachReason.lastCardDanger);
        }
      }
    }
    if (_minOpp <= 2) out.add(CoachReason.opponentNearlyOut);
    return out;
  }

  void _breakReasons(Play p, List<CoachReason> out) {
    final codes = p.codes;
    var i = 0;
    while (i < codes.length) {
      final r = codes[i] >> 2;
      var used = 0;
      while (i < codes.length && codes[i] >> 2 == r) {
        used++;
        i++;
      }
      final held = popCount4[ctx.hand[r]];
      if (used < held) {
        final reason = switch (held) {
          2 => CoachReason.breaksPair,
          3 => CoachReason.breaksTriple,
          _ => CoachReason.breaksFour,
        };
        if (!out.contains(reason)) out.add(reason);
      }
    }
  }
}
