import 'dart:async';
import 'dart:math';

import '../../../games/doudizhu/app/doudizhu_analysis.dart';
import '../../../games/doudizhu/app/doudizhu_grading.dart';
import '../../../games/doudizhu/app/doudizhu_jobs.dart';
import '../../../games/doudizhu/app/doudizhu_range.dart';
import '../../../games/doudizhu/app/doudizhu_record.dart';
import '../../../games/doudizhu/doudizhu.dart';
import '../../../kit/coach_answer.dart';
import '../../../kit/game_keys.dart';
import '../../../kit/game_record.dart';
import '../../../kit/grading.dart';
import '../../../kit/jobs/jobs_core.dart';
import '../../../kit/match.dart';
import '../../../kit/seats.dart';
import '../../kit/card_flights.dart';
import '../../kit/cards.dart';
import '../../kit/game_sounds.dart';
import '../../kit/table_pile.dart';
import '../../kit/turn_controller.dart';
import 'doudizhu_cards.dart';
import 'doudizhu_opening.dart';
import 'doudizhu_table.dart';

/// The targets a match can be played to (points won), smallest first.
///
/// Fight the Landlord's rules score each deal and stop there: Pagat sets no
/// target, and other rule books end the game "whenever players wish", the
/// most won being the winner (gamerules.com). Chinese tournaments (JJ's
/// 定局积分 and 打立出局) play a fixed number of deals, or until a score
/// runs out. So a match here is played to a total of points won: the first
/// to reach it ends the match, and the highest total wins. Deals move few
/// points (a landlord wins or loses 6 in a typical deal, see
/// tool/games/doudizhu_match_length.dart), and every point won is lost by
/// someone else, so the targets are small: to 30, a match of evenly matched
/// players lasts about 14 deals (most between 5 and 36).
const landlordTargets = [20, 30, 50, 100];

/// The match a new setup offers: to 30 points.
const landlordStandardMatch = MatchTarget(points: 30);

/// The players at the table: always three (the engine plays the 3-player
/// game), so the target never needs scaling.
const landlordPlayers = 3;

/// The choices of [seat]'s turn on [game] that aren't plays, as record
/// moves: Pass when following, and in the auction No bid and each bid (or
/// Call / No call, Rob / No rob). The coach list always shows them
/// (TurnController.listedMoves), in the game and in the review. Empty when
/// it isn't [seat]'s turn.
List<String> ddzListedMoves(DdzGame game, int seat) {
  final open = game.phase == DdzPhase.bidding || game.phase == DdzPhase.playing;
  if (!open || game.toAct != seat) return const [];
  return [
    for (final m in game.legalMoves())
      if (m is! DdzPlay) ddzMoveText(seat, m),
  ];
}

/// What the setup chose: the rules, the two bots' levels, Training or Free
/// Play, the match's target, and the toggles to start with (the last
/// game's).
class LandlordChoice {
  const LandlordChoice({
    this.rules = DdzRules.standard,
    this.levels = const [KitLevel.medium, KitLevel.medium],
    this.training = true,
    this.match = landlordStandardMatch,
    this.extra = const {},
  });

  final DdzRules rules;

  /// The levels of the bots at seats 1 and 2.
  final List<KitLevel> levels;
  final bool training;

  /// The match's target (no points: no match, the deals just go on).
  final MatchTarget match;

  /// Toggles carried over from the last game ('coach', 'counter',
  /// 'showCards', and 'sort': the hand's Rank or Suit).
  final Map<String, Object?> extra;

  /// Where a deal's record keeps the setup's [match] (the kit keeps the
  /// match itself, its totals, under MatchScore.extraKey).
  static const playToKey = 'playTo';

