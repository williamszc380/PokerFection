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

/// The players of a hand, by this device's seat: their room seats, as the
/// server sent them, and as the table and the session play them; and
/// whether the user only watches it (out of chips).
typedef _Lineup = ({List<int> roomSeats, List<SeatInfo> infos, List<PlayerInfo> players, bool watching});

/// A move the user made before GTO's answer for it was worked out (the
/// table doesn't wait for it): scored once the answer comes. [choice] is
/// the menu's choice played (drawn from [mix], if [drew]); [action] a
/// raise of another amount, graded as [choice].
typedef _Unscored = ({
  int hand,
  int turnId,
  List<double> mix,
  int choice,
  bool drew,
  PlayerAction? action,
  bool oneAction,
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
/// With help on (the host picks it for the whole table), moves are sent as
/// soon as they are chosen, and the score shows without holding the table.
/// A pre-action the user picked while others acted is sent the moment their
/// turn opens.
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
/// A user out of chips (or who sits out) [watching] a hand isn't in it: its
/// seats are the server's, nobody is the user, and the session (help,
/// scores, the GTO bots) sits it out; on the host's device the bots then
/// play by their rules. Players out of chips, or who sit out, keep their
/// places at the table ([TableViewState.others]), the user's at the bottom.
/// Once the game is over ([gameOver]), nothing more is played here: the
/// room's lobby takes the connection back ([handBack]).
class OnlineTableController extends TableController {
  /// The table set up by [first], the line-up of a hand; [start] is the
  /// first message to follow, if not [first] itself (a snapshot, for a
  /// player who comes back during a hand).
  OnlineTableController(this.client, NextHand first, {ServerMessage? start, super.speed, super.random, super.solutions})
    : seats = _seatMapOf(first),
      _help = first.help,
      _nextHelp = first.help,
      _showCards = first.showCards,
      _nextShowCards = first.showCards,
      super(_configFor(client, first)) {
    _viewRoomSeats = _sessionRoomSeats = _lineupOf(first, client.isHost).roomSeats;
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

  /// The user is out of chips (or sits out) and watches the hand on screen.
  bool watching = false;

  /// The user sat out since they last played a hand: back, they watch until
  /// they are dealt in.
  bool _satOut = false;

  /// The game is over (once its last hand is shown): who won.
  GameOver? gameOver;

  /// The room's lobby took the connection back: the table leaves it open.
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

  /// The help in the hand on screen, and in the next one.
  HelpLevel _help, _nextHelp;

  /// GTO's answer for one of the user's turns (null: there is none), once
  /// worked out.
  ({int hand, int turnId, SpotStrategy? spot})? _answer;

  /// The user's moves made before their answers came, oldest first.
  final List<_Unscored> _unscored = [];

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

  /// Whether players may look at others' cards in the hand on screen, and
  /// in the next one.
  bool _showCards, _nextShowCards;

  /// Cards the user looked at in this hand, by seat (shown face up).
  final Map<int, List<PlayingCard>> _peeked = {};

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

  @override
  bool isUserSeat(int seat) => !watching && super.isUserSeat(seat);

  @override
  bool get guessGto => _help != HelpLevel.none;

  @override
  bool get advanced => _help == HelpLevel.advanced;

  /// The user is choosing, with help on, and GTO's answer is still being
  /// worked out (it joins the choices when ready).
  bool get helpPending {
    final turn = _myTurn, answer = _answer;
    if (!guessGto || turn == null || heroOptions == null) return false;
    return answer == null || answer.hand != _handNumber || answer.turnId != turn.turnId;
  }

  /// The table [next] sets up, as this device sees it: the user in seat 0,
  /// everyone else played elsewhere, except the bots on the host's device.
  static TableConfig _configFor(OnlineClient client, NextHand next) {
    final settings = client.room?.settings ?? const RoomSettings();
    return TableConfig(
      players: _lineupOf(next, client.isHost, stackBb: settings.stackBb).players,
      ante: settings.ante,
      raiseRule: settings.raiseRule,
      resetStacksEachHand: settings.resetStacks,
      guessGto: next.help != HelpLevel.none,
      advanced: next.help == HelpLevel.advanced,
    );
  }

  /// The players of the hand [next] announces, by this device's seat.
  static _Lineup _lineupOf(NextHand next, bool host, {int stackBb = 100}) {
    final seats = _seatMapOf(next);
    final watching = next.you == null;
    final infos = [for (var local = 0; local < seats.playerCount; local++) next.seats[seats.toServer(local)]];
    return (
      roomSeats: [for (final info in infos) info.seat],
      infos: infos,
      players: [
        for (final (local, info) in infos.indexed)
          _playerFor(info, me: !watching && local == 0, host: host, stackBb: stackBb),
      ],
      watching: watching,
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
          (e) => e.$1 is HandDealt || e.$1 is HandEvents || e.$1 is NextHand || e.$1 is BotCards || e.$1 is PeekCards,
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
      case PeekCards():
        _onPeek(m);
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
  /// moment, then the room's lobby (the table screen hands it back).
  void _onGameOver(GameOver m) {
    gameOver = m;
    _clearHeroDecision();
    _myTurn = null;
    nextHandAt = null;
    notice = null;
    _toast(OnlineToast.gameOver(m));
    _notify();
  }

  /// After the game is over: the room's lobby takes the connection back,
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
  /// device is ready.
  void _onNext(NextHand m) {
    final lineup = _lineupOf(m, isHost, stackBb: rules.stackBb);
    // The next hand's messages use its seats.
    seats = _seatMapOf(m);
    _nextLineup = lineup;
    final stacks = seats.listToLocal(m.stacks), button = seats.toLocal(m.button);
    _nextHelp = m.help;
    _nextShowCards = m.showCards;
    handOver = true;
    paused = false;
    nextHandAt = DateTime.now().add(Duration(milliseconds: m.maxWaitMs));
    // A hand the user watches: the session sits it out, and the server doesn't wait for this device.
    if (!lineup.watching) {
      _sessionJob(() async {
        _seatSession(lineup);
        session.announced = (stacks: stacks, button: button);
        session.guessGto = m.help != HelpLevel.none;
        session.setAdvanced(m.help == HelpLevel.advanced);
        _precomputeNext();
      });
      unawaited(_readyFor(m.hand, Duration(milliseconds: m.maxWaitMs)));
    }
    _notify();
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
    watching = lineup.watching;
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

  /// Tells the server this device is ready for hand [hand] (its last hand
  /// is shown already): at once, or when solving is needed (help, or GTO
  /// bots on the host's device), once the hand's whole preflop game is
  /// solved. The server deals anyway after [cap].
  Future<void> _readyFor(int hand, Duration cap) async {
    final watch = Stopwatch()..start();
    // The session knows the next hand's line-up and help once its jobs so far are done.
    await _within(_sessionTail, cap);
    if (session.needsSolver) {
      // Too slow (or failed): help, and the GTO bots, come later in the hand.
      await _within(_solutions.solve(session.upcomingSpec), cap - watch.elapsed);
    }
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
    _showCards = _nextShowCards;
    _peeked.clear();
    _myTurn = null;
    _answer = null;
    _sentMove = null;
    outOfSync = false;
    _shownBatches = 1;
    try {
      _mirror = _build(deal);
    } on MirrorMismatch catch (e) {
      _mirror = null;
      _lostSync(e);
    }
    if (!watching) _sessionJob(() => _sessionDeal(m.hand, deal));
    handOver = false;
    nextHandAt = null;
    _clearHeroDecision();
    _heroFolded = false;
    notice = null;
    await _play(batch);
    _afterBatch(m.turn, at);
  }

  /// The whole preflop game of hand [hand] (the next for the session),
  /// solved, if help or the GTO bots need it: waits for a solve still
  /// running, so the help comes late rather than not at all, unless the
  /// server deals another hand first. Null without it.
  Future<PreflopAdvisor?> _blueprint(int hand) async {
    if (!session.needsSolver) return null;
    final spec = session.upcomingSpec;
    final ready = _solutions.ready(spec);
    if (ready != null || _latest.$1 > hand) return ready;
    PreflopAdvisor? advisor;
    await _beforeNextHand(_solutions.solve(spec).then((a) => advisor = a), hand);
    return advisor;
  }

  PokerHand _build(RemoteDeal deal) => deal.build(
    smallBlind: TableConfig.smallBlind,
    bigBlind: TableConfig.bigBlind,
    ante: session.config.ante,
    raiseRule: session.config.raiseRule,
  );

  /// The session's copy of hand [hand], from [deal]: once its whole preflop
  /// game is solved, if help or the GTO bots need it.
  Future<void> _sessionDeal(int hand, RemoteDeal deal) async {
    _sessionBroken = false;
    session.announced = (stacks: deal.stacks, button: deal.buttonSeat);
    session.advisor = await _blueprint(hand);
    final h = session.startHand(deal);
    _sessionBatches = 1;
    await _track(hand);
    if (h.isOver) _finishSessionHand();
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
      } on MirrorMismatch catch (e) {
        _mirror = null;
        _lostSync(e);
      }
    }
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
    if (!watching) _sessionJob(() => _sessionStep(hand, batch));
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
    final lineup = _lineupOf(h.lineup, isHost, stackBb: rules.stackBb);
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
    // The cards the user looked at stay up.
    for (final MapEntry(key: seat, value: cards) in map.mapToLocal(h.peeks).entries) {
      _peeked[seat] = cards;
      view.seats[seat]
        ..cards = cards
        ..cardsHeld = 2
        ..faceUp = true;
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
    _showCards = _nextShowCards = h.lineup.showCards;
    _peeked.clear();
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
    // A hand the user watches: the session sits it out.
    if (!watching) {
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
          session.guessGto = _help != HelpLevel.none;
          session.setAdvanced(_help == HelpLevel.advanced);
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
          ..stack = same && !info.out ? info.chips ?? m.settings.startingStack : 0;
      }
    }
    final host = m.seats.where((s) => s.seat == m.host).firstOrNull;
    hostAway = m.phase == RoomPhase.playing && host?.status == SeatStatus.away;
    paused = m.phase == RoomPhase.playing && m.paused;
    if (paused) nextHandAt = null;
    final before = _lastRules;
    _lastRules = m.settings;
    if (before != null && before != m.settings && m.phase == RoomPhase.playing && !isHost) {
      _toast(const OnlineToast.rulesChanged());
    }
    _notify();
  }

  void _toast(OnlineToast toast) {
    if (!_toasts.isClosed) _toasts.add(toast);
  }

  /// Everyone is told what a player did: pressed Show GTO, or looked at
  /// someone's cards. It shows for a moment (in step with the table), and
  /// goes in the hand's record.
  void _onNotice(Notice m) {
    final mine = client.mySeat;
    final note = HandNote(
      name: m.seat == mine ? null : m.name,
      peek: m.kind == NoticeKind.peek,
      target: m.target == null || m.target == mine ? null : m.targetName,
    );
    _toast(OnlineToast.note(note));
    _sessionJob(() async {
      final record = session.history.lastOrNull;
      if (record != null && record.handNumber == m.hand) record.notes.add(note);
    });
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
  /// it is still running on the session's copy (as in [_waitForAnswers]):
  /// before the flop, the user's subgame; after it, the street. Null if
  /// there is nothing to wait for.
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

  /// Whether [future] completes within [limit].
  static Future<bool> _within(Future<void> future, Duration limit) =>
      future.timeout(limit.isNegative ? Duration.zero : limit).then((_) => true, onError: (Object _) => false);

  // ---------------------------------------------------------------------------
  // Help
  // ---------------------------------------------------------------------------

  /// Works out GTO's answer for the user's [turn] on the session's copy of
  /// the hand, once it has caught up and solved what it needs (the choices
  /// already show).
  void _answerFor(Turn turn) {
    final hand = _handNumber;
    _sessionJob(() async {
      final h = session.hand;
      SpotStrategy? spot;
      if (!_sessionBroken &&
          session.guessGto &&
          h != null &&
          h.handNumber == hand &&
          h.toAct == TableSession.heroSeat &&
          !h.isOver) {
        final wait = _answersFor(TableSession.heroSeat, hand);
        if (wait == null || await _beforeNextHand(wait, hand)) spot = session.heroSpot();
      }
      _answerCame(hand, turn.turnId, spot);
    });
  }

  /// GTO's answer (or that there is none) for the user's turn [turnId] of
  /// hand [hand], on the session's copy, which is at that turn. It joins
  /// the choices if they still show; a move already made with them is
  /// scored now.
  void _answerCame(int hand, int turnId, SpotStrategy? spot) {
    _answer = (hand: hand, turnId: turnId, spot: spot);
    final turn = _myTurn;
    if (turn != null && turn.turnId == turnId && hand == _handNumber && heroOptions != null) {
      if (spot != null) {
        heroSpot = spot;
        heroMenu = spot.actions;
      }
    } else {
      final i = _unscored.indexWhere((played) => played.hand == hand && played.turnId == turnId);
      if (i >= 0) {
        final played = _unscored.removeAt(i);
        if (spot != null) _scoreLate(played, spot);
      }
    }
    // Older ones won't get an answer any more (the session caught up without).
    _unscored.removeWhere((played) => played.hand < hand);
    _notify();
  }

  void _dropUnscored(int hand, int turnId) =>
      _unscored.removeWhere((played) => played.hand == hand && played.turnId == turnId);

  /// Scores [played], a move made before its answer [spot] came, and
  /// records it. It shows (without holding the table) unless the user is
  /// choosing again already.
  void _scoreLate(_Unscored played, SpotStrategy spot) {
    final h = session.hand!, record = session.history.lastOrNull;
    final actions = spot.actions;
    if (record == null || record.handNumber != played.hand || played.mix.length != actions.length) return;
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
    record.decisions.add(
      DecisionRecord(
        street: h.street,
        board: h.board,
        spot: spot,
        mix: List.unmodifiable(mix),
        score: score,
        oneAction: played.oneAction,
        turnId: played.turnId,
      )..played = choice,
    );
    if (heroOptions != null || _quietGrade(score, oneAction: played.oneAction)) return;
    heroSpot = spot;
    heroMix = List.unmodifiable(mix);
    heroScore = score;
    heroPlay = choice;
    heroDrew = played.drew;
    heroAction = played.action;
  }

  /// [choice] of [actions] (the same menu, now with GTO's answer) if GTO
  /// has solved it; for a raise it hasn't, the nearest size it has (for a
  /// raise of another amount, [action], nearest to that). Null if none.
  static int? _solvedChoice(List<SpotAction> actions, int choice, PlayerAction? action) {
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

  /// The server checked or folded for the user at turn [turnId] (their
  /// time ran out first): a decision recorded for it says so.
  void _correctRecord(int hand, int turnId, ActionTaken played) {
    final record = session.history.lastOrNull;
    if (record == null || record.handNumber != hand) return;
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

  /// Plays the bot in [seat] at [turn] (on the host's device). A GTO bot
  /// waits for the session's copy of the hand to catch up and its solve to
  /// finish, for a few seconds at most; otherwise, or for the other styles,
  /// the bot plays by its rules on the table's copy.
  Future<void> _playBot(Turn turn, int seat) async {
    final hand = _handNumber;
    final watch = Stopwatch()..start();
    await Future<void>.delayed(Playback.botThink);
    final limit = turn.ms ?? OnlineTiming.botLimit.inMilliseconds;
    final cap = Duration(milliseconds: max(0, min(6000, limit - 3000)));
    var caughtUp = await _within(_sessionTail, cap - watch.elapsed);
    if (caughtUp) caughtUp = await _within(_answersFor(seat, hand) ?? Future.value(), cap - watch.elapsed);
    if (_disposed || ended || _latest != (hand, turn.turnId)) return;
    PlayerAction? move;
    final h = session.hand;
    if (caughtUp && !_sessionBroken && h != null && h.handNumber == hand && h.toAct == seat && !h.isOver) {
      try {
        move = session.botDecision();
      } catch (e) {
        debugPrint('Online table: bot decision failed: $e');
      }
    }
    final mirror = _mirror;
    if (move == null) {
      // The server checks or folds for it when time runs out.
      if (mirror == null || mirror.toAct != seat) return;
      // A random style is the session's secret, once it has this hand's players.
      final secret = listEquals(_sessionRoomSeats, _viewRoomSeats) ? session.styles[seat] : null;
      final style = view.seats[seat].info.style ?? secret ?? BotStyle.tag;
      move = Bot(style, _random).decide(mirror, seat);
    }
    client.send(BotAct(hand: hand, turnId: turn.turnId, seat: seats.toServer(seat), action: move));
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
      session.history.lastOrNull?.decisions.removeWhere((d) => d.turnId == turn.turnId);
      super.submitMix(mix, choice: choice, oneAction: oneAction);
    }
    final play = heroPlay ?? choice ?? _drawFrom(menu, mix);
    if (heroSpot == null && guessGto) {
      _unscored.add((
        hand: _handNumber,
        turnId: turn.turnId,
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

  /// As in simple training on the device, a good play just goes on (its
  /// score joins the recent ones); GTO's answer shows after a mistake or a
  /// blunder, and always in advanced training.
  static bool _quietGrade(DecisionScore score, {required bool oneAction}) =>
      oneAction && score.grade.index < DecisionGrade.mistake.index;

  @override
  int? get _recordTurnId => _myTurn?.turnId;

  /// A move made before GTO's answer comes is graded once it does.
  @override
  bool get _gradesPlay => heroSpot != null || helpPending;

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

  /// A hand played again from a snapshot makes no sound.
  @override
  void _sound(SoundEffect effect) {
    if (!_replaying) super._sound(effect);
  }

  /// The server deals the hands.
  @override
  Future<void> startNextHand() async {}

  /// The host picks the help for the whole table.
  @override
  void setAdvanced(bool value) {}

  /// Other players' cards stay hidden online (unless the host lets players
  /// look: see [peek]).
  @override
  void toggleCards(int seat) {}

  @override
  void toggleAllCards() {}

  @override
  bool _cardsShown(int seat) => _peeked.containsKey(seat);

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

  /// The host changes the help, the time limit, whether the bots' styles
  /// show or whether players may look at others' cards, from the next hand.
  void changeSettings(RoomSettings settings) {
    if (isHost) client.send(ChangeSettings(settings: settings));
  }

  // ---------------------------------------------------------------------------
  // Looking at cards, and telling everyone about help
  // ---------------------------------------------------------------------------

  /// Whether the host lets players look at others' cards in this hand.
  bool get cardsAllowed => _showCards;

  /// Whether the user may ask to see the cards of [seat] now: looking is
  /// allowed, the hand is on, and they're someone else's (not seen yet).
  bool canPeek(int seat) =>
      _showCards &&
      !ended &&
      !watching &&
      !handOver &&
      _handNumber > 0 &&
      seat != TableSession.heroSeat &&
      seat < playerCount &&
      !_peeked.containsKey(seat);

  /// Asks to see [seat]'s cards: the server sends them to this device only,
  /// and tells everyone.
  void peek(int seat) {
    if (canPeek(seat)) client.send(Peek(hand: _handNumber, seat: seats.toServer(seat)));
  }

  /// The cards the user asked for: face up for the rest of the hand (a
  /// player who folded gets them back, dimmed).
  void _onPeek(PeekCards m) {
    if (m.hand != _handNumber) return;
    final seat = seats.toLocal(m.seat);
    _peeked[seat] = m.cards;
    view.seats[seat]
      ..cards = m.cards
      ..cardsHeld = 2
      ..faceUp = true;
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

  /// The host removes the player in room seat [roomSeat] ([name]): at once,
  /// or when the hand they play ends. They can't join the room again.
  void removePlayer(int roomSeat, String name) {
    if (isHost && !ended) client.send(RemovePlayer(seat: roomSeat, name: name));
  }

  @override
  void dispose() {
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
