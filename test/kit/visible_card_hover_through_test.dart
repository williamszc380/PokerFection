// A hand that can't be played from (not the player's turn, the step that
// opens a deal, a spectator's seat) still says "Everyone can see this
// card" only over the card everyone can see: never while the mouse is over
// the card lying on top of it, nor over two cards at once.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';

import 'shots.dart';

final _eight = [for (var i = 0; i < 8; i++) CardFace.suited(i + 1, i % 4)];
final _labelBox = find.byKey(const ValueKey('visible label'));

Future<TestGesture> _mouseAt(WidgetTester tester, Offset at) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: at);
  addTearDown(mouse.removePointer);
  await tester.pump();
  return mouse;
}

void main() {
  testWidgets('a hand that takes no taps: over the card on top of the visible one, no label', (tester) async {
    await pumpShot(
      tester,
      Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: 260,
          height: 140,
          // No onToggle: the hand can't be played from now.
          child: HandFan(cards: _eight, visibleToAll: const {0}, fanned: false),
        ),
      ),
      size: const Size(800, 400),
    );
    final first = tester.getRect(find.byKey(ValueKey('${_eight[0]}#1')));
    final second = tester.getRect(find.byKey(ValueKey('${_eight[1]}#1')));
    expect(second.left, lessThan(first.right), reason: 'the second card lies over the first');
    // Over the second card, where it covers the first.
    final over = Offset((second.left + first.right) / 2, first.center.dy);
    await _mouseAt(tester, over);
    expect(_labelBox, findsNothing, reason: 'the mouse is over the 4, not the visible 3');
  });

  testWidgets('a seat with two visible cards side by side: one label at a time', (tester) async {
    await pumpShot(
      tester,
      Center(
        child: SeatHand(count: 13, cardWidth: 40, visibleToAll: [_eight[0], _eight[1]]),
      ),
      size: const Size(600, 300),
    );
    final cards = find.byType(GameCardView);
    final last = tester.getRect(cards.last);
    final before = tester.getRect(cards.at(cards.evaluate().length - 2));
    expect(last.left, lessThan(before.right));
    await _mouseAt(tester, Offset((last.left + before.right) / 2, last.center.dy));
    await shot(tester, 'review_kit_two_visible_hover');
    expect(_labelBox, findsOneWidget, reason: 'the card on top says so, once');
  });
}
