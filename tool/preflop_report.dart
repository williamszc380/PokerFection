// Solves a preflop game and prints the first-in ranges, for checking results.
//
// Run from the project root:
//   dart run tool/preflop_report.dart [players] [stack in BB] [iterations] [threads] [hero]
//
// hero: the player (in preflop order, 0 = first to act) with the full menu, or -1.
import 'dart:io';
import 'dart:typed_data';

import 'package:pokerfection/src/engine/positions.dart';
import 'package:pokerfection/src/gto/hand_classes.dart';
import 'package:pokerfection/src/gto/preflop/parallel_preflop_solver.dart';
import 'package:pokerfection/src/gto/preflop/preflop_equity.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tree.dart';

Future<void> main(List<String> args) async {
  final players = args.isNotEmpty ? int.parse(args[0]) : 6;
  final stackBb = args.length > 1 ? int.parse(args[1]) : 100;
  final iterations = args.length > 2 ? int.parse(args[2]) : 200;
  final threads = args.length > 3 ? int.parse(args[3]) : 1;
  final hero = args.length > 4 ? int.parse(args[4]) : -1;

  final equity =
      PreflopEquity.fromBytes(ByteData.sublistView(File('assets/preflop_equity.bin').readAsBytesSync()));
  final spec = PreflopSpec(stacks: List.filled(players, stackBb * 100), hero: hero);
  final watch = Stopwatch()..start();
  final solution = await solvePreflopInParallel(spec, equity, iterations: iterations, threads: threads);
  final tree = solution.tree;
  stdout.writeln('$players players, $stackBb BB, hero $hero, ${tree.decisions.length} decisions, '
      '$iterations iterations, $threads threads: ${watch.elapsedMilliseconds} ms\n');

  final names = positionsForTable(players);
  PreflopNode node = tree.root;
  while (node is PreflopDecision) {
    final d = node;
    final parts = <String>[];
    for (var i = 0; i < d.actions.length; i++) {
      var share = 0.0;
      for (var h = 0; h < handClassCount; h++) {
        share += solution.frequency(d, i, h) * handClassCombos(h) / 1326;
      }
      parts.add('${d.actions[i]} ${(share * 100).toStringAsFixed(1)}%');
    }
    stdout.writeln('${names[d.player].label.padRight(6)} first in: ${parts.join(', ')}');
    final fold = d.actions.indexWhere((a) => a.move == PreflopMove.fold || a.move == PreflopMove.check);
    if (fold < 0) break;
    node = d.children[fold];
  }

  // 13x13 grid of the first player's raise frequency (A top-left, suited above the diagonal).
  final first = tree.root as PreflopDecision;
  stdout.writeln('\n${names.first.label} raise % (suited top-right, offsuit bottom-left):');
  for (var row = 12; row >= 0; row--) {
    final line = StringBuffer();
    for (var col = 12; col >= 0; col--) {
      final hand = row == col
          ? handClassIndex(row, col, suited: false)
          : handClassIndex(row, col, suited: col < row);
      var raise = 0.0;
      for (var i = 0; i < first.actions.length; i++) {
        final move = first.actions[i].move;
        if (move == PreflopMove.raise || move == PreflopMove.allIn) raise += solution.frequency(first, i, hand);
      }
      line.write((raise * 100).round().toString().padLeft(4));
    }
    stdout.writeln(line);
  }
}
