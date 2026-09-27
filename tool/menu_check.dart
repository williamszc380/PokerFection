// AA/KK/AKs at the first decision of the user's subgame, with different
// raise menus, to see which choices make the solve drift.
import 'dart:io';
import 'dart:typed_data';

import 'package:pokerfection/src/gto/hand_classes.dart';
import 'package:pokerfection/src/gto/preflop/parallel_preflop_solver.dart';
import 'package:pokerfection/src/gto/preflop/preflop_equity.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tree.dart';

Future<void> main(List<String> args) async {
  final players = args.isNotEmpty ? int.parse(args[0]) : 6;
  final iterations = args.length > 1 ? int.parse(args[1]) : 200;
  final equity =
      PreflopEquity.fromBytes(ByteData.sublistView(File('assets/preflop_equity.bin').readAsBytesSync()));
  for (final menu in [
    [2.5],
    [2.5, 4.0],
    [2.0, 2.5, 3.0, 4.0],
  ]) {
    final s = await solvePreflopInParallel(
        PreflopSpec(stacks: List.filled(players, 10000), hero: 0, raiseMultiples: menu), equity,
        iterations: iterations, threads: 12);
    final root = s.tree.root as PreflopDecision;
    final overall = [
      for (var a = 0; a < root.actions.length; a++)
        [for (var h = 0; h < handClassCount; h++) s.frequency(root, a, h) * handClassCombos(h) / 1326]
            .reduce((x, y) => x + y),
    ];
    stdout.writeln('menu $menu: overall ${[
      for (var a = 0; a < root.actions.length; a++) '${root.actions[a]} ${(overall[a] * 100).toStringAsFixed(1)}%'
    ].join(', ')}');
    for (final name in ['AA', 'KK', 'AKs', 'T9s']) {
      final h = [for (var i = 0; i < handClassCount; i++) i].firstWhere((i) => handClassName(i) == name);
      stdout.writeln('  $name: ${[
        for (var a = 0; a < root.actions.length; a++)
          '${(s.frequency(root, a, h) * 100).round()}% ${(s.value(root, a, h) / 100).toStringAsFixed(2)}'
      ].join(' | ')}');
    }
  }
}
