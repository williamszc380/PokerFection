part of 'table_controller.dart';

/// Something to tell the user above their choices at an online table.
enum OnlineNotice {
  /// Their time ran out: the server checked or folded for them.
  timesUp,

  /// The server refused their move: choose again.
  refused,

  /// This device's copy of the hand no longer matches the server's.
  outOfSync,
}

/// A short message shown for a moment at an online table: what a player
/// did that everyone is told ([note]), that the host changed the rules,
/// another player's chat message ([chat]), that the host removed a player
/// ([removed]: their name), or that the game is over ([over]: who won).
class OnlineToast {
  const OnlineToast.note(HandNote this.note) : over = null, chat = null, removed = null;
  const OnlineToast.rulesChanged() : note = null, over = null, chat = null, removed = null;
  const OnlineToast.chat(ChatLine this.chat) : note = null, over = null, removed = null;
  const OnlineToast.removed(String this.removed) : note = null, over = null, chat = null;
  const OnlineToast.gameOver(GameOver this.over) : note = null, chat = null, removed = null;

  final HandNote? note;
  final ChatLine? chat;
  final String? removed;
  final GameOver? over;
}

/// What a spectator's coach shows for the player in [seat] ([name]) at
/// their turn: GTO's answer ([spot]); or "—" when their cards are [hidden]
/// from this device (a bot's, unless the host lets spectators see them);
/// or that it is being worked out ([thinking]); or that there is none
/// ([none] says why, when known).
class SpectatorCoach {
  const SpectatorCoach({
    required this.seat,
    required this.name,
    this.spot,
    this.hidden = false,
    this.thinking = false,
    this.none,
  });

  final int seat;
  final String name;
  final SpotStrategy? spot;
  final bool hidden;
  final bool thinking;
  final NoAnswer? none;
}

/// The players of a hand, by this device's seat: their room seats, as the
/// server sent them, and as the table and the session play them; whether
/// the user only watches it (not dealt in), and if so whether as a
/// spectator (no seat of theirs: they see the people's cards, and the
/// coach) rather than from a seat (out of chips, or sitting out); and
/// whether the host's device plays a GTO bot in it (its session then
/// follows the hand for the bot, even while the host watches).
typedef _Lineup = ({
  List<int> roomSeats,
  List<SeatInfo> infos,
  List<PlayerInfo> players,
  bool watching,
  bool spectating,
  bool gtoBots,
});

/// Plays a table online. The server deals, checks every move and keeps the
/// clocks; this follows it, and sends the user's moves (and on the host's
/// device, the bots').
///
/// The user sits in seat 0 as at a table on the device: the server's seats
/// are turned around (see SeatMap), so everything else works unchanged.
/// Only the seats taken play a hand, so the number of players can change
/// from one hand to the next: the session takes the new line-up as soon as
/// the server announces it (to solve the next hand), the table when the
/// hand is dealt (until then it shows the last one's end).
/// Each hand is followed in two copies built from the server's messages
/// (see mirror.dart):
/// - the table's own ([_mirror]), moved on as each message is handled: the
///   user's choices come from it, at once;
/// - the session's (TableSession.hand), moved on one action at a time,
///   waiting for its trackers after each (the order they need). It gives
///   the help (GTO's answer, ranges) and on the host's device plays the
///   GTO bots; it may fall behind while they solve, but never holds up the
///   table: the choices show at once, GTO's answer when it is ready.
///
/// Nothing at the table waits for a solve, on any device. Each device says
/// Ready as soon as it has shown the last hand, and the server deals then
/// (3 s more at most: OnlineTiming.readyWait). Each hand's solves are
/// claimed by its own SolveOwner, one solve at a time per device, the most
/// urgent first; the next hand's solves start once its line-up is
/// announced. The host's bots wait a moment for theirs ([_playBot]), then
/// play the best they have, which keeps the hand on the solved lines for
/// everyone's help. Every device solves for itself, from the cards it may
/// see: nothing about solves is sent between devices.
///
/// With help on (the host picks it for the whole table), moves are sent as
/// soon as they are chosen, and the score shows without holding the table.
/// Show GTO works at any time: pressed before GTO's answer has come, the
/// answer is solved first and shows when it does, and the choices keep
/// working meanwhile (the turn's clock runs as always). A pre-action the
/// user picked while others acted is sent the moment their turn opens.
///
/// Neither copy's cards are shown: the table only plays the server's
/// events, with the user's own cards and the hands shown at the end. The
/// messages are handled one at a time, in order, each played out on the
/// table before the next (faster when several are waiting).
///
/// When the connection drops, the client gets it back by itself and the
/// server sends a snapshot of the hand: what was missed is played (or, if
/// this device's copy can't simply go on, the whole hand again, at once),
/// and a move the user made meanwhile is sent again if still due. A copy
/// that stops matching the server's asks for a snapshot too.
///
/// A user [watching] a hand isn't in it: its seats are the server's, and
/// nobody is the user (every screen check says so: no choices, no seat of
/// theirs). Watching from a seat (out of chips, or sitting out), the
/// session sits the hand out. A [spectating] user (everyone enters a room
/// so, the host too) sees every person's cards (the bots' too when the
/// host lets spectators: [_visible]), and the session follows the hand
/// with nobody as the user ([follows]): for the coach ([coachOn], see
/// [spectatorCoach]), worked out on this device from the cards it may
/// show (its solves come first, as an answer the user looks at does), and
/// on the host's device for its GTO bots, which the host's device keeps
/// playing by the solver while the host watches, from a seat or as a
/// spectator. Players out of chips, or
/// who sit out, keep their places at the table ([TableViewState.others]),
/// the user's at the bottom.
/// Once the game is over ([gameOver]), nothing more is played here: the
/// app's room (RoomService) takes the connection back ([handBack]).
class OnlineTableController extends TableController {
  /// The table set up by [first], the line-up of a hand; [start] is the
  /// first message to follow, if not [first] itself (a snapshot, for a
  /// player who comes back during a hand).
  OnlineTableController(this.client, NextHand first, {ServerMessage? start, super.speed, super.random, super.solutions})
    : seats = _seatMapOf(first),
      _help = first.help,
      _nextHelp = first.help,
      coachOn = defaultCoachOn(),
      super(_configFor(client, first)) {
    _shownLineup = _lineupOf(first, client);
    _viewRoomSeats = _sessionRoomSeats = _shownLineup.roomSeats;
    // The first message is the line-up (which made the table), or the snapshot it came with.
    _receive(start ?? first);
    _statusChanges = client.changes.listen((_) => _onStatus());
    // Others' chat messages show at once (they don't wait for the hand on screen).
    _chatLines = client.said.listen((line) {
      if (!line.you) _toast(OnlineToast.chat(line));
    });
    final room = client.room;
    if (room != null) _onRoom(room);
    client.attach(_receive);
  }

  final OnlineClient client;

  /// The server's hand seats and this device's, for the hand being played
  /// (from its line-up on: the next one's).
  SeatMap seats;

  /// The room seat of each seat on screen, and in the session.
  late List<int> _viewRoomSeats, _sessionRoomSeats;

  /// The room seats of those at the table who don't play the hand on screen.
  List<int> _otherRoomSeats = const [];

  /// The user isn't dealt in the hand on screen: they watch it (from a
  /// seat, out of chips or sitting out, or as a [spectating] member).
  bool watching = false;

  /// The user watches the hand on screen as a spectator: no seat of theirs
  /// (or one they only wait for), every person's cards face up.
  bool spectating = false;

  /// The spectator's coach is on (the Coach chip, on this device only and
  /// not kept): see [defaultCoachOn].
  bool coachOn;

  /// The table is on screen (TableScreen says so). The app's room keeps
  /// the game going while the user is elsewhere (the host's bots, its
  /// Ready); meanwhile the table makes no sound and a spectator's coach
  /// rests (from the next hand once back).
  bool get onScreen => _onScreen;
  bool _onScreen = false;
  set onScreen(bool on) {
    if (_onScreen == on) return;
    _onScreen = on;
    if (_disposed) return;
    _sessionJob(() async => _coaching(coachOn && spectating && _onScreen));
  }

  /// Each sound the table would play now (tests listen).
  @visibleForTesting
  static void Function(SoundEffect effect)? debugOnSound;

  /// The seats of the hand on screen whose cards this device may show
  /// (by this device's seat): a spectator's, the seats whose cards came
  /// in its deal (people's, and the bots' when the host lets spectators
  /// see them), never the host's own copy of the bots' cards. The coach
  /// answers only for these.
  final Set<int> _visible = {};

  /// The user sat out since they last played a hand: back, they watch until
  /// they are dealt in.
  bool _satOut = false;

