/// Gomoku's background jobs: the coach (`gomoku.coach`) and the bots
/// (`gomoku.bot`), with a room's two (gomoku_online_jobs.dart), registered
/// in lib/src/kit/jobs/job_registry.dart. There
/// is no guide job: the Threats guide's figures are fixed (a test checks
/// each one with the engine).
///
/// Both jobs take the game record cut at the position (GameRecord.jobJson)
/// and a seat, replay it with the engine's own codec, and give the engine
/// only that seat's view (Gomoku hides nothing, but the rule is the same
/// for every game).
///
/// Work budgets: the coach's default budget everywhere (it stays well under
/// its cap natively and in the browser, see CoachBudget), the deep one for
/// Think longer, and the quick one in tests. The engine's time cap is what
/// is left of the job's; with no cap the engine gets a day, explicitly, so
/// the same input always gives the same answer.
library;

import '../../../kit/game_keys.dart';
import '../../../kit/game_record.dart';
import '../../../kit/jobs/jobs_core.dart';
import '../../../kit/seats.dart';
import '../gomoku.dart';
import 'gomoku_analysis.dart';
import 'gomoku_online_jobs.dart';
import 'gomoku_record.dart';

/// Gomoku's jobs, in the registry: the solo game's, and a room's (its bots
/// and a spectator's coach, see gomoku_online_jobs.dart).
final List<GameJob<Object?, Object?>> gomokuJobs = [const GomokuCoachJob(), const GomokuBotJob(), ...gomokuOnlineJobs];

/// Time kept back from the job's cap for replaying, encoding and the reply.
const _capMargin = Duration(milliseconds: 40);

/// "No limit" for the engine, when the job has no cap: explicit, never the
/// engine's own default (900 ms for the coach), so answers repeat exactly.
const gomokuNoLimit = Duration(days: 1);

/// The engine's time cap for a job: what is left of the job's cap (less a
/// margin), or [gomokuNoLimit].
Duration gomokuTimeFor(JobContext context) {
  final left = context.remaining;
  if (left == null) return gomokuNoLimit;
  final time = left - _capMargin;
  return time < const Duration(milliseconds: 10) ? const Duration(milliseconds: 10) : time;
}

/// How much the coach looks at.
enum GomokuDepth {
  /// The platform's usual budget (the quick one in tests).
  normal,

  /// The quick budget anywhere (small examples).
  quick,

  /// Think longer.
  deep,
}

/// The coach's budget for [depth] on [context]'s platform, with its time.
CoachBudget gomokuCoachBudget(JobContext context, GomokuDepth depth) {
  final base = switch (depth) {
    GomokuDepth.deep => CoachBudget.deep,
    GomokuDepth.quick => CoachBudget.quick,
    GomokuDepth.normal => context.platform == JobPlatform.test ? CoachBudget.quick : const CoachBudget(),
  };
  return base.withTime(gomokuTimeFor(context));
}

/// The coach's input: the game up to the position, the seat to move, and
/// (to grade a move the first answer left out) a move to include.
class GomokuCoachInput {
  const GomokuCoachInput({required this.record, required this.seat, this.include, this.depth = GomokuDepth.normal});

  /// GameRecord.jobJson of the game up to the position.
  final Map<String, Object?> record;
  final int seat;

  /// A move that must be analysed too (Renju notation).
  final String? include;
  final GomokuDepth depth;

  Map<String, Object?> toJson() => {
    'record': record,
    'seat': seat,
    'include': ?include,
    if (depth != GomokuDepth.normal) 'depth': depth.name,
  };

  factory GomokuCoachInput.fromJson(Object? json) {
    final map = json! as Map<String, Object?>;
    final depth = map['depth'] as String?;
    return GomokuCoachInput(
      record: (map['record']! as Map).cast<String, Object?>(),
      seat: map['seat']! as int,
      include: map['include'] as String?,
      depth: depth == null ? GomokuDepth.normal : GomokuDepth.values.byName(depth),
    );
  }
}

/// `gomoku.coach`: the analysed moves for the side to move, best first,
/// with proofs, reasons and lines.
class GomokuCoachJob extends GameJob<GomokuCoachInput, GomokuAnalysis> {
  const GomokuCoachJob();

