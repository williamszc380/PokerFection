/// One game (or one deal, or one shoe) as plain JSON: what the most recent
/// game keeps, and, cut down, what a coach or bot job gets.
library;

import 'grading.dart';
import 'seats.dart';

/// Who sits in a seat.
class SeatSpec {
  const SeatSpec({required this.human, this.level, required this.name});

  /// A person at this device; otherwise a bot at [level].
  final bool human;
  final KitLevel? level;
  final String name;

  Map<String, Object?> toJson() => {'human': human, 'level': ?level?.name, 'name': name};

  /// Throws on anything that isn't a seat (GameRecord.fromJson catches it).
  factory SeatSpec.fromJson(Object? json) {
    final map = json! as Map<String, Object?>;
    final level = map['level'] as String?;
    return SeatSpec(
      human: map['human']! as bool,
      level: level == null ? null : KitLevel.values.byName(level),
      name: map['name']! as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SeatSpec && other.human == human && other.level == level && other.name == name;

  @override
  int get hashCode => Object.hash(human, level, name);
}

/// A game so far: the rules, the seats, the deal and the moves, with the
/// player's grades, the result and the screen's toggles. Each game's codec
/// (in `lib/src/games/<key>/app/`) fills [rules], [deal] and [moves] in its
/// own notation and replays them; the kit only stores and cuts them.
class GameRecord {
  GameRecord({
    required this.game,
    required this.version,
    required this.seed,
    this.rules = const {},
    this.seats = const [],
    this.deal = const {},
    List<String> moves = const [],
    List<MoveMark?>? marks,
    this.result,
    this.extra = const {},
    DateTime? played,
  })  : moves = List.unmodifiable(moves),
        marks = List.unmodifiable([
          for (var i = 0; i < moves.length; i++) i < (marks?.length ?? 0) ? marks![i] : null,
        ]),
        played = played ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// The game's key (GameKeys).
  final String game;

  /// The game's codec version; a record of another version is ignored.
  final int version;

  /// The game seed (every other seed comes from mixSeed).
  final int seed;
  final Map<String, Object?> rules;
  final List<SeatSpec> seats;
  final Map<String, Object?> deal;

  /// The game's moves in its own notation, in order.
  final List<String> moves;

  /// The player's grade per move (null: a bot's move, Free Play, or not
  /// graded); always as long as [moves].
  final List<MoveMark?> marks;

  /// The game's result once it is over.
  final Map<String, Object?>? result;

  /// The mode and the setup's choices, and the screen's toggles ('coach',
  /// 'sort', 'counter', 'count'): carried into the next game.
  final Map<String, Object?> extra;

  /// When the game started (TurnController stamps it at the deal; 1970
  /// when nobody did).
  final DateTime played;

  GameRecord copyWith({
    List<String>? moves,
    List<MoveMark?>? marks,
    Map<String, Object?>? Function()? result,
    Map<String, Object?>? extra,
    DateTime? played,
  }) =>
      GameRecord(
        game: game,
        version: version,
        seed: seed,
        rules: rules,
        seats: seats,
        deal: deal,
        moves: moves ?? this.moves,
        marks: marks ?? this.marks,
        result: result == null ? this.result : result(),
        extra: extra ?? this.extra,
        played: played ?? this.played,
      );

  GameRecord withMove(String move) => copyWith(moves: [...moves, move]);

  GameRecord withMark(int i, MoveMark? mark) => copyWith(marks: [...marks]..[i] = mark);

  GameRecord withResult(Map<String, Object?>? result) => copyWith(result: () => result);

  GameRecord withExtra(String key, Object? value) => copyWith(extra: {...extra, key: value});

  /// The game before move [count] (its first [count] moves); no result
  /// unless that is the whole game.
  GameRecord upTo(int count) => count >= moves.length
      ? this
      : copyWith(moves: moves.sublist(0, count), marks: marks.sublist(0, count), result: () => null);

  /// What a job gets: the game, version, seed, rules, seats, deal and the
  /// first [upTo] moves (all by default). No marks, result or extra: a job
  /// replays the record and sees only what its seat may know.
  Map<String, Object?> jobJson({int? upTo}) => {
        'game': game,
        'version': version,
        'seed': seed,
        'rules': rules,
        'seats': [for (final seat in seats) seat.toJson()],
        'deal': deal,
        'moves': upTo == null || upTo >= moves.length ? moves : moves.sublist(0, upTo),
      };

  Map<String, Object?> toJson() => {
        ...jobJson(),
        if (marks.any((m) => m != null)) 'marks': [for (final m in marks) m?.toJson()],
        'result': ?result,
        if (extra.isNotEmpty) 'extra': extra,
        'played': played.millisecondsSinceEpoch,
      };

  /// The record saved by [toJson] (or a job's [jobJson]), or null if [json]
  /// is broken, of another game, or of another [version].
  static GameRecord? fromJson(Object? json, {required String game, required int version}) {
    try {
      if (json is! Map<String, Object?>) return null;
      if (json['game'] != game || json['version'] != version) return null;
      final moves = [for (final m in json['moves']! as List) m as String];
      final marks = json['marks'] as List?;
      if (marks != null && marks.length != moves.length) return null;
      return GameRecord(
        game: game,
        version: version,
        seed: json['seed']! as int,
        rules: Map.unmodifiable(json['rules']! as Map<String, Object?>),
        seats: List.unmodifiable([for (final s in json['seats']! as List) SeatSpec.fromJson(s)]),
        deal: Map.unmodifiable(json['deal']! as Map<String, Object?>),
        moves: moves,
        marks: [for (final m in marks ?? const []) m == null ? null : (MoveMark.fromJson(m) ?? (throw FormatException('mark')))],
        result: switch (json['result']) {
          null => null,
          final Map<String, Object?> result => result,
          _ => throw const FormatException('result'),
        },
        extra: Map.unmodifiable(json['extra'] as Map<String, Object?>? ?? const {}),
        played: DateTime.fromMillisecondsSinceEpoch(json['played'] as int? ?? 0),
      );
    } on Object {
      return null;
    }
  }
}
