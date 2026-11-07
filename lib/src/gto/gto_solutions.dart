import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../engine/events.dart';
import 'postflop/postflop_solver.dart';
import 'postflop/postflop_tree.dart';
import 'preflop/background_solve.dart';
import 'preflop/preflop_advisor.dart';
import 'preflop/preflop_equity.dart';
import 'preflop/preflop_solver.dart';
import 'preflop/preflop_tree.dart';
import 'solve_cache.dart';
import 'solve_queue.dart';

export 'solve_queue.dart' show SolveCancelled, SolveClaim, SolveOwner, SolvePriority, SolveQueue;

/// One preflop solve for a [SolveRunner]: a whole game ([ranges] null) or
/// the user's subgame.
class PreflopRun {
  const PreflopRun({
    required this.spec,
    required this.equity,
    required this.iterations,
    this.ranges,
    this.warm,
    this.onProgress,
    this.owner,
    required this.priority,
  });

  final PreflopSpec spec;
  final PreflopEquity equity;
  final int iterations;

  /// The players' ranges for a subgame (see [PreflopSolver]); null for a
  /// whole game.
  final Float64List? ranges;

  /// A similar game's answer to start from (see [warmStrategies]).
  final PreflopSolution? warm;

  /// Told how far the solve is, from 0 to 1 (whole games only).
  final void Function(double progress)? onProgress;

  /// The hand that asked first (null for tools and tests), and how urgent
  /// the solve was when it started: for tests that check who asked.
  final SolveOwner? owner;
  final SolvePriority priority;
}

/// One postflop street for a [SolveRunner].
class PostflopRun {
  const PostflopRun({
    required this.spec,
    required this.ranges,
    required this.iterations,
    this.owner,
    required this.priority,
  });

  final PostflopSpec spec;

  /// Both players' ranges, first to act first.
  final List<Float64List> ranges;
  final int iterations;

  /// See [PreflopRun.owner].
  final SolveOwner? owner;
  final SolvePriority priority;
}

/// Does the actual solving for [GtoSolutions], once the queue says it is a
/// job's turn. Tests put in their own, which finish solves when the test
/// says (`test/gto/manual_solves.dart`).
abstract interface class SolveRunner {
  Future<PreflopSolution> preflop(PreflopRun run);
  Future<PostflopSolution> postflop(PostflopRun run);
}

/// The solvers the app uses: on other threads (isolates on the device,
/// Web Workers in the browser), or on this one.
class StandardSolveRunner implements SolveRunner {
  const StandardSolveRunner({this.inBackground = true});

  final bool inBackground;

  @override
  Future<PreflopSolution> preflop(PreflopRun run) async {
    final PreflopRun(:spec, :equity, :iterations, :ranges, :warm, :onProgress) = run;
    if (inBackground) {
      return solveInBackground(spec, equity, iterations, onProgress ?? (_) {}, ranges: ranges, warmFrom: warm);
    }
    final tree = PreflopTree(spec);
    return PreflopSolver(tree, equity, ranges: ranges, warm: warm == null ? null : warmStrategies(tree, warm))
        .solve(iterations: iterations, onProgress: onProgress == null ? null : (done, total) => onProgress(done / total));
  }

  @override
  Future<PostflopSolution> postflop(PostflopRun run) async {
    if (inBackground) return solvePostflopInBackground(run.spec, run.ranges, run.iterations);
    return PostflopSolver(run.spec, run.ranges).solve(iterations: run.iterations);
  }
}

/// What a queued job solves; part of its key in [GtoSolutions.queue].
enum _Kind { whole, subgame, street }

/// Runs the solvers in the background, one at a time, most urgent first
/// (see [SolveQueue]).
///
/// Preflop games are kept while the app runs, so each is only solved once.
/// Postflop streets and the user's preflop subgames depend on the exact
/// cards and betting, so each one is solved when it is reached; the last
/// few are kept too (see [SolveCache]), for when the same spot comes again.
///
/// Each solve can say which hand wants it ([SolveOwner]) and how urgently
/// ([SolvePriority]). Callers that say neither get [SolvePriority.shown]
/// and are never dropped, as before there was a queue.
class GtoSolutions {
  GtoSolutions({
    this.iterations = 200,
    int? warmIterations,
    this.inBackground = true,
    this.keep = 8,
    this.postflopIterations,
    Future<PreflopEquity> Function()? loadEquity,
    this.runner,
    SolveQueue? queue,
  })  : warmIterations = warmIterations ?? (iterations * 0.32).ceil(),
        _loadEquity = loadEquity ?? _loadEquityAsset,
        queue = queue ?? SolveQueue();

