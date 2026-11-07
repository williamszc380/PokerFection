// Big Two's jobs from cold: each run in a fresh isolate, as the apps run
// them, so nothing a previous job built (lookup tables, caches) is there.
//
// For every coach and bot job it prints:
// - "to engine": from the isolate's start to the engine call (decoding the
//   input, replaying the record, building the seat's view). The kit's rule
//   is under 50 ms natively; above that, the expensive part has to come in
//   as input instead.
// - "whole job": the request run start to finish, reply encoded, at the
//   desktop budget with the coach's 1000 ms (bot 800 ms) cap.
//
//   dart run tool/games/big_two_cold.dart            (each input once)
//   dart run tool/games/big_two_cold.dart --runs 3   (each input 3 times, fresh each time)
//   dart run tool/games/big_two_cold.dart --quick    (the light test budget: checks the tool
//                                                     runs, with "to engine" still real)
//
// Timing only: run it alone, never next to another benchmark.
//
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:isolate';

import 'package:pokerfection/src/games/big_two/app/big_two_jobs.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_record.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/kit/game_record.dart';
import 'package:pokerfection/src/kit/jobs/job_registry.dart';
import 'package:pokerfection/src/kit/jobs/jobs_core.dart';
import 'package:pokerfection/src/kit/seats.dart';

Future<void> main(List<String> args) async {
  final i = args.indexOf('--runs');
  final runs = i >= 0 && i + 1 < args.length ? int.parse(args[i + 1]) : 1;
  final platform = args.contains('--quick') ? JobPlatform.test : JobPlatform.desktop;
  const coach = BigTwoCoachJob();
  const bot = BigTwoBotJob();
  final positions = _positions();
  print('Big Two jobs from cold, $runs run(s) each, fresh isolate every time, ${platform.name} budget.');
  print('${'job'.padRight(34)} ${'to engine'.padLeft(10)} ${'whole job'.padLeft(10)}');
  var worstEngine = 0.0;
  for (final (label, record, seat) in positions) {
    final inputs = <(String, GameJob<Object?, Object?>, Object?, JobKind)>[
      ('coach $label', coach, BigTwoCoachInput(record: record.jobJson(), seat: seat, seed: 1), JobKind.coach),
      (
        'bot hard $label',
        bot,
        BigTwoBotInput(record: record.jobJson(), seat: seat, seed: 1, level: KitLevel.hard),
        JobKind.bot,
      ),
      (
        'bot easy $label',
        bot,
        BigTwoBotInput(record: record.jobJson(), seat: seat, seed: 1, level: KitLevel.easy),
        JobKind.bot,
      ),
    ];
    for (final (name, job, input, kind) in inputs) {
      for (var r = 0; r < runs; r++) {
        final request = encodeRequest(
          1,
          job,
          input,
          cap: capFor(kind, platform, background: true),
          platform: platform,
        );
        final toEngine = await Isolate.run(() => _toEngine(job, request));
        final whole = await Isolate.run(() => _whole(request));
        if (toEngine > worstEngine) worstEngine = toEngine;
        print(
          '${name.padRight(34)} ${'${toEngine.toStringAsFixed(1)} ms'.padLeft(10)} '
          '${'${whole.toStringAsFixed(1)} ms'.padLeft(10)}',
        );
      }
    }
  }
  print(
    'Worst time to the engine call: ${worstEngine.toStringAsFixed(1)} ms '
    '(${worstEngine < 50 ? 'under' : 'OVER'} the 50 ms rule).',
  );
}

/// Milliseconds from the isolate's start to the engine call.
double _toEngine(GameJob<Object?, Object?> job, String request) {
  final clock = Stopwatch()..start();
  final input = job.decodeInput((jsonDecode(request) as Map<String, Object?>)['in']);
  final view = switch (input) {
    final BigTwoCoachInput coach => coach.view(),
    final BigTwoBotInput bot => bot.view(),
    _ => throw StateError('not a Big Two input'),
  };
  if (!view.isMyTurn) throw StateError('nobody on turn');
  return clock.elapsedMicroseconds / 1000;
}

/// Milliseconds for the whole request.
double _whole(String request) {
  final clock = Stopwatch()..start();
  final reply = runJobRequest(request, kitJobs);
  if (reply.contains('"err"')) throw StateError(reply);
  return clock.elapsedMicroseconds / 1000;
}

/// Positions from the deal to late in it, 4, 3 and 2 players.
List<(String, GameRecord, int)> _positions() {
  final out = <(String, GameRecord, int)>[];
  for (final (players, moves) in [(4, 0), (4, 20), (4, 40), (3, 0), (3, 30), (2, 10)]) {
    final rules = BigTwoRules.standard(players: players);
    var record = BigTwoRecord.deal(
      rules: rules,
      seed: 77 + moves,
      seats: [
        const SeatSpec(human: true, name: 'Player'),
        for (var s = 1; s < players; s++) SeatSpec(human: false, level: KitLevel.hard, name: kitBotNames[s - 1]),
      ],
    );
    final state = BigTwoRecord.replay(record);
    for (var m = 0; m < moves; m++) {
      final seat = state.toMove;
      final play = BigTwoBot(BotLevel.easy, seed: m).chooseMove(state.viewFor(seat));
      if ((state.copy()..applyTrusted(play)).isOver) break;
      state.apply(play);
      record = record.withMove(bigTwoMoveText(seat, play));
    }
    out.add(('${players}p move ${record.moves.length}', record, state.toMove));
  }
  return out;
}