  @override
  String get name => '${GameKeys.gomoku}.coach';

  @override
  Object? encodeInput(GomokuCoachInput input) => input.toJson();
  @override
  GomokuCoachInput decodeInput(Object? json) => GomokuCoachInput.fromJson(json);
  @override
  Object? encodeOutput(GomokuAnalysis output) => encodeGomokuAnalysis(output);
  @override
  GomokuAnalysis decodeOutput(Object? json) => decodeGomokuAnalysis(json);

  @override
  GomokuAnalysis run(GomokuCoachInput input, JobContext context) {
    final game = GomokuRecord.replayJson(input.record);
    final include = input.include;
    return GomokuCoach(budget: gomokuCoachBudget(context, input.depth)).analyze(
      game.viewFor(GomokuRecord.colorOf(input.seat)),
      include: include == null ? null : GomokuMove.parse(include),
    );
  }

  @override
  List<GomokuCoachInput> examples() => [
    for (final (rules, moves) in _examplePositions)
      GomokuCoachInput(record: _record(rules, moves), seat: _seatToMove(moves), depth: GomokuDepth.quick),
    // Grading a move the coach would leave out: a quiet one, with an open
    // four ready (it still wins).
    GomokuCoachInput(
      record: _record(GomokuRules.freestyle, 'h8 a1 i8 a2 j8 a3 k8 b1'),
      seat: 0,
      include: 'a15',
      depth: GomokuDepth.quick,
    ),
  ];

  @override
  List<GomokuCoachInput> checkInputs() => [
    for (final (i, (rules, moves)) in _checkPositions().indexed)
      GomokuCoachInput(
        record: _record(rules, moves),
        seat: _seatToMove(moves),
        depth: i.isEven ? GomokuDepth.normal : GomokuDepth.quick,
        include: i % 5 == 3 ? _farCorner(rules) : null,
      ),
  ];
}

/// A bot's input: the game up to the position, the bot's seat, its level
/// and its seed.
class GomokuBotInput {
  const GomokuBotInput({required this.record, required this.seat, required this.level, required this.seed});

  /// GameRecord.jobJson of the game so far.
  final Map<String, Object?> record;
  final int seat;
  final KitLevel level;
  final int seed;

  Map<String, Object?> toJson() => {'record': record, 'seat': seat, 'level': level.name, 'seed': seed};

  factory GomokuBotInput.fromJson(Object? json) {
    final map = json! as Map<String, Object?>;
    return GomokuBotInput(
      record: (map['record']! as Map).cast<String, Object?>(),
      seat: map['seat']! as int,
      level: KitLevel.values.byName(map['level']! as String),
      seed: map['seed']! as int,
    );
  }
}

/// A bot's move, and how it chose it ("five", "block", "vcf", "search"...).
class GomokuBotOutput {
  const GomokuBotOutput(this.move, {this.how = ''});

  /// Renju notation, or "pass".
  final String move;
  final String how;

  Map<String, Object?> toJson() => {'move': move, if (how.isNotEmpty) 'how': how};

  factory GomokuBotOutput.fromJson(Object? json) {
    final map = json! as Map<String, Object?>;
    return GomokuBotOutput(map['move']! as String, how: map['how'] as String? ?? '');
  }
}

/// The engine's level for the kit's.
BotLevel gomokuBotLevel(KitLevel level) => switch (level) {
  KitLevel.easy => BotLevel.easy,
  KitLevel.medium => BotLevel.medium,
  KitLevel.hard => BotLevel.hard,
};

/// `gomoku.bot`: the bot's move.
class GomokuBotJob extends GameJob<GomokuBotInput, GomokuBotOutput> {
  const GomokuBotJob();

  @override
  String get name => '${GameKeys.gomoku}.bot';

  @override
  Object? encodeInput(GomokuBotInput input) => input.toJson();
  @override
  GomokuBotInput decodeInput(Object? json) => GomokuBotInput.fromJson(json);
  @override
  Object? encodeOutput(GomokuBotOutput output) => output.toJson();
  @override
  GomokuBotOutput decodeOutput(Object? json) => GomokuBotOutput.fromJson(json);

