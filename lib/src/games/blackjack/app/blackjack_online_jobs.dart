/// Blackjack's jobs for a room (in blackjackJobs, so they run in a worker):
/// - `blackjack.onlineBot`: a bot's decision on the host's device, from
///   the bot's own view (the room's message, which never holds the hole
///   card or the shoe's order);
/// - `blackjack.onlineCoach`: a spectator's coach for the seat to act,
///   from that seat's view rebuilt from the spectators' one.
///
/// Both put the engine's view back together from the room's JSON
/// (blackjack_view_codec.dart) and decide exactly as the solo game's jobs
/// do. The solo jobs replay a shoe from its seed; online there is no seed
/// at all, so the view is all a job gets.
///
/// The basic strategy chart takes about a second to build, and each job
/// starts in a fresh worker. So the chart is built once per rules on each
/// device that needs one (the Hard bot, the coach): the first job without
/// one builds it, exactly as the `blackjack.chart` job would, and hands it
/// back with its answer; the device keeps it and passes it to every job
/// after (see BlackjackOnlineUi).
library;

import '../../../kit/jobs/jobs_core.dart';
import '../blackjack.dart';
import '../online/blackjack_view_codec.dart';
import 'blackjack_analysis_codec.dart' show BlackjackCoachResult;
import 'blackjack_examples.dart';
import 'blackjack_jobs.dart' show roundNumbers;
import 'blackjack_record.dart';

/// A room's decision for a job: the deciding seat's view (its `"you"`),
/// the bot's [level] (bot jobs only), and the chart for the view's rules if
/// the device has it already.
class BlackjackOnlineInput {
  const BlackjackOnlineInput({required this.view, this.level, this.chart});

  final Map<String, Object?> view;
  final BotLevel? level;
  final BasicStrategyChart? chart;

  Map<String, Object?> toJson() => {'view': view, 'level': ?level?.name, 'chart': ?chart?.toJson()};

  /// The input written by [toJson]; throws if [json] isn't one.
  factory BlackjackOnlineInput.fromJson(Object? json) {
    final map = json! as Map<String, Object?>;
    final level = map['level'] as String?;
    final chart = map['chart'];
    return BlackjackOnlineInput(
      view: (map['view']! as Map).cast<String, Object?>(),
      level: level == null ? null : BotLevel.values.byName(level),
      chart: chart == null ? null : BasicStrategyChart.fromJson(chart),
    );
  }

  /// The engine's view for the deciding seat. Throws if it isn't that
  /// seat's turn.
  BlackjackView engineView() {
    final view = blackjackViewFromWire(this.view);
    if (!view.isMyTurn) throw StateError('no decision for seat ${view.seat} here');
    return view;
  }

  /// The chart for [rules]: the one given, else built now (about a second).
  BasicStrategyChart chartFor(BlackjackRules rules) => chart ?? BasicStrategyChart.forRules(rules);
}

/// A job's answer, with the chart it built (null: it was given one, or
/// needed none), for the device to keep.
typedef BlackjackOnlineBotOutput = ({String move, BasicStrategyChart? chart});
typedef BlackjackOnlineCoachOutput = ({BlackjackCoachResult coach, BasicStrategyChart? chart});

/// A bot's decision in a room (kind `bot`): Easy and Medium by their simple
/// rules, Hard by the chart.
class BlackjackOnlineBotJob extends GameJob<BlackjackOnlineInput, BlackjackOnlineBotOutput> {
  const BlackjackOnlineBotJob();

  @override
  String get name => 'blackjack.onlineBot';

  @override
  Object? encodeInput(BlackjackOnlineInput input) => input.toJson();
  @override
  BlackjackOnlineInput decodeInput(Object? json) => BlackjackOnlineInput.fromJson(json);
  @override
  Object? encodeOutput(BlackjackOnlineBotOutput output) => {'mv': output.move, 'chart': ?output.chart?.toJson()};
  @override
  BlackjackOnlineBotOutput decodeOutput(Object? json) {
    final map = json! as Map<String, Object?>;
    final chart = map['chart'];
    return (move: map['mv']! as String, chart: chart == null ? null : BasicStrategyChart.fromJson(chart));
  }

  @override
  BlackjackOnlineBotOutput run(BlackjackOnlineInput input, JobContext context) {
    final view = input.engineView();
    final level = input.level ?? BotLevel.hard;
    final built = level == BotLevel.hard && input.chart == null ? input.chartFor(view.rules) : null;
    final action = BlackjackBot(level, chart: built ?? input.chart).chooseAction(view);
    return (move: handMove(view.turn!.hand, action), chart: built);
  }

  @override
  List<BlackjackOnlineInput> examples() => [
    for (final (i, d) in onlineExampleDecisions(quick: true).indexed)
      BlackjackOnlineInput(view: d.view, chart: d.chart, level: BotLevel.values[i % BotLevel.values.length]),
  ];

