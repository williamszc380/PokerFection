// Screenshots of choosing from the coach list in Gomoku (a row clicked
// once: its point aimed at and the row lit; under Renju, Pass lit when it
// is the only move), at four sizes in the three languages. PNGs are
// written only with --dart-define=SHOTS=<folder>; without it this runs as
// one more overflow check.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/gomoku/app/gomoku_record.dart';
import 'package:pokerfection/src/games/gomoku/gomoku.dart';
import 'package:pokerfection/src/kit/seats.dart';
import 'package:pokerfection/src/ui/games/gomoku/gomoku_screen.dart';
import 'package:pokerfection/src/ui/games/gomoku/gomoku_table.dart';
import 'package:pokerfection/src/ui/games/gomoku/l10n/gomoku_strings.dart';
import 'package:pokerfection/src/ui/kit/coach_panel.dart';
import 'package:pokerfection/src/ui/kit/game_sounds.dart';

import '../../../games/gomoku/app/positions.dart';
import '../../../kit/shots.dart';
import 'gomoku_harness.dart';

const _middle = ['h8', 'i9', 'g9', 'g7', 'i7', 'h6', 'j8', 'h9'];

/// A sideways phone, a wide phone, a PC, a phone upright (a browser).
const _sizes = [Size(568, 320), Size(900, 420), Size(1280, 800), Size(390, 844)];

Finder _row(String text) => find.descendant(of: find.byType(CoachList), matching: find.text(text));

void main() {
  setUpAll(loadShotFonts);
  setUp(() => GameSounds.output = (_) {});

  for (final size in _sizes) {
    for (final language in AppLanguage.values) {
      final tag = shotTag(size, language);

      testWidgets('gomoku: a coach row selected, $tag', (tester) async {
        await pumpGomoku(
          tester,
          const GomokuScreen(options: GomokuOptions(level: KitLevel.easy), opening: _middle, toggles: {'coach': true}),
          size: size,
          language: language,
        );
        final strings = GomokuStrings.forLanguage(language);
        final pick = tester.widget<GomokuTable>(find.byType(GomokuTable)).pick!;
        await tester.tap(_row(strings.moveName(pick.notation)));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byKey(const ValueKey('selected row')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await shot(tester, 'gomoku_row_selected_$tag');
        await closeGomoku(tester);
      });

      testWidgets('gomoku: Pass selected under Renju, $tag', (tester) async {
        await pumpGomoku(
          tester,
          GomokuScreen(
            options: const GomokuOptions(rules: GomokuRules.renju, level: KitLevel.easy),
            opening: stuckRenju.split(' '),
            toggles: const {'coach': true},
          ),
          size: size,
          language: language,
        );
        final strings = GomokuStrings.forLanguage(language);
        await tester.tap(_row(strings.moveName('pass')));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byKey(const ValueKey('chosen ring')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await shot(tester, 'gomoku_pass_selected_$tag');
        await closeGomoku(tester);
      });
    }
  }
}
