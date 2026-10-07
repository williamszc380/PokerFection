import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/engine/actions.dart';
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
  testWidgets('the connection drops and comes back: the table catches up, a move made meanwhile counts once, '
      'and the host plays its bots again', (tester) async {
    setScreen(tester, const Size(1280, 900));
    final clock = ManualClock();
    final registry = RoomRegistry(clock: clock, random: Random(11));
    // The host's device side of the latest connection, to drop it.
    late MemoryLink link;
    final client = OnlineClient(
      'memory',
      clock: clock,
      random: Random(1),
      connect: (_) async {
        final (server, device) = MemoryLink.pair();
        registry.accept(server);
        return link = device;
      },
    );
    Future<void> wait([Duration time = const Duration(milliseconds: 100)]) async {
      clock.advance(time);
      await tester.pump(time);
    }

    final opening = client.open(
      // Stacks reset every hand: nobody runs out of chips here.
      const CreateRoom(
        name: 'Ann',
        settings: RoomSettings(seats: 3, stackBb: 20, resetStacks: true),
        bots: {1: 'tag', 2: 'gto'},
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

    Future<void> playUntil(bool Function() done, String what, {bool act = true}) async {
      for (var step = 0; !done(); step++) {
        expect(step, lessThan(3000), reason: 'never: $what');
        await wait();
        final options = controller.heroOptions;
        if (act && options != null) {
          await controller.heroAct(options.canCheck ? const PlayerAction.check() : const PlayerAction.call());
        }
        expect(controller.outOfSync, isFalse);
      }
    }

    await playUntil(() => controller.session.handsFinished >= 1, 'a first hand');

    // At the user's turn the connection drops; they act anyway (the move can't go yet).
    await playUntil(() => controller.heroOptions != null, "the user's turn", act: false);
    final hand = controller.handNumber, finished = controller.session.handsFinished;
    final move = controller.heroOptions!.canCheck ? const PlayerAction.check() : const PlayerAction.call();
    await link.close();
    await wait();
    expect(controller.reconnecting, isTrue);
    expect(registry.room(code)!.connectedCount, 0, reason: 'the host is away');
    await controller.heroAct(move);

    // Back within a second (before the server would check or fold for the user): the move is sent again.
    await playUntil(() => !controller.reconnecting, 'reconnected', act: false);
    await wait();
    final sent = [
      for (final text in link.sent)
        text.contains('"t":"act"')
            ? 'act'
            : text.contains('"t":"rejoin"')
            ? 'rejoin'
            : '',
    ]..removeWhere((t) => t.isEmpty);
    expect(sent.take(2), ['rejoin', 'act']);
    await playUntil(
      () => controller.handNumber > hand || controller.session.handsFinished > finished,
      'the hand went on',
    );
    final record = controller.session.history.firstWhere((h) => h.handNumber == hand);
    expect(record.result, isNotNull, reason: 'the hand was followed to its end');

    // Dropped again for longer, in the middle of whatever happens: the bots check or fold meanwhile, and the
    // table catches up (playing the hand again if it moved on), then plays on with the host's bots.
    await link.close();
    for (var i = 0; i < 4; i++) {
      await wait(const Duration(milliseconds: 50));
    }
    final before = controller.session.handsFinished;
    await playUntil(() => controller.session.handsFinished >= before + 3, 'hands after coming back');
    expect(controller.ended, isFalse);

    await tester.pumpWidget(const SizedBox());
    await wait(const Duration(seconds: 1));
  });

  testWidgets('a guest away while hands go on: auto-played, then back in a newer hand (played again at once); '
      'away too long, the seat is gone', (tester) async {
    setScreen(tester, const Size(1280, 900));
    final clock = ManualClock();
    final registry = RoomRegistry(clock: clock, random: Random(5));
    MemoryLink connect() {
      final (server, device) = MemoryLink.pair();
      registry.accept(server);
      return device;
    }

    Future<void> wait([Duration time = const Duration(milliseconds: 100)]) async {
      clock.advance(time);
      await tester.pump(time);
    }

    // The host's device, as simple as can be: it checks or calls, for itself and its bot.
    final host = connect();
    final causes = <ActCause>[];
    var code = '', mySeat = -1, dealt = 0;
    var botSeats = <int>{};
    host.messages.listen((text) {
      final m = ServerMessage.decode(text);
      switch (m) {
        case Welcome():
          code = m.code;
        case NextHand():
          botSeats = {
            for (final (i, s) in m.seats.indexed)
              if (s.kind == SeatKind.bot) i,
          };
          mySeat = m.you ?? -1;
          host.send(Ready(m.hand).encode());
        case HandDealt(:final hand, :final turn) || HandEvents(:final hand, :final turn):
          if (m case HandDealt()) dealt = hand;
          if (m case HandEvents(:final cause)) causes.add(cause);
          if (turn == null) break;
          final move = turn.toCall == 0 ? const PlayerAction.check() : const PlayerAction.call();
          if (botSeats.contains(turn.seat)) {
            host.send(BotAct(hand: hand, turnId: turn.turnId, seat: turn.seat, action: move).encode());
          } else if (turn.seat == mySeat) {
            host.send(Act(hand: hand, turnId: turn.turnId, action: move).encode());
          }
        default:
          break;
      }
    });
    host.send(
      const CreateRoom(name: 'Ann', settings: RoomSettings(seats: 3, stackBb: 20, resetStacks: true), bots: {2: 'tag'})
          .encode(),
    );
    await wait();

    // The guest, on the table screen; offline when the test says so.
    var offline = false;
    late MemoryLink link;
    final client = OnlineClient(
      'memory',
      clock: clock,
      random: Random(2),
      connect: (_) async {
        if (offline) throw StateError('No network');
        return link = connect();
      },
    );
    final opening = client.open(JoinRoom(code: code, name: 'Ben'));
    await wait();
    await opening;
    NextHand? first;
    client.attach((m) => first ??= m is NextHand ? m : null);
    host.send(const StartGame().encode());
    for (var i = 0; first == null && i < 20; i++) {
      await wait();
    }
    client.detach();
    final controller = OnlineTableController(client, first!, speed: PlaybackSpeed.instant, solutions: testSolutions());
    await tester.pumpWidget(MaterialApp(home: TableScreen.online(controller: controller)));

    Future<void> playUntil(bool Function() done, String what) async {
      for (var step = 0; !done(); step++) {
        expect(step, lessThan(3000), reason: 'never: $what');
        await wait();
        final options = controller.heroOptions;
        if (options != null) {
          await controller.heroAct(options.canCheck ? const PlayerAction.check() : const PlayerAction.call());
        }
        expect(controller.outOfSync, isFalse);
      }
    }

    await playUntil(() => controller.session.handsFinished >= 1, 'a first hand');

    // Away (no network) while the others play on: the server plays the guest's turns.
    offline = true;
    await link.close();
    final hand = controller.handNumber;
    for (var i = 0; i < 600 && dealt <= hand + 1; i++) {
      await wait();
    }
    expect(causes, contains(ActCause.away));
    expect(controller.reconnecting, isTrue);

    // Back: the table is at the newer hand at once, and plays on.
    offline = false;
    await playUntil(() => !controller.reconnecting, 'reconnected');
    expect(controller.handNumber, greaterThan(hand));
    final back = controller.session.handsFinished;
    await playUntil(() => controller.session.handsFinished >= back + 2, 'hands after coming back');

    // Away for good: after the hold, coming back is refused, and the seat is empty.
    offline = true;
    await link.close();
    await wait(const Duration(seconds: 125));
    offline = false;
    await playUntil(() => controller.ended, 'given up');
    expect(client.failure, JoinError.seatGone);

    await tester.pumpWidget(const SizedBox());
    await wait(const Duration(seconds: 1));
  });
}
