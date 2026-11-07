/// Gomoku's jobs in a room: the bots the host's device plays
/// (`gomoku.onlineBot`) and a spectator's coach (`gomoku.onlineCoach`).
/// They take the room's view (see gomoku_view_codec.dart) rather than a
/// game record: the room sends the whole game, and the engine replays it
/// with its own codec, so the bot and the coach see exactly what the
/// table shows.
///
/// They run the solo game's engine the same way (the bot's level and the
/// coach's usual budget, see gomoku_jobs.dart), so a bot or the coach in a
/// room plays and advises as it does against the player.
library;

import '../../../kit/game_keys.dart';
import '../../../kit/jobs/jobs_core.dart';
import '../../../kit/seats.dart';
import '../gomoku.dart';
import '../online/gomoku_view_codec.dart';
import 'gomoku_analysis.dart';
import 'gomoku_jobs.dart';

/// The room's two jobs (in gomokuJobs, so the worker has them).
final List<GameJob<Object?, Object?>> gomokuOnlineJobs = [const GomokuOnlineBotJob(), const GomokuOnlineCoachJob()];

/// A bot's turn in a room: the bot's own seat view, its level, its seed.
class GomokuOnlineBotInput {
  const GomokuOnlineBotInput({required this.view, required this.level, required this.seed});

  /// The bot's seat view (with `you`).
  final Map<String, Object?> view;
  final KitLevel level;
  final int seed;

  Map<String, Object?> toJson() => {'view': view, 'level': level.name, 'seed': seed};

  factory GomokuOnlineBotInput.fromJson(Object? json) {
    final map = json! as Map<String, Object?>;
    return GomokuOnlineBotInput(
      view: (map['view']! as Map).cast<String, Object?>(),
      level: KitLevel.values.byName(map['level']! as String),
      seed: map['seed']! as int,
    );
  }
}

/// `gomoku.onlineBot`: the bot's move (GomokuBotOutput, as the solo bot's).
class GomokuOnlineBotJob extends GameJob<GomokuOnlineBotInput, GomokuBotOutput> {
  const GomokuOnlineBotJob();

  @override
  String get name => '${GameKeys.gomoku}.onlineBot';

  @override
  Object? encodeInput(GomokuOnlineBotInput input) => input.toJson();
  @override
  GomokuOnlineBotInput decodeInput(Object? json) => GomokuOnlineBotInput.fromJson(json);
  @override
  Object? encodeOutput(GomokuBotOutput output) => output.toJson();
  @override
  GomokuBotOutput decodeOutput(Object? json) => GomokuBotOutput.fromJson(json);

  @override
  GomokuBotOutput run(GomokuOnlineBotInput input, JobContext context) {
    final view = GomokuOnlineView.fromJson(input.view);
    final bot = GomokuBot(gomokuBotLevel(input.level), seed: input.seed, maxTime: gomokuTimeFor(context));
    final move = bot.chooseMove(view.game.viewFor(view.colorOf(view.you ?? view.seatToAct ?? 0)));
    return GomokuBotOutput(move.notation, how: bot.lastStats?.how ?? '');
  }

  @override
  List<GomokuOnlineBotInput> examples() => [
    for (final (i, view) in _exampleViews.indexed) GomokuOnlineBotInput(view: view, level: KitLevel.easy, seed: 3 + i),
  ];

  @override
  List<GomokuOnlineBotInput> checkInputs() => [
    for (final (i, view) in _checkViews().indexed)
      GomokuOnlineBotInput(view: view, level: KitLevel.values[i % 3], seed: 21 + i),
  ];
}

/// A spectator's coach in a room: the acting seat's view (rebuilt from the
/// spectators' view) and the round's coach seed.
class GomokuOnlineCoachInput {
  const GomokuOnlineCoachInput({required this.view, required this.seed});

  final Map<String, Object?> view;

  /// Unused by Gomoku's coach (it is the same every time), kept so every
  /// game's coach job takes the same input.
  final int seed;

  Map<String, Object?> toJson() => {'view': view, 'seed': seed};

