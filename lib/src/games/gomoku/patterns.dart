/// Line shapes and their lookup tables: the heart of the engine's speed.
///
/// For every empty point and each of the four directions, the board keeps
/// a key for the ten points around it on that line (five on each side, two
/// bits each: empty, Black, White or off the board). A table turns that key
/// into the shape the line would make if a given color played the point:
/// five, open four, four, open three and so on. Each table entry is worked
/// out once, the first time it is needed, from the definitions below, so
/// the board never has to scan a line during search.
library;

import 'dart:typed_data';

/// The shape one line makes through a point, for the color that would put
/// a stone there. Ordered from weakest to strongest (except [overline]).
///
/// The definitions are the classical ones (Allis 1994, "Go-Moku and
/// Threat-Space Search"; the RIF Renju rules for "three" and "four"):
/// a four can become five with one more stone, an open (straight) four in
/// two ways at both ends, and a three can become a four (an open three can
/// become an open four).
abstract final class Line {
  /// Five can never be made through this point on this line.
  static const dead = 0;

  /// Only the stone itself: five is still possible, nothing more.
  static const one = 1;

  /// Can become a closed three.
  static const block2 = 2;

  /// Can become an open three ("open two").
  static const flex2 = 3;

  /// Can become a four, but not an open four ("closed three").
  static const block3 = 4;

  /// Can become an open four ("open three", including broken threes such
  /// as `_XX_X_`).
  static const flex3 = 5;

  /// One point away from five ("four").
  static const block4 = 6;

  /// An open (straight) four: four in a row with both ends free, so it can
  /// become five at either end and cannot be stopped.
  static const flex4 = 7;

  /// Two fours on one line that are not a straight four, such as
  /// `X_XXX_X`. Unstoppable like an open four, but in Renju it is Black's
  /// forbidden double four.
  static const doubleFour = 8;

  /// Five in a row (or more, where the rule allows it): the game is won.
  static const five = 9;

  /// Six or more in a row where only exactly five wins: not a win. In Renju
  /// it is Black's forbidden overline.
  static const overline = 10;

  /// Names for tests and debugging.
  static const names = [
    'dead', 'one', 'block2', 'flex2', 'block3', 'flex3', 'block4', 'flex4', 'doubleFour', 'five', 'overline', //
  ];
}

/// What a move makes over all four lines through its point together (a
/// "combination"). Ordered so that a bigger number is a stronger threat.
abstract final class Combo {
  /// The point is taken, or the move is forbidden.
  static const none = 0;

  /// Anything less than the shapes below.
  static const low = 1;

  /// An open three, or two closed threes (the start of a double four).
  static const flex3 = 2;

  /// An open three plus a closed three.
  static const flex3Plus = 3;

  /// Two or more open threes ("double three", 3-3).
  static const doubleThree = 4;

  /// A four (plus nothing that wins by itself).
  static const four = 5;

  /// A four and an open three together ("four-three", 4-3): usually wins.
  static const fourThree = 6;

  /// An open four or two fours: wins on the next move.
  static const winIn2 = 7;

  /// Five in a row: wins now.
  static const five = 8;

  /// The number of combination values.
  static const count = 9;

  /// The lowest value the board tracks in its sets of threatening points.
  static const threatening = flex3;
}

/// The lookup table for one color under one win rule, filled lazily.
///
/// A key holds ten points, two bits each: bits 0–9 are the five points
/// before the center (farthest first), bits 10–19 the five after it.
/// Each point is 0 (empty), 1 (Black), 2 (White) or 3 (off the board).
/// The center itself is not in the key: the table answers "what would this
/// line be if [self] played the center".
final class PatternTable {
  PatternTable._(this.self, this.exactFive, this.straightThreesOnly);

  /// The table for color [self] (1 Black, 2 White). [exactFive]: only
  /// exactly five wins (Standard, and Black in Renju). [straightThreesOnly]:
  /// a three only counts if it can become a straight four, and two fours on
  /// one line are no use (Black in Renju, where that is a foul).
  /// Tables are shared and live for the whole program.
  static PatternTable of(int self, {required bool exactFive, bool straightThreesOnly = false}) {
    final id = self * 4 + (exactFive ? 2 : 0) + (straightThreesOnly ? 1 : 0);
    return _tables[id] ??= PatternTable._(self, exactFive, straightThreesOnly);
  }

