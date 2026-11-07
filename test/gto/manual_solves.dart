import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:pokerfection/src/gto/gto_solutions.dart';
import 'package:pokerfection/src/gto/postflop/postflop_solver.dart';
import 'package:pokerfection/src/gto/postflop/postflop_tree.dart';
import 'package:pokerfection/src/gto/preflop/preflop_equity.dart';
import 'package:pokerfection/src/gto/preflop/preflop_solver.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tree.dart';

/// What a [PendingSolve] is for.
enum SolveKind { whole, subgame, street }

/// Solves that finish only when the test says, so a test chooses when
/// answers arrive (and, with a queue that runs several at once, in what
/// order) without any wall time.
///
/// The queue still decides which solve starts: a solve shows up in
/// [pending] once it is the queue's turn for it. [complete] then runs the
/// real solver on this thread, with the run's own iterations: with
/// [withManualSolves] those are few, and warm starts are off, so the same
/// spot always gives the same answer whatever was solved before.
class ManualSolves implements SolveRunner {
  ManualSolves({this.auto = false});

  /// Finish every solve as soon as it starts (the "everything at once" run
  /// to compare others with).
  bool auto;

  /// Started and not finished yet, oldest first.
  final List<PendingSolve> pending = [];

  /// Every solve started, in the order the queue started them.
  final List<PendingSolve> started = [];

  /// The one solve running (with one-at-a-time queues there is at most one).
  PendingSolve get only {
    if (pending.length != 1) throw StateError('${pending.length} solves pending: $pending');
    return pending.single;
  }

  /// Finishes every solve pending now. Those it lets start come in later
  /// microtasks: flush them (a pump, or a zero delay) before looking again.
  void completeAll() {
    for (final solve in [...pending]) {
      solve.complete();
    }
  }

  @override
  Future<PreflopSolution> preflop(PreflopRun run) => _start(
    run.ranges == null ? SolveKind.whole : SolveKind.subgame,
    run.spec,
    [?run.ranges],
    run.owner,
    run.priority,
    run.iterations,
    run.warm != null,
    () {
      final tree = PreflopTree(run.spec);
      final warm = run.warm == null ? null : warmStrategies(tree, run.warm!);
      return PreflopSolver(tree, run.equity, ranges: run.ranges, warm: warm).solve(iterations: run.iterations);
    },
  );

  @override
  Future<PostflopSolution> postflop(PostflopRun run) => _start(
    SolveKind.street,
    run.spec,
    run.ranges,
    run.owner,
    run.priority,
    run.iterations,
    false,
    () => PostflopSolver(run.spec, run.ranges).solve(iterations: run.iterations),
  );

  Future<T> _start<T>(
    SolveKind kind,
    Object spec,
    List<Float64List> ranges,
    SolveOwner? owner,
    SolvePriority priority,
    int iterations,
    bool warmed,
    T Function() solve,
  ) {
    final result = Completer<T>();
    late final PendingSolve pendingSolve;
    void finish() {
      if (result.isCompleted) throw StateError('$pendingSolve has already finished');
      pending.remove(pendingSolve);
    }

    pendingSolve = PendingSolve._(
      kind,
      spec,
      ranges,
      owner,
      priority,
      iterations,
      warmed,
      () {
        finish();
        result.complete(solve());
      },
      (error) {
        finish();
        result.completeError(error);
      },
      () => result.isCompleted,
    );
    started.add(pendingSolve);
    pending.add(pendingSolve);
    if (auto) pendingSolve.complete();
    return result.future;
  }
}

/// One solve started by the queue and waiting for the test.
class PendingSolve {
  PendingSolve._(
    this.kind,
    this.spec,
    this.ranges,
    this.owner,
    this.priority,
    this.iterations,
    this.warmed,
    this._complete,
    this._fail,
    this._done,
  );

  final SolveKind kind;

  /// A [PreflopSpec] (whole game or subgame) or a [PostflopSpec] (street).
  final Object spec;

  /// The subgame's range, or the street's two ranges; empty for a whole game.
  final List<Float64List> ranges;

  /// The hand that asked first, and how urgent the solve was when it started.
  final SolveOwner? owner;
  final SolvePriority priority;

  /// The solver iterations, and whether it starts from a similar game's
  /// answer (never, unless the test turns warm starts back on).
  final int iterations;
  final bool warmed;

  final void Function() _complete;
  final void Function(Object error) _fail;
  final bool Function() _done;

  PreflopSpec get preflop => spec as PreflopSpec;
  PostflopSpec get postflop => spec as PostflopSpec;

  bool get done => _done();

  /// Solves it now, on this thread, and hands the answer back.
  void complete() => _complete();

  /// Makes it fail, as a solver that crashed would.
  void fail([Object error = const _SolveFailed()]) => _fail(error);

  @override
  String toString() => 'PendingSolve(${kind.name}, ${priority.name}, hand ${owner?.hand})';
}

class _SolveFailed implements Exception {
  const _SolveFailed();

  @override
  String toString() => 'The solver failed (a test said so)';
}

/// The equity table, read once for all tests (each load hands it out in a
/// new future, made in the zone that asks: widget tests' fake time).
final PreflopEquity _equity = PreflopEquity.fromBytes(
  ByteData.sublistView(File('assets/preflop_equity.bin').readAsBytesSync()),
);

/// Solutions whose solves run through [solves], with few iterations (as in
/// the other tests) and no warm starts.
GtoSolutions withManualSolves(
  ManualSolves solves, {
  int iterations = 30,
  int postflopIterations = 5,
  SolveQueue? queue,
}) => GtoSolutions(
  iterations: iterations,
  postflopIterations: postflopIterations,
  inBackground: false,
  loadEquity: () async => _equity,
  runner: solves,
  queue: queue,
)..warm = false;
