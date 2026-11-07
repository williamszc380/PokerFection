// The player's own seat badge is read at a glance like the bots': on a
// sideways phone it may shrink a little to fit, never to a fraction of
// theirs.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';

import '../../../kit/shots.dart';
import 'states.dart';

/// How much [key]'s badge is scaled down on screen (1: full size): the
/// badge shrinks its own box (SeatBadge.minScale) before it cuts words.
double scaleOf(WidgetTester tester, String key) {
  final box = find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(AnimatedContainer)).first;
  return tester.getRect(box).height / tester.getSize(box).height;
}

void main() {
  setUpAll(loadShotFonts);

  testWidgets('at 568x320 the player\'s badge is drawn about as large as the bots\'', (tester) async {
    // The deal of the Free Play screenshot: the player is the landlord, 20 cards.
    final c = await gameAt(tester, DdzPhase.playing, training: false, seed: 3);
    for (final language in AppLanguage.values) {
      await showGame(tester, c, const Size(568, 320), language);
      final player = scaleOf(tester, 'seat 0');
      final bot = scaleOf(tester, 'seat 1');
      expect(
        player,
        greaterThan(0.85 * bot),
        reason: '$language: the player\'s ×${player.toStringAsFixed(2)}, a bot\'s ×${bot.toStringAsFixed(2)}',
      );
      expect(player, greaterThanOrEqualTo(SeatBadge.minScale - 0.001), reason: '$language: never below the floor');
      expect(tester.takeException(), isNull, reason: '$language: nothing overflows');
    }
    await closeGame(tester, c);
  });
}
