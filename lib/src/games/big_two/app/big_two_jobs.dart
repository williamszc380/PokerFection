/// Big Two's background jobs: the coach (`big_two.coach`), the bots
/// (`big_two.bot`) and an opponent's range (`big_two.range`, in
/// big_two_range.dart), registered in lib/src/kit/jobs/job_registry.dart,
/// with the room's bot and spectators' coach (`big_two.onlineBot`,
/// `big_two.onlineCoach`, in big_two_online_jobs.dart).
///
/// All three take the game record cut at the position (GameRecord.jobJson) and
/// a seat, replay it, and give the engine only that seat's view, so they
/// can never peek. Seeds come in the input. There is no guide job: the
/// Hand ranks guide is drawn from the rules alone.
///
/// Work budgets by platform: 3000 play-outs on desktops and in WebAssembly,
/// 1500 on phones and in the JavaScript build (it is about twice as slow),
/// three times as many for Think longer, and the light budget in tests.
/// The coach spends a third of them comparing every move on the same
/// guessed deals (CoachBudget.compareShare); the Hard bot spends them all
/// on finding its move.
/// The engine's time cap comes from the job's; with no cap the engine gets
/// none either (null maxMillis), so the same input gives the same answer.
library;

import 'dart:math';

import '../../../kit/game_keys.dart';
import '../../../kit/game_record.dart';
import '../../../kit/jobs/jobs_core.dart';
import '../../../kit/seats.dart';
import '../big_two.dart';
import 'big_two_analysis.dart';
import 'big_two_online_jobs.dart';
import 'big_two_range.dart';
import 'big_two_record.dart';

/// Big Two's jobs, in the registry.
final List<GameJob<Object?, Object?>> bigTwoJobs = [
  const BigTwoCoachJob(),
  const BigTwoBotJob(),
  const BigTwoRangeJob(),
  const BigTwoOnlineBotJob(),
  const BigTwoOnlineCoachJob(),
];

/// Time kept back from the job's cap for replaying, encoding and the reply.
const _capMargin = Duration(milliseconds: 40);

/// The coach's (and the Hard bot's) budget on [context]'s platform:
/// [deep] for Think longer; [playouts] overrides the platform's number
/// (small examples, the cross-platform check).
CoachBudget bigTwoBudget(JobContext context, {bool deep = false, int? playouts}) {
  var budget = switch (context.platform) {
    JobPlatform.test => CoachBudget.quick,
    JobPlatform.webJs || JobPlatform.phone => CoachBudget.standard.copyWith(playouts: 1500),
    JobPlatform.desktop || JobPlatform.webWasm => CoachBudget.standard,
  };
  if (deep) budget = budget.copyWith(playouts: budget.playouts * 3);
  if (playouts != null) budget = budget.copyWith(playouts: playouts);
  return _capped(budget, context);
}

/// [budget] with the job's time cap, or explicitly none.
CoachBudget _capped(CoachBudget budget, JobContext context) {
  final left = context.remaining;
  return budget.copyWith(maxMillis: () => left == null ? null : max(0, (left - _capMargin).inMilliseconds));
}

/// What both jobs replay: the record up to the position, and whose view.
abstract class _PositionInput {
  const _PositionInput({required this.record, required this.seat, required this.seed});

  /// GameRecord.jobJson of the game up to the position.
  final Map<String, Object?> record;
  final int seat;
  final int seed;

  /// [seat]'s view of the position (what the engine is given).
  BigTwoView view() => BigTwoRecord.replayJson(record).viewFor(seat);
}

/// The coach's input.
class BigTwoCoachInput extends _PositionInput {
  const BigTwoCoachInput({
    required super.record,
    required super.seat,
    required super.seed,
    this.deep = false,
    this.playouts,
    this.include,
  });

  /// Think longer (three times the play-outs).
  final bool deep;

  /// Play-outs instead of the platform's number (examples, checks).
  final int? playouts;

  /// A move that must be rated. The coach rates every legal move anyway,
  /// so it is always there; kept so the kit's grading request reads the
  /// same for every game.
  final String? include;

  Map<String, Object?> toJson() => {
    'record': record,
    'seat': seat,
    'seed': seed,
    if (deep) 'deep': true,
    'playouts': ?playouts,
    'include': ?include,
  };

