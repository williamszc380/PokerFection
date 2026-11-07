import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../app/drills.dart';
import '../app/sounds.dart';
import '../bots/bot.dart';
import '../engine/actions.dart';
import '../engine/cards.dart';
import '../engine/events.dart';
import '../engine/poker_hand.dart';
import '../engine/rules.dart';
import '../game/hand_follower.dart';
import '../game/hand_snapshot.dart';
import '../game/pre_action.dart';
import '../game/table_session.dart';
import '../gto/action_menu.dart';
import '../gto/gto_solutions.dart';
import '../gto/postflop/postflop_tracker.dart' show PostflopTracker;
import '../gto/preflop/preflop_advisor.dart' show PreflopAdvisor;
import '../gto/spot_strategy.dart';
import '../online/mirror.dart';
import '../online/online_client.dart';
import '../online/protocol.dart';
import '../online/seat_map.dart';
import '../online/timing.dart';
import 'table_view_state.dart';

part 'drill_controller.dart';
part 'online_table_controller.dart';

enum PlaybackSpeed {
  normal('Normal', 1.0),
  fast('Fast', 0.35),
  instant('Instant', 0);

  const PlaybackSpeed(this.label, this.factor);
  final String label;

  /// Multiplies every animation and pause. 0 skips them.
  final double factor;
}

/// One of the user's decisions: its hand and id (on the device, how many
/// actions came before it; online, the server's turn), and the players and
/// bot styles of the table then (a drill saved from it needs them).
typedef _Decision = ({int hand, int turnId, List<PlayerInfo> players, List<BotStyle?> styles});

/// A move the user made before GTO's answer for it was worked out (the
/// table doesn't wait for it): scored once the answer comes. [choice] is
/// the menu's choice played (drawn from [mix], if [drew]); [action] a
/// raise of another amount, graded as [choice]. [players] and [styles] are
/// the decision's (see [_Decision]).
typedef _Unscored = ({
  int hand,
  int turnId,
  List<PlayerInfo> players,
  List<BotStyle?> styles,
  List<double> mix,
  int choice,
  bool drew,
  PlayerAction? action,
  bool oneAction,
});

/// A Mistake or a Blunder graded after its move, in the hand on screen:
/// listed when the hand is over.
typedef LateGrade = ({int hand, Street street, DecisionGrade grade});

/// Runs a [TableSession] for the table screen.
///
/// The engine decides everything instantly; this controller replays its
/// events one at a time, updating [view] and launching [flying] chips and
/// cards, so the user can follow what happened.
///
/// The table never waits for a solve. Each hand is dealt at once, and a
/// [HandFollower] follows it behind the table for GTO's answers: it solves
/// the hand's whole game, the user's subgames and the streets, one after
/// the other, in the order the hand reached them. The user's choices show
/// at once; GTO's answer joins them when it is ready ([answerPending] until
/// then). A move made before it plays at once, and is graded when the
/// answer comes, against that same decision (a Mistake or a Blunder then
/// shows without holding the table, and is listed when the hand is over:
/// [lateMistakes]). The bots wait a moment for the solves they play from
/// ([botBudget]), then play the best they have, which keeps the hand on the
/// solved lines. The next hand's whole game is solved once this one can't
/// ask for more. Each Mistake or Blunder is saved to the [drills], to play
/// again later.
class TableController extends ChangeNotifier {
  TableController(
    TableConfig config, {
    this._speed = PlaybackSpeed.normal,
    Random? random,
    GtoSolutions? solutions,
    this.drills,
  })  : session = TableSession(
          config,
          random: random,
          solvePostflop: (solutions ?? GtoSolutions.shared).solvePostflop,
          solveSubgame: (solutions ?? GtoSolutions.shared).solveSubgame,
        ),
        _random = random ?? Random(),
        _solutions = solutions ?? GtoSolutions.shared {
    view = TableViewState([
      for (var i = 0; i < config.playerCount; i++)
        SeatView(info: session.players[i], stack: session.stacks[i]),
    ]);
  }

  final TableSession session;
  final Random _random;
  final GtoSolutions _solutions;

  /// Where the user's mistakes are saved (none: they aren't).
  final Drills? drills;
  /// What the table shows. Online, a new one when the players change
  /// between hands.
  late TableViewState view;
  final List<FlyingItem> flying = [];

  /// What the user may do, while waiting for their decision.
  LegalActions? heroOptions;

  /// Guess the GTO mode: the answer for the user's current decision (or,
  /// with [heroScoreLate], the one just graded).
  SpotStrategy? heroSpot;

  /// The user's choices at their current decision (the same list every time;
  /// see [actionMenu]): GTO's answer lists them too, when there is one.
  List<SpotAction>? heroMenu;

  /// The user's mix (frequencies adding up to 1) and its score, once submitted.
  List<double>? heroMix;
  DecisionScore? heroScore;

  /// The score showing is of a move made before its answer came: the hand
  /// went on meanwhile, and OK just puts the score away.
  bool heroScoreLate = false;

  /// What the "why" of the score showing is worked out from, read at its
  /// decision (see whyInputs).
  WhyInputs? heroWhy;

  /// Why GTO has no answer for the user's current decision, once that is
  /// known (null: there is one, it is still on its way, or no reason is
  /// known).
  NoAnswer? answerNone;

  bool handOver = false;

  /// How long a bot that plays from a solve waits for it after its think
  /// pause (see Playback.botBudget). Null: as long as it takes (tests that
  /// check GTO's exact moves).
  @visibleForTesting
  Duration? botBudget = Playback.botBudget;

