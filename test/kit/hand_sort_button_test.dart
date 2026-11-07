// The hand's Sort button: a detached pill just above the left end of the
// cards, clearly visible, never over a card (even a picked one), showing
// the order the hand is in ("Rank", "Suit") or, once the player has moved
// a card, "Sort". One place to sort.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';
import 'package:pokerfection/src/ui/kit/felt.dart';
import 'package:pokerfection/src/ui/kit/game_scaffold.dart';
import 'package:pokerfection/src/ui/widgets/card_view.dart';

import 'shots.dart';

const _shotSizes = [Size(568, 320), Size(900, 420), Size(1280, 800), Size(390, 844)];

/// [n] cards of a Big Two deal (no jokers), lowest first.
List<CardFace> _deal(int n) => [for (var i = 0; i < n; i++) CardFace.suited((i * 5) % 13, (i * 3) % 4)];

/// A game screen's split (the table, the hand under it, the panel at the
/// side) with only the hand in it, as Big Two and Fight the Landlord lay
/// it out: padded 8, 4, 8, 6.
Widget _screen({
  required List<CardFace> cards,
  Set<int> selected = const {},
  HandOrder? order = HandOrder.rank,
  VoidCallback? onSort,
  void Function(int from, int to)? onReorder,
  void Function(int)? onToggle,
}) =>
    Scaffold(
      appBar: AppBar(title: const Text('Big Two')),
      body: LayoutBuilder(
        builder: (context, constraints) => GameScaffold.split(
          constraints: constraints,
          table: const FeltArea(),
          bottom: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
            child: HandFan(
              key: const ValueKey('the hand'),
              cards: cards,
              selected: selected,
              sortOrder: order,
              onSort: onSort,
              onToggle: onToggle ?? (_) {},
              onReorder: onReorder ?? (_, _) {},
              showing: 0.46,
              maxCardWidth: 76,
            ),
          ),
          panel: (_) => const SizedBox.expand(),
        ),
      ),
    );

final _button = find.byKey(const ValueKey('hand sort'));

List<Rect> _drawnCards(WidgetTester tester) => [
      for (final e in find.descendant(of: find.byType(HandFan), matching: find.byType(CardView)).evaluate())
        tester.getRect(find.byWidget(e.widget)),
    ];

