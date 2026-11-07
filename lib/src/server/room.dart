import 'dart:async';
import 'dart:math';

import '../engine/actions.dart';
import '../engine/events.dart';
import '../game/table_rules.dart' show nextHandSetup;
import '../kit/seats.dart' show kitBotNames;
import '../online/games/game_envelope.dart';
import '../online/clock.dart';
import '../online/games/game_runner.dart';
import '../online/games/online_games.dart';
import '../online/protocol.dart';
import '../online/redact.dart';
import '../online/timing.dart';
import 'client_link.dart';
import 'hand_runner.dart';

part 'poker_table.dart';
part 'runner_table.dart';

/// A person in a room (a member): a spectator, or a player in a seat.
class RoomPlayer {
  RoomPlayer._(this.token, this.name, this.link, this.id, {this.device});

  /// Proves who they are (secret: only sent to them), also to come back
  /// after the connection dropped.
  final String token;
  final String name;

  /// Their member id (1, 2, 3…, never reused in the room), shown to
  /// everyone: not a secret.
  final int id;

  /// The key their app joined with (see JoinRoom.device), if any.
  final String? device;

  /// Their connection; null while they are away, and once they left.
  ClientLink? link;

  /// Their room seat; null for a spectator. While [waiting], the seat they
  /// take at the next hand (kept for them).
  int? seat;

  /// Asked for a seat during a hand: seated from the next one (a spectator
  /// until then).
  bool waiting = false;

  /// Gave up their seat during a hand: they play it out, and spectate from
  /// the next one.
  bool standing = false;

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

  /// Gets what spectators get: no seat, or not seated yet ([waiting]).
  bool get spectator => seat == null || waiting;
}

/// The game a room plays: Hold'em ([online] and [setup] null), or another
/// game with the host's setup.
typedef _Game = ({String key, OnlineGame? online, OnlineSetup? setup});

const _Game _holdem = (key: holdemKey, online: null, setup: null);

/// A chat message as the room keeps it: its number, who said it (their
/// token and name) and what.
typedef _Said = ({int n, String token, String name, String text});

/// The table that plays a room's game: poker's ([_PokerTable]) or any
/// other game's through its runner ([_RunnerTable]). The room keeps the
/// members (links, holds, bans, the chat) and calls the table at each of
/// its entry points, in a fixed order: each hook below is one entry
/// point's part about the table.
abstract class _Table {
  /// Lobby, or playing (also while the game waits for players).
  RoomPhase get phase;

  /// Playing, but too few can play: no round is dealt.
  bool get paused;

  /// Seats change at once (the lobby, or while the game waits for
  /// players): the room's idle timer runs then.
  bool get seatsOpen;

  /// Every seat as RoomState shows it, with who comes and goes at the next
  /// round ([showStyles]: with the bots' styles or levels).
  List<SeatInfo> seatInfos({required bool showStyles});

  /// Hold'em's rules as RoomState shows them (null for the other games).
  RoomSettings? get holdemSettings;

  /// Whether RoomState shows [p] the bots' styles.
  bool showsStylesTo(RoomPlayer p);

  /// [p] joined ([joining]) or came back: what they need to catch up (the
  /// round being played as they may see it; the host also the bots' part).
  void caughtUp(RoomPlayer p, {required bool joining});

  /// [p]'s device asked for a fresh copy of the round.
  void resync(RoomPlayer p);

  /// [p] came back, before they are welcomed: the host plays the bots
  /// again; their clock (or for the host, a bot's) starts again.
  void onRejoin(RoomPlayer p);

  /// After [p] came back and was caught up ([back]: sat out for being
  /// away, now dealt in again).
  void afterRejoin(RoomPlayer p, {required bool back});

  /// [p]'s connection dropped: their clock starts again, shorter.
  void onAway(RoomPlayer p);

  /// After someone went away (the room told): a round waiting for them
  /// may be dealt.
  void afterAway();

  /// [p] leaves for good: a spectator (or anyone while seats are open) is
  /// removed from the room at once, with their seat; a player in a round
  /// plays it out by the clock, and goes when it ends.
  void onLetGo(RoomPlayer p);

