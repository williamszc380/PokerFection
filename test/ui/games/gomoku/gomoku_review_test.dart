// The menu's Last game for Gomoku: the most recent game replayed move by
// move, the board before each move with that move see-through, the grades
// from the game, and the coach on demand for the Player's moves, at the
// three sizes in the three languages.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/gomoku/app/gomoku_record.dart';
import 'package:pokerfection/src/games/gomoku/gomoku.dart';
import 'package:pokerfection/src/kit/game_record.dart';
import 'package:pokerfection/src/ui/games/gomoku/gomoku_review.dart';
import 'package:pokerfection/src/ui/games/gomoku/gomoku_screen.dart';
import 'package:pokerfection/src/ui/games/gomoku/gomoku_table.dart';
import 'package:pokerfection/src/ui/games/gomoku/l10n/gomoku_strings.dart';
import 'package:pokerfection/src/ui/kit/coach_panel.dart';
import 'package:pokerfection/src/ui/kit/game_sounds.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';
import 'package:pokerfection/src/ui/kit/move_feedback.dart';
import 'package:pokerfection/src/ui/kit/review_kit.dart';

import '../../../kit/shots.dart';
import 'gomoku_harness.dart';

/// A middle game, Black (the player) to move.
const _middle = ['h8', 'i9', 'g9', 'g7', 'i7', 'h6', 'j8', 'h9'];

/// Black to move with an open four h8-k8: g8 or l8 makes five.
const _winning = ['h8', 'a1', 'i8', 'a2', 'j8', 'a3', 'k8', 'a4'];

/// Plays [move] with a click on the game screen from [opening], lets the
/// bot answer, leaves, and gives back the game as saved.
Future<GameRecord> playGame(WidgetTester tester, List<String> opening, String move) async {
  final games = LastGames();
  await pumpGomoku(
    tester,
    GomokuScreen(options: const GomokuOptions(level: KitLevel.easy), opening: opening),
    lastGames: games,
  );
  final at = pointOnScreen(tester, boardPoint(GomokuMove.parse(move), 15));
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: at);
  await mouse.down(at);
  await mouse.up();
  await mouse.removePointer();
  await settleGomoku(tester, rounds: 6);
  await closeGomoku(tester);
  return (await loadLastGomoku(games))!;
}

/// A game left unfinished: the player's c3 (not the best move, graded),
/// then the bot's reply.
Future<GameRecord> leftGame(WidgetTester tester) => playGame(tester, _middle, 'c3');

/// A game won by the player with l8.
Future<GameRecord> wonGame(WidgetTester tester) => playGame(tester, _winning, 'l8');

Future<void> pumpReview(
  WidgetTester tester,
  GameRecord record, {
  Size size = const Size(1280, 800),
  AppLanguage language = AppLanguage.english,
}) async {
  await pumpGomoku(tester, GomokuReview(record: record), size: size, language: language);
}

Future<void> goTo(WidgetTester tester, int step) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.home);
  await tester.pump();
  for (var i = 0; i < step; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
  }
  await settleGomoku(tester, rounds: 2);
}

/// The End key: the last step. (The slider's thumb starts moving on the
/// frame after the step changes, so a frame is drawn before the wait.)
Future<void> toEnd(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.end);
  await tester.pump();
  await settleGomoku(tester, rounds: 1);
}

Future<void> toggleCoach(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('coach chip')));
  await settleGomoku(tester);
}

String headline(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('review headline'))).data!;

Finder get _board => find.byKey(const ValueKey('gomoku board'));

