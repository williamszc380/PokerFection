// Choosing from the coach list, the same way in every game: one click on a
// row selects its move (Gomoku: aims at its point, or lights Pass), a
// double click plays it, and a legal pass is always among the rows.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/gomoku/app/gomoku_analysis.dart';
import 'package:pokerfection/src/games/gomoku/app/gomoku_record.dart';
import 'package:pokerfection/src/games/gomoku/gomoku.dart';
import 'package:pokerfection/src/kit/seats.dart';
import 'package:pokerfection/src/ui/games/gomoku/gomoku_screen.dart';
import 'package:pokerfection/src/ui/games/gomoku/gomoku_table.dart';
import 'package:pokerfection/src/ui/kit/coach_panel.dart';
import 'package:pokerfection/src/ui/kit/game_sounds.dart';

import '../../../games/gomoku/app/positions.dart';
import '../../../kit/shots.dart';
import 'gomoku_harness.dart';

/// A middle game, Black (the player) to move.
const _middle = ['h8', 'i9', 'g9', 'g7', 'i7', 'h6', 'j8', 'h9'];

const _easy = GomokuOptions(level: KitLevel.easy);
const _coachOn = {'coach': true};

Finder get _rows => find.byType(CoachList);
Finder get _selectedRow => find.byKey(const ValueKey('selected row'));
Finder get _place => find.byKey(const ValueKey('place'));
/// The Pass button (the coach's Pass row is keyed 'pass' as well).
Finder get _pass => find.byWidgetPredicate((w) => w is ButtonStyleButton && w.key == const ValueKey('pass'));
Finder get _chosenRing => find.byKey(const ValueKey('chosen ring'));

/// The coach's pick now, as the board shows it.
GomokuMove _pick(WidgetTester tester) => tester.widget<GomokuTable>(find.byType(GomokuTable)).pick!;

/// The coach row that reads [move].
Finder _row(String move) => find.descendant(of: _rows, matching: find.text(move));

