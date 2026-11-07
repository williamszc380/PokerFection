import '../../../games/big_two/app/big_two_analysis.dart';
import '../../../games/big_two/app/big_two_grading.dart';
import '../../../games/big_two/app/big_two_jobs.dart';
import '../../../games/big_two/app/big_two_match.dart';
import '../../../games/big_two/app/big_two_range.dart';
import '../../../games/big_two/app/big_two_record.dart';
import '../../../games/big_two/big_two.dart';
import '../../../kit/coach_answer.dart';
import '../../../kit/game_keys.dart';
import '../../../kit/game_record.dart';
import '../../../kit/grading.dart';
import '../../../kit/hand_order.dart';
import '../../../kit/jobs/jobs_core.dart';
import '../../../kit/match.dart';
import '../../../kit/seats.dart';
import '../../kit/card_flights.dart';
import '../../kit/cards.dart' show HandFan;
import '../../kit/game_sounds.dart';
import '../../kit/table_pile.dart' show TablePile;
import '../../kit/turn_controller.dart';
import 'big_two_coach_view.dart' show bigTwoFace;
import 'big_two_opening.dart' show BigTwoOpeningTimer;
import 'big_two_table.dart' show BigTwoTableFacts;

/// [cards] (a hand, lowest first under [rules]) sorted as [sort] says: by
/// rank (then suit, as the rules order them), or by suit (then rank).
/// [HandOrder.own] is no sort of its own: the hand comes back by rank.
List<Card> sortedHand(BigTwoRules rules, List<Card> cards, HandOrder sort) {
  if (sort != HandOrder.suit) return cards;
  return [...cards]..sort((a, b) {
    final bySuit = rules.suitStrength(a.suit).compareTo(rules.suitStrength(b.suit));
    return bySuit != 0 ? bySuit : a.rank.compareTo(b.rank);
  });
}

/// How the player's hand was laid out, as a record's extra keeps it: the
/// sort last chosen ('sort', 'rank' or 'suit', by rank when it has none)
/// and the player's own order once they dragged a card ('order', each card
/// as short text such as "Td"; null while sorted).
HandArrangement<Card> arrangementOf(Map<String, Object?> extra) =>
    HandArrangement.fromExtra<Card>(extra, (code) => code is String ? _tryCard(code) : null);

/// The extra keys [arrangement] is kept under (see arrangementOf).
Map<String, Object?> arrangementExtra(HandArrangement<Card> arrangement) => arrangement.toExtra((card) => card.short);

Card? _tryCard(String code) {
  try {
    return Card.parse(code);
  } on FormatException {
    return null;
  }
}

/// [cards] (the player's, lowest first under [rules]) as [arrangement] lays
/// them out: sorted by its sort, then in the player's own order if they
/// made one (cards they have played drop out of it).
List<Card> arrangedHand(BigTwoRules rules, List<Card> cards, HandArrangement<Card> arrangement) =>
    arrangement.arrange(sortedHand(rules, cards, arrangement.sort));

/// What the setup chose: the rules, the bots, the mode and the match's
/// target, plus the screen's toggles from the last game (the hand's sort,
/// Card counter, the coach, Show cards).
class BigTwoSetup {
  BigTwoSetup({
    required this.rules,
    this.level = KitLevel.medium,
    this.seatLevels,
    this.training = true,
    MatchTarget? match,
    this.toggles = const {},
  }) : match = match ?? bigTwoStandardTarget(rules.scoring);

  final BigTwoRules rules;

  /// Every bot's level, unless [seatLevels] gives one per bot.
  final KitLevel level;

  /// "Customize seats": one level per bot (seat 1 first), or null.
  final List<KitLevel>? seatLevels;

  /// Training (grades and the coach) or Free Play, fixed for the game.
  final bool training;

  /// The match: play to a target (the scoring's standard unless chosen,
  /// see bigTwoStandardTarget), or No limit; scaled with the players when
  /// asked (bigTwoMatchTarget).
  final MatchTarget match;

  /// The screen's toggles to start with ('coach', 'sort', 'counter',
  /// 'showCards').
  final Map<String, Object?> toggles;

  /// A first game is two players: Player against one bot.
  static const defaultPlayers = 2;

  /// The toggles a record's extra may carry. The player's own card order
  /// ('order') is not one: every game starts sorted.
  static const toggleKeys = ['coach', 'sort', 'counter', TurnController.showCardsKey];

