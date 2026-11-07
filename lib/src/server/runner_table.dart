part of 'room.dart';

/// A round as it was dealt: the room seat of each hand seat, the token of
/// the person there (null for a bot), each bot's level (null for a
/// person), and whether spectators see the bots' hidden cards in it (the
/// host's switch when it was dealt).
typedef _Dealt = ({List<int> seats, List<String?> tokens, List<String?> levels, bool seeBots});

/// The table of a game other than Hold'em, played through the game's
/// [GameRunner] (see game_runner.dart): its seats (the setup's, empty at
/// first), the rounds, each turn's clock, and what each member is sent.
///
/// lobby → Start (the host; every seat taken, or at least the game's
/// least for a game dealt to the seats taken) → between rounds → a round
/// is dealt (round 1 at once; later ones once its least time to see the
/// last result has passed and every seated person is ready, or at the
/// game's latest) → its turns → round over: the seats settle → between
/// rounds again, or the lobby when the host ended the game. With too few
/// who can play between rounds, the game waits for players (paused).
///
/// Seats change at once in the lobby, between rounds and while the game
/// waits; during a round a member's request waits for its end (they watch
/// it), as poker's does. A person's request takes a bot's seat if there is
/// no free one (the bot leaves at the round's end).
///
/// Turns have the poker clock: the setup's time per move (or none) for a
/// person, a few seconds while they are away, none once they left, and for
/// a bot the host's device's time (shorter while the host is away): when
/// it runs out the room plays the runner's [GameRunner.autoMove]. A
/// member's refused moves at a turn are ignored after a few, until the
/// turn's clock runs out or their device asks for a fresh copy.
///
/// Every change sends every member their full view: a seat in the round
/// its own ([GameRunner.seatView]), everyone else the spectators' (one copy
/// for them all, with the round's coach seed: [GameRunner.spectatorView],
/// the bots' hidden cards only when the round was dealt with the host's
/// switch on). The host's device also gets each bot's turn with that bot's
/// own view, and plays it. Every deal draws from the room's secure Random.
class _RunnerTable implements _Table {
  _RunnerTable(this.room, this.game, this._setup) : _seats = [for (var s = 0; s < _setup.seats; s++) _Seat()];

  final Room room;
  final OnlineGame game;
  OnlineSetup _setup;

  /// The room seats; a bot's [_Seat.botStyle] is its level.
  List<_Seat> _seats;

  RoomPhase _phase = RoomPhase.lobby;

  /// Playing, but too few can play: no round is dealt until enough can.
  bool _paused = false;

  /// Between rounds: the next one is dealt not before [_earliestDeal]
  /// (ms) and once every seated person is ready ([_maxTimer] deals it at
  /// the latest).
  bool _between = false;
  int _earliestDeal = 0;
  Timer? _minTimer, _maxTimer;

  /// The host ended the game during a round: the lobby when it ends.
  bool _ending = false;

  /// The game being played (from Start to the game's end).
  GameRunner? _runner;

  /// The last round dealt (0 before the first), and the messages sent in
  /// it so far.
  int _round = 0;
  int _seq = 0;

  /// The round being played (or the last, until the next is dealt).
  _Dealt? _dealt;

  /// The open turn: its id, the hand seat to act (null: none, between
  /// rounds), the time shown for it and when its clock starts and the
  /// time shown runs out (ms; null for no limit).
  int _turnId = 0;
  int? _turnSeat;
  int? _turnMs;
  int _turnStartsAt = 0;
  int? _turnShownEnd;
  Timer? _turnTimer;

  /// Asks the host's device for a bot's turn once the devices have shown
  /// what comes before it (the round's who-goes-first step).
  Timer? _askTimer;

  /// The move just made, and the round's result once it is over.
  EnvelopeLast? _last;
  EnvelopeOver? _over;

  /// A fresh random number per round, for the spectators' coach (never
  /// tied to the deal).
  int _coachSeed = 0;

  /// The host's connection that plays the bots this round, and the bot's
  /// turn it was asked to play.
  ClientLink? _botDriver;
  EnvelopeBotRequest? _botRequest;

  /// Refused moves at the open turn, by member token.
  final Map<String, int> _rejects = {};

  /// Each seat's score in this game, by room seat (cleared when the seat
  /// changes hands or the game ends).
  final Map<int, num> _scores = {};

  /// During a round: the host's bots for the next one, by room seat (a bot
  /// added, or a new level), or null for a bot taken away.
  final Map<int, String?> _botChanges = {};

  /// Seats a member asked for during a round whose bot leaves for them at
  /// its end: the bot's queued change before (to put back if they change
  /// their mind).
  final Map<int, (bool, String?)> _displaced = {};

