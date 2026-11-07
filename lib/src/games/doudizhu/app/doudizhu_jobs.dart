import 'dart:math';

import '../../../kit/game_record.dart';
import '../../../kit/jobs/jobs_core.dart';
import '../../../kit/seats.dart';
import '../doudizhu.dart';
import 'doudizhu_analysis.dart';
import 'doudizhu_online_jobs.dart';
import 'doudizhu_range.dart';
import 'doudizhu_record.dart';

/// Fight the Landlord's background jobs (coach, bot and an opponent's
/// range, see doudizhu_range.dart; and in a room, the host's bots and a
/// spectator's coach, see doudizhu_online_jobs.dart), registered in
/// lib/src/kit/jobs/job_registry.dart. There is no guide job: the
/// Combinations guide is fixed text and cards.
final List<GameJob<Object?, Object?>> doudizhuJobs = [
  const DdzCoachJob(),
  const DdzBotJob(),
  const DdzRangeJob(),
  const DdzOnlineBotJob(),
  const DdzOnlineCoachJob(),
];

/// The coach's work for one answer on [platform], stopping by [remaining]
/// (null: no cap, and then explicitly no time limit, so the answer depends
/// only on the input). JavaScript and phones get half the deals of a PC
/// (the engine is about 2.3 times slower in JavaScript); Think longer
/// ([deep]) three times as many; tests a few, so they stay fast.
DdzBudget ddzCoachBudget(JobPlatform platform, Duration? remaining, {bool deep = false}) {
  final test = platform == JobPlatform.test;
  final base = switch (platform) {
    JobPlatform.desktop || JobPlatform.webWasm => 2400,
    JobPlatform.phone || JobPlatform.webJs => 1200,
    JobPlatform.test => 160,
  };
  return DdzBudget(
    rollouts: deep ? base * 3 : base,
    maxTime: _deadline(remaining),
    maxCandidates: test ? 10 : 20,
    exactCards: test ? 10 : 16,
    exactNodeBudget: test ? 40000 : 300000,
    poolSize: test ? 60 : 300,
  );
}

/// A bot's work at [level] on [platform] (Easy needs none): the engine's
/// Medium and Hard budgets, halved in JavaScript and on phones, small in
/// tests.
DdzBudget ddzBotBudget(DdzLevel level, JobPlatform platform, Duration? remaining) {
  final engine = level == DdzLevel.hard ? DdzBudget.hard : DdzBudget.medium;
  final rollouts = switch (platform) {
    JobPlatform.desktop || JobPlatform.webWasm => engine.rollouts,
    JobPlatform.phone || JobPlatform.webJs => engine.rollouts ~/ 2,
    JobPlatform.test => level == DdzLevel.hard ? 120 : 60,
  };
  final test = platform == JobPlatform.test;
  return DdzBudget(
    rollouts: rollouts,
    maxTime: _deadline(remaining),
    maxCandidates: test ? 6 : engine.maxCandidates,
    exactCards: test ? 8 : engine.exactCards,
    exactNodeBudget: test ? 20000 : engine.exactNodeBudget,
    poolSize: test ? 40 : engine.poolSize,
  );
}

/// Most of what is left of the cap: the rest pays for replaying the record
/// and sending the answer back. Null (no cap) stays null: no time limit.
Duration? _deadline(Duration? remaining) => remaining == null ? null : remaining * 0.8;

/// The engine's level for a kit level.
DdzLevel ddzLevel(KitLevel level) => switch (level) {
      KitLevel.easy => DdzLevel.easy,
      KitLevel.medium => DdzLevel.medium,
      KitLevel.hard => DdzLevel.hard,
    };

/// The position a job looks at: [record] replayed, the seat checked.
DdzView ddzJobView(Map<String, Object?> record, int seat) {
  final game = ddzReplay(ddzRecordFromJson(record) ?? (throw const FormatException('Not a doudizhu record')));
  if ((game.phase != DdzPhase.bidding && game.phase != DdzPhase.playing) || game.toAct != seat) {
    throw StateError('Not seat $seat\'s turn');
  }
  return game.viewFor(seat);
}