  /// The game is over (once its last hand is shown): who won.
  GameOver? gameOver;

  /// The app's room took the connection back: the table leaves it open.
  bool _handedBack = false;

  /// The next hand's players, until it is dealt.
  _Lineup? _nextLineup;
  late final StreamSubscription<void> _statusChanges;
  late final StreamSubscription<ChatLine> _chatLines;
  final StreamController<OnlineToast> _toasts = StreamController.broadcast();

  /// Messages not handled yet, with when each came in.
  final List<(ServerMessage, DateTime)> _inbox = [];
  bool _pumping = false;

  /// The table's own copy of the current hand.
  PokerHand? _mirror;
  int _handNumber = 0;

  /// Batches of the hand on screen played so far (the deal is the first),
  /// and of the session's hand.
  int _shownBatches = 0, _sessionBatches = 0;

  /// Playing a hand again from a snapshot: at once, without sounds.
  bool _replaying = false;

  /// The user's move at their open turn, until the server plays it: sent
  /// again after reconnecting, if the turn is still open.
  ({int hand, int turnId, PlayerAction action})? _sentMove;

  /// The hand this device last asked a fresh copy of (once a hand).
  int _resyncedHand = -1;

  /// The newest turn the server opened (hand and turn), maybe not shown
  /// yet: a bot's move for an older one is dropped.
  (int, int) _latest = (0, 0);

  /// Completes (and is replaced) when the server deals a new hand.
  Completer<void> _dealt = Completer();

  /// The user's open turn, while their choices show or their move is on
  /// its way.
  Turn? _myTurn;

  /// The bots' cards, by hand (on the host's device).
  final Map<int, Map<int, List<PlayingCard>>> _botCards = {};

  /// The session's copy of the hand is moved on one job at a time.
  Future<void> _sessionTail = Future.value();

  /// The session's copy went wrong in this hand: the bots use their rules.
  bool _sessionBroken = false;

  /// The session's hand's solves (see SolveOwner): claimed while a bot
  /// waits for its solve, while the user has Show GTO on, and while a
  /// spectator's coach is on; finished once the hand is over on the table,
  /// let go of when the next hand is dealt.
  SolveOwner? _owner;

  /// The spectator's coach's claim on the session's hand, while it is on.
  SolveClaim? _coachClaim;

  /// The help in the hand on screen, and in the next one.
  HelpLevel _help, _nextHelp;

  /// GTO's answer for one of the user's turns (null: there is none), once
  /// worked out.
  ({int hand, int turnId, SpotStrategy? spot})? _answer;

  /// A message for the user above their choices (or while waiting).
  OnlineNotice? notice;

  /// The host is away (their connection dropped): nobody plays the bots,
  /// which check or fold, until the host comes back.
  bool hostAway = false;

  /// Between hands, too few seats are taken: the game waits for players.
  bool paused = false;

  /// This device's copy of the hand stopped matching the server's (in
  /// this hand: the next starts afresh).
  bool outOfSync = false;

  /// When the next hand is dealt at the latest.
  DateTime? nextHandAt;

  /// The user showed their cards after the hand on screen.
  bool _shownMine = false;

  /// The decision (hand and turn) everyone was last told the user pressed
  /// Show GTO at.
  (int, int)? _helpSent;

  /// The rules as last sent, to tell when the host changes them.
  RoomSettings? _lastRules;

  String get roomCode => client.room?.code ?? client.welcome?.code ?? '';

  /// The hand on screen.
  int get handNumber => _handNumber;

  /// The room's rules, as the host set them (with the changes for the next
  /// hand): everyone sees them.
  RoomSettings get rules => client.room?.settings ?? const RoomSettings();

  /// The host shows the bots' styles to everyone.
  bool get showStyles => rules.showStyles;
  bool get isHost => client.isHost;

  /// What everyone is told for a moment (see [OnlineToast]).
  Stream<OnlineToast> get toasts => _toasts.stream;

  /// The table is over for this device: the room closed, or the
  /// connection was lost.
  bool get ended => client.status == OnlineStatus.closed || connectionLost;

  /// The connection dropped and couldn't be got back (rather than the room
  /// closing).
  bool get connectionLost => client.status == OnlineStatus.lost;

  /// The connection dropped: getting it back (the table carries on, and
  /// catches up once back).
  bool get reconnecting => client.status == OnlineStatus.reconnecting;

  /// The help everyone gets in the hand on screen (the host picks it, from
  /// the next hand).
  HelpLevel get help => _help;

  /// The user's room seat, as the room shows it.
  SeatInfo? get _mine {
    final seats = client.room?.seats, seat = client.mySeat;
    return seats == null || seat == null || seat >= seats.length ? null : seats[seat];
  }

  /// The user is out of chips (from the end of the hand they lost them
  /// in): they watch until they rebuy or the game ends.
  bool get out => !ended && gameOver == null && (_mine?.out ?? false) && (watching || handOver);

  /// The user, out of chips, may buy in again (the host allows rebuys).
  bool get canRebuy => out && rules.rebuys;

  /// The user rebought: they watch until they are dealt in.
  bool get rebuying => _comingBack && !_satOut;

  /// The user sits out, or will from the next hand (see [sittingOut]).
  bool get sitsOut => !ended && gameOver == null && (_mine?.sittingOut ?? false);

  /// The user sits out (from the end of the hand they were in): they watch,
  /// not dealt in, until they are back.
  bool get sittingOut => sitsOut && (watching || handOver);

  /// The user sits out from the next hand (they play the one on screen).
  bool get sitsOutNextHand => sitsOut && !watching && !handOver;

  /// The user is back from sitting out: they watch until they are dealt in.
  bool get backNextHand => _comingBack && _satOut;

  /// The user may sit out, or be back: during the game, with chips.
  bool get canSitOut => !ended && gameOver == null && client.room?.phase == RoomPhase.playing && !(_mine?.out ?? true);

  /// The user watches, with chips and not sitting out: they are dealt in
  /// from the next hand.
  bool get _comingBack =>
      !ended &&
      gameOver == null &&
      watching &&
      !(_mine?.out ?? true) &&
      !(_mine?.sittingOut ?? true) &&
      client.room?.phase == RoomPhase.playing;

  /// The session follows the hand on screen: the user plays it, watches
  /// it as a spectator, or (on the host's device) a GTO bot plays in it.
  bool get follows => _followed(_shownLineup);

  /// The line-up of the hand on screen (before the first is dealt, the
  /// first announced).
  late _Lineup _shownLineup;

  /// Whether the session follows the hand of [lineup] (see [follows]).
  static bool _followed(_Lineup lineup) => !lineup.watching || lineup.spectating || lineup.gtoBots;

  /// Whether the server waits for this device to be Ready for the hand of
  /// [lineup]: it plays in it (only to show the last hand: nobody waits
  /// for a solve, the host's GTO bots' included).
  static bool _readies(_Lineup lineup) => !lineup.watching;

  /// The Coach chip starts off, for everyone: the best play isn't shown
  /// until the user asks for it (the chip, or the Coach button in the Game
  /// tab). Not kept: every room starts so.
  static bool defaultCoachOn() => false;

  /// Turns the spectator's coach on or off, on this device: answers from
  /// the next hand when it was off (the hand's solves start when it is
  /// dealt).
  void setCoach(bool on) {
    if (coachOn == on) return;
    coachOn = on;
    _sessionJob(() async => _coaching(on && spectating && _onScreen));
    _notify();
  }

  /// The session works out the spectator's coach ([on]) or not. Its answers
  /// are looked at as soon as they come, so the hand's solves come first
  /// while it is on, as for Show GTO (until the hand is over).
  void _coaching(bool on) {
    session.coaching = on;
    _coachClaim?.end();
    _coachClaim = on ? _owner?.claim(SolvePriority.shown) : null;
  }

  @override
  bool isUserSeat(int seat) => !watching && super.isUserSeat(seat);

  /// Help is for the players dealt in (a spectator has the coach).
  @override
  bool get guessGto => _help != HelpLevel.none && !spectating;

  @override
  bool get advanced => _help == HelpLevel.advanced;

  /// The user is choosing, with help on, and GTO's answer is still being
  /// worked out on the session's copy (it joins the choices when ready).
  @override
  bool get answerPending {
    final turn = _myTurn, answer = _answer;
    if (!guessGto || turn == null || heroOptions == null) return false;
    return answer == null || answer.hand != _handNumber || answer.turnId != turn.turnId;
  }

  /// Show GTO's claim goes on the hand on screen's solves at once, not as a
  /// session job, so it also lifts the solve the session is waiting for
  /// (and the hand's, if the session hasn't dealt it yet).
  @override
  Iterable<SolveOwner> get _answerOwners => [
    for (final owner in [?_owner, ?_nextOwner])
      if (owner.hand == _handNumber) owner,
  ];

