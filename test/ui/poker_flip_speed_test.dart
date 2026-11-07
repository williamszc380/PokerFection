// Poker's cards turn over at the Animations setting's speed too: 400 ms at
// Normal (unchanged), quicker at Fast, at once at Instant, like the new
// games' cards.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;
import 'package:pokerfection/src/ui/widgets/card_view.dart';

import '../kit/shots.dart';

void main() {
  for (final speed in PlaybackSpeed.values) {
    testWidgets("a poker card's flip at ${speed.label}", (tester) async {
      await pumpShot(
        tester,
        const Center(child: CardView(width: 60)),
        size: const Size(200, 200),
        wrap: (app) => AppSettingsScope(settings: AppSettings()..speed = speed, child: app),
      );
      expect(
        tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration,
        const Duration(milliseconds: 400) * speed.factor,
      );
    });
  }
}
