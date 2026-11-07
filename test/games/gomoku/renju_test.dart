// Renju's forbidden moves for Black, from the RIF International Rules of
// Renju (https://www.renju.net/rifrules/): a double three, a double four
// and an overline are fouls, unless the move makes exactly five; a three
// only counts if it can become a straight four by a move that is itself
// allowed.
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/gomoku/gomoku.dart';
import 'package:pokerfection/src/games/gomoku/patterns.dart';
import 'package:pokerfection/src/games/gomoku/threats.dart';

import 'helpers.dart';

const renju = GomokuRules.renju;

void main() {
  test('a double three is forbidden for Black, but White may play there', () {
    // h8 makes f8-g8-h8 and h8-h9-h10, both open.
    final g = game('f8 g8 h9 h10', 'a1 a3 a5 a7', rules: renju);
    expect(g.isLegal(GomokuMove.parse('h8')), isFalse);
    expect(g.forbiddenMoves(), contains(GomokuMove.parse('h8')));
    final whiteToMove = game('f8 g8 h9 h10 o15', 'a1 a3 a5 a7', rules: renju);
    expect(whiteToMove.isLegal(GomokuMove.parse('h8')), isTrue);
    expect(whiteToMove.forbiddenMoves(), isEmpty);
  });

  test('the same double three is fine in Freestyle', () {
    expect(game('f8 g8 h9 h10', 'a1 a3 a5 a7').isLegal(GomokuMove.parse('h8')), isTrue);
  });

  test('a double four is forbidden', () {
    // h8 makes e8-h8 (closed by d8) and h8-h11 (closed by h12).
    final board = stones('e8 f8 g8 h9 h10 h11', 'd8 h12 a1 a3 a5 a7', rules: renju);
    expect(board.isForbidden(at('h8')), isTrue);
  });

  test('four-three is allowed', () {
    final board = stones('e8 f8 g8 h9 h10', 'd8 a1 a3 a5 a7', rules: renju);
    expect(board.isForbidden(at('h8')), isFalse);
    expect(board.combo(1, at('h8')), Combo.fourThree);
  });

  test('five wins even when the same move makes an overline or a double four', () {
    // h8 makes d8-h8 (five) and h7-h12 (six).
    final board = stones('d8 e8 f8 g8 h7 h9 h10 h11 h12', 'a1 a3 a5 a7 a9 a11 a13 a15 c1', rules: renju);
    expect(board.isForbidden(at('h8')), isFalse);
    expect(board.combo(1, at('h8')), Combo.five);
  });

  test('a three whose only straight four would be an overline is no three', () {
    // e8-f8-g8 with Black on b8 and j8: d8 or h8 would make a four whose
    // other end makes six, so the row is not open. With g9-g10 that makes
    // only one three at g8: allowed.
    final board = stones('b8 e8 f8 j8 g9 g10', 'a1 a3 a5 a7 a9 o15', rules: renju);
    expect(board.pattern(1, at('g8'), 0), isNot(Line.flex3));
    expect(board.isForbidden(at('g8')), isFalse);
    // Without b8 and j8 it is a real double three.
    expect(stones('e8 f8 g9 g10', 'a1 a3 a5 a7', rules: renju).isForbidden(at('g8')), isTrue);
  });

  test('a three whose only straight four is itself a forbidden point is no three', () {
    // g8 makes e8-f8-g8 (closed on the left by c8, so h8 is its only
    // straight four) and g8-g9-g10 (open, completed at g11). But h8 is a
    // double four for Black (h9-h11 closed by h12, i9-k11 closed by l12),
    // so the row is not a real three and g8 is allowed.
    final board = stones(
      'e8 f8 g9 g10 h9 h10 h11 i9 j10 k11',
      'c8 h12 l12 a1 a3 a5 a7 a9 a11 a13',
      rules: renju,
    );
    expect(board.isForbidden(at('h8')), isTrue);
    expect(board.pattern(1, at('g8'), 0), Line.flex3);
    expect(board.pattern(1, at('g8'), 1), Line.flex3);
    expect(board.isForbidden(at('g8')), isFalse);
  });

  test("White wins with a four whose five point Black can't take", () {
    // g8 would give Black six in a row (d8-i8), so Black can't block g12's
    // four there. (g7 and g13 keep White from simply making an open four.)
    final board = stones('d8 e8 f8 h8 i8 g7 g13', 'g9 g10 g11 a1 a3 a5', rules: renju);
    expect(board.side, 2);
    expect(board.isForbidden(at('g8')), isTrue);
    final proof = ThreatSolver(board).vcf()!;
    expect(proof.movesToWin, 2);
    expect(name(proof.line.first), 'g12');
  });

  test('bots never play a forbidden move', () {
    final g = game('f8 g8 h9 h10', 'a1 a3 a5 a7', rules: renju);
    for (final level in BotLevel.values) {
      final move = GomokuBot(level).chooseMove(g.viewFor(Stone.black));
      expect(g.isLegal(move), isTrue, reason: '$level played $move');
    }
  });

  test('Standard rules count an overline as no win but allow it', () {
    final board = stones('d8 e8 f8 h8 i8', 'a1 a3 a5 a7 a9', rules: GomokuRules.standard);
    expect(board.isForbidden(at('g8')), isFalse);
    expect(board.combo(1, at('g8')), isNot(Combo.five));
  });

  group('a White block on a point forbidden to Black', () {
    // Black: row g8 h8 (closed at j8), column d9-d11 (closed at d12), and a
    // separate forced win in the lower right. White: b6 c7 and e7 f6, so
    // White d8 is a double three. f8 makes Black's row an open three whose
    // one open-four point is e8, and makes d8 a double four for Black, so
    // White can block on d8 and attack at the same time.
    const black = 'g8 h8 d9 d10 d11 l3 k5 m3 m4 o6';
    const white = 'j8 d12 b6 c7 e7 f6 l1 o1 l5 a15';

    test('means f8 is no forced win: White d8 blocks and wins (checked against every reply)', () {
      final board = stones(black, white, rules: renju, side: 1);
      board.play(at('f8'));
      board.play(at('d8'));
      expect(defenderLoses(board, 4), isTrue, reason: 'White forces five against every Black reply');
      board.undo();
      board.undo();
      expect(ThreatSolver(board).winAfter(at('f8')), isNull, reason: 'the solver must not prove f8 wins');
    });

    test('so the coach does not call f8 a sure win', () {
      final g = game(black, white, rules: renju);
      final f8 = GomokuMove.parse('f8');
      final a = const GomokuCoach().analyze(g.viewFor(Stone.black), include: f8);
      expect(a.of(f8)!.winsIn, isNull);
      expect(a.of(f8)!.reasons, isNot(contains(MoveReason.startsForcedWin)));
    });
  });

  group('when every empty point is forbidden to Black', () {
    // A game reached by legal play (random moves that avoid fives) with
    // five points left, all forbidden to Black, Black to move. RIF rules,
    // article 5: a player may pass; article 10.1: only a full board (or
    // two passes in a row, 10.3) is a draw.
    final stuck = GomokuGame.fromMoves(renju, GomokuGame.parseMoves(_stuck));

    test('Black must pass: it is the only legal move, and the game goes on', () {
      expect(stuck.isOver, isFalse);
      expect(stuck.toMove, Stone.black);
      expect(stuck.forbiddenMoves(), hasLength(5));
      expect(stuck.mustPass, isTrue);
      expect(stuck.legalMoves(), [GomokuMove.pass]);
      expect(stuck.isLegal(GomokuMove.pass), isTrue);
      expect(stuck.isLegal(stuck.forbiddenMoves().first), isFalse);
      final after = stuck.play(GomokuMove.pass);
      expect(after.isOver, isFalse);
      expect(after.toMove, Stone.white);
      expect(after.legalMoves(), hasLength(5), reason: 'White may play any empty point');
    });

    test('every bot passes, and the coach says why', () {
      for (final level in BotLevel.values) {
        expect(GomokuBot(level).chooseMove(stuck.viewFor(Stone.black)), GomokuMove.pass, reason: '$level');
      }
      final analysis = const GomokuCoach().analyze(stuck.viewFor(Stone.black));
      expect(analysis.best!.move, GomokuMove.pass);
      expect(analysis.best!.reasons, [MoveReason.mustPass]);
      expect(GomokuAnalysis.fromJson(analysis.toJson()).best!.move, GomokuMove.pass);
    });

    test('bots play the game out from there, and it saves with the passes', () {
      var g = stuck;
      while (!g.isOver) {
        g = g.play(GomokuBot(BotLevel.hard).chooseMove(g.viewFor(g.toMove)));
      }
      expect(g.moves.where((m) => m.isPass), isNotEmpty);
      expect(GomokuGame.fromJson(g.toJson()).moves, g.moves);
    });
  });
}

