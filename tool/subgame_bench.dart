// Times the preflop solves one hand needs: the whole game (for the bots)
// and the subgame at the user's first decision when everyone folds to them.
//
// Run from the project root:
//   dart run tool/subgame_bench.dart [players] [stack in BB] [iterations] [threads]
import 'dart:io';
import 'dart:typed_data';

import 'package:pokerfection/src/engine/positions.dart';
import 'package:pokerfection/src/gto/preflop/parallel_preflop_solver.dart';
import 'package:pokerfection/src/gto/preflop/preflop_equity.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tree.dart';

Future<void> main(List<String> args) async {
  final players = args.isNotEmpty ? int.parse(args[0]) : 6;
  final stackBb = args.length > 1 ? int.parse(args[1]) : 100;
  final iterations = args.length > 2 ? int.parse(args[2]) : 200;
  final threads = args.length > 3 ? int.parse(args[3]) : 12;
  final equity =
      PreflopEquity.fromBytes(ByteData.sublistView(File('assets/preflop_equity.bin').readAsBytesSync()));
  final stacks = List.filled(players, stackBb * 100);
  final names = positionsForTable(players);
  const fold = PreflopAction(PreflopMove.fold);

  Future<void> time(String label, PreflopSpec spec) async {
    final watch = Stopwatch()..start();
    final solution = await solvePreflopInParallel(spec, equity, iterations: iterations, threads: threads);
    stdout.writeln('${label.padRight(12)} ${solution.tree.decisions.length.toString().padLeft(6)} decisions: '
        '${watch.elapsedMilliseconds} ms');
  }

  await time('whole game', PreflopSpec(stacks: stacks));
  for (var hero = 0; hero < players - 1; hero++) {
    await time('${names[hero].label} first', PreflopSpec(stacks: stacks, hero: hero, history: List.filled(hero, fold)));
  }
  if (players > 3) {
    // The second player facing an open from the first.
    await time('${names[1].label} vs open',
        PreflopSpec(stacks: stacks, hero: 1, history: const [PreflopAction(PreflopMove.raise, 250)]));
  }
}
