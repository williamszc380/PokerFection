import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/engine/actions.dart';
import 'package:pokerfection/src/online/clock.dart';
import 'package:pokerfection/src/online/games/game_envelope.dart';
import 'package:pokerfection/src/online/games/game_runner.dart';
import 'package:pokerfection/src/online/memory_link.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/online/timing.dart';
import 'package:pokerfection/src/server/room_registry.dart';

/// A member's raw device: it keeps every message and says Ready to each
/// hand announced.
class _Member {
  _Member(this.link) {
    link.messages.listen((text) {
      final m = ServerMessage.decode(text);
      got.add(m);
      if (m is NextHand) send(Ready(m.hand));
    });
  }

  final MemoryLink link;
  final List<ServerMessage> got = [];

  void send(ClientMessage m) {
    if (!link.isClosed) link.send(m.encode());
  }

  Welcome get welcome => got.whereType<Welcome>().last;
  RoomState get room => got.whereType<RoomState>().last;
  List<T> all<T>() => got.whereType<T>().toList();
  Rejection? get lastRejection => all<Rejected>().lastOrNull?.reason;
}

/// A server on a clock the test moves ([roomIdle] as a device's host sets
/// it, or bin/server.dart's default), with raw devices.
class _Harness {
  _Harness({Duration? roomIdle = OnlineTiming.roomIdle}) {
    registry = RoomRegistry(clock: clock, random: Random(3), roomIdle: roomIdle, games: {'gomoku': _FakeGame()});
  }

  final clock = ManualClock();
  late final RoomRegistry registry;
  final List<_Member> members = [];

  _Member connect(String name) {
    final (server, device) = MemoryLink.pair(address: name);
    registry.accept(server);
    final m = _Member(device);
    members.add(m);
    return m;
  }

  Future<void> settle() async {
    for (var i = 0; i < 10; i++) {
      await pumpEventQueue();
    }
  }

  /// A room with no game (what the app creates).
  Future<_Member> create() async {
    final host = connect('Ann');
    host.send(const CreateRoom(name: 'Ann'));
    await settle();
    return host;
  }

  Future<_Member> join(String name, _Member host, {String? device}) async {
    final m = connect(name);
    m.send(JoinRoom(code: host.welcome.code, name: name, device: device));
    await settle();
    return m;
  }

  /// Lets [time] pass, every connection still open saying it is there (a
  /// ping doesn't keep a room from being idle).
  Future<void> pass(Duration time) async {
    const step = Duration(seconds: 10);
    for (var left = time; left > Duration.zero; left -= step) {
      for (final m in members) {
        m.send(const Ping(0));
      }
      await pumpEventQueue();
      clock.advance(left < step ? left : step);
    }
    await settle();
  }

  bool isOpen(_Member host) => registry.room(host.welcome.code)?.isClosed == false;
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
  test('a room the app creates has no game: no settings, no seats, in the lobby, the host a spectator', () async {
    final h = _Harness();
    final host = await h.create();
    expect(host.welcome.isHost, isTrue);
    final room = host.room;
    expect(room.game, isNull);
    expect(room.settings, isNull);
    expect(room.seats, isEmpty);
    expect(room.phase, RoomPhase.lobby);
    expect(room.members.map((m) => (m.id, m.name, m.seat)), [(host.welcome.id, 'Ann', null)]);
    expect(room.games, {holdemKey: holdemGv, 'gomoku': 1});
  });

