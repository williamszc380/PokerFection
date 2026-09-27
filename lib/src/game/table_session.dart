import 'dart:math';

import '../bots/bot.dart';
import '../engine/actions.dart';
import '../engine/events.dart';
import '../engine/poker_hand.dart';
import '../engine/positions.dart';
import '../engine/rules.dart';
import '../gto/postflop/postflop_tracker.dart';
import '../gto/postflop/postflop_tree.dart';
import '../gto/range_info.dart';
import '../gto/preflop/preflop_advisor.dart';
import '../gto/preflop/preflop_tracker.dart';
import '../gto/preflop/preflop_tree.dart';
import '../gto/spot_strategy.dart';
import 'history.dart';

export 'history.dart';

/// One player at the table.
class PlayerInfo {
  const PlayerInfo({required this.name, required this.stackBb, this.style, this.isHero = false});

  final String name;

  /// Starting stack in big blinds.
  final int stackBb;

  /// The bot's style; null means a random one, picked when the table starts
  /// (and unknown to the user unless styles are shown).
  final BotStyle? style;
  final bool isHero;

  PlayerInfo copyWith({int? stackBb}) =>
      PlayerInfo(name: name, stackBb: stackBb ?? this.stackBb, style: style, isHero: isHero);

  /// Same player with another style (null for random).
  PlayerInfo withStyle(BotStyle? style) =>
      PlayerInfo(name: name, stackBb: stackBb, style: style, isHero: isHero);
}

/// The starting situation the user picks before playing.
class TableConfig {
  const TableConfig({
    required this.players,
    this.heroPosition,
    this.ante = 0,
    this.resetStacksEachHand = false,
    this.guessGto = false,
    this.showStyles = false,
    this.showHands = false,
    this.raiseRule = RaiseRule.standard,
    this.preflopSizes = PreflopSettings.defaultRaiseMultiples,
    this.postflopSizes = PostflopSpec.defaultHeroSizes,
  });

  /// Everyone gets the same stack. Opponents share [opponentStyle], or each
  /// gets a random style when it is null.
  factory TableConfig.quick({
    int playerCount = 6,
    int stackBb = 100,
    BotStyle? opponentStyle,
    Position? heroPosition,
    int ante = 0,
    bool resetStacksEachHand = false,
    bool guessGto = false,
    bool showStyles = false,
    bool showHands = false,
    RaiseRule raiseRule = RaiseRule.standard,
  }) =>
      TableConfig(
        players: quickPlayers(count: playerCount, stackBb: stackBb, style: opponentStyle),
        heroPosition: heroPosition,
        ante: ante,
        resetStacksEachHand: resetStacksEachHand,
        guessGto: guessGto,
        showStyles: showStyles,
        showHands: showHands,
        raiseRule: raiseRule,
      );

  /// Chips per big blind. Amounts are shown to the user in big blinds.
  static const bigBlind = 100;
  static const smallBlind = 50;
  /// Bots are named in seat order, clockwise from the user.
  static const botNames = ['Alice', 'Bob', 'Charlie', 'David', 'Eve', 'Frank', 'Grace'];

  /// The user plus [count] - 1 bots with the same stack and [style]
  /// (random when null).
  static List<PlayerInfo> quickPlayers({
    required int count,
    required int stackBb,
    BotStyle? style,
  }) =>
      [
        PlayerInfo(name: 'You', stackBb: stackBb, isHero: true),
        for (var i = 1; i < count; i++) PlayerInfo(name: botNames[i - 1], stackBb: stackBb, style: style),
      ];

  /// Seat 0 is the user; the rest are bots, clockwise.
  final List<PlayerInfo> players;

  /// Always play from this position, or null to rotate the button normally.
  final Position? heroPosition;

  /// Ante per player, in chips.
  final int ante;
  final bool resetStacksEachHand;

  /// Ask the user for their strategy and score it against GTO.
  final bool guessGto;

  /// Training aids, only available in Guess the GTO mode: show each bot's
  /// style, and show their cards face up during the hand.
  final bool showStyles;
  final bool showHands;

  /// How small a raise may be.
  final RaiseRule raiseRule;

