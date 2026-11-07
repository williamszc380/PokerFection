// The cold cost of Gomoku's background jobs: each job in a fresh isolate,
// as the apps run them (one short-lived isolate per job, so every static
// cache starts empty).
//
//   dart run tool/games/gomoku_cold.dart          (JIT: a first look)
//   dart compile exe tool/games/gomoku_cold.dart -o gomoku_cold.exe && gomoku_cold.exe   (AOT, as the apps)
//
// For every input it measures, each in its own fresh isolate:
// - reach: decoding the input and replaying the record, up to the engine
//   call. The kit's rule: under 50 ms natively, or the expensive part must
//   come in as input instead;
// - cold: the whole job (the engine's lazily filled pattern tables
//   included);
// - warm: the same job run a second time in that isolate.
//
// Timing only: run it alone (the user's rule), never in tests.
//
// ignore_for_file: avoid_print
import 'dart:isolate';

import 'package:pokerfection/src/games/gomoku/app/gomoku_jobs.dart';
import 'package:pokerfection/src/games/gomoku/app/gomoku_record.dart';
import 'package:pokerfection/src/games/gomoku/gomoku.dart';
import 'package:pokerfection/src/kit/jobs/jobs_core.dart';
import 'package:pokerfection/src/kit/seats.dart';

/// The longest record a job can get: a whole Renju game (about 220 moves)
/// where every Black move is checked for forbidden points as it replays.
const _longRenju =
    'h6 k4 i5 k9 h13 m3 f14 a11 g7 b11 d2 h2 b3 l2 m6 f8 a9 n7 b9 g1 a13 j10 k13 n8 b13 e6 g15 o3 k5 m15 '
    'b12 n15 a15 o11 m7 d4 m9 m4 j15 k10 f4 c9 e4 a7 i6 n10 h1 d15 o2 o15 k11 b5 k12 i3 e2 j9 i13 a6 i14 m1 '
    'n2 f10 j3 i8 b15 c10 f2 b1 g10 l14 o13 g11 o14 m13 b8 a8 d9 l4 n14 f7 g4 j1 a5 b10 e12 l8 c13 a10 h11 c15 '
    'j7 e3 f6 e1 m2 d5 d8 e5 o12 f1 m14 g14 b14 b7 h9 i1 a2 j2 n4 g12 m12 j12 i11 g2 n5 l3 o1 c6 c2 m8 c4 h12 '
    'h7 l13 l7 c14 e14 h4 n13 a4 e9 k7 o5 g8 f12 i10 f13 d3 o10 o9 n9 d14 o6 l12 h14 a3 a1 f15 e8 g13 j14 j5 '
    'l1 c11 e13 c3 h3 a14 o8 e7 i2 i15 l6 g9 k1 g5 c5 b2 n12 o4 i4 n1 d11 k2 l9 i7 g3 k14 d1 n11 j13 m11 d6 j4 '
    'k15 i12 l15 d13 o7 e15 c1 d12 i9 b6 f11 b4 c8 n6 h10 g6 j8 h15 l10 c12 h5 j11 e10 m10 d10 a12 c7 f5 n3 f9';

Future<void> main() async {
  const coach = GomokuCoachJob();
  const bot = GomokuBotJob();
  final long = GomokuRecord.start(
    const GomokuOptions(rules: GomokuRules.renju),
    seed: 1,
    moves: _longRenju.split(' '),
  ).jobJson();
  final longSeat = (long['moves']! as List).length.isEven ? 0 : 1;
  final cases = <(String, GameJob<Object?, Object?>, Object?)>[
    for (final (i, input) in coach.examples().indexed) ('coach example $i', coach, coach.encodeInput(input)),
    for (final (i, input) in coach.checkInputs().indexed)
      if (i % 4 == 0) ('coach check $i', coach, coach.encodeInput(input)),
    ('coach, long Renju game', coach, coach.encodeInput(GomokuCoachInput(record: long, seat: longSeat))),
    for (final (i, input) in bot.examples().indexed) ('bot example $i', bot, bot.encodeInput(input)),
    for (final (i, input) in bot.checkInputs().indexed)
      if (i % 4 == 1) ('bot check $i (${input.level.name})', bot, bot.encodeInput(input)),
    (
      'bot, long Renju game',
      bot,
      bot.encodeInput(GomokuBotInput(record: long, seat: longSeat, level: KitLevel.hard, seed: 1)),
    ),
  ];

  print(
    '${'job'.padRight(30)} ${'reach'.padLeft(8)} ${'cold'.padLeft(8)} ${'warm'.padLeft(8)}  (ms; cap 1000 coach, 800 bot)',
  );
  var worstReach = 0.0;
  for (final (label, job, json) in cases) {
    final reach = await Isolate.run(() => _reach(job, json));
    final (cold, warm) = await Isolate.run(() => _coldWarm(job, json));
    if (reach > worstReach) worstReach = reach;
    print(
      '${label.padRight(30)} ${_ms(reach)} ${_ms(cold)} ${_ms(warm)}${reach > 50 ? '   <-- over 50 ms to reach the engine' : ''}',
    );
  }
  print('worst reach: ${worstReach.toStringAsFixed(1)} ms (the rule: under 50 ms natively)');
}

String _ms(double ms) => ms.toStringAsFixed(1).padLeft(8);

double _millis(Stopwatch clock) => clock.elapsedMicroseconds / 1000;

/// Decoding and replaying, up to the engine call (what a job does first).
double _reach(GameJob<Object?, Object?> job, Object? json) {
  final clock = Stopwatch()..start();
  final input = job.decodeInput(json);
  final record = switch (input) {
    GomokuCoachInput(:final record) => record,
    GomokuBotInput(:final record) => record,
    _ => throw StateError('not a Gomoku job'),
  };
  final game = GomokuRecord.replayJson(record);
  game.viewFor(game.toMove);
  return _millis(clock);
}

/// The whole job from a cold start, then again warm.
(double, double) _coldWarm(GameJob<Object?, Object?> job, Object? json) {
  double once() {
    final clock = Stopwatch()..start();
    final cap = Duration(milliseconds: job is GomokuBotJob ? 800 : 1000);
    job.encodeOutput(job.run(job.decodeInput(json), JobContext(platform: JobPlatform.desktop, timeCap: cap)));
    return _millis(clock);
  }

  final cold = once();
  return (cold, once());
}
