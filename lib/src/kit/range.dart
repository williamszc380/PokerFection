/// What an opponent could hold, from the player's side of the table: for
/// each rank, the chance they hold at least 1, 2, 3 or 4 of it, and the
/// combinations they could make, each with its chance. A card game's range
/// job (JobKind.range) samples the hidden hands consistent with the play so
/// far, from the player's view only (never the cards shown by the Training
/// option), and tallies them with [OpponentRange.tally]. Pure Dart and plain
/// JSON, so it travels through Jobs like the coach's answers.
library;

import 'dart:math';

/// One rank's chances: [atLeast] holds P(at least 1), P(at least 2), ...,
/// up to the most copies a hand can have (4 in one deck, 1 for a joker).
class RankChance {
  const RankChance({required this.rank, required this.atLeast});

  /// The rank in the game's own notation ('3', 'T', 'A', '2', 'BJ'); the
  /// game's RangeLook turns it into a label.
  final String rank;
  final List<double> atLeast;

  /// The chance of holding at least [n] (1 to 4) of the rank; 0 past the
  /// most a hand can have.
  double chance(int n) => n >= 1 && n <= atLeast.length ? atLeast[n - 1] : 0;

  /// How many of the rank they hold on average.
  double get expected => atLeast.fold(0.0, (sum, p) => sum + p);

  Map<String, Object?> toJson() => {'r': rank, 'p': atLeast};

  static RankChance fromJson(Object? json) {
    final map = json! as Map;
    return RankChance(rank: map['r']! as String, atLeast: [for (final p in map['p']! as List) (p as num).toDouble()]);
  }
}

/// One kind of combination (pairs, straights, bombs...) with the chance an
/// opponent can make at least one, and its likeliest instances.
class ComboChance {
  const ComboChance({required this.kind, required this.chance, this.examples = const []});

  /// The kind in the game's notation ('pair', 'straight', 'bomb', 'rocket',
  /// 'twos:2'); the game's RangeLook names it.
  final String kind;

  /// The chance they can make at least one.
  final double chance;

  /// Up to [OpponentRange.maxExamples] instances, likeliest first: the move
  /// in the game's notation and the chance they hold it.
  final List<(String combo, double chance)> examples;

  Map<String, Object?> toJson() => {
    'k': kind,
    'p': chance,
    if (examples.isNotEmpty)
      'e': [
        for (final (combo, p) in examples) [combo, p],
      ],
  };

  static ComboChance fromJson(Object? json) {
    final map = json! as Map;
    return ComboChance(
      kind: map['k']! as String,
      chance: (map['p']! as num).toDouble(),
      examples: [for (final e in map['e'] as List? ?? const []) ((e as List)[0] as String, (e[1] as num).toDouble())],
    );
  }
}

/// An opponent's range at one point of the deal.
class OpponentRange {
  const OpponentRange({
    required this.seat,
    required this.cards,
    required this.samples,
    required this.ranks,
    required this.combos,
  });

  /// The opponent's seat.
  final int seat;

  /// How many cards they hold.
  final int cards;

  /// How many hidden deals the chances come from (1 when the hand is
  /// known: every chance is then 0 or 100%). Weighted deals count as many
  /// as they are worth (their effective number, see [tally]), not as many
  /// as were dealt: the sheet must not claim more than the chances rest on.
  final int samples;

  /// Every rank, in the game's order (lowest first).
  final List<RankChance> ranks;

  /// Every kind of combination the game names, in the game's order (kinds
  /// they can't make have chance 0, so the list keeps its shape).
  final List<ComboChance> combos;

  /// The most instances kept per kind.
  static const maxExamples = 3;

