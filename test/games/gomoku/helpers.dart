import 'package:pokerfection/src/games/gomoku/board.dart';
import 'package:pokerfection/src/games/gomoku/game.dart';
import 'package:pokerfection/src/games/gomoku/patterns.dart';
import 'package:pokerfection/src/games/gomoku/rules.dart';

/// The point number of Renju notation such as "h8" on a [size] board.
int at(String notation, [int size = 15]) => GomokuMove.parse(notation).index(size);

/// Point numbers for space-separated notation.
List<int> points(String text, [int size = 15]) => [for (final m in GomokuGame.parseMoves(text)) m.index(size)];

/// Notation for a point number.
String name(int cell, [int size = 15]) => GomokuMove.fromIndex(cell, size).notation;

/// A board with the [black] and [white] stones (notation), [side] to move.
Board stones(String black, String white, {GomokuRules rules = GomokuRules.freestyle, int? side}) =>
    Board.fromStones(rules, points(black, rules.size), points(white, rules.size), side: side);

/// A game reaching the position with the [black] and [white] stones, playing
/// them alternately (Black first). Black must have as many stones as White,
/// or one more.
GomokuGame game(String black, String white, {GomokuRules rules = GomokuRules.freestyle}) {
  final b = GomokuGame.parseMoves(black), w = GomokuGame.parseMoves(white);
  assert(b.length == w.length || b.length == w.length + 1);
  return GomokuGame.fromMoves(rules, [
    for (var i = 0; i < b.length; i++) ...[b[i], if (i < w.length) w[i]],
  ]);
}

/// Exhaustive check, independent of the solver and of [Board.defenses]:
/// can the side to move on [b] force five within [n] of its own moves?
/// The attacker tries only threats (fours, and threes from three moves
/// out), so this can only under-report wins; the defender, in
/// [defenderLoses], tries every legal move. Used to verify proofs.
bool attackerWins(Board b, int n) {
  final me = b.side, opp = 3 - me;
  if (b.count(me, Combo.five) > 0) return true;
  if (n <= 1) return false;
  final candidates = <int>[];
  if (b.count(opp, Combo.five) > 0) {
    final fives = <int>[];
    b.fivePoints(opp, fives);
    if (fives.length > 1 || !b.isLegal(fives[0])) return false;
    candidates.add(fives[0]);
  } else {
    for (var c = 0; c < b.area; c++) {
      if (b.stones[c] == 0 && b.combo(me, c) >= (n == 2 ? Combo.four : Combo.flex3) && b.isLegal(c)) {
        candidates.add(c);
      }
    }
    candidates.sort((x, y) => b.combo(me, y).compareTo(b.combo(me, x)));
  }
  for (final c in candidates) {
    b.play(c);
    final wins = defenderLoses(b, n - 1);
    b.undo();
    if (wins) return true;
  }
  return false;
}

/// Whether the side to move on [b] (the defender) loses within the
/// attacker's next [n] moves whatever it plays: every legal reply is tried.
bool defenderLoses(Board b, int n) {
  final def = b.side, att = 3 - def;
  if (b.count(def, Combo.five) > 0) return false;
  if (b.count(att, Combo.five) > 0) {
    final fives = <int>[];
    b.fivePoints(att, fives);
    if (fives.length > 1 || !b.isLegal(fives[0])) return true;
    b.play(fives[0]);
    final r = attackerWins(b, n);
    b.undo();
    return r;
  }
  if (n <= 1) return false;
  for (var c = 0; c < b.area; c++) {
    if (!b.isLegal(c)) continue;
    b.play(c);
    final r = attackerWins(b, n);
    b.undo();
    if (!r) return false;
  }
  return true;
}

/// The defender's moves that stop [attacker]'s open-four threat on [b],
/// found by trying every legal move: the ones after which the attacker
/// has no open four or double four to make, plus the defender's own
/// fours. What [Board.defenses] must return.
Set<int> allDefenses(Board b, int attacker) => {
      for (var c = 0; c < b.area; c++)
        if (b.isLegal(c) && (b.combo(3 - attacker, c) >= Combo.four || _stops(b, c, attacker))) c,
    };

bool _stops(Board b, int c, int attacker) {
  b.play(c);
  final stops = !b.hasWinIn2(attacker);
  b.undo();
  return stops;
}
