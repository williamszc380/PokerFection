import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_jobs.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/kit/game_record.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/kit/seats.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_screen.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_setup.dart';
import 'package:pokerfection/src/ui/kit/kit_scope.dart';
import 'package:pokerfection/src/ui/kit/setup_kit.dart';

import '../../../kit/shots.dart';

const pc = Size(1280, 800);

/// The setup in a scope with [store] (the last game) and inline jobs.
Future<void> showSetup(WidgetTester tester, LastGames store) async {
  await pumpShot(
    tester,
    const LandlordSetup(),
    size: pc,
    wrap: (child) => KitScope(newJobs: Jobs.inline, lastGames: store, child: child),
  );
  await tester.pumpAndSettle();
}

/// Which segments of the choice row [key] can be picked.
List<bool> segments(WidgetTester tester, Key key) {
  final row = find.byKey(key);
  final button = tester.widget<SegmentedButton<int>>(
    find.descendant(of: row, matching: find.byType(SegmentedButton<int>)),
  );
  return [for (final s in button.segments) s.enabled];
}

bool switchOn(WidgetTester tester, String key) =>
    tester.widget<Switch>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Switch))).value;

Future<void> closeAll(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  setUpAll(loadShotFonts);

  testWidgets('it starts on the standard rules, one level for both bots, and Training', (tester) async {
    await showSetup(tester, LastGames());
    expect(find.text('Standard'), findsOneWidget);
    expect(switchOn(tester, 'four with two'), isTrue);
    expect(switchOn(tester, 'kitty shown'), isTrue);
    expect(switchOn(tester, 'customize seats'), isFalse);
    // Each bot's own level is greyed out (not hidden) until "Customize seats".
    expect(segments(tester, const ValueKey('seat level 0')), everyElement(isFalse));
    await tester.tap(find.byKey(const ValueKey('customize seats')));
    await tester.pumpAndSettle();
    expect(segments(tester, const ValueKey('seat level 0')), everyElement(isTrue));
    await closeAll(tester);
  });

  testWidgets('a preset sets the switches; changing a switch makes the rules Custom', (tester) async {
    await showSetup(tester, LastGames());
    final presets = find.byType(PresetRow<String>);
    PresetRow<String> row() => tester.widget<PresetRow<String>>(presets);
    expect(row().selected, 'standard');
    await tester.tap(find.text('Beginner'));
    await tester.pumpAndSettle();
    expect(row().selected, 'beginner');
    expect(switchOn(tester, 'four with two'), isFalse);
    await tester.tap(find.byKey(const ValueKey('four with two')));
    await tester.pumpAndSettle();
    expect(row().selected, isNull, reason: 'Custom');
    await closeAll(tester);
  });

  testWidgets('the multiplier cap is greyed out when nothing doubles', (tester) async {
    await showSetup(tester, LastGames());
    expect(segments(tester, const ValueKey('max multiplier')), everyElement(isTrue));
    await tester.tap(find.byKey(const ValueKey('bombs double')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('spring doubles')));
    await tester.pumpAndSettle();
    expect(segments(tester, const ValueKey('max multiplier')), everyElement(isFalse));
    await closeAll(tester);
  });

  testWidgets('it starts from the last game\'s choices, and Start opens the game with them', (tester) async {
    final store = LastGames();
    final last = ddzSampleGame(1, rules: DdzRules.app);
    store.save(
      GameRecord(
        game: last.game,
        version: last.version,
        seed: last.seed,
        rules: last.rules,
        seats: const [
          SeatSpec(human: true, name: 'Player'),
          SeatSpec(human: false, level: KitLevel.hard, name: 'Ana'),
          SeatSpec(human: false, level: KitLevel.easy, name: 'Ben'),
        ],
        deal: last.deal,
        moves: last.moves,
        extra: const {'mode': 'free', 'counter': false},
      ),
    );
    await store.flush();
    await showSetup(tester, store);
    expect(tester.widget<PresetRow<String>>(find.byType(PresetRow<String>)).selected, 'app');
    expect(switchOn(tester, 'customize seats'), isTrue, reason: 'the two bots had different levels');
    await tester.tap(find.byKey(const ValueKey('start')));
    await tester.pump();
    await tester.pump();
    final screen = tester.widget<LandlordScreen>(find.byType(LandlordScreen));
    expect(screen.choice.rules, DdzRules.app);
    expect(screen.choice.levels, [KitLevel.hard, KitLevel.easy]);
    expect(screen.choice.training, isFalse);
    expect(screen.choice.extra, {'counter': false});
    await closeAll(tester);
  });
}