Future<void> _doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  setUpAll(loadShotFonts);
  setUp(() => GameSounds.output = (_) {});

  group('a click on a coach row', () {
    testWidgets('aims at its point and lights the row, and places nothing', (tester) async {
      await pumpGomoku(tester, const GomokuScreen(options: _easy, opening: _middle, toggles: _coachOn));
      final pick = _pick(tester);
      final stones = boardPainter(tester).stones.length;
      expect(_selectedRow, findsNothing);
      await tester.tap(_row(pick.notation));
      await tester.pump(const Duration(milliseconds: 400));
      expect(boardPainter(tester).aim, isTrue);
      expect(boardPainter(tester).ghost?.point, boardPoint(pick, 15));
      expect(boardPainter(tester).stones, hasLength(stones), reason: 'one click never plays');
      expect(find.descendant(of: _selectedRow, matching: find.text(pick.notation)), findsOneWidget);
      expect(tester.widget<ButtonStyleButton>(_place).onPressed, isNotNull);
      await closeGomoku(tester);
    });

    testWidgets('a point aimed at on the board lights its row too', (tester) async {
      await pumpGomoku(tester, const GomokuScreen(options: _easy, opening: _middle, toggles: _coachOn));
      final pick = _pick(tester);
      await tester.tapAt(pointOnScreen(tester, boardPoint(pick, 15)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.descendant(of: _selectedRow, matching: find.text(pick.notation)), findsOneWidget);
      await closeGomoku(tester);
    });

    testWidgets('then Enter places the stone aimed at', (tester) async {
      await pumpGomoku(tester, const GomokuScreen(options: _easy, opening: _middle, toggles: _coachOn));
      final pick = _pick(tester);
      await tester.tap(_row(pick.notation));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(boardPainter(tester).stones[boardPoint(pick, 15)], Stone.black);
      await closeGomoku(tester);
    });
  });

  testWidgets('a double click on a coach row places the stone on its point', (tester) async {
    await pumpGomoku(tester, const GomokuScreen(options: _easy, opening: _middle, toggles: _coachOn));
    final pick = _pick(tester);
    final stones = boardPainter(tester).stones.length;
    await _doubleTap(tester, _row(pick.notation));
    expect(boardPainter(tester).stones, hasLength(stones + 1));
    expect(boardPainter(tester).stones[boardPoint(pick, 15)], Stone.black);
    await closeGomoku(tester);
  });

  testWidgets('two clicks on different rows only move the aim', (tester) async {
    await pumpGomoku(tester, const GomokuScreen(options: _easy, opening: _middle, toggles: _coachOn));
    final stones = boardPainter(tester).stones.length;
    final table = tester.widget<GomokuTable>(find.byType(GomokuTable));
    final [first, second, ...] = table.coachMoves;
    await tester.tap(_row(first.notation));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(_row(second.notation));
    await tester.pump(const Duration(milliseconds: 400));
    expect(boardPainter(tester).stones, hasLength(stones));
    expect(boardPainter(tester).ghost?.point, boardPoint(second, 15));
    await closeGomoku(tester);
  });

  group('Renju, when every point left is forbidden to Black', () {
    final stuck = stuckRenju.split(' ');
    const renju = GomokuOptions(rules: GomokuRules.renju, level: KitLevel.easy);

    testWidgets('Pass is among the coach rows, with its value', (tester) async {
      await pumpGomoku(tester, GomokuScreen(options: renju, opening: stuck, toggles: _coachOn));
      expect(_row('Pass'), findsOneWidget);
      await closeGomoku(tester);
    });

    testWidgets('one click lights the Pass button, Enter passes', (tester) async {
      await pumpGomoku(tester, GomokuScreen(options: renju, opening: stuck, toggles: _coachOn));
      expect(_chosenRing, findsNothing);
      await tester.tap(_row('Pass'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.descendant(of: _chosenRing, matching: _pass), findsOneWidget);
      expect(find.descendant(of: _selectedRow, matching: find.text('Pass')), findsOneWidget);
      final moves = tester.widget<GomokuTable>(find.byType(GomokuTable)).game.moves.length;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      final game = tester.widget<GomokuTable>(find.byType(GomokuTable)).game;
      expect(game.moves, hasLength(moves + 1));
      expect(game.moves.last, GomokuMove.pass);
      expect(_chosenRing, findsNothing, reason: 'a move made drops the choice');
      await closeGomoku(tester);
    });

    testWidgets('a double click passes', (tester) async {
      await pumpGomoku(tester, GomokuScreen(options: renju, opening: stuck, toggles: _coachOn));
      await _doubleTap(tester, _row('Pass'));
      expect(tester.widget<GomokuTable>(find.byType(GomokuTable)).game.moves.last, GomokuMove.pass);
      await closeGomoku(tester);
    });

    testWidgets('in Spanish and Chinese the row reads as the button', (tester) async {
      for (final language in [AppLanguage.spanish, AppLanguage.chinese]) {
        await pumpGomoku(tester, GomokuScreen(options: renju, opening: stuck, toggles: _coachOn), language: language);
        final button = tester.widget<Text>(find.descendant(of: _pass, matching: find.byType(Text)));
        expect(find.descendant(of: _rows, matching: find.text(button.data!)), findsOneWidget, reason: '$language');
        await closeGomoku(tester);
      }
    });
  });

  group('the moves always listed', () {
    test('a pass, only when it is legal', () {
      final stuck = GomokuGame.fromMoves(GomokuRules.renju, GomokuGame.parseMoves(stuckRenju));
      expect(gomokuListedMoves(stuck), ['pass']);
      expect(gomokuListedMoves(GomokuRecord.replay(GomokuRecord.start(_easy, seed: 1, botName: 'Ana'))), isEmpty);
    });
  });
}
