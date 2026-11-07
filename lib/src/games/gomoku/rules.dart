/// Gomoku's rules as one value object that the game, the bots and the coach
/// all take, so a rule change can never reach one of them and miss another.
///
/// Sources for the rules:
/// - Freestyle (five or more wins) and Standard (exactly five):
///   https://en.wikipedia.org/wiki/Gomoku and the Gomocup rules,
///   https://gomocup.org/detail-information/
/// - Renju (Black's forbidden moves, White wins with five or more): the RIF
///   International Rules of Renju, https://www.renju.net/rifrules/ and
///   https://en.wikipedia.org/wiki/Renju
library;

/// A stone's color. Black always moves first; which player holds Black is
/// decided outside the engine (by the player against a bot, or by an
/// opening rule such as Swap2 online, where the first three stones are
/// still played in the order Black, White, Black).
enum Stone {
  black,
  white;

  /// The other color.
  Stone get opponent => this == black ? white : black;

  /// The engine's internal code for this color: 1 for Black, 2 for White
  /// (0 means an empty point).
  int get code => index + 1;

  /// The color with the internal [code] 1 or 2.
  static Stone fromCode(int code) => code == 1 ? black : white;
}

/// What makes a line of stones a win.
enum WinRule {
  /// Five or more in a row wins, for both colors (an overline of six or
  /// more also wins). The default: its rule fits in one sentence, and it is
  /// the variant Allis solved and Gomocup plays.
  freestyle(
    'Freestyle',
    'Five or more in a row wins.',
  ),

  /// Exactly five in a row wins, for both colors. Six or more in a row is
  /// an overline: it does not win, and the game goes on.
  standard(
    'Standard',
    'Exactly five in a row wins. Six or more does not.',
  ),

  /// The RIF Renju rules (without an opening rule): Black must make
  /// exactly five, and may not make a double three, a double four or an
  /// overline (a forbidden move; this engine simply does not allow it).
  /// A move that makes five wins even if it also makes one of those shapes.
  /// White has no forbidden moves and wins with five or more.
  renju(
    'Renju',
    'Black needs exactly five and may not make a double three, a double four or six in a row. White wins with five or more.',
  );

  const WinRule(this.label, this.description);

  /// A short name for menus.
  final String label;

  /// One line for the "?" note.
  final String description;

  /// Whether [stone] needs exactly five (an overline does not win for it).
  bool exactFiveFor(Stone stone) => this == standard || (this == renju && stone == Stone.black);

  /// Whether [stone] has forbidden moves (only Black, only in Renju).
  bool hasForbiddenMoves(Stone stone) => this == renju && stone == Stone.black;
}

/// The board size and the win rule, together: everything that changes how a
/// game of Gomoku is played. Immutable, comparable and serialisable, so a
/// room can send it to every device and a saved game can carry it.
class GomokuRules {
  /// Rules with a [size]×[size] board (15 or 19) and a [winRule].
  const GomokuRules({this.size = 15, this.winRule = WinRule.freestyle})
      : assert(size == 15 || size == 19, 'Gomoku boards are 15×15 or 19×19');

  /// The default: Freestyle on 15×15.
  static const freestyle = GomokuRules();

  /// Exactly five, 15×15.
  static const standard = GomokuRules(winRule: WinRule.standard);

  /// Renju, which is always played on 15×15.
  static const renju = GomokuRules(winRule: WinRule.renju);

  /// Freestyle on the larger 19×19 board (it only helps Black more, but
  /// players who know Gomoku from a Go board expect it).
  static const freestyle19 = GomokuRules(size: 19);

  /// Exactly five on 19×19.
  static const standard19 = GomokuRules(size: 19, winRule: WinRule.standard);

  /// The presets a menu offers, default first.
  static const presets = [freestyle, standard, renju, freestyle19, standard19];

  /// The number of points along each side.
  final int size;

  /// What makes a line a win.
  final WinRule winRule;

  /// The number of points on the board.
  int get area => size * size;

  /// A short label for menus, such as "Freestyle 15×15".
  String get label => '${winRule.label} $size×$size';

  /// For saving and sending: `{"size": 15, "win": "freestyle"}`.
  Map<String, Object> toJson() => {'size': size, 'win': winRule.name};

  /// The rules [toJson] wrote. Throws a [FormatException] for anything else.
  static GomokuRules fromJson(Map<String, Object?> json) {
    final size = json['size'];
    final win = WinRule.values.where((w) => w.name == json['win']).firstOrNull;
    if ((size != 15 && size != 19) || win == null) throw FormatException('Not Gomoku rules: $json');
    return GomokuRules(size: size as int, winRule: win);
  }

  @override
  bool operator ==(Object other) => other is GomokuRules && other.size == size && other.winRule == winRule;

  @override
  int get hashCode => Object.hash(size, winRule);

  @override
  String toString() => label;
}
