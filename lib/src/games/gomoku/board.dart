/// The engine's fast, mutable board: the search plays and takes back moves
/// on it millions of times, so everything the search asks about (the shape
/// of every line through every empty point, the threats each color has,
/// the points worth looking at) is kept up to date move by move instead of
/// being recomputed.
library;

import 'dart:math';
import 'dart:typed_data';

import 'patterns.dart';
import 'rules.dart';

/// A set of points with constant-time add, remove and membership, which can
/// be walked in insertion order (more or less). Used for the points near
/// stones and for each color's threatening points.
final class CellSet {
  /// An empty set for a board of [area] points.
  CellSet(int area)
      : _items = Int16List(area),
        _pos = Int16List(area)..fillRange(0, area, -1);

  final Int16List _items;
  final Int16List _pos;

  /// The number of points in the set.
  int length = 0;

  /// The point at [i] (0 ≤ i < [length]).
  int operator [](int i) => _items[i];

  /// Whether [cell] is in the set.
  bool contains(int cell) => _pos[cell] >= 0;

  /// Adds [cell] (no effect if present).
  void add(int cell) {
    if (_pos[cell] >= 0) return;
    _pos[cell] = length;
    _items[length++] = cell;
  }

  /// Removes [cell] (no effect if absent).
  void remove(int cell) {
    final p = _pos[cell];
    if (p < 0) return;
    final last = _items[--length];
    _items[p] = last;
    _pos[last] = p;
    _pos[cell] = -1;
  }
}

/// The board the bots, solvers and coach work on. Points are numbered
/// `y * size + x`. Colors are 1 (Black) and 2 (White); Black moves first.
final class Board {
  /// An empty board for [rules].
  Board(this.rules)
      : size = rules.size,
        area = rules.area,
        stones = Uint8List(rules.area),
        _keys = Int32List(rules.area * 4),
        _pat = Uint8List(rules.area * 8),
        _combo = Uint8List(rules.area * 2),
        _flags = Uint8List(rules.area),
        _value = Int32List(rules.area * 2),
        _near = Uint8List(rules.area),
        nearby = CellSet(rules.area),
        threats = [CellSet(rules.area), CellSet(rules.area)],
        _history = Int16List(rules.area * 2),
        _seen = Int32List(rules.area),
        _hits = Int16List(rules.area),
        _renju = rules.winRule == WinRule.renju,
        _lines = _linesFor(rules.size),
        _square = _squareFor(rules.size),
        _zobrist = _zobristFor(rules.area),
        _tables = [
          PatternTable.of(1,
              exactFive: rules.winRule.exactFiveFor(Stone.black),
              straightThreesOnly: rules.winRule.hasForbiddenMoves(Stone.black)),
          PatternTable.of(2, exactFive: rules.winRule.exactFiveFor(Stone.white)),
        ],
        _comboTables = [
          _comboCache[rules.winRule == WinRule.renju] ??= _comboTable(rules.winRule == WinRule.renju),
          _comboCache[false] ??= _comboTable(false),
        ] {
    for (var c = 0; c < area; c++) {
      for (var d = 0; d < 4; d++) {
        var key = 0;
        for (var o = -5; o <= 5; o++) {
          if (o != 0 && _lines[(c * 4 + d) * 11 + o + 5] < 0) key |= 3 << PatternTable.shiftOf(o);
        }
        _keys[c * 4 + d] = key;
      }
      _count[Combo.none] += 1;
      _count[Combo.count + Combo.none] += 1;
      _repattern(c);
      _refresh(c);
    }
  }

  /// A board with [moves] (point numbers, Black first) played.
  factory Board.fromMoves(GomokuRules rules, Iterable<int> moves) {
    final board = Board(rules);
    for (final m in moves) {
      board.play(m);
    }
    return board;
  }

  /// A board with the [black] and [white] stones on it, whatever order
  /// they came in and even if Black's stones would be forbidden (for
  /// puzzles and tests). The side to move is [side] (1 Black, 2 White);
  /// by default Black when the counts are equal, White otherwise.
  factory Board.fromStones(GomokuRules rules, Iterable<int> black, Iterable<int> white, {int? side}) {
    final board = Board(rules);
    for (final (color, cells) in [(1, black), (2, white)]) {
      for (final c in cells) {
        board._place(c, color);
        board._history[board.moveCount++] = c;
      }
    }
    board.side = side ?? (black.length == white.length ? 1 : 2);
    return board;
  }

  /// The rules this board plays by.
  final GomokuRules rules;

