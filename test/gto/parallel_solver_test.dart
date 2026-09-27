import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/gto/preflop/background_solve.dart';
import 'package:pokerfection/src/gto/preflop/parallel_preflop_solver.dart';
import 'package:pokerfection/src/gto/preflop/preflop_equity.dart';
import 'package:pokerfection/src/gto/preflop/preflop_solver.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tree.dart';

final equity =
    PreflopEquity.fromBytes(ByteData.sublistView(File('assets/preflop_equity.bin').readAsBytesSync()));

void main() {
  for (final spec in [
    PreflopSpec(stacks: List.filled(6, 10000)),
    PreflopSpec(stacks: [4000, 10000, 1500, 8000, 2500], ante: 10),
  ]) {
    test('several threads give exactly the same answer as one (${spec.key})', () async {
      final serial = PreflopSolver(PreflopTree(spec), equity).solve(iterations: 25);
      final parallel = await solvePreflopInParallel(spec, equity, iterations: 25, threads: 4);
      expect(parallel.strategy.length, serial.strategy.length);
      for (var i = 0; i < serial.strategy.length; i++) {
        expect(parallel.strategy[i], serial.strategy[i], reason: 'strategy $i');
        final a = serial.values[i], b = parallel.values[i];
        expect(a.isNaN ? b.isNaN : b == a, isTrue, reason: 'value $i: $a vs $b');
      }
    });
  }

  test('the app\'s background solve (all cores, off the UI thread) matches too', () async {
    final spec = PreflopSpec(stacks: [3000, 3000, 3000, 3000]);
    final serial = PreflopSolver(PreflopTree(spec), equity).solve(iterations: 20);
    final progress = <double>[];
    final background = await solveInBackground(spec, equity, 20, progress.add);
    expect(background.strategy, serial.strategy);
    expect(progress.last, 1);
  });

  test('the work plan covers every decision exactly once', () {
    final tree = PreflopTree(PreflopSpec(stacks: List.filled(8, 10000)));
    final plan = PreflopWorkPlan(tree, 6);
    final seen = <int>{...plan.trunk};
    void branch(PreflopNode node) {
      if (node is PreflopDecision) {
        expect(seen.add(node.id), isTrue);
        node.children.forEach(branch);
      }
    }

    for (final id in plan.frontier) {
      branch(tree.decisions[id]);
    }
    expect(seen.length, tree.decisions.length);
    expect(plan.assignments.expand((a) => a).toSet().length, plan.frontier.length);
  });
}
