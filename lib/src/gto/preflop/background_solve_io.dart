import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import '../postflop/parallel_postflop_solver.dart';
import '../postflop/postflop_solver.dart';
import '../postflop/postflop_tree.dart';
import 'parallel_preflop_solver.dart';
import 'preflop_equity.dart';
import 'preflop_solver.dart';
import 'preflop_tree.dart';

/// Threads for one solve: every core but one (left for the UI), at most 12.
int get _threads => min(max(Platform.numberOfProcessors - 1, 1), 12);

/// Solves [spec] away from the UI thread, spread over the CPU's cores
/// (one coordinator isolate plus worker isolates), reporting progress 0-1.
/// [ranges]: see [PreflopSolver].
Future<PreflopSolution> solveInBackground(
  PreflopSpec spec,
  PreflopEquity equity,
  int iterations,
  void Function(double progress) onProgress, {
  Float64List? ranges,
}) async {
  final port = ReceivePort();
  final result = Completer<PreflopSolution>();
  port.listen((message) {
    if (message is double) {
      onProgress(message);
    } else if (message is (Float32List, Float32List)) {
      // The tree is rebuilt here: it is quick and doesn't need to be sent.
      result.complete(PreflopSolution(PreflopTree(spec), message.$1, message.$2));
      port.close();
    } else {
      result.completeError(StateError('Preflop solver failed: $message'));
      port.close();
    }
  });
  final _Request request = (port.sendPort, spec, equity.values, iterations, _threads, ranges);
  await Isolate.spawn(_coordinatorMain, request, onError: port.sendPort);
  return result.future;
}

/// Solves one postflop street away from the UI thread, on all CPU cores.
Future<PostflopSolution> solvePostflopInBackground(
  PostflopSpec spec,
  List<Float64List> ranges,
  int iterations,
) async {
  final threads = _threads;
  final (strategy, values) = await Isolate.run(() async {
    final solution = await solvePostflopInParallel(spec, ranges, iterations: iterations, threads: threads);
    return (solution.strategy, solution.values);
  });
  // Rebuilding the tree here is quick and saves sending it.
  final hands = PostflopHands(spec.board);
  return PostflopSolution(PostflopTree(spec, hands: hands.length), hands, strategy, values);
}

typedef _Request = (SendPort, PreflopSpec, Float64List, int, int, Float64List?);

Future<void> _coordinatorMain(_Request request) async {
  final (reply, spec, equityValues, iterations, threads, ranges) = request;
  final solution = await solvePreflopInParallel(
    spec,
    PreflopEquity(equityValues),
    iterations: iterations,
    threads: threads,
    ranges: ranges,
    onProgress: (done, total) {
      if (done % 5 == 0 || done == total) reply.send(done / total);
    },
  );
  reply.send((solution.strategy, solution.values));
}
