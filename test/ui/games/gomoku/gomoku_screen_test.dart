import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/gomoku/app/gomoku_record.dart';
import 'package:pokerfection/src/games/gomoku/gomoku.dart';
import 'package:pokerfection/src/kit/game_keys.dart';
import 'package:pokerfection/src/ui/games/gomoku/gomoku_screen.dart';
import 'package:pokerfection/src/ui/games/gomoku/gomoku_table.dart';
import 'package:pokerfection/src/ui/games/gomoku/l10n/gomoku_strings.dart';
import 'package:pokerfection/src/ui/kit/coach_panel.dart';
import 'package:pokerfection/src/ui/kit/game_sounds.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';
import 'package:pokerfection/src/ui/kit/move_feedback.dart';

import '../../../kit/shots.dart';
import 'gomoku_harness.dart';

/// A middle game, Black (the player) to move.
const _middle = ['h8', 'i9', 'g9', 'g7', 'i7', 'h6', 'j8', 'h9'];

/// Black to move with an open four h8-k8: g8 or l8 makes five.
const _winning = ['h8', 'a1', 'i8', 'a2', 'j8', 'a3', 'k8', 'a4'];

/// Renju, Black to move: i8 would be a double three (forbidden).
const _renju = ['h8', 'a1', 'j8', 'a2', 'i9', 'a3', 'i10', 'a4'];

const _easy = GomokuOptions(level: KitLevel.easy);

/// The coach starts hidden in a new game; the tests of its moves turn it on
/// as the coach chip would.
const _coachOn = {'coach': true};

Finder get _board => find.byKey(const ValueKey('gomoku board'));
Finder get _place => find.byKey(const ValueKey('place'));
Finder get _pass => find.byKey(const ValueKey('pass'));

bool _enabled(WidgetTester tester, Finder button) => tester.widget<ButtonStyleButton>(button).onPressed != null;

Offset _at(WidgetTester tester, String notation) => pointOnScreen(tester, boardPoint(GomokuMove.parse(notation), 15));

MouseCursor? _cursor() => RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);

