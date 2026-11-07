// The blackjack controller: a shoe is a game, the strategy chart is made
// once before the first turn, the coach answers every decision (never the
// deal), moves are graded with the engine's lines, and the shoe is saved
// after every move.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/blackjack/app/blackjack_grading.dart';
import 'package:pokerfection/src/games/blackjack/app/blackjack_jobs.dart';
import 'package:pokerfection/src/games/blackjack/app/blackjack_record.dart';
import 'package:pokerfection/src/games/blackjack/blackjack.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/kit/jobs/jobs_core.dart';
import 'package:pokerfection/src/ui/games/blackjack/blackjack_controller.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import '../../../kit/fakes.dart';
import 'blackjack_scenes.dart' show CountingChartJob;

BlackjackController controllerFor(BlackjackSettings settings, {required Jobs jobs, LastGames? lastGames}) =>
    BlackjackController(
      settings: settings,
      jobs: jobs,
      lastGames: lastGames ?? LastGames(),
      playerName: 'Player',
      dealerName: 'Dealer',
      speed: () => PlaybackSpeed.instant,
    );

/// Plays the chart's move (the coach's pick) at every decision, or the
/// first legal one without an answer, dealing between rounds, until the
/// shoe ends or [moves] moves were made.
Future<void> playOn(BlackjackController game, {int moves = 1000}) async {
  for (var i = 0; i < moves && !game.isOver; i++) {
    await settle();
    final legal = game.play.legalMoves();
    final pick = game.coach?.pick;
    game.humanMove(pick != null && legal.contains(pick) ? pick : legal.first);
  }
  await settle();
}

