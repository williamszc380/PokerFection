import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/gomoku/app/gomoku_analysis.dart';
import 'package:pokerfection/src/games/gomoku/app/gomoku_jobs.dart';
import 'package:pokerfection/src/games/gomoku/app/gomoku_record.dart';
import 'package:pokerfection/src/games/gomoku/gomoku.dart';
import 'package:pokerfection/src/kit/coach_answer.dart';
import 'package:pokerfection/src/kit/jobs/job_registry.dart';
import 'package:pokerfection/src/kit/jobs/jobs_core.dart';
import 'package:pokerfection/src/kit/seats.dart';

import 'positions.dart';

/// Runs [job] on [input] as a worker would: through the request and reply.
Object? _run(
  GameJob<Object?, Object?> job,
  Object? input, {
  JobPlatform platform = JobPlatform.desktop,
  Duration? cap,
}) {
  final reply = jsonDecode(
    runJobRequest(encodeRequest(1, job, input, platform: platform, cap: cap), kitJobs),
  ) as Map<String, Object?>;
  expect(reply['err'], isNull);
  return reply['out'];
}

Map<String, Object?> _position(String moves, {GomokuRules rules = GomokuRules.freestyle}) => GomokuRecord.start(
  GomokuOptions(rules: rules),
  seed: 1,
  moves: [
    for (final m in moves.split(' '))
      if (m.isNotEmpty) m,
  ],
).jobJson();

