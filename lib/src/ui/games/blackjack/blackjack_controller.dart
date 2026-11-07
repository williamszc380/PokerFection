import '../../../games/blackjack/app/blackjack_analysis_codec.dart';
import '../../../games/blackjack/app/blackjack_grading.dart';
import '../../../games/blackjack/app/blackjack_jobs.dart';
import '../../../games/blackjack/app/blackjack_range.dart';
import '../../../games/blackjack/app/blackjack_record.dart';
import '../../../games/blackjack/blackjack.dart';
import '../../../kit/coach_answer.dart';
import '../../../kit/game_keys.dart';
import '../../../kit/game_record.dart';
import '../../../kit/grading.dart';
import '../../../kit/jobs/jobs.dart';
import '../../../kit/jobs/jobs_core.dart';
import '../../kit/game_sounds.dart';
import '../../kit/turn_controller.dart';
import 'blackjack_dealing.dart';

/// What the setup chose for a game of blackjack.
class BlackjackSettings {
  const BlackjackSettings({
    this.rules = const BlackjackRules(),
    this.training = true,
    this.coachMode = CoachMode.fresh,
    this.toggles = const {},
  });

  /// The settings a saved shoe was played with (the setup's defaults where
  /// it says nothing), with its screen toggles, so a game started from the
  /// setup looks like the last one.
  factory BlackjackSettings.fromRecord(GameRecord record) => BlackjackSettings(
    rules: BlackjackRules.fromJson(record.rules),
    training: record.extra['mode'] != 'free',
    coachMode: CoachMode.byName(record.extra['coachMode']),
    toggles: {
      for (final key in toggleKeys)
        if (record.extra[key] case final bool on) key: on,
    },
  );

  /// The toggles a record's extra may carry: ☰ Count, the coach chip and
  /// ☰ Show cards (the hole card face up, Training only).
  static const toggleKeys = ['count', 'coach', TurnController.showCardsKey];

  final BlackjackRules rules;

  /// Training (the coach and grades) or Free Play.
  final bool training;
  final CoachMode coachMode;

  /// The screen's toggles to start with ([toggleKeys]).
  final Map<String, Object?> toggles;

  /// These settings with some choices changed (the toggles kept).
  BlackjackSettings copyWith({BlackjackRules? rules, bool? training, CoachMode? coachMode}) => BlackjackSettings(
    rules: rules ?? this.rules,
    training: training ?? this.training,
    coachMode: coachMode ?? this.coachMode,
    toggles: toggles,
  );

  /// What a record keeps of them besides the rules.
  Map<String, Object?> get extra => {'mode': training ? 'training' : 'free', 'coachMode': coachMode.name};
}

/// One player against the dealer, a shoe at a time. One shoe is one game:
/// between rounds the player's only move is the deal ("d"), and the game
/// ends when the cut card comes out (50 rounds with a continuous shuffler);
/// then New shoe starts the next game with the same rules. The dealer
/// plays inside the engine, so nobody else ever has a turn.
///
/// The strategy chart for the rules is made once, by its own job ([prepare]),
/// and goes with every coach job, since each job starts in a fresh isolate
/// or worker with nothing cached. Turns don't wait for it: Deal and the
/// moves work at once on a new shoe, and the kit holds back the coach's
/// jobs until the chart is made, so every answer carries it (a move made
/// meanwhile is graded when its job answers).
class BlackjackController extends TurnController {
  BlackjackController({
    required this.settings,
    required super.jobs,
    required super.lastGames,
    required this.playerName,
    required this.dealerName,
    super.speed,
    super.random,
  }) : super(gameKey: GameKeys.blackjack, training: settings.training);

  final BlackjackSettings settings;

  /// The seats' names in the player's language ("Dealer wins").
  final String playerName;
  final String dealerName;

  BlackjackRules get rules => settings.rules;
  CoachMode get coachMode => settings.coachMode;

  BlackjackPlay? _play;
  BasicStrategyChart? _chart;
  JobHandle<BasicStrategyChart>? _chartJob;