  /// Plays the bots' moves instead of the bots (null: the bot decides), so
  /// tests can play the same hand however fast the answers come. Played at
  /// once, like a drill's recorded moves.
  @visibleForTesting
  PlayerAction? Function(PokerHand hand, int seat)? scriptedBots;

  PlaybackSpeed _speed;
  bool _busy = false;
  bool _disposed = false;
  bool _heroFolded = false;

  /// The decision showing, and whether its answer has come (with or
  /// without a spot).
  _Decision? _decision;
  bool _answered = false;

  /// The followers of the hand on the table and, while it still has
  /// answers to give, of the hand before (see HandFollower).
  HandFollower? _follower, _previous;

  /// The next hand's claim on the solves started for it ahead of time.
  SolveOwner? _nextOwner;

  /// The claim on the user's first decision of the next hand if everyone
  /// folds to them, solved ahead of time: a guess, so it is its own and
  /// never made more urgent (the hand's own claim lifts it once the hand
  /// asks for it), and let go of once someone before the user does more
  /// than fold (see [_settleAhead]).
  SolveOwner? _aheadOwner;

  /// The user's moves made before their answers came, oldest first.
  final List<_Unscored> _unscored = [];
  final List<LateGrade> _lateMistakes = [];

  PlaybackSpeed get speed => _speed;
  set speed(PlaybackSpeed value) {
    _speed = value;
    _notify();
  }

  PokerHand? get hand => session.hand;
  /// The players on screen (online, the session may know the next hand's
  /// line-up already).
  int get playerCount => view.seats.length;
  bool get guessGto => session.guessGto;

  /// Advanced training (percentages) in the hand on screen.
  bool get advanced => session.advanced;

  /// Whether [seat] is the user's (online, nobody's in a hand the user
  /// watches, out of chips).
  bool isUserSeat(int seat) => seat == TableSession.heroSeat;

  /// The number of the hand on screen.
  int get _tableHand => session.handNumber;

  /// The user is choosing, in Guess the GTO mode, and GTO's answer is
  /// still on its way: the choices work (the move is graded when it
  /// comes), and Show GTO shows it once it is here.
  bool get answerPending => guessGto && heroOptions != null && heroSpot == null && !_answered && _decision != null;

  /// Show GTO was pressed before the answer came ([wanted]), or turned
  /// off again: while the user waits for the answer, the hand's solves come
  /// first (they all lead to it). The wait, and so the claim, ends when the
  /// answer comes or turns out to be none, when Show GTO is turned off, when
  /// the decision is over (the panel lights Show GTO for one decision only:
  /// at the next one it is pressed again if wanted), or at hand over.
  void wantAnswerShown([bool wanted = true]) {
    for (final claim in _shownClaims) {
      claim.end();
    }
    _shownClaims = [if (wanted) for (final owner in _answerOwners) owner.claim(SolvePriority.shown)];
  }

  /// The claims Show GTO holds while the user waits for the answer (see
  /// [wantAnswerShown]).
  List<SolveClaim> _shownClaims = const [];

  /// Whose solves the user's answer comes from: the hand on the table's.
  Iterable<SolveOwner> get _answerOwners => [?_follower?.owner];

  /// Moves in the hand on screen whose grades are still to come.
  bool get gradesPending => _unscored.any((played) => played.hand == _tableHand);

  /// The Mistakes and Blunders of the hand on screen graded after their
  /// moves, in the order they were graded.
  List<LateGrade> get lateMistakes => [for (final m in _lateMistakes) if (m.hand == _tableHand) m];

  /// The hands followed for their answers (the one on the table last).
  @visibleForTesting
  List<HandFollower> get followers => [?_previous, ?_follower];

  /// Completes once the followers have caught up with the table, and every
  /// answer asked for so far has been given.
  @visibleForTesting
  Future<void> caughtUp() async {
    while (true) {
      final tails = [for (final f in followers) f.tail];
      await Future.wait(tails);
      final now = [for (final f in followers) f.tail];
      if (now.length == tails.length && [for (var i = 0; i < now.length; i++) identical(now[i], tails[i])].every((same) => same)) {
        return;
      }
    }
  }

  Future<void> startNextHand() async {
    if (_busy) return;
    _busy = true;
    handOver = false;
    _clearHeroDecision();
    _heroFolded = false;
    _lateMistakes.clear();
    // Two hands back: their answers won't come any more (see _follow).
    _unscored.removeWhere((played) => played.hand < session.handNumber);
    final hand = session.startHandWith(track: false);
    for (final (i, seat) in view.seats.indexed) {
      seat.style = session.styles[i];
    }
    final deal = hand.drainEvents();
    _follow(hand, deal);
    _settleAhead(hand);
    // Rarely, the blinds put everyone all-in: the hand is decided already.
    _maybePrecompute(hand);
    await _play(deal);
    await _runUntilHeroOrEnd();
    _busy = false;
    await _playPreAction();
  }

