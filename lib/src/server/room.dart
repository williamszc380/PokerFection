import 'dart:async';
import 'dart:math';

import '../engine/actions.dart';
import '../engine/events.dart';
import '../game/table_rules.dart' show nextHandSetup;
import '../online/clock.dart';
import '../online/protocol.dart';
import '../online/redact.dart';
import '../online/timing.dart';
import 'client_link.dart';
import 'hand_runner.dart';

/// A person in a room.
class RoomPlayer {
  RoomPlayer._(this.token, this.name, this.link, this.seat, {this.device});

  /// Proves who they are (secret: only sent to them), also to come back
  /// after the connection dropped.
  final String token;
  final String name;

  /// The key their app joined with (see JoinRoom.device), if any.
  final String? device;

  /// Their connection; null while they are away, and once they left.
  ClientLink? link;

  /// Their room seat (kept for them, while [waiting]).
  int seat;

  /// Joined during the game: seated from the next hand.
  bool waiting = false;

  /// Left during the game (or stayed away too long): the server plays
  /// their turns, and the seat is empty from the next hand.
  bool left = false;

  /// Ready for the next hand.
  bool ready = false;

  /// Sits out: not dealt in from the next hand announced (keeping the seat
  /// and chips) until they are back.
  bool sittingOut = false;

  /// The host removed them while they played a hand: they go when it ends.
  bool removing = false;

  /// Sat out by the server, for being away through a whole hand: dealt in
  /// again once they come back.
  bool _satOutAway = false;

  /// Away since the hand being played was dealt (sat out if still away when
  /// it ends).
  bool _awayAllHand = false;

  /// While away: gives up the seat when it fires.
  Timer? _hold;

  /// When the device last asked for a fresh copy of the hand (ms).
  int? _lastResync;

  /// When they said something in the chat lately (ms), oldest first.
  final List<int> _said = [];

  bool get connected => link != null && !left;

  /// The connection dropped: the seat is kept for a while
  /// ([OnlineTiming.hold]) and the server checks or folds for them after a
  /// few seconds ([OnlineTiming.awayLimit]), until they come back.
  bool get away => link == null && !left;
}

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
/// the bots' styles and without (for players who don't see them); and the
/// stacks, button and rules. Kept while the hand runs, for players who
/// catch up (see [Snapshot]).
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
  bool showCards,
});

/// A chat message as the room keeps it: its number, who said it (their
/// token and name) and what.
typedef _Said = ({int n, String token, String name, String text});

/// A refused message: the sender gets rejected{reason}, nothing changes.
class _Refused implements Exception {
  const _Refused(this.reason, {this.turnId});
  final Rejection reason;
  final int? turnId;
}

/// One table on the server, from the lobby through every hand.
///
/// Everything that happens to it (a message, a timer, a dropped
/// connection) is handled by one synchronous call, so they all happen in
/// one order. A refused message changes nothing; anything else going
/// wrong closes only this room.
///
/// A room starts with only its host; the other seats are empty until
/// people join or the host adds bots. Each hand is dealt to the seats
/// taken (see protocol.dart: room seats and hand seats), so the number of
/// players can change between hands; with fewer than [minPlayers] who can
/// play (people still connected, and bots while the host's device is there
/// to play them) the game waits.
///
/// A player whose connection drops is away: the seat stays theirs for
/// [OnlineTiming.hold], the server checks or folds for them after a few
/// seconds, and when they come back ([rejoin]) they get a snapshot of the
/// hand to catch up. After the hold they have left. The host leaving (or
/// away too long) closes the room: it usually runs on the host's device.
///
/// A player who runs out of chips keeps their seat but isn't dealt in. With
/// rebuys (the host's rule), a person chooses to buy in again ([Rebuy]: the
/// starting stack, from the next hand) or to leave, and bots buy in again
/// by themselves; without, they are out until the game ends, and people
/// watch. Once someone has been knocked out and only one player is left who
/// has chips (or may rebuy), the game is over: everyone is told who won
/// ([GameOver]) and the room is back in the lobby, with the same seats, bots
/// and rules, for the host to start a new game.
///
/// Everyone in the room may chat, whatever the phase (out of chips, or
/// waiting for a seat, too): each message goes to everyone connected, and
/// the room keeps the last [chatKept] for whoever joins or comes back.
///
/// A player who sits out keeps their seat and chips but isn't dealt in
/// (they watch) until they are back; one away through a whole hand is sat
/// out until they come back, rather than checked or folded hand after hand.
/// A change for a hand announced but not dealt yet announces it again (see
/// [_lineupChanged]). The host may remove a player: at once, or, if they
/// play the hand, when it ends; the room then refuses their token and
/// their device ([bars]).
///
/// The server deals with a secure deck, checks every move and keeps every
/// clock. Each player is sent only their own cards; the host's device,
/// which plays the bots, also gets the bots' cards, and a player may see
/// another's when the host allows it (everyone is told). The server itself
/// never decides for a bot, except to check or fold when the host's device
/// doesn't answer in time.
class Room {
  Room({
    required this.code,
    required RoomSettings settings,
    Map<int, String> bots = const {},
    required this._clock,
    required this._random,
    required this._onClosed,
    void Function(String message)? log,
  }) : _settings = settings,
       _log = log ?? ((_) {}) {
    _seats = [for (var s = 0; s < settings.seats; s++) _Seat()];
    for (final MapEntry(key: seat, value: style) in bots.entries) {
      // Seat 0 is the host's.
      if (seat > 0 && seat < _seats.length) _seats[seat].botStyle = style;
    }
  }

