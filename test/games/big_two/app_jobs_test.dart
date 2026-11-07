// The coach and bot jobs (JSON in, JSON out), their work budgets, the
// analysis codec, and how the coach's answer becomes grades.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_analysis.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_grading.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_jobs.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_range.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_record.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/gto/spot_strategy.dart' show DecisionGrade;
import 'package:pokerfection/src/kit/coach_answer.dart';
import 'package:pokerfection/src/kit/game_record.dart';
import 'package:pokerfection/src/kit/grading.dart';
import 'package:pokerfection/src/kit/jobs/job_registry.dart';
import 'package:pokerfection/src/kit/jobs/jobs_core.dart';
import 'package:pokerfection/src/kit/seats.dart';

/// Runs [job] on [input] the way a worker does, and gives the decoded output.
O runJob<I, O>(GameJob<I, O> job, I input, {JobPlatform platform = JobPlatform.test, Duration? cap}) {
  final reply = jsonDecode(
    runJobRequest(encodeRequest(1, job, input, cap: cap, platform: platform), kitJobs),
  ) as Map<String, Object?>;
  if (reply['err'] case final String error) fail(error);
  return job.decodeOutput(reply['out']);
}

GameRecord dealt(BigTwoRules rules, int seed) => BigTwoRecord.deal(
  rules: rules,
  seed: seed,
  seats: [
    const SeatSpec(human: true, name: 'Player'),
    for (var i = 1; i < rules.players; i++) SeatSpec(human: false, level: KitLevel.easy, name: kitBotNames[i - 1]),
  ],
);

