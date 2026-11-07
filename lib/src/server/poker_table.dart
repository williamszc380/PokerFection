part of 'room.dart';

/// Who has a room seat: a person (by token), a bot (with its style), or
/// nobody.
class _Seat {
  String? token;
  String? botStyle;

  bool get isBot => botStyle != null;
  bool get isEmpty => token == null && botStyle == null;
}

/// A hand as it was announced: the room seat of each hand seat, with the
/// token of the person there (null for a bot); the seats as shown, with
/// the bots' styles and without (for players who don't see them); the
/// stacks, button and rules; whether spectators see the bots' cards in it
/// ([seeBots], as the host had it then), and whether a bot plays by the
/// solver ([gtoBot]: the host's device solves the hand first). Kept while
/// the hand runs, for members who catch up (see [Snapshot]).
typedef _Lineup = ({
  List<int> seats,
  List<String?> tokens,
  List<SeatInfo> withStyles,
  List<SeatInfo> withoutStyles,
  bool showStyles,
  int button,
  List<int> stacks,
  HelpLevel help,
  int turnLimit,
  bool seeBots,
  bool gtoBot,
});

/// The poker table of a [Room]: its seats, the game and every hand, from
/// the lobby on. The room keeps the people in it (their links, holds, bans
/// and the chat) and calls the table, in the same order as before the
/// table was a class of its own; the table reaches the room's members,
/// links and timers through [room].
///
/// Each seat gets only its own cards; the spectators (members without a
/// seat, or waiting for one) get every person's, and the bots' when the
/// hand was announced with the host's switch on ([_Lineup.seeBots]): one
/// copy for them all.
class _PokerTable implements _Table {
  _PokerTable(this.room, RoomSettings settings, Map<int, String> bots) : _settings = settings {
    _seats = [for (var s = 0; s < settings.seats; s++) _Seat()];
    for (final MapEntry(key: seat, value: style) in bots.entries) {
      // Everyone starts as a spectator, the host too: any seat may hold a bot.
      if (seat >= 0 && seat < _seats.length) _seats[seat].botStyle = style;
    }
  }

  /// The room this table is in.
  final Room room;

  RoomSettings _settings;

  /// The host's changes during the game, for the next hand.
  RoomSettings? _nextSettings;

  /// During the game: the host's bots for the next hand, by room seat (a
  /// bot added, or a new style), or null for a bot taken away.
  final Map<int, String?> _botChanges = {};

  late List<_Seat> _seats;

  RoomPhase _phase = RoomPhase.lobby;

  /// During the game, between hands: too few can play to deal.
  bool _paused = false;

  /// Each taken seat's chips (by room seat) at the end of the last hand; a
  /// seat not listed starts with the starting stack.
  final Map<int, int> _stacks = {};

  /// Room seats out of chips in this game: not dealt in until they rebuy
  /// (people, with rebuys) or the game ends.
  final Set<int> _out = {};

  /// Someone ran out of chips in this game: it is over once only one
  /// player is left who has chips (or may rebuy).
  bool _knockedOut = false;

  /// The room seat of the button of the hand announced last, and of the
  /// one before, which it moved on from (-1 before the first).
  int _buttonSeat = -1, _buttonFrom = -1;

  /// The stacks and button of the next hand, while waiting to deal it
  /// (then of the current one), by hand seat.
  List<int> _handStacks = const [];
  int _handButton = 0;

  /// The next hand as announced, and the current (or last) hand as dealt.
  _Lineup? _announced, _dealt;

  /// The current hand, or the next one while waiting to deal it.
  int _handNumber = 0;

  /// The current hand (or the last, until the next is dealt).
  HandRunner? _hand;

  /// The help in the current hand.
  HelpLevel _handHelp = HelpLevel.none;

  /// Who was told about already in this hand: a player's Show GTO at a
  /// turn (token and turn).
  final Set<(String, int)> _helpTold = {};

  /// Seats a member asked for during a hand, whose bot leaves for them at
  /// its end: what the bot's queued change was before (to put back if they
  /// change their mind).
  final Map<int, (bool, String?)> _displaced = {};

  /// The host ended the game during a hand: back to the lobby when it ends.
  bool _ending = false;

  /// The hand seats that showed their cards after the last hand.
  final Set<int> _shown = {};

  /// The host's connection that got this hand's bot cards (when it was
  /// dealt, or when the host came back): only it may play the bots.
  ClientLink? _botDriver;

  /// The open turn, its clock, and when the time shown for it runs out
  /// (ms; null for no limit).
  Turn? _turn;
  Timer? _turnTimer;
  int? _turnShownEnd;

  /// Waiting to deal the next hand: not before [_earliestDeal] (ms), and
  /// once everyone is ready; at [_latestDeal] at the latest.
  bool _dealing = false;
  int _earliestDeal = 0, _latestDeal = 0;
  Timer? _minTimer, _maxTimer;

  // ---------------------------------------------------------------------------
  // What the room calls (see _Table), by the names the poker code has
  // always had
  // ---------------------------------------------------------------------------

  @override
  RoomPhase get phase => _phase;

  @override
  bool get paused => _paused;

  @override
  bool get seatsOpen => _seatsOpen;

  @override
  List<SeatInfo> seatInfos({required bool showStyles}) => _seatInfos(showStyles: showStyles);

  @override
  RoomSettings? get holdemSettings => _shownSettings;

  @override
  bool showsStylesTo(RoomPlayer p) => p.token == room._hostToken || _shownSettings.showStyles || p.spectator;

  /// A snapshot: on joining only while the game runs, coming back always.
  @override
  void caughtUp(RoomPlayer p, {required bool joining}) {
    if (!joining || _phase == RoomPhase.playing) _sendSnapshot(p);
  }

