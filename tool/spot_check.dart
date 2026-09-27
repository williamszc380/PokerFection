// Solves one preflop subgame at several iteration counts and prints one
// hand's strategy and values, to tell slow convergence from a real bias.
import 'dart:io';
import 'dart:typed_data';

import 'package:pokerfection/src/gto/hand_classes.dart';
import 'package:pokerfection/src/gto/preflop/preflop_equity.dart';
import 'package:pokerfection/src/gto/preflop/preflop_solver.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tree.dart';

void main(List<String> args) {
  final equity =
      PreflopEquity.fromBytes(ByteData.sublistView(File('assets/preflop_equity.bin').readAsBytesSync()));
  final which = args.isNotEmpty ? args[0] : '799';
  final (spec, name) = switch (which) {
    '815' => (
        PreflopSpec(stacks: [1742, 488, 1389], ante: 48, hero: 0, raiseMultiples: [1.5, 2.2, 4.0]),
        '77',
      ),
    _ => (
        PreflopSpec(
          stacks: [1741, 2692, 1449, 2566],
          ante: 25,
          hero: 1,
          raiseMultiples: [2.2, 2.5, 3.0, 5.0, 6.0],
          history: [const PreflopAction(PreflopMove.raise, 305)],
        ),
        'JJ',
      ),
  };
  final hand = [for (var h = 0; h < handClassCount; h++) h].firstWhere((h) => handClassName(h) == name);
  for (final iterations in [300, 1000, 3000]) {
    final s = PreflopSolver(PreflopTree(spec), equity).solve(iterations: iterations);
    final root = s.tree.root as PreflopDecision;
    stdout.writeln('$iterations: ${[
      for (var a = 0; a < root.actions.length; a++)
        '${root.actions[a]} ${(s.frequency(root, a, hand) * 100).round()}% '
            '${(s.value(root, a, hand) / 100).toStringAsFixed(2)}',
    ].join(' | ')}');
  }
}