  /// Starts following [hand] (dealt with [deal], its first events) for
  /// its answers. The hand before is kept while it still has answers to
  /// give (only what those read), and the one before that let go, its
  /// solves not started yet dropped.
  void _follow(PokerHand hand, List<GameEvent> deal) {
    if (_previous case final old?) _abandon(old);
    _previous = null;
    if (_follower case final last?) {
      // Nobody plays in it any more (a drill's spot ends before its hand
      // does): what it still solves only grades.
      last.owner.finish();
      if (last.pendingAnswers > 0) {
        _previous = last..trimForAnswers();
      } else {
        _abandon(last);
      }
    }
    _follower = null;
    final next = _nextOwner;
    _nextOwner = null;
    if (!session.needsSolver) {
      if (next != null) _solutions.drop(next);
      return;
    }
    final owner = next != null && next.hand == hand.handNumber ? next : SolveOwner(hand.handNumber);
    if (!identical(owner, next) && next != null) _solutions.drop(next);
    final f = _follower = HandFollower(table: hand, deal: deal, owner: owner);
    f.onIdle = () {
      // The hand before has given its last answer: nothing more to keep.
      if (identical(_previous, f)) {
        _previous = null;
        _abandon(f);
      }
    };
    final spec = session.specOf(hand);
    f.start(() async {
      final blueprint = _solutions.ready(spec) ?? await _solutions.solve(spec, owner: owner, priority: SolvePriority.bot);
      final trackers = session.trackersFor(
        f.hand,
        blueprint,
        // The user's subgames grade them; in Free Play they are only for
        // the GTO bots' replies.
        subgames: (s, ranges) => _solutions.solveSubgame(s, ranges,
            owner: owner, priority: guessGto ? SolvePriority.grade : SolvePriority.bot),
        streets: (s, ranges) => _solutions.solvePostflop(s, ranges,
            owner: owner, priority: session.hasGtoBotIn(f.hand) ? SolvePriority.bot : SolvePriority.grade),
        needed: session.streetNeeded,
      );
      if (identical(_follower, f) && !_disposed) {
        // The table's answers, ranges and GTO bots read them from now on.
        session.advisor = blueprint;
        session.useTrackers(trackers.preflop, trackers.postflop);
        _notify();
      }
      return trackers;
    });
  }

  /// Nothing more is worked out for [f]'s hand.
  void _abandon(HandFollower f) {
    f.abandoned = true;
    _solutions.drop(f.owner);
  }

  /// Whether anyone still needs solves in [hand]: a GTO bot is still in
  /// it, or the user in Guess the GTO mode.
  bool _needsMore(PokerHand hand) => !hand.isOver && session.needsSolver && session.streetNeeded(hand);

  /// Starts on the next hand's solves once this hand can't ask for more:
  /// when it is decided, or (with stacks reset every hand, so the next one
  /// is known already) once nobody needs anything more in it.
  void _maybePrecompute(PokerHand hand) {
    // Decided: nobody plays in it any more, so whatever made its solves
    // urgent is over, and what is left of them only grades (behind the
    // next hand's game).
    if (_follower case final f? when hand.isOver && f.owner.hand == hand.handNumber) f.owner.finish();
    if (hand.isOver || (session.config.resetStacksEachHand && !_needsMore(hand))) _precomputeNext();
  }

  /// The hand number whose next hand is already being solved.
  int _precomputedAfter = -1;

  /// Starts solving the next hand (its whole game, then the user's first
  /// decision if everyone folds to them) as soon as it is known: when this
  /// hand is decided, while its last cards and chips are still being shown.
  void _precomputeNext() {
    if (!session.needsSolver || _precomputedAfter == session.handNumber) return;
    _precomputedAfter = session.handNumber;
    final owner = _nextOwner = SolveOwner(session.handNumber + 1);
    // Failures show up when the hand needs the solve; nothing to do here.
    _quietly(_solutions.solve(session.upcomingSpec, owner: owner, priority: SolvePriority.nextHand));
    if (_aheadOwner case final old?) _solutions.drop(old);
    _aheadOwner = null;
    if (session.upcomingHeroSpec case final heroSpec?) {
      final ahead = _aheadOwner = SolveOwner(session.handNumber + 1);
      _quietly(_solutions.solve(heroSpec, owner: ahead, priority: SolvePriority.ahead));
    }
  }

  /// Lets go of the guess solved ahead of time for [hand] (the user's first
  /// decision if everyone folds to them) once it can't be used: it was for
  /// another hand, or someone before the user did more than fold. Until
  /// then it waits behind everything the hand really asks for.
  void _settleAhead(PokerHand hand) {
    final ahead = _aheadOwner;
    if (ahead == null) return;
    if (ahead.hand == hand.handNumber && !_aheadMissed(hand, isUserSeat)) return;
    _aheadOwner = null;
    _solutions.drop(ahead);
  }


  Future<void> heroAct(PlayerAction action) async {
    final hand = session.hand;
    if (_busy || heroOptions == null || hand == null) return;
    _busy = true;
    _clearHeroDecision();
    if (action.type == ActionType.fold) _heroFolded = true;
    hand.act(action);
    final batch = hand.drainEvents();
    // The street that begins starts solving while its cards are dealt on screen.
    _follower?.step(batch);
    _maybePrecompute(hand);
    await _play(batch);
    await _runUntilHeroOrEnd();
    _busy = false;
    await _playPreAction();
  }

  /// The action the user will play once they continue, and whether it was
  /// drawn from their mix (rather than ticked).
  int? heroPlay;
  bool heroDrew = false;

  /// What the user actually plays when it isn't [heroPlay]'s action: a raise
  /// of any amount (from the slider), graded as the nearest solved size.
  PlayerAction? heroAction;