  SeatRange get _range => game.seatsFor(_setup.rules);

  // ---------------------------------------------------------------------------
  // What the room calls (see _Table)
  // ---------------------------------------------------------------------------

  @override
  RoomPhase get phase => _phase;

  @override
  bool get paused => _paused;

  @override
  bool get seatsOpen => _phase == RoomPhase.lobby || _paused;

  @override
  List<SeatInfo> seatInfos({required bool showStyles}) => [
    for (var s = 0; s < _seats.length; s++) _seatInfo(s, showLevel: showStyles),
  ];

  @override
  RoomSettings? get holdemSettings => null;

  /// The bots' levels are no secret in these games.
  @override
  bool showsStylesTo(RoomPlayer p) => true;

  /// The latest view of the round (as a seat in it, or as a spectator); the
  /// host also the bot's turn being played.
  @override
  void caughtUp(RoomPlayer p, {required bool joining}) {
    if (_dealt == null || _runner == null) return;
    room._send(p, _stateFor(p, catchUp: true));
    final request = _botRequest;
    if (request != null && p.token == room._hostToken && p.link != null && p.link == _botDriver) {
      room._send(p, _envelope(request));
    }
  }

  /// A fresh copy, and their refused moves at this turn forgotten (so a
  /// device that went wrong can't leave a turn stuck).
  @override
  void resync(RoomPlayer p) {
    _rejects.remove(p.token);
    caughtUp(p, joining: false);
  }

  @override
  void onRejoin(RoomPlayer p) {
    // The host's device plays the bots again (it is sent the bot's turn when caught up).
    if (p.token == room._hostToken && _turnSeat != null) _botDriver = p.link;
    room._guarded(() => _restartClockFor(p));
  }

  @override
  void afterRejoin(RoomPlayer p, {required bool back}) => _maybeResume();

  @override
  void onAway(RoomPlayer p) => _restartClockFor(p);

  @override
  void afterAway() => _maybeDeal();

  /// In the lobby, between rounds and while the game waits, and for a
  /// spectator (or one waiting for a seat), they go at once, with their
  /// seat; in a round the room plays their turns, and the seat is empty
  /// from its end.
  @override
  void onLetGo(RoomPlayer p) {
    if (_open || p.spectator) {
      room._players.remove(p.token);
      final seat = p.seat;
      if (p.waiting) {
        _unqueue(p);
      } else if (seat != null && _seats[seat].token == p.token) {
        _empty(seat);
      }
    } else {
      p.left = true;
      // Their turn now is played at once.
      _restartClockFor(p);
    }
  }

  @override
  void afterLeave() => _seatsChanged(sendRoom: false);

  /// A player in the round being played.
  @override
  bool playsRound(RoomPlayer p) => !p.spectator && _turnSeat != null && (_dealt?.tokens.contains(p.token) ?? false);

  @override
  void afterRemoval() => _seatsChanged();

  /// Only the bots' levels (the game's rules come with ChooseGame): at once
  /// in the lobby and between rounds, else from the next round.
  @override
  void changeSettings(RoomPlayer p, ChangeSettings m) {
    if (p.token != room._hostToken) throw const _Refused(Rejection.notHost);
    final levels = m.botStyles ?? const <int, String>{};
    if (m.settings != null || levels.values.any((level) => !game.botLevels.contains(level))) {
      throw const _Refused(Rejection.illegal);
    }
    for (final MapEntry(key: seat, value: level) in levels.entries) {
      if (seat >= _seats.length) continue;
      if (_open) {
        if (_seats[seat].isBot) _seats[seat].botStyle = level;
      } else if (_botChanges[seat] != null || (_seats[seat].isBot && !_botChanges.containsKey(seat))) {
        _botChanges[seat] = level;
      }
    }
    room._sendRoom();
    room._watchIdle();
  }

  /// The host seats a bot at [level]: in [preferred], or the first free
  /// seat (during a round, from the next).
  @override
  void addBot(RoomPlayer p, String level, int? preferred) {
    if (p.token != room._hostToken) throw const _Refused(Rejection.notHost);
    if (!game.botLevels.contains(level)) throw const _Refused(Rejection.illegal);
    final seat = _freeSeat(preferred);
    if (seat == null) throw const _Refused(Rejection.illegal);
    if (_open) {
      _seats[seat].botStyle = level;
      _scores.remove(seat);
    } else {
      _botChanges[seat] = level;
    }
    _seatsChanged();
  }