  /// Hand [hand] and those before it are over on the table: nobody plays
  /// in them any more, so what made their solves urgent is over too (see
  /// SolveOwner.finish), and what is left of them goes after the next
  /// hand's game.
  void _finishHandsTo(int hand) {
    for (final owner in [?_owner, ?_nextOwner]) {
      if (owner.hand <= hand) owner.finish();
    }
  }

  /// The table [next] sets up, as this device sees it: the user in seat 0,
  /// everyone else played elsewhere, except the bots on the host's device.
  static TableConfig _configFor(OnlineClient client, NextHand next) {
    final settings = client.room?.settings ?? const RoomSettings();
    return TableConfig(
      players: _lineupOf(next, client, stackBb: settings.stackBb).players,
      ante: settings.ante,
      raiseRule: settings.raiseRule,
      resetStacksEachHand: settings.resetStacks,
      guessGto: next.help != HelpLevel.none,
      advanced: next.help == HelpLevel.advanced,
    );
  }

  /// The players of the hand [next] announces, by this device's seat, as
  /// [client]'s user sees it: playing it, or watching it (as a spectator
  /// when no seat is theirs: see OnlineClient.isSpectator).
  static _Lineup _lineupOf(NextHand next, OnlineClient client, {int stackBb = 100}) {
    final seats = _seatMapOf(next);
    final watching = next.you == null, host = client.isHost;
    final infos = [for (var local = 0; local < seats.playerCount; local++) next.seats[seats.toServer(local)]];
    return (
      roomSeats: [for (final info in infos) info.seat],
      infos: infos,
      players: [
        for (final (local, info) in infos.indexed)
          _playerFor(info, me: !watching && local == 0, host: host, stackBb: stackBb),
      ],
      watching: watching,
      spectating: watching && client.isSpectator,
      // Only the host's device plays the bots (and follows the hand for its GTO ones).
      gtoBots: host && infos.any((info) => info.kind == SeatKind.bot && info.style == 'gto'),
    );
  }

  /// The seats of the hand [next] announces as this device numbers them:
  /// the user in seat 0, or when the user watches, the server's.
  static SeatMap _seatMapOf(NextHand next) => SeatMap(next.seats.length, next.you ?? 0);

  static PlayerInfo _playerFor(SeatInfo seat, {required bool me, required bool host, required int stackBb}) {
    if (me) return PlayerInfo(name: seat.name, stackBb: stackBb, isHero: true);
    final bot = seat.kind == SeatKind.bot;
    if (bot && host) return PlayerInfo(name: seat.name, stackBb: stackBb, style: _styleOf(seat.style), isBot: true);
    return PlayerInfo(name: seat.name, stackBb: stackBb, remote: true, isBot: bot);
  }

  static bool _samePlayer(PlayerInfo a, PlayerInfo b) =>
      a.name == b.name && a.isHero == b.isHero && a.isBot == b.isBot && a.remote == b.remote && a.style == b.style;

  /// A bot style sent by the server; null for a random one.
  static BotStyle? _styleOf(String? name) => name == null ? null : BotStyle.values.asNameMap()[name];

  // ---------------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------------

  void _receive(ServerMessage m) {
    if (_disposed) return;
    switch (m) {
      case HandDealt():
        _latest = (m.hand, m.turn?.turnId ?? 0);
        // The session stops waiting for answers in the hand before.
        final dealt = _dealt;
        _dealt = Completer();
        dealt.complete();
      case HandEvents():
        _latest = (m.hand, m.turn?.turnId ?? 0);
      case Snapshot(:final hand?):
        final newer = hand.hand > _latest.$1;
        _latest = (hand.hand, hand.turn?.turnId ?? 0);
        if (newer) {
          final dealt = _dealt;
          _dealt = Completer();
          dealt.complete();
        }
        // What came before is in it: no need to play that.
        _inbox.removeWhere(
          (e) => e.$1 is HandDealt || e.$1 is HandEvents || e.$1 is NextHand || e.$1 is BotCards,
        );
      case RoomState():
        // Only the seats' badges: no need to wait for the table.
        _onRoom(m);
        return;
      case PlayerRemoved():
        _toast(OnlineToast.removed(m.name));
        return;
      default:
        break;
    }
    _inbox.add((m, DateTime.now()));
    if (!_pumping) unawaited(_pump());
  }

  Future<void> _pump() async {
    _pumping = true;
    try {
      // After the game is over, what comes is the lobby's (see handBack).
      while (_inbox.isNotEmpty && !_disposed && gameOver == null) {
        final (message, at) = _inbox.removeAt(0);
        try {
          await _handle(message, at);
        } catch (e) {
          _lostSync(e);
        }
      }
    } finally {
      _pumping = false;
    }
  }

  Future<void> _handle(ServerMessage m, DateTime at) async {
    switch (m) {
      case NextHand():
        _onNext(m);
      case BotCards():
        _botCards[m.hand] = seats.mapToLocal(m.cards);
      case HandDealt():
        await _onHand(m, at);
      case HandEvents():
        await _onEvents(m, at);
      case Snapshot():
        await _onSnapshot(m, at);
      case CardsShown():
        _onShown(m);
      case Notice():
        _onNotice(m);
      case Rejected():
        _onRejected(m);
      case GameOver():
        _onGameOver(m);
      default:
        _notify();
    }
  }

  /// The game is over, its last hand shown: everyone sees who won for a
  /// moment, then the app's room takes the connection back (handBack).
  void _onGameOver(GameOver m) {
    gameOver = m;
    _clearHeroDecision();
    _myTurn = null;
    nextHandAt = null;
    notice = null;
    _toast(OnlineToast.gameOver(m));
    _notify();
  }

  /// After the game is over: the app's room takes the connection back,
  /// with the messages not handled here, in order (a new game may have
  /// started already). The table then leaves the connection open.
  OnlineClient handBack() {
    _handedBack = true;
    client.detach();
    for (final (message, _) in _inbox.reversed) {
      client.pushBack(message);
    }
    _inbox.clear();
    return client;
  }

  /// Between hands: who plays the next one (someone may have joined or
  /// left, the host may have added or taken away a bot), with what stacks
  /// and what help. The session takes the line-up now, so solving can
  /// start; the table when the hand is dealt. The server deals once every
  /// player's device is Ready: this one is at once, since the last hand is
  /// shown by now (messages are played in order).
  void _onNext(NextHand m) {
    final lineup = _lineupOf(m, client, stackBb: rules.stackBb);
    // The next hand's messages use its seats.
    seats = _seatMapOf(m);
    _nextLineup = lineup;
    final stacks = seats.listToLocal(m.stacks), button = seats.toLocal(m.button);
    _nextHelp = m.help;
    // Before the next hand's solves are asked for (as a session job).
    _finishHandsTo(m.hand - 1);
    handOver = true;
    paused = false;
    nextHandAt = DateTime.now().add(Duration(milliseconds: m.maxWaitMs));
    // A hand the user watches from a seat: the session sits it out (unless
    // the host's GTO bots play in it), and the server doesn't wait for this
    // device. A spectator's session follows it, for the coach.
    if (_followed(lineup)) {
      _sessionJob(() async {
        _seatSession(lineup);
        session.announced = (stacks: stacks, button: button);
        _helpFor(lineup, m.help);
        _solveAhead(m.hand);
      });
    }
    if (_readies(lineup)) _readyFor(m.hand);
    _notify();
  }

  /// The session's help for the hand of [lineup]: the room's [help] for
  /// the user playing it, and on the host's device (its bots then play
  /// GTO before the flop, as every player's help expects); none for a
  /// spectator elsewhere, whose coach works it out instead ([coachOn]).
  void _helpFor(_Lineup lineup, HelpLevel help) {
    session.guessGto = help != HelpLevel.none && (!lineup.watching || isHost);
    session.setAdvanced(help == HelpLevel.advanced);
    _coaching(lineup.spectating && coachOn && _onScreen);
  }

  /// Starts on hand [hand]'s solves as soon as the session has taken its
  /// line-up (between hands, while the last one's end shows): its whole
  /// game, then the user's first decision if everyone folds to them. Nothing
  /// waits for them: the hand is dealt when the players' devices have shown
  /// the last one, and gets its answers when they are ready. A hand
  /// announced again (another line-up) starts over: what only the old
  /// line-up wanted is let go of.
  void _solveAhead(int hand) {
    final old = _nextOwner;
    _nextOwner = null;
    if (session.needsSolver) {
      final owner = _nextOwner = SolveOwner(hand);
      // Failures show up when the hand needs the solve; nothing to do here.
      _quietly(_solutions.solve(session.upcomingSpec, owner: owner, priority: SolvePriority.nextHand));
    }
    if (old != null) _solutions.drop(old);
    // A guess, with its own claim: never made more urgent (see _aheadOwner).
    if (_aheadOwner case final oldAhead?) _solutions.drop(oldAhead);
    _aheadOwner = null;
    if (session.needsSolver) {
      if (session.upcomingHeroSpec case final heroSpec?) {
        final ahead = _aheadOwner = SolveOwner(hand);
        _quietly(_solutions.solve(heroSpec, owner: ahead, priority: SolvePriority.ahead));
      }
    }
  }