  factory BigTwoCoachInput.fromJson(Object? json) {
    final map = json! as Map<String, Object?>;
    return BigTwoCoachInput(
      record: (map['record']! as Map).cast<String, Object?>(),
      seat: map['seat']! as int,
      seed: map['seed']! as int,
      deep: map['deep'] as bool? ?? false,
      playouts: map['playouts'] as int?,
      include: map['include'] as String?,
    );
  }
}

/// `big_two.coach`: every legal move of the seat on turn, rated, the pick
/// first, with the hand plan.
class BigTwoCoachJob extends GameJob<BigTwoCoachInput, BigTwoReport> {
  const BigTwoCoachJob();

  @override
  String get name => '${GameKeys.bigTwo}.coach';

  @override
  Object? encodeInput(BigTwoCoachInput input) => input.toJson();
  @override
  BigTwoCoachInput decodeInput(Object? json) => BigTwoCoachInput.fromJson(json);
  @override
  Object? encodeOutput(BigTwoReport output) => output.toJson();
  @override
  BigTwoReport decodeOutput(Object? json) => BigTwoReport.fromJson(json);

  @override
  BigTwoReport run(BigTwoCoachInput input, JobContext context) {
    final view = input.view();
    // A third of the play-outs compare every move on shared deals, so the
    // points the panel shows and the grades use are fair between moves.
    final budget = bigTwoBudget(
      context,
      deep: input.deep,
      playouts: input.playouts,
    ).copyWith(compareShare: CoachBudget.coach.compareShare);
    return BigTwoReport.fromAnalysis(BigTwoCoach(budget: budget).analyze(view, seed: input.seed), input.seat);
  }

  @override
  List<BigTwoCoachInput> examples() => [
    for (final (record, seat) in _positions(_exampleSpots))
      BigTwoCoachInput(record: record.jobJson(), seat: seat, seed: 7, playouts: 200),
  ];

  @override
  List<BigTwoCoachInput> checkInputs() => [
    for (final (i, (record, seat)) in _positions(_checkSpots).indexed)
      BigTwoCoachInput(record: record.jobJson(), seat: seat, seed: 100 + i, playouts: 300, deep: i % 5 == 4),
  ];
}

/// A bot's input.
class BigTwoBotInput extends _PositionInput {
  const BigTwoBotInput({
    required super.record,
    required super.seat,
    required super.seed,
    required this.level,
    this.analysis = false,
    this.playouts,
  });

  final KitLevel level;

  /// Also send back the analysis the move came from (Medium and Hard), for
  /// an online host to show spectators without asking the coach again.
  final bool analysis;

  /// The Hard bot's play-outs instead of the platform's number.
  final int? playouts;

  Map<String, Object?> toJson() => {
    'record': record,
    'seat': seat,
    'seed': seed,
    'level': level.name,
    if (analysis) 'analysis': true,
    'playouts': ?playouts,
  };

  factory BigTwoBotInput.fromJson(Object? json) {
    final map = json! as Map<String, Object?>;
    return BigTwoBotInput(
      record: (map['record']! as Map).cast<String, Object?>(),
      seat: map['seat']! as int,
      seed: map['seed']! as int,
      level: KitLevel.values.byName(map['level']! as String),
      analysis: map['analysis'] as bool? ?? false,
      playouts: map['playouts'] as int?,
    );
  }
}

/// A bot's move, with the analysis behind it when one was asked for and made.
class BigTwoBotOutput {
  const BigTwoBotOutput(this.move, {this.analysis});

  /// The move, `"<seat>:<cards>"` or `"<seat>:pass"`.
  final String move;
  final BigTwoReport? analysis;

  Map<String, Object?> toJson() => {'move': move, 'analysis': ?analysis?.toJson()};

  factory BigTwoBotOutput.fromJson(Object? json) {
    final map = json! as Map<String, Object?>;
    final analysis = map['analysis'];
    return BigTwoBotOutput(map['move']! as String, analysis: analysis == null ? null : BigTwoReport.fromJson(analysis));
  }
}

/// The engine's level for the kit's.
BotLevel bigTwoBotLevel(KitLevel level) => switch (level) {
  KitLevel.easy => BotLevel.easy,
  KitLevel.medium => BotLevel.medium,
  KitLevel.hard => BotLevel.hard,
};

