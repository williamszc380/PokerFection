// ignore_for_file: avoid_print

// The same blackjack workload on every platform, to compare the native
// build with the JavaScript one (no dart:io, so it compiles to JS):
//
//   dart run tool/games/blackjack_web_bench.dart
//   dart compile js -O2 tool/games/blackjack_web_bench.dart -o build/bj_bench.js
//   node build/bj_bench.js
//
// It times: building the Standard basic strategy chart (with its optimal
// house edge), the coach (FRESH + SEEN) on 3,000 fixed decisions from
// seeded play (enough to see the slow tail: a few hundred understate it
// several times over), one of the slowest spots on its own (3-3 against a
// 2 under Vegas Strip rules, where both modes value resplits to four
// hands), dealer outcome evaluations, and bot self-play. The checksums must
// match across platforms: every deal is seeded with a 32-bit generator.
import 'dart:typed_data';

import 'package:pokerfection/src/games/blackjack/blackjack.dart';

void main() {
  const rules = BlackjackRules();

  final chartWatch = Stopwatch()..start();
  final chart = BasicStrategyChart.forRules(rules);
  print(
    'chart + optimal house edge: ${chartWatch.elapsedMilliseconds} ms '
    '(edge ${(chart.optimalEdge * 100).toStringAsFixed(4)}%)',
  );

  // Self-play first (also warms up the JIT / JS engine).
  final playWatch = Stopwatch()..start();
  final table = BlackjackTable(rules, seed: 42);
  final bot = BlackjackBot(BotLevel.hard);
  var net = 0.0;
  const rounds = 20000;
  for (var i = 0; i < rounds; i++) {
    final round = table.deal([1, 1, 1]);
    while (!round.isOver) {
      round.apply(bot.chooseAction(round.viewFor(round.turn!.seat)));
    }
    for (var s = 0; s < 3; s++) {
      net += round.result(s).net;
    }
  }
  print(
    'self-play: ${(playWatch.elapsedMicroseconds / rounds).toStringAsFixed(1)} us per 3-seat round '
    '(checksum ${net.toStringAsFixed(1)})',
  );

  // Dealer outcome evaluations.
  final graph = DealerGraph.of(1, false);
  final counts = Int32List.fromList(Composition.decks(6).counts);
  counts[1]--;
  final out = Float64List(dealerOutcomeCount);
  final work = Float64List(graph.nodeCount);
  final dealerWatch = Stopwatch()..start();
  var bust = 0.0;
  const evals = 20000;
  for (var i = 0; i < evals; i++) {
    counts[i % 10]--;
    graph.outcomes(counts, 310, out, work);
    counts[i % 10]++;
    bust += out[dealerBust];
  }
  print(
    'dealer outcomes (upcard 2): ${(dealerWatch.elapsedMicroseconds / evals).toStringAsFixed(2)} us each '
    '(checksum ${bust.toStringAsFixed(4)})',
  );

  // The coach on fixed decisions.
  final coach = const BlackjackCoach();
  final t2 = BlackjackTable(rules, seed: 7);
  final times = <double>[];
  var check = 0.0;
  var coachTotal = 0;
  while (times.length < 3000) {
    final round = t2.deal([1, 1, 1]);
    while (!round.isOver) {
      final v = round.viewFor(round.turn!.seat);
      final w = Stopwatch()..start();
      final a = coach.analyze(v);
      final us = w.elapsedMicroseconds;
      coachTotal += us;
      times.add(us / 1000);
      check += a.of(a.bestSeen).evSeen;
      round.apply(bot.chooseAction(v));
    }
  }
  times.sort();
  final avg = coachTotal / 1000 / times.length;
  print(
    'coach (FRESH + SEEN, ${times.length} decisions): avg ${avg.toStringAsFixed(2)} ms, '
    'median ${times[times.length ~/ 2].toStringAsFixed(2)} ms, '
    '99th pct ${times[(times.length * 0.99).floor()].toStringAsFixed(2)} ms, '
    '99.9th pct ${times[(times.length * 0.999).floor()].toStringAsFixed(2)} ms, max ${times.last.toStringAsFixed(2)} ms '
    '(checksum ${check.toStringAsFixed(4)})',
  );

  // One of the slowest spots: 3-3 against a 2, Vegas Strip, after a few
  // small cards so that SEEN differs from FRESH (two full analyses).
  final strip = BlackjackRules.preset(BlackjackPreset.vegasStrip);
  BasicStrategyChart.forRules(strip);
  final worst = <double>[];
  for (var i = 0; i < 5; i++) {
    final shoe = Shoe.forRules(strip, seed: i + 1)
      ..stack([for (final c in '4c 5c 6c 9c 3h 2s 3d 7c'.split(' ')) Card.parse(c)]);
    final first = BlackjackRound.deal(strip, shoe, [1]);
    while (!first.isOver) {
      first.apply(BlackjackAction.stand);
    }
    shoe.stack([for (final c in '3s 2h 3c Kd'.split(' ')) Card.parse(c)]);
    final v = BlackjackRound.deal(strip, shoe, [1]).viewFor(0);
    final w = Stopwatch()..start();
    coach.analyze(v);
    worst.add(w.elapsedMicroseconds / 1000);
  }
  worst.sort();
  print('coach on 3-3 v 2 (Vegas Strip, SEEN differs from FRESH): median of 5 ${worst[2].toStringAsFixed(1)} ms');
}
