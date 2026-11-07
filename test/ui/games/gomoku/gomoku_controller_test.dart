import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/gomoku/app/gomoku_record.dart';
import 'package:pokerfection/src/games/gomoku/gomoku.dart';
import 'package:pokerfection/src/gto/spot_strategy.dart' show DecisionGrade;
import 'package:pokerfection/src/kit/game_keys.dart';
import 'package:pokerfection/src/kit/game_record.dart';
import 'package:pokerfection/src/kit/jobs/job_registry.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/kit/seats.dart';
import 'package:pokerfection/src/ui/games/gomoku/gomoku_controller.dart';
import 'package:pokerfection/src/ui/kit/game_sounds.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import '../../../kit/fakes.dart';

/// Remembers every record saved, in order.
class _Saves extends LastGames {
  final saved = <GameRecord>[];

  @override
  void save(GameRecord record) {
    saved.add(record);
    super.save(record);
  }
}

/// Lets queued jobs and pauses run (inline jobs run a microtask later).
Future<void> _settle([int rounds = 8]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

GomokuController _controller({
  GomokuOptions options = const GomokuOptions(level: KitLevel.easy),
  LastGames? lastGames,
  List<String> opening = const [],
  Map<String, Object?> toggles = const {},
}) => GomokuController(
  options: options,
  jobs: Jobs.inline(),
  lastGames: lastGames ?? LastGames(),
  speed: () => PlaybackSpeed.instant,
  toggles: toggles,
  opening: opening,
);

/// The player's move by the Easy bot (as a stand-in for a person).
String _easyMove(GomokuController c, int i) =>
    GomokuBot(BotLevel.easy, seed: 100 + i).chooseMove(c.game.viewFor(c.game.toMove)).notation;

/// Plays the player's turns with the Easy bot until the game ends.
Future<void> _playOut(GomokuController c) async {
  for (var i = 0; i < 300 && !c.isOver; i++) {
    await _settle();
    final seat = c.seatToAct;
    if (seat != null && c.isHuman(seat)) c.humanMove(_easyMove(c, i));
  }
  await _settle();
}

void main() {
  setUp(() => GameSounds.output = (_) {});

  test('the player is the colour chosen; Black moves first, so as White the bot opens', () async {
    final asWhite = _controller(
      options: const GomokuOptions(color: GomokuColorChoice.white, level: KitLevel.easy),
    );
    await asWhite.newGame();
    await _settle();
    expect(asWhite.playerColor, Stone.white);
    expect(asWhite.record.moves, hasLength(1), reason: "the bot's first stone");
    expect(asWhite.seatToAct, 1);
    expect(asWhite.isHuman(1), isTrue);
    asWhite.dispose();
  });

  test('a full game against the bot ends, with a winner (or a draw) in the record', () async {
    final c = _controller();
    await c.newGame();
    await _playOut(c);
    expect(c.isOver, isTrue);
    expect(c.record.result, isNotNull);
    final winner = c.game.result!.winner;
    expect(c.winners, [if (winner != null) GomokuRecord.seatOf(winner)]);
    if (winner != null) expect(c.record.result!['line'], hasLength(greaterThanOrEqualTo(5)));
    expect(GomokuRecord.replay(c.record).movesText(), c.game.movesText(), reason: 'the record replays to the game');
    c.dispose();
  });

  test('Training grades the player\'s moves with the engine\'s grading', () async {
    final c = _controller();
    await c.newGame();
    for (var i = 0; i < 4 && !c.isOver; i++) {
      await _settle();
      c.humanMove(_easyMove(c, i));
    }
    await _settle(20);
    final graded = [
      for (final (i, m) in c.marks.indexed)
        if (m != null) i,
    ];
    expect(graded, isNotEmpty);
    expect(graded.every((i) => c.isHuman(i.isEven ? 0 : 1)), isTrue, reason: "only the player's moves");
    for (final i in graded) {
      expect(c.marks[i]!.played, c.record.moves[i]);
    }
    expect(c.averageScore, isNotNull);
    c.dispose();
  });

  test('the best move is graded Best; leaving a four on the board is a Blunder', () async {
    // Black (the player) to move; White has a four d10-g10, closed at c10.
    final c = _controller(opening: ['c10', 'd10', 'h3', 'e10', 'j3', 'f10', 'l3', 'g10']);
    await c.newGame();
    await _settle();
    expect(c.coach?.pick, 'h10');
    expect(c.analysis!.best!.move.notation, 'h10');
    c.humanMove('k3');
    await _settle(20);
    final mark = c.marks[8]!;
    expect(mark.grade, DecisionGrade.blunder);
    expect(mark.score, 0);
    expect(mark.best, 'h10');
    expect(c.isOver, isTrue, reason: 'White made five');
    expect(c.winners, [1]);
    c.dispose();
  });

  test('a move the coach left out is graded once the coach has looked at it', () async {
    final c = _controller(opening: ['h8', 'h9']);
    await c.newGame();
    await _settle();
    expect(c.coach!.rates('a1'), isFalse);
    c.humanMove('a1');
    await _settle(20);
    expect(c.marks[2], isNotNull);
    expect(c.marks[2]!.grade.index, greaterThan(DecisionGrade.good.index), reason: 'far from everything');
    c.dispose();
  });

  test('Free Play gives no grades and starts no coach jobs', () async {
    final c = _controller(options: const GomokuOptions(level: KitLevel.easy, training: false));
    await c.newGame();
    for (var i = 0; i < 3; i++) {
      await _settle();
      expect(c.coachJobs, isEmpty);
      c.humanMove(_easyMove(c, i));
    }
    await _settle();
    expect(c.marks.whereType<Object>(), isEmpty);
    expect(c.coach, isNull);
    c.dispose();
  });

  test("New game cancels the coach's and the bot's jobs and starts over with the same choices", () async {
    // Jobs that wait to be answered, so they are still running at New game.
    final backend = ManualBackend(kitJobs);
    final c = GomokuController(
      options: const GomokuOptions(rules: GomokuRules.renju, level: KitLevel.easy),
      jobs: Jobs.using(backend),
      lastGames: LastGames(),
      speed: () => PlaybackSpeed.instant,
    );
    await c.newGame();
    await _settle();
    final show = backend.on(JobLane.coach)!;
    expect(show.name, 'gomoku.coach', reason: 'the coach looks at the first position');
    final firstSeed = c.record.seed;
    await c.newGame();
    await _settle();
    expect(show.token.isCancelled, isTrue);
    expect(c.coachJobs, ['show:0'], reason: "only the new game's job is left");
    expect(c.record.moves, isEmpty);
    expect(c.record.rules, GomokuRules.renju.toJson());
    expect(c.record.seed, isNot(firstSeed));
    c.dispose();

    final asWhite = GomokuController(
      options: const GomokuOptions(color: GomokuColorChoice.white, level: KitLevel.easy),
      jobs: Jobs.using(backend),
      lastGames: LastGames(),
      speed: () => PlaybackSpeed.instant,
    );
    await asWhite.newGame();
    await _settle();
    final bot = backend.on(JobLane.bot)!;
    expect(bot.name, 'gomoku.bot');
    await asWhite.newGame();
    expect(bot.token.isCancelled, isTrue);
    asWhite.dispose();
  });

  test('the record is saved at the start and after every move', () async {
    final saves = _Saves();
    final c = _controller(
      lastGames: saves,
      options: const GomokuOptions(level: KitLevel.easy, training: false),
    );
    await c.newGame();
    expect(saves.saved.last.moves, isEmpty);
    for (var i = 0; i < 3; i++) {
      await _settle();
      c.humanMove(_easyMove(c, i));
      expect(saves.saved.last.moves, c.record.moves, reason: 'saved right after the move');
      await _settle();
      expect(saves.saved.last.moves, hasLength(c.record.moves.length), reason: "and after the bot's");
    }
    c.dispose();
    final loaded = await saves.load(GameKeys.gomoku, version: gomokuRecordVersion, validate: GomokuRecord.validate);
    expect(loaded!.moves, c.record.moves);
  });

  test('toggles survive into the next game, and from the last game into a new screen', () async {
    final c = _controller();
    await c.newGame();
    c.coachVisible = false;
    await c.newGame();
    expect(c.coachVisible, isFalse);
    c.dispose();

    final next = _controller(toggles: {'coach': false});
    await next.newGame();
    expect(next.coachVisible, isFalse);
    expect(next.record.extra['mode'], 'training', reason: 'the setup\'s choices are kept too');
    next.dispose();
  });

  test('an illegal move changes nothing', () async {
    final c = _controller(opening: ['h8', 'h9']);
    await c.newGame();
    await _settle();
    expect(() => c.humanMove('h8'), throwsArgumentError);
    expect(c.record.moves, ['h8', 'h9']);
    expect(c.game.moves, hasLength(2));
    c.dispose();
  });

  test('the bots\' fallback plays a legal move fast', () async {
    final c = _controller(opening: ['h8']);
    await c.newGame();
    final move = GomokuMove.parse(c.fallbackBotMove(1));
    expect(c.game.isLegal(move), isTrue);
    c.dispose();
  });
}