  /// Points along each side.
  final int size;

  /// Points on the board.
  final int area;

  /// What is on each point: 0 empty, 1 Black, 2 White.
  final Uint8List stones;

  /// The empty points within two steps of a stone, where any sensible move
  /// is (the first move of a game aside).
  final CellSet nearby;

  /// For each color (index 0 Black, 1 White), the empty points where its
  /// move would make at least an open three ([Combo.threatening]).
  final List<CellSet> threats;

  final Int32List _keys; // per point and direction: the line key
  final Uint8List _pat; // per point, direction and color: the Line shape
  final Uint8List _combo; // per point and color: the Combo
  final Uint8List _flags; // per point: Renju forbidden marks for Black
  final Int32List _value; // per point and color: how good the move is
  final Uint8List _near; // per point: stones within two steps
  final Int32List _count = Int32List(Combo.count * 2); // per color and Combo
  final Int32List _total = Int32List(2); // per color: sum of point values
  final Int16List _history;
  final Int32List _seen; // per point: the defenses() call that last saw it
  final Int16List _hits; // per point: how many targets it touches
  int _stamp = 0;
  final bool _renju;
  final Int16List _lines;
  final Int16List _square;
  final Uint32List _zobrist;
  final List<PatternTable> _tables;
  final List<Int32List> _comboTables;

  /// The number of moves played: the stones on the board, plus any passes
  /// (see [play]).
  int moveCount = 0;

  /// The color to move: 1 Black, 2 White.
  int side = 1;

  /// The low 32 bits of the position's Zobrist hash (two 32-bit halves, so
  /// the JavaScript build, which has no 64-bit integers, hashes the same).
  int hashLo = 0;

  /// The high 32 bits of the position's Zobrist hash.
  int hashHi = 0;

  static const _forbidden = 1; // Black may not play here (Renju), surely
  static const _maybeForbidden = 2; // two open threes: forbidden if both are real

  /// The four line directions: across, up, and the two diagonals.
  static const dx = [1, 0, 1, 1];

  /// See [dx].
  static const dy = [0, 1, 1, -1];

  /// How much each [Line] shape adds to the value of playing a point. The
  /// evaluation is the sum of these over the empty points for each color.
  static const lineValue = [0, 1, 4, 12, 16, 48, 60, 300, 300, 2000, 0];

  /// The bonus each [Combo] adds on top of [lineValue].
  static const comboValue = [0, 0, 6, 30, 200, 0, 500, 300, 0];

  /// The point at the center (where the first move goes).
  int get center => (size ~/ 2) * size + size ~/ 2;

  /// The last move played, or −1 on an empty board or after a pass.
  int get lastMove => moveCount == 0 ? -1 : _history[moveCount - 1];

  /// The move played [n] moves ago (0 = the last one).
  int moveAt(int index) => _history[index];

  /// A hash that fits in 53 bits (safe as a JavaScript number), for maps.
  int get key53 => hashLo * 0x200000 + (hashHi & 0x1FFFFF);

  /// The point [offset] steps (−5…5) from [cell] in direction [dir], or −1
  /// when that is off the board.
  int lineCell(int cell, int dir, int offset) => _lines[(cell * 4 + dir) * 11 + offset + 5];

  /// The [Line] shape [color] would make in direction [dir] by playing the
  /// empty point [cell].
  int pattern(int color, int cell, int dir) => _pat[cell * 8 + dir * 2 + color - 1];

  /// The [Combo] [color] would make by playing the empty point [cell]
  /// ([Combo.none] for a taken point or, for Renju Black, a surely
  /// forbidden one).
  int combo(int color, int cell) => _combo[cell * 2 + color - 1];

  /// How many empty points give [color] the combination [combo].
  int count(int color, int combo) => _count[(color - 1) * Combo.count + combo];

  /// How good playing [cell] is for [color], from its line shapes.
  int value(int color, int cell) => _value[cell * 2 + color - 1];

  /// Plays [cell] for the side to move; −1 passes (Renju, when Black has
  /// no legal point; the searches never pass).
  void play(int cell) {
    if (cell < 0) {
      _history[moveCount++] = -1;
      side = 3 - side;
      return;
    }
    _place(cell, side);
    _history[moveCount++] = cell;
    side = 3 - side;
  }

  /// Takes back the last move.
  void undo() {
    final cell = _history[--moveCount];
    side = 3 - side;
    if (cell >= 0) _remove(cell);
  }

