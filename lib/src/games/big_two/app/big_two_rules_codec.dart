/// Big Two's rules as the plain JSON a record and a job input carry, and
/// the setup's view of them: which preset they are, and the choices a
/// switch can take.
///
/// The JSON is the engine's own [BigTwoRules.toJson]; this file only wraps
/// it, so the app, the jobs and (later) the online host read rules one way.
library;

import '../big_two.dart';

/// Reading and writing rules, and matching them to a preset.
abstract final class BigTwoRulesCodec {
  /// [rules] as plain JSON (the engine's [BigTwoRules.toJson]).
  static Map<String, Object?> encode(BigTwoRules rules) => rules.toJson();

  /// The rules [encode] wrote. Throws [FormatException] on anything else,
  /// so a broken record is ignored rather than half read.
  static BigTwoRules decode(Object? json) {
    try {
      return BigTwoRules.fromJson((json! as Map).cast<String, Object?>());
    } on Object catch (error) {
      throw FormatException('Not Big Two rules: $error');
    }
  }

  /// The preset [rules] are exactly (for the same players and cards each),
  /// or null: Custom.
  static BigTwoPreset? presetOf(BigTwoRules rules) {
    for (final preset in BigTwoPreset.values) {
      if (BigTwoRules.preset(preset, players: rules.players, cardsEach: rules.cardsEach) == rules) return preset;
    }
    return null;
  }

  /// The straight orders the setup offers, in its order.
  static const straights = [StraightRule.pagat, StraightRule.hongKong, StraightRule.taiwan, StraightRule.twoHigh];

  /// Cards each a player count may deal (the first is its default).
  static List<int> cardsEachFor(int players) => switch (players) {
    4 => const [13],
    3 => const [17],
    _ => const [17, 13, 21],
  };

  /// [rules] with [players] seats, dealing that count's default.
  static BigTwoRules withPlayers(BigTwoRules rules, int players) =>
      rules.copyWith(players: players, cardsEach: cardsEachFor(players).first);
}