  @override
  void removeBot(RoomPlayer p, int seat) {
    if (p.token != room._hostToken) throw const _Refused(Rejection.notHost);
    if (seat >= _seats.length) throw const _Refused(Rejection.illegal);
    final s = _seats[seat];
    if (_open) {
      if (!s.isBot) throw const _Refused(Rejection.illegal);
      s.botStyle = null;
      _scores.remove(seat);
    } else if (_botChanges[seat] != null) {
      // A bot still to come (or with a new level) is simply not seated.
      if (s.isBot) {
        _botChanges[seat] = null;
      } else {
        _botChanges.remove(seat);
      }
    } else if (s.isBot && !_botChanges.containsKey(seat)) {
      _botChanges[seat] = null;
    } else {
      throw const _Refused(Rejection.illegal);
    }
    _seatsChanged();
  }

  /// The host starts the game: every seat taken (or, for a game dealt to
  /// the seats taken, its least); round 1 is dealt at once.
  @override
  void start(RoomPlayer p) {
    if (p.token != room._hostToken) throw const _Refused(Rejection.notHost);
    if (_phase != RoomPhase.lobby) throw const _Refused(Rejection.stale);
    final taken = _seats.where((s) => !s.isEmpty).length;
    if (taken < _range.needed(_seats.length) || taken < _range.min) throw const _Refused(Rejection.illegal);
    _phase = RoomPhase.playing;
    _runner = game.newRunner(_setup, room._random);
    _round = 0;
    _scores.clear();
    for (final q in room._players.values) {
      q.ready = false;
    }
    _betweenRounds(minWait: Duration.zero);
  }

  /// [p] takes a seat: [preferred], or the first free one, or a bot's. At
  /// once in the lobby, between rounds and while the game waits; during a
  /// round from the next one (they watch it).
  @override
  void takeSeat(RoomPlayer p, int? preferred) {
    if (p.seat != null) throw const _Refused(Rejection.illegal);
    final seat = _seatFor(preferred);
    if (seat == null) throw const _Refused(Rejection.illegal);
    final s = _seats[seat];
    if (_open) {
      // A bot gives way at once.
      s.botStyle = null;
      s.token = p.token;
      p.seat = seat;
      _scores.remove(seat);
      _seatsChanged();
      return;
    }
    if (_botNextRound(seat)) {
      _displaced[seat] = (_botChanges.containsKey(seat), _botChanges[seat]);
      _botChanges[seat] = null;
    }
    p.waiting = true;
    p.seat = seat;
    room._sendRoom();
  }

  /// [p] gives up their seat, or the one they wait for: at once in the
  /// lobby, between rounds and while the game waits; during a round they
  /// play it out, and watch from its end.
  @override
  void leaveSeat(RoomPlayer p) {
    final seat = p.seat;
    if (seat == null) throw const _Refused(Rejection.illegal);
    if (p.waiting) {
      _unqueue(p);
      room._sendRoom();
      return;
    }
    if (p.standing) return;
    if (_open) {
      if (_seats[seat].token == p.token) _empty(seat);
      p.seat = null;
      _seatsChanged();
      return;
    }
    p.standing = true;
    room._sendRoom();
  }

  /// Back to the lobby now between rounds (or while the game waits), else
  /// once the round being played ends.
  @override
  void endGame() {
    if (_phase != RoomPhase.playing || _ending) throw const _Refused(Rejection.illegal);
    if (_paused || _turnSeat == null) {
      _gameOver();
      return;
    }
    _ending = true;
  }

  /// The game's messages; poker's are for a hand that isn't there.
  @override
  void receive(RoomPlayer p, ClientMessage m) {
    switch (m) {
      case GameMessage():
        _gameMessage(p, m);
      case Act(:final turnId) || BotAct(:final turnId) || UsedHelp(:final turnId):
        throw _Refused(Rejection.stale, turnId: turnId);
      case Rebuy() || SitOut():
        throw const _Refused(Rejection.illegal);
      default:
        throw const _Refused(Rejection.stale);
    }
  }

  @override
  void close() {
    _turnTimer?.cancel();
    _askTimer?.cancel();
    _minTimer?.cancel();
    _maxTimer?.cancel();
  }

  /// The host changed the setup in the lobby (ChooseGame, the same game):
  /// people and bots keep their seats where they still exist, the others
  /// move to the first empty ones. Refused with fewer seats than are taken.
  void changeSetup(OnlineSetup setup) {
    final n = setup.seats;
    if (n != _seats.length) {
      if (_seats.where((s) => !s.isEmpty).length > n) throw const _Refused(Rejection.illegal);
      final old = _seats;
      _seats = [for (var s = 0; s < n; s++) _Seat()];
      final moved = <_Seat>[];
      for (final (s, seat) in old.indexed) {
        if (seat.isEmpty) continue;
        if (s < n) {
          _seats[s] = seat;
        } else {
          moved.add(seat);
        }
      }
      for (final seat in moved) {
        final free = _seats.indexWhere((s) => s.isEmpty);
        _seats[free] = seat;
        if (seat.token case final token?) room._players[token]!.seat = free;
      }
    }
    _setup = setup;
  }