  final String code;
  final Clock _clock;

  /// Deals the cards (a secure one on the server).
  final Random _random;
  final void Function(Room room) _onClosed;
  final void Function(String message) _log;

  RoomSettings _settings;

  /// The host's changes during the game, for the next hand.
  RoomSettings? _nextSettings;

  /// During the game: the host's bots for the next hand, by room seat (a
  /// bot added, or a new style), or null for a bot taken away.
  final Map<int, String?> _botChanges = {};

  late List<_Seat> _seats;
  final Map<String, RoomPlayer> _players = {};
  String? _hostToken;

  RoomPhase _phase = RoomPhase.lobby;
  bool _closed = false;

  /// During the game, between hands: too few can play to deal.
  bool _paused = false;

  /// Closes the room when no hand is dealt for a long while.
  Timer? _idle;

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
  /// turn, a look at a seat (token and turn, or token and seat).
  final Set<(String, int)> _helpTold = {}, _peeksTold = {};

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

  /// The chat's last [chatKept] messages, oldest first, and how many there
  /// have been.
  final List<_Said> _chat = [];
  int _chatCount = 0;

  /// The tokens and devices of the players the host removed.
  final Set<String> _barredTokens = {}, _barredDevices = {};

  bool get isClosed => _closed;
  RoomPhase get phase => _phase;
  bool get isPaused => _paused;

  /// Whether the host removed the player with [token], or one on [device]:
  /// they can't come back.
  bool bars({String? token, String? device}) => _barredTokens.contains(token) || _barredDevices.contains(device);

  /// People still at the table (not away, nor gone).
  int get connectedCount => _players.values.where((p) => p.connected).length;

  /// The host, while connected.
  RoomPlayer? get _host {
    final p = _players[_hostToken];
    return p != null && p.connected ? p : null;
  }

  /// Everyone told what happens at the table: seated and connected.
  Iterable<RoomPlayer> get _seated => _players.values.where((p) => p.connected && !p.waiting);