  /// After someone left (the room told).
  void afterLeave();

  /// Whether the host's removal of [p] waits for the round's end (they
  /// play it).
  bool playsRound(RoomPlayer p);

  /// After someone was removed.
  void afterRemoval();

  void changeSettings(RoomPlayer p, ChangeSettings m);
  void addBot(RoomPlayer p, String style, int? seat);
  void removeBot(RoomPlayer p, int seat);
  void start(RoomPlayer p);
  void takeSeat(RoomPlayer p, int? seat);
  void leaveSeat(RoomPlayer p);

  /// The host ends the game (already checked to be the host).
  void endGame();

  /// The game's own messages (poker's acts and its Ready, Show cards,
  /// rebuys and sitting out; the other games' GameMessage): throws
  /// [_Refused].
  void receive(RoomPlayer p, ClientMessage m);

  /// Every timer of the table stops (the room closes, or plays another
  /// game).
  void close();
}

/// A refused message: the sender gets rejected{reason}, nothing changes.
class _Refused implements Exception {
  const _Refused(this.reason, {this.turnId});
  final Rejection reason;
  final int? turnId;
}

/// One room on the server: its members, and the table that plays its game,
/// from the lobby through every hand.
///
/// A room starts with no game: only its members and the chat, no seats.
/// The host picks a game in the lobby ([ChooseGame]), and its seats come
/// with it; picking another sends everyone back to watching (the room
/// keeps the host's Hold'em rules for when Hold'em is picked again). With
/// no game, everything about seats and the table is refused.
///
/// Everything that happens to it (a message, a timer, a dropped
/// connection) is handled by one synchronous call, so they all happen in
/// one order. A refused message changes nothing; anything else going
/// wrong closes only this room.
///
/// Everyone enters as a spectator, the host too, up to [cap] members (bots
/// don't count). A member takes a seat ([TakeSeat]) and gives it up
/// ([LeaveSeat]): at once in the lobby, while the game waits for players
/// and between hands; during a hand, from the next one (see
/// [_PokerTable._takeSeat]). Each hand is dealt to the seats taken (see
/// protocol.dart: room seats and hand seats), so the number of players can
/// change between hands; with fewer than [minPlayers] who can play (people
/// still connected, and bots while the host's device is there to play
/// them) the game waits.
///
/// A member whose connection drops is away: a player's seat stays theirs
/// for [OnlineTiming.hold], the server checks or folds for them after a few
/// seconds, and when they come back ([rejoin]) they get a snapshot of the
/// hand to catch up. After the hold they have left (a spectator is gone at
/// once). The host leaving closes the room: it usually runs on the host's
/// device. On a server of its own the host being away too long closes it
/// too, and a room nobody uses for a long while closes ([_idleAfter]); a
/// room on a device (with no [_idleAfter]) never idles out, and its host's
/// absence never ends it: the room lives as long as the host's app does,
/// and the host comes back with [RejoinRoom] like anyone.
///
/// A player who runs out of chips keeps their seat but isn't dealt in. With
/// rebuys (the host's rule), a person chooses to buy in again ([Rebuy]: the
/// starting stack, from the next hand) or to leave, and bots buy in again
/// by themselves; without, they are out until the game ends, and people
/// watch. Once someone has been knocked out and only one player is left who
/// has chips (or may rebuy), the game is over: everyone is told who won
/// ([GameOver]) and the room is back in the lobby, with the same seats, bots
/// and rules, for the host to start a new game. The host may also end the
/// game ([EndGame]).
///
/// Everyone in the room may chat, whatever the phase: each message goes to
/// everyone connected, and the room keeps the last [chatKept] for whoever
/// joins or comes back.
///
/// A player who sits out keeps their seat and chips but isn't dealt in
/// (they watch) until they are back; one away through a whole hand is sat
/// out until they come back, rather than checked or folded hand after hand.
/// A change for a hand announced but not dealt yet announces it again (see
/// [_PokerTable._lineupChanged]). The host may remove a member: a spectator
/// at once; a player at once, or, if they play the hand, when it ends; the
/// room then refuses their token and their device ([bars]).
///
/// The server deals with a secure deck, checks every move and keeps every
/// clock. Each seat is sent only its own cards; spectators every person's,
/// and the bots' only when the host allows it ([HostSettings]); the host's
/// device, which plays the bots, also gets the bots' cards. Nobody gets the
/// deck or the cards not dealt yet. The server itself never decides for a
/// bot, except to check or fold when the host's device doesn't answer in
/// time.
class Room {
  /// A room with no game ([game] null, what the app asks for), or with
  /// Hold'em's table at once ([game] [holdemKey], with [bots]: a shortcut
  /// for tests and tools). [settings] are its Hold'em rules until the host
  /// changes them.
  Room({
    required this.code,
    RoomSettings settings = const RoomSettings(),
    Map<int, String> bots = const {},
    String? game,
    required this._clock,
    required this._random,
    required this._onClosed,
    this._atMeetingService,
    this._cap = 16,
    this._idleAfter = OnlineTiming.roomIdle,
    Map<String, OnlineGame>? games,
    void Function(String message)? log,
  }) : assert(game == null || game == holdemKey, "A room starts with no game or with Hold'em"),
       assert(game == holdemKey || bots.isEmpty, "Bots come with a Hold'em table"),
       _holdemSettings = settings,
       _games = games ?? onlineGames,
       _log = log ?? ((_) {}) {
    if (game == holdemKey) {
      _game = _holdem;
      _table = _PokerTable(this, settings, bots);
    }
  }

