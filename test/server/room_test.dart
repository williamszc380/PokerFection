import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/engine/actions.dart';
import 'package:pokerfection/src/engine/cards.dart';
import 'package:pokerfection/src/engine/events.dart';
import 'package:pokerfection/src/engine/poker_hand.dart';
import 'package:pokerfection/src/online/clock.dart';
import 'package:pokerfection/src/online/memory_link.dart';
import 'package:pokerfection/src/online/mirror.dart';
import 'package:pokerfection/src/online/online_client.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/online/seat_proof.dart';
import 'package:pokerfection/src/online/seat_map.dart';
import 'package:pokerfection/src/online/timing.dart';
import 'package:pokerfection/src/server/client_link.dart';
import 'package:pokerfection/src/server/room_registry.dart';

import '../helpers.dart';

/// A device at the table, as simple as can be: it follows each hand on a
/// mirror (as the app does) and plays random legal moves, the host's
/// device also for the bots. Out of chips, it watches, and rebuys when it
/// may.
class _Device {
  _Device(this.link, this.rng) {
    link.messages.listen((text) => inbox.add(ServerMessage.decode(text)));
  }

  final MemoryLink link;
  final Random rng;
  final List<ServerMessage> inbox = [];
  final List<ServerMessage> seen = [];
  Welcome? welcome;
  SeatMap? seats;
  PokerHand? mirror;
  int hand = 0;
  Map<int, List<PlayingCard>> botCards = const {};
  int handsEnded = 0;

  /// This device's hand seat in each hand (null: watched).
  final Map<int, int?> you = {};
  int watched = 0, rebuys = 0;
  bool rebuying = false;

  void send(ClientMessage m) => link.send(m.encode());

  /// Handles what came in; true if there was anything.
  bool step() {
    if (inbox.isEmpty) return false;
    final messages = [...inbox];
    inbox.clear();
    for (final m in messages) {
      seen.add(m);
      // Back during a hand (it came with a snapshot): it follows from the next hand.
      if (seats == null && (m is BotCards || m is HandDealt || m is HandEvents)) continue;
      switch (m) {
        case Welcome():
          welcome = m;
        case NextHand():
          seats = SeatMap(m.stacks.length, m.you ?? 0);
          you[m.hand] = m.you;
          if (m.you == null) watched++;
          send(Ready(m.hand));
        case RoomState(:final you?):
          final out = m.seats[you].out;
          if (out && m.settings.rebuys && !rebuying) {
            rebuys++;
            send(const Rebuy());
          }
          rebuying = out;
        case BotCards():
          botCards = seats!.mapToLocal(m.cards);
        case HandDealt():
          hand = m.hand;
          final local = seats!.eventsToLocal(m.batch);
          mirror = RemoteDeal.fromBatch(local, extraKnown: botCards)
              .build(smallBlind: onlineSmallBlind, bigBlind: onlineBigBlind, ante: 0);
          botCards = const {};
          _ended(local);
          _turn(m.turn);
        case HandEvents():
          final local = seats!.eventsToLocal(m.batch);
          applyBatch(mirror!, local);
          _ended(local);
          _turn(m.turn);
        default:
          break;
      }
    }
    return true;
  }

  void _ended(List<GameEvent> batch) {
    for (final e in batch) {
      if (e is HandEnded) {
        handsEnded++;
        expect(e.netChange.values.fold(0, (a, b) => a + b), 0, reason: 'chips are kept');
        expect([for (var s = 0; s < e.finalStacks.length; s++) mirror!.stackOf(s)], e.finalStacks);
      }
    }
  }

  void _turn(Turn? turn) {
    if (turn == null) return;
    final seat = seats!.toLocal(turn.seat);
    final legal = mirror!.legalActions();
    expect(mirror!.toAct, seat);
    expect(turn.matches(legal), isTrue);
    if (seat == 0 && you[hand] != null) {
      send(Act(hand: hand, turnId: turn.turnId, action: randomAction(legal, rng)));
    } else if (welcome!.isHost && mirror!.knows(seat) && (seat != 0 || you[hand] == null)) {
      send(BotAct(hand: hand, turnId: turn.turnId, seat: turn.seat, action: randomAction(legal, rng)));
    }
  }
}

