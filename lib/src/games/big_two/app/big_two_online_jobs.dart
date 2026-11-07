/// Big Two's jobs in a room (registered in bigTwoJobs):
/// - `big_two.onlineBot`: a bot's move on the host's device, from that
///   bot's own view (the room's seat view, big_two_view_codec.dart);
/// - `big_two.onlineCoach`: a spectator's coach for the seat on turn, from
///   that seat's view rebuilt from the spectators' view.
///
/// Both read the view the room sent, never a record: in a room nobody
/// holds the deal. The engine gets that seat's view only, so neither can
/// peek. Seeds come in the input; the budgets are the solo jobs' (see
/// bigTwoBudget).
library;

import 'dart:math';

import '../../../kit/game_keys.dart';
import '../../../kit/jobs/jobs_core.dart';
import '../../../kit/seats.dart';
import '../big_two.dart';
import '../online/big_two_view_codec.dart';
import 'big_two_analysis.dart';
import 'big_two_jobs.dart' show bigTwoBotLevel, bigTwoBudget;

/// A room job's input: the seat's view (the room's JSON), a seed, and the
/// bot's level (the bot only).
class BigTwoOnlineInput {
  const BigTwoOnlineInput({required this.view, required this.seed, this.level, this.playouts});

  /// The seat's view, as bigTwoSeatView writes it.
  final Map<String, Object?> view;
  final int seed;

  /// The bot's level; null for the coach.
  final KitLevel? level;

  /// Play-outs instead of the platform's number (examples, checks).
  final int? playouts;

  Map<String, Object?> toJson() => {'view': view, 'seed': seed, 'level': ?level?.name, 'playouts': ?playouts};

  factory BigTwoOnlineInput.fromJson(Object? json) {
    final map = (json! as Map).cast<String, Object?>();
    final level = map['level'] as String?;
    return BigTwoOnlineInput(
      view: (map['view']! as Map).cast<String, Object?>(),
      seed: map['seed']! as int,
      level: level == null ? null : KitLevel.values.byName(level),
      playouts: map['playouts'] as int?,
    );
  }
}

/// Time kept back from the job's cap for reading the view and replying.
const _capMargin = Duration(milliseconds: 40);

/// `big_two.onlineBot`: the move of a bot at the input's level, seeing
/// only its own view. Its output is the move's text.
class BigTwoOnlineBotJob extends GameJob<BigTwoOnlineInput, String> {
  const BigTwoOnlineBotJob();

  @override
  String get name => '${GameKeys.bigTwo}.onlineBot';

  @override
  Object? encodeInput(BigTwoOnlineInput input) => input.toJson();
  @override
  BigTwoOnlineInput decodeInput(Object? json) => BigTwoOnlineInput.fromJson(json);
  @override
  Object? encodeOutput(String output) => {'mv': output};
  @override
  String decodeOutput(Object? json) => (json! as Map)['mv']! as String;

  @override
  String run(BigTwoOnlineInput input, JobContext context) {
    final view = bigTwoEngineView(input.view);
    final level = input.level ?? KitLevel.medium;
    final left = context.remaining;
    final budget = switch (level) {
      KitLevel.hard => bigTwoBudget(context, playouts: input.playouts),
      KitLevel.medium => CoachBudget.quick.copyWith(
        maxMillis: () => left == null ? null : max(0, (left - _capMargin).inMilliseconds),
      ),
      KitLevel.easy => null,
    };
    final play = BigTwoBot(bigTwoBotLevel(level), seed: input.seed, budget: budget).chooseMove(view);
    return bigTwoMove(view.seat, play);
  }

  @override
  List<BigTwoOnlineInput> examples() => [
    for (final (i, view) in _views(_exampleSpots).indexed)
      BigTwoOnlineInput(view: view, seed: 3 + i, level: KitLevel.values[i % 3], playouts: 200),
  ];

  @override
  List<BigTwoOnlineInput> checkInputs() => [
    for (final (i, view) in _views(_checkSpots).indexed)
      BigTwoOnlineInput(view: view, seed: 300 + i, level: KitLevel.values[i % 3], playouts: 300),
  ];
}