  /// Scores the user's mix (how often to take each action, adding up to 1)
  /// and fixes the action to play: [choice], or one drawn from the mix.
  /// Before GTO's answer comes, the move plays at once and is scored when
  /// it does.
  void submitMix(List<double> mix, {int? choice, bool oneAction = false}) {
    final spot = heroSpot;
    final hand = session.hand;
    final options = heroOptions;
    if (hand == null || heroScore != null || options == null) return;
    if (spot == null) {
      if (answerPending) unawaited(_playBeforeAnswer(mix, choice: choice, oneAction: oneAction));
      return;
    }
    heroMix = List.unmodifiable(mix);
    heroScore = scoreDecision(spot, mix);
    heroDrew = choice == null;
    heroPlay = choice ?? _draw(spot, mix);
    heroWhy = whyInputs(hand, options, session.postflop);
    _recordOf(_tableHand)?.addDecision(DecisionRecord(
      street: hand.street,
      board: hand.board,
      spot: spot,
      mix: heroMix!,
      score: heroScore!,
      oneAction: oneAction,
      turnId: _recordTurnId,
    )..played = heroPlay);
    _scored(heroScore!);
    _notify();
  }

  /// The decision a decision's record is kept with: on the device, how
  /// many actions came before it (online, the server's turn).
  int? get _recordTurnId => _decision?.turnId;

  /// The record of hand [number], if the user played it.
  HandRecord? _recordOf(int number) {
    for (final record in session.history.reversed) {
      if (record.handNumber == number) return record;
    }
    return null;
  }

  /// Plays the user's move at once, before GTO's answer for it has come
  /// ([mix], and [choice] of the menu, or one drawn from the mix; [action]
  /// a raise of another amount): it is graded when the answer comes (see
  /// [_answerCame]).
  Future<void> _playBeforeAnswer(List<double> mix, {int? choice, required bool oneAction, PlayerAction? action}) async {
    final d = _decision, menu = heroMenu;
    if (d == null || menu == null) return;
    final play = choice ?? _drawFrom(menu, mix);
    _unscored.add((
      hand: d.hand,
      turnId: d.turnId,
      players: d.players,
      styles: d.styles,
      mix: List.unmodifiable(mix),
      choice: play,
      drew: choice == null,
      action: action,
      oneAction: oneAction,
    ));
    await heroAct(action ?? menu[play].action);
  }

  /// The user's decision was just scored: a Mistake or a Blunder is saved
  /// to the drills (the same spot saved before starts over), and the table
  /// says so ([savedToDrills]).
  void _scored(DecisionScore score) {
    final hand = session.hand;
    if (hand != null) _scoredAt(score, hand, session.players, session.styles);
  }

  /// [_scored], for the decision [at] stands at (on the device, maybe its
  /// hand follower), played by [players] with [styles].
  void _scoredAt(DecisionScore score, PokerHand at, List<PlayerInfo> players, List<BotStyle?> styles) {
    final drills = this.drills;
    if (drills == null || score.grade.index < DecisionGrade.mistake.index) return;
    final spot = DrillSpot.at(
      at,
      players: players,
      styles: styles,
      grade: score.grade,
      evLoss: score.evLoss,
      now: drills.now(),
    );
    if (spot == null) return;
    final added = drills.save(spot);
    if (!_saved.isClosed) _saved.add((again: !added, wait: spot.cooldown));
  }

  /// Tells the table each mistake saved to the drills ([again]: the same
  /// spot was saved before), and when it is first due ([wait] from now).
  Stream<({bool again, Duration wait})> get savedToDrills => _saved.stream;
  final _saved = StreamController<({bool again, Duration wait})>.broadcast();

  int _draw(SpotStrategy spot, List<double> mix) => _drawFrom(spot.actions, mix);

  /// One of [actions] (those allowed), drawn at random from [mix].
  int _drawFrom(List<SpotAction> actions, List<double> mix) {
    var roll = _random.nextDouble();
    var last = actions.indexWhere((a) => a.available);
    for (var i = 0; i < mix.length; i++) {
      if (mix[i] <= 0 || !actions[i].available) continue;
      last = i;
      roll -= mix[i];
      if (roll < 0) return i;
    }
    return last;
  }

  /// Simple training: plays [choice] and grades it against GTO. Better plays
  /// go ahead at once; after a mistake or a blunder, GTO's answer shows first
  /// (then [continueHand]). A raise of another amount is played as [action]
  /// and graded as [choice], the nearest size GTO has. Before GTO's answer
  /// comes, the move plays at once and is graded when it does.
  Future<void> playGraded(int choice, {PlayerAction? action}) async {
    final spot = heroSpot, menu = heroMenu;
    if (spot == null) {
      if (answerPending && menu != null && heroScore == null) {
        await _playBeforeAnswer([for (var i = 0; i < menu.length; i++) i == choice ? 1.0 : 0.0],
            choice: choice, oneAction: true, action: action);
      }
      return;
    }
    submitMix([for (var i = 0; i < spot.actions.length; i++) i == choice ? 1.0 : 0.0],
        choice: choice, oneAction: true);
    heroAction = action;
    final grade = heroScore?.grade;
    if (grade != null && grade.index < DecisionGrade.mistake.index) await continueHand();
  }

  /// Switches between simple and advanced training (from the next hand
  /// during one).
  void setAdvanced(bool value) {
    session.setAdvanced(value);
    _notify();
  }

  /// After scoring: plays the chosen (or drawn) action. A score of a move
  /// played already (graded after it) just goes.
  Future<void> continueHand() async {
    if (heroScoreLate || heroOptions == null) {
      _clearHeroDecision();
      _notify();
      return;
    }
    final spot = heroSpot, play = heroPlay;
    if (spot == null || play == null || heroScore == null) return;
    await heroAct(heroAction ?? spot.actions[play].action);
  }

  // ---------------------------------------------------------------------------
  // Answers that come after their moves (on the device and online)
  // ---------------------------------------------------------------------------