void main() {
  test('a host, a guest and two bots play hands, with rebuys; every device follows exactly', () async {
    final clock = ManualClock();
    final registry = RoomRegistry(clock: clock, random: Random(5));
    final rng = Random(9);
    _Device connect(String address) {
      final (server, device) = MemoryLink.pair(address: address);
      registry.accept(server);
      return _Device(device, rng);
    }

    final host = connect('host'), guest = connect('guest'), devices = [host, guest];
    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await pumpEventQueue();
        if (!devices.map((d) => d.step()).toList().contains(true)) return;
      }
    }

    host.send(
      const CreateRoom(
        name: 'Ann',
        settings: RoomSettings(seats: 4, stackBb: 20, rebuys: true),
        bots: {2: 'gto', 3: 'tag'},
      ),
    );
    await settle();
    final code = host.welcome!.code;
    guest.send(JoinRoom(code: code, name: 'Ben'));
    await settle();
    expect(guest.welcome!.seat, 1);

    // Only the host may start, or play the bots.
    guest.send(const StartGame());
    await settle();
    expect(guest.seen.whereType<Rejected>().single.reason, Rejection.notHost);
    host.send(const StartGame());

    for (var tick = 0; host.handsEnded < 30; tick++) {
      expect(tick, lessThan(2000), reason: 'the game stalled');
      await settle();
      // Nothing to do: time passes (the next hand is dealt after a pause).
      for (final d in devices) {
        d.send(const Ping(0));
      }
      await settle();
      clock.fireNext();
    }

    expect(registry.room(code)!.isClosed, isFalse);
    expect(guest.handsEnded, host.handsEnded);
    // The bots' cards go to the host's device only, and every rejection was meant.
    expect(guest.seen.whereType<BotCards>(), isEmpty);
    expect(host.seen.whereType<BotCards>(), isNotEmpty);
    expect(host.seen.whereType<Rejected>(), isEmpty);
    // Each player gets their own cards; one out of chips watches without any, then rebuys.
    for (final device in devices) {
      for (final dealt in device.seen.whereType<HandDealt>()) {
        final cards = dealt.batch.whereType<HoleCardsDealt>().single.cards;
        expect(cards.keys, [?device.you[dealt.hand]]);
      }
    }
    expect(host.rebuys + guest.rebuys, greaterThan(0));
    expect(host.watched + guest.watched, greaterThan(0));
  });

  test('without rebuys, players out of chips watch; the last one with chips wins, and the room is back in the lobby',
      () async {
    final clock = ManualClock();
    final registry = RoomRegistry(clock: clock, random: Random(2));
    final (server, link) = MemoryLink.pair();
    registry.accept(server);
    final received = <ServerMessage>[];
    void send(ClientMessage m) => link.send(m.encode());
    // The host's device checks or calls, for itself and its bots (2 BB stacks: all-ins come fast).
    NextHand? next;
    link.messages.listen((text) {
      final m = ServerMessage.decode(text);
      received.add(m);
      switch (m) {
        case NextHand():
          next = m;
          send(Ready(m.hand));
        case HandDealt(:final hand, :final turn) || HandEvents(:final hand, :final turn):
          if (turn == null) break;
          final move = turn.toCall == 0 ? const PlayerAction.check() : const PlayerAction.call();
          if (turn.seat == next!.you) {
            send(Act(hand: hand, turnId: turn.turnId, action: move));
          } else {
            send(BotAct(hand: hand, turnId: turn.turnId, seat: turn.seat, action: move));
          }
        default:
          break;
      }
    });

    send(const CreateRoom(name: 'Ann', settings: RoomSettings(seats: 3, stackBb: 2), bots: {1: 'tag', 2: 'nit'}));
    await pumpEventQueue();
    send(const StartGame());
    for (var tick = 0; !received.any((m) => m is GameOver); tick++) {
      expect(tick, lessThan(1000), reason: 'the game never ended');
      send(const Ping(0));
      await pumpEventQueue();
      clock.advance(const Duration(milliseconds: 500));
      await pumpEventQueue();
    }

    // The host ran out first and was dealt out: it watched the bots play on (the hands still came, without
    // cards), and its device still played them.
    final game = received.takeWhile((m) => m is! GameOver).toList();
    final out = <int>{};
    for (final m in game) {
      switch (m) {
        case RoomState():
          out.addAll([for (final s in m.seats) if (s.out) s.seat]);
        case NextHand():
          expect(m.seats.map((s) => s.seat).toSet().intersection(out), isEmpty);
          expect(m.you == null, out.contains(0));
        case HandDealt() when out.contains(0):
          expect(m.batch.whereType<HoleCardsDealt>().single.cards, isEmpty);
        default:
          break;
      }
    }
    expect(out, {0});
    expect(game.whereType<NextHand>().where((m) => m.you == null), isNotEmpty);
    expect(game.whereType<HandDealt>().length, game.whereType<NextHand>().length);
    // The last hand knocked out the other: its winner won the game.
    final over = received.whereType<GameOver>().single;
    expect(out, isNot(contains(over.seat)));
    expect(over.name, ['Ann', 'Alice', 'Bob'][over.seat!]);
    final ends = [
      for (final m in game)
        ...switch (m) {
          HandDealt(:final batch) || HandEvents(:final batch) => batch.whereType<HandEnded>(),
          _ => const <HandEnded>[],
        },
    ];
    expect(ends.last.finalStacks, containsAll([0, 600]));

    // Back in the lobby: the same seats and rules, nobody out; Start deals a new game with fresh stacks.
    final lobby = received.skipWhile((m) => m is! GameOver).whereType<RoomState>().first;
    expect(lobby.phase, RoomPhase.lobby);
    expect(lobby.seats.map((s) => (s.kind, s.out)), [
      (SeatKind.human, false),
      (SeatKind.bot, false),
      (SeatKind.bot, false),
    ]);
    send(const StartGame());
    await pumpEventQueue();
    final fresh = received.skipWhile((m) => m is! GameOver).whereType<NextHand>().first;
    expect(fresh.stacks, [200, 200, 200]);
  });

  test('moves out of turn, for an old turn, or not allowed are refused', () async {
    final clock = ManualClock();
    final registry = RoomRegistry(clock: clock, random: Random(2));
    final (server, link) = MemoryLink.pair();
    registry.accept(server);
    final received = <ServerMessage>[];
    link.messages.listen((text) => received.add(ServerMessage.decode(text)));
    void send(ClientMessage m) => link.send(m.encode());

    send(const CreateRoom(name: 'Ann', settings: RoomSettings(seats: 2), bots: {1: 'gto'}));
    await pumpEventQueue();
    send(const StartGame());
    await pumpEventQueue();
    send(Ready((received.whereType<NextHand>().single).hand));
    await pumpEventQueue();
    clock.advance(const Duration(seconds: 1));
    await pumpEventQueue();
    final dealt = received.whereType<HandDealt>().single;
    final turn = dealt.turn!;
    Rejection? lastRejection() => received.whereType<Rejected>().lastOrNull?.reason;

    // Heads-up the button acts first: either the host or the bot.
    final hostTurn = turn.seat == 0;
    if (!hostTurn) {
      send(Act(hand: dealt.hand, turnId: turn.turnId, action: const PlayerAction.call()));
      await pumpEventQueue();
      expect(lastRejection(), Rejection.notYourTurn);
      send(BotAct(hand: dealt.hand, turnId: turn.turnId, seat: 1, action: const PlayerAction.call()));
      await pumpEventQueue();
    } else {
      send(BotAct(hand: dealt.hand, turnId: turn.turnId, seat: 1, action: const PlayerAction.call()));
      await pumpEventQueue();
      expect(lastRejection(), Rejection.notYourTurn);
      send(Act(hand: dealt.hand, turnId: turn.turnId, action: const PlayerAction.call()));
      await pumpEventQueue();
    }
    final events = received.whereType<HandEvents>().first;
    expect(events.cause, ActCause.act);
    // The same move again, for the turn that is over now.
    send(Act(hand: dealt.hand, turnId: turn.turnId, action: const PlayerAction.call()));
    await pumpEventQueue();
    expect(lastRejection(), Rejection.stale);
    // The big blind can check: a fold is refused, and so is a raise below the minimum.
    final next = events.turn!;
    expect(next.toCall, 0);
    final fold = const PlayerAction.fold(), tooSmall = PlayerAction.raiseTo(next.minRaiseTo - 1);
    for (final action in [fold, tooSmall]) {
      if (next.seat == 0) {
        send(Act(hand: dealt.hand, turnId: next.turnId, action: action));
      } else {
        send(BotAct(hand: dealt.hand, turnId: next.turnId, seat: 1, action: action));
      }
      await pumpEventQueue();
      expect(lastRejection(), Rejection.illegal);
    }
    // A bot's turn the host's device leaves alone: the server checks for it.
    if (next.seat == 1) {
      clock.advance(const Duration(seconds: 20));
      await pumpEventQueue();
      final auto = received.whereType<HandEvents>().last;
      expect(auto.cause, ActCause.timeout);
      expect((auto.batch.first as ActionTaken).kind, ActionKind.check);
    }
  });

  test('after the hand a player may show their cards to everyone, once; not during it', () async {
    final clock = ManualClock();
    final registry = RoomRegistry(clock: clock, random: Random(5));
    final (server, link) = MemoryLink.pair();
    registry.accept(server);
    final received = <ServerMessage>[];
    link.messages.listen((text) => received.add(ServerMessage.decode(text)));
    void send(ClientMessage m) => link.send(m.encode());

    send(const CreateRoom(name: 'Ann', settings: RoomSettings(seats: 2), bots: {1: 'gto'}));
    await pumpEventQueue();
    send(const StartGame());
    await pumpEventQueue();
    send(Ready((received.whereType<NextHand>().single).hand));
    await pumpEventQueue();
    clock.advance(const Duration(seconds: 1));
    await pumpEventQueue();
    final dealt = received.whereType<HandDealt>().single;
    final mine = dealt.batch.whereType<HoleCardsDealt>().single.cards.values.single;
    // Not while the hand goes on.
    send(ShowCards(hand: dealt.hand));
    await pumpEventQueue();
    expect(received.whereType<Rejected>().last.reason, Rejection.stale);
    // Whoever acts first folds: the hand is over.
    final turn = dealt.turn!;
    send(turn.seat == 0
        ? Act(hand: dealt.hand, turnId: turn.turnId, action: const PlayerAction.fold())
        : BotAct(hand: dealt.hand, turnId: turn.turnId, seat: 1, action: const PlayerAction.fold()));
    await pumpEventQueue();
    send(ShowCards(hand: dealt.hand));
    send(ShowCards(hand: dealt.hand));
    await pumpEventQueue();
    final shown = received.whereType<CardsShown>().toList();
    expect(shown, hasLength(1), reason: 'shown once');
    expect(shown.single.seat, 0, reason: "the host's room seat");
    expect(shown.single.cards, mine);
  });

  test('the time limit starts once the actions are shown, plus 1 s unshown; help changes from the next hand', () async {
    final clock = ManualClock();
    final registry = RoomRegistry(clock: clock, random: Random(4));
    final (server, link) = MemoryLink.pair();
    registry.accept(server);
    final received = <ServerMessage>[];
    link.messages.listen((text) => received.add(ServerMessage.decode(text)));
    void send(ClientMessage m) => link.send(m.encode());
    const settings = RoomSettings(seats: 2, turnLimit: 15);

    send(const CreateRoom(name: 'Ann', settings: settings, bots: {1: 'gto'}));
    await pumpEventQueue();
    send(const StartGame());
    await pumpEventQueue();
    send(Ready(received.whereType<NextHand>().single.hand));
    await pumpEventQueue();
    clock.advance(Duration.zero);
    await pumpEventQueue();

    // The host's next turn; the host's device plays the bot (check or call) until then.
    Future<(int, Turn)> hostTurn() async {
      while (true) {
        final (hand, turn) = switch (received.lastWhere((m) => m is HandDealt || m is HandEvents)) {
          HandDealt(:final hand, :final turn) || HandEvents(:final hand, :final turn) => (hand, turn),
          _ => throw StateError('unreachable'),
        };
        if (turn == null) throw StateError('The hand ended');
        if (turn.seat == 0) return (hand, turn);
        final call = turn.toCall == 0 ? const PlayerAction.check() : const PlayerAction.call();
        send(BotAct(hand: hand, turnId: turn.turnId, seat: 1, action: call));
        await pumpEventQueue();
      }
    }

    // The host turns help on during the hand: it applies from the next one.
    send(const ChangeSettings(settings: RoomSettings(seats: 2, turnLimit: 15, help: HelpLevel.simple)));
    await pumpEventQueue();
    expect(received.whereType<RoomState>().last.settings.help, HelpLevel.simple);

    // 0.9 s into the unshown second, a move still counts.
    var (hand, turn) = await hostTurn();
    expect(turn.ms, 15000);
    clock.advance(Duration(milliseconds: turn.waitMs + 15000 + 900));
    await pumpEventQueue();
    final move = turn.toCall == 0 ? const PlayerAction.check() : const PlayerAction.call();
    send(Act(hand: hand, turnId: turn.turnId, action: move));
    await pumpEventQueue();
    expect(received.whereType<HandEvents>().last.cause, ActCause.act);

    // Past it, the server checks or folds, and a move for that turn is too late.
    (hand, turn) = await hostTurn();
    clock.advance(Duration(milliseconds: turn.waitMs + 16000));
    await pumpEventQueue();
    final auto = received.whereType<HandEvents>().last;
    expect((auto.turnId, auto.cause), (turn.turnId, ActCause.timeout));
    send(Act(hand: hand, turnId: turn.turnId, action: const PlayerAction.check()));
    await pumpEventQueue();
    expect(received.whereType<Rejected>().last.reason, Rejection.stale);

    // The rest of the hand times out too; the next hand gets the help.
    for (var tick = 0; received.whereType<NextHand>().length < 2; tick++) {
      expect(tick, lessThan(50), reason: 'the hand never ended');
      send(const Ping(0));
      await pumpEventQueue();
      clock.advance(const Duration(seconds: 20));
      await pumpEventQueue();
    }
    expect([for (final next in received.whereType<NextHand>()) next.help], [HelpLevel.none, HelpLevel.simple]);
  });

  test('everyone in the room chats: messages are cleaned, at most 4 each 8 s, and the last 64 go to whoever joins',
      () async {
    final clock = ManualClock();
    final registry = RoomRegistry(clock: clock, random: Random(6));
    ({MemoryLink link, List<ServerMessage> got}) connect(String address) {
      final (server, device) = MemoryLink.pair(address: address);
      registry.accept(server);
      final got = <ServerMessage>[];
      device.messages.listen((text) => got.add(ServerMessage.decode(text)));
      return (link: device, got: got);
    }

    List<ChatLine> lines(List<ServerMessage> got) => [for (final m in got.whereType<ChatLines>()) ...m.lines];
    final host = connect('host'), guest = connect('guest');
    host.link.send(const CreateRoom(name: 'Ann').encode());
    await pumpEventQueue();
    final code = host.got.whereType<Welcome>().single.code;
    guest.link.send(JoinRoom(code: code, name: 'Ben').encode());
    await pumpEventQueue();

    // Control and text-direction characters go, a line break is a space, and a long message is cut.
    final dirty = '${String.fromCharCodes([0x202E])}gg${String.fromCharCodes([7, 10])}wp ${'x' * 300}';
    host.link.send(jsonEncode({'t': 'say', 'text': dirty}));
    await pumpEventQueue();
    final said = lines(guest.got).single;
    expect((said.name, said.text, said.you), ('Ann', 'gg wp ${'x' * 250}', false));
    expect(lines(host.got).single.you, isTrue);

    // A fifth message within 8 s is refused; once the first is 8 s old, one more goes.
    for (var i = 1; i <= 5; i++) {
      guest.link.send(Say('$i').encode());
    }
    await pumpEventQueue();
    expect(lines(host.got).map((line) => line.text).skip(1), ['1', '2', '3', '4']);
    expect(guest.got.whereType<Rejected>().single.reason, Rejection.rateLimited);
    clock.advance(OnlineTiming.chatWindow);
    guest.link.send(const Say('6').encode());
    await pumpEventQueue();
    expect(lines(host.got).last.text, '6');

    // Many more, each player once every 2 s: whoever joins gets the last 64.
    clock.advance(OnlineTiming.chatWindow);
    for (var i = 0; i < 64; i++) {
      (i.isEven ? host : guest).link.send(Say('m$i').encode());
      await pumpEventQueue();
      clock.advance(const Duration(seconds: 1));
    }
    final total = lines(host.got).length;
    expect(total, 1 + 5 + 64);
    final newcomer = OnlineClient(
      'memory',
      clock: clock,
      connect: (_) async {
        final (server, device) = MemoryLink.pair(address: 'newcomer');
        registry.accept(server);
        return device;
      },
    );
    final heard = <ChatLine>[];
    newcomer.said.listen(heard.add);
    await newcomer.open(JoinRoom(code: code, name: 'Cy'));
    await pumpEventQueue();
    expect(newcomer.chat.length, chatKept);
    expect((newcomer.chat.first.n, newcomer.chat.last.text), (total - chatKept + 1, 'm63'));

    // The app keeps within the limit itself (with a little to spare).
    for (var i = 0; i < chatBurst; i++) {
      expect(newcomer.say('hi $i'), isTrue);
    }
    expect(newcomer.say('one more'), isFalse);
    expect(newcomer.chatWait, OnlineTiming.chatWindow + OnlineTiming.grace);
    await pumpEventQueue();
    expect(newcomer.chat.length, chatKept);
    expect(heard.skip(chatKept).map((line) => (line.text, line.you)), [for (var i = 0; i < 4; i++) ('hi $i', true)]);
    expect(lines(guest.got).last.you, isFalse);
    await newcomer.close();
  });

  test('a player sits out (the hand announced is announced again without them) and is back; away through a whole '
      'hand, they sit out until they come back', () async {
    final clock = ManualClock();
    final registry = RoomRegistry(clock: clock, random: Random(3));
    final rng = Random(4);
    _Device connect(String address) {
      final (server, device) = MemoryLink.pair(address: address);
      registry.accept(server);
      return _Device(device, rng);
    }

    final host = connect('host');
    var guest = connect('guest');
    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await pumpEventQueue();
        if (![host.step(), guest.step()].contains(true)) return;
      }
    }

    Future<void> until(bool Function() done, String what) async {
      for (var tick = 0; ; tick++) {
        await settle();
        if (done()) return;
        expect(tick, lessThan(2000), reason: 'never: $what');
        host.send(const Ping(0));
        guest.send(const Ping(0));
        await settle();
        clock.fireNext();
      }
    }

    SeatInfo ben() => host.seen.whereType<RoomState>().last.seats[1];

    host.send(
      const CreateRoom(name: 'Ann', settings: RoomSettings(seats: 3, stackBb: 20, resetStacks: true), bots: {2: 'tag'}),
    );
    await settle();
    final code = host.welcome!.code;
    guest.send(JoinRoom(code: code, name: 'Ben'));
    await settle();
    host.send(const StartGame());

    // The next hand is announced (not dealt yet) when Ben sits out: it is announced again without him.
    await until(() => host.handsEnded >= 1 && host.seen.lastWhere((m) => m is NextHand || m is HandDealt) is NextHand,
        'a hand announced');
    final announced = host.seen.whereType<NextHand>().last;
    expect(seatsOf(announced), [0, 1, 2]);
    guest.send(const SitOut(true));
    await settle();
    final again = host.seen.whereType<NextHand>().last;
    expect(again.hand, announced.hand);
    expect(seatsOf(again), [0, 2]);
    expect(guest.you[again.hand], isNull);
    expect((ben().sittingOut, ben().chips), (true, 2000), reason: 'he keeps his seat and chips');

    // He watches the others play; back, he is dealt in from the next hand.
    await until(() => host.hand > again.hand + 1, 'hands without him');
    expect([for (final next in host.seen.whereType<NextHand>().skipWhile((m) => m != again)) ...seatsOf(next)],
        isNot(contains(1)));
    final sat = guest.hand;
    guest.send(const SitOut(false));
    await until(() => guest.hand > sat && guest.you[guest.hand] != null, 'dealt in again');
    expect(ben().sittingOut, isFalse);

    // His connection drops: once a whole hand went by without him, he sits out, until he comes back.
    final token = guest.welcome!.token;
    await guest.link.close();
    await until(() => ben().sittingOut, 'sat out while away');
    expect(ben().status, SeatStatus.away);
    final away = host.hand;
    await until(() => host.hand > away + 1, 'hands without him');
    expect([for (final next in host.seen.whereType<NextHand>()) if (next.hand > away) ...seatsOf(next)],
        isNot(contains(1)));
    guest = connect('guest');
    guest.send(RejoinRoom(code: code, token: token));
    await until(() => guest.hand > 0 && guest.you[guest.hand] != null, 'dealt in once back');
    expect(ben().sittingOut, isFalse);
    expect(host.seen.whereType<Rejected>(), isEmpty);
  });

  test('the host removes a player during a hand: they play it out, then go; neither their token nor their device '
      'gets back in', () async {
    final clock = ManualClock();
    final registry = RoomRegistry(clock: clock, random: Random(8));
    final (hostServer, hostLink) = MemoryLink.pair(address: 'host');
    registry.accept(hostServer);
    final host = _Device(hostLink, Random(6));
    // Ben's device: ready for each hand; at his turn, it checks or calls once the test lets it.
    final (benServer, ben) = MemoryLink.pair(address: 'ben');
    registry.accept(benServer);
    final got = <ServerMessage>[];
    var plays = false;
    int? seat;
    (int, Turn)? turn;
    void play() {
      if (turn case (final hand, final t) when plays) {
        turn = null;
        final move = t.toCall == 0 ? const PlayerAction.check() : const PlayerAction.call();
        ben.send(Act(hand: hand, turnId: t.turnId, action: move).encode());
      }
    }

    ben.messages.listen((text) {
      final m = ServerMessage.decode(text);
      got.add(m);
      switch (m) {
        case NextHand():
          seat = m.you;
          ben.send(Ready(m.hand).encode());
        case HandDealt(:final hand, turn: final t) || HandEvents(:final hand, turn: final t):
          turn = t != null && t.seat == seat ? (hand, t) : null;
          play();
        default:
          break;
      }
    });
    Future<void> until(bool Function() done, String what) async {
      for (var tick = 0; ; tick++) {
        for (var i = 0; i < 20; i++) {
          await pumpEventQueue();
          if (!host.step()) break;
        }
        if (done()) return;
        expect(tick, lessThan(2000), reason: 'never: $what');
        host.send(const Ping(0));
        ben.send(const Ping(0).encode());
        await pumpEventQueue();
        clock.fireNext();
      }
    }

    host.send(
      const CreateRoom(name: 'Ann', settings: RoomSettings(seats: 3, stackBb: 20, resetStacks: true), bots: {2: 'tag'}),
    );
    await until(() => host.welcome != null, 'the room');
    final code = host.welcome!.code;
    ben.send(JoinRoom(code: code, name: 'Ben', device: 'ben-phone').encode());
    await until(() => got.any((m) => m is Welcome), 'Ben in');
    host.send(const StartGame());

    // At Ben's turn (the game waits for him), the host removes him: he plays the hand out first.
    await until(() => turn != null, "Ben's turn");
    host.send(const RemovePlayer(seat: 1, name: 'Ben'));
    await until(() => host.seen.whereType<RoomState>().last.seats[1].leaving, 'Ben leaves next hand');
    expect(got.whereType<Closing>(), isEmpty);
    plays = true;
    play();
    await until(() => got.any((m) => m is Closing), 'Ben gone');
    expect(got.whereType<Closing>().single.reason, CloseReason.removed);
    final handEnd = got.lastIndexWhere(
      (m) => switch (m) {
        HandDealt(:final batch) || HandEvents(:final batch) => batch.any((e) => e is HandEnded),
        _ => false,
      },
    );
    expect(handEnd, inInclusiveRange(0, got.indexWhere((m) => m is Closing)), reason: 'the hand ended first');
    expect(host.seen.whereType<PlayerRemoved>().single.name, 'Ben');
    expect(seatsOf(host.seen.whereType<NextHand>().last), [0, 2]);
    expect(host.seen.whereType<RoomState>().last.seats[1].isEmpty, isTrue);

    // Neither his token nor his device gets back in; another device does.
    Future<ServerMessage> answer(ClientMessage opening, String address) async {
      final (server, device) = MemoryLink.pair(address: address);
      registry.accept(server);
      final answers = <ServerMessage>[];
      device.messages.listen((text) => answers.add(ServerMessage.decode(text)));
      device.send(opening.encode());
      await pumpEventQueue();
      return answers.first;
    }

    final token = got.whereType<Welcome>().single.token;
    final refused = isA<ServerError>().having((e) => e.code, 'code', JoinError.removed);
    expect(await answer(RejoinRoom(code: code, token: token), 'ben'), refused);
    expect(await answer(JoinRoom(code: code, name: 'Ben', device: 'ben-phone'), 'ben'), refused);
    expect(await answer(JoinRoom(code: code, name: 'Ben', device: 'cy-phone'), 'cy'), isA<Welcome>());
  });

  test("a connection that only pings and never asks for a room is dropped after 15 s (anyone who knows a room's "
      'code can open connections to its host: they must not pile up); one in a room stays', () async {
    final clock = ManualClock();
    final registry = RoomRegistry(clock: clock, random: Random(5));
    final (idleServer, idle) = MemoryLink.pair(address: 'idle');
    final (hostServer, host) = MemoryLink.pair(address: 'host');
    registry.accept(idleServer);
    registry.accept(hostServer);
    host.messages.listen((_) {});
    idle.messages.listen((_) {});
    host.send(const CreateRoom(name: 'Ann').encode());
    for (var s = 0; s < 20; s++) {
      idle.send(Ping(s).encode());
      host.send(Ping(s).encode());
      clock.advance(const Duration(seconds: 1));
      await pumpEventQueue();
    }
    expect(idle.isClosed, isTrue);
    expect(host.isClosed, isFalse);
    expect(registry.connectionCount, 1);
    expect(RoomRegistry.joinWait, const Duration(seconds: 15));
  });

  test('a player coming back over a direct connection proves the seat for that connection only: the proof gets '
      "the seat there, and nowhere else (another connection's, or one that can't say which it is)", () async {
    final clock = ManualClock();
    final registry = RoomRegistry(clock: clock, random: Random(5));
    Future<ServerMessage> answer(ClientMessage opening, ClientLink Function(MemoryLink server) wrap) async {
      final (server, device) = MemoryLink.pair(address: 'guest');
      registry.accept(wrap(server));
      final answers = <ServerMessage>[];
      device.messages.listen((text) => answers.add(ServerMessage.decode(text)));
      device.send(opening.encode());
      await pumpEventQueue();
      return answers.first;
    }

    final (hostServer, host) = MemoryLink.pair(address: 'host');
    registry.accept(hostServer);
    final welcomes = <Welcome>[];
    host.messages.listen((text) {
      if (ServerMessage.decode(text) case final Welcome w) welcomes.add(w);
    });
    host.send(const CreateRoom(name: 'Ann').encode());
    await pumpEventQueue();
    final code = welcomes.single.code;
    final ben = await answer(JoinRoom(code: code, name: 'Ben'), (s) => s) as Welcome;

    final seatGone = isA<ServerError>().having((e) => e.code, 'code', JoinError.seatGone);
    final proof = seatProof(ben.token, 'offer A|answer A');
    expect(await answer(RejoinRoom.proved(code: code, proof: proof), (s) => _Bound(s, 'offer B|answer B')), seatGone);
    expect(await answer(RejoinRoom.proved(code: code, proof: proof), (s) => s), seatGone);
    expect(await answer(RejoinRoom.proved(code: code, proof: proof), (s) => _Bound(s, null)), seatGone);
    final back = await answer(RejoinRoom.proved(code: code, proof: proof), (s) => _Bound(s, 'offer A|answer A'));
    expect(back, isA<Welcome>().having((w) => w.seat, 'seat', ben.seat));
  });

  test("a room code is never all digits: older apps would read peer:23456 as a server called 'peer'", () {
    // Draws every digit first, then letters.
    final digitsFirst = _Draws([for (var i = 0; i < 5; i++) RoomRegistry.codeLetters.indexOf('2'), 0, 1, 2, 3, 4]);
    expect(RoomRegistry.randomCode(digitsFirst), 'ABCDE');
    final random = Random(1);
    for (var i = 0; i < 20000; i++) {
      expect(RoomRegistry.randomCode(random), isNot(matches(RegExp(r'^\d+$'))));
    }
  });
}

/// A server's side of a direct connection, that knows which it is
/// ([binding]: both ends' certificates).
class _Bound implements ClientLink, BoundConnection {
  _Bound(this._link, this.binding);

  final MemoryLink _link;

  @override
  final String? binding;

  @override
  String get address => _link.address;

  @override
  Stream<String> get messages => _link.messages;

  @override
  void send(String message) => _link.send(message);

  @override
  Future<void> close() => _link.close();
}

/// A Random that gives [draws] in turn (then zeros).
class _Draws implements Random {
  _Draws(this.draws);

  final List<int> draws;
  var _i = 0;

  @override
  int nextInt(int max) => _i < draws.length ? draws[_i++] : 0;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}

/// The room seats of the players of a hand.
List<int> seatsOf(NextHand m) => [for (final s in m.seats) s.seat];
