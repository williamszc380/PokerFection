// How the second player responds to a jam by the first, in the whole game
// and in the user's subgame (user first to act).
import 'dart:io';
import 'dart:typed_data';

import 'package:pokerfection/src/gto/hand_classes.dart';
import 'package:pokerfection/src/gto/preflop/parallel_preflop_solver.dart';
import 'package:pokerfection/src/gto/preflop/preflop_equity.dart';
import 'package:pokerfection/src/gto/preflop/preflop_solver.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tree.dart';

Future<void> main(List<String> args) async {
  final players = args.isNotEmpty ? int.parse(args[0]) : 6;
  final iterations = args.length > 1 ? int.parse(args[1]) : 200;
  final equity =
      PreflopEquity.fromBytes(ByteData.sublistView(File('assets/preflop_equity.bin').readAsBytesSync()));
  final stacks = List.filled(players, 10000);

  void show(String label, PreflopSolution s) {
    final root = s.tree.root as PreflopDecision;
    final jam = root.actions.indexWhere((a) => a.move == PreflopMove.allIn);
    var jamShare = 0.0;
    for (var h = 0; h < handClassCount; h++) {
      jamShare += s.frequency(root, jam, h) * handClassCombos(h) / 1326;
    }
    final next = root.children[jam] as PreflopDecision;
    final call = next.actions.indexWhere((a) => a.move == PreflopMove.call);
    final callers = <String>[];
    var callShare = 0.0;
    for (var h = 0; h < handClassCount; h++) {
      final f = s.frequency(next, call, h);
      callShare += f * handClassCombos(h) / 1326;
      if (f > 0.2) callers.add('${handClassName(h)} ${(f * 100).round()}%');
    }
    stdout.writeln('$label: first player jams ${(jamShare * 100).toStringAsFixed(2)}%; '
        'next calls ${(callShare * 100).toStringAsFixed(1)}%: ${callers.join(', ')}');
  }

  show('whole  ', await solvePreflopInParallel(PreflopSpec(stacks: stacks), equity,
      iterations: iterations, threads: 12));
  show('subgame', await solvePreflopInParallel(PreflopSpec(stacks: stacks, hero: 0), equity,
      iterations: iterations, threads: 12));
}
