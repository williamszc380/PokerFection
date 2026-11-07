import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/gomoku/board.dart';
import 'package:pokerfection/src/games/gomoku/gomoku.dart';
import 'package:pokerfection/src/games/gomoku/patterns.dart';
import 'package:pokerfection/src/games/gomoku/threats.dart';

import 'helpers.dart';

/// The points where the side to move in [g] would win at once, worked out
/// from the game rules alone (not the engine's tables).
List<GomokuMove> winningPoints(GomokuGame g) =>
    [for (final m in g.legalMoves()) if (g.play(m).result?.winner == g.toMove) m];

/// The points where the player who just moved threatens to make five: what
/// they could win with if the opponent played elsewhere (the empty point
/// farthest from the last move).
Set<GomokuMove> threatsOfLastMover(GomokuGame g) {
  final last = g.lastMove!;
  int distance(GomokuMove m) => (m.x - last.x).abs() + (m.y - last.y).abs();
  final far = g.legalMoves().reduce((a, b) => distance(b) > distance(a) ? b : a);
  return winningPoints(g.play(far)).toSet();
}

/// Checks, by the rules alone, that [line] from [start] is a win by
/// continuous fours: every attacking move threatens five, every defending
/// move is the only block (or any move against two threats), and the last
/// move makes five.
void expectValidVcf(GomokuGame start, List<int> line) {
  final attacker = start.toMove;
  var g = start;
  for (var i = 0; i < line.length; i++) {
    final move = GomokuMove.fromIndex(line[i], 15);
    expect(g.isLegal(move), isTrue, reason: 'move $i ($move) of ${line.map(name)}');
    if (i.isEven) {
      g = g.play(move);
      if (i == line.length - 1) {
        expect(g.result?.winner, attacker, reason: 'the line should end with five');
      } else {
        expect(winningPoints(g), isEmpty, reason: 'the defender must not have five after $move');
        final threats = threatsOfLastMover(g);
        expect(threats, isNotEmpty, reason: '$move should threaten five');
        if (threats.length == 1) {
          expect(GomokuMove.fromIndex(line[i + 1], 15), threats.single, reason: 'the defender must block');
        }
      }
    } else {
      g = g.play(move);
    }
  }
}