  /// Whether the side to move may play [cell].
  bool isLegal(int cell) => isLegalFor(side, cell);

  /// Whether [color] may play [cell]: it must be empty and, for Black in
  /// Renju, not forbidden.
  bool isLegalFor(int color, int cell) {
    if (stones[cell] != 0) return false;
    if (color != 1 || !_renju) return true;
    final f = _flags[cell];
    if (f == 0) return true;
    if (f & _forbidden != 0) return false;
    return !_isDoubleThree(cell);
  }

  /// Whether Black playing [cell] would be a forbidden move in Renju
  /// (an overline, a double four or a double three, unless it makes five).
  /// Always false under the other rules.
  bool isForbidden(int cell) => _renju && stones[cell] == 0 && !isLegalFor(1, cell);

  /// Whether [color] has a legal move that makes an open four or a double
  /// four (so it wins with its next move unless the opponent can make five
  /// first).
  bool hasWinIn2(int color) {
    if (count(color, Combo.winIn2) == 0) return false;
    if (color != 1 || !_renju) return true;
    // Collected first: the legality check plays moves, which reorders the set.
    final set = threats[0];
    final cells = [
      for (var i = 0; i < set.length; i++)
        if (_combo[set[i] * 2] == Combo.winIn2) set[i],
    ];
    return cells.any((c) => isLegalFor(1, c));
  }

  /// The defender's moves that can stop [attacker]'s open-four threat (an
  /// open three, or a point for a double four): every legal move after
  /// which the attacker has no such move left, plus the defender's own
  /// fours (which gain a tempo). Any other move loses to the open four, so
  /// the threat solver may prove a win by trying only these, and the
  /// search looks at nothing else when the opponent has an open three. The
  /// defender is the side to move.
  ///
  /// The list must be complete, or a "proof" could skip the one reply that
  /// holds. So the candidates come from geometry, not from the attacker's
  /// shapes: a stone changes a point's shape only on the lines through it,
  /// within five points, so every target point (where the attacker would
  /// make the open four) must be taken, or have one of its four-making
  /// lines blocked; and the candidates are the points that do that for
  /// every target at once. Each is then checked by playing it. (Checking
  /// only the points where the attacker itself would make a four misses,
  /// in Renju, a White block on a point that is forbidden to Black.)
  ///
  /// One Renju case reaches further: a target that is also a double three
  /// is forbidden once both of its threes are real (RIF rules, article 9.3),
  /// and whether a three is real depends on other points' legality, which a
  /// White stone anywhere near can change. For such a target every empty
  /// point is tried.
  List<int> defenses(int attacker) {
    final def = 3 - attacker;
    final out = <int>[];
    // Collected first: checking legality and trying defenses play moves,
    // which reorders the sets.
    final attSet = threats[attacker - 1], defSet = threats[def - 1];
    final mine = [
      for (var i = 0; i < defSet.length; i++)
        if (combo(def, defSet[i]) >= Combo.four) defSet[i],
    ];
    final targets = [
      for (var i = 0; i < attSet.length; i++)
        if (combo(attacker, attSet[i]) == Combo.winIn2) attSet[i],
    ]..retainWhere((c) => isLegalFor(attacker, c));
    if (targets.isNotEmpty) {
      final reachesFar = attacker == 1 && _renju && targets.any((t) => _flags[t] & _maybeForbidden != 0);
      final candidates = reachesFar
          ? [for (var c = 0; c < area; c++) if (stones[c] == 0) c]
          : _blockPoints(targets, attacker);
      for (final c in candidates) {
        _tryDefense(c, attacker, def, out);
      }
    }
    for (final c in mine) {
      if (!out.contains(c) && isLegal(c)) out.add(c);
    }
    return out;
  }

  // The empty points that touch every target: the target itself, or an
  // empty point within five of it on one of its lines where the attacker
  // would make a four (a stone on any other line can't take away the open
  // four or the double four).
  List<int> _blockPoints(List<int> targets, int attacker) {
    final stamp = ++_stamp;
    for (var k = 0; k < targets.length; k++) {
      final t = targets[k];
      void touch(int q) {
        if (_seen[q] != stamp) {
          if (k > 0) return; // not near an earlier target
          _seen[q] = stamp;
          _hits[q] = 0;
        }
        if (_hits[q] == k) _hits[q] = k + 1;
      }

      touch(t);
      for (var d = 0; d < 4; d++) {
        final p = pattern(attacker, t, d);
        if (p != Line.block4 && p != Line.flex4 && p != Line.doubleFour) continue;
        for (var o = -5; o <= 5; o++) {
          final q = o == 0 ? -1 : lineCell(t, d, o);
          if (q >= 0 && stones[q] == 0) touch(q);
        }
      }
    }
    final first = targets.first, all = targets.length;
    final out = <int>[if (_hits[first] == all) first];
    for (var d = 0; d < 4; d++) {
      for (var o = -5; o <= 5; o++) {
        final q = o == 0 ? -1 : lineCell(first, d, o);
        if (q >= 0 && _seen[q] == stamp && _hits[q] == all) {
          _hits[q] = 0; // listed once, even if two directions reach it
          out.add(q);
        }
      }
    }
    return out;
  }