  final String code;
  final Clock _clock;

  /// Deals the cards (a secure one on the server).
  final Random _random;
  final void Function(Room room) _onClosed;
  final void Function(String message) _log;

  /// Whether the room can be reached through the meeting service now (its
  /// host holds the room's name there); each Welcome says so. Null: never
  /// (a server of its own).
  final bool Function()? _atMeetingService;

  bool get _peer => _atMeetingService?.call() ?? false;

  /// The most members (not left) the room takes, the host's included; bots
  /// don't count. The hosting side sets it (see RoomRegistry.roomCap).
  final int _cap;

  /// How long the room stays open with nothing happening in the lobby (or
  /// while the game waits for players); null: it never closes for being
  /// idle, and its host's absence doesn't end it (a room on a device, see
  /// RoomRegistry.roomIdle).
  final Duration? _idleAfter;

  /// The games other than Hold'em this room can play.
  final Map<String, OnlineGame> _games;

  /// The game the room plays (the host picks it in the lobby); null until
  /// they do.
  _Game? _game;

  /// The host's Hold'em rules, kept while the room plays another game (or
  /// none), for when Hold'em is picked again.
  RoomSettings _holdemSettings;

  /// The host lets spectators see the bots' cards (from the next hand).
  bool _seeBots = false;

  /// The table: its seats, the game and every round (poker_table.dart,
  /// runner_table.dart). A new one when the host picks another game; null
  /// with no game.
  _Table? _table;

  final Map<String, RoomPlayer> _players = {};
  String? _hostToken;

  /// The last member id given.
  int _nextId = 0;

  bool _closed = false;

  /// Closes the room when no hand is dealt for a long while.
  Timer? _idle;

  /// The chat's last [chatKept] messages, oldest first, and how many there
  /// have been.
  final List<_Said> _chat = [];
  int _chatCount = 0;

  /// The tokens and devices of the members the host removed.
  final Set<String> _barredTokens = {}, _barredDevices = {};

  bool get isClosed => _closed;
  RoomPhase get phase => _table?.phase ?? RoomPhase.lobby;
  bool get isPaused => _table?.paused ?? false;

  /// The tokens of the members still in the room (not left, not removed),
  /// spectators included.
  Iterable<String> get tokensSeated => [
    for (final p in _players.values)
      if (!p.left && !bars(token: p.token)) p.token,
  ];

