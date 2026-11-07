/// Drives a game's runner ([OnlineGame] / [GameRunner]) through a real
/// room on a clock the test moves, with raw devices that play by
/// themselves: the rooms step's tests use it with the fake High card game,
/// and each game agent's `<key>_runner_test.dart` with its own game.
///
/// What it checks while the rounds go (see [RunnerHarness.problems]):
/// - every view a seat is given holds no other seat's hidden data, and the
///   spectators' none of the bots' unless the round was dealt with the
///   host's switch on (the game says what is hidden: [RunnerHarness.secrets]);
/// - no view (a seat's, the spectators' with or without the switch, a bot's
///   turn) holds a card nobody may see yet: the rest of the deck, a kitty
///   before it is shown, a dealer's hole card, the shoe's next card (the
///   game says which: [RunnerHarness.undealt]; a card game must give it,
///   or such a leak goes unseen);
/// - the acting seat's view rebuilt from the spectators' view
///   ([RunnerHarness.seatViewFrom]) is exactly that seat's own view, and is
///   null for a hidden bot;
/// - every auto-move (time ran out, or the player is away) is legal;
/// - someone acts whenever the round isn't over;
/// - a seat in a round is only ever sent its own view; the bots' views go
///   only to the host's device;
/// - every message a device gets is under [RunnerHarness.maxBytes];
/// - no move the devices make is refused (unless a test sends one on
///   purpose: [HarnessDevice.rejected]).
///
/// And on demand: [RunnerHarness.expectJunkRefused] (junk sent at a seat's
/// turn is refused, one move at a time, and never closes the room).
///
/// And for one runner alone: [expectDealsFromRandom] (every deal draws from
/// the room's Random, never from a seed of its own) and
/// [expectMoveRoundTrips] (a move, the longest a game has, goes through the
/// game envelope unchanged).
library;

import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/online/clock.dart';
import 'package:pokerfection/src/online/games/game_envelope.dart';
import 'package:pokerfection/src/online/games/game_runner.dart';
import 'package:pokerfection/src/online/memory_link.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/server/hand_runner.dart' show HandRunner;
import 'package:pokerfection/src/server/room_registry.dart';

/// A legal move for hand seat [seat] seeing [seatView] (the game's own
/// choice: random, or a simple rule).
typedef PickMove = String Function(Map<String, Object?> seatView, int seat, Random random);

/// The strings in hand seat [seat]'s view that nobody else may see now (as
/// they appear in the JSON, e.g. a hidden card's code in quotes). Empty
/// once they are public.
typedef Secrets = Set<String> Function(Map<String, Object?> seatView, int seat);

/// The acting seat's view rebuilt from the spectators' (the game's view
/// codec); null when that seat's hidden data isn't in it.
typedef SeatViewFrom = Map<String, Object?>? Function(Map<String, Object?> spectatorView, int seat);

/// The strings (as in the JSON) that no seat and no spectator may see now,
/// read from the game's own runner ([runner]: what the game's newRunner
/// made, to cast to its type): cards not dealt to anyone, a kitty before
/// it is turned, a dealer's hole card. Empty once they are public.
typedef Undealt = Set<String> Function(GameRunner runner);

/// A Random that counts what is drawn from it.
class RecordingRandom implements Random {
  RecordingRandom(this._inner);
  final Random _inner;
  int draws = 0;

  @override
  int nextInt(int max) {
    draws++;
    return _inner.nextInt(max);
  }

  @override
  bool nextBool() {
    draws++;
    return _inner.nextBool();
  }

  @override
  double nextDouble() {
    draws++;
    return _inner.nextDouble();
  }
}