  /// The user's raise sizes: before the flop as multiples of the bet they
  /// face (when first in, of the big blind); after it as shares of the pot.
  final List<double> preflopSizes;
  final List<double> postflopSizes;

  bool get stylesVisible => guessGto && showStyles;
  bool get handsVisible => guessGto && showHands;

  int get playerCount => players.length;
  int stackOf(int seat) => players[seat].stackBb * bigBlind;
}

/// A series of hands at one table. The user always sits in seat 0.
class TableSession {
  TableSession(this.config, {Random? random, this.solvePostflop, this.solveSubgame})
      : _random = random ?? Random() {
    styles = [
      for (final p in config.players) p.isHero ? null : (p.style ?? _randomStyle()),
    ];
    hiddenStyles = [for (final p in config.players) !p.isHero && p.style == null];
    if (config.handsVisible) {
      revealedSeats.addAll([for (var s = 0; s < config.playerCount; s++) if (s != heroSeat) s]);
    }
    _bots = [for (final s in styles) s == null ? null : Bot(s, _random)];
    stacks = [for (var seat = 0; seat < config.playerCount; seat++) config.stackOf(seat)];
    _button = _random.nextInt(config.playerCount);
  }

  static const heroSeat = 0;

  final TableConfig config;
  final Random _random;

  /// Solves postflop streets (needed for GTO answers and GTO bots after the flop).
  final PostflopSolve? solvePostflop;

  /// Solves the user's preflop subgames (their GTO answers, and the bots'
  /// replies to whatever they choose).
  final PreflopSubgameSolve? solveSubgame;

  /// Follow the current hand before and after the flop, when solving is needed.
  PreflopTracker? preflop;
  PostflopTracker? postflop;

  /// The solve of the user's latest preflop decision, and whether it is done.
  Future<void>? _heroPreflop;
  bool _heroPreflopDone = true;
  int _heroPreflopTicket = 0;
  late List<Bot?> _bots;

  /// Each seat's actual style (null for the user), with random ones resolved.
  late List<BotStyle?> styles;

  /// Seats whose style is random and kept secret.
  late List<bool> hiddenStyles;

  /// Bots whose cards the user chose to see during play (Guess the GTO mode).
  final Set<int> revealedSeats = {};

  BotStyle _randomStyle() => BotStyle.humanLike[_random.nextInt(BotStyle.humanLike.length)];

  /// Gives every bot a new random human-like style (from the next decision on).
  void shuffleStyles() {
    styles = [for (final s in styles) s == null ? null : _randomStyle()];
    _bots = [for (final s in styles) s == null ? null : Bot(s, _random)];
  }

  /// Changes one bot's style; null gives it a random style kept secret.
  void setStyle(int seat, BotStyle? style) {
    if (seat == heroSeat) return;
    final resolved = style ?? _randomStyle();
    styles[seat] = resolved;
    hiddenStyles[seat] = style == null;
    _bots[seat] = Bot(resolved, _random);
  }

  /// What [seat] is likely to hold right now, if everyone played GTO so far;
  /// null when the hand has left the solved lines. A raise counts the same
  /// at any size (GTO's split between sizes is mostly noise). For opponents,
  /// hands using the user's cards are left out; the user's own range is
  /// shown as the opponents see it (they don't know the user's cards).
  RangeInfo? rangeOf(int seat) {
    final h = hand;
    if (h == null) return null;
    final dead = {
      for (final c in [...h.board, if (seat != heroSeat) ...h.holeCards(heroSeat)]) c.index,
    };
    if (h.street == Street.preflop) {
      final weights = preflop?.rangeOf(h, seat, anySize: true);
      return weights == null ? null : RangeInfo.fromClasses(weights, dead);
    }
    final weights = postflop?.currentRange(h, seat);
    return weights == null ? null : RangeInfo.fromCombos(weights, dead);
  }

  /// Whether any opponent plays the solver's strategy (now, or once
  /// switched to it during the game).
  bool get hasGtoBots => styles.contains(BotStyle.gto);