  /// GTO's answer [a] for the user's decision [d], worked out on [at] (a
  /// copy of the hand standing at that decision; its trackers' [postflop]
  /// gives the "why"). It joins the choices if they still show; a move
  /// already made there is scored now.
  void _answerCame(_Decision d, GtoAnswer a, PokerHand? at, {PostflopTracker? postflop}) {
    if (_disposed) return;
    if (_showing(d)) {
      // Nobody waits for this answer any more.
      wantAnswerShown(false);
      _answered = true;
      answerNone = a.none;
      if (a.spot case final spot?) {
        heroSpot = spot;
        heroMenu = spot.actions;
      }
    } else {
      final i = _unscored.indexWhere((played) => played.hand == d.hand && played.turnId == d.turnId);
      if (i >= 0) {
        final played = _unscored.removeAt(i);
        if ((a.spot, at) case (final spot?, final at?)) _scoreLate(played, spot, at, postflop ?? session.postflop);
      }
    }
    _notify();
  }

  /// Whether the choices of decision [d] still show.
  bool _showing(_Decision d) => heroOptions != null && identical(_decision, d);

  /// Scores [played], a move made before its answer [spot] came, worked out
  /// on [at] (at that decision, followed by [postflop] after the flop), and
  /// records it with its hand, in the hand's order. A drill is saved from
  /// [at], with the decision's players. A Mistake or a Blunder in the hand
  /// on screen shows (without holding the table) unless the user is
  /// choosing again already, and is listed when the hand is over.
  void _scoreLate(_Unscored played, SpotStrategy spot, PokerHand at, PostflopTracker? postflop) {
    final record = _recordOf(played.hand);
    final actions = spot.actions;
    if (record == null || played.mix.length != actions.length) return;
    final List<double> mix;
    final int? choice;
    if (played.oneAction) {
      choice = _solvedChoice(actions, played.choice, played.action);
      if (choice == null) return;
      mix = [for (var i = 0; i < actions.length; i++) i == choice ? 1.0 : 0.0];
    } else {
      // Shares on choices GTO hasn't solved drop out.
      final kept = [for (final (i, share) in played.mix.indexed) actions[i].available ? share : 0.0];
      final total = kept.fold(0.0, (a, b) => a + b);
      if (total <= 0) return;
      mix = [for (final share in kept) share / total];
      choice = actions[played.choice].available ? played.choice : null;
    }
    final score = scoreDecision(spot, mix);
    record.addDecision(
      DecisionRecord(
        street: at.street,
        board: at.board,
        spot: spot,
        mix: List.unmodifiable(mix),
        score: score,
        oneAction: played.oneAction,
        turnId: played.turnId,
      )..played = choice,
    );
    _scoredAt(score, at, played.players, played.styles);
    final onScreen = played.hand == _tableHand;
    if (onScreen && score.grade.index >= DecisionGrade.mistake.index) {
      _lateMistakes
        ..removeWhere((m) => m.hand != played.hand)
        ..add((hand: played.hand, street: at.street, grade: score.grade));
    }
    if (heroOptions != null || !onScreen || !_showsLate(score, played)) return;
    heroSpot = spot;
    heroMix = List.unmodifiable(mix);
    heroScore = score;
    heroPlay = choice;
    heroDrew = played.drew;
    heroAction = played.action;
    heroWhy = whyInputs(at, at.legalActions(), postflop);
    heroScoreLate = true;
  }

  /// Whether a score that came after its move shows: only a Mistake or a
  /// Blunder, in simple and advanced training alike. The table has moved
  /// on, so a Best or Good play just joins the recent scores rather than
  /// pop up over it.
  bool _showsLate(DecisionScore score, _Unscored played) => score.grade.index >= DecisionGrade.mistake.index;




  /// Shows or hides one bot's cards, right away and in later hands.
  void toggleCards(int seat) {
    final revealed = session.revealedSeats;
    if (!revealed.remove(seat)) revealed.add(seat);
    _showRevealed(seat);
    _notify();
  }

  /// Whether every opponent's cards are shown.
  bool get allCardsShown => [
        for (var s = 0; s < playerCount; s++)
          if (s != TableSession.heroSeat) s,
      ].every(session.revealedSeats.contains);

  /// Shows every opponent's cards right away (or hides them all again).
  void toggleAllCards() {
    final showAll = !allCardsShown;
    for (var s = 0; s < playerCount; s++) {
      if (s == TableSession.heroSeat) continue;
      showAll ? session.revealedSeats.add(s) : session.revealedSeats.remove(s);
      _showRevealed(s);
    }
    _notify();
  }

  /// Turns a bot's cards up or down in the current hand to match the setting.
  /// A player who folded gets their cards back, face up, while shown.
  void _showRevealed(int seat) {
    final h = hand, view = this.view.seats[seat];
    if (h == null) return;
    final show = session.revealedSeats.contains(seat);
    if (view.folded) {
      view
        ..cards = show ? h.holeCards(seat) : const []
        ..cardsHeld = show ? 2 : 0
        ..faceUp = show;
      return;
    }
    // Showdown cards stay up; not yet dealt stays empty.
    if (view.cardsHeld == 0 || h.isOver) return;
    view
      ..cards = show ? h.holeCards(seat) : const []
      ..faceUp = show;
  }

  /// Whether [seat]'s cards are shown on the table (a player who folds
  /// keeps them, dimmed): bots the user chose to see; online, a player whose
  /// cards the user looked at.
  bool _cardsShown(int seat) => session.revealedSeats.contains(seat);

