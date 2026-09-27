import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../app/sounds.dart';
import '../bots/bot.dart';
import '../engine/actions.dart';
import '../engine/cards.dart';
import '../engine/events.dart';
import '../engine/poker_hand.dart';
import '../game/table_session.dart';
import '../gto/action_menu.dart';
import '../gto/gto_solutions.dart';
import '../gto/spot_strategy.dart';
import 'table_view_state.dart';

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
class TableController extends ChangeNotifier {
  TableController(
    TableConfig config, {
    this._speed = PlaybackSpeed.normal,
    Random? random,
    GtoSolutions? solutions,
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

  static const _chipMove = Duration(milliseconds: 380);
  static const _cardMove = Duration(milliseconds: 260);
  static const _dealGap = Duration(milliseconds: 70);
  static const _botThink = Duration(milliseconds: 650);

  final TableSession session;
  final Random _random;
  final GtoSolutions _solutions;
  late final TableViewState view;
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
  int get playerCount => session.config.playerCount;
  bool get guessGto => session.config.guessGto;

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
  }

  /// The action the user will play once they continue, and whether it was
  /// drawn from their mix (rather than ticked).
  int? heroPlay;
  bool heroDrew = false;

  /// Scores the user's mix (how often to take each action, adding up to 1)
  /// and fixes the action to play: [choice], or one drawn from the mix.
  void submitMix(List<double> mix, {int? choice}) {
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
    )..played = heroPlay);
    _notify();
  }

  int _draw(SpotStrategy spot, List<double> mix) {
    var roll = _random.nextDouble();
    var last = spot.actions.indexWhere((a) => a.available);
    for (var i = 0; i < mix.length; i++) {
      if (mix[i] <= 0 || !spot.actions[i].available) continue;
      last = i;
      roll -= mix[i];
      if (roll < 0) return i;
    }
    return last;
  }

  /// After scoring: plays the chosen (or drawn) action.
  Future<void> continueHand() async {
    final spot = heroSpot, play = heroPlay;
    if (spot == null || play == null || heroScore == null) return;
    await heroAct(spot.actions[play].action);
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

  /// Changes one bot's style; null makes it random and secret.
  void setStyle(int seat, BotStyle? style) {
    session.setStyle(seat, style);
    view.seats[seat].style = session.styles[seat];
    _notify();
  }

  /// Gives every bot a new random style (Guess the GTO mode).
  void shuffleStyles() {
    session.shuffleStyles();
    for (final (i, seat) in view.seats.indexed) {
      seat.style = session.styles[i];
    }
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
  }

  @override
  void dispose() {
    _disposed = true;
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
      if (seat == TableSession.heroSeat) {
        heroOptions = hand.legalActions();
        heroSpot = session.heroSpot();
        _sound(SoundEffect.yourTurn);
        heroMenu = heroSpot?.actions ??
            actionMenu(
              hand,
              preflopSizes: session.config.preflopSizes,
              postflopSizes: session.config.postflopSizes,
            );
        _notify();
        return;
      }
      await _pause(_botThink);
      if (_disposed) return;
      hand.act(session.botDecision());
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
        await _pause(const Duration(milliseconds: 250));

      case AntesPosted():
        var total = 0;
        event.amounts.forEach((seat, amount) {
          view.seats[seat].stack -= amount;
          total += amount;
          _fly(Anchor.seat(seat), const Anchor.pot(), _chipMove, chips: amount);
        });
        await _pause(_chipMove);
        view.pots = [total];
        _notify();

      case BlindPosted():
        final seat = view.seats[event.seat];
        seat.stack -= event.amount;
        _fly(Anchor.seat(event.seat), Anchor.bet(event.seat), _chipMove, chips: event.amount,
            onArrive: () => seat.bet += event.amount);
        await _pause(_chipMove * 0.7);

      case HoleCardsDealt():
        for (var round = 0; round < 2; round++) {
          for (final seatIndex in event.dealOrder) {
            final seat = view.seats[seatIndex];
            final visible =
                seatIndex == TableSession.heroSeat || session.revealedSeats.contains(seatIndex);
            if (visible) seat.cards = event.cards[seatIndex]!;
            _sound(SoundEffect.deal);
            _fly(const Anchor.deck(), Anchor.seatCards(seatIndex), _cardMove,
                card: visible ? seat.cards[round] : null, faceUp: visible, onArrive: () {
              seat.cardsHeld++;
              if (visible) seat.faceUp = true;
            });
            await _pause(_dealGap);
          }
        }
        await _pause(_cardMove);

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
          if (event.seat != TableSession.heroSeat && !session.revealedSeats.contains(event.seat)) {
            final count = seat.cardsHeld;
            seat.cardsHeld = 0;
            for (var i = 0; i < count; i++) {
              _fly(Anchor.seatCards(event.seat), const Anchor.deck(), _cardMove, fadeOut: true);
            }
          }
        }
        if (event.chipsAdded > 0) {
          seat.stack -= event.chipsAdded;
          _fly(Anchor.seat(event.seat), Anchor.bet(event.seat), _chipMove,
              chips: event.chipsAdded, onArrive: () => seat.bet += event.chipsAdded);
        }
        _notify();
        await _pause(_chipMove);

      case UncalledBetReturned():
        final seat = view.seats[event.seat];
        seat.bet -= event.amount;
        _fly(Anchor.bet(event.seat), Anchor.seat(event.seat), _chipMove,
            chips: event.amount, onArrive: () => seat.stack += event.amount);
        await _pause(_chipMove);

      case BetsCollected():
        view.actingSeat = null;
        if (view.seats.any((s) => s.bet > 0)) _sound(SoundEffect.chips);
        for (final (index, seat) in view.seats.indexed) {
          if (seat.bet > 0) {
            _fly(Anchor.bet(index), const Anchor.pot(), _chipMove, chips: seat.bet);
            seat.bet = 0;
          }
          if (!seat.folded) seat.action = null;
        }
        _notify();
        await _pause(_chipMove);
        view.pots = [for (final pot in event.pots) pot.amount];
        _notify();
        await _pause(const Duration(milliseconds: 150));

      case BoardDealt():
        final firstSlot = view.board.length;
        for (final (i, card) in event.cards.indexed) {
          _sound(SoundEffect.deal);
          _fly(const Anchor.deck(), Anchor.board(firstSlot + i), _cardMove, card: card, faceUp: true,
              onArrive: () => view.board.add(card));
          await _pause(const Duration(milliseconds: 120));
        }
        await _pause(_cardMove + const Duration(milliseconds: 250));

      case HandsRevealed():
        event.cards.forEach((seat, cards) {
          view.seats[seat]
            ..cards = cards
            ..faceUp = true;
        });
        _notify();
        await _pause(const Duration(milliseconds: 800));

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
          _fly(const Anchor.pot(), Anchor.seat(seatIndex), _chipMove * 1.4, chips: amount,
              onArrive: () {
            seat.stack += amount;
            seat.won += amount;
          });
        });
        view.results.add(PotResult(event, sidePots: view.pots.length > 1));
        _sound(event.shares.containsKey(TableSession.heroSeat) ? SoundEffect.win : SoundEffect.chips);
        _notify();
        await _pause(_chipMove * 1.4 + const Duration(milliseconds: 400));

      case HandEnded():
        view.heroResult = event.netChange[TableSession.heroSeat];
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
      if (_disposed) return;
      flying.remove(item);
      onArrive?.call();
      _notify();
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