  /// Stacks at the start of the next hand.
  late List<int> stacks;
  PokerHand? hand;
  int handNumber = 0;
  int _button = 0;
  bool _recorded = true;

  /// Chips the user has won (or lost, if negative) over all finished hands.
  int heroNet = 0;
  int handsFinished = 0;

  /// The solved whole preflop game (the bots' strategies) for the next or
  /// current hand.
  PreflopAdvisor? advisor;

  /// Every hand of the session, with the user's scored decisions (Guess the GTO mode).
  final List<HandRecord> history = [];

  /// All scored decisions so far.
  Iterable<DecisionScore> get scores => history.expand((h) => h.decisions).map((d) => d.score);

  /// Solved games are needed to score the user or to run GTO bots.
  bool get needsSolver => config.guessGto || hasGtoBots;

  List<PlayerInfo> get players => config.players;

  /// Stacks and button for the hand that [startHand] will deal next. Play
  /// carries on from hand to hand (unless stacks reset every hand), so these
  /// are known as soon as the current hand is decided, before its payout
  /// has been shown.
  ({List<int> stacks, int button}) get upcoming {
    final n = config.playerCount;
    final h = hand;
    final now = h != null && h.isOver ? [for (var seat = 0; seat < n; seat++) h.stackOf(seat)] : stacks;
    final nextStacks = config.resetStacksEachHand
        ? [for (var seat = 0; seat < n; seat++) config.stackOf(seat)]
        // Anyone who went broke buys back in.
        : [for (var seat = 0; seat < n; seat++) now[seat] == 0 ? config.stackOf(seat) : now[seat]];
    final position = config.heroPosition;
    final button = position != null
        ? buttonSeatFor(n, heroSeat, position)
        : (handNumber == 0 ? _button : (_button + 1) % n);
    return (stacks: nextStacks, button: button);
  }

  /// The whole preflop game the next hand will be.
  PreflopSpec get upcomingSpec {
    final next = upcoming;
    return _spec(next.stacks, next.button);
  }

  /// The user's first decision in the next hand if everyone before them
  /// folds: it doesn't depend on anyone's play, so it can be solved ahead
  /// of time. Null when there is no such decision (the big blind wins when
  /// everyone folds).
  PreflopSpec? get upcomingHeroSpec {
    final next = upcoming;
    final order = _spec(next.stacks, next.button, heroHistory: const []).hero;
    if (order == config.playerCount - 1) return null;
    return _spec(next.stacks, next.button,
        heroHistory: List.filled(order, const PreflopAction(PreflopMove.fold)));
  }

  PreflopSpec _spec(List<int> stacksBySeat, int button, {List<PreflopAction>? heroHistory}) =>
      PreflopAdvisor.specFor(
        stacksBySeat: stacksBySeat,
        buttonSeat: button,
        smallBlind: TableConfig.smallBlind,
        bigBlind: TableConfig.bigBlind,
        ante: config.ante,
        raiseRule: config.raiseRule,
        heroSeat: heroHistory == null ? null : heroSeat,
        raiseMultiples: config.preflopSizes,
        history: heroHistory ?? const [],
      );

  PokerHand startHand() {
    if (hand != null && !hand!.isOver) throw StateError('The current hand is not finished');
    if (hand != null) finishHand();
    final next = upcoming;
    stacks = next.stacks;
    _button = next.button;
    handNumber++;
    _recorded = false;
    final h = hand = PokerHand(
      stacks: stacks,
      buttonSeat: _button,
      smallBlind: TableConfig.smallBlind,
      bigBlind: TableConfig.bigBlind,
      ante: config.ante,
      handNumber: handNumber,
      random: _random,
      raiseRule: config.raiseRule,
    );
    history.add(HandRecord(
      handNumber: handNumber,
      holeCards: h.holeCards(heroSeat),
      position: h.positionOf(heroSeat),
    ));
    final blueprint = currentAdvisor, subgames = solveSubgame, streets = solvePostflop;
    final tracker = preflop = needsSolver && blueprint != null && subgames != null
        ? PreflopTracker(
            blueprint: blueprint,
            solveSubgame: subgames,
            heroSeat: heroSeat,
            raiseMultiples: config.preflopSizes,
          )
        : null;
    postflop = tracker != null && streets != null
        ? PostflopTracker(
            preflop: tracker,
            solve: streets,
            bigBlind: TableConfig.bigBlind,
            raiseRule: config.raiseRule,
            heroSeat: heroSeat,
            sizes: config.postflopSizes,
          )
        : null;
    _heroPreflop = null;
    _heroPreflopDone = true;
    return h;
  }