  /// Where the record's extra keeps [match] (the setup's choice; the match
  /// itself is the kit's, under MatchScore.extraKey).
  static const matchKey = 'matchTarget';

  /// Each bot's level, seat 1 first.
  List<KitLevel> get levels {
    final custom = seatLevels;
    return [for (var i = 0; i < rules.players - 1; i++) custom != null && i < custom.length ? custom[i] : level];
  }

  /// The seats: the player at seat 0, then the bots, named in order. The
  /// player's seat is shown as S.you ("Player") in the app's language; the
  /// name saved here is only a fallback.
  List<SeatSpec> get seats => [
    const SeatSpec(human: true, name: 'Player'),
    for (final (i, l) in levels.indexed) SeatSpec(human: false, level: l, name: kitBotNames[i]),
  ];

  /// What the record keeps of the setup besides the rules and seats.
  Map<String, Object?> get extra => {
    'mode': training ? 'training' : 'free',
    'level': level.name,
    if (seatLevels != null) 'customSeats': true,
    matchKey: match.toJson(),
  };

  /// This setup with [match] as its target.
  BigTwoSetup withMatch(MatchTarget match) => BigTwoSetup(
    rules: rules,
    level: level,
    seatLevels: seatLevels,
    training: training,
    match: match,
    toggles: toggles,
  );

  /// The setup [record] was played with (the setup pre-fills from it),
  /// or the default one when there is no record: the standard rules for
  /// [defaultPlayers].
  factory BigTwoSetup.from(GameRecord? record) {
    if (record == null) return BigTwoSetup(rules: BigTwoRules.standard(players: defaultPlayers));
    final rules = BigTwoRecord.rulesOf(record);
    final levels = [for (final seat in record.seats.skip(1)) seat.level ?? KitLevel.medium];
    final level = KitLevel.values.asNameMap()[record.extra['level']] ?? levels.firstOrNull ?? KitLevel.medium;
    return BigTwoSetup(
      rules: rules,
      level: level,
      seatLevels: record.extra['customSeats'] == true ? levels : null,
      training: record.extra['mode'] != 'free',
      match: MatchTarget.fromJson(record.extra[matchKey], fallback: bigTwoStandardTarget(rules.scoring)),
      toggles: {
        for (final key in toggleKeys)
          if (record.extra.containsKey(key)) key: record.extra[key],
      },
    );
  }
}

/// Runs a Big Two game for the screen: the engine, the bots and the coach
/// through the kit, plus what the screen shows and does: the cards the
/// player has picked, the move under the mouse in the coach list, how the
/// hand is laid out (sorted, or in the player's own order), the Card
/// counter toggle, the session's points, the match (see big_two_match.dart)
/// and the opponents' ranges (big_two.range).
///
/// The player sits at seat 0. One deal is one record; after it, Next deal
/// starts another with the same seats, rules and toggles, and adds the
/// deal's points to the match.
///
/// Every deal opens with who goes first ([opening], BigTwoOpening): for
/// [openingLength] (the Animations speed: about two seconds at Normal,
/// none at Instant) nobody is to act, so neither the bots nor the player
/// move while the felt shows it; then the turns go on.
class BigTwoController extends TurnController {
  BigTwoController({required this.setup, required super.jobs, required super.lastGames, super.speed, super.random})
    : rules = setup.rules,
      super(gameKey: GameKeys.bigTwo, training: setup.training);

  final BigTwoSetup setup;
  final BigTwoRules rules;

  BigTwoState? _state;
  BigTwoOpeningTimer? _opening;
  var _openingDeal = 0;
  Duration _openingLength = Duration.zero;
  final _selected = <Card>{};
  String? _preview;
  int _net = 0;

  /// The player's seat as the screen names it ("Player" in the app's
  /// language, S.you); the record keeps an English fallback. The screen
  /// sets it, so the kit's scoreboard and status say it too.
  String? youName;

  /// The deal as it stands (every hand: the screen shows only the player's
  /// until the deal ends).
  BigTwoState get state => _state ?? (throw StateError('No deal yet: call newGame'));

  // ---- the game, for the kit ----

  @override
  int? get seatToAct {
    final state = _state;
    // Nobody acts while the felt shows who goes first.
    return state == null || state.isOver || openingPlaying ? null : state.toMove;
  }