  /// The token of a member still in the room (not left, not removed) that
  /// [proves] says is proven, or null: a member coming back with a proof
  /// of their place rather than its token (see seat_proof.dart).
  String? tokenProven(bool Function(String token) proves) {
    for (final p in _players.values) {
      if (!p.left && !bars(token: p.token) && proves(p.token)) return p.token;
    }
    return null;
  }

  /// Whether the host removed the member with [token], or one on [device]:
  /// they can't come back.
  bool bars({String? token, String? device}) => _barredTokens.contains(token) || _barredDevices.contains(device);

  /// Members connected now (not away, nor gone).
  int get connectedCount => _players.values.where((p) => p.connected).length;

  /// The host, while connected.
  RoomPlayer? get _host {
    final p = _players[_hostToken];
    return p != null && p.connected ? p : null;
  }

  /// The game as RoomState says it (null: none picked yet).
  GameChoice? get _gameChoice => switch (_game) {
    null => null,
    (key: final key, online: final online?, setup: final setup) => GameChoice(
      key,
      gv: online.gv,
      setup: setup?.toJson(),
    ),
    _ => GameChoice.holdem,
  };

  /// In the lobby (with a game or none), or while the game waits for
  /// players: the room closes if nothing happens (a chat line counts) for
  /// [_idleAfter]; never on a device.
  void _watchIdle() {
    _idle?.cancel();
    _idle = null;
    final after = _idleAfter;
    if (after == null || _closed || !(_table?.seatsOpen ?? true)) return;
    _idle = _clock.schedule(after, () => _guarded(() => close(CloseReason.idle)));
  }

  // ---------------------------------------------------------------------------
  // Joining, leaving and coming back
  // ---------------------------------------------------------------------------

  /// The room's creator: a spectator, like everyone (see [TakeSeat]).
  RoomPlayer addHost(ClientLink link, String name, String token) {
    final p = RoomPlayer._(token, name, link, ++_nextId);
    _players[token] = p;
    _hostToken = token;
    _send(p, Welcome(code: code, token: token, id: p.id, isHost: true, peer: _peer));
    _sendRoom();
    _watchIdle();
    return p;
  }

  /// [name] comes in as a spectator, and is caught up with the hand being
  /// played. Null when the room has [_cap] members already (or is
  /// closed). [device] is the key their app joined with.
  RoomPlayer? join(ClientLink link, String name, String token, {String? device}) {
    if (_closed) return null;
    if (_players.values.where((p) => !p.left).length >= _cap) return null;
    final p = RoomPlayer._(token, name, link, ++_nextId, device: device);
    _players[token] = p;
    _send(p, Welcome(code: code, token: token, id: p.id, isHost: false, peer: _peer));
    _sendRoom();
    _table?.caughtUp(p, joining: true);
    _sendChat(p);
    _guarded(_watchIdle);
    return p;
  }