void main() {
  setUpAll(loadShotFonts);
  setUp(() => GameSounds.output = (_) {});

  final g = GomokuStrings.forLanguage(AppLanguage.english);
  final k = KitStrings.forLanguage(AppLanguage.english);

  testWidgets('it opens at the first move: the empty board, "Move 1 · Player", and h8 as a see-through stone', (
    tester,
  ) async {
    final record = await leftGame(tester);
    await pumpReview(tester, record);
    expect(tester.takeException(), isNull);
    expect(headline(tester), '${k.moveNumber(1)} · ${g.you}');
    expect(tester.widget<Text>(find.byKey(const ValueKey('review move'))).data, 'h8');
    final painter = boardPainter(tester);
    expect(painter.stones, isEmpty);
    expect(painter.sequence, hasLength(1));
    expect(painter.sequence.single.point, boardPoint(GomokuMove.parse('h8'), 15));
    expect(painter.sequence.single.stone, Stone.black);
    expect(painter.sequence.single.label, isNull, reason: 'a plain see-through stone, not a numbered line');
    await closeGomoku(tester);
  });

  testWidgets("each step names whose move it is: the bot by name, the user's seat \"Player\", never \"You\"", (
    tester,
  ) async {
    final record = await leftGame(tester);
    await pumpReview(tester, record);
    await goTo(tester, 1);
    expect(headline(tester), '${k.moveNumber(2)} · ${record.seats[1].name}');
    expect(boardPainter(tester).stones, hasLength(1));
    expect(boardPainter(tester).sequence.single.stone, Stone.white);
    for (final language in AppLanguage.values) {
      await closeGomoku(tester);
      await pumpReview(tester, record, language: language);
      expect(headline(tester), endsWith(GomokuStrings.forLanguage(language).you));
      for (final you in const ['You', 'Tú', '你']) {
        expect(find.textContaining(you), findsNothing);
      }
    }
    await closeGomoku(tester);
  });

  testWidgets('the graded move shows its grade from the game; hovering "Best move: x" rings x', (tester) async {
    final record = await leftGame(tester);
    final graded = _middle.length;
    expect(record.moves[graded], 'c3');
    final mark = record.marks[graded]!;
    expect(mark.best, isNot('c3'));
    await pumpReview(tester, record);
    await goTo(tester, graded);
    expect(find.byKey(const ValueKey('review mark')), findsOneWidget);
    final pick = find.descendant(of: find.byType(MoveFeedback), matching: find.text('${g.pickLabel}: ${mark.best}'));
    expect(pick, findsOneWidget);
    expect(boardPainter(tester).spot, isNull);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(pick));
    await tester.pump();
    expect(boardPainter(tester).spot, boardPoint(GomokuMove.parse(mark.best), 15));
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(boardPainter(tester).spot, isNull);
    await mouse.removePointer();
    await closeGomoku(tester);
  });

  testWidgets("the coach on demand: the Player's moves get its moves, and a row's line shows on hover; the bot's "
      'moves get none', (tester) async {
    final record = await leftGame(tester);
    final graded = _middle.length;
    await pumpReview(tester, record);
    await goTo(tester, graded);
    expect(find.byType(CoachList), findsNothing, reason: 'the coach waits for its chip');
    await toggleCoach(tester);
    expect(find.byType(CoachList), findsOneWidget);
    expect(find.descendant(of: find.byType(CoachList), matching: find.text(g.pickLabel)), findsOneWidget);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.descendant(of: find.byType(CoachList), matching: find.text(g.pickLabel))));
    await tester.pump();
    final line = boardPainter(tester).sequence;
    expect(line, isNotEmpty);
    expect(line.first.label, '1', reason: "the row's line, numbered as in the game");
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(boardPainter(tester).sequence.single.label, isNull, reason: 'back to the move played');
    await mouse.removePointer();
    // The bot's reply: no coach.
    await goTo(tester, graded + 1);
    expect(find.byType(CoachList), findsNothing);
    await closeGomoku(tester);
  });

  testWidgets('the last step: the final board; "You win" with the winning row, or where a game was left', (
    tester,
  ) async {
    final won = await wonGame(tester);
    expect(won.result, isNotNull);
    await pumpReview(tester, won);
    await toEnd(tester);
    expect(headline(tester), k.youWin);
    expect(boardPainter(tester).winLine, hasLength(5));
    expect(boardPainter(tester).sequence, isEmpty, reason: 'no move after the last');

    await closeGomoku(tester);
    final left = await leftGame(tester);
    expect(left.result, isNull);
    await pumpReview(tester, left);
    await toEnd(tester);
    expect(headline(tester), '${k.moveNumber(left.moves.length + 1)} · ${g.you}');
    await closeGomoku(tester);
  });

  testWidgets('another game given to an open review starts it from its first move', (tester) async {
    final left = await leftGame(tester);
    final won = await wonGame(tester);
    await pumpReview(tester, left);
    await toEnd(tester);
    await pumpReview(tester, won);
    expect(tester.widget<ReviewScaffold>(find.byType(ReviewScaffold)).record, same(won));
    expect(headline(tester), '${k.moveNumber(1)} · ${g.you}');
    expect(boardPainter(tester).stones, isEmpty);
    await closeGomoku(tester);
  });

  testWidgets('with no record given it opens the saved game', (tester) async {
    final record = await leftGame(tester);
    final store = LastGames()..save(record);
    await pumpGomoku(tester, const GomokuReview(), lastGames: store);
    expect(headline(tester), '${k.moveNumber(1)} · ${g.you}');
    await closeGomoku(tester);
  });

  group('fits every size and language, the board whole, nothing overflowing', () {
    for (final size in shotSizes) {
      for (final language in AppLanguage.values) {
        final tag = shotTag(size, language);
        testWidgets('the graded step with the coach on, and the end, $tag', (tester) async {
          final record = await leftGame(tester);
          await pumpReview(tester, record, size: size, language: language);
          await goTo(tester, _middle.length);
          await toggleCoach(tester);
          expect(tester.takeException(), isNull);
          expect(onScreen(tester, _board), isTrue);
          expect(find.byType(CoachList), findsOneWidget);
          expect(onScreen(tester, find.byKey(const ValueKey('step next'))), isTrue);
          await shot(tester, 'gomoku_review_$tag');
          await closeGomoku(tester);
          final won = await wonGame(tester);
          await pumpReview(tester, won, size: size, language: language);
          await toEnd(tester);
          expect(tester.takeException(), isNull);
          expect(tester.widget<IconButton>(find.byKey(const ValueKey('step next'))).onPressed, isNull, reason: 'at the end');
          expect(boardPainter(tester).winLine, hasLength(5));
          await shot(tester, 'gomoku_review_end_$tag');
          await closeGomoku(tester);
        });
      }
    }
  });
}