  /// The choice a saved game was played with (setup starts from it).
  factory LandlordChoice.of(GameRecord record) => LandlordChoice(
    rules: ddzRulesOf(record),
    levels: [for (final seat in record.seats.skip(1)) seat.level ?? KitLevel.medium],
    training: record.extra['mode'] != 'free',
    match: MatchTarget.fromJson(record.extra[playToKey], fallback: landlordStandardMatch),
    extra: {
      for (final key in const ['coach', 'counter', TurnController.showCardsKey])
        if (record.extra[key] case final bool value) key: value,
      // The sort the player last chose; their own order belonged to that
      // deal's cards.
      if (record.extra['sort'] case final String sort) 'sort': sort,
    },
  );
}

/// Runs a game of Fight the Landlord: the player at seat 0 (the bottom),
/// bots at seats 1 (to the right, next to play) and 2 (to the left). One
/// deal is one record; Next deal keeps the seats, rules and toggles.
///
/// It also holds the player's card selection, so the panel, the hand and
/// the coach's "select" share it.
///
/// Every deal opens with who bids first ([dealing], doudizhu_opening.dart):
/// the cards go round the table and the face-up card flies to its holder,
/// at the Animations setting's speed. It is an animation, not work: while
/// it plays nobody is to act ([seatToAct] is null, the buttons greyed out),
/// and when it ends the auction opens by itself (as Big Two's opening).
class LandlordController extends TurnController {
  LandlordController({
    required super.jobs,
    required super.lastGames,
    this.choice = const LandlordChoice(),
    super.speed,
    super.random,
  }) : super(gameKey: GameKeys.doudizhu, training: choice.training);

  final LandlordChoice choice;

  /// The rules every deal of this session is played under. Whatever reads
  /// a move back (the coach's rows, its pick, the grade card) reads it
  /// under these: a play legal only under a variant, such as both jokers
  /// as kickers, is not a valid play under the standard rules.
  DdzRules get rules => choice.rules;

  DdzGame? _game;

  /// The deal as it stands.
  DdzGame get game => _game ?? (throw StateError('No deal yet: call newGame'));

  /// The points of the deals before this one (in memory only).
  int _netBefore = 0;
  var _deals = 0;

  /// The step that opens the deal now; null once it is over (at Instant
  /// there is none: the table shows its result at once).
  LandlordDealing? get dealing => _clock?.now;
  LandlordDealClock? _clock;

  /// The step that opens the deal is playing: nobody is to act until it
  /// ends (then the auction opens by itself). Never at Instant.
  bool get openingPlaying => _clock != null;

  /// The cards the player has picked (ids).
  Set<int> get selected => _selected;
  Set<int> _selected = const {};

  /// The coach row under the mouse (a move key), previewed on the table.
  String? get preview => _preview;
  String? _preview;

  /// The human's seat.
  static const you = 0;

  /// The player's seat as the screen names it, in the app's language
  /// ("Player", "Jugador", 玩家): the screen sets it. The record keeps
  /// "Player"; the kit's match views (the status line, the scores, who won
  /// the match) read names through [seatName].
  String playerName = 'Player';

  @override
  String seatName(int seat) => seat == you ? playerName : super.seatName(seat);

  // ---- the game ----

  @override
  int? get seatToAct {
    final g = _game;
    // Nobody acts while the deal opens.
    if (g == null || openingPlaying) return null;
    return g.phase == DdzPhase.bidding || g.phase == DdzPhase.playing ? g.toAct : null;
  }

  @override
  bool isHuman(int seat) => seat == you;

  @override
  bool get isOver => _game != null && (game.phase == DdzPhase.finished || game.phase == DdzPhase.thrownIn);

  /// Everyone passed in the auction: nobody plays this deal.
  bool get thrownIn => _game?.phase == DdzPhase.thrownIn;

  @override
  List<int> get winners {
    final result = _game?.result;
    if (result == null) return const [];
    return [
      for (var s = 0; s < 3; s++)
        if (result.wonBy(s)) s,
    ];
  }

