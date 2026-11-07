import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/gomoku/board.dart';
import 'package:pokerfection/src/games/gomoku/game.dart';
import 'package:pokerfection/src/games/gomoku/patterns.dart';
import 'package:pokerfection/src/games/gomoku/rules.dart';
import 'package:pokerfection/src/games/gomoku/threats.dart';
import 'package:pokerfection/src/ui/games/gomoku/gomoku_guides.dart';
import 'package:pokerfection/src/ui/games/gomoku/l10n/gomoku_strings.dart';

/// The Threats guide's figures, each played on the engine: every caption
/// must be true of its board.
void main() {
  List<int> cells(String text) => [for (final m in GomokuFigureSpec.moves(text)) m.index(15)];
  String names(Iterable<int> cs) => ([for (final c in cs) GomokuMove.fromIndex(c, 15).notation]..sort()).join(' ');
  GomokuFigureSpec spec(GomokuFigure figure) => gomokuFigures.singleWhere((s) => s.figure == figure);

  /// The board before the figure's last stone ([GomokuFigureSpec.key]), Black to move.
  Board before(GomokuFigureSpec s) {
    final key = s.key == null ? -1 : cells(s.key!).single;
    return Board.fromStones(
      s.rules,
      [
        for (final c in cells(s.black))
          if (c != key) c,
      ],
      cells(s.white),
      side: 1,
    );
  }

  int keyOf(GomokuFigureSpec s) => cells(s.key!).single;

  /// Black's five points after the figure's last stone.
  String fivePoints(GomokuFigureSpec s) {
    final board = before(s)..play(keyOf(s));
    final out = <int>[];
    board.fivePoints(1, out);
    return names(out);
  }

  /// The empty points where Black would make an open four, after the last stone.
  String openFourPoints(GomokuFigureSpec s) {
    final board = before(s)..play(keyOf(s));
    board.side = 1;
    return names([
      for (var c = 0; c < board.area; c++)
        if (board.stones[c] == 0 && List.generate(4, (d) => board.pattern(1, c, d)).contains(Line.flex4)) c,
    ]);
  }

  bool hasLine(Board board, int cell, int shape) => List.generate(4, (d) => board.pattern(1, cell, d)).contains(shape);

  test('every figure is in order, fits its 9×9 cut-out, and has no point twice', () {
    expect([for (final s in gomokuFigures) s.figure], GomokuFigure.values);
    for (final s in gomokuFigures) {
      final all = [s.black, s.white, s.dots, s.forbidden, s.sequence].expand(GomokuFigureSpec.moves).toList();
      expect(all.toSet(), hasLength(all.length), reason: '${s.figure}');
      for (final m in all) {
        final (x, y) = GomokuFigureSpec.point(m);
        expect(
          x >= 0 && y >= 0 && x < GomokuFigureSpec.lines && y < GomokuFigureSpec.lines,
          isTrue,
          reason: '${s.figure}: $m',
        );
      }
    }
  });

  test('Five: the last stone makes five in a row', () {
    final s = spec(GomokuFigure.five);
    expect(before(s).combo(1, keyOf(s)), Combo.five);
  });

  test('Open four: two ways to make five, at the dots', () {
    final s = spec(GomokuFigure.openFour);
    expect(hasLine(before(s), keyOf(s), Line.flex4), isTrue);
    expect(fivePoints(s), names(cells(s.dots)));
  });

  test('Four: one way to make five, at the dot', () {
    final s = spec(GomokuFigure.four);
    expect(before(s).combo(1, keyOf(s)), Combo.four);
    expect(fivePoints(s), names(cells(s.dots)));
  });

  test('Open three and broken three: the dots make an open four', () {
    for (final figure in [GomokuFigure.openThree, GomokuFigure.brokenThree]) {
      final s = spec(figure);
      expect(hasLine(before(s), keyOf(s), Line.flex3), isTrue, reason: '$figure');
      expect(openFourPoints(s), names(cells(s.dots)), reason: '$figure');
    }
  });

  test('Four-three: a four (its five point at the dot) and an open three at once', () {
    final s = spec(GomokuFigure.fourThree);
    expect(before(s).combo(1, keyOf(s)), Combo.fourThree);
    expect(fivePoints(s), names(cells(s.dots)));
  });

  test('Double three: two open threes at once', () {
    final s = spec(GomokuFigure.doubleThree);
    expect(before(s).combo(1, keyOf(s)), Combo.doubleThree);
  });

  test('Double four: two fours at once, neither open, five points at the dots', () {
    final s = spec(GomokuFigure.doubleFour);
    final board = before(s);
    expect(board.combo(1, keyOf(s)), Combo.winIn2);
    expect(hasLine(board, keyOf(s), Line.flex4), isFalse, reason: 'two fours, not an open four');
    expect(fivePoints(s), names(cells(s.dots)));
  });

  test('VCF: every Black move is a four, White\'s reply blocks it, and 7 makes five', () {
    final s = spec(GomokuFigure.vcf);
    final board = Board.fromStones(s.rules, cells(s.black), cells(s.white), side: 1);
    final proof = ThreatSolver(board).vcf(maxNodes: 50000);
    expect(proof, isNotNull);
    expect(proof!.foursOnly, isTrue);
    expect(proof.movesToWin, 4);
    final line = cells(s.sequence);
    for (var i = 0; i < line.length; i++) {
      expect(board.stones[line[i]], 0);
      board.play(line[i]);
      if (i.isOdd) continue;
      if (i == line.length - 1) {
        expect(board.winnerThrough(line[i]), 1, reason: 'the last move makes five');
      } else {
        final fives = <int>[];
        board.fivePoints(1, fives);
        expect(fives, contains(line[i + 1]), reason: 'move ${i + 1} is a four, and White must block at ${i + 2}');
      }
    }
  });

  test('Renju\'s forbidden moves: the crossed points, and no others nearby', () {
    for (final figure in [GomokuFigure.forbiddenThree, GomokuFigure.forbiddenFour, GomokuFigure.forbiddenOverline]) {
      final s = spec(figure);
      expect(s.rules, GomokuRules.renju);
      final board = before(s);
      final forbidden = [
        for (var c = 0; c < board.area; c++)
          if (board.isForbidden(c)) c,
      ];
      expect(names(forbidden), names(cells(s.forbidden)), reason: '$figure');
      // The same point is fine under Freestyle: it is the rule, not the shape.
      final free = Board.fromStones(GomokuRules.freestyle, cells(s.black), cells(s.white), side: 1);
      expect(free.isLegal(cells(s.forbidden).single), isTrue, reason: '$figure');
    }
  });
}
