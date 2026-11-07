import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_analysis.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_jobs.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_record.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/kit/game_record.dart';
import 'package:pokerfection/src/kit/jobs/job_registry.dart';
import 'package:pokerfection/src/kit/jobs/jobs_core.dart';
import 'package:pokerfection/src/kit/seats.dart';

/// Runs [job] on [input] the way a worker does: encoded, through
/// runJobRequest, decoded; returns the reply's raw output too.
(O, Object?) viaRequest<I, O>(GameJob<I, O> job, I input, {JobPlatform platform = JobPlatform.test}) {
  final reply = jsonDecode(runJobRequest(encodeRequest(1, job, input, platform: platform), kitJobs)) as Map;
  expect(reply['err'], isNull, reason: '${reply['err']}');
  return (job.decodeOutput(reply['out']), reply['out']);
}

int toAct(GameRecord position) => ddzReplay(position).toAct;

/// The position before move [i] of [game], for the seat that made it.
DdzCoachInput coachAt(GameRecord game, int i, {String? include, int seed = 1}) {
  final position = game.upTo(i);
  return DdzCoachInput(record: position.jobJson(), seat: toAct(position), include: include, seed: seed);
}

/// The index of the landlord's first lead in [game].
int firstLead(GameRecord game) {
  for (var i = 0; i < game.moves.length; i++) {
    if (ddzReplay(game, upTo: i).phase == DdzPhase.playing) return i;
  }
  throw StateError('no lead');
}

