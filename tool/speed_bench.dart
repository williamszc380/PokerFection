// How long the solves take, for 2 to 8 players at 100 BB, with the app's
// settings (at most 12 threads, 200 preflop iterations, 120 on the flop and
// turn, 300 on the river):
// - the whole preflop game, and the first player's subgame (as the app
//   does it: with 6 or more players, warm-started from the game, 64
//   iterations);
// - the next hand's game (one player won 6 BB), warm-started from this one
//   with 64 iterations, as the app does;
// - the flop, turn and river after an open and the big blind's call;
// - with 3 or more players, the flop of a 3-way pot (open, cold call, big
//   blind call), played against the field (strongestOfField).
//
// It also keeps a fingerprint of every answer (how often each action at
// the first decision is taken, over the range), to check that a faster
// solver still gives the same strategies:
//   dart run tool/speed_bench.dart --save build/bench_before.json
//   dart run tool/speed_bench.dart --check build/bench_before.json
// Options: --players 2-8 (or one count), --runs N (median time), --threads N.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pokerfection/src/engine/cards.dart';
import 'package:pokerfection/src/gto/combos.dart';
import 'package:pokerfection/src/gto/hand_classes.dart';
import 'package:pokerfection/src/gto/postflop/parallel_postflop_solver.dart';
import 'package:pokerfection/src/gto/postflop/postflop_solver.dart';
import 'package:pokerfection/src/gto/postflop/postflop_tree.dart';
import 'package:pokerfection/src/gto/preflop/parallel_preflop_solver.dart';
import 'package:pokerfection/src/gto/preflop/preflop_equity.dart';
import 'package:pokerfection/src/gto/preflop/preflop_solver.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tree.dart';

const bb = 100;

late final PreflopEquity equity;
late final int threads;
late final int runs;
final times = <String, int>{};
final prints = <String, List<double>>{};

Future<void> main(List<String> args) async {
  String? option(String name) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final players = (option('--players') ?? '2-8').split('-').map(int.parse).toList();
  final counts = [for (var p = players.first; p <= players.last; p++) p];
  runs = int.parse(option('--runs') ?? '1');
  threads = int.parse(option('--threads') ?? '${min(max(Platform.numberOfProcessors - 1, 1), 12)}');
  equity = PreflopEquity.fromBytes(ByteData.sublistView(File('assets/preflop_equity.bin').readAsBytesSync()));
  stdout.writeln('threads $threads, runs $runs');

  for (final n in counts) {
    await _table(n);
  }
  final total = times.values.fold(0, (a, b) => a + b);
  stdout.writeln('\nTotal ${(total / 1000).toStringAsFixed(1)} s');

  if (option('--save') case final path?) {
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({'times': times, 'prints': prints}));
    stdout.writeln('Saved $path');
  }
  if (option('--check') case final path?) {
    final before = jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
    final oldTimes = (before['times'] as Map).cast<String, int>();
    final oldPrints = (before['prints'] as Map).map((k, v) => MapEntry(k as String, (v as List).cast<num>()));
    stdout.writeln('\n${'solve'.padRight(26)} before    after  speed-up  largest change');
    var oldTotal = 0, newTotal = 0;
    for (final key in times.keys) {
      final was = oldTimes[key], now = times[key]!;
      final a = oldPrints[key], b = prints[key]!;
      var diff = 0.0;
      if (a != null && a.length == b.length) {
        for (var i = 0; i < a.length; i++) {
          diff = max(diff, (a[i] - b[i]).abs());
        }
      }
      if (was != null) {
        oldTotal += was;
        newTotal += now;
      }
      stdout.writeln('${key.padRight(26)} ${'${was ?? '-'}'.padLeft(6)} ${'$now'.padLeft(8)}  '
          '${was == null ? '' : '${(was / now).toStringAsFixed(2)}x'.padLeft(8)}  '
          '${a == null ? '-' : diff.toStringAsFixed(3)}');
    }
    stdout.writeln('${'all'.padRight(26)} ${'$oldTotal'.padLeft(6)} ${'$newTotal'.padLeft(8)}  '
        '${(oldTotal / newTotal).toStringAsFixed(2)}x');
  }
}

/// Times [solve] ([runs] times, the median) and keeps its answer's fingerprint.
Future<T> _timed<T>(String key, Future<T> Function() solve, List<double> Function(T) fingerprint) async {
  final took = <int>[];
  late T result;
  for (var r = 0; r < runs; r++) {
    final watch = Stopwatch()..start();
    result = await solve();
    took.add(watch.elapsedMilliseconds);
  }
  took.sort();
  times[key] = took[took.length ~/ 2];
  prints[key] = fingerprint(result);
  stdout.writeln('  ${key.padRight(24)} ${times[key]} ms');
  return result;
}

