// ignore_for_file: avoid_print (no dart:io here, so it also runs as JavaScript)
// A fixed Gomoku workload with no platform libraries, so the same file runs
// natively and compiled to JavaScript, to compare speed and check that both
// give exactly the same answers (the fingerprint must match):
//
//   dart run tool/games/gomoku_bench.dart
//   dart compile js -O2 tool/games/gomoku_bench.dart -o build/gomoku_bench.js
//   node build/gomoku_bench.js
//
// It times: raw search speed on one position (nodes per second), the coach
// at its default budget on 20 positions from bot games (Freestyle, then
// Renju and Standard 19×19), and the hard bot's move on the Freestyle
// positions. Node limits only, so the work is identical.
import 'package:pokerfection/src/games/gomoku/board.dart';
import 'package:pokerfection/src/games/gomoku/gomoku.dart';
import 'package:pokerfection/src/games/gomoku/search.dart';
import 'package:pokerfection/src/games/gomoku/threats.dart';

void main() {
  final positions = _positions(GomokuRules.freestyle);
  var fingerprint = 0;
  void mix(int v) => fingerprint = (fingerprint * 31 + v) & 0x3FFFFFFF;

  // Raw search speed, on a fixed quiet middlegame position.
  final mid = GomokuGame.fromMoves(GomokuRules.freestyle, GomokuGame.parseMoves('h8 j6 f6 e5 e7 g5 h5 g6 g7 h7 i9 j10'));
  final board = Board.fromMoves(mid.rules, [for (final m in mid.moves) m.index(15)]);
  final clock = Stopwatch()..start();
  final result = Searcher(board).search(const SearchLimits(maxNodes: 200000));
  final searchMs = clock.elapsedMicroseconds / 1000;
  mix(result.move);
  mix(result.score & 0xFFFF);
  print('search: ${result.nodes} nodes in ${searchMs.toStringAsFixed(0)} ms = '
      '${(result.nodes / searchMs).toStringAsFixed(0)} k nodes/s (depth ${result.depth})');

  // Threat solver speed.
  clock.reset();
  var solverNodes = 0;
  for (final g in positions) {
    final b = Board.fromMoves(g.rules, [for (final m in g.moves) m.index(15)]);
    final solver = ThreatSolver(b);
    final p = solver.vct(maxNodes: 20000);
    solverNodes += solver.nodes;
    mix(p?.movesToWin ?? 0);
  }
  final solverMs = clock.elapsedMicroseconds / 1000;
  print('VCT: $solverNodes nodes in ${solverMs.toStringAsFixed(0)} ms = '
      '${(solverNodes / solverMs).toStringAsFixed(0)} k nodes/s');

  // The coach at its default budget (with no time cap, for identical work).
  const coach = GomokuCoach(budget: CoachBudget(maxTime: Duration(minutes: 1)));
  final times = <double>[];
  for (final g in positions) {
    clock.reset();
    final a = coach.analyze(g.viewFor(g.toMove));
    times.add(clock.elapsedMicroseconds / 1000);
    mix(a.best!.move.index(15));
    mix(a.best!.score & 0xFFFF);
    mix(a.moves.length);
  }
  _report('coach', times);

  // The coach under the rules that check every candidate for a loss (an
  // overline or a forbidden point can make a move lose), where it works
  // hardest.
  for (final rules in [GomokuRules.renju, GomokuRules.standard19]) {
    times.clear();
    for (final g in _positions(rules)) {
      clock.reset();
      final a = coach.analyze(g.viewFor(g.toMove));
      times.add(clock.elapsedMicroseconds / 1000);
      mix(a.best!.move.index(rules.size));
      mix(a.moves.length);
    }
    _report('coach (${rules.label})', times);
  }

  // The hard bot (no time cap).
  times.clear();
  for (final g in positions) {
    clock.reset();
    final m = GomokuBot(BotLevel.hard).chooseMove(g.viewFor(g.toMove));
    times.add(clock.elapsedMicroseconds / 1000);
    mix(m.index(15));
  }
  _report('hard bot', times);
  print('fingerprint $fingerprint');
}

// Positions from medium-vs-easy games, every third move from move 6.
List<GomokuGame> _positions(GomokuRules rules) {
  final positions = <GomokuGame>[];
  for (var seed = 0; positions.length < 20; seed++) {
    var g = GomokuGame(rules);
    final black = GomokuBot(BotLevel.medium, seed: seed), white = GomokuBot(BotLevel.easy, seed: seed);
    while (!g.isOver && positions.length < 20) {
      if (g.moves.length >= 6 && g.moves.length % 3 == 0) positions.add(g);
      g = g.play((g.toMove == Stone.black ? black : white).chooseMove(g.viewFor(g.toMove)));
    }
  }
  return positions;
}

void _report(String what, List<double> times) {
  final sorted = [...times]..sort();
  final avg = times.reduce((a, b) => a + b) / times.length;
  print('$what: average ${avg.toStringAsFixed(0)} ms, median ${sorted[sorted.length ~/ 2].toStringAsFixed(0)} ms, '
      'max ${sorted.last.toStringAsFixed(0)} ms over ${times.length} positions');
}
