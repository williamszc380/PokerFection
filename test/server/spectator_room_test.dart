import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/engine/actions.dart';
import 'package:pokerfection/src/engine/events.dart';
import 'package:pokerfection/src/engine/rules.dart';
import 'package:pokerfection/src/online/clock.dart';
import 'package:pokerfection/src/online/games/game_envelope.dart';
import 'package:pokerfection/src/online/games/game_runner.dart';
import 'package:pokerfection/src/online/games/online_games.dart';
import 'package:pokerfection/src/online/memory_link.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/online/timing.dart';
import 'package:pokerfection/src/server/room_registry.dart';

/// A member's device, as simple as can be: it keeps every message, says
/// Ready to each hand announced ([autoReady]), and checks or calls at its
/// turns ([policy]) in the hands it plays ([playsIn]); the host's device
/// also for the bots ([playsBots]).
class _Member {
  _Member(this.name, this.link) {
    link.messages.listen((text) {
      final m = ServerMessage.decode(text);
      texts.add(text);
      got.add(m);
      _on(m);
    });
  }

  final String name;
  final MemoryLink link;
  final List<ServerMessage> got = [];
  final List<String> texts = [];
  bool autoReady = true, playsBots = false;
  bool Function(int hand) playsIn = (_) => true;
  PlayerAction Function(Turn turn) policy = (turn) =>
      turn.toCall == 0 ? const PlayerAction.check() : const PlayerAction.call();

  /// Each hand as last announced to this device (or caught up with), and
  /// as it was when dealt.
  final Map<int, NextHand> lineups = {}, dealtAs = {};
  (int, Turn)? lastTurn;

  void send(ClientMessage m) {
    if (!link.isClosed) link.send(m.encode());
  }

  Welcome get welcome => got.whereType<Welcome>().last;
  int get id => welcome.id;
  RoomState get room => got.whereType<RoomState>().last;
  int? get seat => room.yourSeat;
  List<T> all<T>() => got.whereType<T>().toList();
  Rejection? get lastRejection => all<Rejected>().lastOrNull?.reason;

  /// The hole cards dealt to this device in [hand], by hand seat.
  Map<int, Object> cardsIn(int hand) =>
      all<HandDealt>().singleWhere((d) => d.hand == hand).batch.whereType<HoleCardsDealt>().single.cards;

  void _on(ServerMessage m) {
    switch (m) {
      case NextHand():
        lineups[m.hand] = m;
        if (autoReady) send(Ready(m.hand));
      case Snapshot(:final hand, :final next):
        if (hand != null) lineups[hand.hand] = dealtAs[hand.hand] = hand.lineup;
        if (next != null) {
          lineups[next.hand] = next;
          if (autoReady) send(Ready(next.hand));
        }
        if (hand != null) _turn(hand.hand, hand.turn);
      case HandDealt(:final hand, :final turn):
        dealtAs[hand] = lineups[hand]!;
        _turn(hand, turn);
      case HandEvents(:final hand, :final turn):
        _turn(hand, turn);
      default:
        break;
    }
  }

  void _turn(int hand, Turn? turn) {
    lastTurn = turn == null ? null : (hand, turn);
    if (turn == null || !playsIn(hand)) return;
    final lineup = lineups[hand];
    if (lineup == null) return;
    if (turn.seat == lineup.you) {
      send(Act(hand: hand, turnId: turn.turnId, action: policy(turn)));
    } else if (playsBots && lineup.seats[turn.seat].kind == SeatKind.bot) {
      send(BotAct(hand: hand, turnId: turn.turnId, seat: turn.seat, action: policy(turn)));
    }
  }

  /// Plays the open turn now (after [playsIn] changed).
  void actNow() {
    if (lastTurn case (final hand, final turn)) _turn(hand, turn);
  }

  /// Whether a hand is being played here: dealt, its turn open.
  bool get midHand => lastTurn != null;

  /// The last hand announced is not dealt yet (between hands).
  bool get betweenHands =>
      got.lastWhere((m) => m is NextHand || m is HandDealt, orElse: () => const Pong(0)) is NextHand;
}

/// A room on a clock the test moves, with raw devices.
class _Harness {
  _Harness({int cap = RoomRegistry.largeRoomCap, Map<String, OnlineGame>? games, Random? random}) {
    registry = RoomRegistry(clock: clock, random: random ?? Random(7), roomCap: cap, games: games);
  }

  final clock = ManualClock();
  late final RoomRegistry registry;
  final List<_Member> members = [];