  /// Shared by the whole app.
  static final shared = GtoSolutions();

  /// Preflop solver iterations.
  final int iterations;

  /// Preflop solver iterations from a warm start (64 for 200): see [_warmFor].
  final int warmIterations;

  /// Postflop solver iterations for every street, or null for the defaults
  /// (more on the river, which is quick to solve).
  final int? postflopIterations;

  /// Every solve waits its turn here.
  final SolveQueue queue;

  /// Runs the solves; null for [StandardSolveRunner] (in the background
  /// when [inBackground]).
  @visibleForTesting
  SolveRunner? runner;

  /// Whether solves may start from a similar game's answer (see [_warmFor]).
  /// Which games are kept depends on what was solved before and when, so
  /// tests that compare answers turn this off.
  @visibleForTesting
  bool warm = true;

  SolveRunner get _runner => runner ?? StandardSolveRunner(inBackground: inBackground);

  /// Solves one postflop street, given both players' ranges (first to act first).
  Future<PostflopSolution> solvePostflop(
    PostflopSpec spec,
    List<Float64List> ranges, {
    SolveOwner? owner,
    SolvePriority priority = SolvePriority.shown,
  }) {
    final cacheKey = SolveKey(jsonEncode(spec.toJson()), ranges);
    final key = (_Kind.street, cacheKey);
    // Copied now: the caller may change its arrays before the job's turn.
    final copied = cacheKey.ranges;
    return _cached(_streets, cacheKey, key, owner, priority, () {
      final iterations = postflopIterations ??
          switch (spec.street) {
            Street.river => 300,
            _ => 120,
          };
      return _runner.postflop(PostflopRun(
        spec: spec,
        ranges: copied,
        iterations: iterations,
        owner: owner,
        priority: queue.priorityOf(key) ?? priority,
      ));
    });
  }

  /// The last postflop streets and preflop subgames solved (a big subgame
  /// takes ~100 MB, a street a few MB).
  final _streets = SolveCache<PostflopSolution>(8);
  final _subgames = SolveCache<PreflopSolution>(2);

  /// How many solved preflop games to keep in memory (the user's subgames
  /// count too; an 8-player whole game takes ~35 MB). The least recently
  /// used are dropped first.
  final int keep;

  /// Solve on other threads, using all CPU cores. Off in tests.
  final bool inBackground;
  final Future<PreflopEquity> Function() _loadEquity;
  Future<PreflopEquity>? _equity;
  final Map<PreflopSpec, PreflopAdvisor> _ready = {};
  final Map<PreflopSpec, Future<PreflopAdvisor>> _running = {};
  final Map<PreflopSpec, ValueNotifier<double>> _progress = {};

  PreflopAdvisor? ready(PreflopSpec spec) {
    final advisor = _ready.remove(spec);
    if (advisor != null) _ready[spec] = advisor; // now the most recently used
    return advisor;
  }

  /// From 0 to 1 while [spec] is being solved.
  ValueListenable<double> progressOf(PreflopSpec spec) =>
      _progress.putIfAbsent(spec, () => ValueNotifier(0));

  /// The solved game for [spec], starting the solve if needed. Asking again
  /// while it waits or runs shares it, and can make it more urgent.
  Future<PreflopAdvisor> solve(PreflopSpec spec, {SolveOwner? owner, SolvePriority priority = SolvePriority.shown}) {
    final done = ready(spec);
    if (done != null) return Future.value(done);
    final key = (_Kind.whole, spec);
    final running = _running[spec];
    if (running != null) {
      queue.join(key, owner: owner, priority: priority);
      return running;
    }
    // A dropped owner gets nothing new, and leaves nothing behind.
    if (owner != null && owner.dropped) return SolveCancelled.future();
    final future = queue.add(key, owner: owner, priority: priority, () async {
      try {
        final equity = await (_equity ??= _loadEquity());
        final progress = progressOf(spec) as ValueNotifier<double>;
        final warmFrom = _warmFor(spec);
        final solution = await _runner.preflop(PreflopRun(
          spec: spec,
          equity: equity,
          iterations: warmFrom == null ? iterations : warmIterations,
          warm: warmFrom,
          onProgress: (p) => progress.value = p,
          owner: owner,
          priority: queue.priorityOf(key) ?? priority,
        ));
        final advisor = PreflopAdvisor(solution);
        _ready[spec] = advisor;
        while (_ready.length > keep) {
          _ready.remove(_ready.keys.first);
        }
        progress.value = 1;
        return advisor;
      } finally {
        _running.remove(spec);
      }
    });
    _running[spec] = future;
    // A job taken off the queue never runs its `finally` (drop() forgets it
    // at once; this is for a queue dropped from elsewhere).
    future.then((_) {}, onError: (Object _) {
      if (identical(_running[spec], future)) _running.remove(spec);
    });
    return future;
  }