void main() {
  setUpAll(loadShotFonts);

  testWidgets('it reads Rank, Suit, or Sort once the order is the player\'s own, in each language', (tester) async {
    const words = {
      AppLanguage.english: ['Rank', 'Suit', 'Sort'],
      AppLanguage.spanish: ['Valor', 'Palo', 'Ordenar'],
      AppLanguage.chinese: ['点数', '花色', '排序'],
    };
    for (final MapEntry(key: language, value: labels) in words.entries) {
      for (final order in HandOrder.values) {
        await pumpShot(tester, _screen(cards: _deal(13), order: order, onSort: () {}), size: const Size(568, 320), language: language);
        expect(find.descendant(of: _button, matching: find.text(labels[order.index])), findsOneWidget, reason: '$language $order');
        expect(find.descendant(of: _button, matching: find.byIcon(Icons.sort)), findsOneWidget);
      }
    }
  });

  testWidgets('a tap sorts; under the mouse the hand cursor and a highlight; greyed out (never hidden) without onSort',
      (tester) async {
    var taps = 0;
    await pumpShot(tester, _screen(cards: _deal(13), onSort: () => taps++), size: const Size(900, 420));
    await tester.tap(_button);
    expect(taps, 1);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(_button));
    await tester.pumpAndSettle();
    expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.click);
    final ink = tester.widget<InkWell>(find.descendant(of: _button, matching: find.byType(InkWell)));
    expect(ink.hoverColor!.a, greaterThan(0.15), reason: 'a visible highlight');
    await shot(tester, 'sort_hover_en_900x420');

    await pumpShot(tester, _screen(cards: _deal(13)), size: const Size(900, 420));
    expect(_button, findsOneWidget, reason: 'greyed out, still there');
    expect(tester.widget<Opacity>(find.descendant(of: _button, matching: find.byType(Opacity)).first).opacity, lessThan(1));
    await mouse.moveTo(tester.getCenter(_button) + const Offset(1, 0));
    await tester.pump();
    expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.basic);
  });

  for (final size in _shotSizes) {
    final tag = shotTag(size, AppLanguage.english);
    for (final n in [13, 17, 20]) {
      testWidgets('$tag, $n cards all picked: the button sits just above the left end, over no card, inside the hand',
          (tester) async {
        await pumpShot(
          tester,
          _screen(cards: _deal(n), selected: {for (var i = 0; i < n; i++) i}, order: HandOrder.suit, onSort: () {}),
          size: size,
        );
        await tester.pumpAndSettle();
        final button = tester.getRect(_button);
        final hand = tester.getRect(find.byKey(const ValueKey('the hand')));
        final cards = _drawnCards(tester);
        expect(cards, hasLength(n));
        expect(button.left, greaterThanOrEqualTo(hand.left - 0.5));
        // Where the hand has no room above its cards, over the table's edge.
        expect(button.top, greaterThan(hand.top - button.height - 8), reason: 'just above the hand');
        for (final (i, card) in cards.indexed) {
          expect(button.overlaps(card.deflate(0.5)), isFalse, reason: 'card $i, picked, stays clear of the button');
        }
        final first = cards.first;
        expect((button.left - first.left).abs(), lessThan(6), reason: 'at the left end of the fan');
        expect(first.top - button.bottom, lessThan(GameCardView.maxLift * first.height + 12), reason: 'just above it');
        expect(button.height, greaterThanOrEqualTo(25.9), reason: 'big enough to see and tap');
        if (n == 17) await shot(tester, 'sort_all_picked_$tag');
      });
    }
  }

  test('the cards never get smaller for the button', () {
    for (final (n, box) in [(13, const Size(276, 74.5)), (20, const Size(276, 74.5)), (17, const Size(848, 150))]) {
      final plain = HandFanGeometry(n, box, 76, showing: 0.46);
      final withButton = HandFanGeometry(n, box, 76, showing: 0.46, corner: const Size(64, 26));
      expect(withButton.width, plain.width);
      expect([for (var i = 0; i < n; i++) withButton.center(i)], [for (var i = 0; i < n; i++) plain.center(i)]);
    }
    // An upright browser's hand leaves room above its cards: the button stays in the hand.
    expect(HandFanGeometry(17, const Size(374, 163), 76, showing: 0.46, corner: const Size(64, 26)).corner!.top, greaterThan(0));
    // A sideways phone's cards take the hand's whole height: the button rises above its box.
    expect(HandFanGeometry(13, const Size(276, 74.5), 76, showing: 0.46, corner: const Size(64, 26)).corner!.top, lessThan(0));
  });

  testWidgets('risen above the hand (13 cards on a sideways phone), the button still answers taps and the mouse', (tester) async {
    var taps = 0;
    await pumpShot(tester, _screen(cards: _deal(13), onSort: () => taps++), size: const Size(568, 320));
    await tester.pumpAndSettle();
    final button = tester.getRect(_button);
    final hand = tester.getRect(find.byKey(const ValueKey('the hand')));
    expect(button.top, lessThan(hand.top), reason: "over the table's edge");
    await tester.tapAt(Offset(button.center.dx, button.top + 4));
    expect(taps, 1);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(Offset(button.center.dx, button.top + 4));
    await tester.pump();
    expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.click);
    await shot(tester, 'sort_risen_en_568x320');
  });

  for (final size in _shotSizes.take(3)) {
    testWidgets('screenshots at ${shotTag(size, AppLanguage.english)}: the button, then a card mid-drag', (tester) async {
      var cards = _deal(17);
      var order = HandOrder.rank;
      late StateSetter set;
      await pumpShot(
        tester,
        StatefulBuilder(builder: (context, setState) {
          set = setState;
          return _screen(
            cards: cards,
            selected: {2, 9},
            order: order,
            onSort: () {},
            onReorder: (from, to) => setState(() {
              cards = moveCard(cards, from, to);
              order = HandOrder.own;
            }),
          );
        }),
        size: size,
      );
      await tester.pumpAndSettle();
      await shot(tester, 'sort_rank_${shotTag(size, AppLanguage.english)}');
      final views = find.descendant(of: find.byType(HandFan), matching: find.byType(GameCardView));
      // On the part of card 4 in view, toward card 11's place.
      final from = tester.getRect(views.at(4)).centerLeft + Offset(tester.getRect(views.at(4)).width * 0.2, 0);
      final to = from + tester.getCenter(views.at(11)) - tester.getCenter(views.at(4));
      final gesture = await tester.startGesture(from);
      for (var k = 1; k <= 8; k++) {
        await gesture.moveTo(Offset.lerp(from, to, k / 8)! + Offset(0, -12.0 * k / 8));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();
      await shot(tester, 'drag_mid_${shotTag(size, AppLanguage.english)}');
      await gesture.up();
      await tester.pumpAndSettle();
      expect(order, HandOrder.own);
      await shot(tester, 'drag_done_${shotTag(size, AppLanguage.english)}');
      set(() {});
      await pumpShot(tester, _screen(cards: _deal(20), order: HandOrder.own, onSort: () {}), size: size, language: AppLanguage.spanish);
      await tester.pumpAndSettle();
      await shot(tester, 'sort_own_${shotTag(size, AppLanguage.spanish)}');
    });
  }
}