  /// The member with [token] comes back on [link] (their connection had
  /// dropped, or they opened the room again elsewhere: the older connection
  /// is closed). They get who they are, the room and a snapshot of the hand.
  /// Null if there is no such member any more (they were away too long).
  /// Sat out for being away, they are dealt in again. A spectator comes back
  /// a spectator, a player to their seat.
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
    final table = _table;
    // The host's device plays the bots again; their clock (or with the host back, a bot's) starts again: before
    // the catching up, which tells the time left.
    table?.onRejoin(p);
    _send(p, Welcome(code: code, token: token, id: p.id, isHost: token == _hostToken, peer: _peer));
    _sendRoom();
    table?.caughtUp(p, joining: false);
    _sendChat(p);
    _guarded(_watchIdle);
    if (table != null) _guarded(() => table.afterRejoin(p, back: back));
    return p;
  }

  /// [p]'s connection [link] dropped (or went silent): they are away. Their
  /// place is theirs for a while; their turns are played after a few
  /// seconds. The host of a room on a device (no [_idleAfter]) stays a
  /// member however long they are away: the room runs in their app, and
  /// they come back with [RejoinRoom].
  void disconnected(RoomPlayer p, ClientLink link) => _guarded(() {
    if (_players[p.token] != p || p.link != link || p.left) return;
    p.link = null;
    p._hold?.cancel();
    p._hold = p.token == _hostToken && _idleAfter == null
        ? null
        : _clock.schedule(OnlineTiming.hold, () => _guarded(() => _leave(p)));
    _table?.onAway(p);
    _sendRoom();
    _table?.afterAway();
  });

  /// [p] leaves the room (see [_letGo]); while the game waits, the last
  /// player with chips may have won.
  void _leave(RoomPlayer p) {
    if (_players[p.token] != p || p.left) return;
    _letGo(p);
    if (_closed) return;
    _sendRoom();
    _table?.afterLeave();
  }

  /// [p] is disconnected and leaves: a spectator (or one waiting for a
  /// seat) is gone at once, and a player too in the lobby (or while the
  /// game waits: their seat is empty at once); during the game the server
  /// plays a player's turns, and the seat is empty from the next hand. The
  /// host leaving for good (Leave, or the hold on a server of its own)
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
    final table = _table;
    if (table == null) {
      _players.remove(p.token);
    } else {
      table.onLetGo(p);
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
          _seats.changeSettings(p, m);
        case AddBot():
          _seats.addBot(p, m.style, m.seat);
        case RemoveBot():
          _seats.removeBot(p, m.seat);
        case StartGame():
          _seats.start(p);
        case TakeSeat():
          _seats.takeSeat(p, m.seat);
        case LeaveSeat():
          _seats.leaveSeat(p);
        case EndGame():
          if (p.token != _hostToken) throw const _Refused(Rejection.notHost);
          _seats.endGame();
        case ChooseGame():
          _chooseGame(p, m);
        case HostSettings():
          if (p.token != _hostToken) throw const _Refused(Rejection.notHost);
          _seeBots = m.seeBots;
          _sendRoom();
        // The game's own messages: with no game they name a round that isn't there (or need a seat).
        case Act(:final turnId) || BotAct(:final turnId) || UsedHelp(:final turnId):
          (_table ?? _stale(turnId)).receive(p, m);
        case ShowCards() || Ready() || GameMessage():
          (_table ?? _stale()).receive(p, m);
        case Rebuy() || SitOut():
          _seats.receive(p, m);
        case RemoveMember():
          _removePlayer(p, m.id, m.name);
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

  /// The table, for what needs one (seats, bots, the game's rules): with no
  /// game there is none, and the message is refused.
  _Table get _seats => _table ?? (throw const _Refused(Rejection.illegal));

  /// A move with no table: it names a hand that isn't there.
  Never _stale([int? turnId]) => throw _Refused(Rejection.stale, turnId: turnId);

  /// The host picks the room's game, in the lobby (see [ChooseGame]): the
  /// same game again changes only its rules (for the other games, the
  /// number of seats too: refused if fewer than are taken); another sends
  /// every seated member back to spectating, with a new table (Hold'em:
  /// empty seats with the host's Hold'em rules, no bots; another game: the
  /// setup's seats, empty).
  void _chooseGame(RoomPlayer p, ChooseGame m) {
    if (p.token != _hostToken) throw const _Refused(Rejection.notHost);
    if (phase != RoomPhase.lobby) throw const _Refused(Rejection.illegal);
    final _Game game;
    if (m.game == holdemKey) {
      if (m.setup != null) throw const _Refused(Rejection.illegal);
      game = _holdem;
    } else {
      final online = _games[m.game];
      if (online == null) throw const _Refused(Rejection.illegal);
      try {
        final setup = m.setup == null ? OnlineSetup.defaultFor(online) : OnlineSetup.fromJson(m.setup, online);
        game = (key: m.game, online: online, setup: setup);
      } on FormatException {
        throw const _Refused(Rejection.illegal);
      }
    }
    if (game.key == _game?.key) {
      if ((_table, game.setup) case (final _RunnerTable table, final setup?)) table.changeSetup(setup);
      _game = game;
      _sendRoom();
      return;
    }
    if (_table case final table?) {
      if (table.holdemSettings case final settings?) _holdemSettings = settings;
      table.close();
    }
    for (final q in _players.values) {
      q.seat = null;
      q.waiting = q.standing = q.sittingOut = q._satOutAway = q.removing = false;
    }
    _game = game;
    _table = switch (game) {
      (key: _, online: final online?, setup: final setup?) => _RunnerTable(this, online, setup),
      _ => _PokerTable(this, _holdemSettings, const {}),
    };
    _sendRoom();
    _watchIdle();
  }

  /// The host removes the member [id] (if still [name]): a spectator at
  /// once; a player at once, or while they play a hand (dealt in, not
  /// folded), when it ends.
  void _removePlayer(RoomPlayer p, int id, String name) {
    if (p.token != _hostToken) throw const _Refused(Rejection.notHost);
    final target = _players.values.where((q) => q.id == id).firstOrNull;
    if (target == null || target.token == _hostToken) throw const _Refused(Rejection.illegal);
    // They are going already (or the id was misread).
    if (target.name != name || target.left || target.removing) throw const _Refused(Rejection.stale);
    final table = _table;
    if (table != null && table.playsRound(target)) {
      target.removing = true;
      _sendRoom();
      return;
    }
    _expel(target);
    if (table != null) {
      table.afterRemoval();
    } else {
      _sendRoom();
    }
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
    final told = PlayerRemoved(id: q.id, name: q.name);
    for (final other in _players.values) {
      if (other.link != null) _send(other, told);
    }
  }

  /// A device's copy of the hand went wrong: it gets a fresh one (not too
  /// often).
  void _resync(RoomPlayer p) {
    final now = _clock.nowMs, last = p._lastResync;
    if (last != null && now - last < OnlineTiming.resyncGap.inMilliseconds) return;
    p._lastResync = now;
    _table?.resync(p);
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
    // A room where people chat isn't idle.
    _watchIdle();
  }

  /// The chat so far, to [p], who joined or came back.
  void _sendChat(RoomPlayer p) {
    if (_chat.isNotEmpty) _send(p, ChatLines([for (final said in _chat) _chatLine(said, p)], all: true));
  }

  ChatLine _chatLine(_Said said, RoomPlayer to) =>
      ChatLine(n: said.n, name: said.name, text: said.text, you: said.token == to.token);

  // ---------------------------------------------------------------------------
  // Closing
  // ---------------------------------------------------------------------------

  /// Ends the room: everyone is told why, and disconnected.
  void close(CloseReason reason) {
    if (_closed) return;
    _closed = true;
    _table?.close();
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

  /// Everyone gets the room as it is now: its members, the game (none until
  /// the host picks one) and its seats, with the host's changes for the
  /// next hand (styles only for the host and spectators, unless the host
  /// shows them to everyone), the Hold'em rules while it plays Hold'em, and
  /// the host's switches.
  void _sendRoom() {
    final table = _table, settings = table?.holdemSettings;
    final members = [
      for (final q in _players.values)
        if (!q.left)
          RoomMember(
            id: q.id,
            name: q.name,
            seat: q.seat,
            status: q.connected ? SeatStatus.connected : SeatStatus.away,
            waiting: q.waiting,
          ),
    ];
    final games = {holdemKey: holdemGv, for (final g in _games.values) g.key: g.gv};
    final withStyles = table?.seatInfos(showStyles: true) ?? const <SeatInfo>[];
    final withoutStyles = table?.seatInfos(showStyles: false) ?? const <SeatInfo>[];
    final game = _gameChoice;
    for (final p in _players.values) {
      if (p.link == null) continue;
      final showStyles = table == null || table.showsStylesTo(p);
      _send(
        p,
        RoomState(
          code: code,
          phase: phase,
          paused: isPaused,
          host: _players[_hostToken]?.id,
          you: p.id,
          cap: _cap,
          seeBots: _seeBots,
          games: games,
          game: game,
          settings: settings,
          members: members,
          seats: showStyles ? withStyles : withoutStyles,
        ),
      );
    }
  }

  /// Sends [text], a message encoded once for many (the spectators' copy).
  void _sendText(RoomPlayer p, String text) => p.link?.send(text);
}