  /// Solves the user's preflop subgame for [PreflopTracker]. With no ranges
  /// (nobody has acted yet except by folding) the solve is shared and kept,
  /// so it can be done ahead of time; otherwise it is solved fresh.
  Future<PreflopSolution> solveSubgame(
    PreflopSpec spec,
    Float64List? ranges, {
    SolveOwner? owner,
    SolvePriority priority = SolvePriority.shown,
  }) async {
    if (ranges == null) return (await solve(spec, owner: owner, priority: priority)).solution;
    final cacheKey = SolveKey(spec.key, [ranges]);
    final key = (_Kind.subgame, cacheKey);
    final copied = cacheKey.ranges.single;
    return _cached(_subgames, cacheKey, key, owner, priority, () async {
      final equity = await (_equity ??= _loadEquity());
      final warmFrom = _warmFor(spec);
      return _runner.preflop(PreflopRun(
        spec: spec,
        equity: equity,
        iterations: warmFrom == null ? iterations : warmIterations,
        ranges: copied,
        warm: warmFrom,
        owner: owner,
        priority: queue.priorityOf(key) ?? priority,
      ));
    });
  }

  /// Lets go of [owner]'s solves that haven't started (a hand that has
  /// nothing more to grade): see [SolveQueue.drop]. They are forgotten at
  /// once, so a later request for the same spot solves it again.
  void drop(SolveOwner owner) {
    for (final key in queue.drop(owner)) {
      switch (key) {
        case (_Kind.whole, final PreflopSpec spec):
          _running.remove(spec);
        case (_Kind.subgame, final SolveKey k):
          _subgames.forget(k);
        case (_Kind.street, final SolveKey k):
          _streets.forget(k);
      }
    }
  }

  /// The kept solve for [cacheKey], or a new job [run] under [key]; a second
  /// request joins the first.
  Future<T> _cached<T>(SolveCache<T> cache, SolveKey cacheKey, Object key, SolveOwner? owner, SolvePriority priority,
      Future<T> Function() run) {
    // A dropped owner gets nothing new, and leaves nothing in the cache.
    if (owner != null && owner.dropped && !cache.contains(cacheKey) && !queue.has(key)) {
      return SolveCancelled.future();
    }
    return cache.get(cacheKey, () => queue.add(key, run, owner: owner, priority: priority),
        kept: () => queue.join(key, owner: owner, priority: priority));
  }

  /// A solved game to start [spec] from (a warm start: see [PreflopSolver]),
  /// if one fits and [warm] allows it. For a whole game, the one with the
  /// closest stacks (the same players, blinds, ante and rules): usually the
  /// last hand's. For the user's subgame with 6 or more players, the whole
  /// game it is part of. With fewer players, subgames come out better from
  /// scratch.
  PreflopSolution? _warmFor(PreflopSpec spec) {
    if (!warm) return null;
    if (spec.hero >= 0) {
      if (spec.players < 6) return null;
      return _ready[_wholeGame(spec)]?.solution;
    }
    PreflopSolution? best;
    var bestGap = 0;
    for (final MapEntry(key: other, value: advisor) in _ready.entries) {
      if (other.hero >= 0 ||
          other.players != spec.players ||
          other.smallBlind != spec.smallBlind ||
          other.bigBlind != spec.bigBlind ||
          other.ante != spec.ante ||
          other.raiseRule != spec.raiseRule) {
        continue;
      }
      var gap = 0;
      for (var k = 0; k < spec.players; k++) {
        gap += (other.stacks[k] - spec.stacks[k]).abs();
      }
      if (best == null || gap < bestGap) {
        best = advisor.solution;
        bestGap = gap;
      }
    }
    return best;
  }

  static PreflopSpec _wholeGame(PreflopSpec spec) => PreflopSpec(
        stacks: spec.stacks,
        smallBlind: spec.smallBlind,
        bigBlind: spec.bigBlind,
        ante: spec.ante,
        raiseRule: spec.raiseRule,
      );

  static Future<PreflopEquity> _loadEquityAsset() async =>
      PreflopEquity.fromBytes(await rootBundle.load('assets/preflop_equity.bin'));
}
