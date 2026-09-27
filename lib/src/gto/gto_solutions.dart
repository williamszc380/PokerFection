import 'dart:async';

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

/// Runs the solvers in the background.
///
/// Preflop games are kept while the app runs, so each is only solved once.
/// Postflop streets depend on the exact board and betting, so each one is
/// solved when it is reached.
class GtoSolutions {
  GtoSolutions({
    this.iterations = 200,
    this.inBackground = true,
    this.keep = 8,
    this.postflopIterations,
    Future<PreflopEquity> Function()? loadEquity,
  }) : _loadEquity = loadEquity ?? _loadEquityAsset;

  /// Shared by the whole app.
  static final shared = GtoSolutions();

  /// Preflop solver iterations.
  final int iterations;

  /// Postflop solver iterations for every street, or null for the defaults
  /// (more on the river, which is quick to solve).
  final int? postflopIterations;

  /// Solves one postflop street, given both players' ranges (first to act first).
  Future<PostflopSolution> solvePostflop(PostflopSpec spec, List<Float64List> ranges) async {
    final iterations = postflopIterations ??
        switch (spec.street) {
          Street.river => 300,
          _ => 120,
        };
    if (inBackground) return solvePostflopInBackground(spec, ranges, iterations);
    return PostflopSolver(spec, ranges).solve(iterations: iterations);
  }

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
        final PreflopSolution solution;
        if (inBackground) {
          solution = await solveInBackground(spec, equity, iterations, (p) => progress.value = p);
        } else {
          solution = PreflopSolver(PreflopTree(spec), equity)
              .solve(iterations: iterations, onProgress: (done, total) => progress.value = done / total);
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
    final equity = await (_equity ??= _loadEquity());
    if (inBackground) return solveInBackground(spec, equity, iterations, (_) {}, ranges: ranges);
    return PreflopSolver(PreflopTree(spec), equity, ranges: ranges).solve(iterations: iterations);
  }

  static Future<PreflopEquity> _loadEquityAsset() async =>
      PreflopEquity.fromBytes(await rootBundle.load('assets/preflop_equity.bin'));
}