/// The coach's answer in a room: its report, and the scoring it was
/// worked out under (which sets how the panel grades the points).
class BigTwoOnlineAdvice {
  const BigTwoOnlineAdvice(this.report, this.scoring);

  final BigTwoReport report;
  final BigTwoScoring scoring;

  Map<String, Object?> toJson() => {'report': report.toJson(), 'scoring': scoring.name};

  factory BigTwoOnlineAdvice.fromJson(Object? json) {
    final map = (json! as Map).cast<String, Object?>();
    return BigTwoOnlineAdvice(
      BigTwoReport.fromJson(map['report']),
      BigTwoScoring.values.byName(map['scoring']! as String),
    );
  }
}

/// `big_two.onlineCoach`: every legal move of the seat on turn, rated, the
/// pick first (as `big_two.coach`, from a view instead of a record).
class BigTwoOnlineCoachJob extends GameJob<BigTwoOnlineInput, BigTwoOnlineAdvice> {
  const BigTwoOnlineCoachJob();

  @override
  String get name => '${GameKeys.bigTwo}.onlineCoach';

  @override
  Object? encodeInput(BigTwoOnlineInput input) => input.toJson();
  @override
  BigTwoOnlineInput decodeInput(Object? json) => BigTwoOnlineInput.fromJson(json);
  @override
  Object? encodeOutput(BigTwoOnlineAdvice output) => output.toJson();
  @override
  BigTwoOnlineAdvice decodeOutput(Object? json) => BigTwoOnlineAdvice.fromJson(json);

  @override
  BigTwoOnlineAdvice run(BigTwoOnlineInput input, JobContext context) {
    final view = bigTwoEngineView(input.view);
    // A third of the play-outs compare every move on shared deals, so the
    // points the list shows are fair between moves (as the solo coach).
    final budget = bigTwoBudget(
      context,
      playouts: input.playouts,
    ).copyWith(compareShare: CoachBudget.coach.compareShare);
    final analysis = BigTwoCoach(budget: budget).analyze(view, seed: input.seed);
    return BigTwoOnlineAdvice(BigTwoReport.fromAnalysis(analysis, view.seat), view.rules.scoring);
  }

  @override
  List<BigTwoOnlineInput> examples() => [
    for (final (i, view) in _views(_exampleSpots).indexed) BigTwoOnlineInput(view: view, seed: 7 + i, playouts: 200),
  ];

  @override
  List<BigTwoOnlineInput> checkInputs() => [
    for (final (i, view) in _views(_checkSpots).indexed) BigTwoOnlineInput(view: view, seed: 100 + i, playouts: 300),
  ];
}

/// A position to test with: rules, the deal's seed, and how many moves
/// Easy bots have played.
typedef _Spot = (BigTwoRules rules, int seed, int moves);

final _exampleSpots = <_Spot>[
  (BigTwoRules.standard(), 21, 0),
  (BigTwoRules.standard(players: 2), 22, 10),
  (BigTwoRules.hongKong(players: 3), 23, 12),
];

/// About 30 positions over every preset and player count, from the deal to
/// late in it.
final _checkSpots = <_Spot>[
  for (var i = 0; i < 30; i++)
    (
      BigTwoRules.preset(BigTwoPreset.values[i % 4], players: const [4, 3, 2][i % 3]),
      2000 + i,
      const [0, 6, 14, 24, 36][i % 5],
    ),
];

/// The view of the seat on turn in each of [spots], as a room sends it:
/// each deal played on by Easy bots (seeded), stopping one move before it
/// would end.
List<Map<String, Object?>> _views(List<_Spot> spots) => [
  for (final (rules, seed, moves) in spots)
    () {
      final state = BigTwoState.deal(rules, seed: seed);
      for (var i = 0; i < moves && !state.isOver; i++) {
        final seat = state.toMove;
        final play = BigTwoBot(BotLevel.easy, seed: mixSeed(seed, i, seat)).chooseMove(state.viewFor(seat));
        if ((state.copy()..applyTrusted(play)).isOver) break;
        state.apply(play);
      }
      return bigTwoSeatView(state, state.toMove, deal: 1, match: null);
    }(),
];