void main() {
  const coach = GomokuCoachJob();
  const bot = GomokuBotJob();

  test('the coach and the bot are registered by name', () {
    expect(kitJobs['gomoku.coach'], isA<GomokuCoachJob>());
    expect(kitJobs['gomoku.bot'], isA<GomokuBotJob>());
  });

  test('every example and check position replays to a game still going, with the seat to move', () {
    for (final input in [...coach.examples(), ...coach.checkInputs()]) {
      final game = GomokuRecord.replayJson(input.record);
      expect(game.isOver, isFalse, reason: '${input.record['moves']}');
      expect(GomokuRecord.colorOf(input.seat), game.toMove);
    }
    for (final input in [...bot.examples(), ...bot.checkInputs()]) {
      expect(GomokuRecord.colorOf(input.seat), GomokuRecord.replayJson(input.record).toMove);
    }
    expect(coach.checkInputs().length, inInclusiveRange(25, 40), reason: 'about 30 for the cross-platform check');
  });

  group('no timing and no hidden limits', () {
    test('without a cap the engine gets an explicit day, never its own default', () {
      expect(gomokuTimeFor(JobContext(platform: JobPlatform.desktop)), gomokuNoLimit);
      expect(gomokuCoachBudget(JobContext(platform: JobPlatform.desktop), GomokuDepth.normal).maxTime, gomokuNoLimit);
    });

    test('with a cap the engine stops a little before the job must', () {
      final time = gomokuTimeFor(JobContext(platform: JobPlatform.desktop, timeCap: const Duration(seconds: 1)));
      expect(time, lessThan(const Duration(seconds: 1)));
      expect(time, greaterThan(const Duration(milliseconds: 900)));
    });

    test('budgets: the default on every platform, the quick one in tests, the deep one for Think longer', () {
      CoachBudget budget(JobPlatform p, GomokuDepth d) => gomokuCoachBudget(JobContext(platform: p), d);
      for (final p in [JobPlatform.desktop, JobPlatform.phone, JobPlatform.webWasm, JobPlatform.webJs]) {
        expect(budget(p, GomokuDepth.normal).searchNodes, const CoachBudget().searchNodes);
      }
      expect(budget(JobPlatform.test, GomokuDepth.normal).searchNodes, CoachBudget.quick.searchNodes);
      expect(budget(JobPlatform.test, GomokuDepth.deep).searchNodes, CoachBudget.deep.searchNodes);
    });

    test('the coach\'s output leaves out its time, and the same position gives the same output', () {
      final input = GomokuCoachInput(record: _position('h8 h9 i9'), seat: 1);
      final first = _run(coach, input)! as Map<String, Object?>;
      expect(first.containsKey('micros'), isFalse);
      expect(_run(coach, input), first);
      expect(decodeGomokuAnalysis(first).elapsed, Duration.zero);
    });

    test('the bot repeats exactly for a seed, at every level', () {
      for (final level in KitLevel.values) {
        final input = GomokuBotInput(record: _position('h8 h9 i9 j10'), seat: 0, level: level, seed: 4);
        expect(_run(bot, input), _run(bot, input), reason: '$level');
      }
    });
  });

  group('the coach job', () {
    test('analyses the position the record leads to, for the side to move', () {
      final analysis = coach.decodeOutput(_run(coach, GomokuCoachInput(record: _position(fourThree), seat: 0)));
      expect(analysis.toMove, Stone.black);
      expect(analysis.best!.move.notation, 'i8');
      expect(analysis.best!.winsIn, 3);
    });

    test('analyses a move it was asked to include, however poor', () {
      final input = GomokuCoachInput(record: _position('h8 h9'), seat: 0, include: 'a1', depth: GomokuDepth.quick);
      final analysis = coach.decodeOutput(_run(coach, input));
      expect(analysis.of(GomokuMove.parse('a1')), isNotNull);
    });

    test('in tests it takes the quick look, the same as asking for it', () {
      final quick = GomokuCoachInput(record: _position('h8 i9'), seat: 0, depth: GomokuDepth.quick);
      final normal = GomokuCoachInput(record: _position('h8 i9'), seat: 0);
      expect(_run(coach, normal, platform: JobPlatform.test), _run(coach, quick));
    });

    test('a Renju position where Black must pass gets a single pass', () {
      final analysis = coach.decodeOutput(
        _run(coach, GomokuCoachInput(record: _position(stuckRenju, rules: GomokuRules.renju), seat: 0)),
      );
      expect([for (final m in analysis.moves) m.move], [GomokuMove.pass]);
      expect(analysis.best!.reasons, [MoveReason.mustPass]);
    });

    test('its input survives JSON', () {
      const input = GomokuCoachInput(record: {'moves': <Object?>[]}, seat: 1, include: 'h8', depth: GomokuDepth.deep);
      final copy = GomokuCoachInput.fromJson(jsonDecode(jsonEncode(input.toJson())));
      expect(copy.toJson(), input.toJson());
    });
  });

  group('the bot job', () {
    test('plays a legal move for its seat, and blocks a four', () {
      final output = bot.decodeOutput(
        _run(bot, GomokuBotInput(record: _position(mustBlock), seat: 0, level: KitLevel.easy, seed: 1)),
      );
      expect(output.move, 'h10');
      expect(output.how, 'block');
    });

    test('passes when Black must', () {
      final input = GomokuBotInput(
        record: _position(stuckRenju, rules: GomokuRules.renju),
        seat: 0,
        level: KitLevel.hard,
        seed: 1,
      );
      expect(bot.decodeOutput(_run(bot, input)).move, 'pass');
    });

    test('its input and output survive JSON', () {
      const input = GomokuBotInput(record: {'moves': <Object?>[]}, seat: 0, level: KitLevel.hard, seed: 77);
      expect(GomokuBotInput.fromJson(jsonDecode(jsonEncode(input.toJson()))).toJson(), input.toJson());
      const output = GomokuBotOutput('h8', how: 'center');
      expect(GomokuBotOutput.fromJson(jsonDecode(jsonEncode(output.toJson()))).toJson(), output.toJson());
    });
  });

  group('the conversion to the kit\'s coach answer', () {
    final analysis = const GomokuCoach(budget: CoachBudget.quick)
        .analyze(GomokuGame.fromMoves(GomokuRules.freestyle, GomokuGame.parseMoves(fourThree)).viewFor(Stone.black));
    final answer = gomokuAnswer(analysis);

    test('one line per analysed move, in the engine\'s order, worth its win chance', () {
      expect([for (final l in answer.lines) l.move], [for (final m in analysis.moves) m.move.notation]);
      expect([for (final l in answer.lines) l.value], [for (final m in analysis.moves) m.winChance]);
      expect(answer.unit, ValueUnit.winChance);
    });

    test('the engine\'s best move is the pick, and the analysis rides along for grading', () {
      expect(answer.pick, 'i8');
      expect(answer.detail, same(analysis));
    });

    test('proofs become codes, reasons their names', () {
      final top = answer.lineFor('i8')!;
      expect(top.proof, 'win:3');
      expect(top.reasons, ['startsForcedWin', 'makesFourThree']);
      expect(parseGomokuProof('win:3'), (true, 3));
      expect(parseGomokuProof('loss:2'), (false, 2));
      expect(parseGomokuProof('sure'), isNull);
      for (final (line, move) in [for (var i = 0; i < answer.lines.length; i++) (answer.lines[i], analysis.moves[i])]) {
        expect(line.proof, gomokuProof(move));
      }
    });

    test('the analysis survives the job\'s codec', () {
      final copy = decodeGomokuAnalysis(jsonDecode(jsonEncode(encodeGomokuAnalysis(analysis))));
      expect(encodeGomokuAnalysis(copy), encodeGomokuAnalysis(analysis));
    });

    test('win chances go out to 4 decimal places, so the apps and a browser answer alike', () {
      // The digits past the 4th come from exp(), which differs in its last
      // binary digit between native code and JavaScript or WebAssembly.
      expect(roundWinChance(0.37832433367012236), 0.3783);
      expect(roundWinChance(0.3783243336701223), 0.3783);
      expect(roundWinChance(1), 1.0);
      final moves = encodeGomokuAnalysis(analysis)['moves']! as List;
      for (final move in moves.cast<Map<String, Object?>>()) {
        final chance = move['winChance']! as double;
        expect(chance, roundWinChance(chance));
        expect((chance * 10000 - (chance * 10000).round()).abs(), lessThan(1e-6));
      }
    });
  });
}
