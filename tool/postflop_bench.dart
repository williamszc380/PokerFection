// Times postflop street solves with realistic ranges: the button opens,
// the big blind calls (6 players, 100 bb), from the preflop solution.
//
// Run from the project root:  dart run tool/postflop_bench.dart [iterations]
import 'dart:io';
import 'dart:typed_data';

import 'package:pokerfection/src/engine/cards.dart';
import 'package:pokerfection/src/gto/combos.dart';
import 'package:pokerfection/src/gto/postflop/parallel_postflop_solver.dart';
import 'package:pokerfection/src/gto/postflop/postflop_tree.dart';
import 'package:pokerfection/src/gto/preflop/preflop_equity.dart';
import 'package:pokerfection/src/gto/preflop/preflop_solver.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tree.dart';

Future<void> main(List<String> args) async {
  final iterations = args.isNotEmpty ? int.parse(args.first) : 120;
  final threadCount = args.length > 1 ? int.parse(args[1]) : 12;
  final equity =
      PreflopEquity.fromBytes(ByteData.sublistView(File('assets/preflop_equity.bin').readAsBytesSync()));
  final tree = PreflopTree(PreflopSpec(stacks: List.filled(6, 10000)));
  final preflop = PreflopSolver(tree, equity).solve(iterations: 150);

  // Walk: UTG, HJ, CO fold; BTN raises; SB folds; BB calls.
  var node = tree.root as PreflopDecision;
  final path = <(PreflopDecision, int)>[];
  PreflopDecision step(PreflopMove move) {
    final i = node.actions.indexWhere((a) => a.move == move);
    path.add((node, i));
    return node = node.children[i] as PreflopDecision;
  }

  step(PreflopMove.fold);
  step(PreflopMove.fold);
  step(PreflopMove.fold);
  step(PreflopMove.raise);
  step(PreflopMove.fold);
  final bbNode = node;
  final bbCall = bbNode.actions.indexWhere((a) => a.move == PreflopMove.call);
  path.add((bbNode, bbCall));

  Float64List range(int player) {
    final classes = List.filled(169, 1.0);
    for (final (n, a) in path) {
      if (n.player != player) continue;
      for (var h = 0; h < 169; h++) {
        classes[h] *= preflop.frequency(n, a, h);
      }
    }
    return Float64List.fromList([for (var c = 0; c < comboCount; c++) classes[comboClass[c]]]);
  }

  final bb = range(5), button = range(3);
  stdout.writeln('BB calls with ${(bb.reduce((a, b) => a + b) / comboCount * 100).toStringAsFixed(0)}% of hands, '
      'button opened ${(button.reduce((a, b) => a + b) / comboCount * 100).toStringAsFixed(0)}%');

  for (final (name, board) in [
    ('flop ', 'Kh 9d 4c'),
    ('turn ', 'Kh 9d 4c 2s'),
    ('river', 'Kh 9d 4c 2s 7h'),
  ]) {
    // No user (bots only), the user out of position (big blind), in position (button).
    for (final hero in [-1, 0, 1]) {
      final spec = PostflopSpec(
        board: [for (final c in parseCards(board)) c.index],
        pot: 550,
        stacks: [9750, 9750],
        bigBlind: 100,
        hero: hero,
      );
      final watch = Stopwatch()..start();
      final solution = await solvePostflopInParallel(spec, [bb, button], iterations: iterations, threads: threadCount);
      stdout.writeln('$name user $hero: ${solution.tree.decisions.length} decisions, '
          '$threadCount threads: ${watch.elapsedMilliseconds} ms');
    }
  }
}