  @override
  Map<String, Object?> get result {
    final r = _game?.result;
    return {
      'winners': winners,
      if (thrownIn) 'thrownIn': true,
      if (r != null) ...{
        'landlord': r.landlord,
        'stake': r.stake,
        'multiplier': r.multiplier,
        'points': r.points,
        if (r.spring) 'spring': true,
        if (r.antiSpring) 'antiSpring': true,
      },
    };
  }

  @override
  bool get playsRounds => true;

  /// The cards of the player's hand everyone at the table has seen (the
  /// face-up card, the shown kitty), marked with the eye on the hand; none
  /// before the deal or once it is over (every hand is shown then).
  Set<int> get visibleInHand => _game == null || isOver ? const {} : {...(dealing?.game ?? game).visibleIn(you)};

  /// The player's points over the deals of this session.
  int get sessionNet => _netBefore + (_game?.result?.points[you] ?? 0);

  /// Deals played this session, this one included.
  int get deals => _deals;

  /// The stake times the multiplier as it stands ("×4"), or null before
  /// anyone bids.
  int? get totalMultiplier {
    final g = _game;
    if (g == null || g.stake == 0) return null;
    return g.stake * g.multiplier;
  }

  @override
  GameRecord deal({GameRecord? previous}) {
    final seed = nextGameSeed();
    if (previous == null) _netBefore = 0;
    if (previous?.result?['points'] case [final int mine, ...]) _netBefore += mine;
    // The hand starts sorted again, by the sort last chosen: the kit would
    // carry the last deal's own order over too.
    final arranged = (started ? arrangement : ddzArrangementOf(choice.extra)).dealt;
    final record = ddzNewRecord(
      seed: seed,
      rules: choice.rules,
      seats: previous?.seats ?? _seats(seed),
      // No first bidder: the card dealt face up decides (Pagat).
      // The setup's toggles only start the session; later deals keep
      // whatever the player switched since (the kit carries extra over).
      extra: {
        if (!started) ...choice.extra,
        'mode': training ? 'training' : 'free',
        LandlordChoice.playToKey: choice.match.toJson(),
        ...ddzArrangementExtra(arranged),
      },
    );
    _clock?.cancel();
    _clock = null;
    _game = ddzReplay(record);
    _deals = previous == null ? 1 : _deals + 1;
    _selected = const {};
    _preview = null;
    _startOpening();
    playSound(SoundEffect.deal);
    return record;
  }

  /// The deal's first step: who bids first, shown as the cards go round
  /// (none at Instant). Nobody is to act while it plays ([openingPlaying]);
  /// when it ends the kit is told to go on, and the auction opens.
  void _startOpening() {
    final start = game;
    final clock = LandlordDealClock(
      start: start,
      order: DdzDealOrder.of(start),
      factor: speed.factor,
      fanSeat: you,
      onChange: notifyListeners,
      onFaceUp: (id) => _flyFaceUp(start.firstBidder, id),
    );
    unawaited(
      clock.run().then((_) {
        // A later deal, or the screen closed, cancelled this one.
        if (!identical(_clock, clock)) return;
        _clock = null;
        resume();
      }),
    );
    // At Instant the step is over as soon as it starts: nothing holds.
    _clock = clock.running ? clock : null;
  }

  /// The face-up card leaves the stack face up for its holder's seat: the
  /// player's hand, or the end of a bot's cards.
  void _flyFaceUp(int seat, int id) {
    unawaited(
      flights.fly([
        CardFlight(
          from: LandlordTable.deckTag,
          to: seat == you ? HandFan.flightTag(ddzFace(id)) : LandlordTable.faceUpTag(seat),
          face: ddzFace(id),
        ),
      ]),
    );
  }

  @override
  void dispose() {
    _clock?.cancel();
    _clock = null;
    super.dispose();
  }

  List<SeatSpec> _seats(int seed) {
    final first = seed % kitBotNames.length;
    final second = (first + 1 + (seed >> 3) % (kitBotNames.length - 1)) % kitBotNames.length;
    return [
      // The screens name this seat in the player's language (S.you).
      const SeatSpec(human: true, name: 'Player'),
      SeatSpec(human: false, level: choice.levels[0], name: kitBotNames[first]),
      SeatSpec(human: false, level: choice.levels[1], name: kitBotNames[second]),
    ];
  }

