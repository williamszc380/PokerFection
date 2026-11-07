import 'dart:math';

import '../bots/bot.dart';
import '../engine/actions.dart';
import '../engine/cards.dart';
import '../engine/events.dart';
import '../engine/poker_hand.dart';
import '../engine/positions.dart';
import '../engine/rules.dart';
import '../gto/postflop/postflop_tracker.dart';
import '../gto/range_info.dart';
import '../gto/preflop/preflop_advisor.dart';
import '../gto/preflop/preflop_tracker.dart';
import '../gto/preflop/preflop_tree.dart';
import '../gto/spot_strategy.dart';
import '../online/mirror.dart';
import 'history.dart';
import 'table_rules.dart';

export 'history.dart';

/// One player at the table.
class PlayerInfo {
  const PlayerInfo({
    required this.name,
    required this.stackBb,
    this.style,
    this.isHero = false,
    this.remote = false,
    this.isBot = false,
  });

  final String name;

  /// Starting stack in big blinds.
  final int stackBb;

  /// The bot's style; null means a random one, picked when the table starts
  /// (and unknown to the user unless styles are shown).
  final BotStyle? style;
  final bool isHero;

  /// Online: someone else plays this seat, on another device (a person, or
  /// a bot run by the host's device). Nothing here decides for it, and its
  /// cards are unknown until shown.
  final bool remote;

  /// Online, for a remote seat: a bot plays it rather than a person.
  final bool isBot;

  PlayerInfo copyWith({int? stackBb}) => PlayerInfo(
      name: name, stackBb: stackBb ?? this.stackBb, style: style, isHero: isHero, remote: remote, isBot: isBot);

  /// Same player with another style (null for random).
  PlayerInfo withStyle(BotStyle? style) =>
      PlayerInfo(name: name, stackBb: stackBb, style: style, isHero: isHero, remote: remote, isBot: isBot);
}

