// Fight the Landlord's hand in the player's own order, with its Sort
// button just above the hand's left end, and a card being dragged to a new
// place, at a sideways phone (568x320), a small PC window (900x420), a PC
// (1280x800) and an upright browser (390x844), in English, Spanish and
// Chinese. Each must fit (no overflow).
//
// PNGs go to the folder given with --dart-define=SHOTS=<folder>:
//   flutter test test/ui/games/doudizhu/hand_order_shots_test.dart --dart-define=SHOTS=<folder>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';

import '../../../kit/shots.dart';
import 'states.dart';

const sizes = [Size(568, 320), Size(900, 420), Size(1280, 800), Size(390, 844)];

void main() {
  setUpAll(loadShotFonts);

  testWidgets('the hand in the player\'s own order, the Sort button reading Sort, and a card mid-drag', (tester) async {
    final c = await reordered(tester);
    for (final language in AppLanguage.values) {
      for (final size in sizes) {
        final tag = shotTag(size, language);
        await showGame(tester, c, size, language);
        expect(tester.takeException(), isNull, reason: tag);
        await shot(tester, 'own_$tag');

        // A card picked up and carried three places to the right.
        final id = c.hand[1];
        final step = tester.getRect(handCard(c.hand[2])).left - tester.getRect(handCard(id)).left;
        final drag = await tester.startGesture(onCard(tester, id));
        for (var i = 0; i < 10; i++) {
          await drag.moveBy(Offset(step / 2, -step / 5));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull, reason: 'drag $tag');
        await shot(tester, 'drag_$tag');
        await drag.cancel();
        await tester.pumpAndSettle();
      }
    }
    await closeGame(tester, c);
  });

  testWidgets("a short hand late in the deal: the Sort button and the player's badge", (tester) async {
    final c = await lateGame(tester);
    for (final language in AppLanguage.values) {
      for (final size in sizes) {
        final tag = shotTag(size, language);
        await showGame(tester, c, size, language);
        expect(tester.takeException(), isNull, reason: tag);
        await shot(tester, 'late_$tag');
      }
    }
    await closeGame(tester, c);
  });
}