  @override
  void applyMove(int seat, String move) {
    final g = game;
    if (seat != g.toAct) throw StateError('Not seat $seat\'s turn');
    final (seat: _, move: m, :cardIds) = ddzParseMove(move, g.rules);
    final lordBefore = g.landlord;
    g.act(m, cardIds: cardIds);
    // The screen still shows the turn before (it redraws on the next frame),
    // so the flights start from where the cards are drawn now.
    _fly(seat, m, lordBefore);
    if (seat == you) _selected = const {};
    _preview = null;
    playSound(switch (m) {
      DdzPlay(:final play) when play.isBombLike => SoundEffect.bomb,
      DdzPlay() => SoundEffect.cardsDown,
      DdzPass() || DdzBid(isPass: true) || DdzCall(yes: false) || DdzRob(yes: false) => SoundEffect.pass,
      _ => SoundEffect.chips,
    });
  }

  /// Flies a play's cards to the table's pile, from the hand or the bot's
  /// seat, each to its place in the play (as the pile draws it, reading
  /// order); and when the auction makes a landlord, the kitty to the
  /// landlord: into the player's hand, or onto a bot's badge (face down
  /// unless the rules show the kitty). The Animations setting sets the
  /// speed; Instant flies nothing.
  void _fly(int seat, DdzMove move, int? lordBefore) {
    final g = game;
    if (move is DdzPlay) {
      final index = g.history.length - 1;
      final ids = ddzPlayOrder(g.history.last.cardIds, move.play);
      unawaited(
        flights.fly([
          for (final (k, id) in ids.indexed)
            CardFlight(
              from: seat == you ? HandFan.flightTag(ddzFace(id)) : CardFlights.seatTag(seat),
              to: TablePile.flightTag(index, k),
              face: ddzFace(id),
            ),
        ]),
      );
    }
    final lord = g.landlord;
    if (lordBefore == null && lord != null) {
      final up = g.rules.kittyShown || lord == you;
      unawaited(
        flights.fly([
          for (final (k, id) in ddzSorted(g.kitty).indexed)
            CardFlight(
              from: LandlordTable.kittyTag(k),
              to: lord == you ? HandFan.flightTag(ddzFace(id)) : LandlordTable.lordCardTag(lord, k),
              face: up ? ddzFace(id) : null,
              faceUp: up,
            ),
        ]),
      );
    }
  }

  /// A pass the player can't avoid (nothing in hand beats the table: 要不起)
  /// plays itself after the bots' pause, as in Big Two. A card play never
  /// does: the last card of a lead, though it is the only legal move, waits
  /// for the player's click (see [coachWanted]).
  @override
  String? forcedMove(int seat) {
    final g = _game;
    if (g == null || g.phase != DdzPhase.playing || g.toAct != seat) return null;
    final legal = g.legalMoves();
    return legal.length == 1 && legal.single is DdzPass ? ddzMoveTextFor(g, legal.single) : null;
  }

  /// Only a real choice gets the coach and a grade: a turn with one legal
  /// move (the last card of a lead) has nothing to judge, and a free Best
  /// would lift the score (as in Big Two).
  @override
  bool coachWanted(int seat) {
    final g = _game;
    return g == null || g.phase != DdzPhase.playing || g.legalMoves().length > 1;
  }

  /// The player can only pass now: the headline says so (要不起) while the
  /// pass plays itself.
  bool get cantBeat => _game != null && forcedMove(you) != null;

  @override
  JobRequest botRequest(int seat, int seed) => JobRequest(
    const DdzBotJob(),
    DdzBotInput(record: record.jobJson(), seat: seat, level: record.seats[seat].level ?? KitLevel.medium, seed: seed),
    JobKind.bot,
  );