  // ---------------------------------------------------------------------------
  // Seats
  // ---------------------------------------------------------------------------

  /// Seats change at once: the lobby, between rounds, while the game waits.
  bool get _open => seatsOpen || _between;

  /// Everyone connected.
  Iterable<RoomPlayer> get _everyone => room._players.values.where((p) => p.connected);

  /// Nobody has room seat [seat] any more (its score goes with them).
  void _empty(int seat) {
    _seats[seat].token = null;
    _scores.remove(seat);
  }

  /// Whether room seat [seat] is dealt in the next round: a bot, or a
  /// person who hasn't left and doesn't give the seat up.
  bool _dealtIn(int seat) {
    final s = _seats[seat];
    if (s.isEmpty) return false;
    final p = room._players[s.token];
    return p == null ? s.isBot : !p.left && !p.standing;
  }

  /// Whether whoever has room seat [seat] can play now: a person who is
  /// connected, or a bot while the host's device is there to play it.
  bool _canPlay(int seat) {
    final s = _seats[seat];
    if (s.token case final token?) {
      final p = room._players[token];
      return p != null && p.connected && !p.standing;
    }
    return s.isBot && room._host != null;
  }

  /// The room seats the next round is dealt to.
  List<int> _lineupNow() => [
    for (var s = 0; s < _seats.length; s++)
      if (_dealtIn(s)) s,
  ];

  /// Whether [lineup] may be dealt: every seat, all able to play (most
  /// games); or, for a game dealt to the seats taken, at least its least
  /// who can play.
  bool _enough(List<int> lineup) {
    final range = _range;
    if (range.everySeat) return lineup.length == _seats.length && lineup.every(_canPlay);
    return lineup.where(_canPlay).length >= range.min;
  }

  /// Whether nobody has room seat [seat] from the next round.
  bool _freeNextRound(int seat) {
    if (room._players.values.any((p) => p.waiting && p.seat == seat)) return false;
    if (_botChanges.containsKey(seat)) return _botChanges[seat] == null;
    final s = _seats[seat];
    if (s.token != null) {
      final p = room._players[s.token];
      return p == null || p.left || p.removing || p.standing;
    }
    return !s.isBot;
  }

  /// The first room seat free from the next round ([preferred] if it is).
  int? _freeSeat([int? preferred]) {
    if (preferred != null && preferred < _seats.length && _freeNextRound(preferred)) return preferred;
    for (var s = 0; s < _seats.length; s++) {
      if (_freeNextRound(s)) return s;
    }
    return null;
  }

  /// Whether a bot has room seat [seat] from the next round, with nobody
  /// waiting for it.
  bool _botNextRound(int seat) {
    if (_seats[seat].token != null || room._players.values.any((p) => p.waiting && p.seat == seat)) return false;
    return _botChanges.containsKey(seat) ? _botChanges[seat] != null : _seats[seat].isBot;
  }

  /// The seat a member asking for [preferred] (or any) gets: that one if
  /// free, else the first free one, else a bot's ([preferred] if a bot has
  /// it, else the highest). Null when every seat holds a person.
  int? _seatFor(int? preferred) {
    final free = _freeSeat(preferred);
    if (free != null) return free;
    if (preferred != null && preferred < _seats.length && _botNextRound(preferred)) return preferred;
    for (var s = _seats.length - 1; s >= 0; s--) {
      if (_botNextRound(s)) return s;
    }
    return null;
  }

  /// [p] no longer waits for their seat: a bot it was to take stays.
  void _unqueue(RoomPlayer p) {
    final seat = p.seat;
    p.waiting = false;
    p.seat = null;
    if (seat == null) return;
    if (_displaced.remove(seat) case (final had, final level)) {
      if (had) {
        _botChanges[seat] = level;
      } else {
        _botChanges.remove(seat);
      }
    }
  }

  /// The seats changed (at once, or queued): everyone is told; between
  /// rounds the round waits for players if too few can play now, or may be
  /// dealt (someone who held it up left); while it waits, it may go on.
  void _seatsChanged({bool sendRoom = true}) {
    if (_between && !_enough(_lineupNow())) {
      _pause();
      return;
    }
    if (sendRoom) {
      room._sendRoom();
      room._watchIdle();
    }
    _maybeDeal();
    _maybeResume();
  }

