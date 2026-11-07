import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/gomoku/board.dart';
import 'package:pokerfection/src/games/gomoku/patterns.dart';
import 'package:pokerfection/src/games/gomoku/rules.dart';

import 'helpers.dart';

/// The shape Black makes by playing `*` on [line], where X is Black, O is
/// White, `.` empty and `|` the edge of the board (everything beyond it is
/// off the board too). Points not shown are empty.
String shape(String line, {bool exact = false, bool renju = false}) {
  final star = line.indexOf('*');
  final cells = List.filled(11, 0);
  var wall = false;
  for (var o = -1; o >= -5; o--) {
    final i = star + o;
    if (i >= 0 && line[i] == '|') wall = true;
    cells[5 + o] = wall ? 3 : (i >= 0 ? _code(line[i]) : 0);
  }
  wall = false;
  for (var o = 1; o <= 5; o++) {
    final i = star + o;
    if (i < line.length && line[i] == '|') wall = true;
    cells[5 + o] = wall ? 3 : (i < line.length ? _code(line[i]) : 0);
  }
  var key = 0;
  for (var o = -5; o <= 5; o++) {
    if (o != 0) key |= cells[5 + o] << PatternTable.shiftOf(o);
  }
  final table = PatternTable.of(1, exactFive: exact || renju, straightThreesOnly: renju);
  return Line.names[table[key]];
}

int _code(String c) => switch (c) { 'X' => 1, 'O' => 2, '|' => 3, _ => 0 };

