import 'dart:typed_data';

import '../postflop/postflop_solver.dart';
import '../postflop/postflop_tree.dart';
import 'preflop_equity.dart';
import 'preflop_solver.dart';
import 'preflop_tree.dart';

/// Browsers have no isolates: solve on the main thread.
Future<PreflopSolution> solveInBackground(
  PreflopSpec spec,
  PreflopEquity equity,
  int iterations,
  void Function(double progress) onProgress, {
  Float64List? ranges,
}) async =>
    PreflopSolver(PreflopTree(spec), equity, ranges: ranges)
        .solve(iterations: iterations, onProgress: (done, total) => onProgress(done / total));

/// Browsers have no isolates: solve on the main thread.
Future<PostflopSolution> solvePostflopInBackground(
  PostflopSpec spec,
  List<Float64List> ranges,
  int iterations,
) async =>
    PostflopSolver(spec, ranges).solve(iterations: iterations);