  void _tryDefense(int c, int attacker, int def, List<int> out) {
    if (!isLegal(c)) return;
    if (combo(def, c) >= Combo.four) {
      out.add(c);
      return;
    }
    play(c);
    final stops = !hasWinIn2(attacker);
    undo();
    if (stops) out.add(c);
  }

  /// Appends to [out] the points where [color] would make five.
  void fivePoints(int color, List<int> out) {
    if (count(color, Combo.five) == 0) return;
    final set = threats[color - 1];
    for (var i = 0; i < set.length; i++) {
      final c = set[i];
      if (_combo[c * 2 + color - 1] == Combo.five) out.add(c);
    }
  }

  /// The first point where [color] would make five, or −1.
  int firstFivePoint(int color) {
    if (count(color, Combo.five) == 0) return -1;
    final set = threats[color - 1];
    for (var i = 0; i < set.length; i++) {
      final c = set[i];
      if (_combo[c * 2 + color - 1] == Combo.five) return c;
    }
    return -1;
  }

  /// The static evaluation for the side to move: its point values minus
  /// the opponent's, plus a bonus when it can already make a four-three or
  /// a double three (which usually win, since it moves first).
  int evaluate() {
    final me = side, opp = 3 - side;
    var score = _total[me - 1] - _total[opp - 1];
    if (count(me, Combo.fourThree) > 0) {
      score += 3000;
    } else if (count(me, Combo.doubleThree) > 0 && count(opp, Combo.four) + count(opp, Combo.fourThree) == 0) {
      score += 1200;
    }
    return score;
  }

  /// The color whose stones make a winning line through [cell] (which must
  /// hold a stone), or 0. Used to check boards, not in search.
  int winnerThrough(int cell) {
    final color = stones[cell];
    if (color == 0) return 0;
    final exact = rules.winRule.exactFiveFor(Stone.fromCode(color));
    for (var d = 0; d < 4; d++) {
      var run = 1;
      for (var o = 1; o <= 5; o++) {
        final q = lineCell(cell, d, o);
        if (q < 0 || stones[q] != color) break;
        run++;
      }
      for (var o = -1; o >= -5; o--) {
        final q = lineCell(cell, d, o);
        if (q < 0 || stones[q] != color) break;
        run++;
      }
      if (run == 5 || (run > 5 && !exact)) return color;
    }
    return 0;
  }

  // ---------------------------------------------------------------------
  // Incremental updates.

  void _place(int cell, int color) {
    stones[cell] = color;
    final z = (cell * 2 + color - 1) * 2;
    hashLo ^= _zobrist[z];
    hashHi ^= _zobrist[z + 1];
    _clear(cell);
    nearby.remove(cell);
    for (var d = 0; d < 4; d++) {
      final base = (cell * 4 + d) * 11 + 5;
      for (var o = 1; o <= 5; o++) {
        final q = _lines[base + o];
        if (q < 0) break;
        _keys[q * 4 + d] |= color << PatternTable.shiftOf(-o);
        if (stones[q] == 0) _update(q, d);
      }
      for (var o = -1; o >= -5; o--) {
        final q = _lines[base + o];
        if (q < 0) break;
        _keys[q * 4 + d] |= color << PatternTable.shiftOf(-o);
        if (stones[q] == 0) _update(q, d);
      }
    }
    final s0 = cell * 25;
    for (var i = 0; i < 25; i++) {
      final q = _square[s0 + i];
      if (q < 0) continue;
      if (_near[q]++ == 0 && stones[q] == 0) nearby.add(q);
    }
  }