const _stuck = 'h6 k4 i5 k9 h13 m3 f14 a11 g7 b11 d2 h2 b3 l2 m6 f8 a9 n7 b9 g1 a13 j10 k13 n8 b13 e6 g15 o3 k5 m15 '
    'b12 n15 a15 o11 m7 d4 m9 m4 j15 k10 f4 c9 e4 a7 i6 n10 h1 d15 o2 o15 k11 b5 k12 i3 e2 j9 i13 a6 i14 m1 '
    'n2 f10 j3 i8 b15 c10 f2 b1 g10 l14 o13 g11 o14 m13 b8 a8 d9 l4 n14 f7 g4 j1 a5 b10 e12 l8 c13 a10 h11 c15 '
    'j7 e3 f6 e1 m2 d5 d8 e5 o12 f1 m14 g14 b14 b7 h9 i1 a2 j2 n4 g12 m12 j12 i11 g2 n5 l3 o1 c6 c2 m8 c4 h12 '
    'h7 l13 l7 c14 e14 h4 n13 a4 e9 k7 o5 g8 f12 i10 f13 d3 o10 o9 n9 d14 o6 l12 h14 a3 a1 f15 e8 g13 j14 j5 '
    'l1 c11 e13 c3 h3 a14 o8 e7 i2 i15 l6 g9 k1 g5 c5 b2 n12 o4 i4 n1 d11 k2 l9 i7 g3 k14 d1 n11 j13 m11 d6 j4 '
    'k15 i12 l15 d13 o7 e15 c1 d12 i9 b6 f11 b4 c8 n6 h10 g6 j8 h15 l10 c12 h5 j11 e10 m10 d10 a12 c7 f5 n3 f9 '
    'j6 f3 k3 l11 m5 l5';