/// A room, its devices and the game, with the checks above.
class RunnerHarness {
  RunnerHarness(
    OnlineGame game, {
    required this.pick,
    this.secrets,
    this.seatViewFrom,
    this.undealt,
    int seed = 1,
    int roomCap = RoomRegistry.largeRoomCap,
    this.maxBytes = 12 * 1024,
  }) : random = RecordingRandom(Random(seed)),
       _moves = Random(seed + 1000) {
    spy = _SpyGame(game, this);
    registry = RoomRegistry(clock: clock, random: random, roomCap: roomCap, roomIdle: null, games: {game.key: spy});
  }

  final PickMove pick;
  final Secrets? secrets;
  final SeatViewFrom? seatViewFrom;
  final Undealt? undealt;

  /// The largest message (UTF-8 bytes) a device may get.
  final int maxBytes;

  final clock = ManualClock();

  /// The room's Random (every deal must draw from it).
  final RecordingRandom random;
  final Random _moves;
  late final RoomRegistry registry;
  late final OnlineGame spy;

  /// Every device still connected (the host's first, until it drops).
  final List<HarnessDevice> devices = [];

  /// What went wrong, as found (empty when all is well).
  final List<String> problems = [];

  /// The largest message any device got (bytes).
  int largest = 0;

  /// The runners made (one per game started), newest last.
  final List<SpyRunner> runners = [];

  /// The host's device (the latest, after it came back).
  HarnessDevice get host => _host!;
  HarnessDevice? _host;

  /// The game as the room sees it ([OnlineGame.key]).
  String get key => spy.key;

  HarnessDevice _connect(String name, {bool host = false}) {
    final (server, device) = MemoryLink.pair(address: name);
    registry.accept(server);
    final d = HarnessDevice._(this, name, device, isHost: host);
    devices.add(d);
    if (host) _host = d;
    return d;
  }

  /// [d]'s connection drops (the room hears it at once).
  Future<void> drop(HarnessDevice d) async {
    devices.remove(d);
    await d.link.close();
    await settle();
  }

  /// [name] comes back to room [code] with their [token] (the host's
  /// device too: then it is [host] again).
  Future<HarnessDevice> rejoin(String name, String code, String token, {bool host = false}) async {
    final d = _connect(name, host: host);
    d.send(RejoinRoom(code: code, token: token));
    await settle();
    return d;
  }

  Future<void> settle() async {
    for (var i = 0; i < 10; i++) {
      await pumpEventQueue();
    }
  }

  /// Lets time pass, timer by timer, until [done].
  Future<void> until(bool Function() done, String what, {int limit = 5000}) async {
    for (var tick = 0; ; tick++) {
      await settle();
      if (done()) return;
      expect(tick, lessThan(limit), reason: 'never: $what');
      for (final d in devices) {
        d.send(const Ping(0));
      }
      await settle();
      clock.fireNext();
    }
  }

  /// Lets [time] pass on the clock (devices say they are there).
  Future<void> pass(Duration time) async {
    const step = Duration(milliseconds: 250);
    for (var left = time; left > Duration.zero; left -= step) {
      for (final d in devices) {
        d.send(const Ping(0));
      }
      await settle();
      clock.advance(left < step ? left : step);
    }
    await settle();
  }

  /// The host opens a room with no game (as the app does).
  Future<HarnessDevice> open({String name = 'Ann'}) async {
    final host = _connect(name, host: true);
    host.send(CreateRoom(name: name));
    await settle();
    return host;
  }

  /// The host picks the game: [rules] (its defaults when null), [seats]
  /// (the game's first when null), [turnLimit] seconds per move.
  Future<void> choose({Map<String, Object?>? rules, int? seats, int turnLimit = 0}) async {
    final r = rules ?? spy.defaultRules;
    host.send(
      ChooseGame(game: key, setup: {'seats': seats ?? spy.seatsFor(r).first, 'turnLimit': turnLimit, 'rules': r}),
    );
    await settle();
  }

  /// [name] joins (a spectator), and takes a seat when [seated].
  Future<HarnessDevice> join(String name, {bool seated = false}) async {
    final d = _connect(name);
    d.send(JoinRoom(code: host.welcome.code, name: name, device: '$name-device'));
    if (seated) d.send(const TakeSeat());
    await settle();
    return d;
  }