/// `big_two.bot`: the move of a bot at the input's level.
class BigTwoBotJob extends GameJob<BigTwoBotInput, BigTwoBotOutput> {
  const BigTwoBotJob();

  @override
  String get name => '${GameKeys.bigTwo}.bot';

  @override
  Object? encodeInput(BigTwoBotInput input) => input.toJson();
  @override
  BigTwoBotInput decodeInput(Object? json) => BigTwoBotInput.fromJson(json);
  @override
  Object? encodeOutput(BigTwoBotOutput output) => output.toJson();
  @override
  BigTwoBotOutput decodeOutput(Object? json) => BigTwoBotOutput.fromJson(json);

  @override
  BigTwoBotOutput run(BigTwoBotInput input, JobContext context) {
    final view = input.view();
    final budget = switch (input.level) {
      KitLevel.hard => bigTwoBudget(context, playouts: input.playouts),
      KitLevel.medium => _capped(CoachBudget.quick, context),
      KitLevel.easy => null,
    };
    final decision = BigTwoBot(bigTwoBotLevel(input.level), seed: input.seed, budget: budget).decide(view);
    final analysis = decision.analysis;
    return BigTwoBotOutput(
      bigTwoMoveText(input.seat, decision.play),
      analysis: input.analysis && analysis != null ? BigTwoReport.fromAnalysis(analysis, input.seat) : null,
    );
  }

  @override
  List<BigTwoBotInput> examples() => [
    for (final (i, (record, seat)) in _positions(_exampleSpots).indexed)
      BigTwoBotInput(
        record: record.jobJson(),
        seat: seat,
        seed: 3,
        level: KitLevel.values[i % 3],
        analysis: i.isEven,
        playouts: 200,
      ),
  ];

  @override
  List<BigTwoBotInput> checkInputs() => [
    for (final (i, (record, seat)) in _positions(_checkSpots).indexed)
      BigTwoBotInput(
        record: record.jobJson(),
        seat: seat,
        seed: 200 + i,
        level: KitLevel.values[i % 3],
        analysis: i % 3 == 2,
        playouts: 300,
      ),
  ];
}

/// A position to test with: rules, the deal's seed, and how many moves
/// Easy bots have played.
typedef _Spot = (BigTwoRules rules, int seed, int moves);

final _exampleSpots = <_Spot>[
  (BigTwoRules.standard(), 11, 0),
  (BigTwoRules.standard(), 12, 30),
  (BigTwoRules.hongKong(players: 3), 13, 12),
];

/// About 30 positions over every preset and player count, from the deal to
/// late in it.
final _checkSpots = <_Spot>[
  for (var i = 0; i < 30; i++)
    (
      BigTwoRules.preset(BigTwoPreset.values[i % 4], players: const [4, 3, 2][i % 3]),
      1000 + i,
      const [0, 6, 14, 24, 36][i % 5],
    ),
];

/// Records of [spots] with their seat to act: each deal played on by Easy
/// bots (seeded), stopping early if it ends.
List<(GameRecord, int)> _positions(List<_Spot> spots) => [
  for (final (rules, seed, moves) in spots) _position(rules, seed, moves),
];

(GameRecord, int) _position(BigTwoRules rules, int seed, int moves) {
  var record = BigTwoRecord.deal(
    rules: rules,
    seed: seed,
    seats: [
      const SeatSpec(human: true, name: 'Player'),
      for (var i = 1; i < rules.players; i++) SeatSpec(human: false, level: KitLevel.easy, name: kitBotNames[i - 1]),
    ],
  );
  final state = BigTwoRecord.replay(record);
  for (var i = 0; i < moves && !state.isOver; i++) {
    final seat = state.toMove;
    final play = BigTwoBot(BotLevel.easy, seed: mixSeed(seed, i, seat)).chooseMove(state.viewFor(seat));
    // Stop one move short of the end: a finished deal has nobody on turn.
    final next = state.copy()..applyTrusted(play);
    if (next.isOver) break;
    state.apply(play);
    record = record.withMove(bigTwoMoveText(seat, play));
  }
  return (record, state.toMove);
}