void main() {
  setUpAll(loadShotFonts);
  setUp(() => GameSounds.output = (_) {});

  group('fits every size and language, with no page scroll', () {
    for (final size in gomokuSizes) {
      for (final language in AppLanguage.values) {
        final tag = shotTag(size, language);

        Future<void> checkLayout(WidgetTester tester) async {
          expect(tester.takeException(), isNull, reason: 'no overflow');
          expect(onScreen(tester, _board), isTrue, reason: 'the whole board shows');
          for (final finder in [_board, _place]) {
            expect(
              find.ancestor(of: finder, matching: find.byType(Scrollable)),
              findsNothing,
              reason: 'the board and the buttons never scroll away',
            );
          }
          expect(onScreen(tester, _place), isTrue);
        }

        testWidgets('the game with the coach on, and its line on hover, $tag', (tester) async {
          await pumpGomoku(
            tester,
            const GomokuScreen(options: _easy, opening: _middle, toggles: _coachOn),
            size: size,
            language: language,
          );
          expect(find.byType(CoachList), findsOneWidget);
          await checkLayout(tester);
          final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
          await mouse.addPointer(location: Offset.zero);
          final pick = find.descendant(
            of: find.byType(CoachList),
            matching: find.text(GomokuStrings.forLanguage(language).pickLabel),
          );
          await mouse.moveTo(tester.getCenter(pick));
          await tester.pump();
          expect(boardPainter(tester).sequence, isNotEmpty);
          await checkLayout(tester);
          await mouse.removePointer();
          await closeGomoku(tester);
        });

        testWidgets('the game with the coach off, Renju, $tag', (tester) async {
          await pumpGomoku(
            tester,
            const GomokuScreen(
              options: GomokuOptions(rules: GomokuRules.renju, level: KitLevel.easy),
              opening: _renju,
              toggles: {'coach': false},
            ),
            size: size,
            language: language,
          );
          expect(find.byType(CoachList), findsNothing);
          expect(onScreen(tester, _pass), isTrue);
          // The user's own seat is "Player" ("Jugador", "玩家"), never "You".
          expect(find.text(GomokuStrings.forLanguage(language).you), findsOneWidget);
          for (final you in const ['You', 'Tú', '你']) {
            expect(find.text(you), findsNothing);
          }
          await checkLayout(tester);
          await closeGomoku(tester);
        });

        testWidgets('game over, $tag', (tester) async {
          await pumpGomoku(
            tester,
            const GomokuScreen(options: _easy, opening: _winning),
            size: size,
            language: language,
          );
          await tester.tapAt(_at(tester, 'g8'));
          await tester.pump();
          await tester.tapAt(_at(tester, 'g8'));
          await settleGomoku(tester);
          expect(find.text(KitStrings.forLanguage(language).youWin), findsOneWidget);
          expect(boardPainter(tester).winLine, hasLength(5));
          expect(tester.takeException(), isNull);
          expect(onScreen(tester, _board), isTrue);
          await closeGomoku(tester);
        });
      }
    }
  });

  group('on a PC, with a mouse', () {
    testWidgets('a see-through stone and a hand cursor follow the mouse over free points only', (tester) async {
      await pumpGomoku(tester, const GomokuScreen(options: _easy, opening: _middle));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(_at(tester, 'c3'));
      await tester.pump();
      expect(boardPainter(tester).ghost?.point, boardPoint(GomokuMove.parse('c3'), 15));
      expect(boardPainter(tester).ghost?.stone, Stone.black);
      expect(boardPainter(tester).aim, isFalse, reason: 'no cross hairs for a mouse');
      expect(_cursor(), SystemMouseCursors.click);
      await mouse.moveTo(_at(tester, 'h8'));
      await tester.pump();
      expect(boardPainter(tester).ghost, isNull, reason: 'h8 is taken');
      expect(_cursor(), isNot(SystemMouseCursors.click));
      await mouse.removePointer();
      await closeGomoku(tester);
    });

    testWidgets('a click places the stone at once, on the point clicked (rows count from the bottom)', (tester) async {
      final games = LastGames();
      await pumpGomoku(
        tester,
        const GomokuScreen(options: _easy, toggles: {'coach': false}),
        lastGames: games,
      );
      expect(boardPainter(tester).coordinates, isTrue, reason: 'room for the letters and numbers');
      // The bottom-left point is a1 in Renju notation, but row 14 for the board.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: _at(tester, 'a1'));
      await mouse.down(_at(tester, 'a1'));
      await mouse.up();
      await tester.pump();
      expect(_at(tester, 'a1').dy, greaterThan(tester.getCenter(_board).dy), reason: 'a1 is low on the screen');
      expect(boardPainter(tester).stones[(0, 14)], Stone.black);
      await mouse.removePointer();
      await closeGomoku(tester);
      final saved = await games.load(GameKeys.gomoku, version: gomokuRecordVersion);
      expect(saved!.moves.first, 'a1');
    });

    testWidgets('Renju\'s forbidden points are crossed out and show a no-entry cursor', (tester) async {
      await pumpGomoku(
        tester,
        const GomokuScreen(
          options: GomokuOptions(rules: GomokuRules.renju, level: KitLevel.easy),
          opening: _renju,
        ),
      );
      expect(boardPainter(tester).forbidden, [boardPoint(GomokuMove.parse('i8'), 15)]);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(_at(tester, 'i8'));
      await tester.pump();
      expect(_cursor(), SystemMouseCursors.forbidden);
      expect(boardPainter(tester).ghost, isNull);
      await mouse.down(_at(tester, 'i8'));
      await mouse.up();
      await tester.pump();
      expect(boardPainter(tester).stones.containsKey(boardPoint(GomokuMove.parse('i8'), 15)), isFalse);
      await mouse.removePointer();
      await closeGomoku(tester);
    });

    testWidgets('the coach marks its top 4 moves, a gradient from the pick; hovering a row previews its line', (
      tester,
    ) async {
      await pumpGomoku(tester, const GomokuScreen(options: _easy, opening: _middle, toggles: _coachOn));
      final painter = boardPainter(tester);
      expect(painter.marks.keys.length, 4, reason: 'at most 4, though the coach lists more');
      final marks = painter.marks.values.toList()..sort((a, b) => a.label.compareTo(b.label));
      expect([for (final m in marks) m.label], ['1', '2', '3', '4']);
      final primary = Theme.of(tester.element(_board)).colorScheme.primary;
      expect(marks.first.fill, primary, reason: 'the pick in the pick colour');
      for (var i = 1; i < marks.length; i++) {
        expect(marks[i].fill.a, lessThan(marks[i - 1].fill.a), reason: 'each next one fainter');
        expect(marks[i].radius, lessThan(marks[i - 1].radius));
      }

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getCenter(find.descendant(of: find.byType(CoachList), matching: find.text('Best move'))),
      );
      await tester.pump();
      expect(boardPainter(tester).sequence.first.label, '1');
      expect(boardPainter(tester).sequence.first.stone, Stone.black);
      expect(boardPainter(tester).marks, isEmpty, reason: 'the line replaces the numbers while it shows');
      expect(find.byKey(const ValueKey('gomoku line')), findsOneWidget);
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(boardPainter(tester).sequence, isEmpty);
      expect(find.byKey(const ValueKey('gomoku line')), findsNothing);
      await mouse.removePointer();
      await closeGomoku(tester);
    });

    testWidgets('a proven win shows in the status line, and the row says "Wins in N"', (tester) async {
      await pumpGomoku(tester, const GomokuScreen(options: _easy, opening: _winning, toggles: _coachOn));
      expect(find.textContaining('Wins in 1'), findsWidgets);
      await closeGomoku(tester);
    });

    testWidgets('the arrow keys aim, Enter places', (tester) async {
      await pumpGomoku(tester, const GomokuScreen(options: _easy, opening: ['h8', 'h9'], toggles: {'coach': false}));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(boardPainter(tester).ghost?.point, boardPoint(GomokuMove.parse('i9'), 15), reason: 'from the last stone');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(boardPainter(tester).ghost?.point, boardPoint(GomokuMove.parse('i10'), 15));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(boardPainter(tester).stones[boardPoint(GomokuMove.parse('i10'), 15)], Stone.black);
      await closeGomoku(tester);
    });
  });

  group('by touch', () {
    testWidgets('a tap aims, a second tap on the same point places; Place is greyed out until there is an aim', (
      tester,
    ) async {
      await pumpGomoku(
        tester,
        const GomokuScreen(options: _easy, opening: ['h8', 'h9']),
        size: const Size(568, 320),
      );
      expect(boardPainter(tester).coordinates, isFalse, reason: 'no room for them on a phone');
      expect(_enabled(tester, _place), isFalse);
      await tester.tapAt(_at(tester, 'j10'));
      await tester.pump();
      expect(boardPainter(tester).aim, isTrue);
      expect(boardPainter(tester).ghost?.point, boardPoint(GomokuMove.parse('j10'), 15));
      expect(_enabled(tester, _place), isTrue);
      expect(boardPainter(tester).stones, hasLength(2), reason: 'aimed, not placed');
      // Another point moves the aim.
      await tester.tapAt(_at(tester, 'k11'));
      await tester.pump();
      expect(boardPainter(tester).ghost?.point, boardPoint(GomokuMove.parse('k11'), 15));
      await tester.tapAt(_at(tester, 'k11'));
      await tester.pump();
      expect(boardPainter(tester).stones[boardPoint(GomokuMove.parse('k11'), 15)], Stone.black);
      expect(boardPainter(tester).ghost, isNull);
      expect(_enabled(tester, _place), isFalse);
      await closeGomoku(tester);
    });

    testWidgets('Place puts the aimed stone down', (tester) async {
      await pumpGomoku(
        tester,
        const GomokuScreen(options: _easy, opening: ['h8', 'h9']),
        size: const Size(390, 844),
      );
      await tester.tapAt(_at(tester, 'j10'));
      await tester.pump();
      await tester.tap(_place);
      await tester.pump();
      expect(boardPainter(tester).stones[boardPoint(GomokuMove.parse('j10'), 15)], Stone.black);
      await closeGomoku(tester);
    });

    testWidgets('tapping a coach row aims at its move, but never plays it', (tester) async {
      await pumpGomoku(
        tester,
        const GomokuScreen(options: _easy, opening: _middle, toggles: _coachOn),
        size: const Size(568, 320),
      );
      final stones = boardPainter(tester).stones.length;
      await tester.tap(find.descendant(of: find.byType(CoachList), matching: find.text('Best move')));
      await tester.pump();
      expect(boardPainter(tester).aim, isTrue);
      expect(boardPainter(tester).stones, hasLength(stones));
      expect(_enabled(tester, _place), isTrue);
      await closeGomoku(tester);
    });
  });

  group('greyed out, never hidden', () {
    testWidgets('Pass is there under Renju only, greyed out unless Black must pass', (tester) async {
      await pumpGomoku(
        tester,
        const GomokuScreen(
          options: GomokuOptions(rules: GomokuRules.renju, level: KitLevel.easy),
          opening: _renju,
        ),
      );
      expect(_enabled(tester, _pass), isFalse);
      await closeGomoku(tester);
      await pumpGomoku(tester, const GomokuScreen(options: _easy, opening: _middle));
      expect(_pass, findsNothing, reason: 'there is no pass in Freestyle');
      await closeGomoku(tester);
    });

    testWidgets('Free Play: the coach chip is greyed out, and no numbers or grades show', (tester) async {
      await pumpGomoku(
        tester,
        const GomokuScreen(
          options: GomokuOptions(level: KitLevel.easy, training: false),
          opening: _middle,
        ),
      );
      final chip = tester.widget<FilterChip>(find.byKey(const ValueKey('coach chip')));
      expect(chip.onSelected, isNull);
      expect(boardPainter(tester).marks, isEmpty);
      expect(find.byType(CoachList), findsNothing);
      await closeGomoku(tester);
    });

    testWidgets('while the bot thinks, nothing can be placed', (tester) async {
      await pumpGomoku(tester, const GomokuScreen(options: _easy, toggles: {'coach': false}));
      await tester.tapAt(_at(tester, 'h8'));
      await tester.pump();
      await tester.tapAt(_at(tester, 'h8'));
      await tester.pump(const Duration(milliseconds: 10));
      // The bot's pause: White's turn, no aim allowed.
      await tester.tapAt(_at(tester, 'c3'));
      await tester.pump(const Duration(milliseconds: 10));
      expect(boardPainter(tester).ghost, isNull);
      expect(_enabled(tester, _place), isFalse);
      await settleGomoku(tester);
      await closeGomoku(tester);
    });
  });

  testWidgets('a new game starts with the coach hidden, and Training still grades the move', (tester) async {
    await pumpGomoku(tester, const GomokuScreen(options: _easy, opening: _middle));
    expect(find.byType(CoachList), findsNothing, reason: 'the player turns the coach on');
    expect(boardPainter(tester).marks, isEmpty, reason: 'no numbered moves either');
    final chip = tester.widget<FilterChip>(find.byKey(const ValueKey('coach chip')));
    expect(chip.selected, isFalse);
    expect(chip.onSelected, isNotNull, reason: 'one tap away');
    await tester.tapAt(_at(tester, 'c3'));
    await tester.pump();
    await tester.tapAt(_at(tester, 'c3'));
    await settleGomoku(tester, rounds: 6);
    expect(find.byType(MoveFeedback), findsOneWidget, reason: 'the grade after the move stays');
    expect(find.byType(CoachList), findsNothing);
    await closeGomoku(tester);
  });

  testWidgets('the game is saved as it goes, and the next screen takes the coach toggle', (tester) async {
    final games = LastGames();
    await pumpGomoku(
      tester,
      const GomokuScreen(options: _easy, opening: ['h8', 'h9']),
      lastGames: games,
    );
    // The coach starts hidden; one tap on its chip shows it.
    await tester.tap(find.byKey(const ValueKey('coach chip')));
    await tester.pump();
    await closeGomoku(tester);
    final saved = await games.load(GameKeys.gomoku, version: gomokuRecordVersion, validate: GomokuRecord.validate);
    expect(saved!.moves, ['h8', 'h9']);
    expect(saved.extra['coach'], isTrue);
  });

  group('hovering "Best move: x" on the grade card rings x on the board', () {
    /// Places [move] with a click, waits for its grade and hovers the
    /// card's best move; returns that move.
    Future<String> hoverCardPick(WidgetTester tester, TestGesture mouse, String move, {bool settle = true}) async {
      await mouse.moveTo(_at(tester, move));
      await mouse.down(_at(tester, move));
      await mouse.up();
      if (settle) {
        await settleGomoku(tester, rounds: 6);
      } else {
        // The grade comes from the included-move job; the bot's pause is still on.
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
      }
      final pick = find.descendant(of: find.byType(MoveFeedback), matching: find.textContaining('Best move: '));
      expect(pick, findsOneWidget, reason: '$move is not the best move');
      await mouse.moveTo(tester.getCenter(pick));
      await tester.pump();
      return tester.widget<Text>(pick).data!.split(': ').last;
    }

    testWidgets('with the coach hidden, the card still shows in Training and its move lights', (tester) async {
      await pumpGomoku(tester, const GomokuScreen(options: _easy, opening: _middle, toggles: {'coach': false}));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      final best = await hoverCardPick(tester, mouse, 'c3');
      expect(boardPainter(tester).spot, boardPoint(GomokuMove.parse(best), 15));
      expect(boardPainter(tester).spot, isNot(boardPoint(GomokuMove.parse('c3'), 15)));
      expect(boardPainter(tester).sequence, isEmpty, reason: "no line from the position after the bot's reply");
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(boardPainter(tester).spot, isNull);
      await mouse.removePointer();
      await closeGomoku(tester);
    });

    testWidgets('while the bot thinks right after the graded move', (tester) async {
      await pumpGomoku(tester, const GomokuScreen(options: _easy, opening: _middle));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      final best = await hoverCardPick(tester, mouse, 'a15', settle: false);
      expect(boardPainter(tester).spot, boardPoint(GomokuMove.parse(best), 15));
      expect(boardPainter(tester).sequence, isEmpty, reason: "the coach's lines are not showing");
      await mouse.removePointer();
      await settleGomoku(tester);
      await closeGomoku(tester);
    });

    testWidgets("with the coach's moves for the new position showing, only the ring: no coach line", (tester) async {
      await pumpGomoku(tester, const GomokuScreen(options: _easy, opening: _middle, toggles: _coachOn));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      final best = await hoverCardPick(tester, mouse, 'c3');
      expect(find.byType(CoachList), findsOneWidget, reason: "the coach answers the bot's reply");
      expect(boardPainter(tester).spot, boardPoint(GomokuMove.parse(best), 15));
      expect(boardPainter(tester).sequence, isEmpty, reason: 'the card has its own hover, apart from the rows');
      await mouse.removePointer();
      await closeGomoku(tester);
    });

    testWidgets("a coach row's hover is not mistaken for the card's: no ring", (tester) async {
      await pumpGomoku(tester, const GomokuScreen(options: _easy, opening: _middle, toggles: _coachOn));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.descendant(of: find.byType(CoachList), matching: find.text('Best move'))));
      await tester.pump();
      expect(boardPainter(tester).sequence, isNotEmpty);
      expect(boardPainter(tester).spot, isNull, reason: 'no move graded yet');
      await mouse.removePointer();
      await closeGomoku(tester);
    });
  });

  testWidgets(
    'on a sideways phone the pick\'s tag reads in full beside a "Wins in 1" badge',
    (tester) async {
      await pumpGomoku(
        tester,
        const GomokuScreen(options: _easy, opening: _winning, toggles: _coachOn),
        size: const Size(568, 320),
      );
      final label = GomokuStrings.forLanguage(AppLanguage.english).pickLabel;
      final tag = find.descendant(of: find.byType(CoachList), matching: find.text(label));
      expect(tag, findsOneWidget);
      expect(find.descendant(of: find.byType(CoachList), matching: find.text('Wins in 1')), findsWidgets);
      expect(tester.renderObject<RenderParagraph>(tag).didExceedMaxLines, isFalse, reason: '"$label" is cut to "Best ..."');
      await closeGomoku(tester);
    },
  );
}