  @override
  String fallbackBotMove(int seat) {
    final view = game.viewFor(seat);
    final move = DdzBot(
      DdzLevel.easy,
      random: Random(mixSeed(record.seed, record.moves.length, seat)),
    ).chooseMove(view);
    return ddzMoveTextFor(game, move);
  }

  @override
  JobRequest coachRequest(GameRecord position, int seat, {String? include, bool deep = false, required int seed}) =>
      JobRequest(
        const DdzCoachJob(),
        DdzCoachInput(record: position.jobJson(), seat: seat, include: include, deep: deep, seed: seed),
        JobKind.coach,
      );

  @override
  CoachAnswer toAnswer(Object? output) => ddzAnswer(output! as DdzAdvice);

  /// Play is graded on win chance. The auction is graded on points, and
  /// its marks say so themselves (MoveMark.unit), so the panel shows each
  /// loss in its own unit.
  @override
  GradeScale get scale => ddzPlayScale;

  /// Graded from the coach's pick, in the answer's own unit (see ddzMark).
  @override
  MoveMark? grade(CoachAnswer answer, String played) => ddzMark(answer, played);

  /// Every choice that isn't a play, while it is legal: Pass when
  /// following, and in the auction No bid and each bid (or Call / No call,
  /// Rob / No rob). The coach list always shows them, with their values.
  @override
  List<String> listedMoves(int seat) => _game == null || seatToAct != seat ? const [] : ddzListedMoves(game, seat);

  // ---- the match ----

  /// A match to the setup's target (always three players), the highest
  /// total winning; none under No limit.
  @override
  MatchScore? startMatch() => switch (choice.match.forPlayers(landlordPlayers, standardPlayers: landlordPlayers)) {
    final target? => MatchScore(target: target, winner: MatchWinner.highest, seats: landlordPlayers),
    null => null,
  };

  /// What each seat won or lost in the deal: the bid times the doublings,
  /// the landlord's twice a peasant's. A deal thrown in (everyone passed)
  /// is dealt again and isn't a deal of the match.
  @override
  List<int>? dealPoints() => _game?.result?.points;

  // ---- ranges ----

  /// An opponent's range, worked out from the player's view of [position]
  /// only (DdzRangeJob), never from the cards the Training option shows.
  @override
  JobRequest? rangeRequest(GameRecord position, int seat, {required int seed}) => seat == you
      ? null
      : JobRequest(
          const DdzRangeJob(),
          DdzRangeInput(record: position.jobJson(), viewer: you, seat: seat, seed: seed),
          JobKind.range,
        );

  // ---- the player's selection ----

  /// Whether the player may pick cards now (their turn to play cards).
  bool get canPlay => started && seatToAct == you && game.phase == DdzPhase.playing;

  /// The play the selected cards make that may be played now, or null.
  Play? get selectedPlay {
    if (!canPlay || _selected.isEmpty) return null;
    final play = readPlay([for (final id in _selected) rankOfId(id)], game.current, game.rules);
    return play != null && game.isLegal(DdzPlay(play)) ? play : null;
  }

  /// The record move of playing the selection, or null when it isn't legal.
  String? get selectedMove {
    final play = selectedPlay;
    if (play == null) return null;
    return ddzMoveText(you, DdzPlay(play), [..._selected]..sort());
  }

  /// How the player's hand is laid out: by rank or by suit, or in their
  /// own order once they drag a card. Kept in the record's extra ('sort',
  /// 'order'), so it is saved with the deal and its sort carried into the
  /// next.
  HandArrangement<int> get arrangement =>
      started ? ddzArrangementOf(record.extra) : const HandArrangement<int>.sorted();

  /// The player's cards as the hand shows them: in the sort chosen, or in
  /// their own order, where the cards they play drop out and the kitty,
  /// should they become the landlord, goes at the end. While the deal
  /// opens, the cards dealt so far.
  List<int> get hand {
    final a = arrangement;
    return a.arrange(ddzHandSorted((dealing?.game ?? game).hands[you], a.sort));
  }

