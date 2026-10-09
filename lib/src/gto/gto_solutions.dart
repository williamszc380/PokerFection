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

/// Runs the solvers in the background.
///
/// Preflop games are kept while the app runs, so each is only solved once.
/// Postflop streets and the user's preflop subgames depend on the exact
/// cards and betting, so each one is solved when it is reached; the last
/// few are kept too (see [SolveCache]), for when the same spot comes again.
class GtoSolutions {
  GtoSolutions({
    this.iterations = 200,
    int? warmIterations,
    this.inBackground = true,
    this.keep = 8,
    this.postflopIterations,
    Future<PreflopEquity> Function()? loadEquity,
  })  : warmIterations = warmIterations ?? (iterations * 0.32).ceil(),
        _loadEquity = loadEquity ?? _loadEquityAsset;

  /// Shared by the whole app.
  static final shared = GtoSolutions();

  /// Preflop solver iterations.
  final int iterations;

  /// Preflop solver iterations from a warm start (64 for 200): see [_warmFor].
  final int warmIterations;

  /// Postflop solver iterations for every street, or null for the defaults
  /// (more on the river, which is quick to solve).
  final int? postflopIterations;

  /// Solves one postflop street, given both players' ranges (first to act first).
  Future<PostflopSolution> solvePostflop(PostflopSpec spec, List<Float64List> ranges) =>
      _streets.get(SolveKey(jsonEncode(spec.toJson()), ranges), () async {
        final iterations = postflopIterations ??
            switch (spec.street) {
              Street.river => 300,
              _ => 120,
            };
        if (inBackground) return solvePostflopInBackground(spec, ranges, iterations);
        return PostflopSolver(spec, ranges).solve(iterations: iterations);
      });

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

  /// The solved game for [spec], starting the solve if needed.
  Future<PreflopAdvisor> solve(PreflopSpec spec) {
    final done = ready(spec);
    if (done != null) return Future.value(done);
    return _running.putIfAbsent(spec, () async {
      try {
        final equity = await (_equity ??= _loadEquity());
        final progress = progressOf(spec) as ValueNotifier<double>;
        final warm = _warmFor(spec);
        final count = warm == null ? iterations : warmIterations;
        final PreflopSolution solution;
        if (inBackground) {
          solution = await solveInBackground(spec, equity, count, (p) => progress.value = p, warmFrom: warm);
        } else {
          final tree = PreflopTree(spec);
          solution = PreflopSolver(tree, equity, warm: warm == null ? null : warmStrategies(tree, warm))
              .solve(iterations: count, onProgress: (done, total) => progress.value = done / total);
        }
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
  }

  /// Solves the user's preflop subgame for [PreflopTracker]. With no ranges
  /// (nobody has acted yet except by folding) the solve is shared and kept,
  /// so it can be done ahead of time; otherwise it is solved fresh.
  Future<PreflopSolution> solveSubgame(PreflopSpec spec, Float64List? ranges) async {
    if (ranges == null) return (await solve(spec)).solution;
    return _subgames.get(SolveKey(spec.key, [ranges]), () async {
      final equity = await (_equity ??= _loadEquity());
      final warm = _warmFor(spec);
      final count = warm == null ? iterations : warmIterations;
      if (inBackground) return solveInBackground(spec, equity, count, (_) {}, ranges: ranges, warmFrom: warm);
      final tree = PreflopTree(spec);
      return PreflopSolver(tree, equity, ranges: ranges, warm: warm == null ? null : warmStrategies(tree, warm))
          .solve(iterations: count);
    });
  }

  /// A solved game to start [spec] from (a warm start: see [PreflopSolver]),
  /// if one fits. For a whole game, the one with the closest stacks (the
  /// same players, blinds, ante and rules): usually the last hand's. For
  /// the user's subgame with 6 or more players, the whole game it is part
  /// of. With fewer players, subgames come out better from scratch.
  PreflopSolution? _warmFor(PreflopSpec spec) {
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