  /// Call after every action (and when the hand starts): on the user's
  /// turn before the flop, starts solving their subgame; when a street
  /// begins, starts solving it.
  Future<void> afterAction() async {
    final h = hand;
    if (h == null) return;
    final tracker = preflop;
    if (tracker != null && h.street == Street.preflop && h.toAct == heroSeat && !h.isOver) {
      final ticket = ++_heroPreflopTicket;
      _heroPreflopDone = false;
      _heroPreflop = tracker.prepare(h).whenComplete(() {
        if (ticket == _heroPreflopTicket) _heroPreflopDone = true;
      });
    }
    await postflop?.update(h);
  }

  /// Completes when the user's latest preflop decision is solved (the bots'
  /// replies to the user come from it too).
  Future<void> get preflopReady => _heroPreflop ?? Future<void>.value();

  /// Whether the user's latest preflop decision is still being solved.
  bool get preflopPending => !_heroPreflopDone;

  /// Whether the player to act needs a solved answer after the flop: the
  /// user in Guess the GTO mode, or a GTO bot.
  bool get needsPostflopAnswer {
    final h = hand;
    if (h == null || h.street == Street.preflop || h.toAct == null || postflop == null) return false;
    return h.toAct == heroSeat ? config.guessGto : styles[h.toAct!] == BotStyle.gto;
  }

  /// Records the result of the finished hand. Calling it again does nothing.
  void finishHand() {
    final h = hand;
    if (h == null || !h.isOver) throw StateError('No finished hand to record');
    if (_recorded) return;
    _recorded = true;
    stacks = [for (var i = 0; i < config.playerCount; i++) h.stackOf(i)];
    final result = h.stackOf(heroSeat) - h.startingStackOf(heroSeat);
    heroNet += result;
    history.last.result = result;
    handsFinished++;
  }

  bool get isHeroTurn => hand?.toAct == heroSeat;

  /// The solved whole game for the current hand, if it is ready (and
  /// really is this hand's game).
  PreflopAdvisor? get currentAdvisor {
    final h = hand, a = advisor;
    if (h == null || a == null) return null;
    final spec = _spec([for (var s = 0; s < h.playerCount; s++) h.startingStackOf(s)], h.buttonSeat);
    return a.tree.spec == spec ? a : null;
  }

  /// The GTO answer for the user's current decision (Guess the GTO mode).
  SpotStrategy? heroSpot() {
    final h = hand;
    if (!config.guessGto || h == null || h.toAct != heroSeat) return null;
    return h.street == Street.preflop ? preflop?.spotFor(h) : postflop?.spotFor(h);
  }

  /// Whether the bot to act plays the solver's strategy right now: GTO bots
  /// always (where a solution exists), and every bot before the flop in
  /// Guess the GTO mode, so the user's spots come from GTO play.
  bool get botPlaysGto {
    final h = hand;
    if (h == null || h.toAct == null) return false;
    return styles[h.toAct!] == BotStyle.gto || (config.guessGto && h.street == Street.preflop);
  }

  /// Asks the bot in the seat to act to make its decision.
  PlayerAction botDecision() {
    final h = hand!;
    final seat = h.toAct!;
    final bot = _bots[seat];
    if (bot == null) throw StateError("It is the user's turn");
    if (botPlaysGto) {
      final move = h.street == Street.preflop ? preflop?.sample(h, _random) : postflop?.sample(h, _random);
      if (move != null) return move;
    }
    final move = bot.decide(h, seat);
    // Keep the hand on the solved lines: use the nearest size the solver has.
    return h.street == Street.preflop ? move : (postflop?.snap(h, move) ?? move);
  }
}
