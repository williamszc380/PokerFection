// Screenshots of Gomoku's screens at every size and in every language, to
// look at. PNGs are written only with --dart-define=SHOTS=<folder>:
//
//   flutter test test/ui/games/gomoku/gomoku_shots_test.dart --dart-define=SHOTS=<folder>
//
// Without it the test still pumps every screen and checks nothing overflows.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/gomoku/app/gomoku_record.dart';
import 'package:pokerfection/src/games/gomoku/gomoku.dart';
import 'package:pokerfection/src/kit/seats.dart';
import 'package:pokerfection/src/ui/games/gomoku/gomoku_guides.dart';
import 'package:pokerfection/src/ui/games/gomoku/gomoku_screen.dart';
import 'package:pokerfection/src/ui/games/gomoku/gomoku_setup.dart';
import 'package:pokerfection/src/ui/games/gomoku/gomoku_table.dart';
import 'package:pokerfection/src/ui/games/gomoku/l10n/gomoku_strings.dart';
import 'package:pokerfection/src/ui/kit/coach_panel.dart';
import 'package:pokerfection/src/ui/kit/game_sounds.dart';
import 'package:pokerfection/src/ui/kit/move_feedback.dart';

import '../../../kit/shots.dart';
import 'gomoku_harness.dart';

/// A middle game, Black (the player) to move.
const _middle = ['h8', 'i9', 'g9', 'g7', 'i7', 'h6', 'j8', 'h9'];

/// Black to move with an open four h8-k8: g8 or l8 wins.
const _winning = ['h8', 'a1', 'i8', 'a2', 'j8', 'a3', 'k8', 'a4'];

void main() {
  setUpAll(loadShotFonts);
  setUp(() => GameSounds.output = (_) {});

  for (final size in shotSizes) {
    for (final language in AppLanguage.values) {
      final tag = shotTag(size, language);

      testWidgets('the game with the coach on, $tag', (tester) async {
        await pumpGomoku(
          tester,
          const GomokuScreen(
            options: GomokuOptions(level: KitLevel.easy),
            opening: _middle,
            // A new game hides the coach until its chip is tapped.
            toggles: {'coach': true},
          ),
          size: size,
          language: language,
        );
        // One move by the player (graded), the bot's reply, the coach's next answer.
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(pointOnScreen(tester, boardPoint(GomokuMove.parse('c3'), 15)));
        await tester.pump();
        await mouse.down(pointOnScreen(tester, boardPoint(GomokuMove.parse('c3'), 15)));
        await mouse.up();
        await settleGomoku(tester, rounds: 6);
        expect(tester.takeException(), isNull);
        await shot(tester, 'gomoku_game_$tag');
        // Hovering the coach's pick previews its line.
        final pick = find.descendant(
          of: find.byType(CoachList),
          matching: find.text(GomokuStrings.forLanguage(language).pickLabel),
        );
        expect(pick, findsOneWidget);
        await mouse.moveTo(tester.getCenter(pick));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await shot(tester, 'gomoku_preview_$tag');
        // Hovering the grade card's best move rings it on the board.
        final cardPick = find.descendant(
          of: find.byType(MoveFeedback),
          matching: find.textContaining('${GomokuStrings.forLanguage(language).pickLabel}: '),
        );
        expect(cardPick, findsOneWidget);
        await mouse.moveTo(tester.getCenter(cardPick));
        await tester.pump();
        expect(boardPainter(tester).spot, isNotNull);
        await shot(tester, 'gomoku_cardpick_$tag');
        await mouse.removePointer();
        await closeGomoku(tester);
      });

      testWidgets('a touch aim and Renju\'s forbidden points, $tag', (tester) async {
        await pumpGomoku(
          tester,
          const GomokuScreen(
            options: GomokuOptions(rules: GomokuRules.renju, level: KitLevel.easy),
            opening: ['h8', 'a1', 'j8', 'a2', 'i9', 'a3', 'i10', 'a4'],
            toggles: {'coach': false},
          ),
          size: size,
          language: language,
        );
        await tester.tapAt(pointOnScreen(tester, boardPoint(GomokuMove.parse('g7'), 15)));
        await tester.pump();
        // Let Place's colour settle from greyed out to ready.
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        await shot(tester, 'gomoku_aim_$tag');
        await closeGomoku(tester);
      });

      testWidgets('game over, $tag', (tester) async {
        await pumpGomoku(
          tester,
          const GomokuScreen(
            options: GomokuOptions(level: KitLevel.easy),
            opening: _winning,
          ),
          size: size,
          language: language,
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: pointOnScreen(tester, boardPoint(GomokuMove.parse('l8'), 15)));
        await mouse.down(pointOnScreen(tester, boardPoint(GomokuMove.parse('l8'), 15)));
        await mouse.up();
        await mouse.removePointer();
        await settleGomoku(tester);
        expect(tester.takeException(), isNull);
        await shot(tester, 'gomoku_over_$tag');
        await closeGomoku(tester);
      });

      testWidgets('setup, $tag', (tester) async {
        await pumpGomoku(tester, const GomokuSetup(), size: size, language: language);
        expect(tester.takeException(), isNull);
        await shot(tester, 'gomoku_setup_$tag');
        await closeGomoku(tester);
      });

      testWidgets('guides, $tag', (tester) async {
        await pumpGomoku(tester, const GomokuThreatsGuide(), size: size, language: language);
        expect(tester.takeException(), isNull);
        await shot(tester, 'gomoku_threats_$tag');
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
        await tester.pump();
        await shot(tester, 'gomoku_threats2_$tag');
        await pumpGomoku(tester, const GomokuRulesGuide(), size: size, language: language);
        expect(tester.takeException(), isNull);
        await shot(tester, 'gomoku_rules_$tag');
        await closeGomoku(tester);
      });
    }
  }
}