  /// Changes one bot's style; null makes it random and secret.
  void setStyle(int seat, BotStyle? style) {
    session.setStyle(seat, style);
    view.seats[seat].style = session.styles[seat];
    _notify();
  }

  void _clearHeroDecision() {
    // Show GTO pressed at this decision was for this one.
    wantAnswerShown(false);
    heroOptions = null;
    heroSpot = null;
    heroMenu = null;
    heroMix = null;
    heroScore = null;
    heroPlay = null;
    heroDrew = false;
    heroAction = null;
    heroScoreLate = false;
    heroWhy = null;
    answerNone = null;
    _decision = null;
    _answered = false;
  }

  @override
  void dispose() {
    _disposed = true;
    // Solves not started yet for this table won't be needed.
    for (final f in followers) {
      _abandon(f);
    }
    for (final owner in [?_nextOwner, ?_aheadOwner]) {
      _solutions.drop(owner);
    }
    unawaited(_saved.close());
    super.dispose();
  }

  Future<void> _runUntilHeroOrEnd() async {
    final hand = session.hand!;
    while (!hand.isOver) {
      if (_disposed) return;
      final seat = hand.toAct!;
      view.actingSeat = seat;
      _notify();
      final recorded = _recordedMove(seat) ?? (seat == TableSession.heroSeat ? null : scriptedBots?.call(hand, seat));
      if (seat == TableSession.heroSeat && recorded == null) {
        _heroTurn(hand);
        return;
      }
      await _pause(Playback.botThink);
      if (_disposed) return;
      final f = _follower;
      if (recorded == null && f != null && session.playsFromSolve(hand, seat)) {
        // A moment more for what it plays from (its hand's solves first,
        // while it waits); then the best it has, which keeps the hand on
        // the solved lines.
        final waiting = f.owner.claim(SolvePriority.bot);
        try {
          final ready = f.readyFor(seat, session.styles[seat]);
          final budget = botBudget;
          if (budget == null) {
            await ready.then((_) {}, onError: (Object _) {});
          } else {
            await _within(ready, budget);
          }
        } finally {
          waiting.end();
        }
        if (_disposed) return;
      }
      hand.act(recorded ?? session.botDecision());
      final batch = hand.drainEvents();
      // The street that begins starts solving while its cards are dealt on screen.
      _follower?.step(batch);
      _settleAhead(hand);
      _maybePrecompute(hand);
      await _play(batch);
    }
    view.actingSeat = null;
    session.finishHand();
    handOver = true;
    _notify();
  }

  /// The user's turn in [hand]: their choices show at once, with GTO's
  /// answer if it is worked out already, else once it is (Guess the GTO
  /// mode). A score of a move graded late that still shows goes.
  void _heroTurn(PokerHand hand) {
    _clearHeroDecision();
    heroOptions = hand.legalActions();
    heroSpot = guessGto ? session.heroSpot() : null;
    heroMenu = heroSpot?.actions ?? actionMenu(hand);
    final d = _decision = (
      hand: hand.handNumber,
      turnId: decisionIdOf(hand),
      players: List.of(session.players),
      styles: List.of(session.styles),
    );
    if (guessGto && heroSpot == null) {
      final f = _follower;
      if (f == null) {
        _answered = true;
      } else {
        f.answer((a, at) => _answerCame(d, a, at, postflop: f.postflop));
      }
    }
    // A pre-action is played once the table is free (see _playPreAction).
    _due = _preActionChoice();
    if (_due == null) _sound(SoundEffect.yourTurn);
    _notify();
  }

  /// A drill replays a saved hand: the move it recorded for [seat] (the
  /// user's own earlier moves too), while there are any. Null: the bot
  /// decides, or the user does.
  PlayerAction? _recordedMove(int seat) => null;

  // ---------------------------------------------------------------------------
  // Pre-actions
  // ---------------------------------------------------------------------------

  /// The user's pick for their next turn, made while someone else acts (see
  /// [PreAction]), with what they had to call then; null if none.
  ({PreAction kind, int toCall})? preAction;

  /// The choice a pre-action plays at the user's turn, until the table is
  /// free to play it.
  int? _due;

  /// While someone else acts in a hand the user is still in (not folded or
  /// all-in): what the user has to call right now, as the table shows it,
  /// so they can pick a pre-action. Null otherwise, and in advanced training
  /// (its decisions need percentages).
  int? get preActionCall {
    final acting = view.actingSeat;
    if (handOver || heroOptions != null || acting == null || isUserSeat(acting) || !_preActionsOn) return null;
    if (view.seats.isEmpty || !isUserSeat(TableSession.heroSeat)) return null;
    final me = view.seats[TableSession.heroSeat];
    if (me.cardsHeld == 0 || me.folded || me.allIn || me.stack == 0) return null;
    return _shownToCall();
  }

  bool get _preActionsOn => !(guessGto && advanced);

  /// Picks [kind] for the user's next turn, or drops it if it is the one
  /// picked already.
  void togglePreAction(PreAction kind) {
    final toCall = preActionCall;
    if (toCall == null) return;
    preAction = preAction?.kind == kind ? null : (kind: kind, toCall: toCall);
    _notify();
  }

  /// What the user has to call as the table shows it (a bet counts once its
  /// chips are in front of the player). Before the flop the big blind sets
  /// the price, even when it was posted short (as in PokerHand).
  int _shownToCall() {
    final me = view.seats[TableSession.heroSeat];
    final price = view.seats.fold(view.board.isEmpty ? TableConfig.bigBlind : 0, (most, seat) => max(most, seat.bet));
    return max(0, min(price - me.bet, me.stack));
  }