  /// The cards of the move just made, flying in from the shoe one by one
  /// (the table holds them back meanwhile). When the dealer's play has
  /// played out, the panel tells the result.
  late final BlackjackDealing dealing = BlackjackDealing(flights: flights, speed: () => speed, onDone: _dealt);
  var _closed = false;

  void _dealt() {
    if (!_closed) notifyListeners();
  }

  /// The shoe being played.
  BlackjackPlay get play => _play ?? (throw StateError('No game yet: call newGame'));

  /// The strategy chart for the rules, once its job has finished.
  BasicStrategyChart? get chart => _chart;

  /// The running count and cards left show on the table (☰ Count); kept
  /// in the record, so the next shoe keeps it.
  bool get showCount => started && record.extra['count'] == true;
  set showCount(bool show) => setExtra('count', show);

  /// The insurance offer standing now is even money (the player's
  /// blackjack against an ace): the coach list names its rows so.
  bool get offersEvenMoney {
    final round = started ? play.round : null;
    return round != null && round.phase == RoundPhase.insurance && play.view().offersEvenMoney;
  }

  /// Whether move [index] of the shoe answered an even-money offer, so the
  /// feedback names that move as its button did. Asked for insurance moves
  /// only; the shoe up to a move never changes, so each answer is kept
  /// until the next shoe.
  bool evenMoneyAt(int index) => _evenMoneyAt[index] ??= evenMoneyAtMove(record, index);
  final _evenMoneyAt = <int, bool>{};

  /// The round is between deals: the panel shows Deal.
  bool get betweenRounds => started && play.betweenRounds;

  // ---- the game ----

  @override
  int? get seatToAct => started && !play.shoeOver ? playerSeat : null;

  @override
  bool isHuman(int seat) => seat == playerSeat;

  @override
  bool get isOver => started && play.shoeOver;

  /// The player wins a shoe that ends ahead, the dealer one that ends
  /// behind; level is a draw.
  @override
  List<int> get winners => !isOver || play.net == 0
      ? const []
      : play.net > 0
      ? const [playerSeat]
      : const [dealerSeat];

  @override
  Map<String, Object?> get result => {'winners': winners, 'net': play.net, 'rounds': play.rounds};

  @override
  GameRecord deal({GameRecord? previous}) {
    final seed = nextGameSeed();
    // A new shoe: the last one's cards leave the felt at once.
    dealing.finish();
    _play = BlackjackPlay(rules, shoeSeed: seed);
    _evenMoneyAt.clear();
    return newBlackjackRecord(
      rules: rules,
      seed: seed,
      playerName: playerName,
      dealerName: dealerName,
      // The first shoe brings the last game's toggles; a New shoe keeps
      // the ones on screen (the kit carries them over).
      extra: {if (!started) ...settings.toggles, ...settings.extra},
    );
  }

  /// The chart job, once per rules: a new shoe with the same rules keeps
  /// the chart. The chart's play tags the coach's answers. Turns don't wait
  /// for it: the kit defers the coach's jobs until it ends, so every answer
  /// carries the chart, and Deal works at once (Free Play has no coach and
  /// needs none). If the job fails, coach jobs go without a chart and the
  /// engine makes its own. Leaving while it runs cancels it, and the kit
  /// reports nothing for a game that was left.
  @override
  Future<void> prepare() async {
    if (_chart != null || !training) return;
    final job = _chartJob ??= jobs.start(const BlackjackChartJob(), rules, kind: JobKind.guide);
    try {
      _chart = await job.result;
    } finally {
      if (_chartJob == job) _chartJob = null;
    }
  }

