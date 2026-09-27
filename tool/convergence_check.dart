// How much the answers at the user's first decision change with more
// solver iterations: compares 50/100/200 iterations against 400.
//
// Run from the project root:  dart run tool/convergence_check.dart [players] [hero] [threads]
import 'dart:io';
import 'dart:typed_data';

import 'package:pokerfection/src/gto/hand_classes.dart';
import 'package:pokerfection/src/gto/preflop/parallel_preflop_solver.dart';
import 'package:pokerfection/src/gto/preflop/preflop_equity.dart';
import 'package:pokerfection/src/gto/preflop/preflop_solver.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tree.dart';

Future<void> main(List<String> args) async {
  final players = args.isNotEmpty ? int.parse(args[0]) : 6;
  final hero = args.length > 1 ? int.parse(args[1]) : 0;
  final threads = args.length > 2 ? int.parse(args[2]) : 12;
  final equity =
      PreflopEquity.fromBytes(ByteData.sublistView(File('assets/preflop_equity.bin').readAsBytesSync()));
  final spec = PreflopSpec(
    stacks: List.filled(players, 10000),
    hero: hero,
    history: List.filled(hero, const PreflopAction(PreflopMove.fold)),
  );
  Future<PreflopSolution> solve(int iterations) =>
      solvePreflopInParallel(spec, equity, iterations: iterations, threads: threads);

  final reference = await solve(400);
  final root = reference.tree.root as PreflopDecision;
  stdout.writeln('Root actions: ${root.actions.join(', ')}');
  for (final iterations in [50, 100, 200]) {
    final s = await solve(iterations);
    var mixDiff = 0.0, worstMix = 0.0, evLoss = 0.0, worstLoss = 0.0;
    for (var h = 0; h < handClassCount; h++) {
      final weight = handClassCombos(h) / 1326;
      var diff = 0.0;
      // EV lost by playing this solve's mix instead of the reference's best action.
      var best = double.negativeInfinity, mine = 0.0;
      for (var a = 0; a < root.actions.length; a++) {
        diff += (s.frequency(root, a, h) - reference.frequency(root, a, h)).abs() / 2;
        final v = reference.value(root, a, h);
        if (v > best) best = v;
      }
      for (var a = 0; a < root.actions.length; a++) {
        mine += s.frequency(root, a, h) * reference.value(root, a, h);
      }
      final loss = (best - mine) / 100;
      mixDiff += weight * diff;
      evLoss += weight * loss;
      if (diff > worstMix) worstMix = diff;
      if (loss > worstLoss) worstLoss = loss;
    }
    stdout.writeln('$iterations iterations: mix differs ${(mixDiff * 100).toStringAsFixed(1)}% on average '
        '(worst hand ${(worstMix * 100).toStringAsFixed(0)}%), EV lost vs the 400-iteration values '
        '${evLoss.toStringAsFixed(3)} BB on average (worst ${worstLoss.toStringAsFixed(3)} BB)');
  }
  // How far from best the reference itself is (its own mixed hands).
  var selfLoss = 0.0;
  for (var h = 0; h < handClassCount; h++) {
    var best = double.negativeInfinity, mine = 0.0;
    for (var a = 0; a < root.actions.length; a++) {
      final v = reference.value(root, a, h);
      if (v > best) best = v;
      mine += reference.frequency(root, a, h) * v;
    }
    selfLoss += handClassCombos(h) / 1326 * (best - mine) / 100;
  }
  stdout.writeln('400 iterations vs its own values: ${selfLoss.toStringAsFixed(3)} BB on average');
  worstHands(reference);
}

/// Prints the hands whose mix in [s] loses the most against their own values.
void worstHands(PreflopSolution s, {int count = 5}) {
  final root = s.tree.root as PreflopDecision;
  final losses = <(double, int)>[];
  for (var h = 0; h < handClassCount; h++) {
    var best = double.negativeInfinity, mine = 0.0;
    for (var a = 0; a < root.actions.length; a++) {
      final v = s.value(root, a, h);
      if (v > best) best = v;
      mine += s.frequency(root, a, h) * v;
    }
    losses.add(((best - mine) / 100, h));
  }
  losses.sort((a, b) => b.$1.compareTo(a.$1));
  for (final (loss, h) in losses.take(count)) {
    final parts = [
      for (var a = 0; a < root.actions.length; a++)
        '${root.actions[a]} ${(s.frequency(root, a, h) * 100).round()}% '
            '${(s.value(root, a, h) / 100).toStringAsFixed(2)}',
    ];
    stdout.writeln('${handClassName(h)} loses ${loss.toStringAsFixed(2)} BB: ${parts.join(' | ')}');
  }
}