  @override
  GomokuBotOutput run(GomokuBotInput input, JobContext context) {
    final game = GomokuRecord.replayJson(input.record);
    final bot = GomokuBot(gomokuBotLevel(input.level), seed: input.seed, maxTime: gomokuTimeFor(context));
    final move = bot.chooseMove(game.viewFor(GomokuRecord.colorOf(input.seat)));
    return GomokuBotOutput(move.notation, how: bot.lastStats?.how ?? '');
  }

  @override
  List<GomokuBotInput> examples() => [
    for (final (rules, moves) in _examplePositions)
      GomokuBotInput(record: _record(rules, moves), seat: _seatToMove(moves), level: KitLevel.easy, seed: 3),
  ];

  @override
  List<GomokuBotInput> checkInputs() => [
    for (final (i, (rules, moves)) in _checkPositions().indexed)
      GomokuBotInput(
        record: _record(rules, moves),
        seat: _seatToMove(moves),
        level: KitLevel.values[i % 3],
        seed: 11 + i,
      ),
  ];
}

// ---- positions for the examples and the cross-platform check ----

Map<String, Object?> _record(GomokuRules rules, String moves) => GameRecord(
  game: GameKeys.gomoku,
  version: gomokuRecordVersion,
  seed: 1,
  rules: rules.toJson(),
  seats: const [
    SeatSpec(human: true, name: 'Player'),
    SeatSpec(human: false, level: KitLevel.medium, name: 'Ana'),
  ],
  moves: [
    for (final m in moves.split(' '))
      if (m.isNotEmpty) m,
  ],
).jobJson();

int _seatToMove(String moves) => moves.split(' ').where((m) => m.isNotEmpty).length.isEven ? 0 : 1;

String _farCorner(GomokuRules rules) => GomokuMove(rules.size - 1, 0).notation;

/// Small, quick positions (each well under 50 ms from a cold start: the
/// moves there are forced, so the coach and the bots settle them at once).
const _examplePositions = [
  // White's four d10-g10: Black must block at h10.
  (GomokuRules.freestyle, 'c10 d10 h3 e10 j3 f10 l3 g10'),
  // Renju, Black to move: i8 would be a double three, forbidden.
  (GomokuRules.renju, 'h8 a1 j8 a2 i9 a3 i10 a4'),
];

/// Games Easy and Medium played under each rule (every few moves is a
/// position to check).
const _sampleGames = [
  (GomokuRules.freestyle, 'h8 g7 g8 f8 i5 e9 h6 d10 c11 e10 f10 e11 e12 c9 f12 b8 a7 b10 e7 b9 b7 d9 f9 a9'),
  (GomokuRules.freestyle, 'h8 f6 i7 j6 j8 k8 h6 k9 k7 i9 h7 h5 j7 l7 g7'),
  (GomokuRules.standard, 'h8 f8 i8 f9 k8 j8 f7 f10 i7 i9 h7 f12 f11 h10 g11 g7 g9 g10 k5 j6 i10 d10 e10 e9 h6 c11'),
  (GomokuRules.standard, 'h8 f8 g9 f10 f9 e9 g7 d8 g8 g11 c7 h12'),
  (GomokuRules.renju, 'h8 f6 i7 j6 j8 k8 h6 k9 h5 h4 g5 f4 h7 h9 g7 j7 g6 k7 g8 g9 g4'),
  (GomokuRules.renju, 'h8 f8 g9 f10 f9 e9 g7 d8 g8 g11 h12 c7'),
  (GomokuRules.freestyle19, 'j10 h8 k9 l8 l10 i10 j8 m11 j7 j6 i9 h9 k7 h6 h10 g11 l6'),
  (GomokuRules.standard19, 'j10 h10 i11 h12 h11 g11 i9 f10 i10 i13 j14 e9'),
];

/// About 30 positions: every game cut at 3, 8 and 2 moves before its end
/// (none of them over).
List<(GomokuRules, String)> _checkPositions() => [
  for (final (rules, text) in _sampleGames)
    for (final cut in {3, 8, text.split(' ').length - 2, text.split(' ').length - 5})
      (rules, text.split(' ').take(cut).join(' ')),
];
