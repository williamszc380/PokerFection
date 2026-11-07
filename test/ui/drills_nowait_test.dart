import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/drills.dart';
import 'package:pokerfection/src/bots/bot.dart';
import 'package:pokerfection/src/engine/cards.dart';
import 'package:pokerfection/src/gto/spot_strategy.dart';
import 'package:pokerfection/src/ui/table_controller.dart';
import 'package:pokerfection/src/ui/table_screen.dart';

import '../gto/manual_solves.dart';

/// The mistake drills never wait for GTO's answer either (they are off in
/// the app for now, but kept working): a saved spot played before its
/// answer comes is graded when it does, and Next Hand works meanwhile.
void main() {
  final t0 = DateTime(2026, 1, 1);

  /// A saved spot, due now: heads-up, the user on the button (first to
  /// act) with king-queen offsuit, no moves before the decision.
  DrillSpot saved() => DrillSpot(
        names: const ['You', 'Alice'],
        styles: const [null, BotStyle.gto],
        stacks: const [2000, 2000],
        button: 0,
        cards: [parseCards('Kd Qc'), parseCards('7c 2d')],
        moves: const [],
        grade: DecisionGrade.mistake,
        evLoss: 1,
        saved: t0,
      );

  ({DrillController drill, ManualSolves solves, DrillSpot spot, Drills drills}) dealing() {
    final spot = saved();
    final drills = Drills(clock: () => t0.add(const Duration(minutes: 10)));
    drills.save(spot);
    final solves = ManualSolves();
    final drill = DrillController(drills, speed: PlaybackSpeed.instant, random: Random(1), solutions: withManualSolves(solves));
    return (drill: drill, solves: solves, spot: drills.spots.single, drills: drills);
  }

  Future<void> open(WidgetTester tester, DrillController drill) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: TableScreen(config: drill.session.config, controller: drill)));
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  /// Lets every solve held finish, in turn.
  Future<void> finish(WidgetTester tester, ManualSolves solves) async {
    for (var i = 0; i < 20 && solves.pending.isNotEmpty; i++) {
      solves.pending.first.complete();
      await tester.pump();
    }
  }

  final next = find.byKey(const ValueKey('continue'));

  testWidgets('played before its answer: "Solving…", Next Hand works; staying, the result shows when it lands',
      (tester) async {
    final (:drill, :solves, :spot, drills: _) = dealing();
    await open(tester, drill);
    expect(drill.spot, same(spot));
    expect(drill.answerPending, isTrue);
    await tester.tap(find.byKey(const ValueKey('quick call')));
    await tester.pump();
    expect(drill.gradePending, isTrue);
    expect(drill.hand!.toAct, 0, reason: 'the hand stays stopped at the decision');
    expect(find.byKey(const ValueKey('solving')), findsOneWidget);
    expect(tester.widget<FilledButton>(next).onPressed, isNotNull);
    expect(find.text('Next Hand'), findsOneWidget);
    await finish(tester, solves);
    expect(drill.gradePending, isFalse);
    expect(drill.outcome, isNotNull);
    expect(drill.heroScore, isNotNull, reason: 'the result shows, whatever the grade');
    expect(find.textContaining('Score '), findsOneWidget);
    expect(spot.due, isNot(t0.add(drillCooldown(0))), reason: 'reviewed');
    await close(tester);
  });

  testWidgets('moving on before the grade: the next hand deals at once, and the spot is reviewed when the grade lands',
      (tester) async {
    final (:drill, :solves, :spot, drills: _) = dealing();
    await open(tester, drill);
    await tester.tap(find.byKey(const ValueKey('quick call')));
    await tester.pump();
    final due = spot.due;
    await tester.tap(next);
    await tester.pump();
    expect(drill.spot, isNull, reason: 'a random hand: the spot is not dealt again while its grade comes');
    expect(drill.session.handNumber, 2);
    expect(spot.due, due);
    // The spot stopped its hand at the decision, short of its end: nobody plays in it any more, so what is left
    // of it only grades (it goes after the next hand's game).
    expect(drill.followers.first.owner.hand, 1);
    expect(drill.followers.first.owner.finished, isTrue);
    await finish(tester, solves);
    expect(spot.due, isNot(due), reason: 'reviewed once graded');
    expect(drill.outcome, isNull, reason: 'nothing shows: the user moved on');
    await close(tester);
  });

  testWidgets('no answer at all: not graded, as before', (tester) async {
    final (:drill, :solves, :spot, drills: _) = dealing();
    await open(tester, drill);
    await tester.tap(find.byKey(const ValueKey('quick call')));
    await tester.pump();
    solves.only.fail();
    await tester.pump();
    expect(drill.outcome?.right, isNull);
    expect(drill.outcome?.wait, drillCooldown(0));
    expect(find.text('No GTO answer: the solver failed'), findsOneWidget);
    expect(find.text('Next Hand'), findsOneWidget);
    expect(spot.step, 0);
    await close(tester);
  });

  testWidgets("a saved spot's grade is the same whether its answer came before or after the play", (tester) async {
    Future<(int, double, bool?)> grade({required bool late}) async {
      final (:drill, :solves, spot: _, drills: _) = dealing();
      solves.auto = !late;
      await open(tester, drill);
      await tester.pump();
      expect(drill.answerPending, late);
      await tester.tap(find.byKey(const ValueKey('quick call')));
      await tester.pump();
      await finish(tester, solves);
      final record = drill.session.history.single.decisions.single;
      final result = (record.score.playScore, record.score.evLoss, drill.outcome?.right);
      await close(tester);
      return result;
    }

    final atOnce = await grade(late: false);
    expect(await grade(late: true), atOnce);
  });
}
