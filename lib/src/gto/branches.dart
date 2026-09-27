/// Splitting one solve across threads (see `solvePreflopInParallel`): the
/// coordinator walks the top of the tree, and each worker thread solves
/// whole branches below it, one round trip per iteration.
library;

import 'dart:typed_data';

/// What a worker needs from a solver (`PreflopSolver` or `PostflopSolver`).
abstract interface class BranchSolver {
  void beginIteration(int t);
  void beginFinalPass();

  /// Walks the branch starting at decision [nodeId], given the players'
  /// reach and masses at [reachAt] and [massAt], writing their values to
  /// [out] at [outAt].
  void walkBranch(
    int nodeId,
    Float64List reach,
    int reachAt,
    Float64List mass,
    int massAt,
    Float64List out,
    int outAt,
  );

  /// Where each decision's numbers start in this solver's arrays (-1 if not owned).
  Int32List get offsets;
  Float64List get ownedAverage;
  Float64List get ownedValues;
}

/// A worker's share of the answer: [BranchSolver.offsets],
/// [BranchSolver.ownedAverage] and [BranchSolver.ownedValues].
typedef BranchExport = (Int32List offsets, Float64List average, Float64List values);

/// A worker thread's side: solves the branches that start at [roots].
class Branches {
  Branches(this._solver, this.roots, {required this.reachBlock, required this.massBlock});

  final BranchSolver _solver;
  final List<int> roots;

  /// Numbers per branch in the reach and mass the coordinator sends.
  final int reachBlock;
  final int massBlock;
  bool _finalPass = false;

  /// One round: walks the branches the coordinator reached ([active]) for
  /// iteration [t], or the final pass ([last]), and returns their values.
  Float64List walk(int t, bool last, Uint8List active, Float64List reach, Float64List mass) {
    if (last && !_finalPass) {
      _solver.beginFinalPass();
      _finalPass = true;
    } else if (!last) {
      _solver.beginIteration(t);
    }
    final values = Float64List(roots.length * reachBlock);
    for (var k = 0; k < roots.length; k++) {
      if (active[k] == 0) continue;
      _solver.walkBranch(roots[k], reach, k * reachBlock, mass, k * massBlock, values, k * reachBlock);
    }
    return values;
  }

  BranchExport export() => (_solver.offsets, _solver.ownedAverage, _solver.ownedValues);
}

/// A worker thread as the coordinator sees it: an isolate, or a Web Worker
/// in browsers (see branch_threads.dart).
abstract interface class BranchWorker {
  /// [Branches.walk], in the worker.
  Future<Float64List> walk(int t, bool last, Uint8List active, Float64List reach, Float64List mass);

  /// [Branches.export], in the worker.
  Future<BranchExport> export();
  void stop();
}