  /// At a round's end (and when the game ends): those the host removed go,
  /// those who left give up their seats, those who leave their seats watch,
  /// those away the whole round watch too (their seat is free), the host's
  /// bots come and go, and those who asked for a seat sit down.
  void _settleSeats() {
    for (final p in [...room._players.values]) {
      if (p.removing) room._expel(p);
    }
    for (final p in [...room._players.values]) {
      if (!p.left) continue;
      room._players.remove(p.token);
      final seat = p.seat;
      if (seat != null && _seats[seat].token == p.token) _empty(seat);
    }
    for (final p in room._players.values) {
      final seat = p.seat;
      final away = p._awayAllHand && p.away;
      p._awayAllHand = false;
      if (seat == null || p.waiting || !(p.standing || away)) continue;
      if (_seats[seat].token == p.token) _empty(seat);
      p.seat = null;
      p.standing = false;
    }
    for (final MapEntry(key: seat, value: level) in _botChanges.entries) {
      final s = _seats[seat];
      if (s.token != null) continue;
      if (level == null || !s.isBot) _scores.remove(seat);
      s.botStyle = level;
    }
    _botChanges.clear();
    _displaced.clear();
    for (final p in room._players.values) {
      final seat = p.seat;
      if (!p.waiting || seat == null) continue;
      p.waiting = false;
      _seats[seat].token = p.token;
      _scores.remove(seat);
    }
  }

  // ---------------------------------------------------------------------------
  // Rounds
  // ---------------------------------------------------------------------------

  /// Between rounds: the seats settle; with enough who can play the next
  /// round is dealt once [minWait] has passed and every seated person is
  /// ready (round 1: at once), at the game's latest anyway; else the game
  /// waits for players. [newRound]: after a round's end (everyone's Ready
  /// counts afresh).
  void _betweenRounds({required Duration minWait, bool newRound = false}) {
    _turnTimer?.cancel();
    _askTimer?.cancel();
    _turnSeat = null;
    _settleSeats();
    _between = false;
    _minTimer?.cancel();
    _maxTimer?.cancel();
    if (newRound) {
      for (final p in room._players.values) {
        p.ready = false;
      }
    }
    if (!_enough(_lineupNow())) {
      _pause();
      return;
    }
    _paused = false;
    room._idle?.cancel();
    room._idle = null;
    _between = true;
    final latest = minWait > game.maxBetweenRounds ? minWait : game.maxBetweenRounds;
    _earliestDeal = room._clock.nowMs + minWait.inMilliseconds;
    _minTimer = room._clock.schedule(minWait, () => room._guarded(_maybeDeal));
    _maxTimer = room._clock.schedule(latest, () => room._guarded(_deal));
    room._sendRoom();
  }

  /// Too few can play: no round is dealt until enough can (see
  /// [_maybeResume]); meanwhile seats change at once.
  void _pause() {
    _paused = true;
    _between = false;
    _minTimer?.cancel();
    _maxTimer?.cancel();
    room._sendRoom();
    room._watchIdle();
  }

  /// While the game waits for players: on as soon as enough can play.
  void _maybeResume() {
    if (_phase != RoomPhase.playing || !_paused || room._closed) return;
    if (_enough(_lineupNow())) _betweenRounds(minWait: Duration.zero);
  }

  /// Deals once the least time has passed and every seated person who is
  /// connected is ready (not for round 1: nobody has seen anything yet).
  void _maybeDeal() {
    if (!_between || room._clock.nowMs < _earliestDeal) return;
    if (_round > 0) {
      for (final s in _lineupNow()) {
        final p = room._players[_seats[s].token];
        if (p != null && p.connected && !p.ready) return;
      }
    }
    _deal();
  }

  void _deal() {
    if (!_between || room._closed) return;
    _between = false;
    _minTimer?.cancel();
    _maxTimer?.cancel();
    final lineup = _lineupNow();
    // Someone went away meanwhile: too few can play now.
    if (!_enough(lineup)) {
      _pause();
      return;
    }
    final runner = _runner!;
    _round++;
    _seq = 0;
    _last = null;
    _over = null;
    final dealt = _dealt = (
      seats: lineup,
      tokens: [for (final s in lineup) _seats[s].token],
      levels: [for (final s in lineup) _seats[s].token == null ? _seats[s].botStyle : null],
      seeBots: room._seeBots,
    );
    // Those away now watch from the round's end if they are still away then.
    for (final token in dealt.tokens) {
      if (room._players[token] case final p?) p._awayAllHand = p.away;
    }
    _botDriver = room._host?.link;
    runner.startRound(_round, [for (final token in dealt.tokens) token == null]);
    _coachSeed = room._random.nextInt(1 << 31);
    if (runner.roundOver) {
      _roundOver();
      return;
    }
    // Every device shows who goes first before the first move, so the
    // first clock (and the host's first bot) waits for that step: a
    // starter with a time limit doesn't lose two seconds of it to the
    // animation, and a bot's opening move doesn't land during it.
    final opening = _capped(runner.openingMs);
    _openTurn(wait: opening);
    _broadcast();
    _askBotAfter(opening);
  }