/// What the coach job gets: the deal up to the decision (GameRecord.jobJson),
/// the seat to advise, a move that must be rated ([include], a record move),
/// Think longer ([deep]) and the seed of its deals.
class DdzCoachInput {
  const DdzCoachInput({required this.record, required this.seat, this.include, this.deep = false, required this.seed});

  final Map<String, Object?> record;
  final int seat;
  final String? include;
  final bool deep;
  final int seed;
}

/// The coach ("GTO"): every move of the seat's decision rated by the
/// engine's coach, which sees only the seat's view. In the auction, every
/// bid against passing (estimateBidding's play-outs).
class DdzCoachJob extends GameJob<DdzCoachInput, DdzAdvice> {
  const DdzCoachJob();

  @override
  String get name => 'doudizhu.coach';

  @override
  Object? encodeInput(DdzCoachInput input) => {
        'record': input.record,
        'seat': input.seat,
        'include': ?input.include,
        if (input.deep) 'deep': true,
        'seed': input.seed,
      };

  @override
  DdzCoachInput decodeInput(Object? json) {
    final map = json! as Map<String, Object?>;
    return DdzCoachInput(
      record: map['record']! as Map<String, Object?>,
      seat: (map['seat']! as num).toInt(),
      include: map['include'] as String?,
      deep: map['deep'] == true,
      seed: (map['seed']! as num).toInt(),
    );
  }

  @override
  Object? encodeOutput(DdzAdvice output) => output.toJson();

  @override
  DdzAdvice decodeOutput(Object? json) => DdzAdvice.fromJson(json);

  @override
  DdzAdvice run(DdzCoachInput input, JobContext context) {
    final budget = ddzCoachBudget(context.platform, context.remaining, deep: input.deep);
    final view = ddzJobView(input.record, input.seat);
    final include = input.include == null ? null : ddzParseMove(input.include!, view.rules).move;
    final analysis = DdzCoach(budget: budget).analyze(view, random: Random(input.seed), include: include);
    return DdzAdvice.of(analysis, view);
  }

  @override
  Object? normalize(Object? outputJson) => _rounded(outputJson);

  @override
  List<DdzCoachInput> examples() {
    // Late in a deal, where an answer is quick even with the full budget.
    final game = ddzSampleGame(1);
    final late = _lateIndex(game, 4);
    final position = game.upTo(late);
    return [
      DdzCoachInput(record: position.jobJson(), seat: _toAct(position), seed: 7),
      DdzCoachInput(
        record: position.jobJson(),
        seat: _toAct(position),
        include: game.moves[late],
        seed: 7,
      ),
    ];
  }

  @override
  List<DdzCoachInput> checkInputs() => [
        for (final seed in const [1, 2, 3, 4, 5])
          for (final (i, (position, played)) in _checkPositions(ddzSampleGame(seed)).indexed)
            DdzCoachInput(
              record: position.jobJson(),
              seat: _toAct(position),
              // Every other position also asks for the move played there.
              include: i.isOdd ? played : null,
              seed: seed * 31 + i,
            ),
      ];
}

/// What a bot job gets: the deal so far, the bot's seat and level, and the
/// seed of its random choices.
class DdzBotInput {
  const DdzBotInput({required this.record, required this.seat, required this.level, required this.seed});

  final Map<String, Object?> record;
  final int seat;
  final KitLevel level;
  final int seed;
}

/// A bot's move, as the record's move text (lowest suits for a play).
class DdzBotJob extends GameJob<DdzBotInput, String> {
  const DdzBotJob();

  @override
  String get name => 'doudizhu.bot';

  @override
  Object? encodeInput(DdzBotInput input) =>
      {'record': input.record, 'seat': input.seat, 'level': input.level.name, 'seed': input.seed};

  @override
  DdzBotInput decodeInput(Object? json) {
    final map = json! as Map<String, Object?>;
    return DdzBotInput(
      record: map['record']! as Map<String, Object?>,
      seat: (map['seat']! as num).toInt(),
      level: KitLevel.values.byName(map['level']! as String),
      seed: (map['seed']! as num).toInt(),
    );
  }

  @override
  Object? encodeOutput(String output) => output;

  @override
  String decodeOutput(Object? json) => json! as String;