  factory GomokuOnlineCoachInput.fromJson(Object? json) {
    final map = json! as Map<String, Object?>;
    return GomokuOnlineCoachInput(view: (map['view']! as Map).cast<String, Object?>(), seed: map['seed']! as int);
  }
}

/// `gomoku.onlineCoach`: the analysed moves for the side to move, best
/// first (the solo coach's analysis, encoded the same way).
class GomokuOnlineCoachJob extends GameJob<GomokuOnlineCoachInput, GomokuAnalysis> {
  const GomokuOnlineCoachJob();

  @override
  String get name => '${GameKeys.gomoku}.onlineCoach';

  @override
  Object? encodeInput(GomokuOnlineCoachInput input) => input.toJson();
  @override
  GomokuOnlineCoachInput decodeInput(Object? json) => GomokuOnlineCoachInput.fromJson(json);
  @override
  Object? encodeOutput(GomokuAnalysis output) => encodeGomokuAnalysis(output);
  @override
  GomokuAnalysis decodeOutput(Object? json) => decodeGomokuAnalysis(json);

  @override
  GomokuAnalysis run(GomokuOnlineCoachInput input, JobContext context) {
    final view = GomokuOnlineView.fromJson(input.view);
    final seat = view.you ?? view.seatToAct;
    return GomokuCoach(budget: gomokuCoachBudget(context, GomokuDepth.normal))
        .analyze(view.game.viewFor(seat == null ? null : view.colorOf(seat)));
  }

  @override
  List<GomokuOnlineCoachInput> examples() => [
    for (final view in _exampleViews) GomokuOnlineCoachInput(view: view, seed: 5),
  ];

  @override
  List<GomokuOnlineCoachInput> checkInputs() => [
    for (final (i, view) in _checkViews().indexed) GomokuOnlineCoachInput(view: view, seed: 31 + i),
  ];
}

// ---- views for the examples and the cross-platform check ----

/// The seat view of the side to move in [moves] under [rules], with Black
/// on hand seat [black].
Map<String, Object?> _viewOf(GomokuRules rules, String moves, {int black = 0}) {
  final game = GomokuGame.fromMoves(rules, GomokuGame.parseMoves(moves));
  final toMove = game.toMove == Stone.black ? black : 1 - black;
  return {...gomokuPublicView(rules, black, game), 'you': toMove};
}

/// Small, quick positions (forced moves: settled at once).
final _exampleViews = [
  // White's four d10-g10: Black (seat 1 here) must block at h10.
  _viewOf(GomokuRules.freestyle, 'c10 d10 h3 e10 j3 f10 l3 g10', black: 1),
  // Renju, Black to move: i8 would be a double three, forbidden.
  _viewOf(GomokuRules.renju, 'h8 a1 j8 a2 i9 a3 i10 a4'),
];

/// Games of every rule cut a few moves in, midway and near their end, with
/// Black on either seat.
const _checkGames = [
  (GomokuRules.freestyle, 'h8 g7 g8 f8 i5 e9 h6 d10 c11 e10 f10 e11 e12 c9 f12 b8 a7 b10 e7 b9'),
  (GomokuRules.standard, 'h8 f8 i8 f9 k8 j8 f7 f10 i7 i9 h7 f12 f11 h10 g11 g7 g9 g10'),
  (GomokuRules.renju, 'h8 f6 i7 j6 j8 k8 h6 k9 h5 h4 g5 f4 h7 h9 g7 j7 g6 k7'),
  (GomokuRules.freestyle19, 'j10 h8 k9 l8 l10 i10 j8 m11 j7 j6 i9 h9 k7 h6'),
  (GomokuRules.standard19, 'j10 h10 i11 h12 h11 g11 i9 f10 i10 i13'),
];

List<Map<String, Object?>> _checkViews() => [
  for (final (i, (rules, text)) in _checkGames.indexed)
    for (final cut in {2, 7, text.split(' ').length - 3})
      _viewOf(rules, text.split(' ').take(cut).join(' '), black: (i + cut) % 2),
];
