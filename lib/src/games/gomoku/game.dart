/// The game of Gomoku as the app sees it: an immutable position with its
/// move list, whose turn it is, which moves are legal and who has won.
library;

import 'dart:typed_data';

import 'board.dart';
import 'rules.dart';

/// A point on the board: column [x] (0 at the left, "a") and row [y]
/// (0 at the bottom, "1"), as in Renju notation, where the center of the
/// 15×15 board is "h8". Or [pass].
class GomokuMove {
  /// The point in column [x] and row [y].
  const GomokuMove(this.x, this.y);

  /// Passing: putting no stone on the board. The RIF Renju rules count a
  /// pass as a move (article 5), and it is how a Renju game goes on when
  /// every empty point is forbidden to Black. This engine allows it only
  /// then (see [GomokuGame.mustPass]); Freestyle and Standard never need it.
  static const pass = GomokuMove(-1, -1);

  /// The point numbered [index] on a board with [size] points a side, or
  /// [pass] for −1 (the engine's number for a pass).
  factory GomokuMove.fromIndex(int index, int size) => index < 0 ? pass : GomokuMove(index % size, index ~/ size);

  /// Reads Renju notation such as "h8" (column letter, then row number), or
  /// "pass". Throws a [FormatException] if it isn't one.
  factory GomokuMove.parse(String text) {
    final t = text.trim().toLowerCase();
    if (t == 'pass') return pass;
    final m = RegExp(r'^([a-s])(\d{1,2})$').firstMatch(t);
    if (m == null) throw FormatException('Not a point: $text');
    return GomokuMove(m.group(1)!.codeUnitAt(0) - 97, int.parse(m.group(2)!) - 1);
  }

  /// The column, 0 = "a".
  final int x;

  /// The row, 0 = "1".
  final int y;

  /// Whether this is [pass] rather than a point.
  bool get isPass => x < 0;

  /// The engine's number for this point on a board with [size] points a
  /// side (−1 for a pass).
  int index(int size) => isPass ? -1 : y * size + x;

  /// Whether the point is on a board with [size] points a side (never for
  /// a pass).
  bool isOn(int size) => x >= 0 && x < size && y >= 0 && y < size;

  /// Renju notation, such as "h8", or "pass".
  String get notation => isPass ? 'pass' : '${String.fromCharCode(97 + x)}${y + 1}';

  @override
  bool operator ==(Object other) => other is GomokuMove && other.x == x && other.y == y;

  @override
  int get hashCode => x * 31 + y;

  @override
  String toString() => notation;
}

/// How a finished game ended.
class GomokuResult {
  /// A win for [winner] with the stones of [line].
  const GomokuResult.win(Stone this.winner, this.line);

  /// No winner: the board is full, or (Renju) both players passed one
  /// after the other.
  const GomokuResult.draw()
      : winner = null,
        line = const [];

  /// The winner, or null for a draw.
  final Stone? winner;

  /// The winning row of stones (five, or more in Freestyle), for the board
  /// to highlight. Empty for a draw.
  final List<GomokuMove> line;

  /// Whether nobody won.
  bool get isDraw => winner == null;
}

/// What one seat may see. Gomoku hides nothing, so every view holds the
/// whole game; the [seat] only says whose side the viewer is on (null for
/// a spectator), which the coach uses to word its advice.
class GomokuView {
  /// [game] as seen from [seat].
  const GomokuView(this.game, this.seat);

  /// The whole game.
  final GomokuGame game;

  /// The viewer's color, or null for a spectator.
  final Stone? seat;
}

/// A position in a game of Gomoku, with the moves that led to it.
/// Immutable: [play] returns a new game, so the app can keep every position
/// of a game for analysis and undo.
class GomokuGame {
  GomokuGame._(this.rules, this.moves, this._cells, this.result);

  /// An empty board under [rules] (Freestyle 15×15 by default).
  factory GomokuGame([GomokuRules rules = GomokuRules.freestyle]) =>
      GomokuGame._(rules, const [], Uint8List(rules.area), null);

  /// The game after playing [moves] in order (Black first). Throws an
  /// [ArgumentError] if one of them is illegal.
  factory GomokuGame.fromMoves(GomokuRules rules, Iterable<GomokuMove> moves) {
    var game = GomokuGame(rules);
    for (final m in moves) {
      game = game.play(m);
    }
    return game;
  }

  /// The game written by [toJson]. Throws a [FormatException] if it isn't one.
  factory GomokuGame.fromJson(Map<String, Object?> json) {
    final rules = GomokuRules.fromJson((json['rules'] as Map).cast<String, Object?>());
    final text = json['moves'];
    if (text is! String) throw FormatException('No moves: $json');
    try {
      return GomokuGame.fromMoves(rules, parseMoves(text));
    } on ArgumentError catch (e) {
      throw FormatException('Bad game: ${e.message}');
    }
  }

  /// Reads space-separated Renju notation, such as "h8 h9 i9".
  static List<GomokuMove> parseMoves(String text) =>
      [for (final t in text.trim().split(RegExp(r'\s+'))) if (t.isNotEmpty) GomokuMove.parse(t)];

  /// The rules of this game.
  final GomokuRules rules;

  /// Every move so far, Black's first (a pass included, see
  /// [GomokuMove.pass]).
  final List<GomokuMove> moves;

  final Uint8List _cells;

  /// How the game ended, or null while it goes on.
  final GomokuResult? result;

