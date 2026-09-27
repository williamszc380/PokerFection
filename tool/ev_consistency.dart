// Checks that choices the solver never makes don't look better than the
// ones it does: for every hand at the user's first decision, compares the
// best value among actions it takes (5%+) with the best among the rest.
//
// Run from the project root:  dart run tool/ev_consistency.dart [iterations]
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pokerfection/src/engine/cards.dart';
import 'package:pokerfection/src/gto/combos.dart';
import 'package:pokerfection/src/gto/hand_classes.dart';
import 'package:pokerfection/src/gto/postflop/parallel_postflop_solver.dart';
import 'package:pokerfection/src/gto/postflop/postflop_tree.dart';
import 'package:pokerfection/src/gto/preflop/parallel_preflop_solver.dart';
import 'package:pokerfection/src/gto/preflop/preflop_equity.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tree.dart';

Future<void> main(List<String> args) async {
  final iterations = args.isNotEmpty ? int.parse(args.first) : 120;
  final equity =
      PreflopEquity.fromBytes(ByteData.sublistView(File('assets/preflop_equity.bin').readAsBytesSync()));

  // Preflop: the user's first decision at each seat of a 6-max table.
  const fold = PreflopAction(PreflopMove.fold);
  for (var hero = 0; hero < 5; hero++) {
    final s = await solvePreflopInParallel(
        PreflopSpec(stacks: List.filled(6, 10000), hero: hero, history: List.filled(hero, fold)), equity,
        iterations: 200, threads: 12);
    final root = s.tree.root as PreflopDecision;
    final gaps = [
      for (var h = 0; h < handClassCount; h++)
        _gap([for (var a = 0; a < root.actions.length; a++) (s.frequency(root, a, h), s.value(root, a, h) / 100)]),
    ];
    _report('preflop seat $hero', gaps, 'BB');
  }

  // Postflop: button vs big blind on each street, the user in either seat.
  final rng = Random(3);
  for (final board in ['Kh 9d 4c', 'Kh 9d 4c 2s', 'Kh 9d 4c 2s 7h']) {
    final cards = [for (final c in parseCards(board)) c.index];
    Float64List range(double keep) => Float64List.fromList([
          for (var c = 0; c < comboCount; c++)
            cards.contains(comboLow[c]) || cards.contains(comboHigh[c]) || rng.nextDouble() > keep ? 0 : 1,
        ]);
    final ranges = [range(0.6), range(0.4)];
    for (final hero in [0, 1]) {
      final spec = PostflopSpec(board: cards, pot: 550, stacks: [9750, 9750], bigBlind: 100, hero: hero);
      final s = await solvePostflopInParallel(spec, ranges, iterations: iterations, threads: 12);
      // The user's first decision: the root, or after the bot checks.
      var node = s.tree.root as PostflopDecision;
      if (node.player != hero) {
        node = node.children[node.actions.indexWhere((a) => a.move == PostflopMove.check)] as PostflopDecision;
      }
      final n = s.hands.length;
      final gaps = <double>[];
      for (var c = 0; c < n; c++) {
        if (ranges[hero][s.hands.full[c]] == 0) continue;
        gaps.add(_gap([
          for (var a = 0; a < node.actions.length; a++)
            (s.strategy[node.offset + a * n + c].toDouble(), s.values[node.offset + a * n + c] / 550),
        ]));
      }
      _report('${board.split(' ').length}-card board, user ${hero == 0 ? 'first' : 'last'}', gaps, 'pots');
    }
  }
}

/// How much better the best action the hand never takes looks than the best
/// one it does take (0 if it doesn't look better).
double _gap(List<(double, double)> actions) {
  var used = double.negativeInfinity, unused = double.negativeInfinity;
  for (final (frequency, value) in actions) {
    if (value.isNaN) continue;
    if (frequency >= 0.05) {
      used = max(used, value);
    } else {
      unused = max(unused, value);
    }
  }
  return used.isInfinite || unused.isInfinite ? 0 : max(0, unused - used);
}

void _report(String label, List<double> gaps, String unit) {
  gaps.sort();
  final worst = gaps.last;
  final share = gaps.where((g) => g > 0.05).length / gaps.length;
  stdout.writeln('$label: unused choice looks better by >0.05 $unit for ${(share * 100).toStringAsFixed(1)}% '
      'of hands; median ${gaps[gaps.length ~/ 2].toStringAsFixed(3)}, worst ${worst.toStringAsFixed(3)} $unit');
}
