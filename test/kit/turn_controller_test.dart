import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/gto/spot_strategy.dart' show DecisionGrade;
import 'package:pokerfection/src/kit/game_record.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/kit/jobs/jobs_core.dart' show JobCancelled;
import 'package:pokerfection/src/ui/kit/game_sounds.dart';
import 'package:pokerfection/src/ui/kit/turn_controller.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import 'fakes.dart';
import 'nim.dart';

/// Nim with start-up work (Blackjack's chart, say) that the test finishes
/// by hand, one per deal.
class _SlowStartNim extends NimController {
  _SlowStartNim({required super.jobs});

  final starts = <Completer<void>>[];

  /// Whether the next games have anything to prepare.
  bool slow = true;

  /// The moves the coach must list, as a game reads them from its table now.
  List<String> listing = const [];

  @override
  Future<void>? prepare() => slow ? (starts..add(Completer())).last.future : null;

  @override
  List<String> listedMoves(int seat) => listing;
}

/// Nim where the player must take exactly 1 whenever an odd number of
/// stones is left (a forced move, as a peasant's Pass when nothing beats
/// the table).
class _ForcedNim extends NimController {
  _ForcedNim({required super.jobs, super.speed});

  @override
  String? forcedMove(int seat) => left.isOdd ? '1' : null;
}

/// Nim whose start-up work fails.
class _BrokenStartNim extends NimController {
  _BrokenStartNim({required super.jobs});

  @override
  Future<void> prepare() async => throw StateError('no chart');
}

