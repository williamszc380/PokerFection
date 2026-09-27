// Solves the whole preflop game for 2 to 8 players at a few stack depths and
// saves the charts for the Preflop Charts screen: for each position, how
// often each starting hand folds, checks or calls, and raises (any size,
// all-in included) when first in, facing an open, and facing a 3-bet after
// opening. Everyone not in the spot folds.
//
// Run from the project root (takes a while):
//   dart run tool/make_charts.dart [iterations] [threads]
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pokerfection/src/engine/positions.dart';
import 'package:pokerfection/src/gto/hand_classes.dart';
import 'package:pokerfection/src/gto/preflop/parallel_preflop_solver.dart';
import 'package:pokerfection/src/gto/preflop/preflop_equity.dart';
import 'package:pokerfection/src/gto/preflop/preflop_solver.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tree.dart';
import 'package:pokerfection/src/gto/spot_strategy.dart';

const stacks = [100, 50, 25];

Future<void> main(List<String> args) async {
  final iterations = args.isNotEmpty ? int.parse(args[0]) : 400;
  final threads = args.length > 1 ? int.parse(args[1]) : Platform.numberOfProcessors;
  final equity =
      PreflopEquity.fromBytes(ByteData.sublistView(File('assets/preflop_equity.bin').readAsBytesSync()));
  final charts = <String, String>{};
  for (final stackBb in stacks) {
    for (var players = 2; players <= 8; players++) {
      final watch = Stopwatch()..start();
      final spec = PreflopSpec(stacks: List.filled(players, stackBb * 100));
      final solution = await solvePreflopInParallel(spec, equity, iterations: iterations, threads: threads);
      final found = _charts(solution, '$stackBb/$players');
      charts.addAll(found);
      stdout.writeln('$stackBb BB, $players players: ${found.length} charts, ${watch.elapsed.inSeconds} s');
    }
  }
  File('assets/preflop_charts.json').writeAsStringSync(jsonEncode({
    'iterations': iterations,
    'charts': charts,
  }));
  stdout.writeln('${charts.length} charts saved');
}

/// Every chart of one solved game, keyed `<stack>/<players>/<hero>/<spot>[/<villain>]`
/// with positions by name ("btn") and spots "open", "vsOpen" and "vs3bet".
Map<String, String> _charts(PreflopSolution solution, String prefix) {
  final n = solution.tree.spec.players;
  final positions = positionsForTable(n);
  final bigBlind = n - 1;
  final charts = <String, String>{};
  void add(int hero, String spot, int? villain, List<PreflopMove> moves) {
    final chart = _chart(solution, hero, moves);
    if (chart == null) return;
    final key = [prefix, positions[hero].name, spot, if (villain != null) positions[villain].name].join('/');
    charts[key] = chart;
  }

  List<PreflopMove> folds(int count) => List.filled(count, PreflopMove.fold);
  const raise = PreflopMove.raise;
  for (var hero = 0; hero < n; hero++) {
    if (hero != bigBlind) add(hero, 'open', null, folds(hero));
    for (var opener = 0; opener < hero; opener++) {
      add(hero, 'vsOpen', opener, [...folds(opener), raise, ...folds(hero - opener - 1)]);
    }
    if (hero == bigBlind) continue;
    for (var threeBettor = hero + 1; threeBettor < n; threeBettor++) {
      add(hero, 'vs3bet', threeBettor, [
        ...folds(hero),
        raise,
        ...folds(threeBettor - hero - 1),
        raise,
        ...folds(n - 1 - threeBettor),
      ]);
    }
  }
  return charts;
}

/// [hero]'s chart after [moves]: per starting hand, three bytes: how often
/// the hand gets there (the hero's own earlier choices; 0 = not in the
/// range), and how often it checks or calls and raises there (percent; the
/// rest folds). Base64. Null if the game has no such line.
String? _chart(PreflopSolution solution, int hero, List<PreflopMove> moves) {
  var node = solution.tree.root;
  final reach = List.filled(handClassCount, 1.0);
  for (final move in moves) {
    if (node is! PreflopDecision) return null;
    final action = node.actions.indexWhere((a) => a.move == move);
    if (action < 0) return null;
    if (node.player == hero) {
      for (var h = 0; h < handClassCount; h++) {
        reach[h] *= solution.frequency(node, action, h);
      }
    }
    node = node.children[action];
  }
  if (node is! PreflopDecision || node.player != hero) return null;
  final bytes = Uint8List(handClassCount * 3);
  for (var h = 0; h < handClassCount; h++) {
    final mix = [0.0, 0.0, 0.0];
    for (var a = 0; a < node.actions.length; a++) {
      final kind = switch (node.actions[a].move) {
        PreflopMove.fold => 0,
        PreflopMove.check || PreflopMove.call => 1,
        PreflopMove.raise || PreflopMove.allIn => 2,
      };
      mix[kind] += solution.frequency(node, a, h);
    }
    final percents = mix.any((f) => f > 0) ? splitWhole(mix, 100) : const [100, 0, 0];
    bytes[h * 3] = (reach[h] * 100).round();
    bytes[h * 3 + 1] = percents[1];
    bytes[h * 3 + 2] = percents[2];
  }
  return base64Encode(bytes);
}