  /// The session takes the next hand's [lineup] (players who stay keep
  /// their bot styles); nothing changes if it is the same.
  void _seatSession(_Lineup lineup) {
    final old = _sessionRoomSeats;
    final from = [
      for (final (seat, room) in lineup.roomSeats.indexed)
        switch (old.indexOf(room)) {
          final o when o >= 0 && _samePlayer(session.players[o], lineup.players[seat]) => o,
          _ => null,
        },
    ];
    final same = from.length == old.length && [for (final (seat, o) in from.indexed) o == seat].every((kept) => kept);
    if (!same) session.changeLineup(lineup.players, from: from);
    _sessionRoomSeats = lineup.roomSeats;
  }

  /// The table shows the players of the hand being dealt, and those at the
  /// table who don't play it (out of chips, sitting out, or back from the
  /// next hand; the user too, while watching) in places of their own:
  /// everyone in room seat order from the user's, at the bottom. A new
  /// table when any of them changed, else the same with each seat's player
  /// as sent.
  void _showLineup(_Lineup lineup) {
    _shownLineup = lineup;
    watching = lineup.watching;
    spectating = lineup.spectating;
    if (!watching) _satOut = false;
    final room = client.room;
    final others = [
      for (final info in room?.seats ?? const <SeatInfo>[])
        if (!info.isEmpty && !lineup.roomSeats.contains(info.seat)) info,
    ];
    final otherSeats = [for (final info in others) info.seat];
    if (!listEquals(lineup.roomSeats, _viewRoomSeats) || !listEquals(otherSeats, _otherRoomSeats)) {
      final me = client.mySeat ?? lineup.roomSeats.first, count = room?.seats.length ?? onlineBotNames.length;
      final order = [...lineup.roomSeats, ...otherSeats]
        ..sort((a, b) => ((a - me) % count).compareTo((b - me) % count));
      // What still flies belongs to the last table.
      flying.clear();
      view = TableViewState(
        [for (final p in lineup.players) SeatView(info: p, stack: p.stackBb * TableConfig.bigBlind)],
        places: [for (final seat in lineup.roomSeats) order.indexOf(seat)],
        others: [
          for (final info in others)
            OtherSeat(
              roomSeat: info.seat,
              place: order.indexOf(info.seat),
              user: info.seat == client.mySeat,
              view: SeatView(
                info: PlayerInfo(name: info.name, stackBb: 0, remote: true, isBot: info.kind == SeatKind.bot),
                stack: 0,
              ),
            ),
        ],
      );
    }
    _otherRoomSeats = otherSeats;
    for (final (local, info) in lineup.infos.indexed) {
      view.seats[local]
        ..info = lineup.players[local]
        // A bot's style, as the server shows it (to everyone when the host shows styles).
        ..style = info.kind == SeatKind.bot ? _styleOf(info.style) : null;
    }
    _viewRoomSeats = lineup.roomSeats;
    if (room != null) _onRoom(room);
  }

  /// Tells the server this device is ready for hand [hand]: it has shown
  /// the last hand. Never later for a solve (help, and the host's GTO bots,
  /// play from what is solved by then: see [_playBot]).
  void _readyFor(int hand) {
    if (!_disposed && !ended) client.send(Ready(hand));
  }

  Future<void> _onHand(HandDealt m, DateTime at) async {
    final batch = seats.eventsToLocal(m.batch);
    final deal = RemoteDeal.fromBatch(batch, extraKnown: _botCards.remove(m.hand) ?? const {});
    _botCards.removeWhere((hand, _) => hand < m.hand);
    final lineup = _nextLineup;
    _nextLineup = null;
    if (lineup != null) _showLineup(lineup);
    if (deal.stacks.length != playerCount) throw MirrorMismatch('Not the players announced');
    _handNumber = m.hand;
    _help = _nextHelp;
    _seeCardsIn(batch);
    _shownMine = false;
    _myTurn = null;
    _answer = null;
    _sentMove = null;
    outOfSync = false;
    _shownBatches = 1;
    // Late Mistakes are listed for the hand on screen only.
    _lateMistakes.clear();
    try {
      _mirror = _build(deal);
    } on MirrorMismatch catch (e) {
      _mirror = null;
      _lostSync(e);
    }
    _settleAheadOnline();
    // A hand the session doesn't follow: what it solved for the last one is no longer wanted.
    _sessionJob(follows ? () => _sessionDeal(m.hand, deal) : () async => _letGoOfOwner());
    handOver = false;
    nextHandAt = null;
    _clearHeroDecision();
    _heroFolded = false;
    notice = null;
    await _play(batch);
    _afterBatch(m.turn, at);
  }

  /// The whole preflop game of hand [hand] (the next for the session),
  /// solved, if help or the GTO bots need it, for [owner]: the session
  /// waits for a solve still running (the table doesn't), so the help comes
  /// late rather than not at all, unless the server deals another hand
  /// first. Null without it. Meanwhile the host's bots keep the hand on its
  /// solved lines without it (TableSession.decisionOn).
  Future<PreflopAdvisor?> _blueprint(int hand, SolveOwner owner) async {
    if (!session.needsSolver) return null;
    final spec = session.upcomingSpec;
    final ready = _solutions.ready(spec);
    if (ready != null || _latest.$1 > hand) return ready;
    PreflopAdvisor? advisor;
    await _beforeNextHand(
      _solutions.solve(spec, owner: owner, priority: SolvePriority.bot).then((a) => advisor = a),
      hand,
    );
    return advisor;
  }

  /// The claim on solves of hand [hand], the one the session deals now:
  /// the one its solves ahead of time were started with ([_solveAhead]), or
  /// the hand's own when it is dealt again (a fresh copy after
  /// reconnecting), else a new one. The hand before is let go of: online,
  /// its answers still to come are dropped once the next hand is dealt.
  /// A spectator's coach looks at its answers as they come: they come first.
  SolveOwner _ownerFor(int hand) {
    final last = _owner, next = _nextOwner;
    final owner = last != null && last.hand == hand
        ? last
        : next != null && next.hand == hand
        ? next
        : SolveOwner(hand);
    if (identical(owner, next)) _nextOwner = null;
    if (!identical(last, owner)) _letGoOfOwner();
    _owner = owner;
    _coaching(session.coaching);
    return owner;
  }

  /// The guess solved ahead of time for the user's first decision is let
  /// go of once it can't be used in the hand on screen (see _settleAhead).
  void _settleAheadOnline() {
    final ahead = _aheadOwner;
    if (ahead == null) return;
    final mirror = _mirror;
    if (mirror != null && ahead.hand == _handNumber) return _settleAhead(mirror);
    if (ahead.hand > _handNumber) return;
    _aheadOwner = null;
    _solutions.drop(ahead);
  }

  /// The session's last hand gets nothing more solved: another is dealt.
  void _letGoOfOwner() {
    final last = _owner;
    if (last == null) return;
    _owner = null;
    _solutions.drop(last);
  }

  /// Whether a GTO bot is still in the session's copy of hand [hand].
  bool _gtoBotIn(int hand) {
    final h = session.hand;
    return h != null && h.handNumber == hand && session.hasGtoBotIn(h);
  }

  PokerHand _build(RemoteDeal deal) => deal.build(
    smallBlind: TableConfig.smallBlind,
    bigBlind: TableConfig.bigBlind,
    ante: session.config.ante,
    raiseRule: session.config.raiseRule,
  );

  /// The session's copy of hand [hand], from [deal]: once its whole preflop
  /// game is solved, if help or the GTO bots need it. Its solves are the
  /// hand's own ([_ownerFor]): the user's subgames grade them (with help,
  /// on the host's device, the bots' replies before the flop come from them
  /// too), and the streets are solved only while someone needs them
  /// (TableSession.streetNeeded).
  Future<void> _sessionDeal(int hand, RemoteDeal deal) async {
    _sessionBroken = false;
    final owner = _ownerFor(hand);
    session.announced = (stacks: deal.stacks, button: deal.buttonSeat);
    session.advisor = await _blueprint(hand, owner);
    final h = session.startHandWith(
      deal: deal,
      subgames: (spec, ranges) => _solutions.solveSubgame(
        spec,
        ranges,
        owner: owner,
        priority: session.guessGto ? SolvePriority.grade : SolvePriority.bot,
      ),
      streets: (spec, ranges) => _solutions.solvePostflop(
        spec,
        ranges,
        owner: owner,
        priority: _gtoBotIn(hand) ? SolvePriority.bot : SolvePriority.grade,
      ),
      needed: session.streetNeeded,
    );
    _sessionBatches = 1;
    await _track(hand);
    if (h.isOver) _finishSessionHand();
    _coachMoved();
  }

