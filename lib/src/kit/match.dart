/// A match: deals played one after another, each deal's points added to
/// running totals per seat, until a total reaches the target. Pure Dart,
/// like the rest of lib/src/kit, so a game's record and tests can use it
/// anywhere.
///
/// Big Two is played this way (penalty points for the cards left; once
/// someone reaches the target, often 100, the lowest total wins), and Fight
/// the Landlord's deals (the bid times the doublings, the landlord paid by
/// or paying each peasant) add up the same way. Each game gives its own
/// standard target and who wins ([MatchWinner]).
library;

import 'dart:math';

/// Who wins a match once a total reaches the target.
enum MatchWinner {
  /// The lowest total (penalty points: Big Two).
  lowest,

  /// The highest total (points won: Fight the Landlord).
  highest,
}

/// The setup's choice: play to [points] (null: no match, deals just go on),
/// raised with the number of players when [scale] is on.
class MatchTarget {
  const MatchTarget({this.points, this.scale = false});

  /// The target as chosen, for the game's usual number of players.
  final int? points;

  /// Raise the target with more players than usual (and lower it with
  /// fewer), so a bigger table doesn't end the match sooner: with more
  /// seats, someone reaches any total in fewer deals.
  final bool scale;

  /// The target at a table of [players], the game usually having
  /// [standardPlayers]: [points] itself, or scaled in proportion, rounded
  /// to a multiple of 5 (never below 5). Null: no match.
  int? forPlayers(int players, {required int standardPlayers}) {
    final points = this.points;
    if (points == null) return null;
    if (!scale || players == standardPlayers) return points;
    return max(5, (points * players / standardPlayers / 5).round() * 5);
  }

  MatchTarget copyWith({int? Function()? points, bool? scale}) =>
      MatchTarget(points: points == null ? this.points : points(), scale: scale ?? this.scale);

  /// For a setup's saved choices: `{'points': 100 | null, 'scale': false}`.
  Map<String, Object?> toJson() => {'points': points, 'scale': scale};

  /// What [toJson] wrote; [fallback] (the game's standard) for anything else.
  static MatchTarget fromJson(Object? json, {required MatchTarget fallback}) {
    if (json is! Map) return fallback;
    // A saved null is "No limit"; a missing or broken one is the standard.
    final points = switch (json['points']) {
      final int p when p > 0 => p,
      null when json.containsKey('points') => null,
      _ => fallback.points,
    };
    return MatchTarget(points: points, scale: json['scale'] is bool ? json['scale'] as bool : fallback.scale);
  }

  @override
  bool operator ==(Object other) => other is MatchTarget && other.points == points && other.scale == scale;

  @override
  int get hashCode => Object.hash(points, scale);

  @override
  String toString() => 'MatchTarget($points${scale ? ', scaled' : ''})';
}

/// A match so far: the target, each finished deal's points per seat, and
/// the totals. Never changed in place; kept in the record's extra under
/// [extraKey], so it is saved after every deal and carried from deal to deal.
class MatchScore {
  MatchScore({required this.target, required this.winner, required int seats, List<List<int>> deals = const []})
    : assert(target > 0),
      deals = List.unmodifiable([for (final d in deals) List<int>.unmodifiable(d)]),
      totals = List.unmodifiable([
        for (var s = 0; s < seats; s++) deals.fold<int>(0, (sum, d) => sum + (s < d.length ? d[s] : 0)),
      ]);

  /// Where the record's extra keeps it.
  static const extraKey = 'match';

  /// The total that ends the match (already scaled for the table).
  final int target;
  final MatchWinner winner;

  /// Each finished deal's points, seat by seat, in order.
  final List<List<int>> deals;

  /// The running totals, seat by seat.
  final List<int> totals;

  int get seats => totals.length;

  /// After a deal that gave [points] (one per seat).
  MatchScore add(List<int> points) {
    if (points.length != seats) throw ArgumentError('${points.length} points for $seats seats');
    return MatchScore(target: target, winner: winner, seats: seats, deals: [...deals, points]);
  }

  /// A total reached the target: the match is over.
  bool get isOver => totals.any((t) => t >= target);

  /// The seats with the best total (lowest or highest, as [winner] says):
  /// who leads, or who won once [isOver]. More than one: a tie.
  List<int> get leaders {
    if (deals.isEmpty) return const [];
    final best = winner == MatchWinner.lowest ? totals.reduce(min) : totals.reduce(max);
    return [
      for (var s = 0; s < seats; s++)
        if (totals[s] == best) s,
    ];
  }

  /// The seats from first to last place; equal totals keep seat order.
  List<int> get standings {
    final order = [for (var s = 0; s < seats; s++) s];
    order.sort((a, b) {
      final by = winner == MatchWinner.lowest ? totals[a].compareTo(totals[b]) : totals[b].compareTo(totals[a]);
      return by != 0 ? by : a.compareTo(b);
    });
    return order;
  }

  /// [seat]'s place, 1 for the leader; equal totals share a place.
  int placeOf(int seat) =>
      1 +
      [
        for (var s = 0; s < seats; s++)
          if (_better(totals[s], totals[seat])) s,
      ].length;

  bool _better(int a, int b) => winner == MatchWinner.lowest ? a < b : a > b;

  Map<String, Object?> toJson() => {'target': target, 'winner': winner.name, 'seats': seats, 'deals': deals};

  /// What [toJson] wrote, or null for anything else (an older record).
  static MatchScore? fromJson(Object? json) {
    try {
      if (json is! Map) return null;
      final target = json['target']! as int;
      if (target <= 0) return null;
      return MatchScore(
        target: target,
        winner: MatchWinner.values.byName(json['winner']! as String),
        seats: json['seats']! as int,
        deals: [
          for (final d in json['deals']! as List) [for (final p in d as List) p as int],
        ],
      );
    } on Object {
      return null;
    }
  }

  @override
  String toString() => 'MatchScore($totals to $target, ${deals.length} deals)';
}