  @override
  String run(DdzBotInput input, JobContext context) {
    final level = ddzLevel(input.level);
    final view = ddzJobView(input.record, input.seat);
    final bot = DdzBot(level, random: Random(input.seed), budget: ddzBotBudget(level, context.platform, context.remaining));
    final move = bot.chooseMove(view);
    return ddzMoveText(input.seat, move, move is DdzPlay ? ddzCardsFor(view.hand, move.play) : const []);
  }

  @override
  List<DdzBotInput> examples() {
    final game = ddzSampleGame(1);
    final late = game.upTo(_lateIndex(game, 10));
    final mid = game.upTo(game.moves.length ~/ 2);
    return [
      DdzBotInput(record: mid.jobJson(), seat: _toAct(mid), level: KitLevel.easy, seed: 3),
      DdzBotInput(record: late.jobJson(), seat: _toAct(late), level: KitLevel.hard, seed: 3),
    ];
  }

  @override
  List<DdzBotInput> checkInputs() => [
        for (final seed in const [1, 2, 3])
          for (final (i, (position, _)) in _checkPositions(ddzSampleGame(seed)).indexed)
            DdzBotInput(
              record: position.jobJson(),
              seat: _toAct(position),
              level: KitLevel.values[i % 3],
              seed: seed * 17 + i,
            ),
      ];
}

/// A whole deal played by three Easy bots, from game seed [seed] (the first
/// seed after it that isn't thrown in): the positions the examples and the
/// cross-platform check use. Easy bots are rules of thumb, so this costs
/// microseconds.
GameRecord ddzSampleGame(int seed, {DdzRules rules = DdzRules.standard}) {
  for (var s = seed;; s += 1000) {
    var record = ddzNewRecord(
      seed: s,
      rules: rules,
      seats: const [
        SeatSpec(human: true, name: 'Player'),
        SeatSpec(human: false, level: KitLevel.easy, name: 'Ana'),
        SeatSpec(human: false, level: KitLevel.easy, name: 'Ben'),
      ],
    );
    final game = ddzReplay(record);
    final bot = DdzBot(DdzLevel.easy, random: Random(s));
    while (game.phase == DdzPhase.bidding || game.phase == DdzPhase.playing) {
      final text = ddzMoveTextFor(game, bot.chooseMove(game.viewFor(game.toAct)));
      ddzApply(game, text);
      record = record.withMove(text);
    }
    if (game.phase == DdzPhase.finished) return record;
  }
}

int _toAct(GameRecord position) => ddzReplay(position).toAct;

/// The first move index with at most [cards] cards left in all hands.
int _lateIndex(GameRecord game, int cards) {
  final replay = ddzReplay(game, upTo: 0);
  for (var i = 0; i < game.moves.length; i++) {
    if (replay.phase == DdzPhase.playing && replay.hands.fold<int>(0, (n, h) => n + h.length) <= cards) return i;
    ddzApply(replay, game.moves[i]);
  }
  return game.moves.length - 1;
}

/// Positions of a deal, each with the move played there: the opening bid,
/// the landlord's first lead, some in the middle and one near the end.
List<(GameRecord, String)> _checkPositions(GameRecord game) => [
      for (final at in _checkPoints(game)) (game.upTo(at), game.moves[at]),
    ];

List<int> _checkPoints(GameRecord game) {
  final replay = ddzReplay(game, upTo: 0);
  var firstLead = 0;
  for (var i = 0; i < game.moves.length; i++) {
    if (replay.phase == DdzPhase.playing) {
      firstLead = i;
      break;
    }
    ddzApply(replay, game.moves[i]);
  }
  final n = game.moves.length;
  final spread = [firstLead + (n - firstLead) ~/ 4, firstLead + (n - firstLead) ~/ 2, n - 4];
  return {0, firstLead, ...spread, _lateIndex(game, 10)}.where((i) => i >= 0 && i < n).toList()..sort();
}

/// Numbers rounded to 9 places, so a JavaScript and a native run compare
/// equal (they print doubles differently: "1" and "1.0").
Object? _rounded(Object? json) => switch (json) {
      final double d => (d * 1e9).round() / 1e9,
      final Map<String, Object?> m => {for (final e in m.entries) e.key: _rounded(e.value)},
      final List<Object?> l => [for (final e in l) _rounded(e)],
      _ => json,
    };
