// Worst-converged hands at the first decision of the whole game (no user menu).
import 'dart:io';
import 'dart:typed_data';

import 'package:pokerfection/src/gto/preflop/parallel_preflop_solver.dart';
import 'package:pokerfection/src/gto/preflop/preflop_equity.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tree.dart';

import 'convergence_check.dart' show worstHands;

Future<void> main(List<String> args) async {
  final players = args.isNotEmpty ? int.parse(args[0]) : 6;
  final iterations = args.length > 1 ? int.parse(args[1]) : 200;
  final equity =
      PreflopEquity.fromBytes(ByteData.sublistView(File('assets/preflop_equity.bin').readAsBytesSync()));
  final s = await solvePreflopInParallel(PreflopSpec(stacks: List.filled(players, 10000)), equity,
      iterations: iterations, threads: 12);
  worstHands(s, count: 6);
}
