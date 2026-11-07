import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/bots/bot.dart';
import 'package:pokerfection/src/engine/actions.dart';
import 'package:pokerfection/src/engine/events.dart';
import 'package:pokerfection/src/engine/poker_hand.dart';
import 'package:pokerfection/src/engine/positions.dart';
import 'package:pokerfection/src/game/table_session.dart';
import 'package:pokerfection/src/gto/gto_solutions.dart';
import 'package:pokerfection/src/gto/spot_strategy.dart';
import 'package:pokerfection/src/ui/table_controller.dart';
import 'package:pokerfection/src/ui/table_screen.dart';

import '../gto/manual_solves.dart';

/// A hand's solves come sooner only while there is a reason: while a bot
/// waits for them, while Show GTO is on. Each claim ends with its reason,
/// and every one at hand over, so what is left of a hand (its grades) goes
/// after the next hand's whole game, as the order bot > shown > nextHand >
/// grade says. Solves finish when each test says (ManualSolves).
void main() {
  const step = Duration(milliseconds: 10);

  Future<void> pumpUntil(WidgetTester tester, bool Function() done, {int max = 3000}) async {
    for (var i = 0; i < max && !done(); i++) {
      await tester.pump(step);
    }
    expect(done(), isTrue);
  }

  int passive(TableController c) =>
      c.heroMenu!.indexWhere((a) => a.kind == SpotActionKind.check || a.kind == SpotActionKind.call);

  int actions(TableController c) => c.hand!.log.whereType<ActionTaken>().length;

  /// Holds the solver with a job of this device's own (another table, say)
  /// until the test completes it.
  Completer<void> hold(GtoSolutions solutions) {
    final blocker = Completer<void>();
    unawaited(solutions.queue.add('blocker', () => blocker.future, priority: SolvePriority.bot));
    return blocker;
  }

  /// Work more urgent than a grade, less than a bot or Show GTO (as the
  /// next hand's whole game is), with no hand of its own. Says whether it
  /// has started.
  bool Function() addNextHandWork(GtoSolutions solutions) {
    var started = false;
    unawaited(solutions.queue.add('next hand', () async => started = true, priority: SolvePriority.nextHand));
    return () => started;
  }

  testWidgets("at hand over, the next hand's whole game goes before the last hand's grades, though a bot waited "
      'in that hand', (tester) async {
    final solves = ManualSolves();
    final solutions = withManualSolves(solves);
    // Some deals have the bot fold before the flop: the first that reaches the river is played.
    for (var seed = 1; seed < 40; seed++) {
      final c = TableController(
        TableConfig.quick(playerCount: 2, heroPosition: Position.bb, guessGto: true, opponentStyle: BotStyle.tag),
        random: Random(seed),
        solutions: solutions,
      )
        // Before the flop the bot decides, waiting for its hand's solves as in play; after it, it checks or calls.
        ..scriptedBots = (PokerHand hand, int seat) {
          if (hand.street == Street.preflop) return null;
          final legal = hand.legalActions();
          return legal.canCheck ? const PlayerAction.check() : const PlayerAction.call();
        };
      unawaited(c.startNextHand());
      Completer<void>? blocker;
      for (var i = 0; !c.handOver && i < 4000; i++) {
        // Every answer comes at once until the turn; from then on something else holds the solver.
        if (blocker == null) solves.completeAll();
        if (c.heroScore != null) unawaited(c.continueHand());
        if (c.heroOptions != null && c.heroScore == null && (!c.answerPending || c.hand!.street == Street.river)) {
          if (c.hand!.street == Street.turn) blocker ??= hold(solutions);
          // On the river the user plays before the answer comes: graded once it does.
          unawaited(c.playGraded(passive(c)));
        }
        await tester.pump(step);
      }
      await tester.pump(const Duration(seconds: 3));
      if (c.hand!.board.length < 5 || blocker == null) {
        blocker?.complete();
        solves.completeAll();
        await tester.pump(const Duration(seconds: 3));
        c.dispose();
        solves.completeAll();
        await tester.pump(const Duration(seconds: 3));
        continue;
      }
      expect(c.gradesPending, isTrue, reason: "the river's grade is still to come");
      expect(c.followers.last.owner.floor, SolvePriority.ahead, reason: "the hand's claims ended with it");
      expect(solutions.queue.queued, hasLength(greaterThanOrEqualTo(2)), reason: "the river and the next hand's game");
      blocker.complete();
      await tester.pump();
      await tester.pump();
      expect(solves.only.kind, SolveKind.whole, reason: "the next hand's game goes first, then the last hand's grade");
      expect(solves.only.owner?.hand, c.hand!.handNumber + 1);
      solves.completeAll();
      await tester.pump(const Duration(seconds: 3));
      solves.completeAll();
      await tester.pump(const Duration(seconds: 3));
      c.dispose();
      await tester.pump(const Duration(seconds: 3));
      return;
    }
    fail('no seed reached the river');
  });

  testWidgets("two bots wait for the hand's solves one after the other, then play their fallbacks: the claim of "
      "each lasts as long as its wait, then the hand's solves are back to their own priority", (tester) async {
    final solves = ManualSolves();
    final solutions = withManualSolves(solves);
    // Three-handed, the user on the button acts first; both blinds are bots that play from the user's subgame.
    final c = TableController(
      TableConfig.quick(playerCount: 3, heroPosition: Position.btn, guessGto: true, opponentStyle: BotStyle.tag),
      random: Random(1),
      solutions: solutions,
    );
    unawaited(c.startNextHand());
    await tester.pump();
    expect(solves.only.kind, SolveKind.whole);
    // The solver is taken (another job of this device) once the whole game is in: the user's subgame waits.
    final blocker = hold(solutions);
    solves.only.complete();
    await pumpUntil(tester, () => c.heroOptions != null);
    await tester.pump();
    expect(c.answerPending, isTrue);
    expect(solutions.queue.queued, hasLength(1), reason: "the user's subgame waits");
    final owner = c.followers.last.owner;
    expect(owner.floor, SolvePriority.ahead, reason: 'nobody waits for it yet');
    final nextStarted = addNextHandWork(solutions);
    await tester.pump();
    expect(solutions.queue.queued.first, 'next hand');

    // The user calls before the answer comes; the small blind's reply comes from that subgame.
    unawaited(c.playGraded(passive(c)));
    await tester.pump();
    for (final seat in [1, 2]) {
      final before = actions(c);
      await pumpUntil(tester, () => owner.floor == SolvePriority.bot);
      expect(actions(c), before, reason: 'seat $seat waits');
      expect(c.view.actingSeat, seat);
      expect(solutions.queue.queued.last, 'next hand', reason: "while seat $seat waits, its hand's solves go first");
      // Its budget runs out: it plays its fallback, and its claim ends while the hand goes on.
      await pumpUntil(tester, () => actions(c) > before);
      expect(c.hand!.isOver, isFalse);
      expect(owner.floor, SolvePriority.ahead, reason: 'seat $seat has moved');
      expect(solutions.queue.queued.first, 'next hand', reason: "the user's subgame is a grade again");
    }
    expect(solves.pending, isEmpty, reason: 'nothing of the hand has started: the solver is still taken');
    blocker.complete();
    await pumpUntil(tester, () => solves.pending.isNotEmpty);
    expect(nextStarted(), isTrue, reason: '"next hand" went first');
    expect(solves.only.kind, SolveKind.whole, reason: "then the user's subgame (with no ranges, a whole game)");
    solves.auto = true;
    solves.completeAll();
    await tester.pump(const Duration(seconds: 5));
    c.dispose();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets("Show GTO pressed at the user's first decision lifts nothing once that decision is over: when the "
      "user folds at a later one, before its answer, the next hand's whole game goes before that grade",
      (tester) async {
    for (var seed = 1; seed < 200; seed++) {
      // Each deal its own solutions: nothing solved for an earlier one.
      final solves = ManualSolves();
      final solutions = withManualSolves(solves);
      // Four-handed, stacks reset each hand: the next hand's game is asked for once the user is out of the hand.
      final c = TableController(
        TableConfig(
          // One bot shorter than the rest: the next hand's game (the button moved) is a new one.
          players: [
            for (final (i, p) in TableConfig.quickPlayers(count: 4, stackBb: 300, style: BotStyle.tag).indexed)
              PlayerInfo(name: p.name, stackBb: i == 1 ? 150 : 300, style: p.style, isHero: p.isHero),
          ],
          guessGto: true,
          resetStacksEachHand: true,
        ),
        random: Random(seed),
        solutions: solutions,
      )..scriptedBots = (PokerHand hand, int seat) {
          final legal = hand.legalActions();
          final raises = hand.log.whereType<ActionTaken>().where((a) => a.kind == ActionKind.raise).length;
          // The first bot after the user's open plays from the user's subgame (it may 3-bet); the others call or
          // check.
          if (hand.street == Street.preflop && raises == 1) return null;
          // Before the user opens, the bots fold to them (always on the solved lines).
          if (hand.street == Street.preflop && raises == 0 && !legal.canCheck) return const PlayerAction.fold();
          return legal.canCheck ? const PlayerAction.check() : const PlayerAction.call();
        };
      Completer<void>? blocker;
      // Lets everything finish, and puts this deal away.
      Future<void> next() async {
        if (blocker case final b? when !b.isCompleted) b.complete();
        solves.auto = true;
        solves.completeAll();
        await tester.pump(const Duration(seconds: 5));
        c.dispose();
        await tester.pump(const Duration(seconds: 3));
        solves.auto = false;
      }

      unawaited(c.startNextHand());
      await tester.pump();
      for (var i = 0; i < 1000 && c.heroOptions == null; i++) {
        // The blueprint (the bots before the user play from it), not the user's subgame.
        for (final s in [...solves.pending]) {
          if (s.priority == SolvePriority.bot) s.complete();
        }
        await tester.pump(step);
      }
      if (!c.answerPending) {
        await next();
        continue;
      }
      expect(c.answerPending, isTrue, reason: "the user's first subgame is on its way");
      final owner = c.followers.last.owner;
      // Show GTO before the answer came (what the panel calls): it shows when it does.
      c.wantAnswerShown(true);
      expect(owner.floor, SolvePriority.shown);
      for (var i = 0; i < 300 && c.heroSpot == null; i++) {
        solves.completeAll();
        await tester.pump(step);
      }
      final raise = c.heroMenu!.indexWhere((a) => a.kind == SpotActionKind.raise);
      if (raise < 0) {
        await next();
        continue;
      }
      // The user opens; something else of this device holds the solver from the bot's reply on.
      unawaited(c.playGraded(raise));
      for (var i = 0; i < 300 && c.heroOptions != null; i++) {
        if (c.heroScore != null) unawaited(c.continueHand());
        await tester.pump(step);
      }
      blocker = Completer<void>();
      unawaited(solutions.queue.add('blocker', () => blocker!.future, priority: SolvePriority.bot));
      for (var i = 0; i < 500 && c.heroOptions == null && !c.hand!.isOver; i++) {
        await tester.pump(step);
      }
      if (c.heroOptions == null || !c.answerPending) {
        await next();
        continue;
      }
      // A decision of its own: the panel has put Show GTO out (decision_panel.dart, "Show GTO pressed at the
      // last one is for that one"). The user folds before the answer comes: graded when it does. The bots play on.
      final fold = c.heroMenu!.indexWhere((a) => a.kind == SpotActionKind.fold);
      unawaited(c.playGraded(fold));
      for (var i = 0; i < 50; i++) {
        await tester.pump(step);
      }
      if (c.hand!.isOver) {
        await next();
        continue;
      }
      expect(c.gradesPending, isTrue);
      final queued = [for (final k in solutions.queue.queued) '${solutions.queue.priorityOf(k)?.name}'];
      blocker.complete();
      await tester.pump();
      await tester.pump();
      expect(solves.only.kind, SolveKind.whole,
          reason: "the user is out of the hand and nobody waits for that decision's answer: the next hand's game goes "
              "before the user's grade; started ${solves.only}, floor ${owner.floor}, queued $queued");
      await next();
      return;
    }
    fail('no seed had the user fold at a second decision with the hand going on');
  });

  group('Show GTO', () {
    final show = find.byKey(const ValueKey('show gto'));

    /// Heads-up training against a bot that calls or checks, the user in
    /// the big blind, at their first decision with its subgame waiting
    /// behind another job (and work for the next hand behind it).
    Future<(TableController, ManualSolves, Completer<void>, bool Function(), GtoSolutions)> atDecision(
        WidgetTester tester) async {
      final solves = ManualSolves();
      final solutions = withManualSolves(solves);
      final c = TableController(
        TableConfig.quick(playerCount: 2, heroPosition: Position.bb, guessGto: true, opponentStyle: BotStyle.tag),
        random: Random(1),
        solutions: solutions,
      )..scriptedBots = (PokerHand hand, int seat) {
          final legal = hand.legalActions();
          return legal.canCheck ? const PlayerAction.check() : const PlayerAction.call();
        };
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: TableScreen(config: c.session.config, controller: c)));
      await tester.pump();
      final blocker = hold(solutions);
      solves.only.complete();
      await pumpUntil(tester, () => c.heroOptions != null);
      await tester.pump();
      expect(c.answerPending, isTrue);
      final nextStarted = addNextHandWork(solutions);
      await tester.pump();
      expect(solutions.queue.queued, hasLength(2));
      expect(solutions.queue.queued.first, 'next hand', reason: "the user's subgame is asked for as a grade");
      return (c, solves, blocker, nextStarted, solutions);
    }

    Future<void> close(WidgetTester tester, TableController c, ManualSolves solves, Completer<void> blocker) async {
      if (!blocker.isCompleted) blocker.complete();
      solves.auto = true;
      solves.completeAll();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    }

    testWidgets("on, the hand's solves come first; off again before the answer came, they are back to their own "
        'priority', (tester) async {
      final (c, solves, blocker, nextStarted, _) = await atDecision(tester);
      final owner = c.followers.last.owner;
      await tester.tap(show);
      await tester.pump();
      expect(owner.floor, SolvePriority.shown);
      await tester.tap(show);
      await tester.pump();
      expect(owner.floor, SolvePriority.ahead);
      blocker.complete();
      await pumpUntil(tester, () => solves.pending.isNotEmpty);
      expect(solves.only.owner, owner);
      expect(nextStarted(), isTrue, reason: "the next hand's work went first: the user's subgame is a grade again");
      await close(tester, c, solves, blocker);
    });

    testWidgets('on before the answer came, the claim ends when the answer comes: nobody waits for it any more',
        (tester) async {
      final (c, solves, blocker, nextStarted, _) = await atDecision(tester);
      final owner = c.followers.last.owner;
      await tester.tap(show);
      await tester.pump();
      expect(owner.floor, SolvePriority.shown);
      blocker.complete();
      await pumpUntil(tester, () => solves.pending.isNotEmpty);
      expect(solves.only.owner, owner);
      expect(nextStarted(), isFalse, reason: "the user's subgame goes before the next hand's work");
      solves.only.complete();
      await tester.pump();
      await tester.pump();
      expect(c.heroSpot, isNotNull, reason: 'the answer shows');
      expect(owner.floor, SolvePriority.ahead, reason: 'the answer came');
      await tester.tap(show);
      await tester.pump();
      expect(owner.floor, SolvePriority.ahead, reason: 'Show GTO is off: nothing changes');
      await close(tester, c, solves, blocker);
    });

    testWidgets('pressed at one decision, it lifts nothing at the next, where it is out until pressed again',
        (tester) async {
      final (c, solves, blocker, _, solutions) = await atDecision(tester);
      final owner = c.followers.last.owner;
      await tester.tap(show);
      await tester.pump();
      expect(owner.floor, SolvePriority.shown);
      blocker.complete();
      await pumpUntil(tester, () => solves.pending.any((s) => s.owner == owner));
      solves.pending.singleWhere((s) => s.owner == owner).complete();
      await tester.pump();
      await tester.pump();
      expect(c.heroSpot, isNotNull, reason: 'the answer shows');
      // The solver is taken again before the flop's street is asked for; the user checks.
      final second = hold(solutions);
      await tester.pump();
      unawaited(c.playGraded(passive(c)));
      await pumpUntil(tester, () {
        if (c.heroScore != null) unawaited(c.continueHand());
        return c.heroOptions != null && c.hand!.street == Street.flop;
      });
      await tester.pump();
      expect(c.answerPending, isTrue, reason: "the flop's answer waits behind the other job");
      expect(find.descendant(of: show, matching: find.byIcon(Icons.visibility)), findsOneWidget,
          reason: 'Show GTO is out at this decision');
      final nextStarted = addNextHandWork(solutions);
      await tester.pump();
      expect(owner.floor, SolvePriority.ahead, reason: 'nobody asked for this answer');
      expect(solutions.queue.queued.first, 'next hand',
          reason: "the flop's street is a grade: the next hand's work goes first");
      await tester.tap(show);
      await tester.pump();
      expect(owner.floor, SolvePriority.shown, reason: 'pressed again at this decision');
      await tester.tap(show);
      await tester.pump();
      expect(owner.floor, SolvePriority.ahead, reason: 'and off again');
      second.complete();
      await pumpUntil(tester, nextStarted);
      await close(tester, c, solves, blocker);
    });
  });
}
