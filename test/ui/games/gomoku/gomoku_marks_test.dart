// The coach's moves on the Gomoku board: at most 4, a gradient of the pick
// colour from the best (strongest) to the 4th (faintest), readable on
// every board and stone look; proofs keep their meaning. Screenshots on
// each look are written only with --dart-define=SHOTS=<folder>:
//
//   flutter test test/ui/games/gomoku/gomoku_marks_test.dart --dart-define=SHOTS=<folder>
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/main.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/gomoku/app/gomoku_record.dart';
import 'package:pokerfection/src/games/gomoku/gomoku.dart';
import 'package:pokerfection/src/kit/seats.dart';
import 'package:pokerfection/src/ui/games/gomoku/gomoku_screen.dart';
import 'package:pokerfection/src/ui/games/gomoku/gomoku_table.dart';
import 'package:pokerfection/src/ui/kit/game_sounds.dart';
import 'package:pokerfection/src/ui/widgets/gomoku_board.dart';

import '../../../kit/shots.dart';
import 'gomoku_harness.dart';

/// A middle game, Black (the player) to move.
const _middle = ['h8', 'i9', 'g9', 'g7', 'i7', 'h6', 'j8', 'h9'];

/// An early game, Black to move: nothing proven yet.
const _early = ['h8', 'i9', 'g9', 'h10'];

/// Black to move with an open four h8-k8: g8 or l8 wins.
const _winning = ['h8', 'a1', 'i8', 'a2', 'j8', 'a3', 'k8', 'a4'];

const _shotSizes = [Size(568, 320), Size(900, 420), Size(1280, 800)];

const _gold = Color(0xFFFFC107);

double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (max(x, y) + 0.05) / (min(x, y) + 0.05);
}

/// How far [c] is from [to], in RGB.
double _distance(Color c, Color to) => sqrt(pow(c.r - to.r, 2) + pow(c.g - to.g, 2) + pow(c.b - to.b, 2));