  @override
  void resync(RoomPlayer p) => _sendSnapshot(p);

  @override
  void onRejoin(RoomPlayer p) {
    // The host's device plays the bots again (the snapshot has their cards).
    final hand = _hand;
    if (p.token == room._hostToken && hand != null && !hand.isOver && !_dealing) _botDriver = p.link;
    room._guarded(() => _restartClockFor(p));
  }

  @override
  void afterRejoin(RoomPlayer p, {required bool back}) => back ? _lineupChanged() : _maybeResume();

  @override
  void onAway(RoomPlayer p) => _restartClockFor(p);

  @override
  void afterAway() => _maybeDeal();

  /// In the lobby (or while the game waits), and for a spectator or one
  /// waiting for a seat, they go at once and their seat is free; during
  /// the game the server plays a player's turns, and the seat is empty from
  /// the next hand.
  @override
  void onLetGo(RoomPlayer p) {
    if (_seatsOpen || p.spectator) {
      room._players.remove(p.token);
      final seat = p.seat;
      if (p.waiting) {
        _unqueue(p);
      } else if (seat != null && _seats[seat].token == p.token) {
        _seats[seat].token = null;
        _freshStack(seat);
      }
    } else {
      p.left = true;
      // Their turn now is played at once.
      _restartClockFor(p);
    }
  }

  @override
  void afterLeave() {
    _maybeDeal();
    _maybeResume();
  }

  /// A player dealt in the hand being played who hasn't folded.
  @override
  bool playsRound(RoomPlayer p) {
    final hand = _hand, at = _handSeatOf(p);
    return !p.spectator && !_dealing && !_paused && hand != null && !hand.isOver && at >= 0 && !hand.hand.isFolded(at);
  }

  @override
  void afterRemoval() => _lineupChanged();

  @override
  void changeSettings(RoomPlayer p, ChangeSettings m) => _changeSettings(p, m);

  @override
  void addBot(RoomPlayer p, String style, int? seat) => _addBot(p, style, seat);

  @override
  void removeBot(RoomPlayer p, int seat) => _removeBot(p, seat);

  @override
  void start(RoomPlayer p) => _start(p);

  @override
  void takeSeat(RoomPlayer p, int? seat) => _takeSeat(p, seat);

  @override
  void leaveSeat(RoomPlayer p) => _leaveSeat(p);

  @override
  void endGame() => _endGame();

  /// Poker's own messages; the other games' are for a round that isn't
  /// there.
  @override
  void receive(RoomPlayer p, ClientMessage m) {
    switch (m) {
      case Act():
        _act(p, m.hand, m.turnId, m.action);
      case BotAct():
        _act(p, m.hand, m.turnId, m.action, botSeat: m.seat);
      case UsedHelp():
        _usedHelp(p, m.hand, m.turnId);
      case ShowCards():
        _showCards(p, m.hand);
      case Ready():
        _ready(p, m.hand);
      case Rebuy():
        _rebuy(p);
      case SitOut():
        _sitOut(p, m.on);
      default:
        throw const _Refused(Rejection.stale);
    }
  }

  @override
  void close() => _close();

  // ---------------------------------------------------------------------------
  // Seats
  // ---------------------------------------------------------------------------

  /// Everyone connected: told what happens at the table (the seats and the
  /// spectators).
  Iterable<RoomPlayer> get _everyone => room._players.values.where((p) => p.connected);

  /// The connected players of [lineup] (a hand as announced or dealt), with
  /// their hand seats.
  Iterable<(RoomPlayer, int)> _playersOf(_Lineup lineup) sync* {
    for (final (seat, token) in lineup.tokens.indexed) {
      final p = token == null ? null : room._players[token];
      if (p != null && p.connected) yield (p, seat);
    }
  }

  /// Seats change at once in the lobby, and while the game waits for
  /// players; otherwise from the next hand.
  bool get _seatsOpen => _phase == RoomPhase.lobby || _paused;

  /// [p]'s hand seat in the current (or last) hand; -1 if not in it.
  int _handSeatOf(RoomPlayer p) => _dealt?.tokens.indexOf(p.token) ?? -1;

  /// The name of whoever has room seat [seat].
  String _nameOf(int seat) {
    final token = _seats[seat].token;
    return token == null ? onlineBotNames[seat] : (room._players[token]?.name ?? onlineBotNames[seat]);
  }

  /// Whether whoever has room seat [seat] can play a hand now: a person
  /// who is connected and doesn't sit out, or a bot while the host's device
  /// is there to play it (and not out of chips).
  bool _canPlay(int seat) {
    if (_out.contains(seat)) return false;
    final s = _seats[seat];
    if (s.token case final token?) {
      final p = room._players[token];
      return p != null && p.connected && !p.sittingOut && !p.standing;
    }
    return s.isBot && room._host != null;
  }

  /// Whether room seat [seat] is dealt in the next hand announced: taken,
  /// not out of chips, and not by someone who sits out (or left, or leaves
  /// the seat, before the seats settle).
  bool _dealtIn(int seat) {
    final s = _seats[seat];
    if (s.isEmpty || _out.contains(seat)) return false;
    final p = room._players[s.token];
    return p == null ? s.isBot : !p.sittingOut && !p.left && !p.standing;
  }

  /// Whether nobody has room seat [seat] from the next hand (nobody waits
  /// for it, no bot is coming, and whoever has it now leaves).
  bool _freeNextHand(int seat) {
    if (room._players.values.any((p) => p.waiting && p.seat == seat)) return false;
    if (_botChanges.containsKey(seat)) return _botChanges[seat] == null;
    final s = _seats[seat];
    if (s.token != null) {
      final p = room._players[s.token];
      return p == null || p.left || p.removing || p.standing;
    }
    return !s.isBot;
  }