  void _remove(int cell) {
    final color = stones[cell];
    stones[cell] = 0;
    final z = (cell * 2 + color - 1) * 2;
    hashLo ^= _zobrist[z];
    hashHi ^= _zobrist[z + 1];
    for (var d = 0; d < 4; d++) {
      final base = (cell * 4 + d) * 11 + 5;
      for (var o = 1; o <= 5; o++) {
        final q = _lines[base + o];
        if (q < 0) break;
        _keys[q * 4 + d] &= 0xFFFFF ^ (3 << PatternTable.shiftOf(-o));
        if (stones[q] == 0) _update(q, d);
      }
      for (var o = -1; o >= -5; o--) {
        final q = _lines[base + o];
        if (q < 0) break;
        _keys[q * 4 + d] &= 0xFFFFF ^ (3 << PatternTable.shiftOf(-o));
        if (stones[q] == 0) _update(q, d);
      }
    }
    final s0 = cell * 25;
    for (var i = 0; i < 25; i++) {
      final q = _square[s0 + i];
      if (q < 0) continue;
      if (--_near[q] == 0) nearby.remove(q);
    }
    _repattern(cell);
    _refresh(cell);
    if (_near[cell] > 0) nearby.add(cell);
  }

  // The line in direction d through the empty point q changed.
  void _update(int q, int d) {
    final key = _keys[q * 4 + d];
    final i = q * 8 + d * 2;
    final black = _tables[0][key], white = _tables[1][key];
    // Often a far stone changes nothing about the shape: skip the rest.
    if (black == _pat[i] && white == _pat[i + 1]) return;
    _pat[i] = black;
    _pat[i + 1] = white;
    _refresh(q);
  }

  // Works out all four lines through the empty point q.
  void _repattern(int q) {
    for (var d = 0; d < 4; d++) {
      final key = _keys[q * 4 + d];
      final i = q * 8 + d * 2;
      _pat[i] = _tables[0][key];
      _pat[i + 1] = _tables[1][key];
    }
  }

  // The point became taken: it no longer counts for either color.
  void _clear(int q) {
    for (var col = 0; col < 2; col++) {
      _setCombo(q, col, Combo.none, 0);
    }
    _flags[q] = 0;
  }

  // Recomputes the combination and value of the empty point q, from the
  // four line shapes for each color, by table.
  void _refresh(int q) {
    final i = q * 8;
    final ib = ((_pat[i] * 11 + _pat[i + 2]) * 11 + _pat[i + 4]) * 11 + _pat[i + 6];
    final iw = ((_pat[i + 1] * 11 + _pat[i + 3]) * 11 + _pat[i + 5]) * 11 + _pat[i + 7];
    final black = _comboTables[0], white = _comboTables[1];
    final packedB = black[ib], packedW = white[iw];
    _flags[q] = packedB >> 28;
    _setCombo(q, 0, (packedB >> 24) & 15, packedB & 0xFFFFFF);
    _setCombo(q, 1, (packedW >> 24) & 15, packedW & 0xFFFFFF);
  }

  // For every set of four line shapes: the combination (bits 24–27), the
  // Renju flags for Black (bits 28–29) and the value (bits 0–23). Index
  // ((p0 * 11 + p1) * 11 + p2) * 11 + p3.
  static Int32List _comboTable(bool renjuBlack) {
    final t = Int32List(11 * 11 * 11 * 11);
    for (var index = 0; index < t.length; index++) {
      var n5 = 0, nF4 = 0, nDouble = 0, nB4 = 0, nF3 = 0, nB3 = 0, nOver = 0, sum = 0;
      for (var rest = index, d = 0; d < 4; d++, rest ~/= 11) {
        final p = rest % 11;
        sum += lineValue[p];
        switch (p) {
          case Line.five:
            n5++;
          case Line.flex4:
            nF4++;
          case Line.doubleFour:
            nDouble++;
          case Line.block4:
            nB4++;
          case Line.flex3:
            nF3++;
          case Line.block3:
            nB3++;
          case Line.overline:
            nOver++;
        }
      }
      var flags = 0;
      int combo;
      if (n5 > 0) {
        combo = Combo.five; // RIF: five wins even if it also makes a foul shape
      } else if (renjuBlack && (nOver > 0 || nF4 + nB4 + 2 * nDouble >= 2)) {
        combo = Combo.none; // RIF: overline and double four are fouls for Black
        flags = _forbidden;
      } else {
        if (renjuBlack && nF3 >= 2) flags = _maybeForbidden;
        if (nF4 + nDouble > 0 || nB4 >= 2) {
          combo = Combo.winIn2;
        } else if (nB4 == 1) {
          combo = nF3 > 0 ? Combo.fourThree : Combo.four;
        } else if (nF3 >= 2) {
          combo = Combo.doubleThree;
        } else if (nF3 == 1) {
          combo = nB3 > 0 ? Combo.flex3Plus : Combo.flex3;
        } else if (nB3 >= 2) {
          combo = Combo.flex3;
        } else {
          combo = Combo.low;
        }
      }
      final value = flags == _forbidden ? 0 : sum + comboValue[combo];
      t[index] = (flags << 28) | (combo << 24) | value;
    }
    return t;
  }

