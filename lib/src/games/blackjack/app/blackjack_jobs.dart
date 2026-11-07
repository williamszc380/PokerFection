/// Blackjack's background jobs, registered in lib/src/kit/jobs/job_registry.dart:
/// - `blackjack.chart`: the basic strategy chart for a rule set. It takes
///   about a second, so a game runs it once at the start (and the Basic
///   strategy guide once per rule set shown) and passes the chart to every
///   coach and bot job: each job starts in a fresh isolate or worker, where
///   the engine's own chart cache is empty.
/// - `blackjack.coach`: the exact value of every legal action for the
///   player's decision, in both knowledge modes, with the chart's play.
/// - `blackjack.bot`: a computer player's decision (not used by the
///   one-player game; it is there for tables with more seats).
/// - `blackjack.range`: the dealer's range, what the hole card could be
///   and what the dealer's two cards could add up to (Training, tapping
///   the dealer), worked out exactly from the cards the player has seen.
/// - `blackjack.onlineBot` and `blackjack.onlineCoach`: a room's bots and a
///   spectator's coach, from the room's views (blackjack_online_jobs.dart).
///
/// Coach and bot inputs are the shoe's record cut at the decision (no marks
/// or toggles) plus the seat; the job replays it and gives the engine only
/// that seat's view, so nothing hidden (the hole card, the shoe's order)
/// can reach an answer.
library;

import '../../../kit/game_record.dart';
import '../../../kit/jobs/jobs_core.dart';
import '../../../kit/range.dart';
import '../blackjack.dart';
import 'blackjack_analysis_codec.dart';
import 'blackjack_examples.dart';
import 'blackjack_online_jobs.dart';
import 'blackjack_range.dart';
import 'blackjack_record.dart';

/// Blackjack's background jobs (see job_registry.dart).
final List<GameJob<Object?, Object?>> blackjackJobs = [
  const BlackjackChartJob(),
  const BlackjackCoachJob(),
  const BlackjackBotJob(),
  const BlackjackRangeJob(),
  const BlackjackOnlineBotJob(),
  const BlackjackOnlineCoachJob(),
];

/// A coach or bot job's input: a shoe cut at the decision, the seat
/// deciding, and the chart for the shoe's rules (null: the engine builds
/// one, which takes about a second; only if the chart job failed).
class BlackjackDecisionInput {
  const BlackjackDecisionInput({required this.position, this.seat = playerSeat, this.chart, this.level});

  /// The shoe up to the decision (GameRecord.upTo).
  final GameRecord position;
  final int seat;
  final BasicStrategyChart? chart;

  /// The bot's level (bot jobs only).
  final BotLevel? level;

  Map<String, Object?> toJson() => {
    'record': position.jobJson(),
    'seat': seat,
    'chart': ?chart?.toJson(),
    'level': ?level?.name,
  };

  /// The input written by [toJson]; throws if [json] isn't one.
  factory BlackjackDecisionInput.fromJson(Object? json) {
    final map = json! as Map<String, Object?>;
    final chart = map['chart'];
    final level = map['level'] as String?;
    return BlackjackDecisionInput(
      position: _record(map['record']),
      seat: map['seat']! as int,
      chart: chart == null ? null : BasicStrategyChart.fromJson(chart),
      level: level == null ? null : BotLevel.values.byName(level),
    );
  }

  static GameRecord _record(Object? json) =>
      GameRecord.fromJson(json, game: 'blackjack', version: blackjackRecordVersion) ??
      (throw const FormatException('not a blackjack record'));

  /// The seat's view at the decision. Throws if it isn't that seat's turn.
  BlackjackView view() {
    final play = BlackjackPlay.replay(position);
    final round = play.round;
    if (round == null || round.isOver || round.turn?.seat != seat) {
      throw StateError('no decision for seat $seat here');
    }
    return round.viewFor(seat);
  }
}

/// The basic strategy chart for a rule set (about 0.9 s native, kind
/// `guide`). Same rules, same chart: the chart carries exactly the rules
/// asked for.
class BlackjackChartJob extends GameJob<BlackjackRules, BasicStrategyChart> {
  const BlackjackChartJob();

  @override
  String get name => 'blackjack.chart';

  @override
  Object? encodeInput(BlackjackRules input) => input.toJson();
  @override
  BlackjackRules decodeInput(Object? json) => BlackjackRules.fromJson(json);
  @override
  Object? encodeOutput(BasicStrategyChart output) => output.toJson();
  @override
  BasicStrategyChart decodeOutput(Object? json) => BasicStrategyChart.fromJson(json);

  /// The engine's build. It has no time budget to pass: it always finishes
  /// (about a second), and the kit's safety timer covers the cap.
  @override
  BasicStrategyChart run(BlackjackRules input, JobContext context) => BasicStrategyChart.forRules(input);

  /// None: every chart takes far longer than the 50 ms an example may.
  @override
  List<BlackjackRules> examples() => const [];

  /// The rule sets the examples use, for the cross-platform check.
  @override
  List<BlackjackRules> checkInputs() => [for (final rules in exampleRules) rules];

  /// The edge, a long fraction, rounded to 9 decimals.
  @override
  Object? normalize(Object? outputJson) => roundNumbers(outputJson);
}

/// The coach's answer for the player's decision: every legal action valued
/// exactly (kind `coach`). There is no budget to pass: the values are exact
/// and an answer takes a few milliseconds (at worst about 140 ms native).
class BlackjackCoachJob extends GameJob<BlackjackDecisionInput, BlackjackCoachResult> {
  const BlackjackCoachJob();

  @override
  String get name => 'blackjack.coach';