void main() {
  late ManualBackend backend;
  late Jobs jobs;

  setUp(() {
    backend = ManualBackend(nimJobs);
    jobs = Jobs.using(backend);
  });

  Future<NimController> started(NimController game) async {
    await game.newGame();
    await settle();
    return game;
  }

  test('the player moves first, and the coach works on the position at once, even while hidden', () async {
    final game = await started(NimController(jobs: jobs, extraAtStart: {'coach': false}));
    expect(game.coachVisible, isFalse);
    expect(game.seatToAct, 0);
    expect(backend.on(JobLane.coach)?.name, 'nim.coach', reason: 'the answer also grades the move');
    expect(game.coachThinking, isTrue);
    backend.answer(backend.on(JobLane.coach)!);
    await settle();
    expect(game.coach!.pick, '3', reason: 'taking 3 of 7 leaves 4, a sure win');
    expect(game.coachThinking, isFalse);
  });

  test('a game with no choice on record starts with the coach hidden; one on record is kept', () async {
    expect(TurnController.coachShownAtFirst, isFalse);
    final fresh = await started(NimController(jobs: jobs));
    expect(fresh.coachVisible, isFalse);
    expect(fresh.record.extra.containsKey('coach'), isFalse);
    final shown = await started(NimController(jobs: Jobs.using(backend), extraAtStart: {'coach': true}));
    expect(shown.coachVisible, isTrue, reason: "the last game's choice");
  });

  test('a bot plays on the bot lane after the player, then the turn comes back with a chime', () async {
    final game = await started(NimController(jobs: jobs));
    game.humanMove('3');
    await settle();
    expect(game.thinkingSeat, 1);
    expect(backend.on(JobLane.bot)?.name, 'nim.bot');
    backend.answer(backend.on(JobLane.bot)!);
    await settle();
    expect(game.record.moves, ['3', '1']);
    expect(game.seatToAct, 0);
    expect(game.sounds, [SoundEffect.stone, SoundEffect.stone, SoundEffect.yourTurn]);
  });

  test('a bot job that fails or times out hands the move to the Easy bot: the game never stalls', () async {
    final game = await started(NimController(jobs: jobs, pile: 9));
    game.humanMove('2');
    await settle();
    backend.fail(backend.on(JobLane.bot)!, 'timeout');
    await settle();
    expect(game.record.moves, ['2', '1'], reason: "the fallback takes 1 (the job's answer would be 3)");
    expect(game.seatToAct, 0);
  });

  group('grading', () {
    test('now: the answer is here and rates the move', () async {
      final game = await started(NimController(jobs: jobs));
      backend.answer(backend.on(JobLane.coach)!);
      await settle();
      game.humanMove('3');
      expect(game.marks.first?.grade, DecisionGrade.best);
      expect(game.marks.first?.score, 100);
      await settle();
      expect(backend.on(JobLane.bot), isNotNull);
    });

    test('later: a move made before the answer came is graded when it comes, and the bot does not wait', () async {
      final game = await started(NimController(jobs: jobs));
      final show = backend.on(JobLane.coach)!;
      game.humanMove('1');
      await settle();
      expect(game.marks.first, isNull);
      expect(backend.on(JobLane.bot), isNotNull, reason: 'bots never wait for grades');
      backend.answer(show);
      await settle();
      final mark = game.marks.first!;
      expect([mark.grade, mark.played, mark.best], [DecisionGrade.mistake, '1', '3']);
      expect(mark.loss, closeTo(0.12, 1e-9), reason: '0.9 − 0.78');
    });

    test('with include: a move the answer left out is rated by a second job from the position before it', () async {
      final game = await started(NimController(jobs: jobs, top: 1));
      backend.answer(backend.on(JobLane.coach)!);
      await settle();
      expect(game.coach!.lines.map((l) => l.move), ['3'], reason: 'only the top move');
      game.humanMove('2');
      await settle();
      expect(game.coachJobs, ['grade:0']);
      final regrade = backend.on(JobLane.coach)!;
      expect(regrade.request, contains('"include":"2"'));
      expect(regrade.request, contains('"moves":[]'), reason: 'the position before the move');
      backend.answer(regrade);
      await settle();
      expect(game.marks.first?.grade, DecisionGrade.inaccuracy, reason: 'leaves 5: 0.84 against 0.9');
    });

    test('ungraded: an engine without include leaves the move ungraded, never guessed', () async {
      final game = await started(NimController(jobs: jobs, top: 1, honorsInclude: false));
      backend.answer(backend.on(JobLane.coach)!);
      await settle();
      game.humanMove('2');
      await settle();
      backend.answer(backend.on(JobLane.coach)!);
      await settle();
      expect(game.marks.first, isNull);
      expect(game.coachJobs, isEmpty);
    });

    test('Free Play starts no coach jobs and grades nothing; the coach chip has nothing to show', () async {
      final game = await started(NimController(jobs: jobs, training: false));
      expect(backend.on(JobLane.coach), isNull);
      game.humanMove('1');
      await settle();
      backend.answer(backend.on(JobLane.bot)!);
      await settle();
      expect(backend.started.map((j) => j.name), ['nim.bot']);
      expect(game.marks, [null, null]);
      expect(game.canThinkLonger, isFalse);
    });
  });

  test('Think longer replaces only the answer on show; an earlier move\'s grade job keeps running', () async {
    final game = await started(NimController(jobs: jobs, pile: 9, top: 1));
    backend.answer(backend.on(JobLane.coach)!);
    await settle();
    game.humanMove('2'); // Not rated: grade:0 starts.
    await settle();
    backend.answer(backend.on(JobLane.bot)!);
    await settle();
    expect(game.seatToAct, 0);
    expect(game.coachJobs, unorderedEquals(['grade:0', 'show:2']));
    expect(game.canThinkLonger, isTrue);

    game.thinkLonger();
    expect(game.coachJobs, unorderedEquals(['grade:0', 'deep:2']), reason: 'the grade job is never cancelled by it');
    expect(game.canThinkLonger, isFalse, reason: 'already thinking longer');
    backend.answer(backend.on(JobLane.coach)!); // grade:0 first (first in, first out)
    await settle();
    expect(game.marks.first, isNotNull);
    backend.answer(backend.on(JobLane.coach)!);
    await settle();
    expect(game.coach!.lines.single.reasons, contains('deep'));
  });

  test('a passed answer is cancelled once nothing waits on it to grade', () async {
    final game = await started(NimController(jobs: jobs, pile: 9));
    final show = backend.on(JobLane.coach)!;
    game.humanMove('1');
    expect(show.token.isCancelled, isFalse, reason: 'it still grades move 0');
    backend.answer(show);
    await settle();
    expect(game.coachJobs, isEmpty);
  });

  test('a new game cancels both lanes, and replies that arrive late change nothing', () async {
    final game = await started(NimController(jobs: jobs, pile: 9));
    game.humanMove('1');
    await settle();
    final bot = backend.on(JobLane.bot)!;
    final show = backend.started.first;
    await game.newGame();
    await settle();
    expect(bot.token.isCancelled, isTrue);
    backend.answer(bot);
    backend.answer(show);
    await settle();
    expect(game.record.moves, isEmpty);
    expect(game.marks, isEmpty);
    expect(game.deals, 2);
  });

  test('a deal that ends shows Next deal; the next deal keeps the seats, rules and toggles', () async {
    final game = NimController(jobs: Jobs.inline(extra: nimJobs), pile: 4, rounds: true);
    await started(game);
    game.humanMove('3');
    await settle();
    expect(game.isOver, isTrue);
    expect(game.winners, [1]);
    expect(game.between, isTrue);
    expect(game.record.result, {'winners': [1]});
    expect(game.sounds.last, SoundEffect.lose);
    game.setExtra('sort', true);
    game.coachVisible = false;
    await game.nextRound();
    await settle();
    expect(game.deals, 2);
    expect(game.between, isFalse);
    expect(game.record.moves, isEmpty);
    expect([game.record.extra['sort'], game.coachVisible, game.record.extra['mode']], [true, false, 'training']);
    expect(game.averageScore, 100, reason: "the session's grades are kept across deals");
  });

  test('a game that is not played in rounds ends with New game, not Next deal', () async {
    final game = NimController(jobs: Jobs.inline(extra: nimJobs), pile: 3);
    await started(game);
    game.humanMove('3');
    await settle();
    expect([game.isOver, game.between, game.winners], [true, false, [0]]);
    expect(game.sounds.last, SoundEffect.win);
  });

  test('an animation holds the turns until the game resumes them', () async {
    final game = await started(NimController(jobs: Jobs.inline(extra: nimJobs), pile: 9)..animateMoves = true);
    game.humanMove('1');
    await settle();
    expect(game.record.moves, ['1'], reason: 'the bot waits for the animation');
    game.animating = false;
    game.resume();
    await settle();
    expect(game.record.moves, hasLength(2));
  });

  test('an illegal move throws and changes nothing', () async {
    final game = await started(NimController(jobs: jobs));
    expect(() => game.humanMove('4'), throwsArgumentError);
    expect(game.record.moves, isEmpty);
    expect(game.seatToAct, 0);
  });

  test('the record is saved at the start and after every move and grade, with the toggles in extra', () async {
    final store = LastGames();
    final game = NimController(jobs: Jobs.inline(extra: nimJobs), lastGames: store, pile: 9);
    await started(game);
    var saved = await store.load('nim', version: 1);
    expect(saved?.moves, isEmpty);

    game.coachVisible = false;
    game.humanMove('2');
    await settle();
    saved = await store.load('nim', version: 1);
    expect(saved!.moves, game.record.moves);
    expect(saved.moves, hasLength(2));
    expect(saved.marks.first?.grade, DecisionGrade.mistake);
    expect(saved.extra, {'mode': 'training', 'coach': false});
    game.dispose();
  });

  test('closing the screen cancels its jobs, stops its threads and writes the record', () async {
    final store = LastGames();
    final game = await started(NimController(jobs: jobs, lastGames: store));
    final show = backend.on(JobLane.coach)!;
    game.dispose();
    expect(show.token.isCancelled, isTrue);
    expect(backend.disposed, isTrue);
    expect((await store.load('nim', version: 1))?.game, 'nim');
  });

  group('prepare (runs alongside the game: no turn waits for it)', () {
    test('a game with nothing to prepare starts its coach job at once', () async {
      final game = NimController(jobs: jobs);
      unawaited(game.newGame());
      expect(game.preparing, isFalse);
      expect(game.coachJobs, ['show:0']);
    });

    test('the player and the bots move while it runs; the coach job waits for it, then starts', () async {
      final game = _SlowStartNim(jobs: jobs);
      unawaited(game.newGame());
      await settle();
      expect(game.preparing, isTrue);
      expect(game.playerToMove, isTrue, reason: 'the first turn is not held');
      expect(game.coachJobs, ['wait:0'], reason: 'the coach needs what prepare() makes');
      expect(game.coachThinking, isTrue);
      expect(backend.started, isEmpty);
      game.humanMove('1');
      expect(game.record.moves, ['1']);
      await settle();
      expect(backend.on(JobLane.bot)?.name, 'nim.bot', reason: 'bots go on meanwhile');
      backend.answer(backend.on(JobLane.bot)!);
      await settle();
      expect(game.record.moves, ['1', '2']);
      expect(game.seatToAct, 0);
      expect(game.coachJobs, ['wait:0', 'wait:2'], reason: 'move 0 still waits to be graded');
      expect(game.marks.first, isNull);
      game.starts.single.complete();
      await settle();
      expect(game.preparing, isFalse);
      expect(game.coachJobs, ['show:0', 'show:2']);
      final running = backend.on(JobLane.coach)!;
      expect(running.request, contains('"moves":[]'), reason: "one coach job at a time: move 0's first");
    });

    test('a move made while it runs is graded once its coach job answers', () async {
      final game = _SlowStartNim(jobs: jobs);
      unawaited(game.newGame());
      await settle();
      game.humanMove('1');
      await settle();
      backend.answer(backend.on(JobLane.bot)!);
      await settle();
      game.starts.single.complete();
      await settle();
      expect(game.marks.first, isNull, reason: 'its job has only just started');
      final show = backend.on(JobLane.coach)!;
      expect(show.request, contains('"moves":[]'), reason: 'the position of move 0, not the one on the table');
      backend.answer(show);
      await settle();
      final mark = game.marks.first!;
      expect([mark.grade, mark.played, mark.best], [DecisionGrade.mistake, '1', '3']);
      expect(game.coachJobs, ['show:2']);
    });

    test('a coach job that waited lists the moves of its turn, not those on the table when it starts', () async {
      final game = _SlowStartNim(jobs: jobs)..listing = ['2'];
      unawaited(game.newGame());
      await settle();
      game.listing = ['1'];
      game.starts.single.complete();
      await settle();
      backend.answer(backend.on(JobLane.coach)!);
      await settle();
      expect(game.coach!.listed, {'2'});
    });

    test("a new game while the last one prepares starts only its own coach jobs, after its own prepare()", () async {
      final game = _SlowStartNim(jobs: jobs);
      unawaited(game.newGame());
      await settle();
      unawaited(game.newGame());
      await settle();
      expect(game.coachJobs, ['wait:0']);
      game.starts.first.complete();
      await settle();
      expect(game.preparing, isTrue, reason: "the new game's prepare() still runs");
      expect(backend.started, isEmpty, reason: "the old game's prepare() starts nothing");
      game.starts.last.complete();
      await settle();
      expect(game.preparing, isFalse);
      expect(backend.running.map((job) => job.name), ['nim.coach']);
    });

    test('a new game with nothing to prepare is not held by the last one that still prepares', () async {
      final game = _SlowStartNim(jobs: jobs);
      unawaited(game.newGame());
      await settle();
      game.slow = false;
      unawaited(game.newGame());
      expect(game.preparing, isFalse);
      expect(game.coachJobs, ['show:0']);
      game.starts.single.complete();
      await settle();
      expect(backend.running.map((job) => job.name), ['nim.coach']);
    });

    test('a prepare() that fails is reported, and the coach jobs that waited start without it', () async {
      final reported = <FlutterErrorDetails>[];
      final before = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = before);
      final game = _BrokenStartNim(jobs: jobs);
      unawaited(game.newGame());
      expect(game.coachJobs, ['wait:0']);
      await settle();
      expect(reported.single.exception, isStateError);
      expect(game.preparing, isFalse);
      expect(game.coachJobs, ['show:0']);
      expect(backend.on(JobLane.coach)?.name, 'nim.coach');
    });

    test("a prepare() cancelled because the game was left is no error", () async {
      final reported = <FlutterErrorDetails>[];
      final before = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = before);
      final game = _SlowStartNim(jobs: jobs);
      unawaited(game.newGame());
      await settle();
      game.dispose();
      game.starts.single.completeError(const JobCancelled());
      await settle();
      expect(reported, isEmpty);
      expect(backend.started, isEmpty);
    });
  });

  group('a forced move', () {
    // On the widget tester's fake clock, so the pauses take no real time.
    testWidgets("plays itself after the bots' pause, with no coach job and no grade", (tester) async {
      final game = _ForcedNim(jobs: jobs, speed: PlaybackSpeed.normal);
      unawaited(game.newGame());
      await tester.pump();
      expect(game.seatToAct, 0, reason: "the player's turn, with 7 left (odd)");
      expect(backend.started, isEmpty, reason: 'nothing to coach: there is no choice');
      await tester.pump(const Duration(milliseconds: 590));
      expect(game.record.moves, isEmpty, reason: 'it waits as long as a bot would');
      await tester.pump(const Duration(milliseconds: 10));
      expect(game.record.moves, ['1']);
      expect(game.marks.whereType<Object>(), isEmpty, reason: 'never graded');
      expect(backend.on(JobLane.bot)?.name, 'nim.bot', reason: 'and the game goes on');
      game.dispose();
    });

    testWidgets('the player may make it sooner; the pause then plays nothing more', (tester) async {
      final game = _ForcedNim(jobs: jobs, speed: PlaybackSpeed.normal);
      unawaited(game.newGame());
      await tester.pump();
      game.humanMove('1');
      await tester.pump(const Duration(seconds: 1));
      expect(game.record.moves, ['1']);
      game.dispose();
    });

    testWidgets("a new deal drops a forced move still waiting; Instant plays it at once", (tester) async {
      final game = _ForcedNim(jobs: jobs, speed: PlaybackSpeed.normal);
      unawaited(game.newGame());
      await tester.pump(const Duration(milliseconds: 300));
      unawaited(game.newGame());
      await tester.pump(const Duration(milliseconds: 300));
      expect(game.record.moves, isEmpty, reason: "the old deal's pause plays nothing in the new one");
      await tester.pump(const Duration(milliseconds: 300));
      expect(game.record.moves, ['1'], reason: "the new deal's own pause");
      game.dispose();
      final instant = _ForcedNim(jobs: Jobs.using(ManualBackend(nimJobs)));
      unawaited(instant.newGame());
      await tester.pump();
      expect(instant.record.moves, ['1']);
      instant.dispose();
    });
  });

  test('each game and deal is stamped with when it was dealt (not the 1970 default)', () async {
    final before = DateTime.now();
    final game = await started(NimController(jobs: jobs, pile: 3, rounds: true));
    expect(game.record.played.isBefore(before), isFalse);
    expect(game.record.played.isAfter(DateTime.now()), isFalse);
    final first = game.record.played;
    game.humanMove('3');
    await settle();
    await game.nextRound();
    await settle();
    expect(game.record.played.isBefore(first), isFalse);
    expect(GameRecord(game: 'nim', version: 1, seed: 1).withMove('3').played, DateTime.fromMillisecondsSinceEpoch(0));
  });
}