  /// Every example at every level, and one Hard bot that builds its chart.
  @override
  List<BlackjackOnlineInput> checkInputs() {
    final decisions = onlineExampleDecisions();
    return [
      for (final (i, d) in decisions.indexed)
        BlackjackOnlineInput(view: d.view, chart: d.chart, level: BotLevel.values[i % BotLevel.values.length]),
      BlackjackOnlineInput(view: decisions.last.view, level: BotLevel.hard),
    ];
  }

  @override
  Object? normalize(Object? outputJson) => roundNumbers(outputJson);
}

/// A spectator's coach in a room (kind `coach`): every legal decision of
/// the seat to act valued exactly, with the chart's play.
class BlackjackOnlineCoachJob extends GameJob<BlackjackOnlineInput, BlackjackOnlineCoachOutput> {
  const BlackjackOnlineCoachJob();

  @override
  String get name => 'blackjack.onlineCoach';

  @override
  Object? encodeInput(BlackjackOnlineInput input) => input.toJson();
  @override
  BlackjackOnlineInput decodeInput(Object? json) => BlackjackOnlineInput.fromJson(json);
  @override
  Object? encodeOutput(BlackjackOnlineCoachOutput output) => {
    'coach': output.coach.toJson(),
    'chart': ?output.chart?.toJson(),
  };
  @override
  BlackjackOnlineCoachOutput decodeOutput(Object? json) {
    final map = json! as Map<String, Object?>;
    final chart = map['chart'];
    return (
      coach: BlackjackCoachResult.fromJson(map['coach']),
      chart: chart == null ? null : BasicStrategyChart.fromJson(chart),
    );
  }

  @override
  BlackjackOnlineCoachOutput run(BlackjackOnlineInput input, JobContext context) {
    final view = input.engineView();
    final chart = input.chartFor(view.rules);
    return (
      coach: BlackjackCoachResult(
        hand: view.turn!.hand,
        evenMoney: view.offersEvenMoney,
        analysis: const BlackjackCoach().analyze(view, chart: chart),
      ),
      chart: input.chart == null ? chart : null,
    );
  }

  @override
  List<BlackjackOnlineInput> examples() => [
    for (final d in onlineExampleDecisions(quick: true)) BlackjackOnlineInput(view: d.view, chart: d.chart),
  ];

  /// Every example, and one without a chart (the first coach of a device).
  @override
  List<BlackjackOnlineInput> checkInputs() {
    final decisions = onlineExampleDecisions();
    return [
      for (final d in decisions) BlackjackOnlineInput(view: d.view, chart: d.chart),
      BlackjackOnlineInput(view: decisions.first.view),
    ];
  }

  @override
  Object? normalize(Object? outputJson) => roundNumbers(outputJson);
}

/// Decisions as a room sends them: the solo examples (one seat, see
/// exampleDecisions) as that seat's view, and seats of a three-seat table
/// dealt from the example rule sets, the Hard bot playing every seat. Each
/// with its rules' chart.
List<({Map<String, Object?> view, BasicStrategyChart chart})> onlineExampleDecisions({bool quick = false}) {
  final out = <({Map<String, Object?> view, BasicStrategyChart chart})>[];
  for (final d in exampleDecisions(quick: quick)) {
    final play = BlackjackPlay.replay(d.position);
    out.add((
      view: {
        ...blackjackPublicView(play.round!, roundNo: play.rounds),
        'you': 0,
      },
      chart: d.chart!,
    ));
  }
  final charts = exampleCharts;
  for (var r = 0; r < (quick ? 1 : charts.length); r++) {
    final chart = charts[r];
    final shoe = Shoe.forRules(chart.rules, seed: 201 + r);
    final bot = BlackjackBot(BotLevel.hard, chart: chart);
    var taken = 0;
    for (var roundNo = 1; roundNo <= 6 && taken < (quick ? 1 : 3); roundNo++) {
      final round = BlackjackRound.deal(chart.rules, shoe, const [1, 1, 1]);
      while (!round.isOver) {
        final seat = round.turn!.seat;
        // A decision of a seat other than the first, once per round (quick:
        // none of the coach's slowest spots, a small pair against a 2, 3 or
        // an ace, nor an offer).
        final view = round.viewFor(seat);
        final hand = view.handToPlay!;
        final slow = hand.isPair && const [1, 2, aceIndex].contains(view.dealerUpcard.rank);
        if (seat > 0 && taken < roundNo && !(quick && (slow || round.phase != RoundPhase.playing))) {
          out.add((
            view: {
              ...blackjackPublicView(round, roundNo: roundNo),
              'you': seat,
            },
            chart: chart,
          ));
          taken++;
        }
        round.apply(bot.chooseAction(view));
      }
    }
  }
  return out;
}
