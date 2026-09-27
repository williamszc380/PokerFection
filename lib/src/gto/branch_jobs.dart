import 'dart:typed_data';

import 'branches.dart';
import 'hand_classes.dart';
import 'postflop/postflop_solver.dart';
import 'postflop/postflop_tree.dart';
import 'preflop/preflop_equity.dart';
import 'preflop/preflop_solver.dart';
import 'preflop/preflop_tree.dart';

/// What one worker thread is given to solve: the branches starting at
/// [roots] (decision ids) of a preflop game or a postflop street.
sealed class BranchJob {
  const BranchJob(this.roots);

  final List<int> roots;

  /// Sets up the worker's side (in the worker: each builds its own copy of the tree).
  Branches start();
}

final class PreflopBranchJob extends BranchJob {
  const PreflopBranchJob(this.spec, this.equity, super.roots);

  final PreflopSpec spec;

  /// [PreflopEquity.values].
  final Float64List equity;

  @override
  Branches start() {
    final tree = PreflopTree(spec);
    final owned = <int>[];
    void collect(PreflopNode node) {
      if (node is PreflopDecision) {
        owned.add(node.id);
        node.children.forEach(collect);
      }
    }

    for (final id in roots) {
      collect(tree.decisions[id]);
    }
    final n = spec.players;
    return Branches(
      PreflopSolver.part(tree, PreflopEquity(equity), owned: owned),
      roots,
      reachBlock: n * handClassCount,
      massBlock: n,
    );
  }
}

final class PostflopBranchJob extends BranchJob {
  const PostflopBranchJob(this.spec, this.ranges, super.roots);

  final PostflopSpec spec;
  final List<Float64List> ranges;

  @override
  Branches start() {
    final tree = PostflopTree(spec, hands: 1);
    final owned = <int>[];
    void collect(PostflopNode node) {
      if (node is PostflopDecision) {
        owned.add(node.id);
        node.children.forEach(collect);
      }
    }

    for (final id in roots) {
      collect(tree.decisions[id]);
    }
    final solver = PostflopSolver.part(spec, ranges, owned: owned);
    return Branches(solver, roots, reachBlock: 2 * solver.hands.length, massBlock: 2);
  }
}