  /// The next turn (the runner says whose), with its clock running after
  /// [wait] (the last move shown).
  void _openTurn({required Duration wait}) {
    _turnTimer?.cancel();
    _askTimer?.cancel();
    _rejects.clear();
    _botRequest = null;
    final seat = _turnSeat = _runner!.seatToAct;
    if (seat == null) return;
    _turnId++;
    _armTimer(wait);
  }

  /// How long whoever plays hand seat [seat] gets to act (null for no
  /// limit), the time shown, and why the room acts for them after it.
  ({Duration? deadline, int? shown, EnvelopeCause cause}) _limit(int seat) {
    final token = _dealt!.tokens[seat];
    if (token != null) {
      final p = room._players[token];
      if (p == null || p.left) return (deadline: Duration.zero, shown: 0, cause: EnvelopeCause.left);
      if (p.away) {
        return (
          deadline: OnlineTiming.awayLimit,
          shown: OnlineTiming.awayLimit.inMilliseconds,
          cause: EnvelopeCause.away,
        );
      }
      final seconds = _setup.turnLimit;
      if (seconds == 0) return (deadline: null, shown: null, cause: EnvelopeCause.timeout);
      return (
        deadline: Duration(seconds: seconds) + OnlineTiming.grace,
        shown: seconds * 1000,
        cause: EnvelopeCause.timeout,
      );
    }
    final host = room._host;
    if (host != null && host.link != null && host.link == _botDriver) {
      return (
        deadline: OnlineTiming.botLimit,
        shown: OnlineTiming.botLimit.inMilliseconds,
        cause: EnvelopeCause.timeout,
      );
    }
    return (
      deadline: OnlineTiming.hostAwayBotLimit,
      shown: OnlineTiming.hostAwayBotLimit.inMilliseconds,
      cause: EnvelopeCause.hostAway,
    );
  }

  /// (Re)starts the open turn's clock, after [wait].
  void _armTimer(Duration wait) {
    _turnTimer?.cancel();
    final seat = _turnSeat!, turnId = _turnId;
    final limit = _limit(seat);
    final deadline = limit.deadline, shown = limit.shown, now = room._clock.nowMs;
    _turnMs = shown;
    _turnStartsAt = now + wait.inMilliseconds;
    _turnShownEnd = shown == null ? null : _turnStartsAt + shown;
    if (deadline == null) return;
    _turnTimer = room._clock.schedule(wait + deadline, () => room._guarded(() => _timeUp(turnId, limit.cause)));
  }

  /// [p] went away, came back or left: if it is their turn (or for the
  /// host, a bot's), its clock starts again from now, with their new limit.
  void _restartClockFor(RoomPlayer p) {
    final seat = _turnSeat, dealt = _dealt;
    if (seat == null || dealt == null) return;
    final token = dealt.tokens[seat];
    if (token == p.token || (token == null && p.token == room._hostToken)) _armTimer(Duration.zero);
  }

  /// The clock ran out: the room plays for them.
  void _timeUp(int turnId, EnvelopeCause cause) {
    final seat = _turnSeat;
    if (seat == null || turnId != _turnId) return;
    // Someone at the table who let the clock run out gets the move doing
    // nothing makes; a seat nobody is playing may get a different one (see
    // GameRunner.autoMove).
    _play(seat, _runner!.autoMove(seat, absent: cause != EnvelopeCause.timeout), cause);
  }

  /// A game message from [p]: a move, a bot's move (the host's device), or
  /// Ready for the next round. One for another game (or version) is for a
  /// round that isn't there.
  void _gameMessage(RoomPlayer p, GameMessage m) {
    final body = m.body;
    final turnId = switch (body) {
      EnvelopeMove(:final turnId) || EnvelopeBotMove(:final turnId) => turnId,
      _ => null,
    };
    if (m.game != game.key || m.gv != game.gv) throw _Refused(Rejection.stale, turnId: turnId);
    switch (body) {
      case EnvelopeReady(:final round):
        // A late one (the round is dealt already) needs nothing.
        if (!_between || round != _round + 1) return;
        p.ready = true;
        _maybeDeal();
      case EnvelopeMove(:final round, :final turnId, :final move):
        _move(p, round, turnId, move);
      case EnvelopeBotMove(:final round, :final turnId, :final move, :final seat):
        _move(p, round, turnId, move, botSeat: seat);
      default:
        throw _Refused(Rejection.stale, turnId: turnId);
    }
  }