  // ---- who goes first ----

  /// This deal's who-goes-first step, from its public facts (the starter,
  /// the cards shown); null for a deal a dealt dragon won, or before one.
  BigTwoOpening? get opening => _state == null ? null : BigTwoOpening.of(_state!);

  /// The step is playing: nobody moves until it ends (then the turns go
  /// on by themselves).
  bool get openingPlaying => _opening?.running ?? false;

  /// How far the step is, 0 to 1 (1 once it is over).
  double get openingProgress => _opening?.progress ?? 1;

  /// The step has named the starter: with two players the low cards have
  /// been called up to the one somebody holds (the headline says "Who
  /// starts?" until then). True once the step is over.
  bool get openingNamed => !openingPlaying || _opening!.named;

  /// How long this deal's step plays (zero at Instant: only its result
  /// shows, the felt's note).
  Duration get openingLength => _openingLength;

  /// The deals dealt so far: a new one starts the felt's step again.
  int get openingDeal => _openingDeal;

  /// Starts the step for the deal just dealt, at the speed now.
  void _startOpening() {
    _opening?.cancel();
    _opening = null;
    _openingDeal++;
    final step = _state!.isOver ? null : opening;
    _openingLength = step == null ? Duration.zero : step.lengthAt(speed.factor);
    if (step == null || _openingLength <= Duration.zero) return;
    _opening = BigTwoOpeningTimer(_openingLength, namedAt: step.namedAt, onNamed: notifyListeners, onEnd: resume);
  }

  @override
  void dispose() {
    _opening?.cancel();
    _opening = null;
    super.dispose();
  }

  @override
  bool isHuman(int seat) => seat == 0;

  @override
  bool get isOver => _state?.isOver ?? false;

  @override
  List<int> get winners => isOver ? [state.winner] : const [];

  @override
  Map<String, Object?> get result => BigTwoRecord.resultOf(state);

  @override
  bool get playsRounds => true;

  @override
  String seatName(int seat) => seat == 0 && youName != null ? youName! : super.seatName(seat);

  /// The setup's target at this table (see bigTwoStartMatch); null: No limit.
  @override
  MatchScore? startMatch() => bigTwoStartMatch(setup.match, rules);

  /// Penalties under penalty scoring, the winner's points under Pusoy Dos
  /// scoring (bigTwoDealPoints).
  @override
  List<int>? dealPoints() => bigTwoDealPoints(rules, state.result);

  /// Pass, whenever it is legal: the coach list always shows it.
  @override
  List<String> listedMoves(int seat) => bigTwoListedMoves(state, seat);

  /// An opponent's range from the player's view (big_two.range); none once
  /// the deal is over (every hand is face up then).
  @override
  JobRequest? rangeRequest(GameRecord position, int seat, {required int seed}) {
    if (seat == 0 || isOver) return null;
    return JobRequest(
      const BigTwoRangeJob(),
      BigTwoRangeInput(record: position.jobJson(), viewer: 0, seat: seat, seed: seed),
      JobKind.range,
    );
  }

  @override
  GameRecord deal({GameRecord? previous}) {
    final last = started ? arrangement : arrangementOf(setup.toggles);
    final record = BigTwoRecord.deal(
      rules: rules,
      seats: setup.seats,
      seed: nextGameSeed(),
      // The first deal brings the last game's toggles; later deals keep
      // the current ones (the kit carries them over). Each deal starts
      // sorted, by the sort last chosen: an order the player made for the
      // last hand means nothing for this one.
      extra: {if (!started) ...setup.toggles, ...setup.extra, ...arrangementExtra(last.dealt)},
    );
    _state = BigTwoRecord.replay(record);
    _selected.clear();
    _preview = null;
    _startOpening();
    playSound(SoundEffect.deal);
    // A dealt dragon ends the deal before anyone plays.
    if (_state!.isOver) _net += _state!.result.scores[0];
    return record;
  }

  @override
  Future<void> newGame() {
    _net = 0;
    return super.newGame();
  }

