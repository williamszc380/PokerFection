import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/online/clock.dart';
import 'package:pokerfection/src/online/memory_link.dart';
import 'package:pokerfection/src/online/online_client.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/server/room_registry.dart';
import 'package:pokerfection/src/ui/table_controller.dart';
import 'package:pokerfection/src/ui/table_screen.dart';

import '../widget_test.dart' show actIfAsked, setScreen, testSolutions;

void main() {
  // The server runs in the test, on a clock the test moves (no real sockets).
  testWidgets('online with help: the host plays hands with its bots, and its moves are scored', (tester) async {
    setScreen(tester, const Size(1280, 900));
    final clock = ManualClock();
    final registry = RoomRegistry(clock: clock, random: Random(3));
    final client = OnlineClient(
      'memory',
      clock: clock,
      connect: (_) async {
        final (server, device) = MemoryLink.pair();
        registry.accept(server);
        return device;
      },
    );
    Future<void> wait([Duration time = const Duration(milliseconds: 100)]) async {
      clock.advance(time);
      await tester.pump(time);
    }

    final opening = client.open(
      const CreateRoom(
        name: 'Ann',
        game: holdemKey,
        settings: RoomSettings(seats: 3, stackBb: 20, resetStacks: true, help: HelpLevel.simple),
        bots: {1: 'gto', 2: 'gto'},
      ),
    );
    await wait();
    await opening;
    NextHand? first;
    client.attach((m) => first ??= m is NextHand ? m : null);
    client.send(const TakeSeat());
    client.send(const StartGame());
    for (var i = 0; first == null && i < 20; i++) {
      await wait();
    }
    client.detach();
    final controller = OnlineTableController(client, first!, speed: PlaybackSpeed.instant, solutions: testSolutions());
    await tester.pumpWidget(MaterialApp(home: TableScreen.online(controller: controller)));

    for (var step = 0; step < 3000 && controller.session.handsFinished < 4; step++) {
      await wait();
      if (controller.heroScore != null) await tester.tap(find.byKey(const ValueKey('continue')));
      if (controller.heroOptions != null) await actIfAsked(tester, call: true);
    }
    expect(controller.session.handsFinished, greaterThanOrEqualTo(4), reason: 'the game stalled');
    expect(controller.outOfSync, isFalse);
    expect(controller.session.history.expand((h) => h.decisions), isNotEmpty, reason: 'moves were scored');
    expect(controller.session.history.expand((h) => h.decisions).every((d) => d.turnId != null), isTrue);

    await tester.pumpWidget(const SizedBox());
    await wait(const Duration(seconds: 1));
  });
}