  /// The host fills [count] seats with bots.
  Future<void> addBots(int count, {String level = 'easy'}) async {
    for (var i = 0; i < count; i++) {
      host.send(AddBot(style: level));
    }
    await settle();
  }

  Future<void> start() async {
    host.send(const StartGame());
    await settle();
  }

  /// Plays until the host's device has seen [count] more rounds end.
  Future<void> playRounds(int count) async {
    final target = host.roundsOver + count;
    await until(() => host.roundsOver >= target, '$count rounds');
  }

  /// Every check passed: no problem found, every message small enough,
  /// no move of the devices refused.
  void expectClean() {
    expect(problems, isEmpty);
    expect(largest, lessThanOrEqualTo(maxBytes));
    for (final d in devices) {
      expect(d.rejected, isEmpty, reason: '${d.name} had moves refused');
    }
  }

  /// Moves no game can read: empty, blanks, numbers too big, odd marks,
  /// JSON, the longest a move may be, and [random] strings of any length.
  List<String> junkMoves(int random) => [
    '',
    ' ',
    '-1',
    '99999999999999999999999',
    ':::',
    ',,,',
    '{"a":[1,2]}',
    'x' * maxMoveLength,
    for (var i = 0; i < random; i++)
      String.fromCharCodes([for (var j = _moves.nextInt(maxMoveLength + 1); j > 0; j--) 32 + _moves.nextInt(95)]),
  ];

  /// At [d]'s next [turns] turns, sends junk ([junkMoves]), one fewer than
  /// a turn takes before more are ignored: each must be refused as illegal,
  /// and nobody may hear the room close. Then [d] plays its own move (the
  /// junk's refusals are taken off [HarnessDevice.rejected] once checked).
  Future<void> expectJunkRefused(HarnessDevice d, {int turns = 4}) async {
    final junk = junkMoves(turns * (HandRunner.maxRejects - 1));
    var next = 0;
    d.autoPlay = false;
    for (var t = 0; t < turns; t++) {
      bool myTurn() {
        final s = d.state, turn = s?.turn;
        return s != null && turn != null && s.over == null && s.you == turn.seat;
      }

      await until(myTurn, "${d.name}'s turn");
      final turnId = d.state!.turn!.turnId;
      for (var i = 0; i < HandRunner.maxRejects - 1; i++) {
        final move = junk[next++ % junk.length];
        final before = d.rejected.length;
        d.play(move);
        await settle();
        expect(d.rejected.length, before + 1, reason: 'junk move "$move" was not refused');
        expect(d.rejected.last.reason, Rejection.illegal, reason: 'junk move "$move"');
        d.rejected.removeLast();
        for (final other in devices) {
          expect(other.all<Closing>(), isEmpty, reason: 'junk move "$move" closed the room');
        }
      }
      expect(d.state!.turn?.turnId, turnId, reason: 'junk moved the turn on');
      d.actNow();
      await until(() => d.state?.turn?.turnId != turnId || d.state?.over != null, "${d.name}'s move");
    }
    d.autoPlay = true;
  }

  void _problem(String what) {
    if (problems.length < 50) problems.add(what);
  }

  String _move(Map<String, Object?> view, int seat) => pick(view, seat, _moves);
}

/// A raw device in the room: keeps everything it gets, says Ready after
/// each round, plays its own turns ([autoPlay]) and, on the host's device,
/// the bots' ([autoBots]), with moves from [RunnerHarness.pick].
class HarnessDevice {
  HarnessDevice._(this.harness, this.name, this.link, {required this.isHost}) {
    link.messages.listen(_onText);
  }

  final RunnerHarness harness;
  final String name;
  final MemoryLink link;
  final bool isHost;

  /// Every message as it came (raw), and read.
  final List<String> texts = [];
  final List<ServerMessage> got = [];

