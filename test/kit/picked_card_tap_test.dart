// A picked card pops up a fifth of its height: the part that rose is the
// most visible part of it (in a fan, the only part of it above its
// neighbours), so it must answer the mouse and the finger like the rest of
// the card: the hand cursor, a tap unpicks it, a drag can move it from there.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';
import 'package:pokerfection/src/ui/widgets/card_view.dart';

import '../ui/games/big_two/big_two_test_util.dart' as b2;
import 'shots.dart';

final _ten = [for (var i = 0; i < 10; i++) CardFace.suited(i, i % 4)];

/// A hand of ten with card 2 picked; returns the picked set and a point in
/// the top tenth of card 2 as drawn (risen), left of card 3.
Future<(Set<int>, Offset)> _pumpHand(WidgetTester tester, {required bool fanned, List<(int, int)>? moves}) async {
  final selected = <int>{2};
  await pumpShot(
    tester,
    StatefulBuilder(
      builder: (context, setState) => Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: 600,
          height: 140,
          child: HandFan(
            cards: _ten,
            fanned: fanned,
            selected: selected,
            onToggle: (i) => setState(() => selected.contains(i) ? selected.remove(i) : selected.add(i)),
            onReorder: moves == null ? null : (from, to) => moves.add((from, to)),
          ),
        ),
      ),
    ),
    size: const Size(600, 200),
  );
  await tester.pumpAndSettle();
  final drawn = tester.getRect(find.descendant(of: find.byType(GameCardView).at(2), matching: find.byType(CardView)));
  final next = tester.getRect(find.byType(GameCardView).at(3));
  final at = Offset((drawn.left + next.left) / 2, drawn.top + drawn.height * 0.08);
  expect(at.dx, lessThan(next.left), reason: 'the point is on card 2, not under card 3');
  return (selected, at);
}

void main() {
  setUpAll(loadShotFonts);

  for (final fanned in [true, false]) {
    final how = fanned ? 'fanned' : 'in a row';
    testWidgets('$how: a tap on the popped-up top of a picked card unpicks it', (tester) async {
      final (selected, at) = await _pumpHand(tester, fanned: fanned);
      await tester.tapAt(at);
      await tester.pump();
      expect(selected, isEmpty, reason: 'tapped the risen part of the picked card');
    });

    testWidgets('$how: the popped-up top of a picked card shows the hand cursor', (tester) async {
      final (_, at) = await _pumpHand(tester, fanned: fanned);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(at);
      await tester.pump();
      expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.click);
    });

    testWidgets('$how: a drag starting on the popped-up top of a picked card moves that card', (tester) async {
      final moves = <(int, int)>[];
      final (selected, at) = await _pumpHand(tester, fanned: fanned, moves: moves);
      final cards = find.byType(GameCardView);
      final to = tester.getRect(cards.at(5)).center;
      final from = tester.getRect(cards.at(2)).center;
      await tester.dragFrom(at, Offset(to.dx - from.dx, 0));
      await tester.pumpAndSettle();
      expect(moves, [(2, 5)], reason: 'the drag began on picked card 2 and took it to 5');
      expect(selected, {2}, reason: 'no pick changed (this hand keeps picks by place; a game keeps them by card)');
    });
  }

  testWidgets('fanned: the empty slot under a picked card belongs to the card beneath it', (tester) async {
    final (selected, _) = await _pumpHand(tester, fanned: true);
    final slot = tester.getRect(find.byType(GameCardView).at(2));
    final card1 = tester.getRect(find.byType(GameCardView).at(1));
    final at = Offset(slot.left + slot.width * 0.15, slot.bottom - slot.height * 0.06);
    expect(at.dx, lessThan(card1.right - 4), reason: 'card 1 lies under that strip');
    await tester.tapAt(at);
    await tester.pump();
    expect(selected, {1, 2}, reason: 'picked card 1 (seen there), not unpicked card 2');
  });

  testWidgets("in a row: the mouse at a card's bottom edge lifts it and it stays lifted", (tester) async {
    await _pumpHand(tester, fanned: false);
    final slot = tester.getRect(find.byType(GameCardView).at(5));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(Offset(slot.center.dx, slot.bottom - 1));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    final drawn = tester.getRect(find.descendant(of: find.byType(GameCardView).at(5), matching: find.byType(CardView)));
    expect(drawn.top, closeTo(slot.top - slot.height * GameCardView.hoverLift, 0.5), reason: 'lifted, not bouncing');
    expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.click);
  });

  testWidgets('Big Two at 568x320: a tap on the popped-up top of a picked card unpicks it', (tester) async {
    final game = b2.seededGame(training: false, rules: BigTwoRules.standard(players: 2));
    await b2.pumpGame(tester, game, size: const Size(568, 320));
    await b2.toMyPlayableTurn(tester, game);
    final card = game.hand[6];
    game.toggle(card);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final views = find.descendant(of: find.byKey(const ValueKey('hand')), matching: find.byType(GameCardView));
    final i = views.evaluate().toList().indexWhere((e) => (e.widget as GameCardView).selected);
    final drawn = tester.getRect(find.descendant(of: views.at(i), matching: find.byType(CardView)));
    final next = tester.getRect(views.at(i + 1));
    final at = Offset(drawn.left + 3, drawn.top + drawn.height * 0.06);
    expect(at.dx, lessThan(next.left));
    await tester.tapAt(at);
    await tester.pump();
    expect(game.selected.contains(card), isFalse, reason: 'tapped the visible top of the picked card');
    await b2.closeGame(tester);
  });
}
