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
import '../game/pre_action.dart';
import '../game/table_session.dart';
import '../gto/action_menu.dart';
import '../gto/gto_solutions.dart';
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

/// Runs a [TableSession] for the table screen.
///
/// The engine decides everything instantly; this controller replays its
/// events one at a time, updating [view] and launching [flying] chips and
/// cards, so the user can follow what happened.
///
/// In Guess the GTO mode it also makes sure the preflop game is solved
/// before each hand (solving the next one in the background while the
/// current hand is played), and runs the "enter your mix, see the score" step.
/// Each Mistake or Blunder is saved to the [drills], to play again later.
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

  /// Guess the GTO mode: the answer for the user's current decision.
  SpotStrategy? heroSpot;

  /// The user's choices at their current decision (the same list every time;
  /// see [actionMenu]): GTO's answer lists them too, when there is one.
  List<SpotAction>? heroMenu;

  /// The user's mix (frequencies adding up to 1) and its score, once submitted.
  List<double>? heroMix;
  DecisionScore? heroScore;

  /// While the next hand's preflop game is being solved: 0 to 1.
  double? preparing;

  /// While the current street is being solved for the player to act.
  bool solvingSpot = false;
  bool handOver = false;

  PlaybackSpeed _speed;
  bool _busy = false;
  bool _disposed = false;
  bool _heroFolded = false;

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

  Future<void> startNextHand() async {
    if (_busy) return;
    _busy = true;
    handOver = false;
    _clearHeroDecision();
    _heroFolded = false;
    if (session.needsSolver) {
      await _prepareSolution();
      if (_disposed) return;
    }
    final hand = session.startHand();
    for (final (i, seat) in view.seats.indexed) {
      seat.style = session.styles[i];
    }
    // Starts solving the user's decision if they act first (and, rarely, a
    // hand skips straight past the preflop betting: everyone all-in).
    await session.afterAction();
    // With stacks reset every hand, the next hand is known already.
    if (session.config.resetStacksEachHand) _precomputeNext();
    await _play(hand.drainEvents());
    await _runUntilHeroOrEnd();
    _busy = false;
    await _playPreAction();
  }

  /// Waits until the next hand's whole preflop game is solved, showing
  /// progress, and queues the user's first decision after it.
  Future<void> _prepareSolution() async {
    final spec = session.upcomingSpec;
    var advisor = _solutions.ready(spec);
    if (advisor == null) {
      final progress = _solutions.progressOf(spec);
      void update() {
        preparing = progress.value;
        _notify();
      }

      progress.addListener(update);
      update();
      try {
        advisor = await _solutions.solve(spec);
      } finally {
        progress.removeListener(update);
        preparing = null;
      }
    }
    session.advisor = advisor;
    final heroSpec = session.upcomingHeroSpec;
    if (heroSpec != null) unawaited(_solutions.solve(heroSpec).then((_) {}, onError: (_) {}));
  }

  /// The hand number whose next hand is already being solved.
  int _precomputedAfter = -1;

  /// Starts solving the next hand (its whole game, then the user's first
  /// decision if everyone folds to them) as soon as it is known: when this
  /// hand is decided, while its last cards and chips are still being shown.
  void _precomputeNext() {
    if (!session.needsSolver || _precomputedAfter == session.handNumber) return;
    _precomputedAfter = session.handNumber;
    final spec = session.upcomingSpec, heroSpec = session.upcomingHeroSpec;
    Future<void> solveBoth() async {
      await _solutions.solve(spec);
      if (heroSpec != null) await _solutions.solve(heroSpec);
    }

    // Failures show up when the hand needs the solve; nothing to do here.
    unawaited(solveBoth().then((_) {}, onError: (_) {}));
  }

  Future<void> heroAct(PlayerAction action) async {
    final hand = session.hand;
    if (_busy || heroOptions == null || hand == null) return;
    _busy = true;
    _clearHeroDecision();
    if (action.type == ActionType.fold) _heroFolded = true;
    hand.act(action);
    if (hand.isOver) _precomputeNext();
    // Start solving a new street while its cards are being dealt on screen.
    final tracking = session.afterAction();
    await _play(hand.drainEvents());
    await tracking;
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
  void submitMix(List<double> mix, {int? choice, bool oneAction = false}) {
    final spot = heroSpot;
    final hand = session.hand;
    if (spot == null || hand == null || heroScore != null) return;
    heroMix = List.unmodifiable(mix);
    heroScore = scoreDecision(spot, mix);
    heroDrew = choice == null;
    heroPlay = choice ?? _draw(spot, mix);
    session.history.last.decisions.add(DecisionRecord(
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

  /// Online: the server's turn a decision is recorded at.
  int? get _recordTurnId => null;

  /// The user's decision was just scored: a Mistake or a Blunder is saved
  /// to the drills (the same spot saved before starts over), and the table
  /// says so ([savedToDrills]).
  void _scored(DecisionScore score) {
    final drills = this.drills, hand = session.hand;
    if (drills == null || hand == null || score.grade.index < DecisionGrade.mistake.index) return;
    final spot = DrillSpot.at(
      hand,
      players: session.players,
      styles: session.styles,
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
  /// and graded as [choice], the nearest size GTO has.
  Future<void> playGraded(int choice, {PlayerAction? action}) async {
    final spot = heroSpot;
    if (spot == null) return;
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

  /// After scoring: plays the chosen (or drawn) action.
  Future<void> continueHand() async {
    final spot = heroSpot, play = heroPlay;
    if (spot == null || play == null || heroScore == null) return;
    await heroAct(heroAction ?? spot.actions[play].action);
  }

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

  /// Waits for the solve the player to act needs, if it is still running:
  /// before the flop, the user's subgame (for their answer in Guess the GTO
  /// mode, and for the bots' replies to their choice); after it, the
  /// street (for the user in Guess the GTO mode, or a GTO bot).
  Future<void> _waitForAnswers() async {
    final hand = session.hand!;
    final Future<void> wait;
    if (hand.street == Street.preflop) {
      final heroTurn = hand.toAct == TableSession.heroSeat;
      if (!session.preflopPending || (heroTurn && !guessGto)) return;
      wait = session.preflopReady;
    } else {
      final tracker = session.postflop;
      if (tracker == null || !session.needsPostflopAnswer || !tracker.solving) return;
      wait = tracker.ready;
    }
    solvingSpot = true;
    _notify();
    try {
      await wait;
    } finally {
      solvingSpot = false;
    }
  }

  void _clearHeroDecision() {
    heroOptions = null;
    heroSpot = null;
    heroMenu = null;
    heroMix = null;
    heroScore = null;
    heroPlay = null;
    heroDrew = false;
    heroAction = null;
  }

  @override
  void dispose() {
    _disposed = true;
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
      await _waitForAnswers();
      if (_disposed) return;
      final recorded = _recordedMove(seat);
      if (seat == TableSession.heroSeat && recorded == null) {
        heroOptions = hand.legalActions();
        heroSpot = session.heroSpot();
        heroMenu = heroSpot?.actions ?? actionMenu(hand);
        // A pre-action is played once the table is free (see _playPreAction).
        _due = _preActionChoice();
        if (_due == null) _sound(SoundEffect.yourTurn);
        _notify();
        return;
      }
      await _pause(Playback.botThink);
      if (_disposed) return;
      hand.act(recorded ?? session.botDecision());
      if (hand.isOver) _precomputeNext();
      final tracking = session.afterAction();
      await _play(hand.drainEvents());
      await tracking;
    }
    view.actingSeat = null;
    session.finishHand();
    handOver = true;
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

  /// Whether the user's play at this decision is graded.
  bool get _gradesPlay => heroSpot != null;

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
