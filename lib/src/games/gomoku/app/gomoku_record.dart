/// Gomoku's game record: what the most recent game keeps, and (cut down)
/// what a coach or bot job gets. It wraps the engine's own codec: the rules
/// are `GomokuRules.toJson()`, the moves are Renju notation ("h8", "pass"),
/// and a replay is `GomokuGame.fromJson`, so the record and the engine can
/// never disagree about a game.
///
/// Seats are colours: seat 0 is Black, seat 1 is White. The deal is empty
/// (nothing is hidden or shuffled in Gomoku).
library;

import '../../../kit/game_keys.dart';
import '../../../kit/game_record.dart';
import '../../../kit/seats.dart';
import '../gomoku.dart';

/// The record format's version; a saved game of another version is ignored.
const gomokuRecordVersion = 1;

/// The colour the player asked for at setup (Random is settled from the
/// game seed, so a saved game always says who had which colour).
enum GomokuColorChoice { black, white, random }

/// The setup's choices. They go into the record (rules, seats and extra), so
/// the next setup starts from the last game's.
class GomokuOptions {
  const GomokuOptions({
    this.rules = GomokuRules.freestyle,
    this.color = GomokuColorChoice.black,
    this.level = KitLevel.medium,
    this.training = true,
  });

  final GomokuRules rules;
  final GomokuColorChoice color;

  /// The bot's level.
  final KitLevel level;

  /// Training (the coach and grades) or Free Play, fixed for the game.
  final bool training;

  GomokuOptions copyWith({GomokuRules? rules, GomokuColorChoice? color, KitLevel? level, bool? training}) =>
      GomokuOptions(
        rules: rules ?? this.rules,
        color: color ?? this.color,
        level: level ?? this.level,
        training: training ?? this.training,
      );

  /// The choices a game was started with. Anything missing or broken falls
  /// back to the default, so an odd record still opens the setup.
  factory GomokuOptions.fromRecord(GameRecord record) {
    const defaults = GomokuOptions();
    GomokuRules rules;
    try {
      rules = GomokuRules.fromJson(record.rules);
    } on Object {
      rules = defaults.rules;
    }
    final bot = record.seats.where((seat) => !seat.human).firstOrNull;
    final color = GomokuColorChoice.values.where((c) => c.name == record.extra['color']).firstOrNull;
    return GomokuOptions(
      rules: rules,
      color: color ?? defaults.color,
      level: bot?.level ?? defaults.level,
      training: record.extra['mode'] != 'free',
    );
  }

  /// What the record's extra keeps of these choices (the rules and the
  /// level are in the record's rules and seats).
  Map<String, Object?> toExtra() => {'mode': training ? 'training' : 'free', 'color': color.name};

  @override
  bool operator ==(Object other) =>
      other is GomokuOptions &&
      other.rules == rules &&
      other.color == color &&
      other.level == level &&
      other.training == training;

  @override
  int get hashCode => Object.hash(rules, color, level, training);
}

/// Reading and writing Gomoku records.
abstract final class GomokuRecord {
  /// The colour of [seat] (0 Black, 1 White).
  static Stone colorOf(int seat) => seat == 0 ? Stone.black : Stone.white;

  /// The seat of [color].
  static int seatOf(Stone color) => color == Stone.black ? 0 : 1;

  /// The colour the player gets for [choice] in the game with [seed]:
  /// Random takes one bit of a seed mixed from the game seed, so it is
  /// fixed by the seed alone.
  static Stone playerColor(GomokuColorChoice choice, int seed) => switch (choice) {
    GomokuColorChoice.black => Stone.black,
    GomokuColorChoice.white => Stone.white,
    GomokuColorChoice.random => mixSeed(seed, 0, 7).isEven ? Stone.black : Stone.white,
  };

  /// A new game's record: the player in the colour [options] give (with
  /// [seed] settling Random), a bot named [botName] in the other, and
  /// [moves] already played (none for a normal game).
  static GameRecord start(
    GomokuOptions options, {
    required int seed,
    String botName = 'Ana',
    List<String> moves = const [],
  }) {
    final player = playerColor(options.color, seed);
    SeatSpec seat(Stone color) => color == player
        ? const SeatSpec(human: true, name: 'Player')
        : SeatSpec(human: false, level: options.level, name: botName);
    return GameRecord(
      game: GameKeys.gomoku,
      version: gomokuRecordVersion,
      seed: seed,
      rules: options.rules.toJson(),
      seats: [seat(Stone.black), seat(Stone.white)],
      moves: moves,
      extra: options.toExtra(),
    );
  }

  /// The game a record (or a job's GameRecord.jobJson) describes, replayed
  /// by the engine. Throws a [FormatException] if it isn't a legal game.
  static GomokuGame replayJson(Map<String, Object?> json) => GomokuGame.fromJson({
    'rules': json['rules'],
    'moves': [for (final m in json['moves']! as List) m as String].join(' '),
  });

  /// The game [record] describes (see [replayJson]).
  static GomokuGame replay(GameRecord record) => replayJson(record.jobJson());

  /// Whether [record] is a Gomoku game this version can show: two seats and
  /// moves that replay legally under its rules.
  static bool validate(GameRecord record) {
    if (record.game != GameKeys.gomoku || record.version != gomokuRecordVersion) return false;
    if (record.seats.length != 2) return false;
    try {
      replay(record);
      return true;
    } on Object {
      return false;
    }
  }

  /// The record saved as [json], or null if it is broken, from another
  /// version, or not a legal game.
  static GameRecord? fromJson(Object? json) {
    final record = GameRecord.fromJson(json, game: GameKeys.gomoku, version: gomokuRecordVersion);
    return record != null && validate(record) ? record : null;
  }
}