  @override
  void applyMove(int seat, String move) {
    final (seat: who, :play) = bigTwoParseMove(rules, move);
    if (who != seat) throw ArgumentError('$move is not seat $seat\'s');
    final state = this.state;
    final beat = state.current;
    // The cards fly to the pile: from the player's hand, or from the bot's
    // badge (face up: everyone sees a play). Launched before the move
    // changes the screen, while the cards are still in the hand.
    if (!play.isPass) {
      final turn = state.history.length;
      flights.fly([
        for (final (k, card) in play.cards.indexed)
          CardFlight(
            from: seat == 0 ? HandFan.flightTag(bigTwoFace(card)) : CardFlights.seatTag(seat),
            to: TablePile.flightTag(turn, k),
            face: bigTwoFace(card),
          ),
      ]);
    }
    state.apply(play);
    if (seat == 0) _selected.clear();
    _preview = null;
    playSound(switch (play) {
      _ when play.isPass => SoundEffect.pass,
      // A bomb dropped on a smaller play.
      _ when rules.bombs && play.isBomb && beat != null && beat.size < 5 => SoundEffect.bomb,
      _ => SoundEffect.cardsDown,
    });
    if (state.isOver) _net += state.result.scores[0];
  }

  @override
  JobRequest botRequest(int seat, int seed) => JobRequest(
    const BigTwoBotJob(),
    BigTwoBotInput(record: record.jobJson(), seat: seat, seed: seed, level: levelOf(seat)),
    JobKind.bot,
  );

  @override
  String toBotMove(Object? output) => (output! as BigTwoBotOutput).move;

  @override
  String fallbackBotMove(int seat) => bigTwoMoveText(
    seat,
    BigTwoBot(BotLevel.easy, seed: mixSeed(record.seed, record.moves.length, seat)).chooseMove(state.viewFor(seat)),
  );

  @override
  JobRequest coachRequest(GameRecord position, int seat, {String? include, bool deep = false, required int seed}) =>
      JobRequest(
        const BigTwoCoachJob(),
        BigTwoCoachInput(record: position.jobJson(), seat: seat, seed: seed, deep: deep, include: include),
        JobKind.coach,
      );

  @override
  CoachAnswer toAnswer(Object? output) => bigTwoAnswer(output! as BigTwoReport, scale);

  /// Graded in points against the coach's pick, past the coach's noise
  /// (see bigTwoScale).
  @override
  GradeScale get scale => bigTwoScale(rules);

  /// Only a real choice is graded: when the only legal move is Pass (nothing
  /// beats the play, Pass locks you out, or only the top 2 is left to lead),
  /// there is nothing to judge, and a free Best would lift the score. No
  /// coach job runs for it either.
  @override
  bool coachWanted(int seat) => state.legalMoves().length > 1;

  /// A pass the player can't avoid (nothing in hand beats the table) plays
  /// itself after the bots' pause, as in Fight the Landlord (要不起), and
  /// the headline says so meanwhile. A card play never does: even a last
  /// card that is the only legal move waits for the player's click.
  @override
  String? forcedMove(int seat) {
    if (_state == null || isOver || state.toMove != seat) return null;
    final legal = state.legalMoves();
    return legal.length == 1 && legal.single.isPass ? bigTwoMoveText(seat, Play.pass) : null;
  }

  /// The player can only pass now: the headline says so while it plays itself.
  bool get cantBeat => myTurn && forcedMove(0) != null;

  /// A bot's level (seat 1 and up).
  KitLevel levelOf(int seat) => setup.levels[seat - 1];

  // ---- what the screen shows ----

  /// The points of this session's finished deals for the player (reset by
  /// New game).
  int get net => _net;

  /// The coach's report for this turn (its moves, the hand plan), once it
  /// has come.
  BigTwoReport? get report => coach?.detail as BigTwoReport?;

  /// How the hand is laid out (kept in the record, see arrangementOf):
  /// sorted by rank or suit, or in the player's own order.
  HandArrangement<Card> get arrangement => started ? arrangementOf(record.extra) : const HandArrangement.sorted();
  set arrangement(HandArrangement<Card> arrangement) {
    if (arrangement == this.arrangement) return;
    for (final MapEntry(:key, :value) in arrangementExtra(arrangement).entries) {
      setExtra(key, value);
    }
  }

  /// What the hand's Sort button shows: Rank, Suit, or (once the player
  /// has moved a card) Sort.
  HandOrder get sortOrder => arrangement.order;