void main() {
  group('VCF (victory by continuous fours)', () {
    test('a four-three: the four forces the block, then the three becomes an open four', () {
      // Black: f8 g8 h8 (closed by e8) and i9 i10. i8 makes a four across
      // and an open three up.
      final position = game('f8 g8 h8 i9 i10', 'e8 a1 a15 o1 o15');
      final board = stones('f8 g8 h8 i9 i10', 'e8 a1 a15 o1 o15');
      final proof = ThreatSolver(board).vcf()!;
      expect(name(proof.line.first), 'i8');
      expect(proof.movesToWin, 3);
      expect(proof.foursOnly, isTrue);
      expectValidVcf(position, proof.line);
    });

    test('two fours in a row, ending in a double four', () {
      // Across c3-e3 (closed by b3), up f5-f6 (closed by f7), and across
      // g4-i4 (closed by j4): f3 and f4 each make a four, and the second
      // makes two at once. (e4, a four plus the open three d3-e4-f5, wins
      // just as fast.)
      const black = 'c3 d3 e3 f5 f6 g4 h4 i4';
      const white = 'b3 f7 j4 o15 o12 l15 o9 i15';
      final proof = ThreatSolver(stones(black, white)).vcf()!;
      expect(proof.movesToWin, 3);
      expect(['f3', 'f4', 'e4'], contains(name(proof.line.first)));
      expectValidVcf(game(black, white), proof.line);
    });

    test('a ready five is a win in 1, an open four a win in 2', () {
      expect(ThreatSolver(stones('h8 i8 j8 k8', 'a1 a3 a5 a7')).vcf()!.movesToWin, 1);
      final open = ThreatSolver(stones('h8 i8 j8', 'a1 a3 a5')).vcf()!;
      expect(open.movesToWin, 2);
      expect(['g8', 'k8'], contains(name(open.line.first)));
    });

    test('finds nothing where there is nothing', () {
      expect(ThreatSolver(stones('h8 i9', 'h9 a1')).vcf(), isNull);
      // A four that is blocked at once leads nowhere.
      expect(ThreatSolver(stones('f8 g8 h8', 'e8 a1 a15')).vcf(), isNull);
    });

    test('every VCF found in real games is a real one', () {
      var found = 0;
      for (var seed = 0; seed < 25; seed++) {
        var g = GomokuGame().play(const GomokuMove(7, 7));
        final bot = GomokuBot(BotLevel.easy, seed: seed);
        while (!g.isOver && g.moves.length < 40) {
          final board = Board.fromMoves(g.rules, [for (final m in g.moves) m.index(15)]);
          final proof = ThreatSolver(board).vcf(maxNodes: 5000);
          if (proof != null) {
            found++;
            expectValidVcf(g, proof.line);
          }
          g = g.play(bot.chooseMove(g.viewFor(g.toMove)));
        }
      }
      expect(found, greaterThan(10));
    });
  });

  group('VCT (victory by continuous threats)', () {
    test('a double three wins in 3, though no four exists', () {
      const black = 'g8 h8 i9 i10', white = 'a1 a15 o1 o15';
      final solver = ThreatSolver(stones(black, white));
      expect(solver.vcf(), isNull);
      final proof = solver.vct()!;
      expect(name(proof.line.first), 'i8');
      expect(proof.movesToWin, 3);
      expect(proof.foursOnly, isFalse);

      // Checked by brute force with the game rules: after i8, whatever
      // White plays, Black makes five within two more moves.
      final after = game(black, white).play(GomokuMove.parse('i8'));
      for (final reply in after.legalMoves()) {
        final g = after.play(reply);
        final wins = winningPoints(g).isNotEmpty ||
            g.legalMoves().where((m) => (m.x - 7).abs() <= 3 && (m.y - 8).abs() <= 3).any((m) {
              final next = g.play(m);
              return !next.isOver && winningPoints(next).isEmpty && threatsOfLastMover(next).length >= 2;
            });
        expect(wins, isTrue, reason: 'White $reply');
      }
    });

    test("a double three is no win when the defender's fours win first", () {
      // As above, but White has its own four-three at e10 (b10-d10 closed by
      // a10, and e11-e12): it answers i8 with fours and wins. Black must not
      // be told it has a forced win.
      const black = 'g8 h8 i9 i10 a10', white = 'b10 c10 d10 e11 e12';
      expect(ThreatSolver(stones(black, white)).vct(), isNull);
      final forWhite = ThreatSolver(stones(black, white, side: 2)).vcf()!;
      expect(name(forWhite.line.first), 'e10');
    });

    // Each proof is checked against every reply the defender has, by the
    // exhaustive search in helpers.dart (which doesn't use the solver or
    // its list of defenses), for every proof of three or four moves found
    // in games between easy bots.
    for (final rules in [GomokuRules.freestyle, GomokuRules.standard, GomokuRules.renju]) {
      test('every short VCT found in ${rules.winRule.label} games wins against every reply', () {
        var checked = 0;
        for (var seed = 0; seed < 14; seed++) {
          var g = GomokuGame(rules).play(const GomokuMove(7, 7));
          final black = GomokuBot(BotLevel.easy, seed: seed), white = GomokuBot(BotLevel.easy, seed: seed + 77);
          while (!g.isOver && g.moves.length < 60) {
            final board = Board.fromMoves(rules, [for (final m in g.moves) m.index(15)]);
            final proof = ThreatSolver(board).vct(maxNodes: 5000);
            if (proof != null && proof.movesToWin >= 3 && proof.movesToWin <= 4) {
              checked++;
              board.play(proof.line.first);
              expect(defenderLoses(board, proof.movesToWin - 1), isTrue,
                  reason: '${g.movesText()}: ${proof.line.map(name).join(' ')}');
              board.undo();
            }
            g = g.play((g.toMove == Stone.black ? black : white).chooseMove(g.viewFor(g.toMove)));
          }
        }
        expect(checked, greaterThan(8));
      });
    }

    test('winAfter proves a move wins, or that it does not', () {
      final board = stones('f8 g8 h8 i9 i10', 'e8 a1 a15 o1 o15');
      final solver = ThreatSolver(board);
      expect(solver.winAfter(at('i8'))!.movesToWin, 3);
      expect(solver.winAfter(at('a3')), isNull);
      // j8 is also a four, but White's block at i8 spoils the four-three:
      // any win left is slower.
      expect(solver.winAfter(at('j8'))?.movesToWin ?? 99, greaterThan(3));
    });
  });

  group('the defenses against an open three', () {
    // The solver proves a win by trying only these replies, and the search
    // looks at nothing else, so they must be all of them: compared with
    // trying every legal move, in positions from random play that is
    // drawn to the stones and their shapes.
    for (final rules in [GomokuRules.freestyle, GomokuRules.standard, GomokuRules.renju, GomokuRules.standard19]) {
      test('are every move that stops it, under ${rules.label}', () {
        var checked = 0;
        for (var seed = 0; seed < 150; seed++) {
          final rng = Random(seed);
          final b = Board(rules)..play(rules.area ~/ 2);
          for (var ply = 0; ply < 70; ply++) {
            final me = b.side, att = 3 - me;
            if (b.count(me, Combo.five) > 0) break;
            if (b.count(att, Combo.five) == 0 && b.hasWinIn2(att)) {
              checked++;
              expect(b.defenses(att).toSet(), allDefenses(b, att), reason: 'seed $seed, move ${b.moveCount}');
            }
            final legal = [for (var i = 0; i < b.nearby.length; i++) b.nearby[i]].where(b.isLegal).toList()
              ..sort((x, y) {
                final c = (b.value(me, y) + b.value(att, y)).compareTo(b.value(me, x) + b.value(att, x));
                return c != 0 ? c : x.compareTo(y);
              });
            if (legal.isEmpty) break;
            b.play(legal[rng.nextInt(min(legal.length, rng.nextBool() ? 3 : 12))]);
          }
        }
        expect(checked, greaterThan(100));
      });
    }

    test('include, in Renju, a White block on a point forbidden to Black', () {
      // Black f8 g8 h8 (closed at j8): e8 is the only open-four point, so
      // d8, e8 and i8 all stop it. d8 is a double four for Black (row
      // d8_f8g8h8 and column d8-d11), but White may of course play there.
      final b = stones('f8 g8 h8 d9 d10 d11', 'j8 d12 a1 a3 o15', rules: GomokuRules.renju, side: 2);
      expect(b.isForbidden(at('d8')), isTrue);
      expect(b.defenses(1).map(name), unorderedEquals(['d8', 'e8', 'i8']));
    });
  });
}