  @override
  Object? encodeInput(BlackjackDecisionInput input) => input.toJson();
  @override
  BlackjackDecisionInput decodeInput(Object? json) => BlackjackDecisionInput.fromJson(json);
  @override
  Object? encodeOutput(BlackjackCoachResult output) => output.toJson();
  @override
  BlackjackCoachResult decodeOutput(Object? json) => BlackjackCoachResult.fromJson(json);

  @override
  BlackjackCoachResult run(BlackjackDecisionInput input, JobContext context) {
    final view = input.view();
    return BlackjackCoachResult(
      hand: view.turn!.hand,
      evenMoney: view.offersEvenMoney,
      analysis: const BlackjackCoach().analyze(view, chart: input.chart),
    );
  }

  @override
  List<BlackjackDecisionInput> examples() => exampleDecisions(quick: true);

  @override
  List<BlackjackDecisionInput> checkInputs() => exampleDecisions();

  /// Values rounded to 9 decimals (well past anything shown or graded).
  @override
  Object? normalize(Object? outputJson) => roundNumbers(outputJson);
}

/// A computer player's decision, as a move (kind `bot`).
class BlackjackBotJob extends GameJob<BlackjackDecisionInput, String> {
  const BlackjackBotJob();

  @override
  String get name => 'blackjack.bot';

  @override
  Object? encodeInput(BlackjackDecisionInput input) => input.toJson();
  @override
  BlackjackDecisionInput decodeInput(Object? json) => BlackjackDecisionInput.fromJson(json);
  @override
  Object? encodeOutput(String output) => output;
  @override
  String decodeOutput(Object? json) => json! as String;

  @override
  String run(BlackjackDecisionInput input, JobContext context) {
    final view = input.view();
    final action = BlackjackBot(input.level ?? BotLevel.hard, chart: input.chart).chooseAction(view);
    return handMove(view.turn!.hand, action);
  }

  @override
  List<BlackjackDecisionInput> examples() => [
    for (final (i, d) in exampleDecisions(quick: true).indexed)
      BlackjackDecisionInput(position: d.position, chart: d.chart, level: BotLevel.values[i % BotLevel.values.length]),
  ];

  @override
  List<BlackjackDecisionInput> checkInputs() => [
    for (final (i, d) in exampleDecisions().indexed)
      BlackjackDecisionInput(position: d.position, chart: d.chart, level: BotLevel.values[i % BotLevel.values.length]),
  ];
}

/// The dealer's range in a shoe cut at some move (GameRecord.upTo), as
/// the player can work it out (kind `range`; see blackjack_range.dart). It
/// replays the shoe and reads only the player's view. Exact and quick: a
/// count of the unseen cards, well under a millisecond.
class BlackjackRangeJob extends GameJob<GameRecord, OpponentRange> {
  const BlackjackRangeJob();

  @override
  String get name => 'blackjack.range';

  @override
  Object? encodeInput(GameRecord input) => input.jobJson();
  @override
  GameRecord decodeInput(Object? json) => BlackjackDecisionInput._record(json);
  @override
  Object? encodeOutput(OpponentRange output) => output.toJson();
  @override
  OpponentRange decodeOutput(Object? json) => OpponentRange.fromJson(json);

  @override
  OpponentRange run(GameRecord input, JobContext context) => dealerRange(BlackjackPlay.replay(input));

  @override
  List<GameRecord> examples() => _rangePositions(exampleDecisions(quick: true));

  /// The example decisions at hole-card tables (the hole card face down,
  /// the dealer having checked or not), and each of their rounds played
  /// out with Stand, the hole card then turned over.
  @override
  List<GameRecord> checkInputs() {
    final hidden = _rangePositions(exampleDecisions());
    return [...hidden, for (final position in hidden.take(8)) ?_standToTheEnd(position)];
  }

  /// Every number (the chances are rounded to 4 decimals by
  /// OpponentRange.toJson) as a whole count of ten-thousandths, because
  /// JavaScript can't tell 1.0 from 1.
  @override
  Object? normalize(Object? outputJson) => _countTenThousandths(outputJson);

  static List<GameRecord> _rangePositions(List<BlackjackDecisionInput> decisions) => [
    for (final d in decisions)
      if (dealerRangeShows(BlackjackPlay.replay(d.position))) d.position,
  ];

  /// [position] with Stand played on every hand until the round is over,
  /// or null if Stand isn't legal somewhere on the way (an offer).
  static GameRecord? _standToTheEnd(GameRecord position) {
    var record = position;
    final play = BlackjackPlay.replay(record);
    for (var round = play.round; round != null && !round.isOver; round = play.round) {
      final hand = round.turn?.hand;
      if (hand == null) return null;
      final move = handMove(hand, BlackjackAction.stand);
      if (!play.legalMoves().contains(move)) return null;
      play.apply(move);
      record = record.withMove(move);
    }
    return record;
  }
}

Object? _countTenThousandths(Object? json) => switch (json) {
  final num v => (v * 10000).round(),
  final Map<String, Object?> m => {for (final e in m.entries) e.key: _countTenThousandths(e.value)},
  final List<Object?> l => [for (final v in l) _countTenThousandths(v)],
  _ => json,
};

/// [json] with every number as a whole count of billionths, so outputs
/// compare equal on every platform even if the last bits of a sum differ.
/// Whole numbers are counted the same way, because JavaScript can't tell
/// 1.0 from 1.
Object? roundNumbers(Object? json) => switch (json) {
  final num v => (v * 1e9).round(),
  final Map<String, Object?> m => {for (final e in m.entries) e.key: roundNumbers(e.value)},
  final List<Object?> l => [for (final v in l) roundNumbers(v)],
  _ => json,
};