  /// The first room seat free from the next hand ([preferred] if it is);
  /// null when the table is full.
  int? _freeSeat([int? preferred]) {
    if (preferred != null && preferred < _seats.length && _freeNextHand(preferred)) return preferred;
    for (var s = 0; s < _seats.length; s++) {
      if (_freeNextHand(s)) return s;
    }
    return null;
  }

  /// Whether a bot has room seat [seat] from the next hand (one that comes,
  /// stays, or is restyled), with nobody waiting for it.
  bool _botNextHand(int seat) {
    if (_seats[seat].token != null || room._players.values.any((p) => p.waiting && p.seat == seat)) return false;
    return _botChanges.containsKey(seat) ? _botChanges[seat] != null : _seats[seat].isBot;
  }

  /// The room seat a member who asks for [preferred] (or any) gets: that
  /// one if it is free from the next hand; else the first free one; else a
  /// bot's, which gives way to people ([preferred] if a bot has it, else
  /// the highest one). Null when every seat holds a person.
  int? _seatFor(int? preferred) {
    final free = _freeSeat(preferred);
    if (free != null) return free;
    if (preferred != null && preferred < _seats.length && _botNextHand(preferred)) return preferred;
    for (var s = _seats.length - 1; s >= 0; s--) {
      if (_botNextHand(s)) return s;
    }
    return null;
  }

  /// Whoever has room seat [seat] next (someone new, or a player who
  /// rebuys) starts with the starting stack.
  void _freshStack(int seat) {
    _stacks.remove(seat);
    _out.remove(seat);
  }

  /// The game is over once someone ran out of chips and only one player is
  /// left who has chips (or may rebuy): (their room seat,), or (null,) if
  /// nobody is. Null while the game goes on.
  (int?,)? _winner() {
    if (!_knockedOut) return null;
    final left = [
      for (var s = 0; s < _seats.length; s++)
        if (!_seats[s].isEmpty && (_settings.rebuys || !_out.contains(s))) s,
    ];
    return left.length > 1 ? null : (left.firstOrNull,);
  }

  // ---------------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------------

  void _changeSettings(RoomPlayer p, ChangeSettings m) {
    if (p.token != room._hostToken) throw const _Refused(Rejection.notHost);
    final settings = m.settings, styles = m.botStyles;
    if (_phase == RoomPhase.lobby) {
      if (settings != null) _resize(settings);
    } else if (settings != null) {
      // During the game the table stays the same; the rest waits for the next hand.
      if (!settings.sameTable(_settings)) throw const _Refused(Rejection.illegal);
      _nextSettings = settings;
    }
    if (styles != null && styles.values.any((style) => !botStyleNames.contains(style))) {
      throw const _Refused(Rejection.illegal);
    }
    for (final MapEntry(key: seat, value: style) in (styles ?? const <int, String>{}).entries) {
      if (seat >= _seats.length) continue;
      if (_seatsOpen) {
        if (_seats[seat].isBot) _seats[seat].botStyle = style;
      } else if (_botChanges[seat] != null || (_seats[seat].isBot && !_botChanges.containsKey(seat))) {
        _botChanges[seat] = style;
      }
    }
    room._sendRoom();
    room._watchIdle();
  }

  /// The host seats a bot: in [preferred], or the first free seat.
  void _addBot(RoomPlayer p, String style, int? preferred) {
    if (p.token != room._hostToken) throw const _Refused(Rejection.notHost);
    // A level is for the other games' bots.
    if (!botStyleNames.contains(style)) throw const _Refused(Rejection.illegal);
    final seat = _freeSeat(preferred);
    if (seat == null) throw const _Refused(Rejection.illegal);
    if (_seatsOpen) {
      _seats[seat].botStyle = style;
      _freshStack(seat);
    } else {
      _botChanges[seat] = style;
    }
    room._sendRoom();
    room._watchIdle();
    _maybeResume();
  }