  /// Rejected answers to this device's own moves.
  final List<Rejected> rejected = [];

  bool autoPlay = true;
  bool autoBots = true;

  /// Says Ready after each round (turned back on: at once, if the last
  /// round is over).
  bool get autoReady => _autoReady;
  set autoReady(bool on) {
    _autoReady = on;
    _maybeReady();
  }

  bool _autoReady = true;

  /// Rounds seen ending, and the moves this device sent.
  int roundsOver = 0;
  int movesSent = 0, botMovesSent = 0;
  int _readyFor = 0;

  Welcome get welcome => got.whereType<Welcome>().last;
  RoomState get room => got.whereType<RoomState>().last;
  int get id => welcome.id;

  /// The game messages this device got (states and bot requests).
  List<EnvelopeBody> get bodies => [
    for (final m in got)
      if (m is ServerGameMessage) m.body,
  ];
  List<EnvelopeState> get states => bodies.whereType<EnvelopeState>().toList();
  EnvelopeState? get state => states.lastOrNull;
  List<EnvelopeBotRequest> get botRequests => bodies.whereType<EnvelopeBotRequest>().toList();

  /// The member's room seat (not one only waited for).
  int? get seat => switch (got.whereType<RoomState>().lastOrNull?.me) {
    RoomMember(:final seat?, waiting: false) => seat,
    _ => null,
  };

  List<T> all<T>() => got.whereType<T>().toList();
  Rejection? get lastRejection => all<Rejected>().lastOrNull?.reason;

  void send(ClientMessage m) {
    if (!link.isClosed) link.send(m.encode());
  }

  /// Sends [body] as this game's message.
  void sendGame(EnvelopeBody body) => send(GameMessage(game: harness.key, gv: harness.spy.gv, body: body));

  /// Plays its own turn now, if it is open (after [autoPlay] was off).
  void actNow() {
    final s = state, turn = s?.turn;
    if (s == null || turn == null || s.over != null || s.you != turn.seat) return;
    movesSent++;
    sendGame(EnvelopeMove(round: s.round, turnId: turn.turnId, move: harness._move(s.view, turn.seat)));
  }

  /// Plays [move] at the open turn (whatever it is).
  void play(String move) {
    final s = state, turn = s?.turn;
    if (s == null || turn == null) return;
    sendGame(EnvelopeMove(round: s.round, turnId: turn.turnId, move: move));
  }

  void _onText(String text) {
    texts.add(text);
    final bytes = utf8.encode(text).length;
    if (bytes > harness.largest) harness.largest = bytes;
    if (bytes > harness.maxBytes) harness._problem('$name got a message of $bytes bytes: ${text.substring(0, 80)}…');
    final ServerMessage m;
    try {
      m = ServerMessage.decode(text);
    } on ProtocolError catch (e) {
      harness._problem('$name could not read $text: $e');
      return;
    }
    got.add(m);
    switch (m) {
      case Rejected():
        rejected.add(m);
      case ServerGameMessage(body: final EnvelopeState s):
        _onState(s);
      case ServerGameMessage(body: final EnvelopeBotRequest r):
        if (!isHost) harness._problem('$name (not the host) got a bot\'s turn');
        if (autoBots) {
          botMovesSent++;
          sendGame(
            EnvelopeBotMove(round: r.round, turnId: r.turnId, seat: r.seat, move: harness._move(r.view, r.seat)),
          );
        }
      case RoomState():
        _maybeReady();
      default:
        break;
    }
  }

