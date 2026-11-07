import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/drills.dart';
import 'package:pokerfection/src/bots/bot.dart';
import 'package:pokerfection/src/engine/actions.dart';
import 'package:pokerfection/src/engine/cards.dart';
import 'package:pokerfection/src/engine/events.dart';
import 'package:pokerfection/src/engine/poker_hand.dart';
import 'package:pokerfection/src/engine/positions.dart';
import 'package:pokerfection/src/game/table_session.dart';
import 'package:pokerfection/src/gto/gto_solutions.dart';
import 'package:pokerfection/src/gto/hand_read.dart';
import 'package:pokerfection/src/gto/preflop/preflop_advisor.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tracker.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tree.dart';
import 'package:pokerfection/src/gto/spot_strategy.dart';
import 'package:pokerfection/src/online/timing.dart';
import 'package:pokerfection/src/ui/history_screen.dart';
import 'package:pokerfection/src/ui/table_controller.dart';
import 'package:pokerfection/src/ui/table_screen.dart';

import '../gto/manual_solves.dart';

/// Play never waits for computation: the hand deals at once, the user's
/// choices work at once, and GTO's answer (and the grade of a move made
/// before it) comes when it is ready, at the decision it belongs to. Show
/// GTO can be pressed meanwhile and holds nothing up. Solves finish when
/// each test says (ManualSolves), with no wall time; the bots' budget is
/// the real one unless a test says otherwise.
void main() {
  const step = Duration(milliseconds: 10);

  Future<void> open(WidgetTester tester, TableController c, {Size size = const Size(1280, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: TableScreen(config: c.session.config, controller: c)));
    await tester.pump();
  }

  /// Leaves the table and lets what is left of its timers run out.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  /// Pumps until [done], and says how long that took.
  Future<Duration> pumpUntil(WidgetTester tester, bool Function() done, {int max = 3000}) async {
    var waited = Duration.zero;
    for (var i = 0; i < max && !done(); i++) {
      await tester.pump(step);
      waited += step;
    }
    expect(done(), isTrue, reason: 'still waiting after $waited');
    return waited;
  }

  /// [move] as the bots' menu has it where [hand] is before the flop.
  PlayerAction onMenu(PokerHand hand, PlayerAction move) =>
      fitToMenu(move, PreflopTree.botMenuAt(PreflopTracker.specAt(hand)), hand.legalActions());

  /// Bots that open with a raise, call a raise and check after the flop
  /// ([folds]: the seats that fold to a raise instead).
  PlayerAction? Function(PokerHand, int) script({Set<int> folds = const {}}) => (hand, seat) {
        final legal = hand.legalActions();
        if (hand.street != Street.preflop) return legal.canCheck ? const PlayerAction.check() : const PlayerAction.call();
        final raised = hand.log.whereType<ActionTaken>().any((e) => e.kind == ActionKind.raise);
        if (!raised) return onMenu(hand, const PlayerAction.raiseTo(250));
        return onMenu(hand, folds.contains(seat) ? const PlayerAction.fold() : const PlayerAction.call());
      };

  /// Heads-up training, the user in the big blind (the bot opens with a
  /// raise, then checks), every solve held.
  TableController headsUp(ManualSolves solves, {bool advanced = false, bool guessGto = true, Drills? drills}) =>
      TableController(
        TableConfig.quick(
          playerCount: 2,
          heroPosition: Position.bb,
          guessGto: guessGto,
          advanced: advanced,
          opponentStyle: BotStyle.gto,
        ),
        random: Random(1),
        solutions: withManualSolves(solves),
        drills: drills,
      )..scriptedBots = script();

  int actions(TableController c) => c.hand!.log.whereType<ActionTaken>().length;

  int choiceOf(TableController c, SpotActionKind kind) => c.heroMenu!.indexWhere((a) => a.kind == kind);

  Finder quick(String name) => find.byKey(ValueKey('quick $name'));
  Finder gtoOn(String name) => find.byKey(ValueKey('${ValueKey('quick $name')} gto'));
  final show = find.byKey(const ValueKey('show gto'));
  final solving = find.byKey(const ValueKey('solving'));

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

  bool lit(WidgetTester tester) => find.descendant(of: show, matching: find.byIcon(Icons.visibility_off)).evaluate().isNotEmpty;

  testWidgets('a hand deals at once, before its whole game is solved; a bot waits for it think + 1 s at most, '
      'and its move keeps the hand on the solved lines', (tester) async {
    final solves = ManualSolves();
    final c = TableController(
      TableConfig.quick(playerCount: 2, heroPosition: Position.bb, guessGto: true, opponentStyle: BotStyle.gto),
      random: Random(1),
      solutions: withManualSolves(solves),
    );
    await open(tester, c);
    expect(c.hand?.handNumber, 1, reason: 'dealt at once');
    expect(solves.only.kind, SolveKind.whole);
    expect(solves.only.priority, SolvePriority.bot);
    expect(find.textContaining(RegExp(r'\d+ ?%')), findsNothing, reason: 'no "Solving… 37%"');
    await pumpUntil(tester, () => c.view.actingSeat == 1);
    expect(c.view.seats[0].cardsHeld, 2, reason: "the user's cards are dealt");
    // The real budget: the bot thinks, waits 1 s more for the whole game, then plays.
    final waited = await pumpUntil(tester, () => actions(c) == 1);
    expect(waited, greaterThanOrEqualTo(Playback.botThink + Playback.botBudget - step * 3));
    expect(waited, lessThanOrEqualTo(Playback.botThink + Playback.botBudget + step * 3));
    expect(c.session.preflop, isNull);
    // The whole game comes: the hand is followed from it, the bot's move included.
    solves.only.complete();
    await tester.pump();
    expect(c.session.preflop, isNotNull);
    expect(c.session.preflop!.rangeOf(c.hand!, 1), isNotNull, reason: 'the bot kept to the solved lines');
    await close(tester);
  });

  testWidgets("the user's choices work at once with no answer yet; Show GTO pressed early holds nothing up, "
      'and the answer shows when it lands', (tester) async {
    final solves = ManualSolves();
    final c = headsUp(solves);
    await open(tester, c);
    solves.only.complete();
    await pumpUntil(tester, () => c.heroOptions != null);
    await tester.pump();
    expect(solves.only.kind, SolveKind.subgame, reason: "the user's decision is being solved");
    expect(c.answerPending, isTrue);
    expect(solving, findsOneWidget);
    expect(find.text('Solving…'), findsOneWidget);
    for (final button in [quick('fold'), quick('call'), quick('raise'), show]) {
      expectWorks(tester, button);
    }
    await tester.tap(show);
    await tester.pump();
    expect(lit(tester), isTrue);
    expect(c.followers.last.owner.floor, SolvePriority.shown, reason: 'solved first');
    expect(solving, findsOneWidget);
    for (final button in [quick('fold'), quick('call'), quick('raise'), show, find.byKey(const ValueKey('raise more'))]) {
      expectWorks(tester, button);
    }
    expect(tester.widget<Slider>(find.byKey(const ValueKey('raise slider'))).onChanged, isNotNull);
    expect(gtoOn('call'), findsNothing);
    // The answer lands while the user is still at the decision: GTO's percentages go on the buttons.
    solves.only.complete();
    await tester.pump();
    expect(c.heroSpot, isNotNull);
    expect(solving, findsNothing);
    expect(gtoOn('call'), findsOneWidget);
    expect(lit(tester), isTrue);
    // The buttons play, graded as always.
    await tester.tap(quick('call'));
    await tester.pump();
    expect(c.session.history.single.decisions, hasLength(1));
    await close(tester);
  });

  testWidgets('Show GTO pressed again before the answer stops waiting for it; the keys play meanwhile', (tester) async {
    final solves = ManualSolves();
    final c = headsUp(solves);
    await open(tester, c);
    solves.only.complete();
    await pumpUntil(tester, () => c.heroOptions != null);
    await tester.pump();
    await tester.tap(show);
    await tester.pump();
    await tester.tap(show);
    await tester.pump();
    expect(lit(tester), isFalse);
    solves.only.complete();
    await tester.pump();
    expect(c.heroSpot, isNotNull, reason: 'the answer still comes');
    expect(gtoOn('call'), findsNothing, reason: "but doesn't show");
    // The next decision: Show GTO pressed, then C, before the answer: the call plays at once.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await pumpUntil(tester, () => c.heroOptions != null && c.hand!.street == Street.flop);
    await tester.pump();
    expect(c.answerPending, isTrue);
    await tester.tap(show);
    await tester.pump();
    final before = actions(c);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pump();
    expect(actions(c), before + 1, reason: 'C checked at once');
    expect(c.hand!.log.whereType<ActionTaken>().last.seat, 0);
    // Graded once the answer comes.
    final decisions = c.session.history.single.decisions.length;
    await pumpUntil(tester, () => solves.pending.isNotEmpty);
    solves.only.complete();
    await tester.pump();
    expect(c.session.history.single.decisions, hasLength(decisions + 1));
    await close(tester);
  });

  testWidgets('no answer (the solve failed): Show GTO greys out and the notice says why', (tester) async {
    final solves = ManualSolves();
    final c = headsUp(solves);
    await open(tester, c);
    solves.only.complete();
    await pumpUntil(tester, () => c.heroOptions != null);
    await tester.pump();
    await tester.tap(show);
    await tester.pump();
    solves.only.fail();
    await tester.pump();
    expect(c.answerPending, isFalse);
    expect(c.answerNone, NoAnswer.solveFailed);
    expect(tester.widget<OutlinedButton>(show).onPressed, isNull);
    expect(lit(tester), isFalse);
    expect(find.text('No GTO answer: the solver failed'), findsOneWidget);
    expect(solving, findsNothing);
    expectWorks(tester, quick('call'));
    await close(tester);
  });

  testWidgets('a move made before its answer plays at once; a late Blunder shows with OK while the bots play on, '
      'recorded and saved at its own decision', (tester) async {
    final solves = ManualSolves();
    var now = DateTime(2026, 1, 1);
    final drills = Drills(clock: () => now);
    // Four players, the user on the button with aces; the first player raises, the blinds call.
    final c = TableController(
      TableConfig.quick(playerCount: 4, heroPosition: Position.btn, guessGto: true, opponentStyle: BotStyle.tag),
      random: Random(2),
      solutions: withManualSolves(solves),
      drills: drills,
    )..scriptedBots = script();
    c.session.preset = (
      holeCards: {
        0: parseCards('As Ad'),
        1: parseCards('7c 2d'),
        2: parseCards('9h 8h'),
        3: parseCards('Kc Qd'),
      },
      board: parseCards('3s 4h Jd 5c Tc'),
    );
    await open(tester, c);
    solves.only.complete();
    await pumpUntil(tester, () => c.heroOptions != null);
    await tester.pump();
    final decision = actions(c);
    // Folding aces, before the answer: the hand goes on at once.
    await tester.tap(quick('fold'));
    await tester.pump();
    expect(c.heroOptions, isNull);
    expect(c.session.history.single.decisions, isEmpty);
    await pumpUntil(tester, () => actions(c) > decision + 1, max: 400);
    expect(c.hand!.isOver, isFalse);
    // The grade lands while the bots play: the card shows with OK, and the table goes on behind it.
    solves.only.complete();
    await tester.pump();
    expect(c.heroScoreLate, isTrue);
    expect(find.text('Blunder').evaluate().isNotEmpty || find.text('Mistake').evaluate().isNotEmpty, isTrue);
    expect(find.widgetWithText(FilledButton, 'OK'), findsOneWidget);
    final shownAt = actions(c);
    await pumpUntil(tester, () => actions(c) > shownAt);
    expect(c.heroScore, isNotNull, reason: 'the card stays while the bots play');
    // Recorded with its own decision: before the flop, no board, after one action.
    final record = c.session.history.single.decisions.single;
    expect(record.street, Street.preflop);
    expect(record.board, isEmpty);
    expect(record.turnId, decision);
    expect(record.spot.handName, 'AA');
    // Saved to the drills from that decision: the moves before it, not the table's now.
    expect(drills.spots.single.moves, hasLength(decision));
    expect(drills.spots.single.board, isEmpty);
    expect(c.lateMistakes.single.street, Street.preflop);
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pump();
    expect(c.heroScore, isNull);
    now = now.add(const Duration(minutes: 1));
    await close(tester);
  });

  testWidgets("a late grade waits for no one: with the user choosing again it doesn't show, and the hand's "
      'end lists it (a tap shows the hand)', (tester) async {
    final solves = ManualSolves();
    final c = headsUp(solves, advanced: true);
    c.session.preset = (holeCards: {0: parseCards('As Ad'), 1: parseCards('7c 2d')}, board: parseCards('3s 4h Jd 5c Tc'));
    await open(tester, c);
    solves.only.complete();
    await pumpUntil(tester, () => c.heroOptions != null);
    await tester.pump();
    // Advanced: a mix that always folds aces (a Blunder), with Call ticked to play.
    c.submitMix([for (final a in c.heroMenu!) a.kind == SpotActionKind.fold ? 1.0 : 0.0],
        choice: choiceOf(c, SpotActionKind.call));
    await pumpUntil(tester, () => c.heroOptions != null && c.hand!.street == Street.flop);
    // The user's flop decision shows first; then the preflop grade lands.
    solves.only.complete();
    await tester.pump();
    expect(c.heroScore, isNull, reason: 'no card while choosing');
    expect(find.byKey(const ValueKey('quick call')).evaluate().isNotEmpty || find.byKey(const ValueKey('play')).evaluate().isNotEmpty, isTrue);
    expect(c.lateMistakes.single.street, Street.preflop);
    expect(c.session.history.single.decisions.single.street, Street.preflop);
    // The user checks down; the hand's end lists the late Blunder, with "Solving…" while grades come.
    while (!c.handOver) {
      if (c.heroOptions != null && c.heroScore == null) {
        c.submitMix([for (final a in c.heroMenu!) a.kind == SpotActionKind.check ? 1.0 : 0.0],
            choice: choiceOf(c, SpotActionKind.check));
      } else if (c.heroScore != null) {
        await c.continueHand();
      }
      await tester.pump(step);
    }
    await tester.pump();
    if (c.heroScore != null) {
      await tester.tap(find.widgetWithText(FilledButton, 'OK'));
      await tester.pump();
    }
    expect(solving, findsOneWidget, reason: 'the flop, turn and river grades are still to come');
    final late = find.byKey(const ValueKey('late 0'));
    expect(late, findsOneWidget);
    expect(find.descendant(of: late, matching: find.textContaining('preflop')), findsOneWidget);
    while (solves.pending.isNotEmpty) {
      solves.only.complete();
      await tester.pump();
    }
    await tester.pump();
    while (c.heroScore != null) {
      await c.continueHand();
      await tester.pump();
    }
    expect(solving, findsNothing);
    expect(c.session.history.single.decisions.map((d) => d.street),
        [Street.preflop, Street.flop, Street.turn, Street.river], reason: 'in the order they were played');
    await tester.tap(late);
    await tester.pumpAndSettle();
    expect(find.byType(HandDetailsDialog), findsOneWidget);
    await close(tester);
  });

  testWidgets("a late preflop grade shown on the flop gives the preflop why, not the flop's", (tester) async {
    final solves = ManualSolves();
    final c = TableController(
      TableConfig.quick(playerCount: 4, heroPosition: Position.btn, guessGto: true, advanced: true, opponentStyle: BotStyle.tag),
      random: Random(2),
      solutions: withManualSolves(solves),
    )..scriptedBots = script();
    c.session.preset = (
      holeCards: {0: parseCards('As Ad'), 1: parseCards('7c 2d'), 2: parseCards('9h 8h'), 3: parseCards('Kc Qd')},
      board: parseCards('3s 4h Jd 5c Tc'),
    );
    await open(tester, c);
    solves.only.complete();
    await pumpUntil(tester, () => c.heroOptions != null);
    await tester.pump();
    c.submitMix([for (final a in c.heroMenu!) a.kind == SpotActionKind.fold ? 1.0 : 0.0],
        choice: choiceOf(c, SpotActionKind.call));
    // On the flop, a bot to act: the grade lands.
    await pumpUntil(tester, () => c.hand!.street == Street.flop && c.view.actingSeat != 0 && c.view.actingSeat != null);
    solves.only.complete();
    await tester.pump();
    expect(c.heroScoreLate, isTrue);
    expect(c.hand!.street, Street.flop);
    final why = c.heroWhy!;
    expect(why.percentile, isNotNull, reason: 'how good aces are before the flop');
    expect(why.read, isNull, reason: 'not a read of the flop');
    final reason = reasonFor(mistakeOf(c.heroSpot!, c.heroMix!)!.$1, percentile: why.percentile, odds: why.odds);
    expect(reason?.kind, ReasonKind.strongStart);
    await close(tester);
  });

  testWidgets('advanced: a mix submitted before the answer plays a move drawn from it, scored later', (tester) async {
    final solves = ManualSolves();
    final c = headsUp(solves, advanced: true);
    await open(tester, c);
    solves.only.complete();
    await pumpUntil(tester, () => c.heroOptions != null);
    await tester.pump();
    final call = choiceOf(c, SpotActionKind.call), fold = choiceOf(c, SpotActionKind.fold);
    final mix = [for (var i = 0; i < c.heroMenu!.length; i++) i == call || i == fold ? 0.5 : 0.0];
    final before = actions(c);
    c.submitMix(mix);
    await tester.pump();
    final played = c.hand!.log.whereType<ActionTaken>().elementAt(before);
    expect(played.seat, 0);
    expect(played.kind, anyOf(ActionKind.call, ActionKind.fold));
    await tester.pump();
    solves.only.complete();
    await tester.pump();
    final record = c.session.history.single.decisions.single;
    expect(record.mix[call], closeTo(0.5, 1e-9));
    expect(record.played, played.kind == ActionKind.call ? call : fold);
    await close(tester);
  });

  testWidgets('Free Play: a GTO bot whose flop is still being solved plays within think + 1 s, '
      'and the hand stays on the solved lines', (tester) async {
    final solves = ManualSolves();
    final c = headsUp(solves, guessGto: false);
    // Only before the flop are the bot's moves set; after it, the GTO bot plays.
    final opening = script();
    c.scriptedBots = (hand, seat) => hand.street == Street.preflop ? opening(hand, seat) : null;
    await open(tester, c);
    solves.only.complete();
    await pumpUntil(tester, () => c.heroOptions != null);
    await tester.pump();
    expect(solves.only.kind, SolveKind.subgame, reason: "the GTO bot's replies come from it");
    await tester.tap(quick('call'));
    await tester.pump();
    solves.only.complete();
    await pumpUntil(tester, () => c.heroOptions != null && c.hand!.street == Street.flop);
    await tester.pump();
    expect(solves.only.kind, SolveKind.street);
    expect(solves.only.priority, SolvePriority.bot);
    await tester.tap(quick('call'));
    await pumpUntil(tester, () => c.view.actingSeat == 1);
    final flopActions = actions(c);
    final waited = await pumpUntil(tester, () => actions(c) > flopActions);
    expect(waited, greaterThanOrEqualTo(Playback.botThink + Playback.botBudget - step * 3));
    expect(waited, lessThanOrEqualTo(Playback.botThink + Playback.botBudget + step * 3));
    // The flop's solve comes after the bot's move: it follows it, and the hand goes on with answers.
    solves.only.complete();
    await tester.pump();
    final follower = c.followers.last;
    await tester.pump();
    expect(follower.postflop!.unavailable, isNull, reason: "the bot's move is on the solved lines");
    expect(follower.failed, isNull);
    await close(tester);
  });

  testWidgets("Next Hand deals at once while the last hand's river grade is still coming; it lands in that hand", (tester) async {
    final solves = ManualSolves();
    final c = headsUp(solves);
    await open(tester, c);
    solves.only.complete();
    // The user calls, then checks down, each time before the answer; each answer comes after, except the river's.
    while (!c.handOver) {
      await pumpUntil(tester, () => c.heroOptions != null || c.handOver || c.heroScore != null);
      if (c.heroScore != null) {
        await tester.tap(find.widgetWithText(FilledButton, 'OK'));
        await tester.pump();
        continue;
      }
      if (c.handOver) break;
      await tester.pump();
      final river = c.hand!.street == Street.river;
      await tester.tap(quick('call'));
      await tester.pump();
      if (!river && solves.pending.isNotEmpty) {
        solves.only.complete();
        await tester.pump();
      }
    }
    await pumpUntil(tester, () => c.handOver);
    while (c.heroScore != null) {
      await c.continueHand();
      await tester.pump();
    }
    expect(solves.only.kind, SolveKind.street, reason: "the river's");
    expect(c.gradesPending, isTrue);
    expect(c.session.history.single.decisions.map((d) => d.street), [Street.preflop, Street.flop, Street.turn]);
    await tester.tap(find.text('Next Hand'));
    await tester.pump();
    expect(c.hand!.handNumber, 2, reason: 'dealt at once');
    expect(c.followers, hasLength(2), reason: 'the hand before is kept for its last answer');
    expect(c.followers.first.preflop!.unavailable, NoAnswer.notNeeded, reason: 'and only what that answer reads');
    // The river's grade lands quietly in the hand it belongs to.
    solves.pending.first.complete();
    await tester.pump();
    await tester.pump();
    expect(c.session.history.first.decisions.map((d) => d.street),
        [Street.preflop, Street.flop, Street.turn, Street.river]);
    expect(c.session.history.last.handNumber, 2);
    expect(c.session.history.last.decisions, isEmpty);
    expect(c.heroScore, isNull);
    expect(c.followers, hasLength(1), reason: 'no answers left: the hand before is let go');
    await close(tester);
  });

  testWidgets('Show GTO puts its decision first: after the solve running, before queued work of lower priority',
      (tester) async {
    final solves = ManualSolves();
    final solutions = withManualSolves(solves);
    final c = TableController(
      TableConfig.quick(playerCount: 2, heroPosition: Position.bb, guessGto: true, opponentStyle: BotStyle.gto),
      random: Random(1),
      solutions: solutions,
    )..scriptedBots = script();
    await open(tester, c);
    // Other work: one for the next hand (it starts once the whole game is in), another, and a grade.
    PreflopSpec other(int bb) => PreflopAdvisor.specFor(
          stacksBySeat: [bb * 100, bb * 100],
          buttonSeat: 0,
          smallBlind: TableConfig.smallBlind,
          bigBlind: TableConfig.bigBlind,
          ante: 0,
        );
    for (final (i, priority) in [SolvePriority.nextHand, SolvePriority.nextHand, SolvePriority.grade].indexed) {
      unawaited(solutions.solve(other(30 + i), owner: SolveOwner(90 + i), priority: priority).then((_) {}, onError: (_) {}));
    }
    solves.only.complete();
    await pumpUntil(tester, () => c.heroOptions != null);
    await tester.pump();
    expect(solves.only.owner?.hand, 90, reason: 'the first piece of other work runs');
    await tester.tap(show);
    await tester.pump();
    solves.only.complete();
    await tester.pump();
    expect(solves.only.kind, SolveKind.subgame, reason: "the user's decision goes next");
    expect(solves.only.owner?.hand, 1);
    expect(solves.only.priority, SolvePriority.shown);
    solves.only.complete();
    await tester.pump();
    expect(gtoOn('call'), findsOneWidget);
    await close(tester);
  });

  testWidgets("the next hand's guess (the user's first decision if everyone folds to them) never goes before the "
      "hand's real work, and is let go of once a bot before the user raises", (tester) async {
    final solves = ManualSolves(auto: true);
    final solutions = withManualSolves(solves);
    final c = TableController(
      TableConfig.quick(playerCount: 3, heroPosition: Position.sb, guessGto: true, opponentStyle: BotStyle.tag),
      random: Random(1),
      solutions: solutions,
    )..scriptedBots = script();
    unawaited(c.startNextHand());
    await pumpUntil(tester, () => c.heroOptions != null);
    // Something else holds the solver from here on (another job of this device).
    final first = Completer<void>(), second = Completer<void>();
    unawaited(solutions.queue.add('first blocker', () => first.future, priority: SolvePriority.bot));
    await tester.pump();
    solves.auto = false;
    // The user folds to the button's raise: hand 1 needs nothing more, so hand 2's solves are asked for.
    unawaited(c.heroAct(const PlayerAction.fold()));
    await pumpUntil(tester, () => c.handOver);
    unawaited(solutions.queue.add('second blocker', () => second.future, priority: SolvePriority.nextHand));
    first.complete();
    await tester.pump();
    for (var i = 0; i < 5 && solves.pending.isNotEmpty; i++) {
      expect(solves.only.preflop.hero, lessThan(0), reason: "hand 2's whole game: ${solves.only}");
      solves.only.complete();
      await tester.pump();
      await tester.pump();
    }
    expect(solutions.queue.running, ['second blocker']);
    expect(solutions.queue.queued, hasLength(1), reason: "only hand 2's guess waits");
    // Hand 2: the button waits for the hand's solves (claiming them meanwhile), then raises: the guess is moot.
    unawaited(c.startNextHand());
    await pumpUntil(tester, () => c.heroOptions != null && c.hand!.handNumber == 2);
    await tester.pump();
    expect(c.answerPending, isTrue);
    expect(solutions.queue.queued, hasLength(1), reason: "the guess is let go of: only the user's real subgame waits");
    // Show GTO: the user's decision runs next.
    c.wantAnswerShown();
    second.complete();
    await tester.pump();
    await tester.pump();
    expect(solves.only.kind, SolveKind.subgame,
        reason: "the user's subgame (it grades the move, and the bots' replies come from it), not the guess the "
            'hand has passed');
    expect(solves.only.priority, SolvePriority.shown);
    solves
      ..auto = true
      ..completeAll();
    await tester.pump(const Duration(seconds: 3));
    c.dispose();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('when everyone folds to the user, the guess solved ahead of time is their answer: it is kept, not '
      'solved again', (tester) async {
    final solves = ManualSolves(auto: true);
    final solutions = withManualSolves(solves);
    final c = TableController(
      TableConfig.quick(playerCount: 4, heroPosition: Position.sb, guessGto: true, opponentStyle: BotStyle.tag),
      random: Random(1),
      solutions: solutions,
    )..scriptedBots = (hand, seat) => const PlayerAction.fold();
    unawaited(c.startNextHand());
    await pumpUntil(tester, () => c.heroOptions != null);
    final guess = c.session.upcomingHeroSpec;
    expect(guess, isNotNull, reason: 'the user is not last to act in hand 2');
    expect(guess!.history, isNotEmpty, reason: 'someone acts before the user in hand 2');
    // The solver is busy until hand 2 is dealt and the user is at their decision.
    final blocker = Completer<void>();
    unawaited(solutions.queue.add('blocker', () => blocker.future, priority: SolvePriority.bot));
    await tester.pump();
    solves.auto = false;
    unawaited(c.heroAct(const PlayerAction.fold()));
    await pumpUntil(tester, () => c.handOver);
    unawaited(c.startNextHand());
    await pumpUntil(tester, () => c.heroOptions != null && c.hand!.handNumber == 2);
    expect(c.answerPending, isTrue);
    blocker.complete();
    for (var i = 0; i < 20 && c.answerPending; i++) {
      solves.completeAll();
      await tester.pump(step);
    }
    expect(c.heroSpot, isNotNull);
    final userSolves = [
      for (final p in solves.started)
        if (p.kind == SolveKind.whole && p.preflop.hero >= 0 && p.preflop.key == guess.key) p,
    ];
    expect(userSolves, hasLength(1), reason: 'solved once');
    expect(identical(userSolves.single.owner, c.followers.last.owner), isFalse,
        reason: 'asked for ahead of time, by its own claim');
    c.dispose();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('leaving the table while a street solve waits its turn and nobody waits for it yet reports no error',
      (tester) async {
    final solves = ManualSolves();
    final solutions = withManualSolves(solves);
    // Heads-up, the user on the button: the bot (big blind) acts first after the flop.
    final c = TableController(
      TableConfig.quick(playerCount: 2, heroPosition: Position.btn, guessGto: true, opponentStyle: BotStyle.tag),
      random: Random(1),
      solutions: solutions,
    )..scriptedBots =
        (hand, seat) => hand.legalActions().canCheck ? const PlayerAction.check() : const PlayerAction.call();
    unawaited(c.startNextHand());
    await tester.pump();
    await pumpUntil(tester, () => c.heroOptions != null);
    for (var i = 0; i < 200 && c.answerPending; i++) {
      if (solves.pending.isNotEmpty) solves.pending.first.complete();
      await tester.pump(step);
    }
    expect(c.heroSpot, isNotNull);
    // Something else holds the solver now (the next hand's game, another table...).
    final blocker = Completer<void>();
    unawaited(solutions.queue.add('blocker', () => blocker.future, priority: SolvePriority.bot));
    await tester.pump();
    // The user limps, the bot checks: the flop's solve is asked for and waits its turn.
    unawaited(c.playGraded(choiceOf(c, SpotActionKind.call)));
    await tester.pump();
    if (c.heroScore != null) unawaited(c.continueHand());
    await pumpUntil(tester, () => c.hand!.street == Street.flop);
    await tester.pump();
    expect(solutions.queue.queued, hasLength(1), reason: "the flop's solve waits behind the blocker");
    // The bot thinks; the user leaves meanwhile. The dropped solve fails quietly.
    c.dispose();
    await tester.pump(const Duration(seconds: 5));
    blocker.complete();
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('advanced: a late Best grade is quiet (no card over the table), as in simple training', (tester) async {
    // GTO's mix at the user's first decision, with every answer in at once.
    final first = ManualSolves(auto: true);
    final a = TableController(
      TableConfig.quick(playerCount: 3, heroPosition: Position.sb, guessGto: true, advanced: true, opponentStyle: BotStyle.gto),
      random: Random(1),
      solutions: withManualSolves(first),
    )..scriptedBots = script();
    await open(tester, a);
    await pumpUntil(tester, () => a.heroSpot != null);
    final gto = List<double>.of(a.heroSpot!.frequencies);
    await close(tester);
    // The same hand with the answer held: the user enters exactly GTO's mix and plays it before the answer.
    final solves = ManualSolves();
    final c = TableController(
      TableConfig.quick(playerCount: 3, heroPosition: Position.sb, guessGto: true, advanced: true, opponentStyle: BotStyle.gto),
      random: Random(1),
      solutions: withManualSolves(solves),
    )..scriptedBots = script();
    await open(tester, c);
    solves.only.complete();
    await pumpUntil(tester, () => c.heroOptions != null);
    await tester.pump();
    expect(c.answerPending, isTrue);
    c.submitMix(gto, choice: choiceOf(c, SpotActionKind.call));
    await tester.pump();
    expect(c.heroOptions, isNull);
    // A bot acts next; the grade lands meanwhile.
    solves.only.complete();
    await tester.pump();
    await tester.pump();
    expect(c.session.history.single.decisions.single.score.grade, DecisionGrade.best);
    expect(c.heroScore, isNull, reason: 'Best is quiet: it joins the recent scores');
    await close(tester);
  });

  group('the same grades however late the answers come', () {
    /// Plays one hand from the same deal with the same moves (the bots'
    /// set, the user calling and checking down), the answers coming early
    /// or late: at each of the user's decisions for which [late] says so,
    /// the user plays before the solves held so far finish; at the others,
    /// they finish first. Returns the hand's records, all they hold.
    Future<List<Object>> play(bool Function(int decision) late) async {
      final solves = ManualSolves();
      final c = TableController(
        TableConfig.quick(playerCount: 3, heroPosition: Position.bb, guessGto: true, opponentStyle: BotStyle.tag),
        speed: PlaybackSpeed.instant,
        random: Random(7),
        solutions: withManualSolves(solves),
      )..scriptedBots = script(folds: {2});
      c.session.preset = (
        holeCards: {0: parseCards('Kh Qh'), 1: parseCards('Ts 9s'), 2: parseCards('7c 2d')},
        board: parseCards('Ks 8h 4c 2s Qd'),
      );
      Future<void> settle() async {
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(Duration.zero);
        }
      }

      Future<void> finishSolves() async {
        for (var round = 0; round < 40 && solves.pending.isNotEmpty; round++) {
          solves.pending.first.complete();
          await settle();
        }
      }

      unawaited(c.startNextHand());
      await settle();
      var decision = 0;
      for (var guard = 0; guard < 60 && !c.handOver; guard++) {
        if (c.heroScore != null) {
          await c.continueHand();
        } else if (c.heroOptions != null) {
          if (late(decision)) {
            expect(c.answerPending, isTrue, reason: 'decision $decision');
          } else {
            for (var round = 0; round < 40 && c.answerPending; round++) {
              await finishSolves();
            }
            expect(c.heroSpot, isNotNull, reason: 'decision $decision');
          }
          final kind = c.hand!.street == Street.preflop ? SpotActionKind.call : SpotActionKind.check;
          unawaited(c.playGraded(choiceOf(c, kind)));
          decision++;
        }
        await settle();
      }
      expect(c.handOver, isTrue);
      for (var round = 0; round < 10; round++) {
        await finishSolves();
      }
      await c.caughtUp();
      final records = [
        for (final d in c.session.history.single.decisions)
          (d.street, d.board.join(' '), d.turnId, d.played, d.score.score, d.score.evLoss, d.spot.frequencies.join(','),
              d.mix.join(',')),
      ];
      c.dispose();
      return records;
    }

    test('a move made before its answer gets exactly the grade it gets when the table waits for it', () async {
      final waited = await play((_) => false);
      expect(waited, hasLength(4), reason: 'preflop, flop, turn and river');
      expect(await play((d) => d == 0), waited, reason: 'the whole game late');
      expect(await play((_) => true), waited, reason: 'every answer late');
      expect(await play((d) => d.isOdd), waited, reason: 'some late');
    });
  });

  group('the same grades however late the answers come, three in the hand after the flop', () {
    /// As above, three-handed (two decisions before the flop, the user
    /// against the field after it), and the solves may finish in any order
    /// ([pick] says which of those running finishes next).
    Future<List<Object>> play(bool Function(int decision) late, {int Function(int finished)? pick}) async {
      final solves = ManualSolves();
      final c = TableController(
        TableConfig.quick(playerCount: 3, heroPosition: Position.btn, guessGto: true, opponentStyle: BotStyle.tag),
        speed: PlaybackSpeed.instant,
        random: Random(7),
        solutions: withManualSolves(solves, queue: SolveQueue(maxRunning: 3)),
      )..scriptedBots = script();
      c.session.preset = (
        holeCards: {0: parseCards('Kh Qh'), 1: parseCards('Ts 9s'), 2: parseCards('7c 7d')},
        board: parseCards('Ks 8h 4c 2s Qd'),
      );
      Future<void> settle() async {
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(Duration.zero);
        }
      }

      var finished = 0;
      Future<void> finishSolves() async {
        for (var round = 0; round < 60 && solves.pending.isNotEmpty; round++) {
          final i = pick == null ? 0 : pick(finished++) % solves.pending.length;
          solves.pending[i].complete();
          await settle();
        }
      }

      unawaited(c.startNextHand());
      await settle();
      var decision = 0;
      for (var guard = 0; guard < 80 && !c.handOver; guard++) {
        if (c.heroScore != null) {
          await c.continueHand();
        } else if (c.heroOptions != null) {
          if (!late(decision)) {
            for (var round = 0; round < 40 && c.answerPending; round++) {
              await finishSolves();
            }
            expect(c.heroSpot, isNotNull, reason: 'decision $decision');
          }
          var i = choiceOf(c, SpotActionKind.check);
          if (i < 0) i = choiceOf(c, SpotActionKind.call);
          unawaited(c.playGraded(i));
          decision++;
        }
        await settle();
      }
      expect(c.handOver, isTrue);
      for (var round = 0; round < 10; round++) {
        await finishSolves();
      }
      await c.caughtUp();
      final records = [
        for (final d in c.session.history.single.decisions)
          (d.street, d.board.join(' '), d.turnId, d.played, d.score.score, d.score.evLoss, d.spot.frequencies.join(','),
              d.mix.join(',')),
      ];
      c.dispose();
      return records;
    }

    test('every arrival order gives the same records', () async {
      final waited = await play((_) => false);
      expect(waited.length, greaterThanOrEqualTo(4));
      expect(await play((_) => true), waited, reason: 'every answer late');
      expect(await play((_) => true, pick: (n) => n * 7 + 3), waited, reason: 'every answer late, out of order');
      expect(await play((d) => d.isOdd, pick: (n) => n * 5 + 1), waited, reason: 'some late, out of order');
      expect(await play((d) => d == 1), waited, reason: 'the second decision before the flop late');
    });
  });
}
