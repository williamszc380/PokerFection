import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/engine/actions.dart';
import 'package:pokerfection/src/engine/events.dart';
import 'package:pokerfection/src/gto/gto_solutions.dart';
import 'package:pokerfection/src/gto/spot_strategy.dart';
import 'package:pokerfection/src/online/online_client.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/online/timing.dart';
import 'package:pokerfection/src/ui/table_controller.dart';
import 'package:pokerfection/src/ui/table_screen.dart';

import '../gto/manual_solves.dart';
import '../widget_test.dart' show setScreen, testSolutions;
import 'room_kit.dart';

/// Online play never waits for computation either: every device says
/// Ready as soon as it has shown the last hand, the host's bots play
/// within their think pause and a second more (keeping the hand on the
/// solved lines for everyone's help), and Show GTO, pressed before its
/// answer, holds nothing up. Each device solves for itself; solves finish
/// when the test says (ManualSolves) on the devices that use them.
void main() {
  const step = Duration(milliseconds: 10);

  /// Lets [time] pass for the server and the widgets, in small steps.
  Future<void> tick(WidgetTester tester, TestServer server, [Duration time = step]) async {
    server.clock.advance(time);
    await tester.pump(time);
  }

  /// Lets time pass in small steps until [done], and says how long that took.
  Future<Duration> tickUntil(WidgetTester tester, TestServer server, bool Function() done, String what,
      {int max = 3000}) async {
    var waited = Duration.zero;
    for (var i = 0; !done(); i++) {
      expect(i, lessThan(max), reason: 'never: $what');
      await tick(tester, server);
      waited += step;
    }
    return waited;
  }

  /// The messages [link] (a device's end, recorded) sent of type [type].
  List<ClientMessage> sentOf(TestServer server, int link, String type) => [
        for (final text in server.links[link].sent)
          if (text.contains('"t":"$type"')) ClientMessage.decode(text),
      ];

  /// [client]'s table for the game [start] begins (the host's StartGame):
  /// from the first hand it is told about. [random] plays its bots (and
  /// picks secret styles) the same way every run.
  Future<OnlineTableController> tableOf(
    WidgetTester tester,
    TestServer server,
    OnlineClient client,
    GtoSolutions solutions,
    void Function() start, {
    Random? random,
  }) async {
    NextHand? first;
    client.attach((m) => first ??= m is NextHand ? m : null);
    start();
    await server.until(tester, () => first != null, 'the first hand announced');
    client.detach();
    return OnlineTableController(client, first!, speed: PlaybackSpeed.instant, solutions: solutions, random: random);
  }

  Future<void> close(WidgetTester tester, TestServer server, List<OnlineTableController> tables) async {
    await tester.pumpWidget(const SizedBox());
    for (final table in tables) {
      table.dispose();
    }
    await server.wait(tester, const Duration(seconds: 1));
  }

  int choiceOf(TableController c, List<SpotActionKind> kinds) => c.heroMenu!.indexWhere((a) => kinds.contains(a.kind));

  /// Check, or else call.
  int passive(TableController c) => choiceOf(c, const [SpotActionKind.check, SpotActionKind.call]);

  testWidgets("a player with help says Ready at once for every hand while its device's solves are all held; the "
      'hands are dealt and their choices work; grades still to come at the next deal are dropped', (tester) async {
    setScreen(tester, const Size(1280, 900));
    final server = TestServer();
    final solves = ManualSolves();
    final own = server.client(record: true);
    await server.open(
      tester,
      own,
      const CreateRoom(
        name: 'Ann',
        game: holdemKey,
        settings: RoomSettings(seats: 3, stackBb: 20, resetStacks: true, help: HelpLevel.simple),
        bots: {1: 'tag', 2: 'gto'},
      ),
    );
    own.send(const TakeSeat());
    await server.until(tester, () => own.mySeat != null, 'seated');
    final table = await tableOf(tester, server, own, withManualSolves(solves), () => own.send(const StartGame()));
    await tester.pumpWidget(MaterialApp(home: TableScreen.online(controller: table, ownsController: false)));

    var decisions = 0;
    final announced = <int, int>{}, ready = <int, int>{};
    while (table.handNumber < 4 || !table.handOver) {
      await tick(tester, server);
      for (final m in sentOf(server, 0, 'ready')) {
        ready.putIfAbsent((m as Ready).hand, () => server.clock.nowMs);
      }
      final next = table.nextHandAt;
      if (next != null) announced.putIfAbsent(table.handNumber + 1, () => server.clock.nowMs);
      if (table.heroOptions != null && table.heroScore == null) {
        expect(table.answerPending, isTrue, reason: 'nothing is solved on this device');
        decisions++;
        await table.playGraded(passive(table));
      }
      expect(server.clock.nowMs, lessThan(120000), reason: 'the game stalled');
    }
    expect(decisions, greaterThan(0));
    expect(solves.started.where((s) => s.done), isEmpty, reason: 'not one solve finished');
    for (final hand in [2, 3, 4]) {
      expect(ready[hand], isNotNull, reason: 'Ready for hand $hand');
      expect(ready[hand]! - announced[hand]!, lessThanOrEqualTo(step.inMilliseconds),
          reason: 'Ready for hand $hand as soon as it was announced, its solve held');
    }
    expect(table.gradesPending, isTrue, reason: "the last hand's grades are still to come");
    await tickUntil(tester, server, () => table.handNumber > 4, 'the next deal');
    await tester.pump();
    expect(table.gradesPending, isFalse);
    expect(table.session.history.expand((h) => h.decisions), isEmpty,
        reason: "the answers didn't come before the next deal: those grades are dropped, as before");
    await close(tester, server, [table]);
  });

  testWidgets("the host's GTO bot plays its flop move after its think pause and the budget while the flop's solve "
      'is held, and keeps the hand on the solved lines', (tester) async {
    setScreen(tester, const Size(1280, 900));
    final server = TestServer(seed: 5);
    final solves = ManualSolves();
    final own = server.client(record: true);
    await server.open(
      tester,
      own,
      const CreateRoom(
        name: 'Ann',
        game: holdemKey,
        settings: RoomSettings(seats: 2, stackBb: 40, resetStacks: true),
        bots: {1: 'gto'},
      ),
    );
    own.send(const TakeSeat());
    await server.until(tester, () => own.mySeat != null, 'seated');
    final table = await tableOf(tester, server, own, withManualSolves(solves), () => own.send(const StartGame()));
    await tester.pumpWidget(MaterialApp(home: TableScreen.online(controller: table, ownsController: false)));
    const bot = 1;

    // Ann checks or calls; the solves before the flop finish as they start, the flop's never.
    bool botOnFlop() => table.view.board.length == 3 && table.view.actingSeat == bot && !table.handOver;
    void preflopSolves() {
      for (final s in [...solves.pending]) {
        if (s.kind != SolveKind.street) s.complete();
      }
    }

    for (var i = 0; !botOnFlop(); i++) {
      expect(i, lessThan(20000), reason: 'never: the bot to act on the flop');
      preflopSolves();
      if (table.heroOptions != null) {
        final move = table.heroOptions!.canCheck ? const PlayerAction.check() : const PlayerAction.call();
        await table.heroAct(move);
      }
      if (table.handOver) solves.completeAll();
      await tick(tester, server);
    }
    final acts = sentOf(server, 0, 'botAct').length;
    final waited = await tickUntil(tester, server, () => sentOf(server, 0, 'botAct').length > acts, 'the bot acts');
    expect(solves.pending.where((s) => s.kind == SolveKind.street), isNotEmpty, reason: "the flop's solve is held");
    expect(waited, greaterThanOrEqualTo(Playback.botThink + Playback.botBudget - step * 3));
    expect(waited, lessThanOrEqualTo(Playback.botThink + Playback.botBudget + step * 3));
    // The flop is solved after all; the session follows the bot's move on to the turn, on the solved lines.
    await tickUntil(tester, server, () {
      solves.completeAll();
      if (table.heroOptions != null) {
        unawaited(table.heroAct(table.heroOptions!.canCheck ? const PlayerAction.check() : const PlayerAction.call()));
      }
      return table.handOver || table.session.hand!.street.index > Street.flop.index;
    }, 'past the flop');
    expect(table.session.postflop?.unavailable, isNot(NoAnswer.leftSolvedLines));
    await close(tester, server, [table]);
  });

  testWidgets("the host's device solves nothing in time (its whole game is held): its bots' moves keep the hand on "
      "the solved lines, so a guest with help gets GTO's answer at each of their decisions before the flop",
      (tester) async {
    setScreen(tester, const Size(1280, 900));
    final server = TestServer(seed: 9);
    final held = ManualSolves();
    final own = server.client();
    await server.open(
      tester,
      own,
      const CreateRoom(
        name: 'Ann',
        game: holdemKey,
        settings: RoomSettings(seats: 4, stackBb: 30, resetStacks: true, help: HelpLevel.simple),
        bots: {0: 'gto', 1: 'tag', 2: 'lag'},
      ),
    );
    final ben = server.client();
    await server.open(tester, ben, JoinRoom(code: own.room!.code, name: 'Ben'));
    ben.send(const TakeSeat());
    await server.until(tester, () => ben.mySeat != null, 'Ben seated');
    // Ann watches; her device plays the bots, Ben's works out his help.
    NextHand? bensFirst;
    ben.attach((m) => bensFirst ??= m is NextHand ? m : null);
    final host = await tableOf(tester, server, own, withManualSolves(held), () => own.send(const StartGame()));
    await server.until(tester, () => bensFirst != null, "Ben's first hand");
    ben.detach();
    final guest = OnlineTableController(ben, bensFirst!, speed: PlaybackSpeed.instant, solutions: testSolutions());
    await tester.pumpWidget(MaterialApp(home: TableScreen.online(controller: guest, ownsController: false)));
    expect(host.spectating, isTrue);

    var answered = 0, afterBots = 0;
    while (guest.handNumber < 6 || !guest.handOver) {
      await tick(tester, server, const Duration(milliseconds: 50));
      expect(server.clock.nowMs, lessThan(300000), reason: 'the game stalled');
      if (guest.heroOptions == null || guest.heroScore != null) {
        if (guest.heroScore != null) await guest.continueHand();
        continue;
      }
      if (guest.answerPending) continue;
      final hand = guest.session.hand!;
      if (hand.street == Street.preflop) {
        expect(guest.heroSpot, isNotNull,
            reason: 'hand ${guest.handNumber}: ${guest.answerNone} after ${hand.log.whereType<ActionTaken>().toList()}');
        answered++;
        if (hand.log.whereType<ActionTaken>().any((a) => a.seat != 0 && a.kind != ActionKind.fold)) afterBots++;
      }
      await guest.playGraded(passive(guest));
    }
    expect(held.started.where((s) => s.done), isEmpty, reason: "the host's device solved nothing");
    expect(answered, greaterThanOrEqualTo(4));
    expect(afterBots, greaterThan(0), reason: 'some answers came after a bot called or raised');
    host.handBack();
    await close(tester, server, [host, guest]);
  });

  final show = find.byKey(const ValueKey('show gto'));
  final solving = find.byKey(const ValueKey('solving'));
  Finder quick(String name) => find.byKey(ValueKey('quick $name'));
  Finder gtoOn(String name) => find.byKey(ValueKey('${ValueKey('quick $name')} gto'));
  bool lit(WidgetTester tester) => find.descendant(of: show, matching: find.byIcon(Icons.visibility_off)).evaluate().isNotEmpty;

  /// Whether [button] takes taps: enabled, and nothing over it ignores or
  /// absorbs them or greys it out.
  void expectWorks(WidgetTester tester, Finder button) {
    final widget = tester.widget(button);
    final onPressed = switch (widget) {
      final ButtonStyleButton b => b.onPressed,
      final IconButton b => b.onPressed,
      _ => throw ArgumentError('$widget'),
    };
    expect(onPressed, isNotNull, reason: '$button is greyed out');
    expect(
      find.ancestor(
        of: button,
        matching: find.byWidgetPredicate((w) =>
            (w is IgnorePointer && w.ignoring) || (w is AbsorbPointer && w.absorbing) || (w is Opacity && w.opacity < 1)),
      ),
      findsNothing,
      reason: '$button is held',
    );
  }

  /// The user's choice buttons the hand allows now (Fold is greyed out
  /// when checking is free), and Show GTO.
  List<Finder> buttons(TableController c) => [
        if (c.heroMenu!.any((a) => a.kind == SpotActionKind.fold && a.available)) quick('fold'),
        quick('call'),
        if (c.heroOptions!.canRaise) quick('raise'),
        show,
      ];

  testWidgets('online, Show GTO pressed before the answer holds nothing up: it lights, its solve comes first, the '
      'answer shows when it lands and only then is everyone told; pressed again it stops waiting, and a move made '
      'meanwhile is sent at once and graded later', (tester) async {
    setScreen(tester, const Size(1280, 900));
    final server = TestServer(seed: 4);
    final solves = ManualSolves();
    final own = server.client(record: true);
    await server.open(
      tester,
      own,
      const CreateRoom(
        name: 'Ann',
        game: holdemKey,
        settings: RoomSettings(seats: 2, stackBb: 40, resetStacks: true, help: HelpLevel.simple),
      ),
    );
    own.send(const TakeSeat());
    await server.until(tester, () => own.mySeat != null, 'seated');
    // Cy checks or calls, on another device: no bot on Ann's to lift her solves.
    final cy = AutoGuest(server, 'Cy', think: const Duration(milliseconds: 300))..join(own.room!.code);
    await server.until(tester, () => cy.room != null, 'Cy in');
    cy.send(const TakeSeat());
    await server.until(tester, () => cy.room?.me?.seat != null, 'Cy seated');
    final table = await tableOf(tester, server, own, withManualSolves(solves), () => own.send(const StartGame()));
    await tester.pumpWidget(MaterialApp(home: TableScreen.online(controller: table, ownsController: false)));

    // Ann's first decision, with nothing solved (the hand's whole game is held).
    await tickUntil(tester, server, () => table.heroOptions != null, 'her turn', max: 20000);
    await tester.pump();
    final hand = table.handNumber;
    expect(table.answerPending, isTrue);
    expect(solving, findsOneWidget);
    expect(solves.pending.single.owner?.hand, hand);
    expect(solves.pending.single.owner?.floor.index, greaterThan(SolvePriority.shown.index));
    for (final button in buttons(table)) {
      expectWorks(tester, button);
    }
    await tester.tap(show);
    await tester.pump();
    expect(lit(tester), isTrue);
    expect(solves.pending.single.owner?.floor, SolvePriority.shown, reason: "the hand's solves come first");
    for (final button in buttons(table)) {
      expectWorks(tester, button);
    }
    expect(tester.widget<Slider>(find.byKey(const ValueKey('raise slider'))).onChanged, isNotNull);
    expect(sentOf(server, 0, 'usedHelp'), isEmpty, reason: 'nothing shown yet');
    // The answer lands while Ann still chooses: GTO's percentages go on the buttons, and everyone is told.
    while (table.answerPending) {
      solves.completeAll();
      await tick(tester, server);
    }
    await tester.pump();
    expect(table.heroSpot, isNotNull);
    expect(solving, findsNothing);
    expect(gtoOn('call'), findsOneWidget);
    expect(sentOf(server, 0, 'usedHelp').map((m) => (m as UsedHelp).hand), [hand]);
    await tester.tap(quick('call'));
    await tester.pump();

    // A later decision of hers before its answer: Show GTO on, then off again, then she calls (or checks).
    await tickUntil(tester, server, () => table.heroOptions != null && table.answerPending, 'another turn, its answer held',
        max: 20000);
    await tester.pump();
    final turnHand = table.handNumber;
    // Show GTO at her first decision was for that one: her answer came, and its claim ended with it.
    final owner = solves.only.owner!;
    expect(lit(tester), isFalse, reason: 'out at this decision');
    expect(owner.floor, SolvePriority.ahead, reason: "nobody asked for this answer: the hand's solves keep their own "
        'priority');
    await tester.tap(show);
    await tester.pump();
    expect(owner.floor, SolvePriority.shown, reason: "on: the hand's solves come first");
    await tester.tap(show);
    await tester.pump();
    expect(lit(tester), isFalse);
    expect(owner.floor, SolvePriority.ahead, reason: 'off: back to their own priority');
    final helped = sentOf(server, 0, 'usedHelp').length, acts = sentOf(server, 0, 'act').length;
    await tester.tap(quick('call'));
    await tester.pump();
    expect(sentOf(server, 0, 'act'), hasLength(acts + 1), reason: 'sent at once');
    // Graded once the answer comes (her record of that hand has the decision, with its turn).
    final decisions = table.session.history.where((r) => r.handNumber == turnHand).single.decisions.length;
    await tickUntil(tester, server, () {
      solves.completeAll();
      return table.session.history.where((r) => r.handNumber == turnHand).single.decisions.length > decisions ||
          table.handNumber > turnHand;
    }, 'the grade');
    final record = table.session.history.where((r) => r.handNumber == turnHand).single;
    expect(record.decisions, hasLength(decisions + 1), reason: 'graded before the next hand was dealt');
    expect(record.decisions.last.turnId, isNotNull);
    expect(sentOf(server, 0, 'usedHelp'), hasLength(helped), reason: "the answer wasn't shown: nobody is told");
    await close(tester, server, [table]);
  });

  testWidgets("online, the next hand's guess (the user's first decision if everyone folds to them) is let go of once "
      'a bot before the user raises: Show GTO then lifts only the real decision', (tester) async {
    setScreen(tester, const Size(1280, 900));
    final server = TestServer(seed: 1);
    final solves = ManualSolves(auto: true);
    final solutions = withManualSolves(solves);
    final own = server.client(record: true);
    await server.open(
      tester,
      own,
      const CreateRoom(
        name: 'Ann',
        game: holdemKey,
        settings: RoomSettings(seats: 3, stackBb: 40, resetStacks: true, help: HelpLevel.simple),
        bots: {1: 'tag', 2: 'tag'},
      ),
    );
    own.send(const TakeSeat());
    await server.until(tester, () => own.mySeat != null, 'seated');
    final table = await tableOf(tester, server, own, solutions, () => own.send(const StartGame()));
    await tester.pumpWidget(MaterialApp(home: TableScreen.online(controller: table, ownsController: false)));

    // From Ann's first decision on, something else holds the solver (another job of this device), so each next
    // hand's guess stays queued.
    await tickUntil(tester, server, () => table.heroOptions != null, 'her first turn', max: 20000);
    final blocker = Completer<void>();
    unawaited(solutions.queue.add('blocker', () => blocker.future, priority: SolvePriority.bot));
    await tester.pump();
    solves.auto = false;
    final from = table.handNumber;
    // Ann checks or calls until a hand where a bot before her raised (the bots wait for the hand's solves, claiming
    // them meanwhile, then play a move on the solved lines).
    var found = false;
    for (var i = 0; i < 40000 && !found && table.handNumber <= from + 2; i++) {
      if (table.heroOptions != null && table.heroScore == null) {
        final h = table.hand!;
        final before = h.log.whereType<ActionTaken>().where((e) => e.street == Street.preflop);
        // Not in the big blind (last to act): her hand had a guess.
        final bigBlind = h.log.whereType<BlindPosted>().any((e) => e.isBigBlind && e.seat == 0);
        // The two hands after it (the third has the same stacks and button as the first: solved already).
        if (table.handNumber > from &&
            table.handNumber <= from + 2 &&
            !bigBlind &&
            h.street == Street.preflop &&
            before.isNotEmpty &&
            before.every((e) => e.seat != 0) &&
            before.any((e) => e.kind != ActionKind.fold)) {
          found = true;
          break;
        }
        await table.playGraded(passive(table));
      }
      await tick(tester, server);
    }
    expect(found, isTrue, reason: 'a hand where a bot before Ann raised');
    final hand = table.handNumber;
    final started = solves.started.length;
    // Ann presses Show GTO; the solver is free again. Her decision is solved before anything of lower priority, and
    // the guess her hand has passed never is.
    table.wantAnswerShown();
    blocker.complete();
    for (var i = 0; i < 100 && table.answerPending; i++) {
      await tester.pump();
      if (solves.pending.isNotEmpty) solves.pending.first.complete();
      await tester.pump();
    }
    expect(table.heroSpot, isNotNull, reason: 'her answer came');
    final guesses = [
      for (final p in solves.started.skip(started))
        if (p.kind == SolveKind.whole && p.owner?.hand == hand && p.preflop.hero >= 0) p,
    ];
    expect(guesses, isEmpty, reason: 'the guess for her first decision was let go of, not solved');
    solves
      ..auto = true
      ..completeAll();
    await close(tester, server, [table]);
  });

  testWidgets("the host leaves the table while its GTO bot's flop solve waits its turn: its dropped solve fails "
      'quietly', (tester) async {
    setScreen(tester, const Size(1280, 900));
    for (final seed in [5, 6, 7, 8, 9, 10, 11]) {
      final server = TestServer(seed: seed);
      final solves = ManualSolves();
      final solutions = withManualSolves(solves);
      final own = server.client(record: true);
      await server.open(
        tester,
        own,
        const CreateRoom(
          name: 'Ann',
          game: holdemKey,
          settings: RoomSettings(seats: 2, stackBb: 40, resetStacks: true),
          bots: {1: 'gto'},
        ),
      );
      own.send(const TakeSeat());
      await server.until(tester, () => own.mySeat != null, 'seated');
      final table = await tableOf(tester, server, own, solutions, () => own.send(const StartGame()));
      await tester.pumpWidget(MaterialApp(home: TableScreen.online(controller: table, ownsController: false)));

      Completer<void>? blocker;
      var found = false;
      for (var i = 0; i < 20000; i++) {
        if (blocker == null) solves.completeAll();
        final h = table.session.hand;
        final options = table.heroOptions;
        final caughtUp = h != null &&
            h.handNumber == table.handNumber &&
            solves.pending.isEmpty &&
            solutions.queue.queued.isEmpty &&
            solutions.queue.running.isEmpty;
        if (options != null) {
          final flopActions = h == null ? -1 : h.log.whereType<ActionTaken>().where((e) => e.street == Street.flop).length;
          if (blocker != null && table.view.board.length == 3 && flopActions == 0 && solutions.queue.queued.isNotEmpty) {
            found = true;
            break;
          }
          // Ann's move before the flop, everything solved: from here something else takes the solver, so the
          // flop's solve, if her move closes the betting, waits its turn.
          if (blocker == null && caughtUp && h.street == Street.preflop && h.toAct == 0) {
            final b = blocker = Completer<void>();
            unawaited(solutions.queue.add('blocker', () => b.future, priority: SolvePriority.bot));
            await tester.pump();
          }
          await table.heroAct(options.canCheck ? const PlayerAction.check() : const PlayerAction.call());
        }
        if (table.handOver && blocker != null) {
          blocker.complete();
          blocker = null;
        }
        await tick(tester, server);
      }
      if (!found) {
        await tester.pumpWidget(const SizedBox());
        table.dispose();
        blocker?.complete();
        solves
          ..auto = true
          ..completeAll();
        await server.wait(tester, const Duration(seconds: 2));
        continue;
      }
      // Ann (first to act on the flop) leaves; nobody waits for the flop's solve yet.
      await tester.pumpWidget(const SizedBox());
      table.dispose();
      await server.wait(tester, const Duration(seconds: 1));
      blocker!.complete();
      solves
        ..auto = true
        ..completeAll();
      await server.wait(tester, const Duration(seconds: 2));
      return;
    }
    fail('no seed put Ann first on the flop with its solve queued');
  });

  testWidgets("at hand over, the next hand's whole game goes before what is left of the last hand, though the "
      "host's GTO bot waited for it", (tester) async {
    setScreen(tester, const Size(1280, 900));
    final server = TestServer(seed: 5);
    final solves = ManualSolves();
    final solutions = withManualSolves(solves);
    final own = server.client(record: true);
    // Free Play: only the host's GTO bot needs solves. Stacks carry over, so each hand's whole game is a new one.
    await server.open(
      tester,
      own,
      const CreateRoom(name: 'Ann', game: holdemKey, settings: RoomSettings(seats: 2, stackBb: 40), bots: {1: 'gto'}),
    );
    own.send(const TakeSeat());
    await server.until(tester, () => own.mySeat != null, 'seated');
    final table = await tableOf(tester, server, own, solutions, () => own.send(const StartGame()), random: Random(1));
    await tester.pumpWidget(MaterialApp(home: TableScreen.online(controller: table, ownsController: false)));

    // Ann checks or calls. Everything is solved as it starts until a hand's turn is; from its river on something
    // else holds the solver (another job of this device), so the river's solve waits its turn.
    Completer<void>? blocker;
    var hand = 0;
    for (var i = 0; blocker == null || !table.handOver || table.handNumber != hand; i++) {
      expect(i, lessThan(40000), reason: 'never: a hand to the river with its solve queued');
      if (blocker == null) solves.completeAll();
      final h = table.session.hand;
      if (blocker == null &&
          h != null &&
          h.handNumber == table.handNumber &&
          h.board.length == 4 &&
          solves.pending.isEmpty &&
          solutions.queue.queued.isEmpty &&
          solutions.queue.running.isEmpty) {
        blocker = Completer<void>();
        unawaited(solutions.queue.add('blocker', () => blocker!.future, priority: SolvePriority.bot));
        hand = table.handNumber;
      }
      if (table.heroOptions != null) {
        await table.heroAct(table.heroOptions!.canCheck ? const PlayerAction.check() : const PlayerAction.call());
      }
      await tick(tester, server);
    }
    expect(table.view.board, hasLength(5), reason: 'the hand went to the river');
    // The next hand is announced: the session asks for its whole game.
    await tickUntil(tester, server, () => solutions.queue.queued.length >= 2, "the next hand's game asked for");
    expect(table.handNumber, hand, reason: 'not dealt yet');
    blocker.complete();
    await tester.pump();
    await tester.pump();
    expect(solves.only.kind, SolveKind.whole, reason: "the next hand's game first: ${solves.only}");
    expect(solves.only.owner?.hand, hand + 1);
    solves
      ..auto = true
      ..completeAll();
    await close(tester, server, [table]);
  });

  testWidgets("a spectator's coach: its hand's solves come first, as for Show GTO", (tester) async {
    setScreen(tester, const Size(1280, 900));
    final server = TestServer();
    final solves = ManualSolves();
    final own = server.client();
    await server.open(
      tester,
      own,
      const CreateRoom(name: 'Ann', game: holdemKey, settings: RoomSettings(seats: 3, stackBb: 20, resetStacks: true)),
    );
    for (final name in ['Cy', 'Di']) {
      final guest = AutoGuest(server, name, think: const Duration(seconds: 1))..join(own.room!.code);
      await server.until(tester, () => guest.room != null, '$name in');
      guest.send(const TakeSeat());
      await server.until(tester, () => guest.room?.me?.seat != null, '$name seated');
    }
    final table = await tableOf(tester, server, own, withManualSolves(solves), () => own.send(const StartGame()));
    await tester.pumpWidget(MaterialApp(home: TableScreen.online(controller: table, ownsController: false)));
    await server.until(tester, () => table.handNumber > 0, 'the first deal');
    expect(table.spectating, isTrue);
    expect(solves.pending, isEmpty, reason: 'the coach is off: nothing to solve');
    table.setCoach(true);
    // From the next hand: its whole game, before anything else.
    final now = table.handNumber;
    await server.until(tester, () => table.handNumber > now && solves.pending.isNotEmpty, 'the next hand, solving');
    expect(solves.pending.single.kind, SolveKind.whole);
    expect(solves.pending.single.owner!.hand, table.handNumber);
    expect(solves.pending.single.owner!.floor, SolvePriority.shown);
    // Its streets too, once the hand gets there.
    await server.until(tester, () {
      solves.completeAll();
      return solves.started.any((s) => s.kind == SolveKind.street && s.owner?.hand == table.handNumber) ||
          table.handOver;
    }, 'a street or the end');
    for (final s in solves.started.where((s) => s.owner?.hand == table.handNumber)) {
      expect(s.owner!.floor, SolvePriority.shown, reason: '$s');
    }
    table.handBack();
    await close(tester, server, [table]);
  });
}