  test('with no game, everything about seats and the table is refused (illegal) and moves are stale; nothing '
      'changes', () async {
    final h = _Harness();
    final host = await h.create();
    final before = jsonEncode(host.room.toJson());
    for (final (message, reason) in [
      (const TakeSeat(), Rejection.illegal),
      (const TakeSeat(0), Rejection.illegal),
      (const LeaveSeat(), Rejection.illegal),
      (const AddBot(), Rejection.illegal),
      (const RemoveBot(0), Rejection.illegal),
      (const StartGame(), Rejection.illegal),
      (const ChangeSettings(settings: RoomSettings(seats: 3)), Rejection.illegal),
      (const EndGame(), Rejection.illegal),
      (const SitOut(true), Rejection.illegal),
      (const Rebuy(), Rejection.illegal),
      (const Act(hand: 1, turnId: 1, action: PlayerAction.check()), Rejection.stale),
      (const Ready(1), Rejection.stale),
      (const GameMessage(game: 'gomoku', gv: 1, body: EnvelopeReady(1)), Rejection.stale),
    ]) {
      host.got.clear();
      host.send(message);
      await h.settle();
      expect(host.lastRejection, reason, reason: message.encode());
      expect(host.all<RoomState>(), isEmpty, reason: message.encode());
    }
    // The next RoomState is the same as before.
    host.send(const HostSettings(seeBots: false));
    await h.settle();
    expect(jsonEncode(host.room.toJson()), before);
  });

  test(
    'with no game, a guest joins (no snapshot), people chat, the host flips the switch and removes a spectator',
    () async {
      final h = _Harness();
      final host = await h.create();
      final ben = await h.join('Ben', host, device: 'ben-phone');
      expect(ben.welcome.isHost, isFalse);
      expect(ben.all<Snapshot>(), isEmpty, reason: 'no game: nothing to catch up with');
      expect(ben.room.members.map((m) => (m.name, m.seat)), [('Ann', null), ('Ben', null)]);
      expect(ben.room.seats, isEmpty);

      ben.send(const Say('hi'));
      await h.settle();
      expect(host.all<ChatLines>().expand((c) => c.lines).map((l) => (l.name, l.text)), [('Ben', 'hi')]);

      host.send(const HostSettings(seeBots: true));
      await h.settle();
      expect(ben.room.seeBots, isTrue);

      host.send(RemoveMember(id: ben.welcome.id, name: 'Ben'));
      await h.settle();
      expect(ben.all<Closing>().single.reason, CloseReason.removed);
      expect(host.all<PlayerRemoved>().single.id, ben.welcome.id);
      expect(host.room.members.map((m) => m.name), ['Ann']);
      // Banned: neither the device nor the token comes back.
      final again = await h.join('Ben', host, device: 'ben-phone');
      expect(again.all<ServerError>().single.code, JoinError.removed);
    },
  );

  test("the host picks Hold'em: its settings and 8 empty seats come, and a game is played", () async {
    final h = _Harness();
    final host = await h.create();
    final ben = await h.join('Ben', host);
    host.send(const ChooseGame(game: holdemKey));
    await h.settle();
    final room = ben.room;
    expect(room.game?.key, holdemKey);
    expect(room.settings, const RoomSettings());
    expect(room.seats.map((s) => s.kind), List.filled(8, SeatKind.empty));
    expect(room.members.map((m) => m.seat), [null, null], reason: 'everyone still watches');

    host.send(const TakeSeat());
    ben.send(const TakeSeat());
    host.send(const AddBot(style: 'tag'));
    await h.settle();
    expect(host.room.taken, 3);
    host.send(const StartGame());
    for (var i = 0; i < 20 && ben.all<HandDealt>().isEmpty; i++) {
      await h.pass(const Duration(seconds: 1));
    }
    expect(ben.all<HandDealt>(), isNotEmpty, reason: 'a hand dealt');
    expect(host.room.phase, RoomPhase.playing);
  });

  test("the host's Hold'em rules survive a switch to another game and back (no bots, nobody seated)", () async {
    final h = _Harness();
    final host = await h.create();
    host.send(const ChooseGame(game: holdemKey));
    host.send(const ChangeSettings(settings: RoomSettings(seats: 3, stackBb: 50)));
    host.send(const AddBot(style: 'tag'));
    host.send(const TakeSeat());
    await h.settle();
    expect(host.room.taken, 2);

    host.send(const ChooseGame(game: 'gomoku'));
    await h.settle();
    expect(host.room.game?.key, 'gomoku');
    expect(host.room.settings, isNull, reason: "Hold'em's rules only while it plays Hold'em");
    expect(host.room.seats.map((s) => s.kind), [SeatKind.empty, SeatKind.empty]);
    expect(host.room.members.single.seat, isNull);

    host.send(const ChooseGame(game: holdemKey));
    await h.settle();
    final room = host.room;
    expect(room.settings, const RoomSettings(seats: 3, stackBb: 50));
    expect(room.seats.map((s) => s.kind), List.filled(3, SeatKind.empty));
    expect(room.members.single.seat, isNull);
  });

