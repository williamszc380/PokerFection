// Prints how big the preflop trees are: the whole game, and the subgames
// solved at the user's decision (everyone before folds to them; or, in the
// big blind, facing a button open).
//
// Run from the project root:  dart run tool/tree_sizes.dart [stack in BB]
import 'dart:io';

import 'package:pokerfection/src/engine/positions.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tree.dart';

void main(List<String> args) {
  final stackBb = args.isNotEmpty ? int.parse(args.first) : 100;
  const fold = PreflopAction(PreflopMove.fold);
  for (var players = 2; players <= 8; players++) {
    final names = positionsForTable(players);
    final stacks = List.filled(players, stackBb * 100);
    final whole = PreflopTree(PreflopSpec(stacks: stacks));
    final line = StringBuffer('${players}p: whole ${whole.decisions.length}');
    for (var hero = 0; hero < players - 1; hero++) {
      final tree = PreflopTree(PreflopSpec(stacks: stacks, hero: hero, history: List.filled(hero, fold)));
      line.write('  ${names[hero].label} ${tree.decisions.length}');
    }
    if (players > 2) {
      // Big blind facing a button open to 2.5 BB (small blind folds).
      final history = [...List.filled(players - 3, fold), const PreflopAction(PreflopMove.raise, 250), fold];
      final tree = PreflopTree(PreflopSpec(stacks: stacks, hero: players - 1, history: history));
      line.write('  BB-vs-BTN ${tree.decisions.length}');
    }
    stdout.writeln(line);
  }
}