  /// The player dragged the card at [from] in [hand] to [to]: the hand is
  /// now in their own order. The cards dealt go with it, so the review
  /// shows the cards played before the drag where they lay (see
  /// [HandArrangement.moved]).
  void reorder(int from, int to) {
    if (!started || dealing != null) return;
    final a = arrangement;
    _arrange(a.moved(hand, from, to,
        whole: a.own != null ? null : ddzHandSorted(ddzReplay(record, upTo: 0).hands[you], a.sort)));
  }

  /// The hand's Sort button: Rank and Suit take turns; from the player's
  /// own order, back to the sort last chosen.
  void sortTap() => _arrange(arrangement.next);

  void _arrange(HandArrangement<int> next) {
    if (!started || dealing != null || next == arrangement) return;
    ddzArrangementExtra(next).forEach(setExtra);
  }

  /// Picks or unpicks a card by hand: a choice lit from the coach list
  /// (Pass, a bid) goes out; the cards now say what will be played.
  void toggle(int id) {
    if (dealing != null || !game.hands[you].contains(id)) return;
    choose(null);
    _selected = _selected.contains(id) ? ({..._selected}..remove(id)) : {..._selected, id};
    notifyListeners();
  }

  /// Clear (and Esc): the picked cards go down, and a choice lit from the
  /// coach list goes out.
  void clearSelection() {
    choose(null);
    if (_selected.isEmpty) return;
    _selected = const {};
    notifyListeners();
  }

  /// A single tap on a coach row: selects its move, never plays it. A
  /// play's cards pop up in the hand; a choice (Pass, No bid, a bid) lights
  /// its button up (TurnController.chosen) and drops the picked cards.
  void selectMove(String key) {
    if (!started) return;
    final DdzMove move;
    try {
      move = ddzParseMove(key, game.rules).move;
    } on FormatException {
      return;
    }
    if (move is DdzPlay) {
      if (!canPlay) return;
      try {
        _selected = ddzCardsFor(game.hands[you], move.play).toSet();
      } on StateError {
        return; // Not in this hand any more.
      }
      choose(null);
    } else {
      _selected = const {};
      choose(key);
    }
    notifyListeners();
  }

  /// A double tap on a coach row: plays its move. A play goes with the
  /// cards a single tap picks, so the record keeps them as for a play made
  /// from the hand. False, and nothing changes, when it can't be played.
  bool playFromRow(String key) {
    if (!playerToMove) return false;
    final DdzMove move;
    try {
      move = ddzParseMove(key, game.rules).move;
    } on FormatException {
      return false;
    }
    if (move is! DdzPlay) return playFromCoach(key);
    try {
      return playFromCoach(ddzMoveText(you, move, ddzCardsFor(game.hands[you], move.play)));
    } on StateError {
      return false;
    }
  }

  /// The coach row of the picked cards: the move key they make (no card
  /// ids, as the rows have them), or null.
  String? get selectedKey => switch (selectedMove) {
    final move? => ddzMoveKey(move),
    null => null,
  };

  /// The mouse is over a coach line (null: it left).
  set preview(String? key) {
    if (key == _preview) return;
    _preview = key;
    notifyListeners();
  }

  /// The cards of the previewed play in the player's hand (empty: none).
  Set<int> get previewCards {
    final key = _preview;
    if (key == null || _game == null) return const {};
    final move = ddzParseMove(key, game.rules).move;
    if (move is! DdzPlay) return const {};
    try {
      return ddzCardsFor(game.hands[you], move.play).toSet();
    } on StateError {
      return const {}; // The move is gone from this hand (it was played).
    }
  }

  /// Plays the selection, if it is legal.
  void playSelection() {
    final move = selectedMove;
    if (move != null) humanMove(move);
  }

  /// The coach's advice for this turn, as the engine's numbers.
  DdzAdvice? get advice => coach?.detail as DdzAdvice?;
}