  test('the same game again changes only its rules: seats and bots are kept', () async {
    final h = _Harness();
    final host = await h.create();
    host.send(const ChooseGame(game: holdemKey));
    host.send(const AddBot(style: 'tag', seat: 2));
    host.send(const TakeSeat(0));
    await h.settle();
    final seats = jsonEncode([for (final s in host.room.seats) s.toJson()]);
    host.got.clear();
    host.send(const ChooseGame(game: holdemKey));
    await h.settle();
    expect(host.all<Rejected>(), isEmpty);
    expect(jsonEncode([for (final s in host.room.seats) s.toJson()]), seats);
    expect(host.room.members.single.seat, 0);

    host.send(const ChooseGame(game: 'gomoku'));
    host.send(const ChooseGame(game: 'gomoku', setup: {'seats': 2, 'turnLimit': 30, 'rules': {}}));
    await h.settle();
    expect(host.room.game?.setup, {'seats': 2, 'turnLimit': 30, 'rules': {}});
  });

  test('a room on a device never closes for being idle; on a server of its own it closes after 30 minutes of '
      'nothing, and a chat line counts as something', () async {
    final device = _Harness(roomIdle: null);
    final onDevice = await device.create();
    await device.pass(const Duration(hours: 2));
    expect(device.isOpen(onDevice), isTrue);
    expect(onDevice.link.isClosed, isFalse);

    final server = _Harness();
    final quiet = await server.create();
    await server.pass(const Duration(minutes: 29));
    expect(server.isOpen(quiet), isTrue);
    await server.pass(const Duration(minutes: 1, seconds: 1));
    expect(server.isOpen(quiet), isFalse);
    expect(quiet.all<Closing>().single.reason, CloseReason.idle);

    final chatty = _Harness();
    final host = await chatty.create();
    await chatty.pass(const Duration(minutes: 20));
    host.send(const Say('anyone?'));
    await chatty.pass(const Duration(minutes: 29));
    expect(chatty.isOpen(host), isTrue, reason: 'the chat line at 20 min moved the close to 50 min');
    await chatty.pass(const Duration(minutes: 1, seconds: 1));
    expect(chatty.isOpen(host), isFalse);
    expect(host.all<Closing>().single.reason, CloseReason.idle);
  });

  test("a device's room doesn't end while its host is away, and the host comes back as host; on a server of its "
      'own the host away past the hold closes it', () async {
    final device = _Harness(roomIdle: null);
    final host = await device.create();
    final ben = await device.join('Ben', host);
    final token = host.welcome.token, code = host.welcome.code;
    await host.link.close();
    device.members.remove(host);
    await device.pass(const Duration(minutes: 10));
    expect(device.isOpen(host), isTrue);
    expect(ben.all<Closing>(), isEmpty);
    expect(ben.room.members.first.status, SeatStatus.away);
    ben.send(const Say('still here'));
    await device.settle();
    expect(ben.all<ChatLines>().expand((c) => c.lines).map((l) => l.text), ['still here']);
    final back = device.connect('Ann');
    back.send(RejoinRoom(code: code, token: token));
    await device.settle();
    expect(back.welcome.isHost, isTrue);
    expect(back.welcome.id, host.welcome.id);
    expect(back.room.members.first.status, SeatStatus.connected);
    expect(back.all<ChatLines>().expand((c) => c.lines).map((l) => l.text), ['still here']);

    final server = _Harness();
    final away = await server.create();
    final cy = await server.join('Cy', away);
    await away.link.close();
    server.members.remove(away);
    await server.pass(OnlineTiming.hold - const Duration(seconds: 5));
    expect(server.isOpen(away), isTrue);
    await server.pass(const Duration(seconds: 10));
    expect(server.isOpen(away), isFalse);
    expect(cy.all<Closing>().single.reason, CloseReason.roomClosed);
  });