  /// The host takes the bot in [seat] away.
  void _removeBot(RoomPlayer p, int seat) {
    if (p.token != room._hostToken) throw const _Refused(Rejection.notHost);
    if (seat >= _seats.length) throw const _Refused(Rejection.illegal);
    final s = _seats[seat];
    if (_seatsOpen) {
      if (!s.isBot) throw const _Refused(Rejection.illegal);
      s.botStyle = null;
      _freshStack(seat);
    } else if (_botChanges[seat] != null) {
      // A bot still to come (or restyled) is simply not seated.
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
    room._sendRoom();
    room._watchIdle();
    _maybeResume();
  }

  /// [p] takes a seat: [preferred], or the first free one, or a bot's (see
  /// [_seatFor]). At once in the lobby and while the game waits for
  /// players; between hands (the next one announced, not dealt yet) at once
  /// too, the hand announced again with them, within the same deal times;
  /// during a hand, from the next one (they spectate it: so a spectator
  /// never plays a hand whose cards they may have seen).
  void _takeSeat(RoomPlayer p, int? preferred) {
    if (p.seat != null) throw const _Refused(Rejection.illegal);
    final seat = _seatFor(preferred);
    if (seat == null) throw const _Refused(Rejection.illegal);
    final s = _seats[seat];
    if (_seatsOpen) {
      // A bot gives way at once.
      s.botStyle = null;
      s.token = p.token;
      p.seat = seat;
      _freshStack(seat);
      room._sendRoom();
      room._watchIdle();
      _maybeResume();
      return;
    }
    // A bot there next hand gives way at its end (or now, between hands: see _reannounce).
    if (_botNextHand(seat)) {
      _displaced[seat] = (_botChanges.containsKey(seat), _botChanges[seat]);
      _botChanges[seat] = null;
    }
    p.waiting = true;
    p.seat = seat;
    if (_dealing) {
      _reannounce();
    } else {
      room._sendRoom();
    }
  }

  /// [p] gives up their seat, or the one they wait for: at once in the
  /// lobby, while the game waits and between hands (announced again
  /// without them); during a hand they play it out, and spectate from the
  /// next one.
  void _leaveSeat(RoomPlayer p) {
    final seat = p.seat;
    if (seat == null) throw const _Refused(Rejection.illegal);
    if (p.waiting) {
      _unqueue(p);
      room._sendRoom();
      return;
    }
    if (p.standing) return;
    if (_seatsOpen || _dealing) {
      if (_seats[seat].token == p.token) {
        _seats[seat].token = null;
        _freshStack(seat);
      }
      p.seat = null;
      p.sittingOut = p._satOutAway = false;
      if (_dealing) {
        _reannounce();
        return;
      }
      room._sendRoom();
      room._watchIdle();
      _maybeResume();
      return;
    }
    p.standing = true;
    room._sendRoom();
  }

  /// [p] no longer waits for their seat: a bot it was to take stays. They
  /// are a spectator with nothing carried over to the next seat they take.
  void _unqueue(RoomPlayer p) {
    final seat = p.seat;
    p.waiting = false;
    p.seat = null;
    p.sittingOut = p._satOutAway = false;
    if (seat == null) return;
    if (_displaced.remove(seat) case (final had, final style)) {
      if (had) {
        _botChanges[seat] = style;
      } else {
        _botChanges.remove(seat);
      }
    }
  }

  /// The seats changed between hands: the next hand is announced again
  /// (the seats settle: see [_settleSeats]), to be dealt within the same
  /// times.
  void _reannounce() {
    final now = room._clock.nowMs;
    _betweenHands(
      minWait: Duration(milliseconds: max(0, _earliestDeal - now)),
      maxWait: Duration(milliseconds: max(0, _latestDeal - now)),
      again: true,
    );
  }

  /// The host ends the game: back to the lobby now while the game waits or
  /// between hands, else once the hand being played ends.
  void _endGame() {
    if (_phase != RoomPhase.playing || _ending) throw const _Refused(Rejection.illegal);
    if (_paused || _dealing || _hand == null || _hand!.isOver) {
      _gameOver(null);
      return;
    }
    _ending = true;
  }

  /// Every timer of the table stops (the room closes, or plays another
  /// game).
  void _close() {
    _turnTimer?.cancel();
    _minTimer?.cancel();
    _maxTimer?.cancel();
  }

  /// New settings in the lobby, maybe with another number of seats: people
  /// and bots keep their seats where they still exist, the others move to
  /// the first empty ones.
  void _resize(RoomSettings settings) {
    final n = settings.seats;
    if (n != _seats.length) {
      final taken = _seats.where((s) => !s.isEmpty).length;
      if (taken > n) throw const _Refused(Rejection.illegal);
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
    _settings = settings;
  }

  void _start(RoomPlayer p) {
    if (p.token != room._hostToken) throw const _Refused(Rejection.notHost);
    if (_phase != RoomPhase.lobby) throw const _Refused(Rejection.stale);
    if (_seats.where((s) => !s.isEmpty).length < minPlayers) throw const _Refused(Rejection.illegal);
    _phase = RoomPhase.playing;
    // A new game: everyone starts with the starting stack.
    _stacks.clear();
    _out.clear();
    _knockedOut = false;
    _betweenHands(minWait: Duration.zero);
  }

  /// While the game waits for players: deals as soon as enough can play
  /// (someone joined, came back or rebought, or the host added a bot). It is
  /// over once only one player is left who has chips (someone left, or the
  /// host took a bot away).
  void _maybeResume() {
    if (_phase != RoomPhase.playing || !_paused || room._closed) return;
    if (_winner() case (final winner,)) {
      _gameOver(winner);
      return;
    }
    final players = [
      for (var s = 0; s < _seats.length; s++)
        if (_canPlay(s)) s,
    ].length;
    if (players >= minPlayers) _betweenHands(minWait: Duration.zero);
  }

  void _ready(RoomPlayer p, int handNumber) {
    // A late one (the hand is dealt already) needs nothing.
    if (!_dealing || handNumber != _handNumber) return;
    p.ready = true;
    _maybeDeal();
  }

  /// [p], out of chips, buys in again for the starting stack (when the host
  /// allows rebuys): dealt in from the next hand (announced again if it was
  /// already).
  void _rebuy(RoomPlayer p) {
    final seat = p.seat;
    if (_phase != RoomPhase.playing ||
        !_settings.rebuys ||
        seat == null ||
        p.spectator ||
        !_out.contains(seat) ||
        _seats[seat].token != p.token) {
      throw const _Refused(Rejection.illegal);
    }
    _freshStack(seat);
    _lineupChanged();
  }

  /// [p] sits out ([on]: not dealt in from the next hand, keeping the seat
  /// and chips; only during the game), or is back: dealt in again from the
  /// next hand. Either way, a hand announced but not dealt yet is announced
  /// again.
  void _sitOut(RoomPlayer p, bool on) {
    // One only waiting for a seat is still a spectator: nothing to sit out yet.
    if (p.spectator || (on && _phase != RoomPhase.playing)) throw const _Refused(Rejection.illegal);
    p._satOutAway = false;
    if (p.sittingOut == on) return;
    p.sittingOut = on;
    _lineupChanged();
  }

  /// Who is dealt in next may have changed (someone sat out or is back,
  /// rebought, or was removed): a hand announced but not dealt yet is
  /// announced again, to be dealt within the same times (so changes over
  /// and over can't hold it up); while the game waits for players, it may
  /// go on.
  void _lineupChanged() {
    final announced = _announced?.seats;
    if (_dealing && announced != null) {
      final lineup = [
        for (var s = 0; s < _seats.length; s++)
          if (_dealtIn(s)) s,
      ];
      if (lineup.length != announced.length || lineup.indexed.any((e) => e.$2 != announced[e.$1])) {
        final now = room._clock.nowMs;
        _betweenHands(
          minWait: Duration(milliseconds: max(0, _earliestDeal - now)),
          maxWait: Duration(milliseconds: max(0, _latestDeal - now)),
          again: true,
        );
        return;
      }
    }
    room._sendRoom();
    _maybeResume();
  }

  // ---------------------------------------------------------------------------
  // Help and showing cards
  // ---------------------------------------------------------------------------

  /// [p] pressed Show GTO at turn [turnId]: everyone is told (once per turn).
  void _usedHelp(RoomPlayer p, int handNumber, int turnId) {
    final hand = _hand;
    if (hand == null || handNumber != hand.handNumber || turnId > hand.turnId) {
      throw _Refused(Rejection.stale, turnId: turnId);
    }
    if (_handHelp == HelpLevel.none || p.spectator || _handSeatOf(p) < 0 || !p.connected) {
      throw _Refused(Rejection.illegal, turnId: turnId);
    }
    if (!_helpTold.add((p.token, turnId))) return;
    _tell(Notice(kind: NoticeKind.help, hand: handNumber, seat: _dealt!.seats[_handSeatOf(p)], name: p.name));
  }

  /// [p] shows their cards once the hand is over (until the next is dealt):
  /// everyone in the room sees them.
  void _showCards(RoomPlayer p, int handNumber) {
    final hand = _hand, dealt = _dealt;
    if (hand == null || dealt == null || handNumber != hand.handNumber || !hand.hand.isOver) {
      throw const _Refused(Rejection.stale);
    }
    final mine = _handSeatOf(p);
    if (mine < 0 || !p.connected) throw const _Refused(Rejection.notYourTurn);
    final cards = shownCardsFor(hand.hand, seat: mine);
    if (cards == null) throw const _Refused(Rejection.illegal);
    if (!_shown.add(mine)) return;
    final shown = CardsShown(hand: handNumber, seat: dealt.seats[mine], cards: cards);
    for (final q in _everyone) {
      room._send(q, shown);
    }
  }

  /// Tells everyone in the room.
  void _tell(Notice notice) {
    for (final p in _everyone) {
      room._send(p, notice);
    }
  }

  // ---------------------------------------------------------------------------
  // Hands
  // ---------------------------------------------------------------------------

  /// Between hands (and when the game ends): those the host removed during
  /// the hand go, those who left give up their seats, those who leave their
  /// seats spectate, the host's bots come and go (a bot a person takes the
  /// seat of goes), those who asked for a seat sit down with the starting
  /// stack, and the host's changes apply.
  void _settleSeats() {
    for (final p in [...room._players.values]) {
      if (p.removing) room._expel(p);
    }
    for (final p in [...room._players.values]) {
      if (!p.left) continue;
      room._players.remove(p.token);
      final seat = p.seat;
      if (seat != null && _seats[seat].token == p.token) {
        _seats[seat].token = null;
        _freshStack(seat);
      }
    }
    for (final p in room._players.values) {
      final seat = p.seat;
      if (!p.standing || seat == null) continue;
      if (_seats[seat].token == p.token) {
        _seats[seat].token = null;
        _freshStack(seat);
      }
      p.seat = null;
      p.standing = p.sittingOut = p._satOutAway = false;
    }
    for (final MapEntry(key: seat, value: style) in _botChanges.entries) {
      final s = _seats[seat];
      if (s.token != null) continue;
      // A new bot buys in; one taken away takes its chips.
      if (style == null || !s.isBot) _freshStack(seat);
      s.botStyle = style;
    }
    _botChanges.clear();
    _displaced.clear();
    // Those who asked for a seat sit down (one who is away meanwhile too: their seat waits for them).
    for (final p in room._players.values) {
      final seat = p.seat;
      if (!p.waiting || seat == null) continue;
      p.waiting = false;
      _seats[seat].token = p.token;
      _freshStack(seat);
    }
    final settings = _nextSettings;
    if (settings != null) _settings = settings;
    _nextSettings = null;
  }

  /// Between hands: the seats settle (see [_settleSeats]) and the game may
  /// be over; else, with enough players, everyone is told who plays the
  /// next hand, with what, and it is dealt once all are ready (after
  /// [minWait], and at most a few seconds later). With too few who can
  /// play, the game waits for players. Those out of chips, or who sit out,
  /// watch. [again]: the same hand, announced again (see [_lineupChanged]),
  /// dealt by [maxWait] at the latest.
  void _betweenHands({required Duration minWait, Duration? maxWait, bool again = false}) {
    _turnTimer?.cancel();
    _turn = null;
    _settleSeats();
    if (_winner() case (final winner,)) {
      _gameOver(winner);
      return;
    }

    final lineup = [
      for (var s = 0; s < _seats.length; s++)
        if (_dealtIn(s)) s,
    ];
    _dealing = false;
    _minTimer?.cancel();
    _maxTimer?.cancel();
    if (lineup.where(_canPlay).length < minPlayers) {
      _pause();
      return;
    }
    _paused = false;
    room._idle?.cancel();
    room._idle = null;

    // Anyone who rebought, went broke with rebuys (a bot) or just sat down buys in for the starting stack.
    final n = lineup.length;
    final next = nextHandSetup(
      stacks: [for (final s in lineup) _stacks[s] ?? 0],
      startingStacks: List.filled(n, _settings.startingStack),
      button: 0,
      firstHand: true,
      resetStacks: _settings.resetStacks,
    );
    // The button moves to the next seat taken (from the same seat, for a hand announced again).
    if (!again) _buttonFrom = _buttonSeat;
    _buttonSeat = _buttonFrom < 0
        ? lineup[room._random.nextInt(n)]
        : lineup.firstWhere((s) => s > _buttonFrom, orElse: () => lineup.first);
    _handStacks = next.stacks;
    _handButton = lineup.indexOf(_buttonSeat);
    for (final (i, s) in lineup.indexed) {
      _stacks[s] = next.stacks[i];
    }
    if (!again) _handNumber++;
    _dealing = true;
    for (final p in room._players.values) {
      p.ready = false;
    }
    final announced = _announced = (
      seats: lineup,
      tokens: [for (final s in lineup) _seats[s].token],
      withStyles: [for (final s in lineup) _seatInfo(s, showStyle: true)],
      withoutStyles: [for (final s in lineup) _seatInfo(s, showStyle: false)],
      showStyles: _settings.showStyles,
      button: _handButton,
      stacks: _handStacks,
      help: _settings.help,
      turnLimit: _settings.turnLimit,
      seeBots: room._seeBots,
      gtoBot: lineup.any((s) => _seats[s].botStyle == 'gto'),
    );
    // Devices that solve (help, or the host's GTO bots) get longer.
    final solving = _settings.help != HelpLevel.none || _seats.any((s) => s.botStyle == 'gto');
    final latest = maxWait ?? minWait + (solving ? OnlineTiming.readyWaitWithHelp : OnlineTiming.readyWait);
    _earliestDeal = room._clock.nowMs + minWait.inMilliseconds;
    _latestDeal = room._clock.nowMs + latest.inMilliseconds;
    _minTimer = room._clock.schedule(minWait, () => room._guarded(_maybeDeal));
    _maxTimer = room._clock.schedule(latest, () => room._guarded(_deal));

    room._sendRoom();
    for (final (p, seat) in _audienceOf(announced)) {
      room._send(
        p,
        _announcement(
          p,
          announced,
          hand: _handNumber,
          you: seat,
          minWaitMs: minWait.inMilliseconds,
          maxWaitMs: latest.inMilliseconds,
        ),
      );
    }
  }

  /// Everyone in the room, with their hand seat in [lineup] (null for a
  /// player not dealt in, who watches, and for every spectator).
  Iterable<(RoomPlayer, int?)> _audienceOf(_Lineup lineup) sync* {
    for (final p in _everyone) {
      final seat = p.spectator ? -1 : lineup.tokens.indexOf(p.token);
      yield (p, seat < 0 ? null : seat);
    }
  }

  /// The hand seats of [lineup] whose cards spectators see: every person's,
  /// and the bots' when it was announced with the host's switch on.
  Set<int> _visibleOf(_Lineup lineup) => {
    for (final (seat, token) in lineup.tokens.indexed)
      if (token != null || lineup.seeBots) seat,
  };

  /// Only one player is left with chips (or nobody: [winner] is null):
  /// everyone is told who won, and the room is back in the lobby with the
  /// same seats, bots and rules, for the host to start a new game.
  void _gameOver(int? winner) {
    _settleSeats();
    final message = GameOver(seat: winner, name: winner == null ? null : _nameOf(winner));
    for (final p in room._players.values) {
      if (p.connected) room._send(p, message);
    }
    _phase = RoomPhase.lobby;
    _paused = false;
    _dealing = false;
    _ending = false;
    _turnTimer?.cancel();
    _minTimer?.cancel();
    _maxTimer?.cancel();
    _turn = null;
    _turnShownEnd = null;
    _hand = null;
    _dealt = null;
    _announced = null;
    _botDriver = null;
    _stacks.clear();
    _out.clear();
    _knockedOut = false;
    _buttonSeat = -1;
    room._sendRoom();
    room._watchIdle();
  }

  /// [lineup] (hand [hand]) as [p] is told about it, in hand seat [you]
  /// (null: watching). The host and spectators see the bots' styles.
  NextHand _announcement(
    RoomPlayer p,
    _Lineup lineup, {
    required int hand,
    required int? you,
    required int minWaitMs,
    required int maxWaitMs,
  }) => NextHand(
    hand: hand,
    button: lineup.button,
    you: you,
    stacks: lineup.stacks,
    seats: p.token == room._hostToken || lineup.showStyles || p.spectator ? lineup.withStyles : lineup.withoutStyles,
    help: lineup.help,
    turnLimit: lineup.turnLimit,
    minWaitMs: minWaitMs,
    maxWaitMs: maxWaitMs,
  );

  /// Too few can play: no hand is dealt until enough can (see
  /// [_maybeResume]); meanwhile seats change at once.
  void _pause() {
    _paused = true;
    _dealing = false;
    _minTimer?.cancel();
    _maxTimer?.cancel();
    room._sendRoom();
    room._watchIdle();
  }

  void _maybeDeal() {
    if (!_dealing || room._clock.nowMs < _earliestDeal) return;
    // Those who watch don't hold up the deal: but the host's device, which plays the bots, solves first for one
    // that plays by the solver (seated or not).
    final announced = _announced!;
    if (_playersOf(announced).any((e) => !e.$1.ready)) return;
    if (announced.gtoBot && !(room._host?.ready ?? true)) return;
    _deal();
  }

  void _deal() {
    if (!_dealing || room._closed) return;
    _dealing = false;
    _minTimer?.cancel();
    _maxTimer?.cancel();
    final dealt = _announced!;
    // Someone went away while it was announced: too few can play now.
    if (dealt.seats.where(_canPlay).length < minPlayers) {
      _pause();
      return;
    }
    _dealt = dealt;
    // Those away now are sat out if they are still away when the hand ends.
    for (final token in dealt.tokens) {
      if (room._players[token] case final p?) p._awayAllHand = p.away;
    }
    final bots = [
      for (final (i, token) in dealt.tokens.indexed)
        if (token == null) i,
    ];
    final hand = _hand = HandRunner(
      stacks: _handStacks,
      button: _handButton,
      handNumber: _handNumber,
      ante: _settings.ante,
      raiseRule: _settings.raiseRule,
      random: room._random,
      botSeats: bots,
    );
    _handHelp = _settings.help;
    _helpTold.clear();
    _shown.clear();
    final host = room._host;
    _botDriver = host?.link;
    if (host != null && bots.isNotEmpty) {
      room._send(host, BotCards(hand: _handNumber, cards: botCardsFor(hand.hand, bots)));
    }
    final turn = _openTurn();
    // The spectators' copy: the same for them all, encoded once.
    final spectated = HandDealt(
      hand: _handNumber,
      batch: redactBatchFor(hand.batches.first, SpectatorViewer(_visibleOf(dealt))),
      turn: turn,
    ).encode();
    for (final (p, seat) in _audienceOf(dealt)) {
      if (p.spectator) {
        room._sendText(p, spectated);
      } else {
        room._send(
          p,
          HandDealt(hand: _handNumber, batch: redactBatchFor(hand.batches.first, SeatViewer(seat)), turn: turn),
        );
      }
    }
    if (turn == null) _handOver();
  }

  /// The next turn, with its clock running; null once the hand is over.
  Turn? _openTurn() {
    _turnTimer?.cancel();
    final hand = _hand!;
    final turn = _turn = hand.openTurn(limitMs: (seat) => _limit(seat).shown);
    if (turn != null) _armTimer(turn.turnId, turn.seat, Duration(milliseconds: turn.waitMs));
    return turn;
  }

  /// How long whoever plays hand seat [seat] gets to act ([deadline] after
  /// the actions before have been shown; null for no limit), the time
  /// shown to the players, and why the server acts for them after it.
  ({Duration? deadline, int? shown, ActCause cause}) _limit(int seat) {
    final token = _dealt!.tokens[seat];
    if (token != null) {
      final p = room._players[token];
      if (p == null || p.left) return (deadline: Duration.zero, shown: 0, cause: ActCause.left);
      if (p.away) {
        return (deadline: OnlineTiming.awayLimit, shown: OnlineTiming.awayLimit.inMilliseconds, cause: ActCause.away);
      }
      final seconds = _settings.turnLimit;
      if (seconds == 0) return (deadline: null, shown: null, cause: ActCause.timeout);
      return (
        deadline: Duration(seconds: seconds) + OnlineTiming.grace,
        shown: seconds * 1000,
        cause: ActCause.timeout,
      );
    }
    final host = room._host;
    if (host != null && host.link == _botDriver) {
      return (deadline: OnlineTiming.botLimit, shown: OnlineTiming.botLimit.inMilliseconds, cause: ActCause.timeout);
    }
    return (
      deadline: OnlineTiming.hostAwayBotLimit,
      shown: OnlineTiming.hostAwayBotLimit.inMilliseconds,
      cause: ActCause.hostAway,
    );
  }

  /// (Re)starts the clock of turn [turnId], for hand seat [seat], after
  /// [watch].
  void _armTimer(int turnId, int seat, Duration watch) {
    _turnTimer?.cancel();
    final limit = _limit(seat);
    final deadline = limit.deadline, shown = limit.shown;
    _turnShownEnd = shown == null ? null : room._clock.nowMs + watch.inMilliseconds + shown;
    if (deadline == null) return;
    _turnTimer = room._clock.schedule(watch + deadline, () => room._guarded(() => _timeUp(turnId, limit.cause)));
  }

  /// [p] went away, came back or left: if it is their turn (or, for the
  /// host, a bot's), its clock starts again from now, with their new limit.
  void _restartClockFor(RoomPlayer p) {
    final hand = _hand, dealt = _dealt, turn = _turn;
    if (_dealing || _paused || hand == null || dealt == null || hand.isOver || turn == null) return;
    final seat = hand.hand.toAct!;
    final token = dealt.tokens[seat];
    if (token == p.token || (token == null && p.token == room._hostToken)) _armTimer(turn.turnId, seat, Duration.zero);
  }

  void _timeUp(int turnId, ActCause cause) {
    final hand = _hand;
    if (_dealing || _paused || hand == null || hand.isOver || hand.turnId != turnId) return;
    final ended = hand.turnId;
    _afterAction(hand.act(hand.autoAction), cause, ended);
  }

  void _act(RoomPlayer p, int handNumber, int turnId, PlayerAction action, {int? botSeat}) {
    final hand = _hand;
    if (_dealing || _paused || hand == null || hand.isOver || handNumber != hand.handNumber || turnId != hand.turnId) {
      throw _Refused(Rejection.stale, turnId: turnId);
    }
    final seat = hand.hand.toAct!;
    final allowed = botSeat == null
        ? p.connected && _handSeatOf(p) == seat && !hand.botSeats.contains(seat)
        : p.link != null && p.link == _botDriver && botSeat == seat && hand.botSeats.contains(seat);
    if (!allowed) throw _Refused(Rejection.notYourTurn, turnId: turnId);
    // After a few refused moves, more are ignored until the clock runs out.
    if (hand.rejects >= HandRunner.maxRejects) throw _Refused(Rejection.rateLimited, turnId: turnId);
    final List<GameEvent> batch;
    try {
      batch = hand.act(action);
    } on ArgumentError {
      hand.rejects++;
      throw _Refused(Rejection.illegal, turnId: turnId);
    } on StateError {
      hand.rejects++;
      throw _Refused(Rejection.illegal, turnId: turnId);
    }
    _afterAction(batch, ActCause.act, turnId);
  }

  /// Sends everyone in the hand the action that ended turn [ended] and what
  /// it led to, with the next turn; or, once the hand is over, gets the
  /// next one ready.
  void _afterAction(List<GameEvent> batch, ActCause cause, int ended) {
    final hand = _hand!;
    final turn = _openTurn();
    final message = HandEvents(hand: hand.handNumber, turnId: ended, cause: cause, batch: batch, turn: turn).encode();
    for (final (p, _) in _audienceOf(_dealt!)) {
      room._sendText(p, message);
    }
    if (turn == null) _handOver();
  }

  void _handOver() {
    final hand = _hand!;
    for (final (i, s) in _dealt!.seats.indexed) {
      final chips = _stacks[s] = hand.hand.stackOf(i);
      // Out of chips (stacks reset every hand: never): with rebuys a bot buys
      // in again by itself and a person chooses; without, they are out.
      if (chips == 0 && !_settings.resetStacks && !(_settings.rebuys && _seats[s].isBot)) {
        _out.add(s);
        _knockedOut = true;
      }
    }
    // Away through the whole hand: sat out until they come back, rather than checked or folded hand after hand.
    for (final token in _dealt!.tokens) {
      if (room._players[token] case final p? when p._awayAllHand && p.away && !p.sittingOut) {
        p.sittingOut = true;
        p._satOutAway = true;
      }
    }
    _botDriver = null;
    _turnShownEnd = null;
    // The host ended the game during the hand (it may have had a winner anyway).
    if (_ending) {
      _settleSeats();
      _gameOver(_winner()?.$1);
      return;
    }
    // Time to see the end of the hand (the showdown, the pot paid) and its result.
    _betweenHands(minWait: Duration(milliseconds: playbackMs(hand.batches.last)) + OnlineTiming.betweenHands);
  }

  /// Everything [p] needs to catch up: the hand they are in or watch (or
  /// the last one, until the next is dealt) as they may see it (a
  /// spectator, as that hand's spectators do), and the next hand if it is
  /// announced.
  void _sendSnapshot(RoomPlayer p) {
    final hand = _hand, dealt = _dealt, now = room._clock.nowMs;
    SnapshotHand? current;
    final at = p.spectator ? -1 : _handSeatOf(p), seat = at < 0 ? null : at;
    if (hand != null && dealt != null) {
      final open = hand.isOver || _dealing ? null : _turn;
      final shownEnd = _turnShownEnd;
      final Viewer viewer = p.spectator ? SpectatorViewer(_visibleOf(dealt)) : SeatViewer(seat);
      current = SnapshotHand(
        lineup: _announcement(p, dealt, hand: hand.handNumber, you: seat, minWaitMs: 0, maxWaitMs: 0),
        batches: redactBatchesFor(hand.batches, viewer),
        turn: open?.resumed(shownEnd == null ? null : max(0, shownEnd - now)),
        botCards: p.token == room._hostToken ? botCardsFor(hand.hand, hand.botSeats) : const {},
      );
    }
    NextHand? next;
    final announced = _announced;
    final you = p.spectator ? -1 : (announced?.tokens.indexOf(p.token) ?? -1);
    if (_dealing && announced != null) {
      next = _announcement(
        p,
        announced,
        hand: _handNumber,
        you: you < 0 ? null : you,
        minWaitMs: max(0, _earliestDeal - now),
        maxWaitMs: max(0, _latestDeal - now),
      );
    }
    room._send(p, Snapshot(hand: current, next: next));
  }

  // ---------------------------------------------------------------------------
  // Sending
  // ---------------------------------------------------------------------------

  /// The seats as RoomState shows them, with who comes and goes at the
  /// next hand ([showStyles]: with the bots' styles).
  List<SeatInfo> _seatInfos({required bool showStyles}) => [
    for (var s = 0; s < _seats.length; s++) _seatInfo(s, showStyle: showStyles, upcoming: true),
  ];

  /// The rules as RoomState shows them: with the host's changes for the
  /// next hand.
  RoomSettings get _shownSettings => _nextSettings ?? _settings;

  /// Room seat [seat] as the players see it; with [upcoming], with who
  /// comes and goes at the next hand, and the bot style the host picked
  /// for it.
  SeatInfo _seatInfo(int seat, {required bool showStyle, bool upcoming = false}) {
    final s = _seats[seat];
    final waiting = room._players.values.where((q) => q.waiting && q.seat == seat).firstOrNull;
    // A bot a person takes the seat of shows as leaving (the person as joining).
    final change = _botChanges.containsKey(seat) ? (_botChanges[seat],) : null;
    final joining = !upcoming ? null : waiting?.name ?? (change?.$1 != null && !s.isBot ? onlineBotNames[seat] : null);
    // Between hands, the chips of those not out (for the seats not in the hand being played).
    final chips = upcoming && _phase == RoomPhase.playing && !_out.contains(seat) ? _stacks[seat] : null;
    final p = s.token == null ? null : room._players[s.token];
    if (p != null) {
      return SeatInfo(
        seat: seat,
        kind: SeatKind.human,
        name: p.name,
        status: p.connected ? SeatStatus.connected : (p.left ? SeatStatus.left : SeatStatus.away),
        joining: joining,
        leaving: upcoming && (p.removing || p.standing || p.left),
        out: _out.contains(seat),
        sittingOut: p.sittingOut,
        chips: chips,
        member: p.id,
      );
    }
    if (!s.isBot) return SeatInfo(seat: seat, kind: SeatKind.empty, joining: joining);
    final style = upcoming ? (change?.$1 ?? s.botStyle!) : s.botStyle!;
    return SeatInfo(
      seat: seat,
      kind: SeatKind.bot,
      name: onlineBotNames[seat],
      style: showStyle ? style : null,
      joining: joining,
      leaving: upcoming && change != null && change.$1 == null,
      out: _out.contains(seat),
      chips: chips,
    );
  }
}