  /// [move] at turn [turnId] of round [round], by [p] for their own seat,
  /// or by the host's device for the bot in hand seat [botSeat].
  void _move(RoomPlayer p, int round, int turnId, String move, {int? botSeat}) {
    final seat = _turnSeat, dealt = _dealt;
    if (seat == null || dealt == null || round != _round || turnId != _turnId) {
      throw _Refused(Rejection.stale, turnId: turnId);
    }
    final allowed = botSeat == null
        ? p.connected && dealt.tokens[seat] == p.token
        : p.link != null && p.link == _botDriver && botSeat == seat && dealt.tokens[seat] == null;
    if (!allowed) throw _Refused(Rejection.notYourTurn, turnId: turnId);
    // After a few refused moves, more are ignored until the clock runs out (or a fresh copy).
    final rejects = _rejects[p.token] ?? 0;
    if (rejects >= HandRunner.maxRejects) throw _Refused(Rejection.rateLimited, turnId: turnId);
    // A game's check that throws on a move it can't read refuses that one
    // move: it never reaches the room's catch-all, which would close the
    // room for everyone.
    String? reason;
    try {
      reason = _runner!.check(seat, move);
    } catch (e) {
      reason = 'unreadable ($e)';
    }
    if (reason != null) {
      _rejects[p.token] = rejects + 1;
      room._log('Room ${room.code}: ${game.key} move "${_short(move)}" refused: $reason');
      throw _Refused(Rejection.illegal, turnId: turnId);
    }
    _play(seat, move, EnvelopeCause.act, refuseThrow: () => _rejects[p.token] = rejects + 1);
  }

  /// [move] cut short for the log.
  static String _short(String move) => move.length <= 40 ? move : '${move.substring(0, 40)}…';

  /// Plays [move] for hand seat [seat], tells everyone, and opens the next
  /// turn (asking the host's device for a bot's), or ends the round.
  ///
  /// [refuseThrow]: for a member's move, the game's act throwing (on a move
  /// its check let through) refuses that move instead of failing the room.
  void _play(int seat, String move, EnvelopeCause cause, {void Function()? refuseThrow}) {
    final runner = _runner!;
    if (refuseThrow == null) {
      runner.act(seat, move);
    } else {
      try {
        runner.act(seat, move);
      } catch (e) {
        refuseThrow();
        room._log('Room ${room.code}: ${game.key} move "${_short(move)}" refused: act threw $e');
        throw _Refused(Rejection.illegal, turnId: _turnId);
      }
    }
    _last = EnvelopeLast(seat: seat, move: move, cause: runner.redealt ? EnvelopeCause.redeal : cause);
    if (runner.roundOver) {
      _roundOver();
      return;
    }
    final shown = _shown(move);
    _openTurn(wait: shown);
    _broadcast();
    // A deal thrown in and dealt again opens with its who-goes-first step:
    // the bot waits for it, as at a round's first deal.
    if (runner.redealt) {
      _askBotAfter(shown);
    } else {
      _askBot();
    }
  }

  /// How long the devices show [move] before the next clock starts.
  Duration _shown(String move) => _capped(_runner!.playbackMs(move));

  /// [ms] as a wait before a clock, at most [OnlineTiming.maxWatch].
  static Duration _capped(int ms) => Duration(milliseconds: min(max(ms, 0), OnlineTiming.maxWatch.inMilliseconds));

  /// [_askBot] once [wait] has passed, if the turn is still open then.
  void _askBotAfter(Duration wait) {
    _askTimer?.cancel();
    if (wait <= Duration.zero) {
      _askBot();
      return;
    }
    final turnId = _turnId;
    _askTimer = room._clock.schedule(wait, () => room._guarded(() {
      if (turnId == _turnId && _turnSeat != null) _askBot();
    }));
  }

  /// The round is over: its result and scores go to everyone, the seats
  /// settle, and the next round comes (or the lobby, when the host ended
  /// the game).
  void _roundOver() {
    final runner = _runner!, dealt = _dealt!;
    _turnTimer?.cancel();
    _askTimer?.cancel();
    _turnSeat = null;
    _botRequest = null;
    _botDriver = null;
    final scores = runner.roundScores;
    for (final (i, s) in dealt.seats.indexed) {
      if (i < scores.length) _scores[s] = (_scores[s] ?? 0) + scores[i];
    }
    _over = EnvelopeOver(result: runner.roundResult(), scores: scores);
    _broadcast();
    if (_ending) {
      _gameOver();
      return;
    }
    // Time to see the last move and the result.
    final last = _last;
    final shown = last == null ? Duration.zero : _shown(last.move);
    _betweenRounds(minWait: shown + game.betweenRounds, newRound: true);
  }