  /// A pre-action that no longer fits what the table shows goes: Check once
  /// someone bets, Call once the amount changes.
  void _reviewPreAction() {
    final pre = preAction;
    if (pre == null || view.seats.isEmpty) return;
    if (!pre.kind.fits(picked: pre.toCall, toCall: _shownToCall())) preAction = null;
  }

  /// At the user's turn: the choice their pre-action plays, if it still
  /// fits (played or not, it goes).
  int? _preActionChoice() {
    final pre = preAction, options = heroOptions, menu = heroMenu;
    preAction = null;
    if (pre == null || options == null || menu == null || !_preActionsOn) return null;
    return pre.kind.choiceIn(menu, options, picked: pre.toCall);
  }

  /// Plays the pre-action due at the user's turn, if any.
  Future<void> _playPreAction() async {
    final choice = _due;
    _due = null;
    if (choice != null && !_disposed) await _playChoice(choice);
  }

  /// Plays [choice] of the user's menu as the buttons do: graded against
  /// GTO when there is an answer (simple training), else at once.
  Future<void> _playChoice(int choice) => _gradesPlay ? playGraded(choice) : heroAct(heroMenu![choice].action);

  /// Whether the user's play at this decision is graded (now, or once
  /// GTO's answer comes).
  bool get _gradesPlay => heroSpot != null || answerPending;

  // ---------------------------------------------------------------------------
  // Event playback
  // ---------------------------------------------------------------------------

  Future<void> _play(List<GameEvent> events) async {
    for (final event in events) {
      if (_disposed) return;
      await _playEvent(event);
    }
  }

  Future<void> _playEvent(GameEvent event) async {
    switch (event) {
      case HandStarted():
        preAction = null;
        for (final (i, seat) in view.seats.indexed) {
          seat.resetForHand(event.stacks[i], event.positions[i]);
        }
        view
          ..buttonSeat = event.buttonSeat
          ..actingSeat = null
          ..board.clear()
          ..pots = const []
          ..results.clear()
          ..heroResult = null;
        _notify();
        await _pause(Playback.handStart);

      case AntesPosted():
        var total = 0;
        event.amounts.forEach((seat, amount) {
          view.seats[seat].stack -= amount;
          total += amount;
          _fly(Anchor.seat(seat), const Anchor.pot(), Playback.chipMove, chips: amount);
        });
        await _pause(Playback.chipMove);
        view.pots = [total];
        _notify();

      case BlindPosted():
        final seat = view.seats[event.seat];
        seat.stack -= event.amount;
        _fly(Anchor.seat(event.seat), Anchor.bet(event.seat), Playback.chipMove, chips: event.amount,
            onArrive: () => seat.bet += event.amount);
        await _pause(Playback.blindPause);

      case HoleCardsDealt():
        for (var round = 0; round < 2; round++) {
          for (final seatIndex in event.dealOrder) {
            final seat = view.seats[seatIndex];
            // Online, only the user's own cards are in the event.
            final visible = (isUserSeat(seatIndex) || _cardsShown(seatIndex)) &&
                event.cards.containsKey(seatIndex);
            if (visible) seat.cards = event.cards[seatIndex]!;
            _sound(SoundEffect.deal);
            _fly(const Anchor.deck(), Anchor.seatCards(seatIndex), Playback.cardMove,
                card: visible ? seat.cards[round] : null, faceUp: visible, onArrive: () {
              seat.cardsHeld++;
              if (visible) seat.faceUp = true;
            });
            await _pause(Playback.dealGap);
          }
        }
        await _pause(Playback.cardMove);

      case ActionTaken():
        final seat = view.seats[event.seat];
        _sound(switch (event.kind) {
          ActionKind.fold => SoundEffect.fold,
          ActionKind.check => SoundEffect.check,
          _ => SoundEffect.chips,
        });
        seat
          ..lastAction = event.kind
          ..action = event
          ..allIn = event.isAllIn;
        if (event.kind == ActionKind.fold) {
          seat.folded = true;
          // The user's cards and shown cards stay up (greyed); the others go to the muck.
          if (!isUserSeat(event.seat) && !_cardsShown(event.seat)) {
            final count = seat.cardsHeld;
            seat.cardsHeld = 0;
            for (var i = 0; i < count; i++) {
              _fly(Anchor.seatCards(event.seat), const Anchor.deck(), Playback.cardMove, fadeOut: true);
            }
          }
        }
        if (event.chipsAdded > 0) {
          seat.stack -= event.chipsAdded;
          _fly(Anchor.seat(event.seat), Anchor.bet(event.seat), Playback.chipMove,
              chips: event.chipsAdded, onArrive: () => seat.bet += event.chipsAdded);
        }
        _notify();
        await _pause(Playback.chipMove);

      case UncalledBetReturned():
        final seat = view.seats[event.seat];
        seat.bet -= event.amount;
        _fly(Anchor.bet(event.seat), Anchor.seat(event.seat), Playback.chipMove,
            chips: event.amount, onArrive: () => seat.stack += event.amount);
        await _pause(Playback.chipMove);

      case BetsCollected():
        // A pre-action is for the street it was picked on.
        preAction = null;
        view.actingSeat = null;
        if (view.seats.any((s) => s.bet > 0)) _sound(SoundEffect.chips);
        for (final (index, seat) in view.seats.indexed) {
          if (seat.bet > 0) {
            _fly(Anchor.bet(index), const Anchor.pot(), Playback.chipMove, chips: seat.bet);
            seat.bet = 0;
          }
          if (!seat.folded) seat.action = null;
        }
        _notify();
        await _pause(Playback.chipMove);
        view.pots = [for (final pot in event.pots) pot.amount];
        _notify();
        await _pause(Playback.potSettle);

      case BoardDealt():
        preAction = null;
        final firstSlot = view.board.length;
        for (final (i, card) in event.cards.indexed) {
          _sound(SoundEffect.deal);
          _fly(const Anchor.deck(), Anchor.board(firstSlot + i), Playback.cardMove, card: card, faceUp: true,
              onArrive: () => view.board.add(card));
          await _pause(Playback.boardGap);
        }
        await _pause(Playback.cardMove + Playback.boardSettle);

      case HandsRevealed():
        event.cards.forEach((seat, cards) {
          view.seats[seat]
            ..cards = cards
            ..faceUp = true;
        });
        _notify();
        await _pause(Playback.reveal);

      case PotAwarded():
        if (event.winningHand == null) {
          view.pots = const [];
        } else {
          view.pots = [
            for (final (i, amount) in view.pots.indexed) i == event.potIndex ? 0 : amount,
          ];
        }
        event.shares.forEach((seatIndex, amount) {
          final seat = view.seats[seatIndex];
          _fly(const Anchor.pot(), Anchor.seat(seatIndex), Playback.awardMove, chips: amount,
              onArrive: () {
            seat.stack += amount;
            seat.won += amount;
          });
        });
        view.results.add(PotResult(event, sidePots: view.pots.length > 1));
        _sound(event.shares.keys.any(isUserSeat) ? SoundEffect.win : SoundEffect.chips);
        _notify();
        await _pause(Playback.awardMove + Playback.awardSettle);

      case HandEnded():
        preAction = null;
        view.heroResult = isUserSeat(TableSession.heroSeat) ? event.netChange[TableSession.heroSeat] : null;
        _notify();
    }
  }