  test("CreateRoom with game holdem starts with Hold'em's table at once, with its bots (the shortcut)", () async {
    final h = _Harness();
    final host = h.connect('Ann');
    host.send(const CreateRoom(name: 'Ann', game: holdemKey, settings: RoomSettings(seats: 4), bots: {1: 'tag'}));
    await h.settle();
    final room = host.room;
    expect(room.game?.key, holdemKey);
    expect(room.settings, const RoomSettings(seats: 4));
    expect(room.seats.map((s) => s.kind), [SeatKind.empty, SeatKind.bot, SeatKind.empty, SeatKind.empty]);
    expect(room.seats[1].style, 'tag');
  });

  group('protocol', () {
    Map<String, Object?> createJson(Map<String, Object?> extra) => {
      ...jsonDecode(const CreateRoom(name: 'Ann').encode()) as Map<String, Object?>,
      ...extra,
    };

    test('bots without a game, or a game other than Hold\'em in create, are not a message', () async {
      expect(
        () => ClientMessage.decode(
          jsonEncode(
            createJson({
              'bots': {'1': 'tag'},
            }),
          ),
        ),
        throwsA(isA<ProtocolError>()),
      );
      expect(() => ClientMessage.decode(jsonEncode(createJson({'game': 'gomoku'}))), throwsA(isA<ProtocolError>()));
      expect(() => ClientMessage.decode(jsonEncode(createJson({'game': 'chess'}))), throwsA(isA<ProtocolError>()));
      final holdem = ClientMessage.decode(
        jsonEncode(
          createJson({
            'game': holdemKey,
            'bots': {'1': 'tag'},
          }),
        ),
      );
      expect((holdem as CreateRoom).game, holdemKey);
      expect(holdem.bots, {1: 'tag'});
      expect((ClientMessage.decode(const CreateRoom(name: 'Ann').encode()) as CreateRoom).game, isNull);

      // As a first message: refused like any malformed one.
      final h = _Harness();
      final device = h.connect('Ann');
      device.link.send(jsonEncode(createJson({'game': 'gomoku'})));
      await h.settle();
      expect(device.lastRejection, Rejection.badMessage);
      expect(h.registry.roomCount, 0);
    });

    test('RoomState round-trips with and without its game and settings', () {
      const bare = RoomState(code: 'K7M2Q', phase: RoomPhase.lobby, host: 1, you: 1, seats: []);
      final bareJson = bare.toJson();
      expect(bareJson.containsKey('game'), isFalse);
      expect(bareJson.containsKey('settings'), isFalse);
      final read = ServerMessage.decode(bare.encode()) as RoomState;
      expect((read.game, read.settings, read.seats.length), (null, null, 0));
      expect(read.toJson(), bareJson);

      const full = RoomState(
        code: 'K7M2Q',
        phase: RoomPhase.lobby,
        host: 1,
        you: 1,
        game: GameChoice.holdem,
        settings: RoomSettings(seats: 3),
        seats: [SeatInfo(seat: 0, kind: SeatKind.empty)],
      );
      final again = ServerMessage.decode(full.encode()) as RoomState;
      expect((again.game?.key, again.settings), (holdemKey, const RoomSettings(seats: 3)));
      expect(again.toJson(), full.toJson());
    });

    test("a v8 create without a game still carries every key v7 requires, and no 'game'", () {
      final create = jsonDecode(const CreateRoom(name: 'Ann').encode()) as Map<String, Object?>;
      for (final key in ['t', 'v', 'rules', 'name', 'settings']) {
        expect(create.containsKey(key), isTrue, reason: key);
      }
      expect(create.containsKey('game'), isFalse);
      expect(create.containsKey('bots'), isFalse);
      expect(create['t'], 'create');
    });
  });
}
