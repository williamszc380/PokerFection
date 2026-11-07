import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/online/online_client.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/ui/table_controller.dart';
import 'package:pokerfection/src/ui/table_screen.dart';

import '../gto/manual_solves.dart';
import '../kit/shots.dart';
import 'room_kit.dart';

/// An online table while GTO's answer is on its way, at every size and in
/// every language: a player with help, simple or advanced (the choices
/// with "Solving…", Show GTO waiting for the answer, the answer shown) and
/// a spectator's coach (working it out, then its answer). Nothing may
/// overflow. With `--dart-define=SHOTS=dir` each is saved as a PNG.
void main() {
  setUpAll(loadShotFonts);
  const sizes = [Size(568, 320), Size(900, 420), Size(1280, 800), Size(390, 844)];

  Future<void> tick(WidgetTester tester, TestServer server, [Duration time = const Duration(milliseconds: 20)]) async {
    server.clock.advance(time);
    await tester.pump(time);
  }

  Future<void> tickUntil(WidgetTester tester, TestServer server, bool Function() done, String what) async {
    for (var i = 0; !done(); i++) {
      expect(i, lessThan(5000), reason: 'never: $what');
      await tick(tester, server);
    }
  }

  Future<void> snap(WidgetTester tester, String name) async {
    await tester.pump();
    final error = tester.takeException();
    await shot(tester, name);
    expect(error, isNull, reason: name);
  }

  /// A Hold'em room on [server] hosted by [own] (Ann), with [guests] who
  /// check or call by themselves, slowly; Ann seated if [seated].
  Future<void> room(WidgetTester tester, TestServer server, OnlineClient own,
      {required List<String> guests, required bool seated, HelpLevel help = HelpLevel.none}) async {
    await server.open(
      tester,
      own,
      CreateRoom(name: 'Ann', game: holdemKey, settings: RoomSettings(seats: 4, stackBb: 40, resetStacks: true, help: help)),
    );
    if (seated) {
      own.send(const TakeSeat());
      await server.until(tester, () => own.mySeat != null, 'seated');
    }
    for (final name in guests) {
      final guest = AutoGuest(server, name, think: const Duration(seconds: 3))..join(own.room!.code);
      await server.until(tester, () => guest.room != null, '$name in');
      guest.send(const TakeSeat());
      await server.until(tester, () => guest.room?.me?.seat != null, '$name seated');
    }
  }

  Future<OnlineTableController> start(WidgetTester tester, TestServer server, OnlineClient own, ManualSolves solves) async {
    NextHand? first;
    own.attach((m) => first ??= m is NextHand ? m : null);
    own.send(const StartGame());
    await server.until(tester, () => first != null, 'the first hand');
    own.detach();
    return OnlineTableController(own, first!, speed: PlaybackSpeed.instant, solutions: withManualSolves(solves));
  }

  Future<void> close(WidgetTester tester, TestServer server, OnlineTableController table) async {
    await tester.pumpWidget(const SizedBox());
    table.dispose();
    await server.wait(tester, const Duration(seconds: 1));
  }

  for (final language in AppLanguage.values) {
    for (final size in sizes) {
      final tag = shotTag(size, language);

      testWidgets('a player with help online: the choices while the answer comes, Show GTO waiting for it, and the '
          'answer, at $tag', (tester) async {
        final server = TestServer(seed: 4);
        final solves = ManualSolves();
        final own = server.client();
        await room(tester, server, own, guests: ['Cy', 'Di'], seated: true, help: HelpLevel.simple);
        final table = await start(tester, server, own, solves);
        await pumpShot(tester, TableScreen.online(controller: table, ownsController: false), size: size, language: language);
        await tickUntil(tester, server, () => table.heroOptions != null, 'her turn');
        await tester.pump(const Duration(milliseconds: 500));
        expect(table.answerPending, isTrue);
        await snap(tester, 'online_pending_$tag');
        await tester.ensureVisible(find.byKey(const ValueKey('show gto')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('show gto')));
        await snap(tester, 'online_show_waiting_$tag');
        while (table.answerPending) {
          solves.completeAll();
          await tick(tester, server);
        }
        expect(table.heroSpot, isNotNull);
        await snap(tester, 'online_answer_$tag');
        await close(tester, server, table);
      });

      testWidgets('a player with advanced help online: the mix while the answer comes, Show GTO waiting for it, and '
          'the answer, at $tag', (tester) async {
        final server = TestServer(seed: 4);
        final solves = ManualSolves();
        final own = server.client();
        await room(tester, server, own, guests: ['Cy', 'Di'], seated: true, help: HelpLevel.advanced);
        final table = await start(tester, server, own, solves);
        await pumpShot(tester, TableScreen.online(controller: table, ownsController: false), size: size, language: language);
        await tickUntil(tester, server, () => table.heroOptions != null, 'her turn');
        await tester.pump(const Duration(milliseconds: 500));
        expect(table.answerPending, isTrue);
        await snap(tester, 'online_adv_pending_$tag');
        await tester.ensureVisible(find.byKey(const ValueKey('show gto')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('show gto')));
        await snap(tester, 'online_adv_show_waiting_$tag');
        while (table.answerPending) {
          solves.completeAll();
          await tick(tester, server);
        }
        expect(table.heroSpot, isNotNull);
        await snap(tester, 'online_adv_answer_$tag');
        await close(tester, server, table);
      });

      testWidgets("a spectator's coach working the answer out, then showing it, at $tag", (tester) async {
        final server = TestServer(seed: 6);
        final solves = ManualSolves();
        final own = server.client();
        await room(tester, server, own, guests: ['Cy', 'Di', 'Eve'], seated: false);
        final table = await start(tester, server, own, solves);
        table.setCoach(true);
        await pumpShot(tester, TableScreen.online(controller: table, ownsController: false), size: size, language: language);
        final thinking = find.byKey(const ValueKey('coach thinking'), skipOffstage: false);
        final answer = find.byKey(const ValueKey('coach answer'), skipOffstage: false);
        await tickUntil(tester, server, () => thinking.evaluate().isNotEmpty && solves.pending.isNotEmpty, 'the coach at work');
        await snap(tester, 'online_coach_thinking_$tag');
        await tickUntil(tester, server, () {
          solves.completeAll();
          return answer.evaluate().isNotEmpty;
        }, "the coach's answer");
        await snap(tester, 'online_coach_answer_$tag');
        table.handBack();
        await close(tester, server, table);
      });
    }
  }
}