void main() {
  const coach = DdzCoachJob();
  const bot = DdzBotJob();

  test('the coach and the bot are registered under the game\'s key', () {
    expect(kitJobs['doudizhu.coach'], isA<DdzCoachJob>());
    expect(kitJobs['doudizhu.bot'], isA<DdzBotJob>());
  });

  group('the coach job', () {
    test('rates the decision of the seat to act, best first, and its answer has no timing in it', () {
      final game = ddzSampleGame(2);
      final i = firstLead(game) + 3;
      final (advice, raw) = viaRequest(coach, coachAt(game, i));
      final view = ddzReplay(game, upTo: i).viewFor(toAct(game.upTo(i)));
      expect(advice.seat, view.seat);
      expect(advice.bidding, isFalse);
      expect(advice.legalMoves, view.legalMoves.length);
      expect(advice.lines, isNotEmpty);
      for (final line in advice.lines) {
        final move = ddzParseMove(line.move);
        expect(move.seat, view.seat);
        expect(view.legalMoves, contains(move.move));
        expect(move.cardIds, isNull, reason: 'coach lines are move keys');
      }
      final text = jsonEncode(raw);
      for (final timing in ['elapsed', 'micros', 'rollouts']) {
        expect(text, isNot(contains(timing)));
      }
    });

    test('in the auction it rates every bid, on points', () {
      final game = ddzSampleGame(4);
      final (advice, _) = viaRequest(coach, coachAt(game, 0));
      expect(advice.bidding, isTrue);
      expect(advice.objective, DdzObjective.points);
      expect(advice.lines, hasLength(advice.legalMoves));
    });

    test('the same input gives the same answer (no cap: no time limit)', () {
      final game = ddzSampleGame(3);
      final input = coachAt(game, firstLead(game) + 2, seed: 9);
      final (_, a) = viaRequest(coach, input);
      final (_, b) = viaRequest(coach, input);
      expect(coach.normalize(a), coach.normalize(b));
    });

    test('with include it rates the move played even when the usual answer leaves it out', () {
      // The landlord's first lead: 20 cards, more leads than the coach rates.
      for (final seed in [1, 2, 3, 4, 5, 6]) {
        final game = ddzSampleGame(seed);
        final i = firstLead(game);
        final view = ddzReplay(game, upTo: i).viewFor(toAct(game.upTo(i)));
        final (plain, _) = viaRequest(coach, coachAt(game, i));
        final left = view.legalMoves.where((m) => plain.lineFor(ddzMoveText(view.seat, m)) == null).firstOrNull;
        if (left == null) continue;
        final played = ddzMoveText(view.seat, left, left is DdzPlay ? ddzCardsFor(view.hand, left.play) : const []);
        final (asked, _) = viaRequest(coach, coachAt(game, i, include: played));
        expect(asked.lineFor(played), isNotNull);
        return;
      }
      fail('no deal had a lead the coach left out');
    });

    test('a position that is not the seat\'s turn fails the job instead of answering for someone else', () {
      final game = ddzSampleGame(1);
      final input = coachAt(game, 5);
      final wrong = DdzCoachInput(record: input.record, seat: (input.seat + 1) % 3, seed: 1);
      final reply = jsonDecode(runJobRequest(encodeRequest(1, coach, wrong, platform: JobPlatform.test), kitJobs));
      expect((reply as Map)['err'], contains('turn'));
    });

    test('the analysis survives its JSON round trip', () {
      final game = ddzSampleGame(1);
      final (advice, _) = viaRequest(coach, coachAt(game, firstLead(game) + 1));
      final again = DdzAdvice.fromJson(jsonDecode(jsonEncode(advice.toJson())));
      expect(jsonEncode(again.toJson()), jsonEncode(advice.toJson()));
    });
  });

  group('the bot job', () {
    test('plays a legal move for its seat, as the record writes it, with cards the seat holds', () {
      final game = ddzSampleGame(2);
      for (final level in KitLevel.values) {
        for (final i in [0, firstLead(game), firstLead(game) + 5]) {
          final position = game.upTo(i);
          final seat = toAct(position);
          final (move, _) = viaRequest(bot, DdzBotInput(record: position.jobJson(), seat: seat, level: level, seed: 4));
          final replay = ddzReplay(position);
          expect(() => ddzApply(replay, move), returnsNormally, reason: '$level at $i: $move');
          expect(ddzParseMove(move).seat, seat);
        }
      }
    });

    test('the same seed gives the same move', () {
      final game = ddzSampleGame(5);
      final position = game.upTo(firstLead(game) + 1);
      final input = DdzBotInput(record: position.jobJson(), seat: toAct(position), level: KitLevel.hard, seed: 12);
      expect(viaRequest(bot, input).$1, viaRequest(bot, input).$1);
    });
  });

  group('budgets', () {
    test('no cap means no time limit; a cap leaves room to send the answer', () {
      expect(ddzCoachBudget(JobPlatform.desktop, null).maxTime, isNull);
      expect(ddzCoachBudget(JobPlatform.desktop, const Duration(seconds: 1)).maxTime, const Duration(milliseconds: 800));
      expect(ddzBotBudget(DdzLevel.hard, JobPlatform.phone, null).maxTime, isNull);
    });

    test('JavaScript and phones get half the work of a PC, Think longer three times', () {
      final pc = ddzCoachBudget(JobPlatform.desktop, null).rollouts;
      expect(ddzCoachBudget(JobPlatform.webJs, null).rollouts, pc ~/ 2);
      expect(ddzCoachBudget(JobPlatform.phone, null).rollouts, pc ~/ 2);
      expect(ddzCoachBudget(JobPlatform.webWasm, null).rollouts, pc);
      expect(ddzCoachBudget(JobPlatform.desktop, null, deep: true).rollouts, pc * 3);
      expect(ddzBotBudget(DdzLevel.hard, JobPlatform.desktop, null).rollouts, DdzBudget.hard.rollouts);
    });
  });

  test('the cross-platform check has about 30 positions per job, all valid', () {
    expect(coach.checkInputs().length, inInclusiveRange(25, 35));
    expect(bot.checkInputs().length, inInclusiveRange(15, 35));
    for (final input in [...coach.checkInputs(), ...bot.checkInputs().map((b) => b)]) {
      final record = switch (input) {
        DdzCoachInput(:final record) => record,
        DdzBotInput(:final record) => record,
        _ => throw StateError('input'),
      };
      expect(ddzRecordFromJson(record), isNotNull);
    }
  });
}
