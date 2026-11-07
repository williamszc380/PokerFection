// The player's own order in Fight the Landlord: dragging a card moves it
// within the hand, a tap still picks it, and the Sort button just above the
// hand's left end shows the order (Rank, Suit, or Sort once the order is
// the player's own) and sorts it. The order lives in the record's extra
// ('sort', 'order'): the cards played drop out of it, the kitty joins it at
// the end, a new deal starts sorted by the sort last chosen, and the review
// shows the hand as the player laid it out.
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_record.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_cards.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_controller.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_review.dart';
import 'package:pokerfection/src/ui/kit/card_flights.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';
import 'package:pokerfection/src/ui/kit/kit_scope.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';
import 'package:pokerfection/src/ui/kit/table_pile.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import '../../../kit/shots.dart';
import 'helpers.dart';
import 'states.dart';

const pc = Size(1280, 800);

final sortButton = find.byKey(const ValueKey('hand sort'));

HandFan hand(WidgetTester tester) => tester.widget<HandFan>(find.byKey(const ValueKey('hand')));

/// The words on the Sort button.
String sortLabel(WidgetTester tester) =>
    tester.widget<Text>(find.descendant(of: sortButton, matching: find.byType(Text))).data!;

/// Drags card [id] [places] places along the hand (by a [kind] pointer, in
/// small steps) and lets go.
Future<void> dragCard(
  WidgetTester tester,
  LandlordController c,
  int id,
  int places, {
  PointerDeviceKind kind = PointerDeviceKind.touch,
}) async {
  final step = tester.getRect(handCard(c.hand[1])).left - tester.getRect(handCard(c.hand[0])).left;
  final drag = await tester.startGesture(onCard(tester, id), kind: kind);
  final moves = places.abs() * 3;
  for (var i = 0; i < moves; i++) {
    await drag.moveBy(Offset(places.sign * step / 3, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await drag.up();
  await tester.pumpAndSettle();
}

/// The player's first bid in a deal where they may bid 3 (and take the
/// kitty).
Future<LandlordController> canBidThree(WidgetTester tester) async {
  for (var s = 1; s < 60; s++) {
    final c = testController(seed: s, training: false);
    c.newGame();
    await pumpUntil(
      tester,
      () => c.isOver || (c.seatToAct == LandlordController.you && c.forcedMove(LandlordController.you) == null),
    );
    if (!c.isOver && c.game.phase == DdzPhase.bidding && c.game.legalMoves().contains(const DdzBid(3))) return c;
    c.dispose();
  }
  throw StateError('the player could never bid 3');
}

void main() {
  setUpAll(loadShotFonts);

  group('sorting by suit', () {
    test('the jokers first, then spades, hearts, clubs and diamonds, each highest first', () {
      // Ids are rank * 4 + suit (rank 0 the 3; suits clubs, diamonds,
      // hearts, spades); 52 and 53 the jokers.
      int card(int rank, int suit) => rank * 4 + suit;
      final hand = [card(0, 3), card(12, 1), 52, card(11, 3), card(5, 2), card(5, 0), 53, card(7, 1)];
      expect(ddzSortedBySuit(hand), [53, 52, card(11, 3), card(0, 3), card(5, 2), card(5, 0), card(12, 1), card(7, 1)]);
    });

    test('Rank keeps the highest-first order the hand always had', () {
      final hand = [0, 51, 52, 13, 30];
      expect(ddzHandSorted(hand, HandOrder.rank), ddzSorted(hand));
      expect(ddzHandSorted(hand, HandOrder.suit), ddzSortedBySuit(hand));
    });
  });

  group('the controller', () {
    testWidgets('the hand starts by rank; Sort switches it to suits and back, and the record keeps the choice', (
      tester,
    ) async {
      final c = await gameAt(tester, DdzPhase.playing, training: false);
      expect(c.arrangement.order, HandOrder.rank);
      expect(c.hand, ddzSorted(c.game.hands[0]));
      c.sortTap();
      expect(c.arrangement.order, HandOrder.suit);
      expect(c.hand, ddzSortedBySuit(c.game.hands[0]));
      expect(c.record.extra['sort'], 'suit');
      c.sortTap();
      expect(c.hand, ddzSorted(c.game.hands[0]));
      expect(c.record.extra['sort'], 'rank');
      await closeGame(tester, c);
    });

    testWidgets('moving a card makes the order the player\'s own; Sort then sorts again by the sort last chosen', (
      tester,
    ) async {
      final c = await gameAt(tester, DdzPhase.playing, training: false);
      c.sortTap(); // Suit.
      final before = c.hand;
      c.reorder(0, 5);
      expect(c.hand, [...before.sublist(1, 6), before[0], ...before.sublist(6)]);
      expect(c.arrangement.order, HandOrder.own);
      expect(c.record.extra['order'], c.hand, reason: 'saved with the deal');
      c.sortTap();
      expect(c.arrangement.order, HandOrder.suit);
      expect(c.hand, before);
      expect(c.record.extra['order'], isNull);
      await closeGame(tester, c);
    });

    testWidgets('the cards played leave the player\'s order; the others keep their places', (tester) async {
      final c = await gameAt(tester, DdzPhase.playing, training: false, leading: true);
      c.clearSelection();
      c.reorder(c.hand.length - 1, 0);
      final mine = c.hand;
      final played = mine[3];
      c.toggle(played);
      c.playSelection();
      expect(c.hand, [...mine]..remove(played));
      expect(c.arrangement.order, HandOrder.own);
      await closeGame(tester, c);
    });

    testWidgets('a card played while the hand was sorted keeps its sorted place in the review after a drag', (
      tester,
    ) async {
      final c = await gameAt(tester, DdzPhase.playing, training: false, leading: true);
      c.clearSelection();
      final played = c.hand[3];
      c.toggle(played);
      c.playSelection();
      final last = c.hand.last;
      c.reorder(c.hand.length - 1, 0);
      expect(c.hand, isNot(contains(played)), reason: 'the live hand has no played card');
      // The review's first step: the cards dealt, in the order the deal ended with.
      final dealt = ddzSorted(ddzReplay(c.record, upTo: 0).hands[0]);
      expect(c.arrangement.arrange(dealt), [
        if (dealt.contains(last)) last,
        for (final id in dealt)
          if (id != last) id,
      ], reason: 'every card where it lay; only the one dragged has moved');
      await closeGame(tester, c);
    });

    testWidgets('the kitty joins the player\'s own order at its end, in the order the sort gives it', (tester) async {
      final c = await canBidThree(tester);
      c.reorder(0, c.hand.length - 1);
      final mine = c.hand;
      c.humanMove(yours(const DdzBid(3)));
      expect(c.game.landlord, LandlordController.you);
      expect(c.hand, [...mine, ...ddzSorted(c.game.kitty)]);
      await closeGame(tester, c);
    });

    testWidgets('a new deal starts sorted, by the sort last chosen; a new session starts from the last game\'s sort', (
      tester,
    ) async {
      final c = await finishedGame(tester, training: false);
      c.sortTap(); // Suit; then the player's own order.
      c.reorder(0, 3);
      unawaited(c.nextRound());
      await tester.pump();
      expect(c.arrangement.order, HandOrder.suit);
      expect(c.record.extra['order'], isNull, reason: 'the last deal\'s order belonged to its cards');
      expect(c.hand, ddzSortedBySuit(c.game.hands[0]));

      final next = testController(extra: LandlordChoice.of(c.record).extra)..newGame();
      expect(next.arrangement.order, HandOrder.suit);
      next.dispose();
      await closeGame(tester, c);
    });
  });

  group('the screen', () {
    testWidgets('dragging a card moves it, by touch and with the mouse; a tap still picks a card', (tester) async {
      final c = await gameAt(tester, DdzPhase.playing, training: false, leading: true);
      c.clearSelection();
      await showGame(tester, c, pc, AppLanguage.english);
      for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
        final before = c.hand;
        await dragCard(tester, c, before[1], 3, kind: kind);
        expect(c.hand, moveCard(before, 1, 4), reason: '$kind');
        expect(c.selected, isEmpty, reason: '$kind: a drag picks nothing');
      }
      expect(sortLabel(tester), 'Sort');

      await tester.tap(handCard(c.hand[0]));
      await tester.pump();
      expect(c.selected, {c.hand[0]});
      // Picking several cards is a tap on each.
      await tester.tap(handCard(c.hand[5]));
      await tester.pump();
      expect(c.selected, {c.hand[0], c.hand[5]});
      await closeGame(tester, c);
    });

    testWidgets('the Sort button: just above the hand\'s left end, over no card, a hand cursor; a tap sorts', (
      tester,
    ) async {
      final c = await gameAt(tester, DdzPhase.playing, training: false);
      await showGame(tester, c, pc, AppLanguage.english);
      expect(sortLabel(tester), 'Rank');
      final button = tester.getRect(sortButton);
      final first = tester.getRect(handCard(c.hand.first));
      expect(button.bottom, lessThanOrEqualTo(first.top + 0.5), reason: 'above the cards');
      expect((button.left - first.left).abs(), lessThan(12), reason: 'at the hand\'s left end');
      expect(
        find.descendant(
          of: sortButton,
          matching: find.byWidgetPredicate((w) => w is MouseRegion && w.cursor == SystemMouseCursors.click),
        ),
        findsWidgets,
      );
      await tester.tap(sortButton);
      await tester.pump();
      expect(sortLabel(tester), 'Suit');
      expect(c.hand, ddzSortedBySuit(c.game.hands[0]));
      await tester.tap(sortButton);
      await tester.pump();
      expect(sortLabel(tester), 'Rank');
      await closeGame(tester, c);
    });

    testWidgets('the button reads the order in each language: Rank / Valor / 点数, Suit / Palo / 花色, then Sort', (
      tester,
    ) async {
      final c = await gameAt(tester, DdzPhase.playing, training: false);
      for (final language in AppLanguage.values) {
        final k = KitStrings.forLanguage(language);
        await showGame(tester, c, pc, language);
        expect(sortLabel(tester), k.handOrder(c.arrangement.order), reason: '$language');
      }
      expect(KitStrings.forLanguage(AppLanguage.spanish).handOrder(HandOrder.rank), 'Valor');
      expect(KitStrings.forLanguage(AppLanguage.chinese).handOrder(HandOrder.suit), '花色');
      await closeGame(tester, c);
    });

    testWidgets('once the deal is over nothing in the hand moves, and the button is greyed out, never hidden', (
      tester,
    ) async {
      final c = await finishedGame(tester, training: false);
      await showGame(tester, c, pc, AppLanguage.english);
      expect(sortButton, findsOneWidget);
      expect(hand(tester).onSort, isNull);
      expect(hand(tester).onReorder, isNull);
      await closeGame(tester, c);
    });

    for (final size in const [Size(568, 320), Size(900, 420), Size(1280, 800), Size(390, 844)]) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()}: the Sort button covers neither the player\'s badge '
          'nor the kitty, with a long hand or a short one', (tester) async {
        for (final c in [await reordered(tester), await lateGame(tester)]) {
          for (final language in AppLanguage.values) {
            await showGame(tester, c, size, language);
            final button = tester.getRect(sortButton);
            for (final key in ['seat 0', 'kitty up', 'kitty down']) {
              final place = find.byKey(ValueKey(key));
              if (place.evaluate().isEmpty) continue;
              final overlap = button.intersect(tester.getRect(place));
              expect(
                overlap.width <= 0 || overlap.height <= 0,
                isTrue,
                reason: '$language, ${c.hand.length} cards: $key',
              );
            }
            expect(tester.takeException(), isNull);
          }
          await closeGame(tester, c);
        }
      });
    }

    testWidgets('a play flies from where the card lies in the player\'s own order', (tester) async {
      var speed = PlaybackSpeed.instant;
      LandlordController? found;
      for (var s = 1; s < 60 && found == null; s++) {
        final t = testController(seed: s, training: false, speedNow: () => speed);
        t.newGame();
        for (var guard = 0; guard < 150 && !t.isOver; guard++) {
          await pumpUntil(
            tester,
            () => t.isOver || (t.seatToAct == LandlordController.you && t.forcedMove(LandlordController.you) == null),
          );
          if (t.isOver) break;
          if (t.game.phase == DdzPhase.playing && t.game.isLead) {
            found = t;
            break;
          }
          t.humanMove(easyMove(t));
        }
        if (found == null) t.dispose();
      }
      final c = found!;
      speed = PlaybackSpeed.normal;
      final card = c.hand.last;
      c.reorder(c.hand.length - 1, 0);
      await showGame(tester, c, pc, AppLanguage.english);
      expect(tester.getRect(handCard(card)).left, lessThan(tester.getRect(handCard(c.hand[1])).left));
      c.toggle(card);
      await tester.pump();
      final from = tester.getCenter(handCard(card));
      c.playSelection();
      final index = c.game.history.length - 1;
      await tester.pump();
      final flying = find.byKey(CardFlights.flyingKey(TablePile.flightTag(index, 0)));
      expect(flying, findsOneWidget);
      expect((tester.getCenter(flying) - from).distance, lessThan(30), reason: 'it leaves from its place in the hand');
      speed = PlaybackSpeed.instant;
      await tester.pump(const Duration(seconds: 1));
      await closeGame(tester, c);
    });
  });

  testWidgets('the review shows the hand as the player laid it out, its Sort button greyed out', (tester) async {
    final c = await finishedGame(tester, training: false);
    final dealt = ddzSorted(ddzReplay(c.record, upTo: 0).hands[0]);
    final own = dealt.reversed.toList();
    final record = c.record.withExtra('sort', 'rank').withExtra('order', own);
    c.dispose();
    await tester.pump(const Duration(seconds: 1));
    await pumpShot(
      tester,
      LandlordReview(record: record),
      size: pc,
      wrap: (child) => KitScope(newJobs: Jobs.inline, lastGames: LastGames(), child: child),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump(const Duration(milliseconds: 500));
    expect(hand(tester).cards, [for (final id in own) ddzFace(id)]);
    expect(hand(tester).sortOrder, HandOrder.own);
    expect(hand(tester).onSort, isNull);
    expect(hand(tester).onReorder, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