void main() {
  final single = BlackjackSettings(rules: BlackjackRules.preset(BlackjackPreset.singleDeck));

  test('a whole shoe plays to the cut card: one game, its result, and a grade for every decision', () async {
    final store = LastGames();
    final game = controllerFor(single, jobs: Jobs.inline(), lastGames: store);
    await game.newGame();
    await settle();
    expect(game.chart, isNotNull, reason: 'the chart is made before the first turn');
    expect(game.betweenRounds, isTrue);
    expect(game.coachWanted(playerSeat), isFalse, reason: 'no coach on the deal');
    await playOn(game);
    expect(game.isOver, isTrue);
    expect(game.play.table.shoe.needsShuffle, isTrue);
    expect(game.seatToAct, isNull);
    final record = game.record;
    expect(record.result, {'winners': game.winners, 'net': game.play.net, 'rounds': game.play.rounds});
    expect(game.winners, game.play.net > 0 ? [playerSeat] : (game.play.net < 0 ? [dealerSeat] : <int>[]));
    for (var i = 0; i < record.moves.length; i++) {
      if (record.moves[i] == dealMove) {
        expect(record.marks[i], isNull, reason: 'the deal is never graded');
      } else {
        expect(record.marks[i], isNotNull, reason: 'decision $i (${record.moves[i]}) is graded');
        expect(record.marks[i]!.score, 100, reason: 'the chart\'s play is Best');
      }
    }
    expect(game.averageScore, 100);
    await store.flush();
    final saved = await store.load('blackjack', version: blackjackRecordVersion);
    expect(saved!.moves, record.moves, reason: 'the whole shoe is saved');
    game.dispose();
  });

  test('a move off the chart is graded below Best, against the exact values', () async {
    final game = controllerFor(const BlackjackSettings(), jobs: Jobs.inline());
    await game.newGame();
    await settle();
    // Deal until a decision where standing is legal but isn't the chart's play.
    for (var i = 0; i < 400; i++) {
      await settle();
      if (game.betweenRounds) {
        game.humanMove(dealMove);
        continue;
      }
      final hand = game.play.handToPlay!;
      final answer = game.coach!;
      final stand = handMove(hand, BlackjackAction.stand);
      if (answer.pick != stand && answer.rates(stand) && !answer.alsoBest.contains(stand)) {
        final i = game.record.moves.length;
        game.humanMove(stand);
        await settle();
        final mark = game.record.marks[i]!;
        expect(mark.score, lessThan(100));
        expect(mark.best, answer.pick);
        expect(mark.loss, closeTo(answer.bestValue! - answer.lineFor(stand)!.value, 1e-9));
        game.dispose();
        return;
      }
      game.humanMove(answer.pick);
    }
    fail('no decision where standing was off the chart');
  });

  test('Free Play: no chart, no coach, no grades', () async {
    final chartJob = CountingChartJob();
    final game = controllerFor(
      BlackjackSettings(rules: single.rules, training: false),
      jobs: Jobs.inline(extra: {chartJob.name: chartJob}),
    );
    await game.newGame();
    await settle();
    expect(chartJob.runs, 0);
    await playOn(game, moves: 30);
    expect(game.record.marks.every((m) => m == null), isTrue);
    expect(game.coach, isNull);
    expect(game.record.extra['mode'], 'free');
    game.dispose();
  });

  test('nobody moves before the chart is made, and a new shoe with the same rules keeps it', () async {
    final backend = ManualBackend({for (final job in blackjackJobs) job.name: job});
    final game = controllerFor(single, jobs: Jobs.using(backend));
    final starting = game.newGame();
    await settle();
    expect(game.preparing, isTrue);
    expect(backend.on(JobLane.coach)?.name, 'blackjack.chart');
    expect(() => game.humanMove(dealMove), throwsStateError, reason: 'no turn before the chart');
    backend.answer(backend.on(JobLane.coach)!);
    await starting;
    await settle();
    expect(game.preparing, isFalse);
    expect(game.chart!.rules, single.rules);
    expect(
      game.record.extra.keys,
      isNot(contains('chart')),
      reason: 'nothing kept beyond the game: the review makes its own',
    );
    game.humanMove(dealMove);
    await settle();
    if (!game.betweenRounds) {
      final coach = backend.on(JobLane.coach)!;
      expect(coach.name, 'blackjack.coach');
      expect(coach.request, contains('"chart":'), reason: 'every coach job carries the chart');
    }
    final before = backend.started.where((j) => j.name == 'blackjack.chart').length;
    await game.newGame();
    await settle();
    expect(backend.started.where((j) => j.name == 'blackjack.chart').length, before, reason: 'same rules, same chart');
    expect(game.preparing, isFalse);
    game.dispose();
  });

  test('a failed chart job doesn\'t stop the game: the coach goes without it', () async {
    final reported = <FlutterErrorDetails>[];
    final before = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = before);
    final backend = ManualBackend({for (final job in blackjackJobs) job.name: job});
    final game = controllerFor(single, jobs: Jobs.using(backend));
    final starting = game.newGame();
    await settle();
    backend.fail(backend.on(JobLane.coach)!);
    await starting;
    await settle();
    expect(reported.single.exception, isA<JobFailed>(), reason: 'the failure is reported, not hidden');
    expect(game.preparing, isFalse);
    expect(game.chart, isNull);
    game.humanMove(dealMove);
    expect(game.record.moves, [dealMove]);
    game.dispose();
  });

  test('a new shoe cancels the jobs of the old one', () async {
    final backend = ManualBackend({for (final job in blackjackJobs) job.name: job});
    final game = controllerFor(single, jobs: Jobs.using(backend));
    final starting = game.newGame();
    await settle();
    backend.answer(backend.on(JobLane.coach)!);
    await starting;
    // Deal until the coach is asked about a decision.
    while (backend.on(JobLane.coach) == null) {
      game.humanMove(game.play.legalMoves().first);
      await settle();
    }
    final pending = backend.on(JobLane.coach)!;
    await game.newGame();
    await settle();
    expect(pending.token.isCancelled, isTrue);
    expect(game.record.moves, isEmpty);
    game.dispose();
  });

  test('the Count toggle and the coach chip are kept in the record and survive into the next shoe', () async {
    final game = controllerFor(single, jobs: Jobs.inline());
    await game.newGame();
    await settle();
    expect(game.showCount, isFalse);
    game.showCount = true;
    game.coachVisible = false;
    await game.newGame();
    await settle();
    expect(game.showCount, isTrue);
    expect(game.coachVisible, isFalse);
    expect(game.record.extra['coachMode'], 'fresh');
    game.dispose();
  });

  test('the settings come back from a saved record', () {
    final record = newBlackjackRecord(
      rules: BlackjackRules.preset(BlackjackPreset.european),
      seed: 5,
      playerName: 'Player',
      dealerName: 'Dealer',
      extra: const BlackjackSettings(training: false, coachMode: CoachMode.seen).extra,
    );
    final settings = BlackjackSettings.fromRecord(record);
    expect(settings.rules, BlackjackRules.preset(BlackjackPreset.european));
    expect(settings.training, isFalse);
    expect(settings.coachMode, CoachMode.seen);
  });

  test('Think longer is greyed out: the values are already exact', () async {
    final game = controllerFor(single, jobs: Jobs.inline());
    await game.newGame();
    await settle();
    expect(game.canThinkLonger, isFalse);
    game.dispose();
  });
}
