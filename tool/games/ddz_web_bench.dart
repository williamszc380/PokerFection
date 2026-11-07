// ignore_for_file: avoid_print

// The same Fight the Landlord workload on every platform, to compare the
// native build with the JavaScript one (no dart:io, so it compiles to JS):
//
//   dart run tool/games/ddz_web_bench.dart
//   dart compile exe tool/games/ddz_web_bench.dart -o build/ddz_bench.exe
//   dart compile js -O2 tool/games/ddz_web_bench.dart -o build/ddz_bench.js
//   node -e "globalThis.self=globalThis;require('./build/ddz_bench.js')"
//
// It times: rule-of-thumb self-play (moves per second), the coach at its
// default budget on 30 fixed decisions, and exact endgame solves.
import 'dart:math';

import 'package:pokerfection/src/games/doudizhu/bot.dart';
import 'package:pokerfection/src/games/doudizhu/coach.dart';
import 'package:pokerfection/src/games/doudizhu/game.dart';
import 'package:pokerfection/src/games/doudizhu/policy.dart';
import 'package:pokerfection/src/games/doudizhu/sim.dart';
import 'package:pokerfection/src/games/doudizhu/solver.dart';
import 'package:pokerfection/src/games/doudizhu/view.dart';

void main() {
  // Warm up (JIT and JS engines optimise hot code after a while).
  selfPlay(200);

  final sw = Stopwatch()..start();
  final moves = selfPlay(2000);
  final us = sw.elapsedMicroseconds;
  print('self-play: ${(us / moves).toStringAsFixed(2)} us per move (${(us / 2000 / 1000).toStringAsFixed(3)} ms per deal)');

  final times = <double>[];
  var checksum = 0.0;
  for (final view in decisions(30)) {
    final a = const DdzCoach().analyze(view, random: Random(1));
    times.add(a.elapsed.inMicroseconds / 1000);
    checksum += a.best.winChance;
  }
  times.sort();
  print('coach (default budget): avg ${(times.reduce((a, b) => a + b) / times.length).toStringAsFixed(1)} ms, '
      'median ${times[times.length ~/ 2].toStringAsFixed(1)} ms, max ${times.last.toStringAsFixed(1)} ms '
      '(checksum ${checksum.toStringAsFixed(4)})');

  final solveWatch = Stopwatch()..start();
  var nodes = 0, solved = 0;
  for (final sim in endgames(40, 20)) {
    final solver = DdzEndgameSolver(nodeLimit: 200000);
    if (solver.landlordWins(sim) != null) solved++;
    nodes += solver.nodes;
  }
  print('exact solves (<= 20 cards left): $solved of 40 in ${solveWatch.elapsedMilliseconds} ms, $nodes positions');
}

const _policy = HeuristicPolicy();

int selfPlay(int deals) {
  final rnd = Random(1);
  var moves = 0;
  for (var i = 0; i < deals; i++) {
    final g = DdzGame.deal(random: rnd)..act(const DdzBid(3));
    final sim = DdzSim.fromGame(g);
    while (!sim.over) {
      sim.apply(_policy.choose(simSituation(sim)));
      moves++;
    }
  }
  return moves;
}

/// Fixed decisions spread over the deal: the k-th stops after k * 3 moves.
List<DdzView> decisions(int n) {
  final out = <DdzView>[];
  final easy = DdzBot(DdzLevel.easy, random: Random(2));
  for (var i = 0; out.length < n; i++) {
    final g = DdzGame.deal(random: Random(1000 + i))..act(const DdzBid(3));
    final stopAt = (i * 3) % 36;
    var k = 0;
    while (g.phase == DdzPhase.playing) {
      final v = g.viewFor(g.toAct);
      if (k++ >= stopAt && v.legalMoves.length > 1) {
        out.add(v);
        break;
      }
      g.act(easy.chooseMove(v));
    }
  }
  return out;
}

/// Positions with at most [cards] cards left, reached by self-play.
List<DdzSim> endgames(int n, int cards) {
  final out = <DdzSim>[];
  for (var i = 0; out.length < n; i++) {
    final g = DdzGame.deal(random: Random(5000 + i))..act(const DdzBid(3));
    final sim = DdzSim.fromGame(g);
    while (!sim.over && sim.sizes[0] + sim.sizes[1] + sim.sizes[2] > cards) {
      sim.apply(_policy.choose(simSituation(sim)));
    }
    if (!sim.over) out.add(sim);
  }
  return out;
}
