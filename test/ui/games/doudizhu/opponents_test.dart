// The bots' hands on the felt (a small fan of card backs each), Training's
// Show cards, and the range a tap on a bot's seat opens.
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_jobs.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_range.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/kit/jobs/jobs_core.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_controller.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_range_view.dart';
import 'package:pokerfection/src/ui/games/doudizhu/l10n/doudizhu_strings.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';
import 'package:pokerfection/src/ui/kit/turn_controller.dart';

import '../../../kit/shots.dart';
import 'helpers.dart';
import 'states.dart';

const pc = Size(1280, 800);
const phone = Size(568, 320);

Finder backs(int seat) => find.byKey(ValueKey('backs $seat'));
Finder faces(int seat) => find.byKey(ValueKey('hand $seat'));

/// The cards drawn face up in [finder].
int faceCount(WidgetTester tester, Finder finder) => tester
    .widgetList<GameCardView>(find.descendant(of: finder, matching: find.byType(GameCardView)))
    .where((card) => card.faceUp)
    .length;

Finder menuItem(String text) => find.ancestor(of: find.text(text), matching: find.byType(PopupMenuItem<VoidCallback>));

void main() {
  setUpAll(loadShotFonts);

  group("the bots' hands", () {
    testWidgets('both bots show a fan of card backs under their names, at most six, the badge giving the count; '
        'the cards everyone has seen show face up after them', (tester) async {
      for (final phase in [DdzPhase.bidding, DdzPhase.playing]) {
        final c = await gameAt(tester, phase);
        for (final size in [phone, pc]) {
          await showGame(tester, c, size, AppLanguage.english);
          for (final seat in [1, 2]) {
            expect(backs(seat), findsOneWidget, reason: '$phase $size seat $seat');
            final fan = tester.widget<SeatHand>(backs(seat));
            expect(fan.count, c.game.handSize(seat));
            expect(fan.faces, isNull, reason: 'face down');
            final drawn = find.descendant(of: backs(seat), matching: find.byType(GameCardView));
            final visible = c.game.visibleIn(seat);
            expect(tester.widgetList(drawn).length, inInclusiveRange(1, 6 + visible.length));
            expect(faceCount(tester, backs(seat)), visible.length, reason: 'only the cards everyone has seen');
            // Under the bot's own badge.
            final badge = tester.getRect(find.byKey(ValueKey('seat $seat')));
            final cards = tester.getRect(backs(seat));
            expect(cards.top, greaterThanOrEqualTo(badge.bottom - 1), reason: '$phase $size seat $seat');
            expect(cards.overlaps(badge.inflate(40)), isTrue, reason: 'right below it');
          }
          expect(tester.takeException(), isNull);
        }
        await closeGame(tester, c);
      }
    });

    testWidgets('after the deal the cards left are turned up, and a bot that went out shows none', (tester) async {
      final c = await finishedGame(tester);
      await showGame(tester, c, phone, AppLanguage.english);
      for (final seat in [1, 2]) {
        final left = c.game.handSize(seat);
        expect(backs(seat), findsNothing);
        if (left == 0) {
          expect(find.byKey(ValueKey('left $seat')), findsNothing);
        } else {
          expect(faceCount(tester, find.byKey(ValueKey('left $seat'))), left, reason: 'every card, face up');
        }
      }
      await closeGame(tester, c);
    });
  });

  group('Show cards (Training only)', () {
    testWidgets("☰ Show cards turns both bots' hands up, every card, and back down", (tester) async {
      final c = await gameAt(tester, DdzPhase.playing);
      await showGame(tester, c, phone, AppLanguage.english);
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(tester.widget<PopupMenuItem<VoidCallback>>(menuItem('Show cards')).enabled, isTrue);
      await tester.tap(find.text('Show cards'));
      await tester.pumpAndSettle();
      expect(c.showOpponentCards, isTrue);
      for (final seat in [1, 2]) {
        expect(backs(seat), findsNothing);
        expect(faceCount(tester, faces(seat)), c.game.handSize(seat), reason: 'seat $seat');
      }
      expect(tester.takeException(), isNull, reason: 'they fit a sideways phone');
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show cards'));
      await tester.pumpAndSettle();
      expect(backs(1), findsOneWidget);
      await closeGame(tester, c);
    });

    testWidgets('the coach, the grades and the ranges never see the cards shown', (tester) async {
      final c = await gameAt(tester, DdzPhase.playing);
      String inputs() => jsonEncode([
        c.coachRequest(c.record, 0, seed: 1).input is DdzCoachInput
            ? (c.coachRequest(c.record, 0, seed: 1).input! as DdzCoachInput).record
            : null,
        (c.rangeRequest(c.record, 1, seed: 1)!.input! as DdzRangeInput).record,
      ]);
      final hidden = inputs();
      c.showOpponentCards = true;
      expect(c.record.extra[TurnController.showCardsKey], isTrue);
      expect(inputs(), hidden, reason: 'the jobs get the same record, without the toggles');
      expect(inputs(), isNot(contains(TurnController.showCardsKey)));
      await closeGame(tester, c);
    });

    testWidgets('greyed out in Free Play, and the hands stay down whatever was saved', (tester) async {
      final c = testController(training: false, extra: const {TurnController.showCardsKey: true});
      c.newGame();
      await pumpUntil(tester, () => c.game.phase == DdzPhase.playing || c.isOver || c.seatToAct == 0);
      await showGame(tester, c, pc, AppLanguage.english);
      expect(c.showOpponentCards, isFalse);
      expect(backs(1), findsOneWidget);
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(tester.widget<PopupMenuItem<VoidCallback>>(menuItem('Show cards')).enabled, isFalse);
      await tester.tapAt(const Offset(5, 400));
      await tester.pumpAndSettle();
      await closeGame(tester, c);
    });

    test('the setup carries it into the next game, with the other toggles', () {
      final c = testController(extra: const {TurnController.showCardsKey: true});
      c.newGame();
      expect(c.showOpponentCards, isTrue);
      expect(LandlordChoice.of(c.record).extra[TurnController.showCardsKey], isTrue);
      c.dispose();
    });
  });

  group("a bot's range", () {
    testWidgets("in Training a tap on a bot's seat opens its range: the ranks, then every kind of combination", (
      tester,
    ) async {
      final c = await gameAt(tester, DdzPhase.playing);
      for (final seat in [1, 2]) {
        expect(c.canShowRange(seat), isTrue);
        await showGame(tester, c, pc, AppLanguage.english);
        await tester.tap(find.byKey(ValueKey('range tap $seat')));
        await tester.pump();
        await pumpUntil(tester, () => c.rangeOf(seat) != null);
        await tester.pump();
        expect(find.byKey(const ValueKey('range sheet')), findsOneWidget);
        expect(find.text('Range · ${c.seatName(seat)} · ${c.game.handSize(seat)} cards'), findsOneWidget);
        for (final kind in ddzRangeKinds) {
          expect(find.byKey(ValueKey('combo $kind')), findsOneWidget, reason: kind);
        }
        for (final label in ['Pairs', 'Trios', 'Straights', 'Pair straights', 'Airplanes', 'Bombs', 'Rocket', 'LJ', 'BJ', '10']) {
          expect(find.text(label), findsWidgets, reason: label);
        }
        // Never a rank the player holds all four of.
        final mine = countsOfIds(c.game.hands[0]);
        final range = c.rangeOf(seat)!;
        for (var r = 0; r <= Rank.two; r++) {
          if (mine[r] == 4) expect(range.ranks[r].chance(1), 0);
        }
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
      }
      await closeGame(tester, c);
    });

    testWidgets("a bot's seat shows the hand cursor in Training, and is only shown in Free Play", (tester) async {
      final c = await gameAt(tester, DdzPhase.playing);
      await showGame(tester, c, pc, AppLanguage.english);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(find.byKey(const ValueKey('seat 1'))));
      addTearDown(mouse.removePointer);
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.click,
      );
      await closeGame(tester, c);

      final free = await gameAt(tester, DdzPhase.playing, training: false);
      await showGame(tester, free, pc, AppLanguage.english);
      expect(find.byKey(const ValueKey('range tap 1')), findsNothing);
      expect(free.canShowRange(1), isFalse);
      await closeGame(tester, free);
    });

    test('the range names its ranks and combinations in every language', () {
      for (final language in AppLanguage.values) {
        final s = LandlordStrings.forLanguage(language);
        final look = landlordRangeLook(s);
        expect(look.rankLabel('T'), '10');
        expect(look.rankLabel('SJ'), s.jokerShort(big: false));
        expect(look.comboText!('TTJJQQ'), '10\u200910 JJ QQ');
        expect(look.comboText!('34567'), '3 4 5 6 7');
        expect(look.comboText!('333444'), '333 444');
        expect(look.comboText!('BR'), '${s.jokerShort(big: false)} ${s.jokerShort(big: true)}');
        expect(look.terms, hasLength(ddzRangeKinds.length), reason: 'each kind explained under "?"');
        for (final kind in ddzRangeKinds) {
          expect(look.comboLabel(kind), isNot(kind), reason: '$language $kind');
        }
      }
      expect(LandlordStrings.forLanguage(AppLanguage.chinese).rangeKind('pairs'), '连对');
      expect(LandlordStrings.forLanguage(AppLanguage.chinese).rangeKind('rocket'), '王炸');
    });

    test('its job comes from the game\'s list and asks from the player\'s view', () {
      final c = testController();
      c.newGame();
      final request = c.rangeRequest(c.record, 2, seed: 3)!;
      expect(request.job.name, 'doudizhu.range');
      expect(request.kind, JobKind.range);
      expect((request.input! as DdzRangeInput).viewer, LandlordController.you);
      expect(c.rangeRequest(c.record, LandlordController.you, seed: 3), isNull, reason: "no range of the player's own");
      expect(doudizhuJobs.any((j) => j.name == request.job.name), isTrue);
      c.dispose();
    });
  });
}
