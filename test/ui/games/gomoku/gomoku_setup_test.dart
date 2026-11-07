import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/gomoku/app/gomoku_record.dart';
import 'package:pokerfection/src/games/gomoku/gomoku.dart';
import 'package:pokerfection/src/kit/seats.dart';
import 'package:pokerfection/src/ui/games/gomoku/gomoku_screen.dart';
import 'package:pokerfection/src/ui/games/gomoku/gomoku_setup.dart';
import 'package:pokerfection/src/ui/games/gomoku/l10n/gomoku_strings.dart';
import 'package:pokerfection/src/ui/games/gomoku/l10n/gomoku_strings_en.dart';
import 'package:pokerfection/src/ui/kit/game_sounds.dart';
import 'package:pokerfection/src/ui/kit/setup_kit.dart';

import '../../../kit/shots.dart';
import 'gomoku_harness.dart';

/// The segment of the choice row [row] showing [label].
Finder _segment(String row, String label) => find.descendant(of: find.byKey(ValueKey(row)), matching: find.text(label));

/// Whether that segment can be chosen (greyed out otherwise).
bool _segmentEnabled(WidgetTester tester, String row, String label) {
  final button = tester.widget<SegmentedButton<int>>(
    find.descendant(of: find.byKey(ValueKey(row)), matching: find.byType(SegmentedButton<int>)),
  );
  return button.segments.firstWhere((s) => (s.label! as Text).data == label).enabled;
}

/// The label of the selected segment of [row].
String _selected(WidgetTester tester, String row) {
  final button = tester.widget<SegmentedButton<int>>(
    find.descendant(of: find.byKey(ValueKey(row)), matching: find.byType(SegmentedButton<int>)),
  );
  return (button.segments.firstWhere((s) => button.selected.contains(s.value)).label! as Text).data!;
}

void main() {
  setUpAll(loadShotFonts);
  setUp(() => GameSounds.output = (_) {});
  const en = GomokuStringsEn();

  testWidgets('starts from the defaults: Freestyle, 15×15, Black, Medium, Training', (tester) async {
    await pumpGomoku(tester, const GomokuSetup());
    expect(_selected(tester, 'rule'), 'Freestyle');
    expect(_selected(tester, 'board'), '15×15');
    expect(_selected(tester, 'color'), 'Black');
    expect(find.text('Medium'), findsOneWidget);
    await closeGomoku(tester);
  });

  testWidgets('Renju greys out 19×19 (it is played on 15×15) and moves a 19×19 board back', (tester) async {
    await pumpGomoku(tester, const GomokuSetup());
    await tester.tap(_segment('board', '19×19'));
    await tester.pump();
    expect(_selected(tester, 'board'), '19×19');
    await tester.tap(_segment('rule', 'Renju'));
    await tester.pump();
    expect(_selected(tester, 'board'), '15×15');
    expect(_segmentEnabled(tester, 'board', '19×19'), isFalse);
    expect(_segment('board', '19×19'), findsOneWidget, reason: 'greyed out, not hidden');
    await tester.tap(_segment('rule', 'Standard'));
    await tester.pump();
    expect(_segmentEnabled(tester, 'board', '19×19'), isTrue);
    await closeGomoku(tester);
  });

  testWidgets('the "?" by the colour says Black has the edge', (tester) async {
    await pumpGomoku(tester, const GomokuSetup());
    final colorHelp = find.descendant(
      of: find.ancestor(of: find.text(en.you), matching: find.byType(SetupSection)),
      matching: find.byIcon(Icons.help_outline),
    );
    await tester.tap(colorHelp);
    await tester.pumpAndSettle();
    expect(find.text(en.definition(GomokuTerm.firstMove)), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await closeGomoku(tester);
  });

  testWidgets('Start opens the game with the choices made', (tester) async {
    await pumpGomoku(tester, const GomokuSetup());
    await tester.tap(_segment('rule', 'Standard'));
    await tester.tap(_segment('color', 'White'));
    await tester.tap(find.text('Hard'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('start')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final screen = tester.widget<GomokuScreen>(find.byType(GomokuScreen));
    expect(
      screen.options,
      const GomokuOptions(rules: GomokuRules.standard, color: GomokuColorChoice.white, level: KitLevel.hard),
    );
    await closeGomoku(tester);
  });

  testWidgets('starts from the last game\'s choices and toggles', (tester) async {
    final games = LastGames();
    const last = GomokuOptions(
      rules: GomokuRules.renju,
      color: GomokuColorChoice.random,
      level: KitLevel.easy,
      training: false,
    );
    games.save(GomokuRecord.start(last, seed: 3, moves: ['h8']).withExtra('coach', false));
    await pumpGomoku(tester, const GomokuSetup(), lastGames: games);
    expect(_selected(tester, 'rule'), 'Renju');
    expect(_selected(tester, 'color'), 'Random');
    await tester.tap(find.byKey(const ValueKey('start')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final screen = tester.widget<GomokuScreen>(find.byType(GomokuScreen));
    expect(screen.options, last);
    expect(screen.toggles, {'coach': false});
    await closeGomoku(tester);
  });

  group('fits every size and language', () {
    for (final size in gomokuSizes) {
      for (final language in AppLanguage.values) {
        testWidgets(shotTag(size, language), (tester) async {
          await pumpGomoku(tester, const GomokuSetup(), size: size, language: language);
          expect(tester.takeException(), isNull);
          expect(onScreen(tester, find.byKey(const ValueKey('start'))), isTrue, reason: 'Start stays in view');
          if (size.height >= 800) {
            // Big screens show every choice without scrolling.
            for (final scrollable in tester.stateList<ScrollableState>(find.byType(Scrollable))) {
              if (scrollable.axisDirection == AxisDirection.down) expect(scrollable.position.maxScrollExtent, 0);
            }
          }
          await closeGomoku(tester);
        });
      }
    }
  });
}
