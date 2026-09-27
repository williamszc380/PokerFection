import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../postflop/postflop_solver.dart';
import '../postflop/postflop_tree.dart';
import '../web_workers.dart';
import 'preflop_equity.dart';
import 'preflop_solver.dart';
import 'preflop_tree.dart';

/// Worker threads for one solve: every core but one (left for the page), at most 12.
int get _threads => min(max(web.window.navigator.hardwareConcurrency - 1, 1), 12);

/// Solves [spec] in a Web Worker, which spreads the work over the CPU's
/// cores (more workers), reporting progress 0-1. [ranges]: see [PreflopSolver].
Future<PreflopSolution> solveInBackground(
  PreflopSpec spec,
  PreflopEquity equity,
  int iterations,
  void Function(double progress) onProgress, {
  Float64List? ranges,
}) async {
  final tree = PreflopTree(spec);
  final request = SolverRequest.preflop(spec, equity.values, iterations: iterations, threads: _threads, ranges: ranges);
  final answer = await _solveInWorker(request, tree.storageSize, onProgress);
  if (answer != null) return PreflopSolution(tree, answer.$1, answer.$2);
  return PreflopSolver(tree, equity, ranges: ranges)
      .solve(iterations: iterations, onProgress: (done, total) => onProgress(done / total));
}

/// Solves one postflop street in a Web Worker, on all CPU cores.
Future<PostflopSolution> solvePostflopInBackground(
  PostflopSpec spec,
  List<Float64List> ranges,
  int iterations,
) async {
  final hands = PostflopHands(spec.board);
  final tree = PostflopTree(spec, hands: hands.length);
  final request = SolverRequest.postflop(spec, ranges, iterations: iterations, threads: _threads);
  final answer = await _solveInWorker(request, tree.storageSize);
  if (answer != null) return PostflopSolution(tree, hands, answer.$1, answer.$2);
  return PostflopSolver(spec, ranges).solve(iterations: iterations);
}

/// The strategies and values a worker finds for [request] (the tree is
/// rebuilt here: it is quick and doesn't need to be sent). Null when there
/// is no worker to use, and the solve has to hold up the page instead.
Future<(Float32List, Float32List)?> _solveInWorker(
  SolverRequest request,
  int size, [
  void Function(double progress)? onProgress,
]) async {
  final worker = await SolverWorker.start();
  if (worker == null) return null;
  try {
    worker.send(request);
    while (true) {
      final reply = await worker.next();
      if (reply.kind == 'progress') {
        onProgress?.call(reply.progress);
        continue;
      }
      final strategy = reply.strategy.toDart;
      if (strategy.length == size) return (strategy, reply.values.toDart);
      // A worker script from another build (a cached copy) has other trees.
      SolverWorker.disable();
      return null;
    }
  } finally {
    worker.stop();
  }
}