  /// Whether the game has ended.
  bool get isOver => result != null;

  /// The color to move (Black on an empty board).
  Stone get toMove => moves.length.isEven ? Stone.black : Stone.white;

  /// The stone on point ([x], [y]), or null if it is empty.
  Stone? stoneAt(int x, int y) {
    final c = _cells[y * rules.size + x];
    return c == 0 ? null : Stone.fromCode(c);
  }

  /// The last move (perhaps a pass), or null on an empty board.
  GomokuMove? get lastMove => moves.isEmpty ? null : moves.last;

  /// The engine's board for this position, built when first needed (the
  /// Renju legality check uses its line tables).
  late final Board _board = Board.fromMoves(rules, [for (final m in moves) m.index(rules.size)]);

  /// Whether the side to move has no point it may play, and so must pass:
  /// possible only for Black in Renju, when every empty point left is
  /// forbidden. The RIF rules let a player pass (article 5), and the game
  /// goes on with White's move; without the pass it would be stuck.
  late final bool mustPass = !isOver &&
      rules.winRule.hasForbiddenMoves(toMove) &&
      !Iterable<int>.generate(rules.area).any((i) => _cells[i] == 0 && _board.isLegalFor(Stone.black.code, i));

  /// Whether the side to move may play [move]: the game goes on, the point
  /// is on the board and empty and, for Black in Renju, not forbidden. A
  /// pass is legal only when it is the only move ([mustPass]).
  bool isLegal(GomokuMove move) {
    if (move.isPass) return mustPass;
    if (isOver || !move.isOn(rules.size)) return false;
    final i = move.index(rules.size);
    if (_cells[i] != 0) return false;
    if (!rules.winRule.hasForbiddenMoves(toMove)) return true;
    return _board.isLegalFor(Stone.black.code, i);
  }

  /// Every legal move, row by row (just [GomokuMove.pass] when Black must
  /// pass).
  List<GomokuMove> legalMoves() {
    if (isOver) return const [];
    if (mustPass) return const [GomokuMove.pass];
    return [
      for (var i = 0; i < rules.area; i++)
        if (_cells[i] == 0 && (!rules.winRule.hasForbiddenMoves(toMove) || _board.isLegalFor(1, i)))
          GomokuMove.fromIndex(i, rules.size),
    ];
  }

  /// The empty points Black may not play (Renju only, and only on Black's
  /// turn; empty otherwise), for the board to mark.
  List<GomokuMove> forbiddenMoves() {
    if (isOver || !rules.winRule.hasForbiddenMoves(toMove)) return const [];
    return [
      for (var i = 0; i < rules.area; i++)
        if (_cells[i] == 0 && _board.isForbidden(i)) GomokuMove.fromIndex(i, rules.size),
    ];
  }

  /// The game after the side to move plays [move]. Throws an [ArgumentError]
  /// if it is illegal.
  GomokuGame play(GomokuMove move) {
    if (!isLegal(move)) throw ArgumentError('Illegal move ${move.notation} in ${movesText()}');
    if (move.isPass) {
      // RIF article 10.3: two passes in a row are a draw. (Only Black can
      // have to pass, so it can't happen in this engine; kept for safety.)
      final twice = lastMove?.isPass ?? false;
      return GomokuGame._(rules, List.unmodifiable([...moves, move]), _cells, twice ? const GomokuResult.draw() : null);
    }
    final cells = Uint8List.fromList(_cells);
    final color = toMove;
    cells[move.index(rules.size)] = color.code;
    final line = _winningLine(cells, move, color);
    final next = [...moves, move];
    GomokuResult? result;
    if (line != null) {
      result = GomokuResult.win(color, line);
    } else if (next.where((m) => !m.isPass).length == rules.area) {
      // RIF article 10.1, and the usual rule elsewhere: a full board is a draw.
      result = const GomokuResult.draw();
    }
    return GomokuGame._(rules, List.unmodifiable(next), cells, result);
  }

  /// This game seen from [seat] (null for a spectator).
  GomokuView viewFor(Stone? seat) => GomokuView(this, seat);

  /// The moves in Renju notation, separated by spaces.
  String movesText() => moves.map((m) => m.notation).join(' ');

  /// For saving the most recent game, or sending it: the rules and moves.
  Map<String, Object> toJson() => {'rules': rules.toJson(), 'moves': movesText()};

  // The stones of a winning row through move, or null. Freestyle: five or
  // more. Standard: exactly five. Renju: exactly five for Black, five or
  // more for White (see rules.dart for the sources).
  List<GomokuMove>? _winningLine(Uint8List cells, GomokuMove move, Stone color) {
    final size = rules.size;
    final exact = rules.winRule.exactFiveFor(color);
    for (var d = 0; d < 4; d++) {
      final run = [move];
      for (final sign in const [1, -1]) {
        var x = move.x + Board.dx[d] * sign, y = move.y + Board.dy[d] * sign;
        while (x >= 0 && x < size && y >= 0 && y < size && cells[y * size + x] == color.code) {
          run.add(GomokuMove(x, y));
          x += Board.dx[d] * sign;
          y += Board.dy[d] * sign;
        }
      }
      if (run.length == 5 || (run.length > 5 && !exact)) {
        run.sort((a, b) => a.x != b.x ? a.x - b.x : a.y - b.y);
        return run;
      }
    }
    return null;
  }
}