  /// The game is over (the host ended it): the seats settle and the room is
  /// back in the lobby with the same seats and bots (the scores go).
  void _gameOver() {
    _settleSeats();
    close();
    _phase = RoomPhase.lobby;
    _paused = false;
    _between = false;
    _ending = false;
    _turnSeat = null;
    _runner = null;
    _dealt = null;
    _round = 0;
    _last = null;
    _over = null;
    _botDriver = null;
    _botRequest = null;
    _scores.clear();
    room._sendRoom();
    room._watchIdle();
  }

  // ---------------------------------------------------------------------------
  // Sending
  // ---------------------------------------------------------------------------

  ServerGameMessage _envelope(EnvelopeBody body) => ServerGameMessage(game: game.key, gv: game.gv, body: body);

  /// Everyone gets their view of the round as it is now: a seat in it its
  /// own, everyone else the spectators' (encoded once for them all).
  void _broadcast() {
    _seq++;
    String? spectated;
    for (final p in _everyone) {
      final at = _handSeatOf(p);
      if (at >= 0) {
        room._send(p, _state(at));
      } else {
        room._sendText(p, spectated ??= _state(null).encode());
      }
    }
  }

  /// [p]'s hand seat in the round being played (or the last one), as a
  /// seat that sees its own; -1 for a spectator (or one waiting for a
  /// seat, or not in it).
  int _handSeatOf(RoomPlayer p) => p.spectator ? -1 : (_dealt?.tokens.indexOf(p.token) ?? -1);

  /// [p]'s view now; [catchUp]: with the time left on the turn's clock.
  ServerGameMessage _stateFor(RoomPlayer p, {bool catchUp = false}) {
    final at = _handSeatOf(p);
    return _state(at < 0 ? null : at, catchUp: catchUp);
  }

  /// The view of hand seat [you] (null: the spectators').
  ServerGameMessage _state(int? you, {bool catchUp = false}) {
    final dealt = _dealt!, runner = _runner!, now = room._clock.nowMs;
    final seat = _turnSeat, shownEnd = _turnShownEnd;
    final turn = seat == null
        ? null
        : EnvelopeTurn(
            seat: seat,
            turnId: _turnId,
            ms: catchUp && shownEnd != null ? max(0, min(shownEnd - now, _turnMs!)) : _turnMs,
            waitMs: max(0, _turnStartsAt - now),
          );
    return _envelope(
      EnvelopeState(
        round: _round,
        seq: _seq,
        you: you,
        turn: turn,
        last: _last,
        view: you == null ? runner.spectatorView(seesBots: dealt.seeBots) : runner.seatView(you),
        seats: dealt.seats,
        over: _over,
        coachSeed: you == null ? _coachSeed : null,
      ),
    );
  }

  /// Asks the host's device to play the bot whose turn it is (with that
  /// bot's own view); kept for the host coming back.
  void _askBot() {
    final seat = _turnSeat, dealt = _dealt;
    if (seat == null || dealt == null || dealt.tokens[seat] != null) return;
    final request = _botRequest = EnvelopeBotRequest(
      round: _round,
      turnId: _turnId,
      seat: seat,
      level: dealt.levels[seat] ?? game.botLevels.first,
      view: _runner!.seatView(seat),
    );
    final host = room._host;
    if (host != null && host.link != null && host.link == _botDriver) room._send(host, _envelope(request));
  }

  /// Room seat [seat] as RoomState shows it, with who comes and goes at the
  /// next round, and the seat's score in this game.
  SeatInfo _seatInfo(int seat, {required bool showLevel}) {
    final s = _seats[seat];
    final waiting = room._players.values.where((q) => q.waiting && q.seat == seat).firstOrNull;
    final change = _botChanges.containsKey(seat) ? (_botChanges[seat],) : null;
    final joining = waiting?.name ?? (change?.$1 != null && !s.isBot ? kitBotNames[seat] : null);
    final score = _phase == RoomPhase.playing ? _scores[seat] : null;
    final p = s.token == null ? null : room._players[s.token];
    if (p != null) {
      return SeatInfo(
        seat: seat,
        kind: SeatKind.human,
        name: p.name,
        status: p.connected ? SeatStatus.connected : (p.left ? SeatStatus.left : SeatStatus.away),
        joining: joining,
        leaving: p.removing || p.standing || p.left,
        member: p.id,
        score: score,
      );
    }
    if (!s.isBot) return SeatInfo(seat: seat, kind: SeatKind.empty, joining: joining);
    final level = change?.$1 ?? s.botStyle!;
    return SeatInfo(
      seat: seat,
      kind: SeatKind.bot,
      name: kitBotNames[seat],
      style: showLevel ? level : null,
      joining: joining,
      leaving: change != null && change.$1 == null,
      score: score,
    );
  }
}
