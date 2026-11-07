// ignore_for_file: avoid_print

// The cold cost of blackjack's background jobs: each job runs in a fresh
// isolate, as the app runs it (one isolate per job, so every static cache
// starts empty), on the inputs of its checkInputs():
//
//   dart run tool/games/blackjack_cold.dart
//
// For each coach and bot job it prints how long the job took to reach its
// engine call (decoding the input, rebuilding the chart from its JSON,
// replaying the shoe to the decision) and the engine call itself, which
// includes building the dealer's draw graphs (DealerGraph, cached per
// isolate) for the upcard. The rule (see jobs_core.dart): a coach or bot
// job must reach its engine call within 50 ms natively; otherwise the
// expensive table goes in as input, as the strategy chart already does.
// It also times the chart job cold, the dealer graphs alone, and checks
// that every reply equals the one this isolate gives (same input, same
// output).
//
// A timing tool: run it alone, never alongside other benchmarks.
import 'dart:convert';
import 'dart:isolate';

import 'package:pokerfection/src/games/blackjack/app/blackjack_jobs.dart';
import 'package:pokerfection/src/games/blackjack/blackjack.dart';
import 'package:pokerfection/src/kit/jobs/jobs_core.dart';

Future<void> main() async {
  final jobs = jobsByName(blackjackJobs);
  var worstReach = 0.0;
  var failures = 0;

  for (final job in <GameJob<BlackjackDecisionInput, Object?>>[const BlackjackCoachJob(), const BlackjackBotJob()]) {
    final reach = <double>[], engine = <double>[], total = <double>[];
    for (final input in job.checkInputs()) {
      final request = encodeRequest(1, job, input, platform: JobPlatform.desktop);
      final cold = await Isolate.run(() => _timed(request, jobs));
      reach.add(cold.reachMs);
      engine.add(cold.engineMs);
      total.add(cold.totalMs);
      // The reply must not depend on what this isolate has cached.
      final warm = runJobRequest(request, jobs);
      if (jsonEncode(job.normalize((jsonDecode(warm) as Map)['out'])) !=
          jsonEncode(job.normalize((jsonDecode(cold.reply) as Map)['out']))) {
        failures++;
        print('  DIFFERENT REPLY: ${job.name} $request');
      }
    }
    worstReach = [worstReach, ...reach].reduce((a, b) => a > b ? a : b);
    print(
      '${job.name}: ${reach.length} inputs, cold in a fresh isolate (ms):\n'
      '  reach the engine call  ${_stats(reach)}\n'
      '  engine call            ${_stats(engine)}\n'
      '  whole job              ${_stats(total)}',
    );
  }

  // The dealer's draw graphs, built once per upcard and soft-17 rule in each
  // isolate: what a coach job pays on top of its first engine call.
  final graphs = await Isolate.run(() {
    final watch = Stopwatch()..start();
    for (var u = 0; u < rankCount; u++) {
      DealerGraph.of(u, false);
      DealerGraph.of(u, true);
    }
    return watch.elapsedMicroseconds / 1000;
  });
  print('DealerGraph, all 20 graphs cold: ${graphs.toStringAsFixed(1)} ms');

  // The chart job, cold, per example rule set.
  for (final rules in const BlackjackChartJob().checkInputs()) {
    final request = encodeRequest(1, const BlackjackChartJob(), rules, platform: JobPlatform.desktop);
    final ms = await Isolate.run(() {
      final watch = Stopwatch()..start();
      runJobRequest(request, jobs);
      return watch.elapsedMicroseconds / 1000;
    });
    print('blackjack.chart cold, $rules: ${ms.toStringAsFixed(0)} ms');
  }

  print(
    worstReach <= 50
        ? 'OK: every coach and bot job reaches its engine call within 50 ms (worst ${worstReach.toStringAsFixed(1)} ms).'
        : 'TOO SLOW: a job takes ${worstReach.toStringAsFixed(1)} ms to reach its engine call (limit 50 ms).',
  );
  if (failures > 0) print('$failures replies differed between a cold and a warm isolate.');
}

/// One job, timed in parts: the input decoded and the decision's view
/// rebuilt ("reach"), then the engine call; plus the job's reply as the app
/// gets it (runJobRequest).
({double reachMs, double engineMs, double totalMs, String reply}) _timed(
  String request,
  Map<String, GameJob<Object?, Object?>> jobs,
) {
  final message = jsonDecode(request) as Map<String, Object?>;
  final watch = Stopwatch()..start();
  final input = BlackjackDecisionInput.fromJson(message['in']);
  final view = input.view();
  final reach = watch.elapsedMicroseconds / 1000;
  if (message['job'] == 'blackjack.coach') {
    const BlackjackCoach().analyze(view, chart: input.chart);
  } else {
    BlackjackBot(input.level ?? BotLevel.hard, chart: input.chart).chooseAction(view);
  }
  final engine = watch.elapsedMicroseconds / 1000 - reach;
  // The job as the app runs it, in this same isolate: its reply is
  // compared with the main isolate's.
  final reply = runJobRequest(request, jobs);
  return (reachMs: reach, engineMs: engine, totalMs: reach + engine, reply: reply);
}

String _stats(List<double> ms) {
  final sorted = [...ms]..sort();
  final mean = sorted.reduce((a, b) => a + b) / sorted.length;
  return 'mean ${mean.toStringAsFixed(1)}, median ${sorted[sorted.length ~/ 2].toStringAsFixed(1)}, '
      'max ${sorted.last.toStringAsFixed(1)}';
}
