/// The solvers' Web Worker, for the web version (browsers have no isolates).
///
/// Compiled on its own into build/web/solver_worker.js by
/// tool/build_web.dart. The page asks one worker for each solve (see
/// background_solve_web.dart), and that worker spreads the work over more
/// copies of itself, as native builds do with isolates (see branches.dart).
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'src/gto/branches.dart';
import 'src/gto/postflop/parallel_postflop_solver.dart';
import 'src/gto/preflop/parallel_preflop_solver.dart';
import 'src/gto/preflop/preflop_equity.dart';
import 'src/gto/web_workers.dart';

final _scope = globalContext as web.DedicatedWorkerGlobalScope;

void main() {
  Branches? branches;
  _scope.onmessage = ((web.MessageEvent event) {
    final request = event.data as SolverRequest;
    try {
      switch (request.kind) {
        case 'preflop':
          unawaited(_reportFailure(_solvePreflop(request)));
        case 'postflop':
          unawaited(_reportFailure(_solvePostflop(request)));
        case 'preflopBranches' || 'postflopBranches':
          branches = request.branchJob.start();
        case 'walk':
          final values = branches!.walk(
            request.t,
            request.last,
            request.active.toDart,
            request.reach.toDart,
            request.mass.toDart,
          );
          _reply(SolverReply(kind: 'walked', walked: values.toJS));
        case 'export':
          final (offsets, average, values) = branches!.export();
          _reply(
            SolverReply(kind: 'exported', offsets: offsets.toJS, average: average.toJS, ownedValues: values.toJS),
            [offsets.buffer.toJS, average.buffer.toJS, values.buffer.toJS],
          );
      }
    } catch (error, stack) {
      _reply(SolverReply(kind: 'failed', error: '$error\n$stack'));
    }
  }).toJS;
  _reply(SolverReply(kind: 'ready'));
}

/// [transfer]: buffers handed over instead of copied (big answers take tens of MB).
void _reply(SolverReply reply, [List<JSObject> transfer = const []]) => _scope.postMessage(reply, transfer.toJS);

Future<void> _reportFailure(Future<void> solving) async {
  try {
    await solving;
  } catch (error, stack) {
    _reply(SolverReply(kind: 'failed', error: '$error\n$stack'));
  }
}

/// Workers can start workers in all current browsers; on one that can't,
/// this worker solves alone.
int _threads(SolverRequest request) => _scope.has('Worker') ? request.threads : 1;

Future<void> _solvePreflop(SolverRequest request) async {
  final ranges = request.ranges.toDart;
  final solution = await solvePreflopInParallel(
    request.preflopSpec,
    PreflopEquity(request.equity.toDart),
    iterations: request.iterations,
    threads: _threads(request),
    ranges: ranges.isEmpty ? null : ranges.single.toDart,
    onProgress: (done, total) {
      if (done % 5 == 0 || done == total) _reply(SolverReply(kind: 'progress', progress: done / total));
    },
  );
  _replySolved(solution.strategy, solution.values);
}

Future<void> _solvePostflop(SolverRequest request) async {
  final solution = await solvePostflopInParallel(
    request.postflopSpec,
    [for (final r in request.ranges.toDart) r.toDart],
    iterations: request.iterations,
    threads: _threads(request),
  );
  _replySolved(solution.strategy, solution.values);
}

void _replySolved(Float32List strategy, Float32List values) => _reply(
      SolverReply(kind: 'solved', strategy: strategy.toJS, values: values.toJS),
      [strategy.buffer.toJS, values.buffer.toJS],
    );