  static final _tables = <int, PatternTable>{};

  /// The number of points in a key.
  static const keyPoints = 10;

  /// The number of different keys.
  static const keyCount = 1 << 20;

  /// The color this table is for.
  final int self;

  /// Whether only exactly five wins.
  final bool exactFive;

  /// Whether only straight-four threes count (Renju Black).
  final bool straightThreesOnly;

  // 255 marks an entry not worked out yet. When five or more wins, the
  // points five away from the center can never matter (a five through the
  // center lies within four points of it, and nothing beyond can spoil it),
  // so the table only needs the inner eight points: 64 KB, which stays in
  // the processor's cache, instead of 1 MB.
  late final Uint8List _memo = exactFive
      ? (Uint8List(keyCount)..fillRange(0, keyCount, 255))
      : (Uint8List(1 << 16)..fillRange(0, 1 << 16, 255));

  int _slot(int key) => exactFive ? key : (key >> 2) & 0xFFFF;

  /// The bit position of the point at [offset] (−5…−1, 1…5) from the center.
  static int shiftOf(int offset) => 2 * (offset < 0 ? offset + 5 : offset + 4);

  /// The [Line] shape for [key].
  int operator [](int key) {
    final known = _memo[exactFive ? key : (key >> 2) & 0xFFFF];
    return known != 255 ? known : _classify(exactFive ? key : key & 0x3FFFC);
  }

  int _classify(int key) {
    // The line as 11 points, with the center (index 5) holding our stone.
    final line = Int8List(11);
    for (var e = 0; e < 11; e++) {
      if (e == 5) {
        line[e] = self;
      } else {
        line[e] = (key >> (2 * (e < 5 ? e : e - 1))) & 3;
      }
    }
    if (!exactFive) {
      // The outermost points are not in the small table's key (see _memo).
      line[0] = 3;
      line[10] = 3;
    }

    int result;
    final run = _run(line);
    if (run >= 5) {
      result = exactFive && run > 5 ? Line.overline : Line.five;
    } else {
      // The points that would make five through the center.
      var fives = 0, first = -1, last = -1;
      for (var e = 0; e < 11; e++) {
        if (line[e] != 0) continue;
        line[e] = self;
        final r = _run(line);
        line[e] = 0;
        if (r == 5 || (!exactFive && r > 5)) {
          fives++;
          if (first < 0) first = e;
          last = e;
        }
      }
      if (fives >= 2) {
        // Two five points five apart enclose four stones in a row: a
        // straight four. Any other pair is two separate fours.
        result = fives == 2 && last - first == 5 ? Line.flex4 : Line.doubleFour;
      } else if (fives == 1) {
        result = Line.block4;
      } else {
        // Otherwise the shape is one step below the best shape one more
        // stone could make here.
        result = Line.dead;
        for (var e = 0; e < 11; e++) {
          if (line[e] != 0) continue;
          final sub = this[key | (self << (2 * (e < 5 ? e : e - 1)))];
          final down = _stepDown(sub);
          if (down > result) result = down;
          if (result == Line.flex3) break;
        }
      }
    }
    _memo[_slot(key)] = result;
    return result;
  }

  int _stepDown(int sub) {
    switch (sub) {
      case Line.flex4:
        return Line.flex3;
      case Line.doubleFour:
        return straightThreesOnly ? Line.dead : Line.flex3;
      case Line.block4:
        return Line.block3;
      case Line.flex3:
        return Line.flex2;
      case Line.block3:
        return Line.block2;
      case Line.flex2:
      case Line.block2:
      case Line.one:
        return Line.one;
      default:
        return Line.dead;
    }
  }

  // How many of our stones are in a row through the center.
  int _run(Int8List line) {
    var n = 1;
    for (var i = 4; i >= 0 && line[i] == self; i--) {
      n++;
    }
    for (var i = 6; i <= 10 && line[i] == self; i++) {
      n++;
    }
    return n;
  }
}