  /// Plays [batch] of hand [hand] on the session's copy (if it follows that
  /// hand), then waits for its trackers.
  Future<void> _sessionStep(int hand, List<GameEvent> batch) async {
    final h = session.hand;
    if (_sessionBroken || h == null || h.handNumber != hand || h.isOver) return;
    // The next hand is dealt already: catch up, without answers in this one.
    if (_latest.$1 > hand) session.detachTrackers();
    applyBatch(h, batch);
    _sessionBatches++;
    await _track(hand);
    if (h.isOver) _finishSessionHand();
    _coachMoved();
  }

  Future<void> _onEvents(HandEvents m, DateTime at) async {
    if (m.hand != _handNumber) return;
    await _applyEvents(m.hand, seats.eventsToLocal(m.batch), cause: m.cause, turnId: m.turnId);
    _afterBatch(m.turn, at);
  }

  /// One action in hand [hand] and what it led to: on the table's copy of
  /// the hand, on the session's (in turn), and on screen. [turnId] is the
  /// turn it ended, and [cause] who chose it (null when not known: caught
  /// up from a snapshot).
  Future<void> _applyEvents(int hand, List<GameEvent> batch, {ActCause? cause, int? turnId}) async {
    _shownBatches++;
    final mirror = _mirror;
    if (mirror != null) {
      try {
        applyBatch(mirror, batch);
        if (mirror.isOver) _finishHandsTo(hand);
      } on MirrorMismatch catch (e) {
        _mirror = null;
        _lostSync(e);
      }
    }
    _settleAheadOnline();
    final sent = _sentMove;
    if (sent != null && turnId != null && turnId >= sent.turnId) _sentMove = null;
    if (batch.firstOrNull case final ActionTaken first when isUserSeat(first.seat)) {
      final auto = cause != null && cause != ActCause.act;
      final played = actionOf(first);
      if (cause == null && sent != null && sent.hand == hand) {
        if (played.type != sent.action.type || played.amount != sent.action.amount) {
          // Caught up after reconnecting: the server played for the user (their move came too late).
          _dropUnscored(hand, sent.turnId);
          _sessionJob(() async => _correctRecord(hand, sent.turnId, first));
        }
      }
      // The choices go (a score shown for the move sent stays, unless the server played instead).
      if (auto || heroOptions != null) _clearHeroDecision();
      _myTurn = null;
      _sentMove = null;
      if (first.kind == ActionKind.fold) _heroFolded = true;
      if (cause != null) notice = auto ? OnlineNotice.timesUp : null;
      if (auto && turnId != null) {
        // A move still on its way when the time ran out didn't count.
        _dropUnscored(hand, turnId);
        _sessionJob(() async => _correctRecord(hand, turnId, first));
      }
    }
    if (follows) _sessionJob(() => _sessionStep(hand, batch));
    view
      ..turnEnds = null
      ..turnLimit = null;
    await _play(batch);
  }

  void _finishSessionHand() {
    session.finishHand();
    _notify();
  }

  /// Where the table is, after reconnecting (or when this device's copy of
  /// the hand went wrong): the hand is caught up with, then the next one
  /// is announced, if it is.
  Future<void> _onSnapshot(Snapshot m, DateTime at) async {
    if (m.hand case final hand?) await _resume(hand, at);
    if (m.next case final next?) _onNext(next);
    // Show GTO pressed while the connection was down: everyone is still told (the server tells once).
    if (_helpSent case (final hand, final turnId) when hand == _handNumber) {
      client.send(UsedHelp(hand: hand, turnId: turnId));
    }
    _notify();
  }

  /// Catches up with hand [h]: plays what was missed, as it would have been
  /// (the table's copy is fine and on that hand), or the whole hand again.
  /// Then its open turn, with the time left.
  Future<void> _resume(SnapshotHand h, DateTime at) async {
    final map = _seatMapOf(h.lineup);
    final batches = [for (final b in h.batches) map.eventsToLocal(b)];
    final lineup = _lineupOf(h.lineup, client, stackBb: rules.stackBb);
    seats = map;
    final goesOn =
        h.hand == _handNumber &&
        _mirror != null &&
        listEquals(lineup.roomSeats, _viewRoomSeats) &&
        _shownBatches > 0 &&
        _shownBatches <= batches.length;
    if (goesOn) {
      for (final batch in batches.skip(_shownBatches)) {
        await _applyEvents(h.hand, batch);
      }
    } else {
      await _replay(h, lineup, batches);
    }
    if (outOfSync && _mirror != null) {
      outOfSync = false;
      if (notice == OnlineNotice.outOfSync) notice = null;
    }
    _afterBatch(h.turn, at);
  }

  /// Plays hand [h] ([batches], in this device's seats) again from the
  /// start, at once and without sounds, on a new copy of the hand. The
  /// session's copy catches up if it can, else starts over too.
  Future<void> _replay(SnapshotHand h, _Lineup lineup, List<List<GameEvent>> batches) async {
    final hand = h.hand;
    final deal = RemoteDeal.fromBatch(batches.first, extraKnown: seats.mapToLocal(h.botCards));
    _nextLineup = null;
    _showLineup(lineup);
    if (deal.stacks.length != playerCount) throw MirrorMismatch('Not the players announced');
    _handNumber = hand;
    _help = _nextHelp = h.lineup.help;
    _seeCardsIn(batches.first);
    _shownMine = false;
    _myTurn = null;
    outOfSync = false;
    if (notice == OnlineNotice.outOfSync) notice = null;
    try {
      final mirror = _build(deal);
      for (final batch in batches.skip(1)) {
        applyBatch(mirror, batch);
      }
      _mirror = mirror;
    } on MirrorMismatch catch (e) {
      _mirror = null;
      _lostSync(e);
    }
    // A hand the user watches from a seat: the session sits it out (see follows).
    if (follows) {
      _sessionJob(() async {
        final current = session.hand;
        final follows =
            !_sessionBroken &&
            current != null &&
            current.handNumber == hand &&
            listEquals(_sessionRoomSeats, lineup.roomSeats) &&
            _sessionBatches > 0 &&
            _sessionBatches <= batches.length;
        if (!follows) {
          _seatSession(lineup);
          _helpFor(lineup, _help);
          await _sessionDeal(hand, deal);
        }
        for (final batch in batches.skip(_sessionBatches)) {
          await _sessionStep(hand, batch);
        }
      });
    }
    handOver = false;
    nextHandAt = null;
    _clearHeroDecision();
    _heroFolded = batches.any(
      (batch) => batch.any((e) => e is ActionTaken && isUserSeat(e.seat) && e.kind == ActionKind.fold),
    );
    _shownBatches = batches.length;
    // What still flies belongs to the table before.
    flying.clear();
    _replaying = true;
    try {
      for (final batch in batches) {
        await _play(batch);
      }
    } finally {
      _replaying = false;
    }
  }

  /// After an action on the session's copy of hand [hand]: waits for its
  /// trackers (TableSession.afterAction), which must be done before the
  /// next action. If they fail, or the server deals another hand first, the
  /// session follows the rest of this hand without them.
  Future<void> _track(int hand) async {
    if (!await _beforeNextHand(session.afterAction(), hand)) session.detachTrackers();
  }

  /// After a hand's events are shown: the next turn (the user's choices,
  /// or on the host's device a bot's move), or the end of the hand.
  void _afterBatch(Turn? turn, DateTime at) {
    if (turn == null) {
      view
        ..actingSeat = null
        ..turnEnds = null
        ..turnLimit = null;
      handOver = true;
      // Who ran out of chips shows now.
      final room = client.room;
      if (room != null) _onRoom(room);
      _notify();
      return;
    }
    final seat = seats.toLocal(turn.seat);
    final ms = turn.ms;
    // A clock only for people with a time limit (bots, and players who left, are quick).
    final clock = ms != null && ms > 0 && !view.seats[seat].info.isBot;
    view
      ..actingSeat = seat
      ..turnEnds = clock ? at.add(Duration(milliseconds: turn.waitMs + ms)) : null
      ..turnLimit = clock ? Duration(milliseconds: ms) : null;
    final sent = _sentMove;
    if (isUserSeat(seat) && sent != null && sent.hand == _handNumber && sent.turnId == turn.turnId) {
      // The move made before the connection dropped may not have arrived: again (the server takes it once).
      _myTurn = turn;
      client.send(Act(hand: sent.hand, turnId: sent.turnId, action: sent.action));
    } else if (isUserSeat(seat)) {
      _myTurn = turn;
      _showChoices(turn);
      if (guessGto) _answerFor(turn);
      // A pre-action that still fits goes at once (graded when the answer comes).
      if (_preActionChoice() case final choice?) {
        unawaited(_playChoice(choice));
      } else {
        _sound(SoundEffect.yourTurn);
      }
    } else if (isHost && !view.seats[seat].info.remote) {
      // The seat's line-up is the view's: the session may still be on the last hand.
      unawaited(_playBot(turn, seat));
    }
    _notify();
  }