  /// Tallies sampled [hands] (each a list of the ranks the opponent holds in
  /// that sample, with repeats: ['3', '3', 'K']) into a range. [rankOrder]
  /// lists every rank, lowest first, with the most copies a hand can hold
  /// of it. [combosOf] names the combinations one sampled hand can make:
  /// each kind with its instances (the moves in the game's notation);
  /// [kinds] lists every kind in the order shown. Equal samples count once
  /// each: the sampler's weights are its repeats. Or [weights], one per
  /// hand: how likely each sampled hand is (Fight the Landlord weighs each
  /// guess by how well it explains the bids and plays); the chances are
  /// then weighted, and [samples] is the effective number of deals,
  /// (sum w)² / sum w², which is far fewer than the hands when a few
  /// guesses carry most of the weight.
  static OpponentRange tally({
    required int seat,
    required List<List<String>> hands,
    required List<(String rank, int copies)> rankOrder,
    required List<String> kinds,
    required Map<String, Set<String>> Function(List<String> hand) combosOf,
    List<double>? weights,
  }) {
    if (weights != null && weights.length != hands.length) {
      throw ArgumentError('${weights.length} weights for ${hands.length} hands');
    }
    var n = 0.0, squares = 0.0;
    final atLeast = {for (final (rank, copies) in rankOrder) rank: List<double>.filled(copies, 0)};
    final kindCount = {for (final kind in kinds) kind: 0.0};
    final instanceCount = {for (final kind in kinds) kind: <String, double>{}};
    for (final (i, hand) in hands.indexed) {
      final w = weights?[i] ?? 1.0;
      n += w;
      squares += w * w;
      final count = <String, int>{};
      for (final rank in hand) {
        count[rank] = (count[rank] ?? 0) + 1;
      }
      for (final MapEntry(key: rank, value: c) in count.entries) {
        final row = atLeast[rank];
        if (row == null) continue;
        for (var k = 0; k < c && k < row.length; k++) {
          row[k] += w;
        }
      }
      for (final MapEntry(key: kind, value: instances) in combosOf(hand).entries) {
        if (instances.isEmpty || !kindCount.containsKey(kind)) continue;
        kindCount[kind] = kindCount[kind]! + w;
        final seen = instanceCount[kind]!;
        for (final combo in instances) {
          seen[combo] = (seen[combo] ?? 0) + w;
        }
      }
    }
    double p(double count) => n <= 0 ? 0 : count / n;
    return OpponentRange(
      seat: seat,
      cards: hands.firstOrNull?.length ?? 0,
      samples: weights == null
          ? hands.length
          : squares <= 0
          ? 0
          : max(1, (n * n / squares).round()),
      ranks: [
        for (final (rank, _) in rankOrder) RankChance(rank: rank, atLeast: [for (final c in atLeast[rank]!) p(c)]),
      ],
      combos: [
        for (final kind in kinds)
          ComboChance(
            kind: kind,
            chance: p(kindCount[kind]!),
            examples: [
              for (final MapEntry(key: combo, value: c)
                  in (instanceCount[kind]!.entries.toList()
                        // Likeliest first; equal counts in name order, so the
                        // same samples always give the same list.
                        ..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key)))
                      .take(maxExamples))
                (combo, p(c)),
            ],
          ),
      ],
    );
  }

  /// The chances rounded to 4 decimals (a job's output repeats exactly on
  /// every platform, and stays small).
  Map<String, Object?> toJson() {
    double r(double p) => (p * 10000).round() / 10000;
    return {
      'seat': seat,
      'cards': cards,
      'samples': samples,
      'ranks': [
        for (final rank in ranks) RankChance(rank: rank.rank, atLeast: [for (final p in rank.atLeast) r(p)]).toJson(),
      ],
      'combos': [
        for (final combo in combos)
          ComboChance(
            kind: combo.kind,
            chance: r(combo.chance),
            examples: [for (final (c, p) in combo.examples) (c, r(p))],
          ).toJson(),
      ],
    };
  }

  static OpponentRange fromJson(Object? json) {
    final map = json! as Map;
    return OpponentRange(
      seat: map['seat']! as int,
      cards: map['cards']! as int,
      samples: map['samples']! as int,
      ranks: [for (final r in map['ranks']! as List) RankChance.fromJson(r)],
      combos: [for (final c in map['combos']! as List) ComboChance.fromJson(c)],
    );
  }
}
