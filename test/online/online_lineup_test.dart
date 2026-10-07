import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/engine/actions.dart';
import 'package:pokerfection/src/engine/events.dart';
import 'package:pokerfection/src/online/clock.dart';
import 'package:pokerfection/src/online/memory_link.dart';
import 'package:pokerfection/src/online/online_client.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/server/room_registry.dart';
import 'package:pokerfection/src/ui/table_controller.dart';
import 'package:pokerfection/src/ui/table_screen.dart';

import '../widget_test.dart' show setScreen, testSolutions;

void main() {
  // The server runs in the test, on a clock the test moves (no real sockets).
  testWidgets('the players change between hands: a guest joins and leaves, the host adds and takes away bots, '
      'looks are told to everyone', (tester) async {
    setScreen(tester, const Size(1280, 900));
    final clock = ManualClock();
    final registry = RoomRegistry(clock: clock, random: Random(7));
    MemoryLink connect() {
      final (server, device) = MemoryLink.pair();
      registry.accept(server);
      return device;
    }

    final client = OnlineClient('memory', clock: clock, connect: (_) async => connect());
    Future<void> wait([Duration time = const Duration(milliseconds: 100)]) async {
      clock.advance(time);
      await tester.pump(time);
    }

    // A room with one bot; players may look at others' cards.
    final opening = client.open(
      const CreateRoom(
        name: 'Ann',
        // Stacks reset every hand: nobody runs out of chips here.
        settings: RoomSettings(seats: 4, stackBb: 20, resetStacks: true, showCards: true),
        bots: {1: 'tag'},
      ),
    );
    await wait();
    final code = (await opening).code;
    NextHand? first;
    client.attach((m) => first ??= m is NextHand ? m : null);
    client.send(const StartGame());
    for (var i = 0; first == null && i < 20; i++) {
      await wait();
    }
    client.detach();
    final controller = OnlineTableController(client, first!, speed: PlaybackSpeed.instant, solutions: testSolutions());
    await tester.pumpWidget(MaterialApp(home: TableScreen.online(controller: controller)));
    expect(controller.playerCount, 2);

    // The guest checks or calls, from whatever hand seat they have.
    final guest = connect();
    final seen = <ServerMessage>[];
    var guestSeat = -1;
    guest.messages.listen((text) {
      final m = ServerMessage.decode(text);
      seen.add(m);
      switch (m) {
        case NextHand():
          guestSeat = m.you ?? -1;
          guest.send(Ready(m.hand).encode());
        case HandDealt(:final hand, :final turn) || HandEvents(:final hand, :final turn):
          if (turn != null && turn.seat == guestSeat) {
            final move = turn.toCall == 0 ? const PlayerAction.check() : const PlayerAction.call();
            guest.send(Act(hand: hand, turnId: turn.turnId, action: move).encode());
          }
        default:
          break;
      }
    });

    final counts = <int>{};
    Future<void> playUntil(bool Function() done, String what) async {
      for (var step = 0; !done(); step++) {
        expect(step, lessThan(3000), reason: 'never: $what');
        await wait();
        counts.add(controller.playerCount);
        final options = controller.heroOptions;
        if (options != null) {
          await controller.heroAct(options.canCheck ? const PlayerAction.check() : const PlayerAction.call());
        }
        expect(controller.outOfSync, isFalse);
      }
    }

    await playUntil(() => controller.session.handsFinished >= 1, 'a hand with the bot');
    guest.send(JoinRoom(code: code, name: 'Ben').encode());
    await playUntil(() => controller.playerCount == 3, 'the guest sat down');

    // The host looks at the guest's cards while the hand is on: only the host gets them, everyone is told.
    final ben = controller.view.seats.indexWhere((seat) => seat.info.name == 'Ben');
    await playUntil(() => controller.canPeek(ben), 'a hand to look in');
    controller.peek(ben);
    await playUntil(() => seen.whereType<Notice>().isNotEmpty, 'the guest was told');
    final notice = seen.whereType<Notice>().single;
    expect((notice.kind, notice.name, notice.targetName), (NoticeKind.peek, 'Ann', 'Ben'));
    expect(seen.whereType<PeekCards>(), isEmpty);
    final dealt = seen.whereType<HandDealt>().last.batch.whereType<HoleCardsDealt>().single.cards;
    expect(controller.view.seats[ben].cards, dealt[guestSeat]);

    // The host takes the bot away (from the next hand): the host and the guest play on.
    controller.removeBot(1);
    await playUntil(
      () => controller.playerCount == 2 && controller.view.seats.any((s) => s.info.name == 'Ben'),
      'the bot left',
    );
    final hands = controller.session.handsFinished;
    await playUntil(() => controller.session.handsFinished > hands, 'a hand heads-up with the guest');

    // The guest leaves: alone, the host waits, until a bot comes.
    guest.send(const Leave().encode());
    await playUntil(() => controller.paused, 'the game waits for players');
    controller.addBot('gto', roomSeat: 3);
    final before = controller.session.handsFinished;
    await playUntil(() => controller.session.handsFinished > before + 1, 'hands with the new bot');
    expect(counts, containsAll([2, 3]));
    expect(controller.view.seats.map((s) => s.info.name), ['Ann', 'Charlie'], reason: 'the new bot sits in seat 3');

    await tester.pumpWidget(const SizedBox());
    await wait(const Duration(seconds: 1));
  });
}