  _Member connect(String name) {
    final (server, device) = MemoryLink.pair(address: name);
    registry.accept(server);
    final m = _Member(name, device);
    members.add(m);
    return m;
  }

  Future<void> settle() async {
    for (var i = 0; i < 10; i++) {
      await pumpEventQueue();
    }
  }

  /// Lets time pass (timer by timer) until [done].
  Future<void> until(bool Function() done, String what) async {
    for (var tick = 0; ; tick++) {
      await settle();
      if (done()) return;
      expect(tick, lessThan(3000), reason: 'never: $what');
      for (final m in members) {
        m.send(const Ping(0));
      }
      await settle();
      clock.fireNext();
    }
  }

  Future<_Member> create({
    RoomSettings settings = const RoomSettings(seats: 3, stackBb: 20, resetStacks: true),
    Map<int, String> bots = const {},
    bool seated = true,
  }) async {
    final host = connect('Ann')..playsBots = true;
    host.send(CreateRoom(name: 'Ann', game: holdemKey, settings: settings, bots: bots));
    if (seated) host.send(const TakeSeat());
    await settle();
    return host;
  }

  Future<_Member> join(String name, _Member host, {String? device, bool seated = false}) async {
    final m = connect(name);
    m.send(JoinRoom(code: host.welcome.code, name: name, device: device));
    if (seated) m.send(const TakeSeat());
    await settle();
    return m;
  }

  /// The first answer to [opening] on a new connection.
  Future<ServerMessage> answer(String opening) async {
    final (server, device) = MemoryLink.pair(address: 'other');
    registry.accept(server);
    final answers = <ServerMessage>[];
    device.messages.listen((text) => answers.add(ServerMessage.decode(text)));
    device.send(opening);
    await settle();
    return answers.first;
  }
}

/// The hand seats of [lineup] a spectator sees: the people's, and the bots'
/// with [bots].
List<int> _visible(NextHand lineup, {bool bots = false}) => [
  for (final (i, s) in lineup.seats.indexed)
    if (s.kind == SeatKind.human || bots) i,
];

