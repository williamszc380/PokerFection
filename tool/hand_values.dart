// Prints one hand's strategy and action values at the first decision, in
// the whole game and in the user's subgame when first to act.
//
// Run from the project root:  dart run tool/hand_values.dart [players] [hand] [iterations]
import 'dart:io';
import 'dart:typed_data';

import 'package:pokerfection/src/gto/hand_classes.dart';
import 'package:pokerfection/src/gto/preflop/parallel_preflop_solver.dart';
import 'package:pokerfection/src/gto/preflop/preflop_equity.dart';
import 'package:pokerfection/src/gto/preflop/preflop_solver.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tree.dart';

Future<void> main(List<String> args) async {
  final players = args.isNotEmpty ? int.parse(args[0]) : 6;
  final name = args.length > 1 ? args[1] : 'AA';
  final iterations = args.length > 2 ? int.parse(args[2]) : 200;
  final hand = [for (var h = 0; h < handClassCount; h++) h].firstWhere((h) => handClassName(h) == name);
  final equity =
      PreflopEquity.fromBytes(ByteData.sublistView(File('assets/preflop_equity.bin').readAsBytesSync()));
  final stacks = List.filled(players, 10000);

  void show(String label, PreflopSolution s) {
    final root = s.tree.root as PreflopDecision;
    final parts = [
      for (var a = 0; a < root.actions.length; a++)
        '${root.actions[a]} ${(s.frequency(root, a, hand) * 100).round()}% '
            '${(s.value(root, a, hand) / 100).toStringAsFixed(2)}',
    ];
    stdout.writeln('$label $name: ${parts.join(' | ')}');
  }

  show('whole  ', await solvePreflopInParallel(PreflopSpec(stacks: stacks), equity,
      iterations: iterations, threads: 12));
  show('subgame', await solvePreflopInParallel(PreflopSpec(stacks: stacks, hero: 0), equity,
      iterations: iterations, threads: 12));
}