  /// The user's choices at [turn], from the table's copy of the hand (or,
  /// if it went wrong, from what the server sent: the smallest raise and
  /// all-in only), with GTO's answer if it is known already. A score still
  /// showing from their last move goes.
  void _showChoices(Turn turn) {
    _clearHeroDecision();
    final mirror = _mirror;
    final options = mirror != null && mirror.toAct == TableSession.heroSeat ? mirror.legalActions() : null;
    if (options != null && turn.matches(options)) {
      heroOptions = options;
      heroMenu = actionMenu(mirror!);
    } else {
      if (options != null) _lostSync(MirrorMismatch('Not the choices the server gives'));
      _choicesFromTurn(turn);
    }
    final answer = _answer;
    if (answer != null && answer.hand == _handNumber && answer.turnId == turn.turnId && answer.spot != null) {
      heroSpot = answer.spot;
      heroMenu = answer.spot!.actions;
    }
  }

  void _choicesFromTurn(Turn turn) {
    heroOptions = LegalActions(
      toCall: turn.toCall,
      canRaise: turn.canRaise,
      minRaiseTo: turn.minRaiseTo,
      maxRaiseTo: turn.maxRaiseTo,
      currentBet: 0,
      streetBet: 0,
      stack: turn.maxRaiseTo,
      pot: 0,
    );
    final raise = turn.canRaise ? null : Unavailable.raisingNotAllowed;
    heroMenu = [
      SpotAction(
        kind: SpotActionKind.fold,
        amount: 0,
        action: const PlayerAction.fold(),
        unavailable: turn.toCall > 0 ? null : Unavailable.checkIsFree,
      ),
      turn.toCall == 0
          ? const SpotAction(kind: SpotActionKind.check, amount: 0, action: PlayerAction.check())
          : SpotAction(kind: SpotActionKind.call, amount: turn.toCall, action: const PlayerAction.call()),
      if (turn.minRaiseTo < turn.maxRaiseTo)
        SpotAction(
          kind: SpotActionKind.raise,
          amount: turn.minRaiseTo,
          action: PlayerAction.raiseTo(turn.minRaiseTo),
          unavailable: raise,
        ),
      SpotAction(
        kind: SpotActionKind.allIn,
        amount: turn.maxRaiseTo,
        action: PlayerAction.raiseTo(turn.maxRaiseTo),
        unavailable: raise,
      ),
    ];
  }

  void _onRejected(Rejected m) {
    final turn = _myTurn;
    // The move didn't count and the turn is still open: choose again.
    if (turn != null && m.turnId == turn.turnId && heroOptions == null && _latest == (_handNumber, turn.turnId)) {
      _sentMove = null;
      _dropUnscored(_handNumber, turn.turnId);
      _showChoices(turn);
      notice = OnlineNotice.refused;
    }
    _notify();
  }

  /// The room changed: the seats' badges (who is away or left, who comes
  /// or goes at the next hand, who ran out of chips: once the hand on
  /// screen is over; who sits out, with their chips), whether the game
  /// waits for players, and the rules (everyone is told when the host
  /// changes them during the game).
  void _onRoom(RoomState m) {
    if (_mine?.sittingOut ?? false) _satOut = true;
    for (final info in m.seats) {
      final local = _viewRoomSeats.indexOf(info.seat);
      if (local >= 0) {
        final seat = view.seats[local];
        // Someone else has the seat now: the player on screen left it.
        final same = !info.isEmpty && info.name == seat.info.name;
        seat
          ..connected = same && (info.kind == SeatKind.bot || info.status != SeatStatus.left)
          ..away = same && info.status == SeatStatus.away
          ..joiningNextHand = info.joining != null
          ..leavingNextHand = info.leaving
          ..out = same && handOver && info.out;
      }
      for (final other in view.others) {
        if (other.roomSeat != info.seat) continue;
        final same = !info.isEmpty && info.name == other.view.info.name;
        // Neither out nor sitting out any more: back from the next hand (after a rebuy, with the starting stack).
        final back = same && !info.out && !info.sittingOut && m.phase == RoomPhase.playing;
        other.view
          ..connected = same && (info.kind == SeatKind.bot || info.status != SeatStatus.left)
          ..away = same && info.status == SeatStatus.away
          ..joiningNextHand = back || info.joining != null
          ..leavingNextHand = info.leaving
          ..out = same && info.out
          ..sittingOut = same && info.sittingOut
          ..stack = same && !info.out ? info.chips ?? (m.settings ?? const RoomSettings()).startingStack : 0;
      }
    }
    // The host may watch (no seat): their status is the member's.
    final host = m.members.where((member) => member.id == m.host).firstOrNull;
    hostAway = m.phase == RoomPhase.playing && host?.status == SeatStatus.away;
    paused = m.phase == RoomPhase.playing && m.paused;
    if (paused) nextHandAt = null;
    // A room without Hold'em's rules (the host picked another game after this one ended) changes no rules.
    if (m.settings case final rules?) {
      final before = _lastRules;
      _lastRules = rules;
      if (before != null && before != rules && m.phase == RoomPhase.playing && !isHost) {
        _toast(const OnlineToast.rulesChanged());
      }
    }
    _notify();
  }

  void _toast(OnlineToast toast) {
    if (!_toasts.isClosed) _toasts.add(toast);
  }

  /// Everyone is told what a player did: pressed Show GTO. It shows for a
  /// moment (in step with the table), and goes in the hand's record.
  void _onNotice(Notice m) {
    final mine = client.mySeat;
    final note = HandNote(
      name: m.seat == mine ? null : m.name,
    );
    _toast(OnlineToast.note(note));
    _sessionJob(() async => _recordOf(m.hand)?.notes.add(note));
  }

  void _onStatus() {
    if (ended) {
      _clearHeroDecision();
      _myTurn = null;
    }
    _notify();
  }

  /// This device's copy of the hand stopped matching the server's: it asks
  /// for a fresh one (once a hand: if that goes wrong too, the hand plays
  /// on without, and the next starts afresh).
  void _lostSync(Object error) {
    debugPrint('Online table out of sync: $error');
    outOfSync = true;
    notice = OnlineNotice.outOfSync;
    if (_resyncedHand != _handNumber && !ended) {
      _resyncedHand = _handNumber;
      client.send(const Resync());
    }
    _notify();
  }

  /// Runs [job] on the session's copy of the hand once the jobs before it
  /// are done. If one fails, the session stops following this hand (its
  /// bots fall back on their rules) until the next.
  void _sessionJob(Future<void> Function() job) {
    _sessionTail = _sessionTail.then((_) async {
      if (_disposed) return;
      try {
        await job();
      } catch (e) {
        debugPrint('Online table: the session lost the hand: $e');
        _sessionBroken = true;
        session.detachTrackers();
      }
    });
  }

  /// The solve the player in [seat] needs at their turn in hand [hand], if
  /// it is still being worked out on the session's copy: before the flop,
  /// the user's subgame (the bots' replies to the user come from it too);
  /// after it, the street. Null if there is nothing to wait for.
  Future<void>? _answersFor(int seat, int hand) {
    final h = session.hand;
    if (h == null || h.handNumber != hand || h.toAct != seat) return null;
    if (h.street == Street.preflop) return session.preflopPending ? session.preflopReady : null;
    final tracker = session.postflop;
    if (tracker == null || !session.needsPostflopAnswer || !tracker.solving) return null;
    return tracker.ready;
  }

  /// Whether [future] completes (without failing) before the server deals
  /// a hand after [hand].
  Future<bool> _beforeNextHand(Future<void> future, int hand) {
    if (_latest.$1 > hand) return Future.value(false);
    return Future.any([future.then((_) => true, onError: (Object _) => false), _dealt.future.then((_) => false)]);
  }

  // ---------------------------------------------------------------------------
  // Help
  // ---------------------------------------------------------------------------