  /// Plays [move] and sends its cards flying in: the first leaves now,
  /// while the screen still shows the felt before the move.
  @override
  void applyMove(int seat, String move) {
    final before = play.roundNets.length;
    final action = parseHandMove(move)?.action;
    final felt = FeltBefore.of(play);
    play.apply(move);
    dealing.start(DealPlan.of(felt, play, split: action == BlackjackAction.split));
    playSound(switch (action) {
      null => SoundEffect.deal,
      BlackjackAction.hit => SoundEffect.deal,
      BlackjackAction.stand || BlackjackAction.noInsurance || BlackjackAction.keepPlaying => SoundEffect.check,
      BlackjackAction.double || BlackjackAction.split || BlackjackAction.insurance => SoundEffect.chips,
      BlackjackAction.surrender => SoundEffect.fold,
    });
    // A round that just ended: its own win or loss (the shoe's last round
    // gets the game's sound from the kit instead).
    if (play.roundNets.length > before && !play.shoeOver) {
      final net = play.roundNets.last;
      if (net > 0) playSound(SoundEffect.win);
      if (net < 0) playSound(SoundEffect.lose);
    }
  }

  /// Not used at one seat; there for tables with more (the Hard bot).
  @override
  JobRequest botRequest(int seat, int seed) => JobRequest(
    const BlackjackBotJob(),
    BlackjackDecisionInput(position: record, seat: seat, chart: _chart, level: BotLevel.hard),
    JobKind.bot,
  );

  @override
  String fallbackBotMove(int seat) {
    final view = play.round!.viewFor(seat);
    return handMove(view.turn!.hand, BlackjackBot(BotLevel.easy).chooseAction(view));
  }

  /// No coach between rounds: the deal is not a decision.
  @override
  bool coachWanted(int seat) => !play.betweenRounds;

  /// Every decision the hand may make now (Hit, Stand, Double, Split,
  /// Surrender; Insurance or not; Surrender or Keep playing): the coach
  /// list shows them all, however many rows that takes, so a legal choice
  /// is never missing from it. The coach values every legal one already.
  @override
  List<String> listedMoves(int seat) => started ? blackjackListedMoves(play) : const [];

  /// A coach row's double click (or Enter on the row selected) makes the
  /// decision only when its button would: not while the cards are being
  /// dealt or the dealer plays, and only a legal one.
  @override
  bool playFromCoach(String move) {
    if (!started || dealing.busy || !play.legalMoves().contains(move)) return false;
    return super.playFromCoach(move);
  }

  /// Training: tapping the dealer shows what the hole card could be and
  /// what the dealer's two cards could add up to, from the cards the player
  /// has seen (never the hole card itself, even when ☰ Show cards turns it
  /// up). Only at hole-card tables, once a round is dealt.
  @override
  JobRequest? rangeRequest(GameRecord position, int seat, {required int seed}) =>
      seat == dealerSeat && started && dealerRangeShows(play)
      ? JobRequest(const BlackjackRangeJob(), position, JobKind.range)
      : null;

  @override
  JobRequest coachRequest(GameRecord position, int seat, {String? include, bool deep = false, required int seed}) =>
      // Every legal action is always valued (no `include` needed), and the
      // values are exact, so a deep answer is the same answer.
      JobRequest(
        const BlackjackCoachJob(),
        BlackjackDecisionInput(position: position, seat: seat, chart: _chart),
        JobKind.coach,
      );

  @override
  CoachAnswer toAnswer(Object? output) => blackjackAnswer(output! as BlackjackCoachResult, coachMode);

  @override
  GradeScale get scale => blackjackScale;

  @override
  MoveMark? grade(CoachAnswer answer, String played) => gradeBlackjack(answer, played, coachMode);

  /// The answers are exact: thinking longer can't change them.
  @override
  bool get canThinkLonger => false;

  /// The coach's result for this turn (the hand, even money), once it came.
  BlackjackCoachResult? get coachResult => coach?.detail as BlackjackCoachResult?;

  @override
  void dispose() {
    _closed = true;
    _chartJob?.cancel();
    dealing.dispose();
    super.dispose();
  }
}

/// The decisions the coach list always shows in [play]: every legal one in
/// a round, none between rounds (the deal is no decision). The game and its
/// review share it.
List<String> blackjackListedMoves(BlackjackPlay play) =>
    play.betweenRounds ? const [] : [for (final move in play.legalMoves()) if (move != dealMove) move];
