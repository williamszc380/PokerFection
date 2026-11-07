import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/gomoku/board.dart';
import 'package:pokerfection/src/games/gomoku/gomoku.dart';
import 'package:pokerfection/src/games/gomoku/patterns.dart';
import 'package:pokerfection/src/games/gomoku/search.dart';

import 'helpers.dart';

/// The points where the side to move would win at once, by the rules alone.
List<GomokuMove> winningPoints(GomokuGame g) =>
    [for (final m in g.legalMoves()) if (g.play(m).result?.winner == g.toMove) m];

/// Positions from quick games between easy bots, many of them with fours
/// and threes on the board.
Iterable<GomokuGame> positions(int games) sync* {
  for (var seed = 0; seed < games; seed++) {
    var g = GomokuGame().play(const GomokuMove(7, 7));
    final black = GomokuBot(BotLevel.easy, seed: seed), white = GomokuBot(BotLevel.easy, seed: seed + 50);
    while (!g.isOver) {
      yield g;
      g = g.play((g.toMove == Stone.black ? black : white).chooseMove(g.viewFor(g.toMove)));
    }
  }
}

void main() {
  test('every level makes five when it can', () {
    var checked = 0;
    for (final g in positions(30)) {
      final wins = winningPoints(g);
      if (wins.isEmpty) continue;
      for (final level in BotLevel.values) {
        expect(wins, contains(GomokuBot(level).chooseMove(g.viewFor(g.toMove))), reason: '$level in ${g.movesText()}');
      }
      checked++;
    }
    expect(checked, greaterThan(20));
  });

  test("every level blocks the opponent's four when it can't win at once", () {
    var checked = 0;
    for (final g in positions(30)) {
      if (winningPoints(g).isNotEmpty) continue;
      // The opponent's five points: where it would win if we passed.
      final board = Board.fromMoves(g.rules, [for (final m in g.moves) m.index(15)]);
      final threats = <int>[];
      board.fivePoints(3 - board.side, threats);
      if (threats.length != 1) continue;
      for (final level in BotLevel.values) {
        expect(GomokuBot(level).chooseMove(g.viewFor(g.toMove)).index(15), threats.single,
            reason: '$level in ${g.movesText()}');
      }
      checked++;
    }
    expect(checked, greaterThan(20));
  });

  test('medium and hard answer an open three (or attack with a four)', () {
    var checked = 0;
    for (final g in positions(12)) {
      final board = Board.fromMoves(g.rules, [for (final m in g.moves) m.index(15)]);
      final me = board.side, opp = 3 - me;
      if (board.count(me, Combo.five) + board.count(opp, Combo.five) > 0 || !board.hasWinIn2(opp)) continue;
      if (board.defenses(opp).isEmpty) continue; // lost anyway
      for (final level in [BotLevel.medium, BotLevel.hard]) {
        final move = GomokuBot(level).chooseMove(g.viewFor(g.toMove)).index(15);
        final four = board.combo(me, move) >= Combo.four;
        board.play(move);
        final stopped = !board.hasWinIn2(opp);
        board.undo();
        expect(four || stopped, isTrue, reason: '$level played ${name(move)} in ${g.movesText()}');
      }
      if (++checked >= 8) break;
    }
    expect(checked, greaterThan(3));
  });

  test('the search alone finds a four-three and sees that it wins', () {
    final board = stones('f8 g8 h8 i9 i10', 'e8 a1 a15 o1 o15');
    final result = Searcher(board).search(const SearchLimits(maxNodes: 20000));
    expect(name(result.move), 'i8');
    expect(result.score, greaterThan(Searcher.winBound));
    expect(result.pv.map(name).take(2), ['i8', 'j8']);
  });

  test('the first move goes in the center', () {
    for (final level in BotLevel.values) {
      expect(GomokuBot(level).chooseMove(GomokuGame().viewFor(Stone.black)), GomokuMove.parse('h8'));
    }
  });

  test('bots are deterministic for a seed (with no time limit)', () {
    List<GomokuMove> play(int seed) {
      var g = GomokuGame();
      final black = GomokuBot(BotLevel.medium, seed: seed), white = GomokuBot(BotLevel.easy, seed: seed);
      while (!g.isOver) {
        g = g.play((g.toMove == Stone.black ? black : white).chooseMove(g.viewFor(g.toMove)));
      }
      return g.moves;
    }

    expect(play(3), play(3));
    final mid = GomokuGame.fromMoves(GomokuRules.freestyle, GomokuGame.parseMoves('h8 j6 f6 e5 e7 g5 h5 g6'));
    expect(GomokuBot(BotLevel.hard).chooseMove(mid.viewFor(mid.toMove)),
        GomokuBot(BotLevel.hard).chooseMove(mid.viewFor(mid.toMove)));
  });

  test('hard beats easy, with either color', () {
    for (final hardIsBlack in [true, false]) {
      var g = GomokuGame();
      final hard = GomokuBot(BotLevel.hard), easy = GomokuBot(BotLevel.easy, seed: 5);
      while (!g.isOver) {
        final hardToMove = (g.toMove == Stone.black) == hardIsBlack;
        g = g.play((hardToMove ? hard : easy).chooseMove(g.viewFor(g.toMove)));
      }
      expect(g.result!.winner, hardIsBlack ? Stone.black : Stone.white, reason: g.movesText());
    }
  });
}
