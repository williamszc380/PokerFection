import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/gomoku/rules.dart' as engine;
import 'package:pokerfection/src/ui/widgets/gomoku_board.dart';

/// A few stones, the last one marked, and one off the board (left out).
const _stones = {
  (0, 0): Stone.black,
  (7, 7): Stone.white,
  (14, 14): Stone.black,
  (3, 11): Stone.white,
  (20, 2): Stone.black,
};

void main() {
  test('the painter draws at any size and shape, with every board and stone look, without errors', () {
    for (final board in BoardStyle.values) {
      for (final stones in StoneStyle.values) {
        for (final lines in [1, 5, 7, 9, 15, 19]) {
          final painter = GomokuBoardPainter(
            lines: lines,
            stones: _stones,
            lastMove: (7, 7),
            board: board,
            stoneStyle: stones,
          );
          for (final size in const [
            Size.zero,
            Size(1, 1),
            Size(24, 24),
            Size(60, 40),
            Size(300, 300),
            Size(900, 1600),
          ]) {
            final recorder = ui.PictureRecorder();
            painter.paint(Canvas(recorder), size);
            recorder.endRecording().dispose();
          }
        }
      }
    }
  });

  testWidgets('the board widget paints at several sizes', (tester) async {
    for (final side in [16.0, 48.0, 120.0, 600.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox.square(
              dimension: side,
              child: const GomokuBoard(stones: _stones, lastMove: (14, 14)),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(GomokuBoard)), Size.square(side));
      expect(tester.takeException(), isNull);
    }
  });

  test('star points: the 4 corner ones and the center on a 15-line board, more on 19, none on small boards', () {
    expect(GomokuBoardPainter.starPoints(15).toSet(), {(3, 3), (3, 11), (11, 3), (11, 11), (7, 7)});
    expect(GomokuBoardPainter.starPoints(19), hasLength(9));
    expect(GomokuBoardPainter.starPoints(9).toSet(), {(2, 2), (2, 6), (6, 2), (6, 6), (4, 4)});
    expect(GomokuBoardPainter.starPoints(7), [(3, 3)]);
    expect(GomokuBoardPainter.starPoints(5), isEmpty);
  });

  test('the point under a tap: the nearest one, nothing off the board', () {
    const size = Size(300, 300);
    expect(GomokuBoardPainter.pointAt(const Offset(10, 10), size, 15), (0, 0));
    expect(GomokuBoardPainter.pointAt(const Offset(150, 150), size, 15), (7, 7));
    expect(GomokuBoardPainter.pointAt(const Offset(299, 0), size, 15), (14, 0));
    expect(GomokuBoardPainter.pointAt(const Offset(-1, 150), size, 15), isNull);
    // A wide space: the board is the square in the middle.
    expect(GomokuBoardPainter.pointAt(const Offset(50, 150), const Size(600, 300), 15), isNull);
    expect(GomokuBoardPainter.pointAt(const Offset(160, 10), const Size(600, 300), 15), (0, 0));
  });

  test('the board draws the play marks too: win line, forbidden points, numbers, a line, an aim, a ring, coordinates', () {
    final painter = GomokuBoardPainter(
      lines: 15,
      stones: const {(7, 7): Stone.black, (8, 8): Stone.white},
      lastMove: (8, 8),
      board: BoardStyle.lightWood,
      stoneStyle: StoneStyle.glossy,
      winLine: const [(0, 0), (1, 1), (2, 2), (3, 3), (4, 4)],
      forbidden: const [(5, 5), (7, 7)],
      marks: const {
        (6, 6): BoardMark('1'),
        (9, 9): BoardMark('2', fill: Colors.green),
      },
      sequence: const [BoardStone((10, 10), Stone.black, '1'), BoardStone((11, 11), Stone.white, '12')],
      sequenceOpacity: 0.7,
      ghost: const BoardStone((3, 4), Stone.white),
      aim: true,
      spot: (8, 8),
      spotColor: Colors.amber,
      coordinates: true,
      labelStyle: const TextStyle(fontFamily: 'Roboto'),
    );
    for (final size in const [Size.zero, Size(40, 40), Size(300, 200), Size(800, 800)]) {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), size);
      recorder.endRecording().dispose();
    }
  });

  test('the ring repaints when it moves or goes, and one off the board is left out', () {
    GomokuBoardPainter ringAt((int, int)? spot) => GomokuBoardPainter(
      lines: 15,
      stones: const {},
      board: BoardStyle.lightWood,
      stoneStyle: StoneStyle.flat,
      spot: spot,
    );
    expect(ringAt((3, 3)).shouldRepaint(ringAt((3, 3))), isFalse);
    expect(ringAt((3, 3)).shouldRepaint(ringAt((4, 3))), isTrue);
    expect(ringAt((3, 3)).shouldRepaint(ringAt(null)), isTrue);
    final recorder = ui.PictureRecorder();
    ringAt((20, 20)).paint(Canvas(recorder), const Size(300, 300));
    recorder.endRecording().dispose();
  });

  test('a point and its place on the screen agree, with and without the coordinates around the edge', () {
    for (final coordinates in [false, true]) {
      for (final size in const [Size(300, 300), Size(640, 420)]) {
        final g = GomokuBoardGeometry(size, 15, coordinates: coordinates);
        for (final point in const [(0, 0), (7, 7), (14, 14), (3, 12)]) {
          expect(g.pointAt(g.at(point)), point);
          // Anywhere within its cell is still that point.
          expect(g.pointAt(g.at(point) + Offset(g.cell * 0.45, -g.cell * 0.45)), point);
        }
        expect(g.pointAt(g.at((0, 0)) - Offset(g.cell, 0)), isNull, reason: 'off the board');
        expect(g.area.contains(g.at((14, 14))), isTrue);
      }
    }
    // The labels take a band on the left and at the bottom: the board's
    // points move right and get smaller.
    final plain = GomokuBoardGeometry(const Size(300, 300), 15);
    final labelled = GomokuBoardGeometry(const Size(300, 300), 15, coordinates: true);
    expect(labelled.cell, lessThan(plain.cell));
    expect(labelled.at((0, 0)).dx, greaterThan(plain.at((0, 0)).dx));
  });

  test("the board's stones are the engine's: one Stone type for the game and its board", () {
    const Stone black = engine.Stone.black;
    expect(black, Stone.black);
    expect(Stone.white.opponent, Stone.black);
  });
}
