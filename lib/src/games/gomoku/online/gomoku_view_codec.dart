/// Gomoku's online rules and views, as the room sends them and every device
/// reads them: the runner writes them, the app's table, bot and coach read
/// them. Pure Dart (the room runs in a browser and in bin/server.dart too).
///
/// Gomoku hides nothing, so a seat's view is the spectators' view plus the
/// seat it is for:
///
/// ```json
/// {"rules": {"size": 15, "win": "renju"}, "black": 0, "moves": "h8 i9 pass", "you": 1}
/// ```
///
/// - `rules`: the engine's own GomokuRules JSON;
/// - `black`: the hand seat playing Black this game (the other plays White);
/// - `moves`: every move so far in Renju notation, Black's first, so the
///   whole game (the stones, whose turn, the result, Renju's forbidden
///   points) is replayed by the engine itself and can't disagree with it;
/// - `you`: the seat the view is for (seat views only).
library;

import '../game.dart';
import '../rules.dart';

/// The version of these views and of the move notation ("h8", "pass"): a
/// device with another one watches nothing ("Update the app to watch").
const gomokuOnlineGv = 1;

/// Who plays Black, game after game (Black moves first, a big edge).
enum GomokuBlackRule {
  /// The seats take turns: the first seat has Black in the first game, the
  /// other in the next, and so on.
  turns,

  /// Each game, Black goes to a seat drawn from the room's secure Random.
  random,

  /// Whoever lost the last game has Black (the weaker player gets the
  /// edge); the first seat in the first game, and after a draw Black
  /// changes seats.
  loser,
}

/// A room's Gomoku rules: the engine's [rules] and who plays Black.
class GomokuOnlineRules {
  const GomokuOnlineRules({this.rules = GomokuRules.freestyle, this.black = GomokuBlackRule.turns});

  final GomokuRules rules;
  final GomokuBlackRule black;

  GomokuOnlineRules copyWith({GomokuRules? rules, GomokuBlackRule? black}) =>
      GomokuOnlineRules(rules: rules ?? this.rules, black: black ?? this.black);

  /// `{"size": 15, "win": "freestyle", "black": "turns"}`.
  Map<String, Object?> toJson() => {...rules.toJson(), 'black': black.name};

  /// The rules [toJson] wrote, read strictly (a member may send anything):
  /// exactly these three keys with known values, and Renju only on 15×15.
  /// Throws [FormatException] otherwise.
  static GomokuOnlineRules fromJson(Object? json) {
    if (json is! Map || json.length != 3 || !json.keys.every(const {'size', 'win', 'black'}.contains)) {
      throw const FormatException('Not Gomoku rules');
    }
    final black = GomokuBlackRule.values.where((b) => b.name == json['black']).firstOrNull;
    if (black == null) throw const FormatException('Not a Black rule');
    if (json['size'] is! int) throw const FormatException('Not a board size');
    final rules = GomokuRules.fromJson({'size': json['size'], 'win': json['win']});
    // Renju is played on 15×15 only (the setup greys 19×19 out under it).
    if (rules.winRule == WinRule.renju && rules.size != 15) throw const FormatException('Renju is 15×15');
    return GomokuOnlineRules(rules: rules, black: black);
  }

  @override
  bool operator ==(Object other) => other is GomokuOnlineRules && other.rules == rules && other.black == black;

  @override
  int get hashCode => Object.hash(rules, black);
}

/// The view everyone may see: the rules, Black's seat and the moves.
Map<String, Object?> gomokuPublicView(GomokuRules rules, int black, GomokuGame game) => {
  'rules': rules.toJson(),
  'black': black,
  'moves': game.movesText(),
};

/// Hand seat [seat]'s view rebuilt from the spectators' view: the same,
/// with the seat (nothing is hidden, so never null for a seat in the game).
Map<String, Object?>? gomokuSeatViewFrom(Map<String, Object?> spectatorView, int seat) {
  if (seat != 0 && seat != 1) return null;
  return {...spectatorView, 'you': seat};
}

/// A view read back: the game replayed by the engine, Black's seat, and
/// the seat it is for (null: the spectators').
class GomokuOnlineView {
  const GomokuOnlineView({required this.game, required this.black, this.you});

  /// Reads [view] (from the room, or a job's input). Throws
  /// [FormatException] if it isn't a Gomoku view or its moves aren't a
  /// legal game.
  factory GomokuOnlineView.fromJson(Map<String, Object?> view) {
    final rules = view['rules'], black = view['black'], moves = view['moves'], you = view['you'];
    if (rules is! Map || (black != 0 && black != 1) || moves is! String || (you != null && you != 0 && you != 1)) {
      throw const FormatException('Not a Gomoku view');
    }
    final game = GomokuGame.fromJson({'rules': rules.cast<String, Object?>(), 'moves': moves});
    return GomokuOnlineView(game: game, black: black! as int, you: you as int?);
  }

  final GomokuGame game;

  /// The hand seat playing Black.
  final int black;

  /// The seat the view is for; null for the spectators'.
  final int? you;

  /// [seat]'s colour.
  Stone colorOf(int seat) => seat == black ? Stone.black : Stone.white;

  /// The seat playing [color].
  int seatOf(Stone color) => color == Stone.black ? black : 1 - black;

  /// The seat to move (null once the game is over).
  int? get seatToAct => game.isOver ? null : seatOf(game.toMove);

  /// The winner's seat (null: no winner, or not over yet).
  int? get winner => switch (game.result?.winner) {
    final Stone stone => seatOf(stone),
    null => null,
  };
}
