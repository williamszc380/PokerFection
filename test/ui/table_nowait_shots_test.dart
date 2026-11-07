import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/bots/bot.dart';
import 'package:pokerfection/src/engine/actions.dart';
import 'package:pokerfection/src/engine/cards.dart';
import 'package:pokerfection/src/engine/events.dart';
import 'package:pokerfection/src/engine/poker_hand.dart';
import 'package:pokerfection/src/engine/positions.dart';
import 'package:pokerfection/src/game/table_session.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tracker.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tree.dart';
import 'package:pokerfection/src/gto/spot_strategy.dart';
import 'package:pokerfection/src/ui/table_controller.dart';
import 'package:pokerfection/src/ui/table_screen.dart';
import 'package:pokerfection/src/ui/widgets/mix_slider.dart';

import '../gto/manual_solves.dart';
import '../kit/shots.dart';

/// The decision panel while GTO's answer is on its way, at every size and
/// in every language: the choices with "Solving…" (simple and advanced),
/// Show GTO waiting for the answer, the answer shown, a late Mistake's
/// card, and the hand's end with its late Mistakes. Nothing may overflow,
/// and what the user needs shows without scrolling. With
/// `--dart-define=SHOTS=dir` each is saved as a PNG.
void main() {
  setUpAll(loadShotFonts);
  const sizes = [Size(568, 320), Size(900, 420), Size(1280, 800), Size(390, 844)];
  const step = Duration(milliseconds: 20);

  PlayerAction onMenu(PokerHand hand, PlayerAction move) =>
      fitToMenu(move, PreflopTree.botMenuAt(PreflopTracker.specAt(hand)), hand.legalActions());

  PlayerAction? script(PokerHand hand, int seat) {
    final legal = hand.legalActions();
    if (hand.street != Street.preflop) return legal.canCheck ? const PlayerAction.check() : const PlayerAction.call();
    final raised = hand.log.whereType<ActionTaken>().any((e) => e.kind == ActionKind.raise);
    return onMenu(hand, raised ? const PlayerAction.call() : const PlayerAction.raiseTo(250));
  }

  Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 2000 && !done(); i++) {
      await tester.pump(step);
    }
    expect(done(), isTrue);
  }

  Future<void> snap(WidgetTester tester, String name) async {
    await tester.pump();
    final error = tester.takeException();
    await shot(tester, name);
    expect(error, isNull, reason: name);
  }

  /// [finder] is on screen whole: not cut off by the screen's edge or by a
  /// scrolling area it is in.
  void expectShown(WidgetTester tester, Finder finder, String what) {
    final element = finder.evaluate().single;
    var visible = tester.getRect(find.byType(TableScreen));
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget is Scrollable) {
        final box = ancestor.renderObject! as RenderBox;
        visible = visible.intersect(box.localToGlobal(Offset.zero) & box.size);
      }
      return true;
    });
    final rect = tester.getRect(finder).deflate(0.5);
    expect(visible.contains(rect.topLeft) && visible.contains(rect.bottomRight), isTrue,
        reason: '$what at $rect, shown $visible');
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  for (final language in AppLanguage.values) {
    for (final size in sizes) {
      final tag = shotTag(size, language);

      testWidgets('the choices while the answer comes, Show GTO waiting for it, and the answer at $tag', (tester) async {
        final solves = ManualSolves();
        final c = TableController(
          TableConfig.quick(playerCount: 6, heroPosition: Position.bb, guessGto: true, opponentStyle: BotStyle.gto),
          random: Random(3),
          solutions: withManualSolves(solves),
        )..scriptedBots = script;
        await pumpShot(tester, TableScreen(config: c.session.config, controller: c), size: size, language: language);
        await tester.pump();
        solves.only.complete();
        await pumpUntil(tester, () => c.heroOptions != null);
        await tester.pump(const Duration(seconds: 1));
        expect(c.answerPending, isTrue);
        await snap(tester, 'nowait_pending_$tag');
        await tester.tap(find.byKey(const ValueKey('show gto')));
        await snap(tester, 'nowait_show_waiting_$tag');
        solves.only.complete();
        await tester.pump();
        expect(c.heroSpot, isNotNull);
        await snap(tester, 'nowait_answer_$tag');
        await close(tester);
      });

      testWidgets('advanced: the mix while the answer comes, Show GTO waiting for it, and the answer at $tag',
          (tester) async {
        final solves = ManualSolves();
        final c = TableController(
          TableConfig.quick(
            playerCount: 6,
            heroPosition: Position.bb,
            guessGto: true,
            advanced: true,
            opponentStyle: BotStyle.gto,
          ),
          random: Random(3),
          solutions: withManualSolves(solves),
        )..scriptedBots = script;
        await pumpShot(tester, TableScreen(config: c.session.config, controller: c), size: size, language: language);
        await tester.pump();
        solves.only.complete();
        await pumpUntil(tester, () => c.heroOptions != null);
        await tester.pump(const Duration(seconds: 1));
        expect(c.answerPending, isTrue);
        // The slider, RNG, Show GTO and Play always show; "Solving…" first of what scrolls above them.
        final slider = find.byType(MixSlider), show = find.byKey(const ValueKey('show gto'));
        final play = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_PlayButton');
        void expectControls() {
          expectShown(tester, slider, 'the mix slider');
          expectShown(tester, show, 'Show GTO');
          expectShown(tester, play, 'Play');
        }

        expectControls();
        expectShown(tester, find.byKey(const ValueKey('solving')), '"Solving…"');
        await snap(tester, 'nowait_adv_pending_$tag');
        await tester.tap(show);
        expectControls();
        await snap(tester, 'nowait_adv_show_waiting_$tag');
        solves.only.complete();
        await tester.pump();
        expect(c.heroSpot, isNotNull);
        expectControls();
        await snap(tester, 'nowait_adv_answer_$tag');
        await close(tester);
      });

      testWidgets("a late Mistake's card while the bots play on at $tag", (tester) async {
        final solves = ManualSolves();
        final c = TableController(
          TableConfig.quick(playerCount: 4, heroPosition: Position.btn, guessGto: true, opponentStyle: BotStyle.tag),
          random: Random(2),
          solutions: withManualSolves(solves),
        )..scriptedBots = script;
        c.session.preset = (
          holeCards: {0: parseCards('As Ad'), 1: parseCards('7c 2d'), 2: parseCards('9h 8h'), 3: parseCards('Kc Qd')},
          board: parseCards('3s 4h Jd 5c Tc'),
        );
        await pumpShot(tester, TableScreen(config: c.session.config, controller: c), size: size, language: language);
        await tester.pump();
        solves.only.complete();
        await pumpUntil(tester, () => c.heroOptions != null);
        await tester.pump();
        c.playGraded(c.heroMenu!.indexWhere((a) => a.kind == SpotActionKind.fold));
        await tester.pump(const Duration(milliseconds: 400));
        solves.only.complete();
        await tester.pump(const Duration(milliseconds: 300));
        expect(c.heroScoreLate, isTrue);
        await snap(tester, 'nowait_late_card_$tag');
        await close(tester);
      });

      testWidgets("the hand's end with its late Mistakes, and grades still to come, at $tag", (tester) async {
        final solves = ManualSolves();
        final c = TableController(
          TableConfig.quick(playerCount: 2, heroPosition: Position.bb, guessGto: true, advanced: true, opponentStyle: BotStyle.gto),
          speed: PlaybackSpeed.instant,
          random: Random(1),
          solutions: withManualSolves(solves),
        )..scriptedBots = script;
        c.session.preset = (holeCards: {0: parseCards('As Ad'), 1: parseCards('7c 2d')}, board: parseCards('3s 4h Jd 5c Tc'));
        await pumpShot(tester, TableScreen(config: c.session.config, controller: c), size: size, language: language);
        await tester.pump();
        solves.only.complete();
        // A mix that always folds aces (a Blunder), with Call ticked to play; then the user checks down.
        await pumpUntil(tester, () => c.heroOptions != null);
        c.submitMix([for (final a in c.heroMenu!) a.kind == SpotActionKind.fold ? 1.0 : 0.0],
            choice: c.heroMenu!.indexWhere((a) => a.kind == SpotActionKind.call));
        await pumpUntil(tester, () => c.heroOptions != null);
        solves.only.complete();
        await tester.pump();
        while (!c.handOver) {
          if (c.heroOptions != null) {
            c.submitMix([for (final a in c.heroMenu!) a.kind == SpotActionKind.check ? 1.0 : 0.0],
                choice: c.heroMenu!.indexWhere((a) => a.kind == SpotActionKind.check));
          }
          await tester.pump(step);
        }
        expect(c.lateMistakes, isNotEmpty);
        expect(c.gradesPending, isTrue);
        await tester.pump();
        expectShown(tester, find.byKey(const ValueKey('late 0')), 'the late Mistake');
        expectShown(tester, find.byKey(const ValueKey('solving')), '"Solving…"');
        await snap(tester, 'nowait_hand_over_$tag');
        await close(tester);
      });
    }
  }
}