  void _onState(EnvelopeState s) {
    // A seat in a round being played gets its own view, never the spectators'.
    final mine = seat;
    if (s.over == null && mine != null && s.seats.contains(mine)) {
      final at = s.seats.indexOf(mine);
      if (s.you != at) harness._problem('$name in hand seat $at got the view of ${s.you ?? 'the spectators'}');
    }
    if (s.you != null && (mine == null || s.seats[s.you!] != mine)) {
      harness._problem('$name (room seat $mine) got hand seat ${s.you}\'s view');
    }
    if (s.over != null) roundsOver++;
    _maybeReady();
    final turn = s.turn;
    if (autoPlay && s.over == null && turn != null && s.you == turn.seat) {
      movesSent++;
      sendGame(EnvelopeMove(round: s.round, turnId: turn.turnId, move: harness._move(s.view, turn.seat)));
    }
  }

  /// After a round's end, a seated member's device is ready for the next.
  void _maybeReady() {
    final s = state;
    if (!_autoReady || s == null || s.over == null || seat == null || _readyFor > s.round) return;
    _readyFor = s.round + 1;
    sendGame(EnvelopeReady(s.round + 1));
  }
}

/// The game as the room sees it: the real one, whose runners are watched.
class _SpyGame implements OnlineGame {
  _SpyGame(this._inner, this._harness);

  final OnlineGame _inner;
  final RunnerHarness _harness;

  @override
  String get key => _inner.key;
  @override
  int get gv => _inner.gv;
  @override
  Map<String, Object?> get defaultRules => _inner.defaultRules;
  @override
  Map<String, Object?> readRules(Object? json) => _inner.readRules(json);
  @override
  SeatRange seatsFor(Map<String, Object?> rules) => _inner.seatsFor(rules);
  @override
  List<String> get botLevels => _inner.botLevels;
  @override
  Duration get betweenRounds => _inner.betweenRounds;
  @override
  Duration get maxBetweenRounds => _inner.maxBetweenRounds;

  @override
  GameRunner newRunner(OnlineSetup setup, Random random) {
    if (!identical(random, _harness.random)) _harness._problem('a runner was not given the room\'s Random');
    final runner = SpyRunner(_inner.newRunner(setup, random), _harness);
    _harness.runners.add(runner);
    return runner;
  }
}

/// A runner, checked as the room uses it ([inner]: the game's own).
class SpyRunner implements GameRunner {
  SpyRunner(this.inner, this._h);

  final GameRunner inner;
  final RunnerHarness _h;
  List<bool> isBot = const [];

  /// What each deal drew from the room's Random.
  final List<int> dealDraws = [];

  /// Every move played, with its seat.
  final List<(int, String)> moves = [];

  @override
  void startRound(int round, List<bool> isBot) {
    this.isBot = isBot;
    final before = _h.random.draws;
    inner.startRound(round, isBot);
    dealDraws.add(_h.random.draws - before);
    _turnCheck('dealt');
  }

  void _turnCheck(String when) {
    if ((inner.seatToAct == null) != inner.roundOver) {
      _h._problem('$when: seatToAct ${inner.seatToAct} but roundOver ${inner.roundOver}');
    }
  }

  @override
  bool get roundOver => inner.roundOver;
  @override
  int? get seatToAct => inner.seatToAct;
  @override
  bool get redealt => inner.redealt;
  @override
  String? check(int seat, String move) => inner.check(seat, move);

  @override
  void act(int seat, String move) {
    inner.act(seat, move);
    moves.add((seat, move));
    _turnCheck('after $seat played $move');
  }

  @override
  String autoMove(int seat, {bool absent = false}) {
    final move = inner.autoMove(seat, absent: absent);
    if (inner.check(seat, move) case final reason?) _h._problem('autoMove($seat) = $move is refused: $reason');
    return move;
  }

  @override
  int playbackMs(String move) => inner.playbackMs(move);
  @override
  int get openingMs => inner.openingMs;

  Set<String> _secretsOf(int seat) => _h.secrets?.call(inner.seatView(seat), seat) ?? const {};

  /// A problem for each card nobody may see that is in [text] ([who]'s view).
  void _undealtCheck(String text, String who) {
    for (final secret in _h.undealt?.call(inner) ?? const <String>{}) {
      if (text.contains(secret)) _h._problem('$who holds $secret, which nobody may see yet: $text');
    }
  }

