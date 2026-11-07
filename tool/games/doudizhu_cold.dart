// ignore_for_file: avoid_print

// The cold cost of Fight the Landlord's background jobs: each job runs in a
// fresh isolate, as the app runs it (one isolate per job, so every static
// cache starts empty), on the inputs of its examples() and checkInputs():
//
//   dart run tool/games/doudizhu_cold.dart            (all inputs)
//   dart run tool/games/doudizhu_cold.dart --quick    (the examples only)
//
// For each job it prints how long the job took to reach its engine call
// (decoding the input, replaying the record to the decision and building
// the seat's view) and the whole job. The rule (see jobs_core.dart): a
// coach or bot job must reach its engine call within 50 ms natively;
// otherwise the expensive table goes in as input. Fight the Landlord's
// engine keeps no tables between calls, so there is nothing to pass in.
// It also checks that every cold reply equals the one this (warm) isolate
// gives: same input, same output.
//
// A timing tool: run it alone, never alongside other benchmarks.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:pokerfection/src/games/doudizhu/app/doudizhu_jobs.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_range.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_record.dart';
import 'package:pokerfection/src/kit/jobs/jobs_core.dart';

Future<void> main(List<String> args) async {
  final quick = args.contains('--quick');
  final jobs = jobsByName(doudizhuJobs);
  var worstReach = 0.0;
  var failures = 0;

  for (final job in <GameJob<Object?, Object?>>[const DdzCoachJob(), const DdzBotJob(), const DdzRangeJob()]) {
    final reach = <double>[], total = <double>[];
    final inputs = quick ? job.examples() : [...job.examples(), ...job.checkInputs()];
    for (final input in inputs) {
      final request = encodeRequest(1, job, input, platform: JobPlatform.desktop);
      final cold = await Isolate.run(() => _timed(request, jobs));
      reach.add(cold.reachMs);
      total.add(cold.totalMs);
      final warm = runJobRequest(request, jobs);
      if (jsonEncode(job.normalize((jsonDecode(warm) as Map)['out'])) !=
          jsonEncode(job.normalize((jsonDecode(cold.reply) as Map)['out']))) {
        failures++;
        print('  DIFFERENT REPLY: ${job.name}');
      }
    }
    worstReach = [worstReach, ...reach].reduce((a, b) => a > b ? a : b);
    print(
      '${job.name}: ${reach.length} inputs, cold in a fresh isolate (ms):\n'
      '  reach the engine call  ${_stats(reach)}\n'
      '  whole job              ${_stats(total)}',
    );
  }

  final ok = worstReach < 50 && failures == 0;
  print(ok
      ? 'OK: every job reaches its engine call within 50 ms cold (worst ${worstReach.toStringAsFixed(1)} ms)'
      : 'FAILED: worst reach ${worstReach.toStringAsFixed(1)} ms, $failures replies differ');
  exit(ok ? 0 : 1);
}

/// Runs one request in this (fresh) isolate, timing the way to the engine.
({double reachMs, double totalMs, String reply}) _timed(String request, Map<String, GameJob<Object?, Object?>> jobs) {
  final watch = Stopwatch()..start();
  final message = jsonDecode(request) as Map<String, Object?>;
  final input = message['in']! as Map<String, Object?>;
  // What every job does before its engine call: replay the record, take the
  // view (the range job: the player's view, whoever's turn it is).
  final record = input['record']! as Map<String, Object?>;
  if (input['viewer'] case final num viewer) {
    ddzReplay(ddzRecordFromJson(record)!).viewFor(viewer.toInt());
  } else {
    ddzJobView(record, (input['seat']! as num).toInt());
  }
  final reachMs = watch.elapsedMicroseconds / 1000;
  final reply = runJobRequest(request, jobs);
  return (reachMs: reachMs, totalMs: watch.elapsedMicroseconds / 1000, reply: reply);
}

String _stats(List<double> ms) {
  if (ms.isEmpty) return '-';
  final sorted = [...ms]..sort();
  final avg = sorted.reduce((a, b) => a + b) / sorted.length;
  return 'avg ${avg.toStringAsFixed(1)}, median ${sorted[sorted.length ~/ 2].toStringAsFixed(1)}, '
      'max ${sorted.last.toStringAsFixed(1)}';
}
