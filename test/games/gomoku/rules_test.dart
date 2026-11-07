import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/gomoku/gomoku.dart';

import 'helpers.dart';

GomokuMove m(String notation) => GomokuMove.parse(notation);

void main() {
  group('moves', () {
    test('use Renju notation: column letter, row number from the bottom', () {
      expect(m('h8'), const GomokuMove(7, 7));
      expect(m('A1'), const GomokuMove(0, 0));
      expect(m('o15').notation, 'o15');
      expect(m('h8').index(15), 7 * 15 + 7);
      expect(GomokuMove.fromIndex(7 * 15 + 7, 15), m('h8'));
      expect(() => GomokuMove.parse('z1'), throwsFormatException);
      expect(() => GomokuMove.parse('h'), throwsFormatException);
    });

    test('a pass is written "pass", and is legal only when nothing else is', () {
      expect(m('pass'), GomokuMove.pass);
      expect(GomokuMove.pass.notation, 'pass');
      expect(GomokuMove.pass.index(15), -1);
      expect(GomokuMove.fromIndex(-1, 15), GomokuMove.pass);
      // Only Black in Renju can be left with no legal point (renju_test.dart).
      for (final rules in GomokuRules.presets) {
        final g = game('h8', '', rules: rules);
        expect(g.mustPass, isFalse);
        expect(g.isLegal(GomokuMove.pass), isFalse);
        expect(() => g.play(GomokuMove.pass), throwsArgumentError);
      }
    });
  });

  group('a new game', () {
    test('starts empty with Black to move, and colors alternate', () {
      var game = GomokuGame();
      expect(game.toMove, Stone.black);
      expect(game.legalMoves().length, 225);
      game = game.play(m('h8'));
      expect(game.toMove, Stone.white);
      expect(game.stoneAt(7, 7), Stone.black);
      game = game.play(m('h9'));
      expect(game.toMove, Stone.black);
      expect(game.stoneAt(7, 8), Stone.white);
      expect(game.legalMoves().length, 223);
    });

    test('is immutable: playing returns a new game', () {
      final empty = GomokuGame();
      final after = empty.play(m('h8'));
      expect(empty.moves, isEmpty);
      expect(after.moves, [m('h8')]);
    });

    test('19×19 boards work the same way', () {
      final game = GomokuGame(GomokuRules.freestyle19).play(m('j10')).play(m('s19'));
      expect(game.stoneAt(18, 18), Stone.white);
      expect(game.legalMoves().length, 361 - 2);
    });
  });

  group('illegal moves', () {
    test('a taken point, a point off the board, and any move after the end', () {
      final start = GomokuGame().play(m('h8'));
      expect(start.isLegal(m('h8')), isFalse);
      expect(start.isLegal(const GomokuMove(15, 0)), isFalse);
      expect(() => start.play(m('h8')), throwsArgumentError);
      final won = game('a1 b1 c1 d1 e1', 'a2 b2 c2 d2');
      expect(won.isOver, isTrue);
      expect(won.legalMoves(), isEmpty);
      expect(won.isLegal(m('h8')), isFalse);
    });
  });

  group('Freestyle (the default): five or more wins', () {
    test('five in a row wins, and the result names the five stones', () {
      final g = game('c3 d3 e3 f3 g3', 'c5 d5 e5 f5');
      expect(g.result!.winner, Stone.black);
      expect(g.result!.line, GomokuGame.parseMoves('c3 d3 e3 f3 g3'));
    });

    test('diagonals count, in both directions', () {
      expect(game('a1 b2 c3 d4 e5', 'a3 a4 a5 a6').result!.winner, Stone.black);
      expect(game('o1 n2 m3 l4 a15', 'a1 b2 c3 d4 e5').result!.winner, Stone.white);
    });

    test('six in a row (an overline) also wins', () {
      final g = game('c3 d3 e3 g3 h3 f3', 'c5 d5 e5 g5 o15');
      expect(g.result!.winner, Stone.black);
      expect(g.result!.line.length, 6);
    });

    test('four does not win', () {
      expect(game('c3 d3 e3 f3', 'c5 d5 e5').isOver, isFalse);
    });
  });

  group('Standard: exactly five wins', () {
    const rules = GomokuRules.standard;
    test('five wins', () {
      expect(game('c3 d3 e3 f3 g3', 'c5 d5 e5 f5', rules: rules).result!.winner, Stone.black);
    });

    test('an overline does not win, and the game goes on', () {
      final g = game('c3 d3 e3 g3 h3 f3', 'c5 d5 e5 g5 o15', rules: rules);
      expect(g.isOver, isFalse);
      expect(g.toMove, Stone.white);
    });

    test('an overline in one line and five in another wins', () {
      // f3 makes six across and five up.
      final g = game('c3 d3 e3 g3 h3 f4 f5 f6 f7 f3', 'a1 a3 a5 a7 a9 a11 a13 a15 c15', rules: rules);
      expect(g.result!.winner, Stone.black);
      expect(g.result!.line, GomokuGame.parseMoves('f3 f4 f5 f6 f7'));
    });
  });

  group('Renju: exactly five for Black, five or more for White', () {
    const rules = GomokuRules.renju;
    test('White wins with an overline', () {
      final g = game('a1 a3 a5 a7 a9 a11', 'c3 d3 e3 g3 h3 f3', rules: rules);
      expect(g.result!.winner, Stone.white);
    });

    test("Black's overline is forbidden, so it can't be played", () {
      final g = game('c3 d3 e3 g3 h3', 'a1 a3 a5 a7 a9', rules: rules);
      expect(g.isLegal(m('f3')), isFalse);
      expect(g.forbiddenMoves(), contains(m('f3')));
      expect(() => g.play(m('f3')), throwsArgumentError);
    });

    test('Black wins with exactly five', () {
      expect(game('c3 d3 e3 f3 g3', 'a1 a3 a5 a7', rules: rules).result!.winner, Stone.black);
    });
  });

  group('saving the most recent game', () {
    test('round-trips through JSON', () {
      final g = game('h8 i9 j10', 'h9 h10', rules: GomokuRules.standard19);
      final copy = GomokuGame.fromJson(g.toJson());
      expect(copy.rules, GomokuRules.standard19);
      expect(copy.moves, g.moves);
      expect(copy.toMove, Stone.white);
    });

    test('rejects anything that is not a game', () {
      expect(() => GomokuGame.fromJson({'rules': {'size': 13, 'win': 'freestyle'}, 'moves': ''}), throwsFormatException);
      expect(() => GomokuGame.fromJson({'rules': GomokuRules.freestyle.toJson(), 'moves': 'h8 h8'}),
          throwsFormatException);
    });
  });

  test('the presets start with the default, Freestyle 15×15', () {
    expect(GomokuRules.presets.first, GomokuRules.freestyle);
    expect(GomokuRules.freestyle.label, 'Freestyle 15×15');
    expect(GomokuRules.presets.map((r) => r.winRule).toSet(), WinRule.values.toSet());
  });
}