  @override
  Map<String, Object?> seatView(int seat) {
    final view = inner.seatView(seat);
    final text = jsonEncode(view);
    for (var other = 0; other < isBot.length; other++) {
      if (other == seat) continue;
      for (final secret in _secretsOf(other)) {
        if (text.contains(secret)) _h._problem('seat $seat\'s view holds seat $other\'s $secret: $text');
      }
    }
    _undealtCheck(text, 'seat $seat\'s view');
    return view;
  }

  @override
  Map<String, Object?> spectatorView({required bool seesBots}) {
    final view = inner.spectatorView(seesBots: seesBots);
    final text = jsonEncode(view);
    _undealtCheck(text, 'the spectators\' view${seesBots ? ' (bots shown)' : ''}');
    for (var s = 0; s < isBot.length; s++) {
      final hidden = isBot[s] && !seesBots;
      final secrets = _secretsOf(s);
      if (hidden) {
        for (final secret in secrets) {
          if (text.contains(secret)) _h._problem('the spectators\' view holds bot seat $s\'s $secret: $text');
        }
      }
      final from = _h.seatViewFrom;
      if (from == null) continue;
      final rebuilt = from(view, s);
      if (hidden && secrets.isNotEmpty) {
        if (rebuilt != null) _h._problem('seat $s (a hidden bot) rebuilt from the spectators\' view');
      } else if (jsonEncode(rebuilt) != jsonEncode(inner.seatView(s))) {
        _h._problem(
          'seat $s rebuilt from the spectators\' view: ${jsonEncode(rebuilt)}\n'
          'its own: ${jsonEncode(inner.seatView(s))}',
        );
      }
    }
    return view;
  }

  @override
  Map<String, Object?> roundResult() => inner.roundResult();
  @override
  List<num> get roundScores => inner.roundScores;
}

/// Every deal of [game]'s runner draws from the Random it was given, and
/// from nothing else: deals draw from it; two runners on equal Randoms deal
/// the same views; other Randoms deal other views (over [rounds] rounds).
/// [isBot]: the lineup to deal to.
void expectDealsFromRandom(OnlineGame game, OnlineSetup setup, List<bool> isBot, {int rounds = 20}) {
  final recording = RecordingRandom(Random(11));
  final runner = game.newRunner(setup, recording);
  runner.startRound(1, isBot);
  expect(recording.draws, greaterThan(0), reason: 'the deal draws from the room\'s Random');
  List<String> deals(int seed) {
    final r = game.newRunner(setup, Random(seed));
    return [
      for (var round = 1; round <= rounds; round++) ...[
        (() {
          r.startRound(round, isBot);
          return jsonEncode([for (var s = 0; s < isBot.length; s++) r.seatView(s)]);
        })(),
      ],
    ];
  }

  expect(deals(5), deals(5), reason: 'the same Random deals the same');
  expect(deals(5), isNot(deals(6)), reason: 'another Random deals otherwise');
}

/// [move] (and as a bot's move, for hand seat [seat]) goes through the game
/// envelope both ways unchanged.
void expectMoveRoundTrips(OnlineGame game, String move, {int seat = 0}) {
  final moved = ClientMessage.decode(
    GameMessage(
      game: game.key,
      gv: game.gv,
      body: EnvelopeMove(round: 9, turnId: 99, move: move),
    ).encode(),
  );
  expect(((moved as GameMessage).body as EnvelopeMove).move, move);
  final bot = ClientMessage.decode(
    GameMessage(
      game: game.key,
      gv: game.gv,
      body: EnvelopeBotMove(round: 9, turnId: 99, seat: seat, move: move),
    ).encode(),
  );
  expect(((bot as GameMessage).body as EnvelopeBotMove).move, move);
  expect(move.length, lessThanOrEqualTo(maxMoveLength));
}