  /// The connected players of [lineup] (a hand as announced or dealt), with
  /// their hand seats.
  Iterable<(RoomPlayer, int)> _playersOf(_Lineup lineup) sync* {
    for (final (seat, token) in lineup.tokens.indexed) {
      final p = token == null ? null : _players[token];
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
    return token == null ? onlineBotNames[seat] : (_players[token]?.name ?? onlineBotNames[seat]);
  }

  /// Whether whoever has room seat [seat] can play a hand now: a person
  /// who is connected and doesn't sit out, or a bot while the host's device
  /// is there to play it (and not out of chips).
  bool _canPlay(int seat) {
    if (_out.contains(seat)) return false;
    final s = _seats[seat];
    if (s.token case final token?) {
      final p = _players[token];
      return p != null && p.connected && !p.sittingOut;
    }
    return s.isBot && _host != null;
  }

  /// Whether room seat [seat] is dealt in the next hand announced: taken,
  /// not out of chips, and not by someone who sits out (or left, before the
  /// seats settle).
  bool _dealtIn(int seat) {
    final s = _seats[seat];
    if (s.isEmpty || _out.contains(seat)) return false;
    final p = _players[s.token];
    return p == null ? s.isBot : !p.sittingOut && !p.left;
  }

  /// Whether nobody has room seat [seat] from the next hand (nobody waits
  /// for it, no bot is coming, and whoever has it now leaves).
  bool _freeNextHand(int seat) {
    if (_players.values.any((p) => p.waiting && p.seat == seat)) return false;
    if (_botChanges.containsKey(seat)) return _botChanges[seat] == null;
    final s = _seats[seat];
    if (s.token != null) {
      final p = _players[s.token];
      return p == null || p.left || p.removing;
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

  /// In the lobby, or while the game waits for players: the room closes if
  /// nothing happens for a long while ([OnlineTiming.roomIdle]).
  void _watchIdle() {
    _idle?.cancel();
    _idle = null;
    if (!_seatsOpen || _closed) return;
    _idle = _clock.schedule(OnlineTiming.roomIdle, () => _guarded(() => close(CloseReason.idle)));
  }

  // ---------------------------------------------------------------------------
  // Joining, leaving and coming back
  // ---------------------------------------------------------------------------

  /// The room's creator, in seat 0.
  RoomPlayer addHost(ClientLink link, String name, String token) {
    final p = RoomPlayer._(token, name, link, 0);
    _players[token] = p;
    _seats[0].token = token;
    _hostToken = token;
    _send(p, Welcome(code: code, token: token, seat: 0, isHost: true));
    _sendRoom();
    _watchIdle();
    return p;
  }

  /// [name] takes an empty seat: at once in the lobby (or while the game
  /// waits for players), from the next hand during the game. Null if every
  /// seat is taken. [device] is the key their app joined with.
  RoomPlayer? join(ClientLink link, String name, String token, {String? device}) {
    if (_closed) return null;
    final seat = _freeSeat();
    if (seat == null) return null;
    final p = RoomPlayer._(token, name, link, seat, device: device);
    _players[token] = p;
    if (_seatsOpen) {
      _seats[seat].token = token;
      _freshStack(seat);
    } else {
      p.waiting = true;
    }
    _send(p, Welcome(code: code, token: token, seat: seat, isHost: false, waiting: p.waiting));
    _sendRoom();
    _sendChat(p);
    _guarded(_watchIdle);
    _guarded(_maybeResume);
    return p;
  }

  /// The player with [token] comes back on [link] (their connection had
  /// dropped, or they opened the room again elsewhere: the older connection
  /// is closed). They get who they are, the room and a snapshot of the hand.
  /// Null if there is no such player any more (they were away too long).
  /// Sat out for being away, they are dealt in again.
  RoomPlayer? rejoin(ClientLink link, String token) {
    if (_closed) return null;
    final p = _players[token];
    if (p == null || p.left) return null;
    final old = p.link;
    p.link = link;
    p._hold?.cancel();
    p._hold = null;
    p._awayAllHand = false;
    final back = p._satOutAway;
    if (back) {
      p.sittingOut = false;
      p._satOutAway = false;
    }
    if (old != null) {
      old.send(const Closing(CloseReason.replaced).encode());
      unawaited(old.close());
    }
    // The host's device plays the bots again (the snapshot has their cards).
    final hand = _hand;
    if (token == _hostToken && hand != null && !hand.isOver && !_dealing) _botDriver = link;
    // Their clock (or with the host back, a bot's) starts again: before the snapshot, which tells the time left.
    _guarded(() => _restartClockFor(p));
    _send(p, Welcome(code: code, token: token, seat: p.seat, isHost: token == _hostToken, waiting: p.waiting));
    _sendRoom();
    _sendSnapshot(p);
    _sendChat(p);
    _guarded(_watchIdle);
    _guarded(back ? _lineupChanged : _maybeResume);
    return p;
  }

  /// [p]'s connection [link] dropped (or went silent): they are away. The
  /// seat is theirs for a while; their turns are played after a few seconds.
  void disconnected(RoomPlayer p, ClientLink link) => _guarded(() {
    if (_players[p.token] != p || p.link != link || p.left) return;
    p.link = null;
    p._hold?.cancel();
    p._hold = _clock.schedule(OnlineTiming.hold, () => _guarded(() => _leave(p)));
    _restartClockFor(p);
    _sendRoom();
    _maybeDeal();
  });

  /// [p] gives up their seat (see [_letGo]); while the game waits, the last
  /// player with chips may have won.
  void _leave(RoomPlayer p) {
    if (_players[p.token] != p || p.left) return;
    _letGo(p);
    if (_closed) return;
    _sendRoom();
    _maybeDeal();
    _maybeResume();
  }

  /// [p] is disconnected and gives up their seat: in the lobby (or while the
  /// game waits) it is empty at once; during the game the server plays their
  /// turns, and the seat is empty from the next hand. The host leaving
  /// closes the room (it usually runs on the host's device, which then
  /// stops serving it).
  void _letGo(RoomPlayer p) {
    final link = p.link;
    p.link = null;
    p._hold?.cancel();
    p._hold = null;
    unawaited(link?.close());
    if (p.token == _hostToken) {
      close(CloseReason.roomClosed);
      return;
    }
    if (_seatsOpen || p.waiting) {
      _players.remove(p.token);
      if (_seats[p.seat].token == p.token) {
        _seats[p.seat].token = null;
        _freshStack(p.seat);
      }
    } else {
      p.left = true;
      // Their turn now is played at once.
      _restartClockFor(p);
    }
  }

  // ---------------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------------

  /// A message from [p] (already read and checked to be well formed).
  void receive(RoomPlayer p, ClientMessage m) {
    if (_closed || _players[p.token] != p) return;
    try {
      switch (m) {
        case ChangeSettings():
          _changeSettings(p, m);
        case AddBot():
          _addBot(p, m.style, m.seat);
        case RemoveBot():
          _removeBot(p, m.seat);
        case StartGame():
          _start(p);
        case Act():
          _act(p, m.hand, m.turnId, m.action);
        case BotAct():
          _act(p, m.hand, m.turnId, m.action, botSeat: m.seat);
        case UsedHelp():
          _usedHelp(p, m.hand, m.turnId);
        case Peek():
          _peek(p, m.hand, m.seat);
        case Ready():
          _ready(p, m.hand);
        case Rebuy():
          _rebuy(p);
        case SitOut():
          _sitOut(p, m.on);
        case RemovePlayer():
          _removePlayer(p, m.seat, m.name);
        case Say():
          _say(p, m.text);
        case Resync():
          _resync(p);
        case Leave():
          _leave(p);
        case CloseRoom():
          if (p.token != _hostToken) throw const _Refused(Rejection.notHost);
          close(CloseReason.roomClosed);
        case Ping():
          _send(p, Pong(m.n));
        case CreateRoom() || JoinRoom() || RejoinRoom():
          throw const _Refused(Rejection.badMessage);
      }
    } on _Refused catch (r) {
      _send(p, Rejected(r.reason, turnId: r.turnId));
    } catch (e, stack) {
      _fail(e, stack);
    }
  }

  void _changeSettings(RoomPlayer p, ChangeSettings m) {
    if (p.token != _hostToken) throw const _Refused(Rejection.notHost);
    final settings = m.settings, styles = m.botStyles;
    if (_phase == RoomPhase.lobby) {
      if (settings != null) _resize(settings);
    } else if (settings != null) {
      // During the game the table stays the same; the rest waits for the next hand.
      if (!settings.sameTable(_settings)) throw const _Refused(Rejection.illegal);
      _nextSettings = settings;
    }
    for (final MapEntry(key: seat, value: style) in (styles ?? const <int, String>{}).entries) {
      if (seat >= _seats.length) continue;
      if (_seatsOpen) {
        if (_seats[seat].isBot) _seats[seat].botStyle = style;
      } else if (_botChanges[seat] != null || (_seats[seat].isBot && !_botChanges.containsKey(seat))) {
        _botChanges[seat] = style;
      }
    }
    _sendRoom();
    _watchIdle();
  }

  /// The host seats a bot: in [preferred], or the first free seat.
  void _addBot(RoomPlayer p, String style, int? preferred) {
    if (p.token != _hostToken) throw const _Refused(Rejection.notHost);
    final seat = _freeSeat(preferred);
    if (seat == null) throw const _Refused(Rejection.illegal);
    if (_seatsOpen) {
      _seats[seat].botStyle = style;
      _freshStack(seat);
    } else {
      _botChanges[seat] = style;
    }
    _sendRoom();
    _watchIdle();
    _maybeResume();
  }

  /// The host takes the bot in [seat] away.
  void _removeBot(RoomPlayer p, int seat) {
    if (p.token != _hostToken) throw const _Refused(Rejection.notHost);
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
    _sendRoom();
    _watchIdle();
    _maybeResume();
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
        if (seat.token case final token?) _players[token]!.seat = free;
      }
    }
    _settings = settings;
  }

  void _start(RoomPlayer p) {
    if (p.token != _hostToken) throw const _Refused(Rejection.notHost);
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
    if (_phase != RoomPhase.playing || !_paused || _closed) return;
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
    if (_phase != RoomPhase.playing || !_settings.rebuys || !_out.contains(p.seat) || _seats[p.seat].token != p.token) {
      throw const _Refused(Rejection.illegal);
    }
    _freshStack(p.seat);
    _lineupChanged();
  }

  /// [p] sits out ([on]: not dealt in from the next hand, keeping the seat
  /// and chips; only during the game), or is back: dealt in again from the
  /// next hand. Either way, a hand announced but not dealt yet is announced
  /// again.
  void _sitOut(RoomPlayer p, bool on) {
    if (on && _phase != RoomPhase.playing) throw const _Refused(Rejection.illegal);
    p._satOutAway = false;
    if (p.sittingOut == on) return;
    p.sittingOut = on;
    _lineupChanged();
  }

  /// The host removes the person in room seat [seat] (if still [name]): at
  /// once, or while they play a hand (dealt in, not folded), when it ends.
  void _removePlayer(RoomPlayer p, int seat, String name) {
    if (p.token != _hostToken) throw const _Refused(Rejection.notHost);
    final target = seat < _seats.length ? _players[_seats[seat].token] : null;
    if (target == null || target.token == _hostToken) throw const _Refused(Rejection.illegal);
    // The seat changed hands meanwhile, or they are going already.
    if (target.name != name || target.left || target.removing) throw const _Refused(Rejection.stale);
    final hand = _hand, at = _handSeatOf(target);
    if (!_dealing && !_paused && hand != null && !hand.isOver && at >= 0 && !hand.hand.isFolded(at)) {
      target.removing = true;
      _sendRoom();
      return;
    }
    _expel(target);
    _lineupChanged();
  }

  /// [q], whom the host removed, goes: they are told and disconnected (their
  /// seat given up as when leaving: see [_letGo]), and can't come back,
  /// neither with their token nor from their device. Everyone else is told.
  void _expel(RoomPlayer q) {
    q.removing = false;
    _barredTokens.add(q.token);
    if (q.device case final device?) _barredDevices.add(device);
    _send(q, const Closing(CloseReason.removed));
    _letGo(q);
    final told = PlayerRemoved(seat: q.seat, name: q.name);
    for (final other in _players.values) {
      if (other.link != null) _send(other, told);
    }
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
        final now = _clock.nowMs;
        _betweenHands(
          minWait: Duration(milliseconds: max(0, _earliestDeal - now)),
          maxWait: Duration(milliseconds: max(0, _latestDeal - now)),
          again: true,
        );
        return;
      }
    }
    _sendRoom();
    _maybeResume();
  }

  /// A device's copy of the hand went wrong: it gets a fresh one (not too
  /// often).
  void _resync(RoomPlayer p) {
    final now = _clock.nowMs, last = p._lastResync;
    if (last != null && now - last < OnlineTiming.resyncGap.inMilliseconds) return;
    p._lastResync = now;
    _sendSnapshot(p);
  }

  // ---------------------------------------------------------------------------
  // Help and looking at cards
  // ---------------------------------------------------------------------------

  /// [p] pressed Show GTO at turn [turnId]: everyone is told (once per turn).
  void _usedHelp(RoomPlayer p, int handNumber, int turnId) {
    final hand = _hand;
    if (hand == null || handNumber != hand.handNumber || turnId > hand.turnId) {
      throw _Refused(Rejection.stale, turnId: turnId);
    }
    if (_handHelp == HelpLevel.none || _handSeatOf(p) < 0 || !p.connected) {
      throw _Refused(Rejection.illegal, turnId: turnId);
    }
    if (!_helpTold.add((p.token, turnId))) return;
    _tell(Notice(kind: NoticeKind.help, hand: handNumber, seat: p.seat, name: p.name));
  }

  /// [p] asks to see the cards of hand seat [seat]: only they get them
  /// (if the host lets players look), and everyone is told.
  void _peek(RoomPlayer p, int handNumber, int seat) {
    final hand = _hand, dealt = _dealt;
    if (_dealing || _paused || hand == null || dealt == null || hand.isOver || handNumber != hand.handNumber) {
      throw const _Refused(Rejection.stale);
    }
    final mine = _handSeatOf(p);
    if (mine < 0 || !p.connected) throw const _Refused(Rejection.notYourTurn);
    final cards = peekCardsFor(hand.hand, seat: seat, viewerSeat: mine, allowed: _settings.showCards);
    if (cards == null) throw const _Refused(Rejection.illegal);
    _send(p, PeekCards(hand: handNumber, seat: seat, cards: cards));
    if (!_peeksTold.add((p.token, seat))) return;
    final target = dealt.seats[seat];
    _tell(
      Notice(
        kind: NoticeKind.peek,
        hand: handNumber,
        seat: p.seat,
        name: p.name,
        target: target,
        targetName: _nameOf(target),
      ),
    );
  }

  /// Tells everyone at the table.
  void _tell(Notice notice) {
    for (final p in _seated) {
      _send(p, notice);
    }
  }

  // ---------------------------------------------------------------------------
  // Chat
  // ---------------------------------------------------------------------------

  /// [p] says [text] (cleaned as it was read): everyone connected gets it,
  /// at the table, watching or in the lobby. At most [chatBurst] messages
  /// each [OnlineTiming.chatWindow].
  void _say(RoomPlayer p, String text) {
    final now = _clock.nowMs;
    p._said.removeWhere((at) => now - at >= OnlineTiming.chatWindow.inMilliseconds);
    if (p._said.length >= chatBurst) throw const _Refused(Rejection.rateLimited);
    p._said.add(now);
    final said = (n: ++_chatCount, token: p.token, name: p.name, text: text);
    _chat.add(said);
    if (_chat.length > chatKept) _chat.removeAt(0);
    for (final q in _players.values) {
      if (q.link != null) _send(q, ChatLines([_chatLine(said, q)]));
    }
  }

  /// The chat so far, to [p], who joined or came back.
  void _sendChat(RoomPlayer p) {
    if (_chat.isNotEmpty) _send(p, ChatLines([for (final said in _chat) _chatLine(said, p)], all: true));
  }

  ChatLine _chatLine(_Said said, RoomPlayer to) =>
      ChatLine(n: said.n, name: said.name, text: said.text, you: said.token == to.token);

  // ---------------------------------------------------------------------------
  // Hands
  // ---------------------------------------------------------------------------

  /// Between hands (and when the game ends): those the host removed during
  /// the hand go, those who left give up their seats, the host's bots come
  /// and go, those who joined sit down with the starting stack, and the
  /// host's changes apply.
  void _settleSeats() {
    for (final p in [..._players.values]) {
      if (p.removing) _expel(p);
    }
    for (final p in [..._players.values]) {
      if (!p.left) continue;
      _players.remove(p.token);
      if (_seats[p.seat].token == p.token) {
        _seats[p.seat].token = null;
        _freshStack(p.seat);
      }
    }
    for (final MapEntry(key: seat, value: style) in _botChanges.entries) {
      final s = _seats[seat];
      if (s.token != null) continue;
      // A new bot buys in; one taken away takes its chips.
      if (style == null || !s.isBot) _freshStack(seat);
      s.botStyle = style;
    }
    _botChanges.clear();
    // Those who joined sit down (one who is away meanwhile too: their seat waits for them).
    for (final p in _players.values) {
      if (!p.waiting) continue;
      p.waiting = false;
      _seats[p.seat].token = p.token;
      _freshStack(p.seat);
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
    _idle?.cancel();
    _idle = null;

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
        ? lineup[_random.nextInt(n)]
        : lineup.firstWhere((s) => s > _buttonFrom, orElse: () => lineup.first);
    _handStacks = next.stacks;
    _handButton = lineup.indexOf(_buttonSeat);
    for (final (i, s) in lineup.indexed) {
      _stacks[s] = next.stacks[i];
    }
    if (!again) _handNumber++;
    _dealing = true;
    for (final p in _players.values) {
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
      showCards: _settings.showCards,
    );
    // Devices that solve (help, or the host's GTO bots) get longer.
    final solving = _settings.help != HelpLevel.none || _seats.any((s) => s.botStyle == 'gto');
    final latest = maxWait ?? minWait + (solving ? OnlineTiming.readyWaitWithHelp : OnlineTiming.readyWait);
    _earliestDeal = _clock.nowMs + minWait.inMilliseconds;
    _latestDeal = _clock.nowMs + latest.inMilliseconds;
    _minTimer = _clock.schedule(minWait, () => _guarded(_maybeDeal));
    _maxTimer = _clock.schedule(latest, () => _guarded(_deal));

    _sendRoom();
    for (final (p, seat) in _audienceOf(announced)) {
      _send(
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

  /// Everyone at the table, with their hand seat in [lineup] (null for a
  /// player out of chips, who watches).
  Iterable<(RoomPlayer, int?)> _audienceOf(_Lineup lineup) sync* {
    for (final p in _seated) {
      final seat = lineup.tokens.indexOf(p.token);
      yield (p, seat < 0 ? null : seat);
    }
  }

  /// Only one player is left with chips (or nobody: [winner] is null):
  /// everyone is told who won, and the room is back in the lobby with the
  /// same seats, bots and rules, for the host to start a new game.
  void _gameOver(int? winner) {
    _settleSeats();
    final message = GameOver(seat: winner, name: winner == null ? null : _nameOf(winner));
    for (final p in _players.values) {
      if (p.connected) _send(p, message);
    }
    _phase = RoomPhase.lobby;
    _paused = false;
    _dealing = false;
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
    _sendRoom();
    _watchIdle();
  }

  /// [lineup] (hand [hand]) as [p] is told about it, in hand seat [you]
  /// (null: watching).
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
    seats: p.token == _hostToken || lineup.showStyles ? lineup.withStyles : lineup.withoutStyles,
    help: lineup.help,
    turnLimit: lineup.turnLimit,
    showCards: lineup.showCards,
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
    _sendRoom();
    _watchIdle();
  }

  void _maybeDeal() {
    if (!_dealing || _clock.nowMs < _earliestDeal) return;
    // Those who watch don't hold up the deal.
    if (_playersOf(_announced!).any((e) => !e.$1.ready)) return;
    _deal();
  }

  void _deal() {
    if (!_dealing || _closed) return;
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
      if (_players[token] case final p?) p._awayAllHand = p.away;
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
      random: _random,
      botSeats: bots,
    );
    _handHelp = _settings.help;
    _helpTold.clear();
    _peeksTold.clear();
    final host = _host;
    _botDriver = host?.link;
    if (host != null && bots.isNotEmpty) {
      _send(host, BotCards(hand: _handNumber, cards: botCardsFor(hand.hand, bots)));
    }
    final turn = _openTurn();
    for (final (p, seat) in _audienceOf(dealt)) {
      _send(p, HandDealt(hand: _handNumber, batch: redactBatch(hand.batches.first, seat), turn: turn));
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
      final p = _players[token];
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
    final host = _host;
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
    _turnShownEnd = shown == null ? null : _clock.nowMs + watch.inMilliseconds + shown;
    if (deadline == null) return;
    _turnTimer = _clock.schedule(watch + deadline, () => _guarded(() => _timeUp(turnId, limit.cause)));
  }

  /// [p] went away, came back or left: if it is their turn (or, for the
  /// host, a bot's), its clock starts again from now, with their new limit.
  void _restartClockFor(RoomPlayer p) {
    final hand = _hand, dealt = _dealt, turn = _turn;
    if (_dealing || _paused || hand == null || dealt == null || hand.isOver || turn == null) return;
    final seat = hand.hand.toAct!;
    final token = dealt.tokens[seat];
    if (token == p.token || (token == null && p.token == _hostToken)) _armTimer(turn.turnId, seat, Duration.zero);
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
    final message = HandEvents(hand: hand.handNumber, turnId: ended, cause: cause, batch: batch, turn: turn);
    for (final (p, _) in _audienceOf(_dealt!)) {
      _send(p, message);
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
      if (_players[token] case final p? when p._awayAllHand && p.away && !p.sittingOut) {
        p.sittingOut = true;
        p._satOutAway = true;
      }
    }
    _botDriver = null;
    _turnShownEnd = null;
    // Time to see the end of the hand (the showdown, the pot paid) and its result.
    _betweenHands(minWait: Duration(milliseconds: playbackMs(hand.batches.last)) + OnlineTiming.betweenHands);
  }

  /// Everything [p] needs to catch up: the hand they are in or watch (or
  /// the last one, until the next is dealt) as they may see it, and the
  /// next hand if it is announced. A player waiting for a seat gets neither.
  void _sendSnapshot(RoomPlayer p) {
    final hand = _hand, dealt = _dealt, now = _clock.nowMs;
    SnapshotHand? current;
    final at = _handSeatOf(p), seat = at < 0 ? null : at;
    if (hand != null && dealt != null && !p.waiting) {
      final open = hand.isOver || _dealing ? null : _turn;
      final shownEnd = _turnShownEnd;
      current = SnapshotHand(
        lineup: _announcement(p, dealt, hand: hand.handNumber, you: seat, minWaitMs: 0, maxWaitMs: 0),
        batches: redactBatches(hand.batches, seat),
        turn: open?.resumed(shownEnd == null ? null : max(0, shownEnd - now)),
        botCards: p.token == _hostToken ? botCardsFor(hand.hand, hand.botSeats) : const {},
        peeks: {
          if (seat != null)
            for (final (token, peeked) in _peeksTold)
              if (token == p.token) peeked: ?peekCardsFor(hand.hand, seat: peeked, viewerSeat: seat, allowed: true),
        },
      );
    }
    NextHand? next;
    final announced = _announced;
    final you = announced?.tokens.indexOf(p.token) ?? -1;
    if (_dealing && announced != null && !p.waiting) {
      next = _announcement(
        p,
        announced,
        hand: _handNumber,
        you: you < 0 ? null : you,
        minWaitMs: max(0, _earliestDeal - now),
        maxWaitMs: max(0, _latestDeal - now),
      );
    }
    _send(p, Snapshot(hand: current, next: next));
  }

  // ---------------------------------------------------------------------------
  // Closing
  // ---------------------------------------------------------------------------

  /// Ends the room: everyone is told why, and disconnected.
  void close(CloseReason reason) {
    if (_closed) return;
    _closed = true;
    _turnTimer?.cancel();
    _minTimer?.cancel();
    _maxTimer?.cancel();
    _idle?.cancel();
    final message = Closing(reason).encode();
    for (final p in _players.values) {
      p._hold?.cancel();
      final link = p.link;
      if (link == null) continue;
      p.link = null;
      link.send(message);
      unawaited(link.close());
    }
    _onClosed(this);
  }

  void _guarded(void Function() body) {
    if (_closed) return;
    try {
      body();
    } catch (e, stack) {
      _fail(e, stack);
    }
  }

  void _fail(Object error, StackTrace stack) {
    _log('Room $code closed after an error: $error\n$stack');
    close(CloseReason.roomError);
  }

  // ---------------------------------------------------------------------------
  // Sending
  // ---------------------------------------------------------------------------

  void _send(RoomPlayer p, ServerMessage m) => p.link?.send(m.encode());

  /// Everyone gets the room as it is now, with the host's changes for the
  /// next hand (styles only for the host, unless the host shows them to
  /// everyone).
  void _sendRoom() {
    final settings = _nextSettings ?? _settings;
    for (final p in _players.values) {
      if (p.link == null) continue;
      final showStyles = p.token == _hostToken || settings.showStyles;
      _send(
        p,
        RoomState(
          code: code,
          phase: _phase,
          paused: _paused,
          host: _players[_hostToken]?.seat,
          you: p.seat,
          settings: settings,
          seats: [for (var s = 0; s < _seats.length; s++) _seatInfo(s, showStyle: showStyles, upcoming: true)],
        ),
      );
    }
  }

  /// Room seat [seat] as the players see it; with [upcoming], with who
  /// comes and goes at the next hand, and the bot style the host picked
  /// for it.
  SeatInfo _seatInfo(int seat, {required bool showStyle, bool upcoming = false}) {
    final s = _seats[seat];
    final waiting = _players.values.where((q) => q.waiting && q.seat == seat).firstOrNull;
    final change = _botChanges.containsKey(seat) ? (_botChanges[seat],) : null;
    final joining = !upcoming ? null : waiting?.name ?? (change?.$1 != null && !s.isBot ? onlineBotNames[seat] : null);
    // Between hands, the chips of those not out (for the seats not in the hand being played).
    final chips = upcoming && _phase == RoomPhase.playing && !_out.contains(seat) ? _stacks[seat] : null;
    final p = s.token == null ? null : _players[s.token];
    if (p != null) {
      return SeatInfo(
        seat: seat,
        kind: SeatKind.human,
        name: p.name,
        status: p.connected ? SeatStatus.connected : (p.left ? SeatStatus.left : SeatStatus.away),
        joining: joining,
        leaving: upcoming && p.removing,
        out: _out.contains(seat),
        sittingOut: p.sittingOut,
        chips: chips,
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