/// A Random that counts what is drawn from it.
class _Counting implements Random {
  _Counting(this._inner);
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

/// Gomoku as a stand-in for any game other than Hold'em (no runner: R4).
class _FakeGame implements OnlineGame {
  @override
  String get key => 'gomoku';
  @override
  int get gv => 1;
  @override
  Map<String, Object?> get defaultRules => const {};
  @override
  Map<String, Object?> readRules(Object? json) =>
      json is Map && json.isEmpty ? const {} : throw const FormatException('No such rules');
  @override
  SeatRange seatsFor(Map<String, Object?> rules) => const SeatRange(2, 2);
  @override
  List<String> get botLevels => botLevelNames;
  @override
  Duration get betweenRounds => const Duration(seconds: 5);
  @override
  Duration get maxBetweenRounds => const Duration(seconds: 15);
  @override
  GameRunner newRunner(OnlineSetup setup, Random random) => throw UnimplementedError('R4');
}

void main() {
  test(
    'everyone enters as a spectator, the host too; spectators see the play styles, players only when shown',
    () async {
      final h = _Harness();
      final host = await h.create(bots: {0: 'tag'}, seated: false);
      expect(host.welcome.isHost, isTrue);
      final room = host.room;
      expect(room.members.map((m) => (m.id, m.name, m.seat)), [(host.id, 'Ann', null)]);
      expect((room.host, room.you, room.cap, room.seeBots, room.game!.key), (host.id, host.id, 16, false, holdemKey));
      expect(
        room.games,
        {holdemKey: holdemGv, for (final g in onlineGames.values) g.key: g.gv},
        reason: "the room runs Hold'em and every game in the online registry, each at its version",
      );
      expect(room.seats[0].kind, SeatKind.bot, reason: 'any seat may hold a bot, seat 0 too');

      final ben = await h.join('Ben', host);
      expect(ben.id, isNot(host.id));
      expect(ben.welcome.isHost, isFalse);
      expect(ben.room.members.map((m) => (m.name, m.seat)), [('Ann', null), ('Ben', null)]);
      expect(ben.room.seats[0].style, 'tag', reason: 'spectators see the styles');
      ben.send(const TakeSeat());
      await h.settle();
      expect(ben.seat, 1, reason: 'the first free seat');
      expect(ben.room.seats[1].member, ben.id);
      expect(ben.room.seats[0].style, isNull, reason: 'players see them only when the host shows them');
      expect(host.room.members.map((m) => (m.name, m.seat)), [('Ann', null), ('Ben', 1)]);
    },
  );

  test('in the lobby TakeSeat and LeaveSeat count at once; one seat each; a bot gives way to a person, never a '
      'person', () async {
    final h = _Harness();
    final host = await h.create(settings: const RoomSettings(seats: 2), bots: {0: 'tag', 1: 'nit'}, seated: false);
    final ben = await h.join('Ben', host);
    ben.send(const TakeSeat(0));
    await h.settle();
    expect(ben.seat, 0);
    expect(ben.room.seats.map((s) => s.kind), [SeatKind.human, SeatKind.bot]);
    ben.send(const TakeSeat());
    await h.settle();
    expect(ben.lastRejection, Rejection.illegal, reason: 'one seat each');
    ben.send(const LeaveSeat());
    await h.settle();
    expect(ben.seat, isNull);
    expect(ben.room.seats[0].isEmpty, isTrue, reason: 'the bot that gave way is gone');
    ben.send(const LeaveSeat());
    await h.settle();
    expect(ben.lastRejection, Rejection.illegal);

    // Every seat held: by a bot, it gives way (the highest one); by people, nobody gets in.
    host.send(const TakeSeat());
    await h.settle();
    expect(host.seat, 0);
    ben.send(const TakeSeat());
    await h.settle();
    expect(ben.seat, 1);
    expect(ben.room.seats.map((s) => s.kind), [SeatKind.human, SeatKind.human]);
    final cy = await h.join('Cy', host);
    cy.send(const TakeSeat());
    await h.settle();
    expect((cy.seat, cy.lastRejection), (null, Rejection.illegal));
  });

  test(
    'between hands a seat change counts for the very next hand: announced again within the same deal times',
    () async {
      final h = _Harness();
      final host = await h.create(bots: {2: 'tag'});
      final ben = await h.join('Ben', host);
      host.send(const StartGame());
      await h.until(() => host.all<NextHand>().length >= 2 && host.betweenHands, 'the next hand announced');
      final announced = host.all<NextHand>().last;
      expect(announced.seats.map((s) => s.seat), [0, 2]);

      ben.send(const TakeSeat());
      await h.settle();
      final again = host.all<NextHand>().last;
      expect(again.hand, announced.hand, reason: 'the same hand');
      expect(again.seats.map((s) => s.seat), [0, 1, 2]);
      expect((again.minWaitMs, again.maxWaitMs), (announced.minWaitMs, announced.maxWaitMs), reason: 'no time passed');
      expect(ben.lineups[again.hand]!.you, isNotNull);
      await h.until(() => ben.dealtAs.containsKey(again.hand), 'the hand dealt');
      expect(ben.cardsIn(again.hand).keys, [ben.dealtAs[again.hand]!.you], reason: 'only his own cards');

      // Leaving between hands counts at once too.
      await h.until(() => host.betweenHands && host.all<NextHand>().last.hand > again.hand, 'the next one announced');
      final next = host.all<NextHand>().last;
      ben.send(const LeaveSeat());
      await h.settle();
      expect(host.all<NextHand>().last.hand, next.hand);
      expect(host.all<NextHand>().last.seats.map((s) => s.seat), [0, 2]);
      expect(ben.seat, isNull);
    },
  );

  test('mid-hand a seat change waits for the hand to end, with badges: a spectator who watched hand N plays N+1 at '
      'the earliest; a player who leaves plays the hand out, and their seat goes to the one waiting', () async {
    final h = _Harness();
    final host = await h.create(bots: {2: 'tag'});
    final ben = await h.join('Ben', host, seated: true);
    final cy = await h.join('Cy', host);
    // Ben's turns wait in the first hand, until the test lets him play.
    ben.playsIn = (hand) => hand != 1;
    host.send(const StartGame());
    await h.until(() => ben.midHand && ben.lastTurn!.$2.seat == ben.lineups[1]!.you, "Ben's turn");
    expect(cy.lineups[1]!.you, isNull);
    expect(cy.cardsIn(1).keys, _visible(cy.dealtAs[1]!), reason: "the people's cards, not the bot's");

    ben.send(const LeaveSeat());
    await h.settle();
    expect(ben.seat, 1, reason: 'still seated: he plays the hand out');
    expect(host.room.seats[1].leaving, isTrue);
    cy.send(const TakeSeat());
    await h.settle();
    final waiting = host.room.members.singleWhere((m) => m.id == cy.id);
    expect((waiting.seat, waiting.waiting), (1, true), reason: 'the seat Ben leaves');
    expect(host.room.seats[1].joining, 'Cy');

    ben.playsIn = (_) => true;
    ben.actNow();
    await h.until(() => cy.dealtAs.containsKey(2), 'the next hand dealt');
    expect(host.all<Rejected>(), isEmpty);
    final lineup = cy.dealtAs[2]!;
    expect(lineup.seats.map((s) => (s.seat, s.name)), containsAll([(1, 'Cy')]));
    expect(cy.cardsIn(2).keys, [lineup.you]);
    expect((ben.seat, ben.lineups[2]!.you), (null, null), reason: 'Ben spectates now');
    expect(ben.cardsIn(2).keys, _visible(lineup));
    // Every hand a member was dealt in, they saw only their own cards.
    for (final m in [host, ben, cy]) {
      for (final MapEntry(key: hand, value: lineup) in m.dealtAs.entries) {
        if (lineup.you case final you?) expect(m.cardsIn(hand).keys, [you], reason: '${m.name}, hand $hand');
      }
    }
  });

  test(
    'with every seat a bot a person still gets in: mid-hand the bot leaves at its end, between hands at once',
    () async {
      final h = _Harness();
      final host = await h.create(
        settings: const RoomSettings(seats: 2, stackBb: 20, resetStacks: true),
        bots: {0: 'tag', 1: 'nit'},
        seated: false,
      );
      final ben = await h.join('Ben', host);
      final cy = await h.join('Cy', host);
      host.playsIn = (hand) => hand != 1;
      host.send(const StartGame());
      await h.until(() => host.midHand, 'a hand of bots');

      ben.send(const TakeSeat());
      await h.settle();
      expect(ben.room.seats[1].leaving, isTrue, reason: 'the bot leaves next hand');
      expect(ben.room.seats[1].joining, 'Ben');
      expect(ben.room.me!.waiting, isTrue);
      host.playsIn = (_) => true;
      host.actNow();
      await h.until(() => host.all<NextHand>().length >= 2 && host.betweenHands, 'the next hand announced');
      expect(host.all<NextHand>().last.seats.map((s) => s.kind), [SeatKind.bot, SeatKind.human]);

      cy.send(const TakeSeat());
      await h.settle();
      expect(host.all<NextHand>().last.seats.map((s) => (s.kind, s.name)), [
        (SeatKind.human, 'Cy'),
        (SeatKind.human, 'Ben'),
      ]);
      expect(cy.seat, 0);
    },
  );

  test(
    "spectators see every person's cards, the bots' only with the host's switch, from the next hand; one joining "
    "mid-hand gets a snapshot with that hand's visibility; seats see only their own; BotCards go to the host only",
    () async {
      final h = _Harness();
      final host = await h.create(bots: {2: 'tag'});
      final ben = await h.join('Ben', host, seated: true);
      final cy = await h.join('Cy', host);
      ben.playsIn = (hand) => hand != 1;
      host.send(const StartGame());
      await h.until(() => cy.dealtAs.containsKey(1) && ben.midHand, 'a hand');
      expect(cy.cardsIn(1).keys, _visible(cy.dealtAs[1]!));

      // On mid-hand: from the next hand. One joining now sees this hand as it was dealt.
      host.send(const HostSettings(seeBots: true));
      await h.settle();
      expect(cy.room.seeBots, isTrue);
      final dee = await h.join('Dee', host);
      final caughtUp = dee.all<Snapshot>().single.hand!;
      expect(caughtUp.lineup.you, isNull);
      expect(caughtUp.botCards, isEmpty);
      expect(caughtUp.batches.first.whereType<HoleCardsDealt>().single.cards.keys, _visible(caughtUp.lineup));

      ben.playsIn = (hand) => hand != 2;
      ben.actNow();
      await h.until(() => cy.dealtAs.containsKey(2) && ben.midHand && ben.lastTurn!.$1 == 2, 'the next hand');
      expect(cy.cardsIn(2).keys, _visible(cy.dealtAs[2]!, bots: true));
      expect(dee.cardsIn(2).keys, _visible(dee.dealtAs[2]!, bots: true), reason: 'the same for every spectator');
      expect(
        cy.texts.lastWhere((t) => t.startsWith('{"t":"hand"')),
        dee.texts.lastWhere((t) => t.startsWith('{"t":"hand"')),
      );

      // Off mid-hand: this hand stays as dealt, for one joining now too.
      host.send(const HostSettings(seeBots: false));
      await h.settle();
      final eve = await h.join('Eve', host);
      final hand2 = eve.all<Snapshot>().single.hand!;
      expect(hand2.batches.first.whereType<HoleCardsDealt>().single.cards.keys, _visible(hand2.lineup, bots: true));
      ben.playsIn = (_) => true;
      ben.actNow();
      await h.until(() => cy.dealtAs.containsKey(3), 'the hand after');
      expect(cy.cardsIn(3).keys, _visible(cy.dealtAs[3]!));

      // Seats: their own cards only; the bots' go to the host's device alone.
      for (final m in [host, ben]) {
        for (final MapEntry(key: hand, value: lineup) in m.dealtAs.entries) {
          expect(m.cardsIn(hand).keys, [lineup.you], reason: '${m.name}, hand $hand');
        }
      }
      expect(host.all<BotCards>(), isNotEmpty);
      for (final m in [ben, cy, dee, eve]) {
        expect(m.all<BotCards>(), isEmpty);
      }
      expect(host.all<Rejected>(), isEmpty);
    },
  );

  test("the host watching with a GTO bot: the deal waits for the host's Ready (its device solves first), 10 s at "
      'most; without one, it does not', () async {
    for (final gto in [true, false]) {
      final h = _Harness();
      final host = await h.create(bots: {0: gto ? 'gto' : 'nit', 1: 'tag'}, seated: false)
        ..autoReady = false;
      final ben = await h.join('Ben', host, seated: true);
      host.send(const StartGame());
      await h.settle();
      final first = host.all<NextHand>().first;
      expect(first.you, isNull);
      expect(ben.dealtAs, gto ? isEmpty : isNotEmpty, reason: 'Ben is ready (gto: $gto)');
      if (!gto) continue;
      h.clock.advance(const Duration(seconds: 9));
      await h.settle();
      expect(ben.dealtAs, isEmpty, reason: "the host hasn't solved yet");
      host.send(Ready(first.hand));
      await h.settle();
      expect(ben.dealtAs.keys, [first.hand]);

      // The host never says Ready: dealt at the latest, 10 s after the earliest.
      await h.until(() => host.all<NextHand>().length >= 2, 'the next hand announced');
      final next = host.all<NextHand>().last;
      final announcedAt = h.clock.nowMs;
      expect(next.maxWaitMs - next.minWaitMs, OnlineTiming.readyWaitWithHelp.inMilliseconds);
      await h.until(() => ben.dealtAs.containsKey(next.hand), 'dealt anyway');
      expect(h.clock.nowMs - announcedAt, next.maxWaitMs);
    }
  });

  test(
    "every deal is shuffled straight from the room's Random (Random.secure() on a real host), never from a seed",
    () async {
      final random = _Counting(Random(3));
      final h = _Harness(random: random);
      final host = await h.create(bots: {1: 'tag'});
      final before = random.draws;
      host.send(const StartGame());
      await h.until(() => host.dealtAs.isNotEmpty, 'the hand dealt');
      expect(random.draws - before, greaterThanOrEqualTo(51), reason: 'one draw per card shuffled');
    },
  );

  test('the room takes as many members as its host allows (bots do not count): one more gets roomFull', () async {
    final h = _Harness(cap: RoomRegistry.smallRoomCap);
    final host = await h.create(
      settings: const RoomSettings(seats: 8),
      bots: {for (var s = 0; s < 8; s++) s: 'tag'},
      seated: false,
    );
    final guests = [for (var i = 1; i < 8; i++) await h.join('P$i', host)];
    expect(guests.every((g) => g.got.whereType<Welcome>().isNotEmpty), isTrue);
    expect(host.room.members, hasLength(8));
    expect(host.room.cap, 8);
    final code = host.welcome.code;
    final full = await h.answer(JoinRoom(code: code, name: 'Nine').encode());
    expect(full, isA<ServerError>().having((e) => e.code, 'code', JoinError.roomFull));
    expect(jsonDecode(const ServerError(JoinError.roomFull).encode()), {'t': 'error', 'code': 'roomFull'});
    guests.last.send(const Leave());
    await h.settle();
    expect(await h.answer(JoinRoom(code: code, name: 'Nine').encode()), isA<Welcome>());
  });

  test('the host removes a spectator at once and a player mid-hand once the hand ends; neither gets back in', () async {
    final h = _Harness();
    final host = await h.create(bots: {2: 'tag'});
    final ben = await h.join('Ben', host, seated: true, device: 'ben-phone');
    final cy = await h.join('Cy', host, device: 'cy-phone');
    ben.playsIn = (hand) => hand != 1;
    host.send(const StartGame());
    await h.until(() => ben.midHand && ben.lastTurn!.$2.seat == ben.lineups[1]!.you, "Ben's turn");

    ben.send(RemoveMember(id: cy.id, name: 'Cy'));
    await h.settle();
    expect(ben.lastRejection, Rejection.notHost);
    host.send(RemoveMember(id: host.id, name: 'Ann'));
    await h.settle();
    expect(host.lastRejection, Rejection.illegal);
    host.send(RemoveMember(id: cy.id, name: 'Someone'));
    await h.settle();
    expect(host.lastRejection, Rejection.stale);

    host.send(RemoveMember(id: cy.id, name: 'Cy'));
    await h.settle();
    expect(cy.all<Closing>().single.reason, CloseReason.removed);
    expect(ben.all<PlayerRemoved>().single.id, cy.id);
    expect(host.room.members.map((m) => m.name), ['Ann', 'Ben']);

    host.send(RemoveMember(id: ben.id, name: 'Ben'));
    await h.settle();
    expect(ben.all<Closing>(), isEmpty, reason: 'he plays the hand out');
    expect(host.room.seats[1].leaving, isTrue);
    ben.playsIn = (_) => true;
    ben.actNow();
    await h.until(() => ben.all<Closing>().isNotEmpty, 'Ben gone');
    expect(host.room.seats[1].isEmpty, isTrue);

    final code = host.welcome.code;
    final refused = isA<ServerError>().having((e) => e.code, 'code', JoinError.removed);
    for (final (who, device) in [(cy, 'cy-phone'), (ben, 'ben-phone')]) {
      expect(await h.answer(RejoinRoom(code: code, token: who.welcome.token).encode()), refused);
      expect(await h.answer(JoinRoom(code: code, name: who.name, device: device).encode()), refused);
    }
    expect(await h.answer(JoinRoom(code: code, name: 'Dee', device: 'dee-phone').encode()), isA<Welcome>());
  });

  test('the host picks the game in the lobby only: another game sends everyone back to spectating; games the room '
      "can't play and a setup that isn't one are refused", () async {
    final h = _Harness(games: {'gomoku': _FakeGame()});
    final host = await h.create(bots: {2: 'tag'});
    final ben = await h.join('Ben', host, seated: true);
    expect(host.room.games, {holdemKey: holdemGv, 'gomoku': 1});

    ben.send(const ChooseGame(game: 'gomoku', setup: {'seats': 2, 'rules': {}}));
    await h.settle();
    expect(ben.lastRejection, Rejection.notHost);
    for (final refused in [
      const ChooseGame(game: 'big_two'),
      const ChooseGame(game: holdemKey, setup: {}),
      const ChooseGame(game: 'gomoku', setup: {'seats': 5, 'rules': {}}),
      const ChooseGame(
        game: 'gomoku',
        setup: {
          'seats': 2,
          'rules': {'size': 15},
        },
      ),
      const ChooseGame(game: 'gomoku', setup: {'seats': 2, 'turnLimit': 7, 'rules': {}}),
    ]) {
      host.got.clear();
      host.send(refused);
      await h.settle();
      expect(host.lastRejection, Rejection.illegal, reason: refused.encode());
    }
    host.link.send('{"t":"chooseGame","game":"chess"}');
    await h.settle();
    expect(host.lastRejection, Rejection.badMessage);

    host.send(const ChooseGame(game: 'gomoku', setup: {'seats': 2, 'turnLimit': 30, 'rules': {}}));
    await h.settle();
    final room = ben.room;
    expect((room.game!.key, room.game!.gv), ('gomoku', 1));
    expect(room.game!.setup, {'seats': 2, 'turnLimit': 30, 'rules': {}});
    expect(room.members.map((m) => m.seat), [null, null]);
    expect(room.seats.map((s) => s.kind), [SeatKind.empty, SeatKind.empty]);
    // Its own table (the runner's, R4): in the lobby a seat is taken at once, and no move is for a round of it.
    ben.send(const TakeSeat());
    ben.send(
      const GameMessage(
        game: 'gomoku',
        gv: 1,
        body: EnvelopeMove(round: 1, turnId: 1, move: 'h8'),
      ),
    );
    await h.settle();
    expect(ben.room.members.map((m) => m.seat), [null, 0]);
    expect(ben.lastRejection, Rejection.stale);

    host.send(const ChooseGame(game: holdemKey));
    await h.settle();
    expect(ben.room.game!.key, holdemKey);
    expect(ben.room.seats.map((s) => s.kind), everyElement(SeatKind.empty), reason: 'a new table, no bots');
    host.send(const TakeSeat());
    ben.send(const TakeSeat());
    await h.settle();
    host.send(const StartGame());
    await h.settle();
    expect(host.room.phase, RoomPhase.playing);
    host.send(const ChooseGame(game: 'gomoku'));
    await h.settle();
    expect(host.lastRejection, Rejection.illegal, reason: 'not during a game');
  });

  test('the host ends the game: between hands at once; during a hand once it ends', () async {
    final h = _Harness();
    final host = await h.create(bots: {1: 'tag'});
    final ben = await h.join('Ben', host);
    host.send(const EndGame());
    await h.settle();
    expect(host.lastRejection, Rejection.illegal, reason: 'no game yet');
    host.playsIn = (hand) => hand != 1;
    host.send(const StartGame());
    await h.until(() => host.midHand, 'a hand');
    ben.send(const EndGame());
    host.send(const EndGame());
    await h.settle();
    expect(ben.lastRejection, Rejection.notHost);
    expect(host.all<GameOver>(), isEmpty, reason: 'the hand goes on');
    host.playsIn = (_) => true;
    host.actNow();
    await h.until(() => host.all<GameOver>().isNotEmpty, 'game over');
    expect(host.all<GameOver>().single.seat, isNull);
    expect(ben.all<GameOver>(), hasLength(1), reason: 'spectators are told too');
    expect(host.room.phase, RoomPhase.lobby);
    expect(host.all<NextHand>(), hasLength(1), reason: 'no hand after it');

    host.autoReady = false;
    host.send(const StartGame());
    await h.settle();
    expect(host.betweenHands, isTrue);
    host.send(const EndGame());
    await h.settle();
    expect(host.all<GameOver>(), hasLength(2));
    expect(host.room.phase, RoomPhase.lobby);
  });

  test("an older app's first message gets upgrade before it is read; v8's first messages keep every field v7 "
      'requires', () async {
    final h = _Harness();
    final host = await h.create();
    final code = host.welcome.code;
    final upgrade = isA<ServerError>().having((e) => e.code, 'code', JoinError.upgrade);
    const v7Settings =
        '{"seats":8,"stackBb":100,"ante":0,"raiseRule":"standard","resetStacks":false,'
        '"rebuys":false,"help":"none","turnLimit":0,"showStyles":false,"showCards":true}';
    for (final opening in [
      '{"t":"join","v":7,"rules":$rulesVersion,"code":"$code","name":"Old"}',
      '{"t":"rejoin","v":7,"rules":$rulesVersion,"code":"$code","token":"abc"}',
      '{"t":"rejoin","v":7,"rules":$rulesVersion,"code":"$code","proof":"abc"}',
      '{"t":"create","v":7,"rules":$rulesVersion,"name":"Old","settings":$v7Settings}',
      // A newer app, whatever else its message holds.
      '{"t":"join","v":9}',
      '{"t":"join","v":$protocolVersion,"rules":${rulesVersion + 1},"code":"$code","name":"Odd"}',
    ]) {
      expect(await h.answer(opening), upgrade, reason: opening);
    }

    // What a v7 host reads strictly (a frozen list of v7's required keys), so it answers upgrade rather than
    // badMessage.
    void expectKeys(Object? json, Map<String, Matcher> keys) {
      expect(json, isA<Map<String, Object?>>());
      for (final MapEntry(:key, value: matcher) in keys.entries) {
        expect((json as Map)[key], matcher, reason: key);
      }
    }

    final text = isA<String>(), number = isA<int>(), flag = isA<bool>();
    final create = jsonDecode(const CreateRoom(name: 'Ann', game: holdemKey, bots: {0: 'gto'}).encode());
    expectKeys(create, {'t': text, 'v': number, 'rules': number, 'name': text, 'settings': isA<Map>()});
    expectKeys(create['settings'], {
      'seats': number,
      'stackBb': number,
      'ante': number,
      'raiseRule': text,
      'resetStacks': flag,
      'rebuys': flag,
      'help': text,
      'turnLimit': number,
      'showStyles': flag,
      'showCards': isFalse,
    });
    expectKeys(jsonDecode(const JoinRoom(code: 'K7M2Q', name: 'Ben', device: 'd').encode()), {
      't': text,
      'v': number,
      'rules': number,
      'code': text,
      'name': text,
    });
    expectKeys(jsonDecode(const RejoinRoom(code: 'K7M2Q', token: 'abc').encode()), {
      't': text,
      'v': number,
      'rules': number,
      'code': text,
      'token': text,
    });
    expectKeys(jsonDecode(const RejoinRoom.proved(code: 'K7M2Q', proof: 'abc').encode()), {
      'v': number,
      'rules': number,
      'code': text,
      'proof': text,
    });
    // A v8 reader takes v7's showCards and ignores it.
    expect(RoomSettings.fromJson(jsonDecode(v7Settings)), const RoomSettings());
  });

  test('message sizes: the room with 16 members and 8 seats, and a spectator catching up with a long 8-handed hand '
      '(every hand visible), stay under 12 KB', () async {
    final h = _Harness();
    final host = await h.create(
      settings: const RoomSettings(seats: 8, stackBb: 1000, showStyles: true),
      bots: {for (var s = 1; s < 8; s++) s: 'gto'},
    );
    // Min-raises for 60 turns, then calls: a long hand; it stops before the end for the spectator to join.
    host.policy = (turn) => turn.canRaise && turn.turnId < 60
        ? PlayerAction.raiseTo(turn.minRaiseTo)
        : (turn.toCall == 0 ? const PlayerAction.check() : const PlayerAction.call());
    host.playsIn = (hand) => (host.lastTurn?.$2.turnId ?? 0) < 70;
    host.send(const HostSettings(seeBots: true));
    final names = [for (var i = 0; i < 15; i++) 'Spectator ${'$i'.padLeft(6, '0')}'];
    for (final name in names) {
      await h.join(name, host);
    }
    host.send(const StartGame());
    await h.until(() => host.lastTurn != null && host.lastTurn!.$2.turnId >= 70, 'a long hand');
    final watcher = h.members[5];
    watcher.send(const Resync());
    await h.settle();
    final snapshot = watcher.texts.lastWhere((t) => t.startsWith('{"t":"snapshot"'));
    final room = host.texts.lastWhere((t) => t.startsWith('{"t":"room"'));
    final dealt = watcher.texts.firstWhere((t) => t.startsWith('{"t":"hand"'));
    final caughtUp = watcher.all<Snapshot>().last.hand!;
    expect(caughtUp.batches.length, greaterThanOrEqualTo(70));
    expect(caughtUp.batches.first.whereType<HoleCardsDealt>().single.cards, hasLength(8));
    for (final (what, text) in [('snapshot', snapshot), ('room', room), ('hand', dealt)]) {
      expect(utf8.encode(text).length, lessThan(12 * 1024), reason: what);
    }
    expect(host.room.members, hasLength(16));
  });

  test('a member only waiting for a seat is still a spectator: they can neither sit out nor rebuy, and take the '
      'seat dealt in', () async {
    final h = _Harness();
    final host = await h.create(bots: {2: 'tag'});
    final ben = await h.join('Ben', host, seated: true);
    final cy = await h.join('Cy', host);
    ben.playsIn = (hand) => hand != 1;
    host.send(const StartGame());
    await h.until(() => ben.midHand && ben.lastTurn!.$2.seat == ben.lineups[1]!.you, "Ben's turn");
    cy.send(const TakeSeat());
    await h.settle();
    expect(cy.room.me!.waiting, isTrue, reason: "the bot's seat, from the next hand");
    for (final m in [const SitOut(true), const Rebuy()]) {
      final before = cy.all<Rejected>().length;
      cy.send(m);
      await h.settle();
      expect(cy.all<Rejected>().length, before + 1, reason: '$m');
      expect(cy.lastRejection, Rejection.illegal, reason: '$m');
    }
    // Waiting again after giving up the queue changes nothing either.
    cy.send(const LeaveSeat());
    cy.send(const TakeSeat());
    await h.settle();
    expect(cy.room.me!.waiting, isTrue);
    ben.playsIn = (_) => true;
    ben.actNow();
    await h.until(() => cy.dealtAs.containsKey(2), 'the next hand dealt');
    expect(cy.dealtAs[2]!.you, isNotNull, reason: 'Cy is dealt in, not sitting out');
    expect(host.room.seats[cy.seat!].sittingOut, isFalse);
  });

  test("the poker table takes only poker's bot styles from CreateRoom (a game level is a bad message)", () async {
    final h = _Harness();
    final answer = await h.answer(const CreateRoom(name: 'Ann', game: holdemKey, bots: {1: 'easy'}).encode());
    expect(answer, isA<Rejected>().having((r) => r.reason, 'reason', Rejection.badMessage));
    expect(await h.answer(const CreateRoom(name: 'Ann', game: holdemKey, bots: {1: 'gto'}).encode()), isA<Welcome>());
  });
}