  /// Works out GTO's answer for the user's [turn] on the session's copy of
  /// the hand, once it has caught up and solved what it needs (the choices
  /// already show), or why there is none.
  void _answerFor(Turn turn) {
    final hand = _handNumber;
    _sessionJob(() async {
      final h = session.hand;
      SpotStrategy? spot;
      NoAnswer? none;
      if (!_sessionBroken &&
          session.guessGto &&
          h != null &&
          h.handNumber == hand &&
          h.toAct == TableSession.heroSeat &&
          !h.isOver) {
        final wait = _answersFor(TableSession.heroSeat, hand);
        final solved = wait == null || await _beforeNextHand(wait, hand);
        if (solved) spot = session.heroSpot();
        if (spot == null) none = _whyNone(h, failed: !solved);
      }
      final decision = (hand: hand, turnId: turn.turnId, players: session.players, styles: session.styles);
      _answerCame(decision, (spot: spot, none: none), h);
    });
  }

  /// Why GTO has no answer for the user at [h] (the session's copy): the
  /// solve it waited for [failed], or the hand's whole game couldn't be
  /// solved, or the trackers say (more than two players after the flop, a
  /// move off the solved lines). Null when no reason is known, or the next
  /// hand was dealt first (then nobody sees it).
  NoAnswer? _whyNone(PokerHand h, {required bool failed}) {
    if (_latest.$1 > h.handNumber) return null;
    if (failed) return NoAnswer.solveFailed;
    final pre = session.preflop, post = session.postflop;
    if (pre == null) return session.needsSolver ? NoAnswer.solveFailed : null;
    return h.street == Street.preflop ? pre.unavailable : (post?.unavailable ?? pre.unavailable);
  }

  /// GTO's answer (or that there is none) for the user's decision [d],
  /// on the session's copy, which is at that turn: as on the device (see
  /// TableController._answerCame). Older moves won't get an answer any more
  /// (the session caught up without).
  @override
  void _answerCame(_Decision d, GtoAnswer a, PokerHand? at, {PostflopTracker? postflop}) {
    _answer = (hand: d.hand, turnId: d.turnId, spot: a.spot);
    _unscored.removeWhere((played) => played.hand < d.hand);
    super._answerCame(d, a, at, postflop: postflop);
  }

  /// The user's choices at turn [d] still show.
  @override
  bool _showing(_Decision d) {
    final turn = _myTurn;
    return turn != null && turn.turnId == d.turnId && d.hand == _handNumber && heroOptions != null;
  }

  @override
  int get _tableHand => _handNumber;

  void _dropUnscored(int hand, int turnId) =>
      _unscored.removeWhere((played) => played.hand == hand && played.turnId == turnId);

  /// The server checked or folded for the user at turn [turnId] (their
  /// time ran out first): a decision recorded for it says so.
  void _correctRecord(int hand, int turnId, ActionTaken played) {
    final record = _recordOf(hand);
    if (record == null) return;
    final kind = switch (played.kind) {
      ActionKind.fold => SpotActionKind.fold,
      ActionKind.check => SpotActionKind.check,
      ActionKind.call => SpotActionKind.call,
      ActionKind.bet || ActionKind.raise => null,
    };
    for (final d in record.decisions) {
      if (d.turnId != turnId) continue;
      final index = d.spot.actions.indexWhere((a) => a.kind == kind);
      d.played = index < 0 ? null : index;
    }
  }

  // ---------------------------------------------------------------------------
  // The host's bots
  // ---------------------------------------------------------------------------

  /// Plays the bot in [seat] at [turn] (on the host's device), in about a
  /// person's time however slow this device is. After its think pause, a
  /// bot that plays from a solve (a GTO bot; before the flop with help on,
  /// any bot) waits a moment more ([botBudget]) for the session's copy of
  /// the hand to catch up, and for the solve its move comes from (its
  /// hand's solves come first meanwhile). Then it plays the best it has:
  /// on the session's copy when that is at this turn, else on the table's
  /// (TableSession.decisionOn). Either way its move keeps the hand on the
  /// solved lines, so every player's help still has its answers.
  Future<void> _playBot(Turn turn, int seat) async {
    final hand = _handNumber;
    bool gone() => _disposed || ended || _latest != (hand, turn.turnId);
    await Future<void>.delayed(Playback.botThink);
    if (gone()) return;
    final style = _botStyle(seat);
    final mirror = _mirror;
    if (mirror != null && mirror.toAct == seat && session.playsFromSolve(mirror, seat, style: style)) {
      final waiting = switch (_owner) {
        final owner? when owner.hand == hand => owner.claim(SolvePriority.bot),
        _ => null,
      };
      try {
        final ready = _readyToPlay(seat, hand);
        final budget = botBudget;
        if (budget == null) {
          await ready.then((_) {}, onError: (Object _) {});
        } else {
          await _within(ready, budget);
        }
      } finally {
        // It has waited: its move comes now, from whatever is ready.
        waiting?.end();
      }
      if (gone()) return;
    }
    PlayerAction? move;
    if (_sessionAt(hand, seat)) {
      try {
        move = session.botDecision();
      } catch (e) {
        debugPrint('Online table: bot decision failed: $e');
      }
    }
    if (move == null) {
      // The server checks or folds for it when time runs out.
      final mirror = _mirror;
      if (mirror == null || mirror.toAct != seat) return;
      try {
        move = session.decisionOn(mirror, seat, style: style);
      } catch (e) {
        debugPrint('Online table: bot decision failed: $e');
        move = Bot(style, _random).decide(mirror, seat);
      }
    }
    client.send(BotAct(hand: hand, turnId: turn.turnId, seat: seats.toServer(seat), action: move));
  }

  /// The style the bot in [seat] of the hand on screen plays: as the
  /// server sent it, or a random one's, which only the session knows (once
  /// it has this hand's players).
  BotStyle _botStyle(int seat) {
    final secret = listEquals(_sessionRoomSeats, _viewRoomSeats) && seat < session.styles.length
        ? session.styles[seat]
        : null;
    return view.seats[seat].info.style ?? secret ?? BotStyle.tag;
  }

  /// Completes once the session's copy of hand [hand] has caught up with
  /// the jobs queued so far, and the solve the player in [seat] needs at
  /// their turn is done (see [_answersFor]).
  Future<void> _readyToPlay(int seat, int hand) async {
    await _sessionTail;
    await (_answersFor(seat, hand) ?? Future<void>.value());
  }

  /// Whether the session's copy stands where the table does in hand
  /// [hand], at [seat]'s turn.
  bool _sessionAt(int hand, int seat) {
    final h = session.hand;
    return !_sessionBroken &&
        h != null &&
        h.handNumber == hand &&
        _sessionBatches == _shownBatches &&
        h.toAct == seat &&
        !h.isOver;
  }

  // ---------------------------------------------------------------------------
  // The user
  // ---------------------------------------------------------------------------

  /// Sends the user's move. The table moves on when the server sends it
  /// back (to everyone).
  @override
  Future<void> heroAct(PlayerAction action) async {
    final turn = _myTurn;
    if (heroOptions == null || turn == null || ended) return;
    _clearHeroDecision();
    _send(turn, action);
  }

  void _send(Turn turn, PlayerAction move) {
    heroOptions = null;
    heroMenu = null;
    notice = null;
    _sentMove = (hand: _handNumber, turnId: turn.turnId, action: move);
    client.send(Act(hand: _handNumber, turnId: turn.turnId, action: move));
    _notify();
  }

  /// Scores the user's mix and sends the move at once (drawn from the mix
  /// unless [choice] is ticked). Before GTO's answer comes, the move goes
  /// anyway and is scored when it does.
  @override
  void submitMix(List<double> mix, {int? choice, bool oneAction = false}) =>
      _submit(mix, choice: choice, oneAction: oneAction);

  /// Simple training: sends [choice] (or [action], a raise of another
  /// amount graded as [choice]) at once; the grade shows without holding
  /// the table.
  @override
  Future<void> playGraded(int choice, {PlayerAction? action}) async {
    final menu = heroMenu;
    if (menu == null) return;
    _submit(
      [for (var i = 0; i < menu.length; i++) i == choice ? 1.0 : 0.0],
      choice: choice,
      oneAction: true,
      action: action,
    );
  }