  static final _comboCache = <bool, Int32List>{};

  void _setCombo(int q, int col, int combo, int value) {
    final ci = q * 2 + col;
    final old = _combo[ci];
    if (old != combo) {
      _count[col * Combo.count + old]--;
      _count[col * Combo.count + combo]++;
      _combo[ci] = combo;
      if (combo >= Combo.threatening) {
        threats[col].add(q);
      } else {
        threats[col].remove(q);
      }
    }
    _total[col] += value - _value[ci];
    _value[ci] = value;
  }

  // RIF rules, article on the double three: a three counts only if it can
  // become a straight four with a move that is not itself forbidden, so the
  // check recurses.
  bool _isDoubleThree(int cell) {
    final dirs = <int>[];
    for (var d = 0; d < 4; d++) {
      if (pattern(1, cell, d) == Line.flex3) dirs.add(d);
    }
    if (dirs.length < 2) return false;
    _place(cell, 1);
    var real = 0;
    for (final d in dirs) {
      if (_realThree(cell, d)) real++;
      if (real >= 2) break;
    }
    _remove(cell);
    return real >= 2;
  }

  // Whether Black's stone at cell (just placed) is part of a three in
  // direction d that can become a straight four through a legal move.
  bool _realThree(int cell, int d) {
    for (var o = -4; o <= 4; o++) {
      if (o == 0) continue;
      final q = lineCell(cell, d, o);
      if (q < 0 || stones[q] != 0 || pattern(1, q, d) != Line.flex4) continue;
      // The straight four made at q must include cell.
      var lo = o, hi = o;
      while (lo - 1 >= -5 && _isBlackAt(cell, d, lo - 1)) {
        lo--;
      }
      while (hi + 1 <= 5 && _isBlackAt(cell, d, hi + 1)) {
        hi++;
      }
      if (lo > 0 || hi < 0) continue;
      if (isLegalFor(1, q)) return true;
    }
    return false;
  }

  bool _isBlackAt(int cell, int d, int o) {
    final q = lineCell(cell, d, o);
    return q >= 0 && stones[q] == 1;
  }

  // ---------------------------------------------------------------------
  // Tables shared by every board of a size.

  static final _linesCache = <int, Int16List>{};
  static final _squareCache = <int, Int16List>{};
  static final _zobristCache = <int, Uint32List>{};

  static Int16List _linesFor(int size) => _linesCache[size] ??= () {
        final t = Int16List(size * size * 44);
        for (var y = 0; y < size; y++) {
          for (var x = 0; x < size; x++) {
            final c = y * size + x;
            for (var d = 0; d < 4; d++) {
              for (var o = -5; o <= 5; o++) {
                final nx = x + dx[d] * o, ny = y + dy[d] * o;
                t[(c * 4 + d) * 11 + o + 5] =
                    nx >= 0 && nx < size && ny >= 0 && ny < size ? ny * size + nx : -1;
              }
            }
          }
        }
        return t;
      }();

  static Int16List _squareFor(int size) => _squareCache[size] ??= () {
        final t = Int16List(size * size * 25);
        for (var y = 0; y < size; y++) {
          for (var x = 0; x < size; x++) {
            var i = (y * size + x) * 25;
            for (var oy = -2; oy <= 2; oy++) {
              for (var ox = -2; ox <= 2; ox++) {
                final nx = x + ox, ny = y + oy;
                t[i++] = (ox == 0 && oy == 0) || nx < 0 || nx >= size || ny < 0 || ny >= size ? -1 : ny * size + nx;
              }
            }
          }
        }
        return t;
      }();

  // Fixed seed: the same position always has the same hash, on every
  // platform, which keeps searches reproducible.
  static Uint32List _zobristFor(int area) => _zobristCache[area] ??= () {
        final rng = Random(0x60E0C0);
        final t = Uint32List(area * 4);
        for (var i = 0; i < t.length; i++) {
          t[i] = (rng.nextInt(0x10000) << 16) | rng.nextInt(0x10000);
        }
        return t;
      }();
}