void main() {
  const coach = BigTwoCoachJob();
  const bot = BigTwoBotJob();

  test('the jobs (solo and online) are registered under the game key', () {
    expect(bigTwoJobs.map((j) => j.name), [
      'big_two.coach',
      'big_two.bot',
      'big_two.range',
      'big_two.onlineBot',
      'big_two.onlineCoach',
    ]);
    expect(kitJobs['big_two.coach'], isA<BigTwoCoachJob>());
    expect(kitJobs['big_two.bot'], isA<BigTwoBotJob>());
    expect(kitJobs['big_two.range'], isA<BigTwoRangeJob>());
  });

  group('the coach job', () {
    test('rates every legal move of the seat on turn, in the record\'s notation, the pick first', () {
      final record = dealt(BigTwoRules.standard(), 31);
      final state = BigTwoRecord.replay(record);
      final seat = state.toMove;
      final report = runJob(coach, BigTwoCoachInput(record: record.jobJson(), seat: seat, seed: 5));
      expect(report.moves.map((m) => m.move).toSet(), {for (final p in state.legalMoves()) bigTwoMoveText(seat, p)});
      expect(report.pick.pointsLost, 0);
      expect(report.plan, isNotEmpty, reason: 'the hand plan comes with it');
      expect(report.plan.length, report.planSure.length);
      expect(report.plan.every((m) => bigTwoMoveSeat(m) == seat), isTrue);
    });

    test('the same input gives the same output, and the output holds no timing', () {
      for (final input in [...coach.examples(), ...coach.checkInputs().take(6)]) {
        final a = runJobRequest(encodeRequest(1, coach, input, platform: JobPlatform.desktop), kitJobs);
        final b = runJobRequest(encodeRequest(1, coach, input, platform: JobPlatform.desktop), kitJobs);
        expect(a, b);
        expect(a, isNot(contains('micros')));
        expect(a, isNot(contains('elapsed')));
      }
    });

    test('it sees only its own seat: the same answer whatever the hidden hands hold', () {
      final record = dealt(BigTwoRules.standard(), 32);
      final seat = BigTwoRecord.replay(record).toMove;
      // Swap two opponents' hands: what the seat on turn sees is unchanged.
      final hands = [...(record.deal['hands']! as List).cast<String>()];
      final others = [
        for (var s = 0; s < 4; s++)
          if (s != seat) s,
      ];
      final first = hands[others[0]];
      hands[others[0]] = hands[others[1]];
      hands[others[1]] = first;
      final swapped = GameRecord.fromJson(
        {
          ...record.toJson(),
          'deal': {...record.deal, 'hands': hands},
        },
        game: record.game,
        version: record.version,
      )!;
      final a = runJob(coach, BigTwoCoachInput(record: record.jobJson(), seat: seat, seed: 2));
      final b = runJob(coach, BigTwoCoachInput(record: swapped.jobJson(), seat: seat, seed: 2));
      expect(jsonEncode(a.toJson()), jsonEncode(b.toJson()));
    });

    test('asking for a seat that is not on turn fails the job', () {
      final record = dealt(BigTwoRules.standard(), 33);
      final seat = (BigTwoRecord.replay(record).toMove + 1) % 4;
      final reply = jsonDecode(
        runJobRequest(
          encodeRequest(
            1,
            coach,
            BigTwoCoachInput(record: record.jobJson(), seat: seat, seed: 1),
            platform: JobPlatform.test,
          ),
          kitJobs,
        ),
      ) as Map<String, Object?>;
      expect(reply['err'], contains('not on turn'));
    });

    test('every example and check input runs and decodes', () {
      expect(coach.examples(), isNotEmpty);
      expect(coach.checkInputs().length, greaterThanOrEqualTo(30));
      for (final input in coach.checkInputs()) {
        expect(runJob(coach, input).moves, isNotEmpty);
      }
    });
  });

  group('the bot job', () {
    test('plays a legal move for its seat, at every level', () {
      final record = dealt(BigTwoRules.standard(players: 3), 41);
      final state = BigTwoRecord.replay(record);
      final seat = state.toMove;
      for (final level in KitLevel.values) {
        final out = runJob(bot, BigTwoBotInput(record: record.jobJson(), seat: seat, seed: 9, level: level));
        final (seat: who, :play) = bigTwoParseMove(state.rules, out.move);
        expect(who, seat);
        expect(state.legalMoves(), contains(play), reason: '$level');
        expect(out.analysis, isNull, reason: 'not asked for');
      }
    });

    test('asked for it, Medium and Hard send back the analysis their move came from; Easy has none', () {
      final record = dealt(BigTwoRules.standard(), 42);
      final seat = BigTwoRecord.replay(record).toMove;
      for (final level in KitLevel.values) {
        final out = runJob(
          bot,
          BigTwoBotInput(record: record.jobJson(), seat: seat, seed: 9, level: level, analysis: true),
        );
        if (level == KitLevel.easy) {
          expect(out.analysis, isNull);
        } else {
          expect(out.analysis!.pick.move, out.move, reason: '$level plays its analysis\'s pick');
        }
      }
    });

    test('the same input gives the same move', () {
      for (final input in bot.checkInputs().take(9)) {
        expect(
          runJob(bot, input, platform: JobPlatform.desktop).move,
          runJob(bot, input, platform: JobPlatform.desktop).move,
        );
      }
    });
  });

  group('budgets', () {
    test('3000 play-outs on desktops and in WebAssembly, 1500 on phones and in JavaScript, light in tests', () {
      int playouts(JobPlatform p, {bool deep = false}) => bigTwoBudget(JobContext(platform: p), deep: deep).playouts;
      expect(playouts(JobPlatform.desktop), 3000);
      expect(playouts(JobPlatform.webWasm), 3000);
      expect(playouts(JobPlatform.phone), 1500);
      expect(playouts(JobPlatform.webJs), 1500);
      expect(playouts(JobPlatform.test), CoachBudget.quick.playouts);
      expect(playouts(JobPlatform.desktop, deep: true), 9000, reason: 'Think longer: three times as many');
      expect(bigTwoBudget(JobContext(platform: JobPlatform.desktop), playouts: 200).playouts, 200);
    });

    test('no cap: the engine gets no time limit; a cap: a limit inside it', () {
      expect(bigTwoBudget(JobContext(platform: JobPlatform.desktop)).maxMillis, isNull);
      final capped = bigTwoBudget(JobContext(platform: JobPlatform.desktop, timeCap: const Duration(seconds: 1)));
      expect(capped.maxMillis, inInclusiveRange(900, 999));
      final spent = bigTwoBudget(JobContext(platform: JobPlatform.desktop, timeCap: Duration.zero));
      expect(spent.maxMillis, 0);
    });

    test('a capped job still answers', () {
      final record = dealt(BigTwoRules.standard(), 43);
      final seat = BigTwoRecord.replay(record).toMove;
      final report = runJob(
        coach,
        BigTwoCoachInput(record: record.jobJson(), seat: seat, seed: 1),
        platform: JobPlatform.desktop,
        cap: Duration.zero,
      );
      expect(report.moves, isNotEmpty);
    });
  });

  group('the analysis codec', () {
    test('a report reads back field for field through JSON', () {
      const report = BigTwoReport(
        moves: [
          BigTwoRating(move: '0:3d', winChance: 0.4123, points: 2.5, samples: 900, reasons: ['shedsLowest']),
          BigTwoRating(
            move: '0:pass',
            winChance: 0.2,
            points: -1.25,
            samples: 40,
            pointsLost: 3.75,
            error: 0.8125,
            eliminatedAt: 0,
          ),
          BigTwoRating(move: '0:2s', winChance: 1, points: 12, samples: 10, sure: true),
        ],
        plan: ['0:3d', '0:2s'],
        planSure: [false, true],
        playouts: 950,
        deals: 900,
      );
      final back = BigTwoReport.fromJson(jsonDecode(jsonEncode(report.toJson())));
      expect(jsonEncode(back.toJson()), jsonEncode(report.toJson()));
      expect(back.moves[1].droppedEarly, isTrue);
      expect(back.moves[1].error, 0.8125);
      expect(back.moves[0].error, 0, reason: 'the pick has no gap to itself');
      expect(back.moves[2].sure, isTrue);
      expect(back.planSure, [false, true]);
    });

    test('numbers are kept to four decimals', () {
      final json = const BigTwoRating(move: '0:3d', winChance: 1 / 3, points: 2 / 3, samples: 1).toJson();
      expect(json['win'], 0.3333);
      expect(json['pts'], 0.6667);
    });
  });

  group('grading', () {
    const report = BigTwoReport(
      moves: [
        BigTwoRating(move: '0:7c 7h', winChance: 0.5, points: 3.0, samples: 1500),
        BigTwoRating(move: '0:7c', winChance: 0.48, points: 2.9, samples: 900, reasons: ['breaksPair']),
        BigTwoRating(move: '0:pass', winChance: 0.3, points: 1.0, samples: 600),
        BigTwoRating(move: '0:2s', winChance: 0.6, points: 3.4, samples: 40, eliminatedAt: 0),
        BigTwoRating(move: '0:3d', winChance: 0.1, points: -9, samples: 30, eliminatedAt: 0),
        BigTwoRating(move: '0:Ks', winChance: 0.45, points: 2.0, samples: 300, sure: true),
      ],
    );
    final answer = bigTwoAnswer(report, bigTwoPenaltyScale);

    test('the answer is in points, the pick is the coach\'s first move, and win chances ride along', () {
      expect(answer.unit, ValueUnit.points);
      expect(answer.pick, '0:7c 7h');
      expect(answer.lines.map((l) => l.move), report.moves.map((m) => m.move), reason: 'in the coach\'s order');
      expect(answer.lineFor('0:7c')!.winChance, 0.48);
      expect(answer.lineFor('0:7c')!.reasons, ['breaksPair']);
      expect(answer.lineFor('0:Ks')!.proof, 'sure');
      expect(answer.detail, same(report));
    });

    test('the pick is Best even when a line shows more points', () {
      expect(bigTwoPenaltyScale.mark(answer, '0:7c 7h')!.grade, DecisionGrade.best);
    });

    test('a move dropped early is at best Good, however good its few play-outs looked', () {
      final mark = bigTwoPenaltyScale.mark(answer, '0:2s')!;
      expect(mark.grade, DecisionGrade.good);
      expect(answer.lineFor('0:2s')!.minLoss, closeTo(0.16, 1e-9));
      expect(
        bigTwoPenaltyScale.mark(answer, '0:3d')!.grade,
        DecisionGrade.blunder,
        reason: 'a dropped move that loses a lot is graded by its loss',
      );
    });

    test('losses grade by points: within the coach\'s noise is Best, then Good, Inaccuracy, Mistake, Blunder', () {
      final scale = bigTwoPenaltyScale;
      expect(
        [
          for (final loss in [0.1, 0.4, 1.0, 2.0, 3.0]) scale.gradeFor(loss),
        ],
        [
          DecisionGrade.best,
          DecisionGrade.good,
          DecisionGrade.inaccuracy,
          DecisionGrade.mistake,
          DecisionGrade.blunder,
        ],
      );
      expect(
        scale.mark(answer, '0:pass')!.grade,
        DecisionGrade.mistake,
        reason: '2 points below the pick (3.0), though a dropped line shows 3.4',
      );
    });

    test('Pusoy Dos scoring (about a point a deal) grades on a scale ten times finer', () {
      expect(bigTwoScale(BigTwoRules.pusoyDos()), bigTwoPusoyScale);
      expect(bigTwoScale(BigTwoRules.standard()), bigTwoPenaltyScale);
      expect(bigTwoPusoyScale.gradeFor(0.1), DecisionGrade.inaccuracy);
      expect(bigTwoPenaltyScale.gradeFor(0.1), DecisionGrade.best);
      final pusoy = bigTwoAnswer(report, bigTwoPusoyScale);
      expect(bigTwoPusoyScale.mark(pusoy, '0:2s')!.grade, DecisionGrade.good);
    });

    group("past the coach's noise", () {
      const scale = bigTwoPenaltyScale;

      test('with no noise, the points a move is sure to lose are its gap to the pick', () {
        for (final gap in [0.0, 0.1, 0.4, 1.0, 2.0, 7.5]) {
          expect(scale.sureLoss(gap, 0), closeTo(gap, 1e-9));
        }
      });

      test('a gap of up to two standard errors loses nothing: it may be chance', () {
        expect(scale.sureLoss(1.9, 1.0), 0);
        expect(scale.sureLoss(2.0, 1.0), 0);
        expect(scale.sureLoss(2.05, 1.0), greaterThan(0));
      });

      test('each grade below Best needs 2.5 more standard errors of gap than the one before', () {
        const error = 1.0;
        // Where each grade ends: its cutoff plus (2 + 2.5 k) errors.
        final ends = [for (final (k, cut) in scale.cutoffs.indexed) cut + (2 + 2.5 * k) * error];
        expect(ends, [2.15, 5.0, 8.2, 12.0].map((e) => closeTo(e, 1e-9)).toList());
        for (final (k, end) in ends.indexed) {
          expect(
            scale.gradeFor(scale.sureLoss(end - 0.01, error)),
            DecisionGrade.values[k],
            reason: 'just inside',
          );
          expect(
            scale.gradeFor(scale.sureLoss(end + 0.01, error)),
            DecisionGrade.values[k + 1],
            reason: 'just past',
          );
        }
      });

      test('the sure loss grows with the gap, and shrinks as the noise grows', () {
        var last = -1.0;
        for (var gap = 0.0; gap < 30; gap += 0.25) {
          final loss = scale.sureLoss(gap, 0.8);
          expect(loss, greaterThanOrEqualTo(last), reason: 'gap $gap');
          expect(loss, lessThanOrEqualTo(gap), reason: 'never more than the gap itself');
          last = loss;
        }
        expect(scale.sureLoss(6, 0.5), greaterThan(scale.sureLoss(6, 1.5)));
      });

      const noisy = BigTwoReport(
        moves: [
          BigTwoRating(move: '0:7c 7h', winChance: 0.5, points: 3.0, samples: 300),
          BigTwoRating(move: '0:7c', winChance: 0.4, points: 0.5, samples: 300, error: 1.5),
          BigTwoRating(move: '0:pass', winChance: 0.2, points: -6.0, samples: 300, error: 0.5),
          BigTwoRating(move: '0:2s', winChance: 0.6, points: 4.0, samples: 300, error: 1.0),
          BigTwoRating(move: '0:3d', winChance: 0.45, points: 2.9, samples: 300, error: 1.0, eliminatedAt: 0),
        ],
      );
      final graded = bigTwoAnswer(noisy, scale);
      DecisionGrade gradeOf(String move) => scale.mark(graded, move)!.grade;

      test("a gap the coach can't tell from noise is Best, though the raw gap would be a Blunder", () {
        final raw = GradeScale(
          unit: scale.unit,
          cutoffs: scale.cutoffs,
          noise: scale.noise,
          scoreScale: scale.scoreScale,
        );
        expect(raw.mark(graded, '0:7c')!.grade, DecisionGrade.blunder, reason: '3.5 below the best line, raw');
        expect(gradeOf('0:7c'), DecisionGrade.best, reason: '2.5 below, with an error of 1.5');
      });

      test('a gap well past the noise is still graded down', () {
        expect(gradeOf('0:pass'), DecisionGrade.blunder, reason: '9 below, with an error of 0.5');
      });

      test('the pick, and a move scoring more than it, are Best; a move dropped early is at best Good', () {
        expect(gradeOf('0:7c 7h'), DecisionGrade.best);
        expect(gradeOf('0:2s'), DecisionGrade.best);
        expect(gradeOf('0:3d'), DecisionGrade.good);
      });

      test('the scale grades only rated moves, and its loss is the sure loss', () {
        expect(scale.mark(graded, '0:Ks'), isNull);
        final mark = scale.mark(graded, '0:pass')!;
        expect(mark.best, '0:7c 7h');
        expect(mark.loss, closeTo(scale.sureLoss(9, 0.5), 1e-9));
        expect(mark.score, scale.scoreFor(mark.loss));
      });
    });

    test('a real coach answer grades every legal move', () {
      final record = dealt(BigTwoRules.standard(), 51);
      final state = BigTwoRecord.replay(record);
      final seat = state.toMove;
      final real = bigTwoAnswer(
        runJob(coach, BigTwoCoachInput(record: record.jobJson(), seat: seat, seed: 3)),
        bigTwoPenaltyScale,
      );
      for (final play in state.legalMoves()) {
        expect(bigTwoPenaltyScale.mark(real, bigTwoMoveText(seat, play)), isNotNull);
      }
    });
  });
}
