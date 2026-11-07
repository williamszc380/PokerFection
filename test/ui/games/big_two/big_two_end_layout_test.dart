// At the end of a deal every bot's last cards are turned up under its
// badge, and the pile keeps the winning play lit in the middle: on a
// sideways phone the two must not lie on top of each other, or the top
// seat's cards hide (and are hidden by) the plays on the pile.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';

import '../../../kit/shots.dart';
import 'big_two_test_util.dart';

void main() {
  setUpAll(loadShotFonts);

  for (final size in bigTwoSizes) {
    testWidgets('after the deal the top seat\'s turned-up cards stay clear of the pile '
        '(${size.width.toInt()}x${size.height.toInt()})', (tester) async {
      final game = seededGame(seed: 9);
      await pumpGame(tester, game, size: size, language: AppLanguage.spanish);
      await playToEnd(tester, game);
      final top = find.descendant(of: find.byKey(const ValueKey('seat 2')), matching: find.byType(SeatHand));
      expect(top, findsOneWidget, reason: 'Ben still holds cards at the end of this deal');
      final cards = tester.getRect(top);
      final plays = find.byWidgetPredicate(
        (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('pile play'),
      );
      expect(plays, findsWidgets);
      for (final play in plays.evaluate()) {
        final rect = tester.getRect(find.byWidget(play.widget));
        expect(
          rect.overlaps(cards),
          isFalse,
          reason: '${(play.widget.key! as ValueKey<String>).value} at $rect lies under the top seat\'s cards at $cards',
        );
      }
      await closeGame(tester);
    });
  }
}