  /// The Sort button (or S): Rank and Suit switch; from the player's own
  /// order, back to the sort last chosen. Nothing once the deal is over,
  /// as the button is greyed out then.
  void sortTap() {
    if (started && !isOver) arrangement = arrangement.next;
  }

  /// The player dragged the card at [from] in [hand] to [to]: the hand is
  /// in their own order from now on (until they sort it or the deal ends).
  /// The cards dealt go with it, so the review shows the cards played
  /// before the drag where they lay (see [HandArrangement.moved]).
  void reorder(int from, int to) {
    if (!started || isOver) return;
    final a = arrangement;
    arrangement = a.moved(
      hand,
      from,
      to,
      whole: a.own != null ? null : sortedHand(rules, BigTwoRecord.replay(record.upTo(0)).handOf(0), a.sort),
    );
  }

  /// The Card counter toggle (kept in the record); it shows only in
  /// Training, with the coach.
  bool get counterOn => _record?.extra['counter'] == true;
  set counterOn(bool on) => setExtra('counter', on);

  GameRecord? get _record => started ? record : null;

  /// The player's cards as they lie in the hand: sorted, or in the
  /// player's own order (see [arrangement]).
  List<Card> get hand => arrangedHand(rules, state.handOf(0), arrangement);

  /// The cards the player has picked.
  Set<Card> get selected => Set.unmodifiable(_selected);

  /// A card tapped in the hand: picked or unpicked. A Pass lit from the
  /// coach list goes out: the player is picking cards now.
  void toggle(Card card) {
    if (!_selected.remove(card)) _selected.add(card);
    choose(null);
    notifyListeners();
  }

  /// A coach row was tapped once: a play's cards are picked (they pop up);
  /// Pass clears the pick and lights the Pass button (TurnController.choose).
  /// Nothing is played: a double tap, Enter or the button does that.
  void selectMove(String move) {
    final cards = bigTwoMoveCards(move);
    _selected
      ..clear()
      ..addAll(cards);
    choose(cards.isEmpty ? move : null);
    notifyListeners();
  }

  void clearSelection() {
    _selected.clear();
    choose(null);
    notifyListeners();
  }

  /// Pass as this player's move text ("0:pass").
  static final passMove = bigTwoMoveText(0, Play.pass);

  /// Pass is lit from the coach list: Enter, a double tap or the button
  /// plays it.
  bool get passChosen => chosen == passMove;

  /// The move under the mouse in the coach list (the hand lights its
  /// cards), or null.
  String? get preview => _preview;
  set preview(String? move) {
    if (move == _preview) return;
    _preview = move;
    notifyListeners();
  }

  /// Whether the player may act now.
  bool get myTurn => started && seatToAct == 0;

  /// The move the picked cards make, when it is legal now; else null.
  String? get selectedMove {
    if (!myTurn || _selected.isEmpty) return null;
    final play = rules.classify(_selected.toList());
    if (play == null || !state.legalMoves().contains(play)) return null;
    return bigTwoMoveText(0, play);
  }

  bool get canPlay => selectedMove != null;
  bool get canPass => myTurn && state.legalMoves().contains(Play.pass);
  /// Clear puts out a lit Pass too (as Esc does, and as in Fight the Landlord).
  bool get canClear => _selected.isNotEmpty || chosen != null;

  /// Plays the picked cards (Play).
  void playSelected() {
    final move = selectedMove;
    if (move != null) humanMove(move);
  }

  /// Passes (Pass).
  void passTurn() {
    if (canPass) humanMove(bigTwoMoveText(0, Play.pass));
  }

  /// The cards of the player's hand everyone at the table has seen (the
  /// starting card until it is played, a three-player deal's face-up card):
  /// the fan marks them with the eye. Empty before the deal and once it is
  /// over.
  Set<Card> get visibleInHand => started ? {...state.visibleIn(0)} : const {};

  /// The player's card counter, from what seat 0 has seen.
  CardCounter get counter => CardCounter.of(state.viewFor(0));
}

/// The choices that aren't card plays, legal for [seat] in [state]: Pass,
/// unless the seat leads (or isn't on turn). The coach list always shows
/// them, in the game and in the review.
List<String> bigTwoListedMoves(BigTwoState state, int seat) =>
    !state.isOver && state.toMove == seat && state.legalMoves().contains(Play.pass)
    ? [bigTwoMoveText(seat, Play.pass)]
    : const [];