/// The starting situation the user picks before playing.
class TableConfig {
  const TableConfig({
    required this.players,
    this.heroPosition,
    this.ante = 0,
    this.resetStacksEachHand = false,
    this.guessGto = false,
    this.advanced = false,
    this.showStyles = false,
    this.showHands = false,
    this.raiseRule = RaiseRule.standard,
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
    bool advanced = false,
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
        advanced: advanced,
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

  /// Grade the user's play against GTO (GTO Training).
  final bool guessGto;

  /// Advanced training: at every decision the user sets how often GTO takes
  /// each action and gets a score. Simple training (the default): they just
  /// play, and GTO's answer shows after a mistake or a blunder.
  final bool advanced;

  /// Training aids, only available in Guess the GTO mode: show each bot's
  /// style, and show their cards face up during the hand.
  final bool showStyles;
  final bool showHands;

  /// How small a raise may be.
  final RaiseRule raiseRule;


  bool get stylesVisible => guessGto && showStyles;
  bool get handsVisible => guessGto && showHands;

  int get playerCount => players.length;
  int stackOf(int seat) => players[seat].stackBb * bigBlind;

  /// The same table with other players (online, the line-up changes
  /// between hands).
  TableConfig withPlayers(List<PlayerInfo> players) => TableConfig(
        players: List.unmodifiable(players),
        heroPosition: heroPosition,
        ante: ante,
        resetStacksEachHand: resetStacksEachHand,
        guessGto: guessGto,
        advanced: advanced,
        showStyles: showStyles,
        showHands: showHands,
        raiseRule: raiseRule,
      );
}

/// A series of hands at one table. The user sits in seat 0 ([heroSeat]),
/// or, online, nowhere: a spectator's device follows the hands with no
/// user at the table ([hero] is -1), for the coach, and the host's for its
/// GTO bots while the host watches.
class TableSession {
  TableSession(this.config, {Random? random, this.solvePostflop, this.solveSubgame})
      : _random = random ?? Random() {
    // Nothing here plays the user's seat or a remote one: they get no style.
    styles = [
      for (final p in config.players) p.isHero || p.remote ? null : (p.style ?? _randomStyle()),
    ];
    hiddenStyles = [for (final p in config.players) !p.isHero && !p.remote && p.style == null];
    if (config.handsVisible) {
      revealedSeats.addAll([
        for (var s = 0; s < config.playerCount; s++)
          if (!config.players[s].isHero && !config.players[s].remote) s,
      ]);
    }
    _bots = [for (final s in styles) s == null ? null : Bot(s, _random)];
    stacks = [for (var seat = 0; seat < config.playerCount; seat++) config.stackOf(seat)];
    _button = _random.nextInt(config.playerCount);
  }

  /// Where the user sits at a table on the device (and online, when they
  /// play the hand).
  static const heroSeat = 0;

  /// The user's seat in the current line-up: [heroSeat], or -1 when nobody
  /// at the table is the user (online, a spectator's line-up).
  int get hero => players.isNotEmpty && players[heroSeat].isHero ? heroSeat : -1;

  /// The table. Online, its players change between hands (see
  /// [changeLineup]).
  TableConfig config;
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

  /// Changes one bot's style; null gives it a random style kept secret.
  void setStyle(int seat, BotStyle? style) {
    if (players[seat].isHero || players[seat].remote) return;
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
      for (final c in [...h.board, if (hero >= 0 && seat != hero) ...h.holeCards(hero)]) c.index,
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

  /// Grade the user's play against GTO (see [TableConfig.guessGto]).
  /// Online, the host turns this help on or off between hands.
  late bool guessGto = config.guessGto;

  /// Advanced training in the current hand (see [TableConfig.advanced]).
  late bool advanced = config.advanced;
  bool? _nextAdvanced;

  /// The level the next hand will use.
  bool get advancedNext => _nextAdvanced ?? advanced;

  /// Switches between simple and advanced training: now between hands, or
  /// from the next hand during one.
  void setAdvanced(bool value) {
    final h = hand;
    if (h != null && !h.isOver) {
      _nextAdvanced = value;
    } else {
      advanced = value;
      _nextAdvanced = null;
    }
  }

  /// Stacks the user set during the game (chips, by seat), for the next
  /// hand; cleared once it is dealt.
  final Map<int, int> stackEdits = {};

  /// Stacks the user set, which also become those players' stacks whenever
  /// stacks are reset (every hand, or after going broke).
  final Map<int, int> _startingStacks = {};

  int _startingStackOf(int seat) => _startingStacks[seat] ?? config.stackOf(seat);

  /// Gives [seat] a stack of [chips] from the next hand on.
  void setStack(int seat, int chips) {
    stackEdits[seat] = chips;
    _startingStacks[seat] = chips;
  }
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

  /// The score (0-100) of every decision so far.
  Iterable<int> get points => history.expand((h) => h.decisions).map((d) => d.points);

  /// Online, on a spectator's device: the coach answers for whoever acts,
  /// when their cards may be seen (see [spotToAct]). It needs the solves a
  /// player with help gets: the whole preflop game, and heads-up streets.
  bool coaching = false;

  /// Solved games are needed to score the user, to run GTO bots, or for a
  /// spectator's coach.
  bool get needsSolver => guessGto || hasGtoBots || (hero < 0 && coaching);

  /// Who sits where. Online, the players change between hands (see
  /// [changeLineup]).
  late List<PlayerInfo> players = List.of(config.players);

  /// Between hands, a whole other table (a drill deals each spot at its
  /// own): [table]'s players and rules, from the next hand (see
  /// [changeLineup]).
  void changeTable(TableConfig table) {
    config = table;
    changeLineup(table.players);
  }

  /// Online, between hands: the next hand is played by [lineup] (the user
  /// in seat 0, or nobody: a spectator's line-up), maybe more or fewer
  /// players than the last. [from] gives,
  /// for each new seat, the old seat of the same player (who keeps their
  /// bot style), or null for someone new. The last hand is recorded (if it
  /// ended) and put away, or dropped if it didn't (a drill stops at the
  /// user's decision); the next one is dealt with [startHand].
  void changeLineup(List<PlayerInfo> lineup, {List<int?> from = const []}) {
    if (lineup.isEmpty || lineup.skip(1).any((p) => p.isHero)) throw ArgumentError('The user sits in seat 0');
    final h = hand;
    if (h != null && h.isOver) finishHand();
    hand = null;
    detachTrackers();
    final oldStyles = styles, oldHidden = hiddenStyles, oldBots = _bots;
    int? old(int seat) => seat < from.length ? from[seat] : null;
    config = config.withPlayers(lineup);
    players = List.of(lineup);
    styles = [
      for (final (seat, p) in lineup.indexed)
        if (old(seat) case final o?) oldStyles[o] else (p.isHero || p.remote ? null : (p.style ?? _randomStyle())),
    ];
    hiddenStyles = [
      for (final (seat, p) in lineup.indexed)
        if (old(seat) case final o?) oldHidden[o] else !p.isHero && !p.remote && p.style == null,
    ];
    _bots = [
      for (final (seat, style) in styles.indexed)
        if (old(seat) case final o?) oldBots[o] else (style == null ? null : Bot(style, _random)),
    ];
    revealedSeats.clear();
    stackEdits.clear();
    _startingStacks.clear();
    stacks = [for (var seat = 0; seat < lineup.length; seat++) config.stackOf(seat)];
    _button = 0;
  }

  /// Online: the next hand's stacks and button as the server announced
  /// them, which [upcoming] gives instead of working them out (a drill
  /// sets them too).
  NextHand? announced;

  /// A drill: the cards the next hand is dealt (every player's, by seat,
  /// and the board so far); the rest come from the deck as usual.
  ({Map<int, List<PlayingCard>> holeCards, List<PlayingCard> board})? preset;

  /// Stacks and button for the hand that [startHand] will deal next. Play
  /// carries on from hand to hand (unless stacks reset every hand), so these
  /// are known as soon as the current hand is decided, before its payout
  /// has been shown.
  NextHand get upcoming {
    final known = announced;
    if (known != null) return known;
    final n = config.playerCount;
    final h = hand;
    final now = h != null && h.isOver ? [for (var seat = 0; seat < n; seat++) h.stackOf(seat)] : stacks;
    final next = nextHandSetup(
      stacks: now,
      startingStacks: [for (var seat = 0; seat < n; seat++) _startingStackOf(seat)],
      button: _button,
      firstHand: handNumber == 0,
      resetStacks: config.resetStacksEachHand,
      edits: stackEdits,
    );
    final position = config.heroPosition;
    return position == null ? next : (stacks: next.stacks, button: buttonSeatFor(n, heroSeat, position));
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
    if (hero < 0) return null;
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
        history: heroHistory ?? const [],
      );

  /// Deals the next hand. Online, [deal] is the server's hand instead (see
  /// RemoteDeal), and this session follows a mirror of it: a hand still
  /// running is dropped (the device fell behind, or reconnected), and the
  /// same hand dealt again (a fresh copy after reconnecting) keeps its
  /// record and scored decisions. The session follows the hand for GTO
  /// answers itself, with its own solvers (see [startHandWith]).
  PokerHand startHand([RemoteDeal? deal]) => startHandWith(deal: deal);

  /// [startHand], with a choice of how the hand is followed for GTO answers.
  /// With [track], the session makes the hand's trackers (see
  /// [trackersFor]: [subgames] and [streets] stand in for the session's
  /// own solvers in this hand, and [needed] says which streets to solve).
  /// Without, it makes none: on the device, a hand follower does, behind
  /// the table, and hands them over with [useTrackers].
  PokerHand startHandWith({
    RemoteDeal? deal,
    bool track = true,
    PreflopSubgameSolve? subgames,
    PostflopSolve? streets,
    bool Function(PokerHand hand)? needed,
  }) {
    final old = hand;
    // The user's record of the same hand: a fresh copy of it (with no user
    // at the table there is none).
    final again = deal != null && deal.handNumber == handNumber && history.lastOrNull?.handNumber == handNumber;
    if (old != null && !old.isOver && deal == null) throw StateError('The current hand is not finished');
    if (old != null && old.isOver && !again) finishHand();
    if (again && _recorded) {
      // Counted already: it counts again when the copy ends.
      heroNet -= history.last.result ?? 0;
      handsFinished--;
      history.last.result = null;
    }
    advanced = advancedNext;
    _nextAdvanced = null;
    _recorded = false;
    final known = announced, cards = preset;
    announced = null;
    preset = null;
    final PokerHand h;
    if (deal == null) {
      final next = known ?? upcoming;
      stacks = next.stacks;
      stackEdits.clear();
      _button = next.button;
      handNumber++;
      h = hand = PokerHand(
        stacks: stacks,
        buttonSeat: _button,
        smallBlind: TableConfig.smallBlind,
        bigBlind: TableConfig.bigBlind,
        ante: config.ante,
        handNumber: handNumber,
        random: _random,
        raiseRule: config.raiseRule,
        holeCards: cards?.holeCards ?? const {},
        board: cards?.board ?? const [],
      );
    } else {
      // The server sets the stacks: edits made here don't apply.
      stacks = List.of(deal.stacks);
      stackEdits.clear();
      _button = deal.buttonSeat;
      handNumber = deal.handNumber;
      h = hand = deal.build(
        smallBlind: TableConfig.smallBlind,
        bigBlind: TableConfig.bigBlind,
        ante: config.ante,
        raiseRule: config.raiseRule,
      );
    }
    if (!again && hero >= 0) {
      history.add(HandRecord(
        handNumber: handNumber,
        holeCards: h.holeCards(hero),
        position: h.positionOf(hero),
        advanced: advanced,
      ));
    }
    final blueprint = currentAdvisor;
    final trackers = track && needsSolver && blueprint != null
        ? trackersFor(h, blueprint, subgames: subgames, streets: streets, needed: needed)
        : (preflop: null, postflop: null);
    useTrackers(trackers.preflop, trackers.postflop);
    return h;
  }

  /// The trackers that follow [h] (this session's hand, or a copy of it
  /// with the same deal) for GTO answers: the bots' strategies come from
  /// [blueprint], the hand's solved whole game, and the user's subgames and
  /// the streets from [subgames] and [streets] (by default this session's
  /// solvers). [needed] says whether a street is worth solving (see
  /// [streetNeeded]); null solves every one. None when [blueprint] isn't
  /// [h]'s game, or there is no solver for subgames; no postflop tracker
  /// without one for streets.
  ({PreflopTracker? preflop, PostflopTracker? postflop}) trackersFor(
    PokerHand h,
    PreflopAdvisor blueprint, {
    PreflopSubgameSolve? subgames,
    PostflopSolve? streets,
    bool Function(PokerHand hand)? needed,
  }) {
    final solveSubgames = subgames ?? solveSubgame, solveStreets = streets ?? solvePostflop;
    if (solveSubgames == null || blueprint.tree.spec != specOf(h)) return (preflop: null, postflop: null);
    final pre = PreflopTracker(
      blueprint: blueprint,
      solveSubgame: solveSubgames,
      heroSeat: hero,
      handNumber: h.handNumber,
    );
    final post = solveStreets == null
        ? null
        : PostflopTracker(
            preflop: pre,
            solve: solveStreets,
            bigBlind: h.bigBlind,
            raiseRule: h.raiseRule,
            heroSeat: hero,
            needed: needed,
          );
    return (preflop: pre, postflop: post);
  }

  /// Follows the current hand with [preflop] and [postflop] (on the device,
  /// its follower's, once the hand's whole game is solved): the range
  /// sheet, the notices and the answers read them.
  void useTrackers(PreflopTracker? preflop, PostflopTracker? postflop) {
    this.preflop = preflop;
    this.postflop = postflop;
    _heroPreflopTicket++;
    _heroPreflop = null;
    _heroPreflopDone = true;
  }

  /// The whole preflop game [h] is: its starting stacks, button, blinds,
  /// ante and raise rule (the key of its blueprint).
  PreflopSpec specOf(PokerHand h) => PreflopAdvisor.specFor(
        stacksBySeat: [for (var s = 0; s < h.playerCount; s++) h.startingStackOf(s)],
        buttonSeat: h.buttonSeat,
        smallBlind: h.smallBlind,
        bigBlind: h.bigBlind,
        ante: h.ante,
        raiseRule: h.raiseRule,
      );

  /// Whether the trackers follow [h]: answers and moves read from them
  /// belong to that hand only.
  bool _tracks(PokerHand h) {
    final tracker = preflop;
    return tracker != null && (tracker.handNumber ?? hand?.handNumber) == h.handNumber;
  }

  /// Whether anyone needs [h]'s next street solved: a GTO bot still in it,
  /// the user still in it in Guess the GTO mode (to be graded), or, with no
  /// user at the table, a spectator's coach.
  bool streetNeeded(PokerHand h) =>
      hasGtoBotIn(h) || (hero < 0 && coaching) || (guessGto && hero >= 0 && !h.isFolded(hero));

  /// Whether a GTO bot is still in [h].
  bool hasGtoBotIn(PokerHand h) {
    for (var s = 0; s < h.playerCount && s < styles.length; s++) {
      if (styles[s] == BotStyle.gto && !h.isFolded(s)) return true;
    }
    return false;
  }

  /// Stops following the current hand for answers (online, to catch up
  /// with the server quickly when the next hand is already dealt): no
  /// more solving, and no GTO answers or ranges in it.
  void detachTrackers() => useTrackers(null, null);

  /// Call after every action (and when the hand starts): on the user's
  /// turn before the flop, starts solving their subgame; when a street
  /// begins, starts solving it.
  Future<void> afterAction() async {
    final h = hand;
    if (h == null) return;
    final tracker = preflop;
    if (tracker != null && h.street == Street.preflop && hero >= 0 && h.toAct == hero && !h.isOver) {
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
  /// user in Guess the GTO mode, a GTO bot, or (with no user at the table)
  /// anyone, for a spectator's coach.
  bool get needsPostflopAnswer {
    final h = hand;
    if (h == null || h.street == Street.preflop || h.toAct == null || postflop == null) return false;
    if (hero < 0 && coaching) return true;
    return h.toAct == hero ? guessGto : styles[h.toAct!] == BotStyle.gto;
  }

  /// Records the result of the finished hand. Calling it again does nothing.
  void finishHand() {
    final h = hand;
    if (h == null || !h.isOver) throw StateError('No finished hand to record');
    if (_recorded) return;
    _recorded = true;
    stacks = [for (var i = 0; i < config.playerCount; i++) h.stackOf(i)];
    // Only the user's hands count (none while nobody at the table is the user).
    final record = history.lastOrNull;
    if (hero < 0 || record == null || record.handNumber != h.handNumber) return;
    final result = h.stackOf(hero) - h.startingStackOf(hero);
    heroNet += result;
    record.result = result;
    handsFinished++;
  }

  bool get isHeroTurn => hero >= 0 && hand?.toAct == hero;

  /// The solved whole game for the current hand, if it is ready (and
  /// really is this hand's game).
  PreflopAdvisor? get currentAdvisor {
    final h = hand, a = advisor;
    if (h == null || a == null) return null;
    return a.tree.spec == specOf(h) ? a : null;
  }

  /// The GTO answer for the user's current decision (Guess the GTO mode).
  SpotStrategy? heroSpot() {
    final h = hand;
    return h == null ? null : spotAt(h);
  }

  /// The GTO answer for the user's decision [h] is at (Guess the GTO mode):
  /// the current hand, or a copy of it that the trackers follow (on the
  /// device, its follower, standing at a decision played already). Null
  /// until it is solved, or when it isn't the user's turn in [h].
  SpotStrategy? spotAt(PokerHand h) {
    if (!guessGto || hero < 0 || h.toAct != hero || !_tracks(h)) return null;
    return h.street == Street.preflop ? preflop?.spotFor(h) : postflop?.spotFor(h);
  }

  /// Online, for a spectator's coach: GTO's answer for whoever acts, if
  /// their cards may be seen ([visible], the seats shown face up) and this
  /// device knows them. Before the flop, the solved whole game's answer
  /// (the blueprint, see PreflopTracker.blueprintSpotFor); after it, the
  /// street's solve, heads-up only (with more players there is none: see
  /// PostflopTracker.unavailable). Null otherwise, or until it is solved.
  SpotStrategy? spotToAct(Set<int> visible) {
    final h = hand, seat = hand?.toAct;
    if (h == null || seat == null || h.isOver || !visible.contains(seat) || !h.knows(seat)) return null;
    return h.street == Street.preflop ? preflop?.blueprintSpotFor(h) : postflop?.spotFor(h);
  }

  /// Whether the bot to act plays the solver's strategy right now: GTO bots
  /// always (where a solution exists), and every bot before the flop in
  /// Guess the GTO mode, so the user's spots come from GTO play.
  bool get botPlaysGto {
    final h = hand;
    if (h == null || h.toAct == null) return false;
    return playsFromSolve(h, h.toAct!);
  }

  /// Whether the bot in [seat] plays from a solve in [on] right now (see
  /// [botPlaysGto]; [style] as in [decisionOn]): the bots that may be worth
  /// a short wait for theirs before [decisionOn] falls back.
  bool playsFromSolve(PokerHand on, int seat, {BotStyle? style}) {
    final playing = style ?? (seat < styles.length ? styles[seat] : null);
    return playing == BotStyle.gto || (guessGto && on.street == Street.preflop && playing != null);
  }

  /// Asks the bot in the seat to act to make its decision.
  PlayerAction botDecision() {
    final h = hand!;
    return decisionOn(h, h.toAct!);
  }

  /// The move of the bot in [seat], to act in [on] (the current hand, or
  /// online, on the host, the table's copy of it when this session is
  /// behind), at once: it never waits for a solve. [style] is the bot's
  /// style when this session's seats may not be [on]'s (online); by
  /// default the session's own bot plays.
  ///
  /// It plays the best thing it has, and every choice keeps the hand on
  /// the solved lines, so a move made without its solve never stops a
  /// later decision from being answered:
  ///  1. before the flop, a bot that plays GTO there (see [botPlaysGto]):
  ///     a move drawn from the hand's solves when the trackers follow
  ///     [on] (the user's latest subgame solved so far, or else the whole
  ///     game), or else its own move. Either way, fitted to the bots' menu
  ///     at that point (see `fitToMenu`): the actions every solve of the
  ///     hand has there, or will have once it is done;
  ///  2. before the flop, any other bot: its own move, as always;
  ///  3. after the flop, a GTO bot: a move drawn from the street's solve,
  ///     once it is done and the trackers follow [on];
  ///  4. otherwise its own move, its bet moved to the nearest size the
  ///     street's solve has, or will have once it is done (see
  ///     PostflopTracker.snap): a raise the street has no room for would
  ///     take the hand off the lines. With no tracker for [on] yet, the
  ///     sizes come from the hand alone, whenever solving is needed.
  PlayerAction decisionOn(PokerHand on, int seat, {BotStyle? style}) {
    if (on.toAct != seat) throw StateError('Seat $seat is not to act');
    final bot = style != null ? Bot(style, _random) : (seat < _bots.length ? _bots[seat] : null);
    if (bot == null) throw StateError(seat == hero ? "It is the user's turn" : 'Seat $seat is played elsewhere');
    assert(on.knows(seat), 'A bot needs to know its cards');
    final tracked = _tracks(on), gtoBot = bot.style == BotStyle.gto;
    if (on.street == Street.preflop) {
      if (!playsFromSolve(on, seat, style: bot.style)) return bot.decide(on, seat);
      final move = (tracked ? preflop?.sample(on, _random) : null) ?? bot.decide(on, seat);
      return fitToMenu(move, PreflopTree.botMenuAt(PreflopTracker.specAt(on)), on.legalActions());
    }
    if (gtoBot && tracked) {
      if (postflop?.sample(on, _random) case final move?) return move;
    }
    final move = bot.decide(on, seat);
    // Keep the hand on the solved lines: use the nearest size the solver has.
    if (tracked) return postflop?.snap(on, move) ?? move;
    return needsSolver
        ? PostflopTracker.snapToBetting(on, move, heroSeat: hero, bigBlind: on.bigBlind, raiseRule: on.raiseRule)
        : move;
  }
}