  // ---------------------------------------------------------------------------
  // Timing
  // ---------------------------------------------------------------------------

  /// Plays a sound effect, unless animations are off.
  void _sound(SoundEffect effect) {
    if (_speed != PlaybackSpeed.instant && !_disposed) Sounds.instance.play(effect);
  }

  double get _factor {
    if (_speed == PlaybackSpeed.instant) return 0;
    // Once the user has folded, hurry through the rest of the hand.
    return _heroFolded ? min(_speed.factor, PlaybackSpeed.fast.factor) : _speed.factor;
  }

  Future<void> _pause(Duration duration) async {
    final factor = _factor;
    if (factor == 0) return;
    await Future<void>.delayed(duration * factor);
  }

  void _fly(
    Anchor from,
    Anchor to,
    Duration duration, {
    int chips = 0,
    PlayingCard? card,
    bool faceUp = false,
    bool fadeOut = false,
    VoidCallback? onArrive,
  }) {
    final factor = _factor;
    if (factor == 0) {
      onArrive?.call();
      return;
    }
    final item = FlyingItem(
      from: from,
      to: to,
      duration: duration * factor,
      chips: chips,
      card: card,
      faceUp: faceUp,
      fadeOut: fadeOut,
    );
    flying.add(item);
    _notify();
    Timer(item.duration, () {
      // Online, a table that starts over takes what still flies off it: that doesn't land.
      if (_disposed || !flying.remove(item)) return;
      onArrive?.call();
      _notify();
    });
  }

  void _notify() {
    if (_disposed) return;
    _reviewPreAction();
    notifyListeners();
  }
}

/// As in simple training on the device, a good play just goes on (its
/// score joins the recent ones): no score shows unless it is a mistake or
/// a blunder, or a mix was set (advanced training).
bool _quietGrade(DecisionScore score, {required bool oneAction}) =>
    oneAction && score.grade.index < DecisionGrade.mistake.index;

/// [choice] of [actions] (the same menu, now with GTO's answer) if GTO
/// has solved it; for a raise it hasn't, the nearest size it has (for a
/// raise of another amount, [action], nearest to that). Null if none.
int? _solvedChoice(List<SpotAction> actions, int choice, PlayerAction? action) {
  final chosen = actions[choice];
  if (chosen.available) return choice;
  if (chosen.kind != SpotActionKind.raise && chosen.kind != SpotActionKind.allIn) return null;
  final to = action?.amount ?? chosen.amount;
  int? best;
  var distance = double.infinity;
  for (final (i, a) in actions.indexed) {
    if (!a.available || (a.kind != SpotActionKind.raise && a.kind != SpotActionKind.allIn)) continue;
    final d = (log(a.amount) - log(to)).abs();
    if (d < distance) (distance, best) = (d, i);
  }
  return best;
}

/// Whether [future] completes (without failing) within [limit].
Future<bool> _within(Future<void> future, Duration limit) =>
    future.timeout(limit.isNegative ? Duration.zero : limit).then((_) => true, onError: (Object _) => false);

/// Whether someone before the user's first move in [hand] did more than
/// fold: the user's first decision isn't the one guessed and solved ahead
/// of time (the one if everyone folds to them).
bool _aheadMissed(PokerHand hand, bool Function(int seat) isUser) {
  for (final e in hand.log) {
    if (e is! ActionTaken || e.street != Street.preflop) continue;
    if (isUser(e.seat)) return false;
    if (e.kind != ActionKind.fold) return true;
  }
  return false;
}

/// Runs [future] for its effect only: a failure shows up where the result
/// is needed.
void _quietly(Future<void> future) => unawaited(future.then((_) {}, onError: (Object _) {}));