void main() {
  final primary = PokerFectionApp.theme.colorScheme.primary;

  group('the marks', () {
    test('a gradient from the best to the 4th: each one paler, more see-through and smaller', () {
      final marks = [for (var r = 0; r < coachMarkLimit; r++) BoardMark.coach(r, color: primary)];
      expect(coachMarkLimit, 4);
      expect([for (final m in marks) m.label], ['1', '2', '3', '4']);
      expect(marks.first.fill, primary, reason: 'the best in the pick colour, opaque');
      for (var i = 1; i < marks.length; i++) {
        expect(marks[i].fill.a, lessThan(marks[i - 1].fill.a));
        expect(marks[i].radius, lessThan(marks[i - 1].radius));
        expect(
          _distance(marks[i].fill.withValues(alpha: 1), primary),
          greaterThan(_distance(marks[i - 1].fill.withValues(alpha: 1), primary)),
        );
        expect(marks[i].rim!.a, lessThan(marks[i - 1].rim!.a));
      }
      expect(marks.last.fill.a, greaterThan(0.4), reason: 'faint, never gone');
      // The scale is fixed: the 2nd move looks the same however many are marked.
      expect(BoardMark.coachFade(0), 0);
      expect(BoardMark.coachFade(3), 1);
      expect(BoardMark.coachFade(9), 1);
      expect(marks.every((m) => m.labelSize < const BoardMark('1').labelSize), isTrue, reason: 'small numbers');
    });

    test('proofs keep their meaning: a proven win with a gold rim at its rank, a proven loss grey', () {
      final win = BoardMark.coach(2, color: primary, proven: true);
      expect(win.label, '3', reason: 'the rank stays');
      expect(win.fill, BoardMark.coach(2, color: primary).fill, reason: 'the gradient stays when every move wins');
      expect(win.radius, BoardMark.coach(2, color: primary).radius);
      expect(win.rim, _gold);
      final loss = BoardMark.coach(1, color: primary, proven: false);
      expect(loss.label, '2');
      expect(loss.fill.r, closeTo(loss.fill.g, 0.001), reason: 'grey');
      expect(loss.fill.a, lessThanOrEqualTo(BoardMark.coach(3, color: primary).fill.a));
    });

    test('readable on every board look: dark numbers on a light disc, a rim around it', () {
      for (final board in BoardStyle.values) {
        for (final wood in [board.light, board.dark]) {
          for (var r = 0; r < coachMarkLimit; r++) {
            for (final proven in [null, true, false]) {
              final m = BoardMark.coach(r, color: primary, proven: proven);
              final disc = Color.alphaBlend(m.fill, wood);
              expect(_contrast(m.ink, disc), greaterThan(4.5), reason: '${board.name} rank $r $proven');
              expect(m.rim!.a, greaterThanOrEqualTo(0.3));
            }
          }
        }
      }
    });

    test('the painter draws them with every board and stone look', () {
      for (final board in BoardStyle.values) {
        for (final stones in StoneStyle.values) {
          final painter = GomokuBoardPainter(
            lines: 15,
            stones: const {(7, 7): Stone.black},
            board: board,
            stoneStyle: stones,
            marks: {
              for (var r = 0; r < 4; r++) (r, r): BoardMark.coach(r, color: primary),
              (9, 9): BoardMark.coach(0, color: primary, proven: true),
              (7, 7): BoardMark.coach(1, color: primary),
            },
          );
          for (final size in const [Size(20, 20), Size(300, 300)]) {
            final recorder = ui.PictureRecorder();
            painter.paint(Canvas(recorder), size);
            recorder.endRecording().dispose();
          }
        }
      }
    });
  });

  group('the table', () {
    Future<GomokuBoardPainter> table(
      WidgetTester tester, {
      required List<GomokuMove> coach,
      Map<GomokuMove, bool> proofs = const {},
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: PokerFectionApp.theme,
          home: Center(
            child: SizedBox.square(
              dimension: 500,
              child: GomokuTable(
                game: GomokuGame.fromMoves(GomokuRules.freestyle, [for (final m in _middle) GomokuMove.parse(m)]),
                player: Stone.black,
                canPlay: true,
                onPlace: (_) {},
                onAim: (_) {},
                coachMoves: coach,
                pick: coach.firstOrNull,
                proofs: proofs,
              ),
            ),
          ),
        ),
      );
      return boardPainter(tester);
    }

    List<GomokuMove> moves(List<String> names) => [for (final m in names) GomokuMove.parse(m)];

    testWidgets('marks at most 4 of the coach moves, in order, strongest first', (tester) async {
      final coach = moves(['f8', 'k8', 'j10', 'g10', 'f6', 'k5']);
      final painter = await table(tester, coach: coach);
      expect(painter.marks, hasLength(4));
      for (final (i, m) in coach.take(4).indexed) {
        final mark = painter.marks[boardPoint(m, 15)]!;
        expect(mark.label, '${i + 1}');
        expect(mark.fill, BoardMark.coach(i, color: primary).fill);
      }
      expect(painter.marks.containsKey(boardPoint(coach[4], 15)), isFalse);

      // Fewer moves: fewer marks, on the same scale.
      final two = await table(tester, coach: coach.take(2).toList());
      expect(two.marks, hasLength(2));
      expect(two.marks[boardPoint(coach[1], 15)]!.fill, BoardMark.coach(1, color: primary).fill);
    });

    testWidgets('proven wins and losses as the proofs say', (tester) async {
      final coach = moves(['f8', 'k8', 'j10', 'g10']);
      final painter = await table(tester, coach: coach, proofs: {coach[1]: true, coach[3]: false});
      expect(painter.marks[boardPoint(coach[1], 15)]!.rim, _gold);
      expect(painter.marks[boardPoint(coach[1], 15)]!.label, '2');
      expect(painter.marks[boardPoint(coach[3], 15)]!.fill, BoardMark.coach(3, color: primary, proven: false).fill);
      expect(painter.marks[boardPoint(coach[2], 15)]!.fill, BoardMark.coach(2, color: primary).fill);
    });
  });

  group('screenshots on every board and stone look', () {
    setUpAll(loadShotFonts);
    setUp(() => GameSounds.output = (_) {});

    for (final size in _shotSizes) {
      final tag = '${size.width.toInt()}x${size.height.toInt()}';
      testWidgets('the coach marks, $tag', (tester) async {
        await pumpGomoku(
          tester,
          const GomokuScreen(
            options: GomokuOptions(level: KitLevel.easy),
            opening: _early,
            toggles: {'coach': true},
          ),
          size: size,
        );
        expect(boardPainter(tester).marks, hasLength(4));
        expect(boardPainter(tester).marks.values.where((m) => m.rim == _gold), isEmpty, reason: 'nothing proven');
        final settings = AppSettings.of(tester.element(find.byType(GomokuScreen)));
        for (final board in BoardStyle.values) {
          for (final stones in StoneStyle.values) {
            settings.update((s) => s
              ..board = board
              ..stones = stones);
            await tester.pump();
            expect(boardPainter(tester).board, board);
            expect(tester.takeException(), isNull);
            await shot(tester, 'marks_${board.name}_${stones.name}_$tag');
          }
        }
        await closeGomoku(tester);
      });

      testWidgets('a proven win, $tag', (tester) async {
        await pumpGomoku(
          tester,
          const GomokuScreen(
            options: GomokuOptions(level: KitLevel.easy),
            opening: _winning,
            toggles: {'coach': true},
          ),
          size: size,
        );
        final marks = boardPainter(tester).marks.values;
        expect(marks.where((m) => m.rim == _gold), isNotEmpty, reason: 'g8 or l8 wins');
        final settings = AppSettings.of(tester.element(find.byType(GomokuScreen)));
        for (final board in BoardStyle.values) {
          settings.update((s) => s.board = board);
          await tester.pump();
          await shot(tester, 'win_${board.name}_$tag');
        }
        await closeGomoku(tester);
      });
    }
  });
}