/// How often each action at the first decision is taken, over the range
/// (by combinations), then the range's average value of each.
List<double> _preflopPrint(PreflopSolution s) {
  final root = s.tree.root as PreflopDecision;
  return [
    for (var a = 0; a < root.actions.length; a++)
      [for (var h = 0; h < handClassCount; h++) s.frequency(root, a, h) * handClassCombos(h)].reduce((x, y) => x + y) /
          comboCount,
  ];
}

List<double> _postflopPrint(PostflopSolution s, Float64List range) {
  final root = s.tree.root as PostflopDecision;
  var total = 0.0;
  for (var c = 0; c < comboCount; c++) {
    if (s.hands.compact[c] >= 0) total += range[c];
  }
  return [
    for (var a = 0; a < root.actions.length; a++)
      [
        for (var c = 0; c < comboCount; c++)
          if (s.hands.compact[c] >= 0) range[c] * s.frequency(root, a, c),
      ].fold(0.0, (x, y) => x + y) /
          total,
  ];
}

Future<void> _table(int n) async {
  stdout.writeln('\n$n players');
  final stacks = List.filled(n, 100 * bb);
  final game = await _timed('${n}p preflop game', () => solvePreflopInParallel(PreflopSpec(stacks: stacks), equity,
      iterations: 200, threads: threads), _preflopPrint);
  final warmSubgame = n >= 6;
  await _timed('${n}p preflop subgame', () => solvePreflopInParallel(PreflopSpec(stacks: stacks, hero: 0), equity,
      iterations: warmSubgame ? 64 : 200, threads: threads, warmFrom: warmSubgame ? game : null), _preflopPrint);
  final next = [...stacks]..[0] += 6 * bb..[n - 1] -= 6 * bb;
  await _timed('${n}p next hand game', () => solvePreflopInParallel(PreflopSpec(stacks: next), equity,
      iterations: 64, threads: threads, warmFrom: game), _preflopPrint);

  // Postflop: the first player opens, the others fold, the big blind calls
  // (heads-up: the button opens, the big blind calls).
  final line = _walk(game, [PreflopMove.raise, for (var k = 1; k < n - 1; k++) PreflopMove.fold, PreflopMove.call]);
  final open = line.raiseTo;
  final pot = 2 * open + (n > 2 ? bb ~/ 2 : 0);
  final behind = 100 * bb - open;
  final bbRange = line.range(n - 1), openerRange = line.range(0);
  for (final (street, board, iterations) in [
    ('flop', 'Kh 9d 4c', 120),
    ('turn', 'Kh 9d 4c 2s', 120),
    ('river', 'Kh 9d 4c 2s 7h', 300),
  ]) {
    final spec = PostflopSpec(
      board: [for (final c in parseCards(board)) c.index],
      pot: pot,
      stacks: [behind, behind],
      bigBlind: bb,
      hero: 0,
    );
    await _timed('${n}p $street', () => solvePostflopInParallel(spec, [bbRange, openerRange],
        iterations: iterations, threads: threads), (s) => _postflopPrint(s, bbRange));
  }

  // A 3-way pot: open, cold call, big blind call; the big blind against the field.
  if (n >= 3) {
    final three = _walk(game, [
      PreflopMove.raise,
      PreflopMove.call,
      for (var k = 2; k < n - 1; k++) PreflopMove.fold,
      PreflopMove.call,
    ]);
    final board = [for (final c in parseCards('Kh 9d 4c')) c.index];
    final spec = PostflopSpec(
      board: board,
      pot: 3 * three.raiseTo + (n > 3 ? bb ~/ 2 : 0),
      stacks: [100 * bb - three.raiseTo, 100 * bb - three.raiseTo],
      bigBlind: bb,
      hero: 0,
    );
    final bbRange3 = three.range(n - 1);
    await _timed('${n}p 3-way flop', () async {
      final field = strongestOfField(board, [three.range(0), three.range(1)]);
      return solvePostflopInParallel(spec, [bbRange3, field], iterations: 120, threads: threads);
    }, (s) => _postflopPrint(s, bbRange3));
  }
}

/// A preflop line through the whole game (raises at the bots' size): each
/// player's range (by combination) and the raise's size.
({int raiseTo, Float64List Function(int player) range}) _walk(PreflopSolution game, List<PreflopMove> moves) {
  PreflopNode node = game.tree.root;
  final n = game.tree.spec.players;
  final classes = List.generate(n, (_) => Float64List(handClassCount)..fillRange(0, handClassCount, 1));
  var raiseTo = 0;
  for (final m in moves) {
    final at = node as PreflopDecision;
    final i = at.actions.indexWhere((a) => a.move == m);
    if (i < 0) throw StateError('No $m');
    if (m == PreflopMove.raise) raiseTo = at.actions[i].raiseTo;
    for (var h = 0; h < handClassCount; h++) {
      classes[at.player][h] *= game.frequency(at, i, h);
    }
    node = at.children[i];
  }
  return (
    raiseTo: raiseTo,
    range: (p) => Float64List.fromList([for (var c = 0; c < comboCount; c++) classes[p][comboClass[c]]]),
  );
}