  void _submit(List<double> mix, {int? choice, required bool oneAction, PlayerAction? action}) {
    final turn = _myTurn, menu = heroMenu;
    if (turn == null || heroOptions == null || menu == null || heroScore != null || ended) return;
    if (heroSpot != null) {
      // A move the server refused was recorded already: this one counts instead.
      _recordOf(_handNumber)?.decisions.removeWhere((d) => d.turnId == turn.turnId);
      super.submitMix(mix, choice: choice, oneAction: oneAction);
    }
    final play = heroPlay ?? choice ?? _drawFrom(menu, mix);
    if (heroSpot == null && guessGto) {
      _unscored.add((
        hand: _handNumber,
        turnId: turn.turnId,
        players: List.of(session.players),
        styles: List.of(session.styles),
        mix: List.unmodifiable(mix),
        choice: play,
        drew: choice == null,
        action: action,
        oneAction: oneAction,
      ));
    }
    heroAction = action;
    _send(turn, action ?? menu[play].action);
    final score = heroScore;
    if (score != null && _quietGrade(score, oneAction: oneAction)) {
      _clearHeroDecision();
      _notify();
    }
  }

  @override
  int? get _recordTurnId => _myTurn?.turnId;

  /// The score shows without holding the table: OK puts it away.
  @override
  Future<void> continueHand() async {
    if (heroOptions != null) return;
    _clearHeroDecision();
    _notify();
  }

  /// Behind the server (several messages waiting): hurry to catch up; at
  /// once when a snapshot is waiting, or being played.
  @override
  double get _factor {
    final factor = super._factor;
    if (_replaying || _inbox.length >= 4 || _inbox.any((e) => e.$1 is Snapshot)) return 0;
    if (_inbox.length >= 2) return min(factor, PlaybackSpeed.fast.factor);
    return factor;
  }

  /// A hand played again from a snapshot makes no sound, and nor does the
  /// table while it is off screen (the room's game goes on over Home or a
  /// game played alone).
  @override
  void _sound(SoundEffect effect) {
    if (_replaying || !_onScreen) return;
    debugOnSound?.call(effect);
    super._sound(effect);
  }

  /// The server deals the hands.
  @override
  Future<void> startNextHand() async {}

  /// The host picks the help for the whole table.
  @override
  void setAdvanced(bool value) {}

  /// Other players' cards stay hidden online, except a spectator's
  /// [_visible] ones.
  @override
  void toggleCards(int seat) {}

  @override
  void toggleAllCards() {}

  @override
  bool _cardsShown(int seat) => _visible.contains(seat);

  /// A new hand on screen, dealt with [deal] (its first batch, by this
  /// device's seat): a spectator sees the cards it came with (see
  /// [_visible]); anyone else only their own.
  void _seeCardsIn(List<GameEvent> deal) {
    _visible.clear();
    if (!spectating) return;
    for (final e in deal) {
      if (e is HoleCardsDealt) _visible.addAll(e.cards.keys);
    }
  }

  // ---------------------------------------------------------------------------
  // The spectator's coach
  // ---------------------------------------------------------------------------

  /// What a spectator's coach shows for whoever acts on screen (null:
  /// nobody acts, or the coach is off, or the user isn't spectating). Its
  /// answer comes from the session's copy of the hand, once that is at the
  /// same point as the screen (it may fall behind while it solves).
  SpectatorCoach? get spectatorCoach {
    final seat = view.actingSeat;
    if (!spectating || !coachOn || ended || handOver || seat == null || seat >= playerCount) return null;
    final name = view.seats[seat].info.name;
    if (!_visible.contains(seat)) return SpectatorCoach(seat: seat, name: name, hidden: true);
    final h = session.hand;
    final caughtUp =
        h != null && h.handNumber == _handNumber && _sessionBatches == _shownBatches && h.toAct == seat && !h.isOver;
    if (!caughtUp || _sessionBroken) return SpectatorCoach(seat: seat, name: name, thinking: !_sessionBroken);
    final spot = session.spotToAct(_visible);
    if (spot != null) return SpectatorCoach(seat: seat, name: name, spot: spot);
    final NoAnswer? none;
    var thinking = false;
    if (h.street == Street.preflop) {
      // No whole game solved for this hand (the coach was off when it was dealt, or the solve failed).
      none = session.preflop == null ? null : NoAnswer.leftSolvedLines;
    } else if (session.postflop case final tracker?) {
      // A street nobody needed isn't solved (the coach was off): no reason to give.
      none = tracker.unavailable == NoAnswer.notNeeded ? null : tracker.unavailable;
      thinking = tracker.unavailable == null;
    } else {
      none = null;
    }
    return SpectatorCoach(seat: seat, name: name, none: none, thinking: thinking);
  }

  /// The session moved on (or its trackers did): the coach may have a new
  /// answer, now or once the street being solved is done.
  void _coachMoved() {
    if (!spectating) return;
    _notify();
    final tracker = session.postflop;
    if (tracker != null && tracker.solving) unawaited(tracker.ready.then((_) => _notify(), onError: (Object _) {}));
  }

  /// The host changes a bot's style, from the next hand ([seat] as the
  /// players list shows it: the session's).
  @override
  void setStyle(int seat, BotStyle? style) {
    if (!isHost || seat >= session.players.length || !session.players[seat].isBot) return;
    setBotStyle(_sessionRoomSeats[seat], style?.name ?? 'random');
  }

  /// The host changes the bot in room seat [roomSeat] to [style] (see
  /// botStyleNames), from the next hand.
  void setBotStyle(int roomSeat, String style) {
    if (isHost && !ended) client.send(ChangeSettings(botStyles: {roomSeat: style}));
  }

  /// The host seats a bot with [style] in an empty seat ([roomSeat], or the
  /// first), or takes the bot in [roomSeat] away: from the next hand.
  void addBot(String style, {int? roomSeat}) {
    if (isHost && !ended) client.send(AddBot(style: style, seat: roomSeat));
  }

  void removeBot(int roomSeat) {
    if (isHost && !ended) client.send(RemoveBot(roomSeat));
  }

  /// The host changes the help, the time limit or whether the bots' styles
  /// show, from the next hand.
  void changeSettings(RoomSettings settings) {
    if (isHost) client.send(ChangeSettings(settings: settings));
  }

  // ---------------------------------------------------------------------------
  // Showing cards, and telling everyone about help
  // ---------------------------------------------------------------------------

  /// Whether the user may show their cards to everyone now: the hand they
  /// played is over (until the next is dealt), and they haven't yet.
  bool get canShowCards =>
      !watching &&
      handOver &&
      !ended &&
      _handNumber > 0 &&
      !_shownMine &&
      view.seats[TableSession.heroSeat].cards.length == 2;

  /// Shows the user's cards to everyone at the table (after the hand).
  void showCards() {
    if (!canShowCards) return;
    _shownMine = true;
    client.send(ShowCards(hand: _handNumber));
    _notify();
  }

  /// A player showed their cards after the hand: face up at their seat
  /// until the next is dealt, and everyone is told.
  void _onShown(CardsShown m) {
    if (m.hand != _handNumber) return;
    // The seats of the hand on screen (the next one's may be announced).
    final seat = _viewRoomSeats.indexOf(m.seat);
    if (seat < 0) return;
    final mine = isUserSeat(seat);
    if (!mine) {
      view.seats[seat]
        ..cards = m.cards
        ..cardsHeld = 2
        ..faceUp = true;
    }
    final note = HandNote(name: mine ? null : view.seats[seat].info.name, shown: m.cards);
    _toast(OnlineToast.note(note));
    _notify();
  }

  /// The user pressed Show GTO at their decision: everyone is told (once a
  /// decision).
  void usedHelp() {
    final turn = _myTurn;
    if (turn == null || !guessGto || ended) return;
    final decision = (_handNumber, turn.turnId);
    if (_helpSent == decision) return;
    _helpSent = decision;
    client.send(UsedHelp(hand: _handNumber, turnId: turn.turnId));
  }

  /// The host ends the room for everyone.
  void closeRoom() {
    if (isHost) client.send(const CloseRoom());
  }

  /// Out of chips, when the host allows rebuys: buys in again for the
  /// starting stack, from the next hand.
  void rebuy() {
    if (canRebuy) client.send(const Rebuy());
  }

  /// Sits out ([on]: not dealt in from the next hand, keeping the seat and
  /// chips), or is back: dealt in again from the next hand.
  void sitOut(bool on) {
    if (canSitOut) client.send(SitOut(on));
  }

  /// A spectator takes a seat (the first free one, else a bot's): from the
  /// next hand, or between hands for the one about to be dealt.
  void joinGame() {
    if (!ended) client.send(const TakeSeat());
  }

  /// Gives up the seat waited for (or, playing, the seat once the hand
  /// ends): back to watching as a spectator.
  void leaveSeat() {
    if (!ended) client.send(const LeaveSeat());
  }

  @override
  void dispose() {
    // Solves not started yet for this table won't be needed.
    _letGoOfOwner();
    unawaited(_statusChanges.cancel());
    unawaited(_chatLines.cancel());
    unawaited(_toasts.close());
    if (!_handedBack) {
      client.detach();
      unawaited(client.close());
    }
    super.dispose();
  }
}