void main() {
  group('line shapes', () {
    test('five, and six where five or more wins', () {
      expect(shape('XXXX*'), 'five');
      expect(shape('XX*XX'), 'five');
      expect(shape('XXXXX*'), 'five');
      expect(shape('XXXXX*', exact: true), 'overline');
      expect(shape('XX*XXX', exact: true), 'overline');
      expect(shape('OXXXX*O', exact: true), 'five');
    });

    test('an open four can become five at both ends', () {
      expect(shape('.XXX*.'), 'flex4');
      expect(shape('..X*XX..'), 'flex4');
    });

    test('a four can become five in one way only', () {
      expect(shape('OXXX*.'), 'block4');
      expect(shape('|XXX*.'), 'block4');
      expect(shape('XX*.X'), 'block4');
      expect(shape('X.X*X'), 'block4');
      // Where only five wins, a four whose other end makes six is closed.
      expect(shape('X.XXX*.', exact: true), 'block4');
      expect(shape('X.XXX*.'), 'flex4');
    });

    test('two fours on one line, such as X.XXX.X, are not a straight four', () {
      expect(shape('X.X*X.X'), 'doubleFour');
      expect(shape('XX.*X.XX'), 'doubleFour');
    });

    test('an open three can become an open four, broken threes included', () {
      expect(shape('..XX*..'), 'flex3');
      expect(shape('.X.X*.'), 'flex3');
      expect(shape('.X*.X.'), 'flex3');
      expect(shape('O.XX*..'), 'flex3');
      expect(shape('.XX*.O'), 'flex3'); // .XXXX.O is still an open four
      expect(shape('X.X*.'), 'flex3'); // .X.XX. is a broken open three
    });

    test('a closed three can only become a four', () {
      expect(shape('OXX*..'), 'block3');
      expect(shape('|XX*..'), 'block3');
      expect(shape('O.XX*.O'), 'block3');
      expect(shape('OX.X*.'), 'block3');
      expect(shape('OX.X*..O'), 'block3');
    });

    test('twos and ones', () {
      expect(shape('...X*...'), 'flex2');
      expect(shape('..X.*...'), 'flex2');
      expect(shape('OX*....'), 'block2');
      expect(shape('O*.....'), 'one');
    });

    test('no room for five is dead', () {
      expect(shape('OXX*XO'), 'dead');
      expect(shape('O...*O'), 'dead');
      expect(shape('|...*O'), 'dead');
    });

    test('Renju Black: a three counts only if it can become a straight four', () {
      // OX.X*..X: the only open-ended four it can make is X.XXX.X, two
      // fours on one line, which is a foul for Black in Renju.
      expect(shape('OX.X*..X'), 'flex3');
      expect(shape('OX.X*..X', renju: true), 'block3');
      expect(shape('..XX*..', renju: true), 'flex3');
    });
  });

  group('the incremental board', () {
    test('always matches a board built from scratch, and undo restores it', () {
      final rng = Random(7);
      for (final rules in [GomokuRules.freestyle, GomokuRules.standard, GomokuRules.renju, GomokuRules.freestyle19]) {
        for (var game = 0; game < 6; game++) {
          final board = Board(rules);
          final empty = _snapshot(Board(rules));
          final played = <int>[];
          for (var i = 0; i < 70; i++) {
            // Near the middle, so lines form and collide.
            final c = rules.size ~/ 2;
            final x = c + rng.nextInt(9) - 4, y = c + rng.nextInt(9) - 4;
            final cell = y * rules.size + x;
            if (board.stones[cell] != 0) continue;
            board.play(cell);
            played.add(cell);
            final fresh = Board.fromStones(
              rules,
              [for (var j = 0; j < played.length; j += 2) played[j]],
              [for (var j = 1; j < played.length; j += 2) played[j]],
            );
            expect(_snapshot(board), _snapshot(fresh), reason: '${rules.label} after ${played.map(name).join(' ')}');
          }
          for (var i = 0; i < played.length; i++) {
            board.undo();
          }
          expect(_snapshot(board), empty);
        }
      }
    });

    test('the same stones give the same hash, whatever the move order', () {
      final a = Board.fromMoves(GomokuRules.freestyle, points('h8 h9 i9 j10'));
      final b = Board.fromMoves(GomokuRules.freestyle, points('i9 j10 h8 h9'));
      final c = Board.fromMoves(GomokuRules.freestyle, points('h9 h8 i9 j10'));
      expect((a.hashLo, a.hashHi), (b.hashLo, b.hashHi));
      expect((a.hashLo, a.hashHi), isNot((c.hashLo, c.hashHi)));
      expect(a.hashLo, inInclusiveRange(0, 0xFFFFFFFF));
      expect(a.hashHi, inInclusiveRange(0, 0xFFFFFFFF));
    });

    test('knows the threats on the board', () {
      // Black's open three g8-h8-i8: f8 and j8 make open fours.
      final board = stones('g8 h8 i8', 'a1 a3 o15');
      expect(board.combo(1, at('f8')), Combo.winIn2);
      expect(board.combo(1, at('j8')), Combo.winIn2);
      expect(board.combo(1, at('e8')), Combo.four);
      expect(board.hasWinIn2(1), isTrue);
      expect(board.hasWinIn2(2), isFalse);
      expect(board.defenses(1).map(name).toSet(), {'f8', 'j8'});
      board.play(at('j8'));
      expect(board.count(1, Combo.five), 2);
      final fives = <int>[];
      board.fivePoints(1, fives);
      expect(fives.map(name).toSet(), {'f8', 'k8'});
    });
  });
}

// Everything the board keeps about each point, for comparison.
List<Object> _snapshot(Board b) => [
      b.hashLo,
      b.hashHi,
      b.side,
      for (var c = 0; c < b.area; c++) ...[
        b.stones[c],
        if (b.stones[c] == 0) ...[
          for (var d = 0; d < 4; d++) ...[b.pattern(1, c, d), b.pattern(2, c, d)],
          b.combo(1, c),
          b.combo(2, c),
          b.value(1, c),
          b.value(2, c),
          b.nearby.contains(c),
          b.threats[0].contains(c),
          b.threats[1].contains(c),
        ],
      ],
      for (var k = 0; k < Combo.count; k++) ...[b.count(1, k), b.count(2, k)],
      b.evaluate(),
    ];
