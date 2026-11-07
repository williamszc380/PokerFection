/// Basic strategy charts and house edges for any rule set.
///
/// A basic strategy chart is the table players learn: one play for each
/// hard total, soft total and pair against each dealer upcard, ignoring
/// which exact cards make the total. It is worked out the way Wizard of
/// Odds describes for its charts ("look at the initial 2-card hands only",
/// https://wizardofodds.com/games/blackjack/strategy/2-decks/):
///
/// 1. For each upcard, take a full shoe minus the upcard.
/// 2. For each two-card hand, compute the exact value of every play
///    ([EvCalculator.initialValues]), counting the dealer's blackjack.
/// 3. For each chart cell, average those values over the two-card hands
///    that make it, weighted by how often each is dealt, and pick the
///    best play. Pairs get their own row; hard totals use the non-pair
///    hands (a pair only when no other hand makes that total).
/// 4. Where the best play is a double or surrender, the next best of hit
///    and stand (or split) is the fallback when the play isn't allowed,
///    written as published charts do: "Dh" double else hit, "Ds" double
///    else stand, "Rh" / "Rs" / "Rp" surrender else hit / stand / split.
///
/// The house edge is then computed exactly (splits approximated as in
/// [EvCalculator]) both for perfect composition-dependent play with a
/// fresh shoe every round, and for a player who follows the chart.
library;

import 'dart:math' as math;

import 'action.dart';
import 'cards.dart';
import 'rules.dart';
import 'solver.dart';

/// A chart cell's code, as published charts write them.
enum ChartCode {
  /// Hit.
  hit('H'),

  /// Stand.
  stand('S'),

  /// Double if allowed, otherwise hit.
  doubleOrHit('Dh'),

  /// Double if allowed, otherwise stand.
  doubleOrStand('Ds'),

  /// Split.
  split('P'),

  /// Surrender if allowed, otherwise hit.
  surrenderOrHit('Rh'),

  /// Surrender if allowed, otherwise stand.
  surrenderOrStand('Rs'),

  /// Surrender if allowed, otherwise split.
  surrenderOrSplit('Rp');

  const ChartCode(this.label);

  /// The chart's short label.
  final String label;

  /// The code for a label ('H', 'S', 'Dh', 'Ds', 'P', 'Rh', 'Rs', 'Rp').
  static ChartCode parse(String label) => values.firstWhere((c) => c.label == label);
}

/// The two house edges of a rule set, as fractions of the initial bet
/// (0.005 = 0.5%).
class HouseEdge {
  /// See the fields.
  const HouseEdge({required this.optimal, required this.basicStrategy});

  /// With perfect play for every exact hand (composition-dependent) and a
  /// freshly shuffled shoe every round: Wizard of Odds' "optimal results".
  final double optimal;

  /// Following the basic strategy chart (total-dependent), fresh shoe
  /// every round: Wizard of Odds' "basic strategy with continuous
  /// shuffler". A cut card adds a little more (the "cut card effect").
  final double basicStrategy;

  @override
  String toString() =>
      'optimal ${(optimal * 100).toStringAsFixed(4)}%, basic strategy ${(basicStrategy * 100).toStringAsFixed(4)}%';
}

/// The basic strategy chart for one rule set.
///
/// Rows: hard 4-21, soft 12-21 and pairs (ace, 2..9, ten-value); columns:
/// the dealer's upcard by rank index (ace first, as in the engine; charts
/// usually print it last, see [toText]).
class BasicStrategyChart implements PlayPolicy {
  BasicStrategyChart._(this.rules, this._hard, this._soft, this._pairs, this.optimalEdge);

  /// The chart for [rules], computed on first use and then cached (it
  /// takes about a second natively).
  ///
  /// The cache lasts only as long as the isolate (or browser worker). The
  /// app's background jobs each start in a fresh one, so they never count
  /// on it: the chart is built once by its own job and handed to the coach
  /// and the bots as JSON ([toJson], [BasicStrategyChart.fromJson]).
  ///
  /// The chart's [rules] are always the ones asked for, even when the
  /// cached chart was built for other rules with the same strategy (another
  /// penetration, say), so the same rules always give the same chart.
  factory BasicStrategyChart.forRules(BlackjackRules rules) {
    final chart = _cache.putIfAbsent(rules.strategyKey, () => _build(rules));
    return chart.rules == rules ? chart : BasicStrategyChart._(rules, chart._hard, chart._soft, chart._pairs, chart.optimalEdge);
  }

  static final Map<String, BasicStrategyChart> _cache = {};

  /// The chart as plain JSON, about half a kilobyte: the rules it was
  /// worked out for, the optimal house edge, and each row as one string of
  /// ten one-letter codes ([_letters]), upcards ace first as in the engine.
  /// Rows: `hard` 4-21, `soft` 12-21, `pairs` A, 2..9, T.
  Map<String, Object?> toJson() {
    String row(List<ChartCode> codes) => [for (final c in codes) _letters[c.index]].join();
    return {
      'rules': rules.toJson(),
      'edge': optimalEdge,
      'hard': [for (var t = 4; t <= 21; t++) row(_hard[t])],
      'soft': [for (var t = 12; t <= 21; t++) row(_soft[t])],
      'pairs': [for (final codes in _pairs) row(codes)],
    };
  }

  /// The chart written by [toJson]. Throws a [FormatException] if [json]
  /// isn't one (wrong row counts, unknown letters).
  factory BasicStrategyChart.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('chart: not a map');
    final rules = BlackjackRules.fromJson(json['rules']);
    final edge = json['edge'];
    if (edge is! num) throw const FormatException('chart: no edge');
    List<List<ChartCode>> rows(String key, int count) {
      final list = json[key];
      if (list is! List || list.length != count) throw FormatException('chart: bad $key');
      return [
        for (final r in list)
          if (r is String && r.length == rankCount)
            [
              for (final ch in r.split(''))
                if (_letters.indexOf(ch) case final i when i >= 0) ChartCode.values[i] else throw FormatException('chart: bad code $ch'),
            ]
          else
            throw FormatException('chart: bad row in $key'),
      ];
    }

    // Unused rows (hard below 4, soft below 12) keep the defaults _build uses.
    final hard = [for (var t = 0; t < 4; t++) List.filled(rankCount, ChartCode.hit), ...rows('hard', 18)];
    final soft = [for (var t = 0; t < 12; t++) List.filled(rankCount, ChartCode.stand), ...rows('soft', 10)];
    return BasicStrategyChart._(rules, hard, soft, rows('pairs', rankCount), edge.toDouble());
  }

  /// One letter per [ChartCode], in its order (H S D d P R r p): Dh is "D"
  /// and Ds "d", surrender else hit / stand / split "R" "r" "p". Only for
  /// the JSON; [ChartCode.label] is what people read.
  static const _letters = ['H', 'S', 'D', 'd', 'P', 'R', 'r', 'p'];

  /// The rules it was worked out for.
  final BlackjackRules rules;

  // [total][upcard] codes; hard 0..21 (rows below 4 unused), soft 0..21
  // (rows below 12 unused), pairs by rank index.
  final List<List<ChartCode>> _hard;
  final List<List<ChartCode>> _soft;
  final List<List<ChartCode>> _pairs;

  /// The house edge with perfect play, found while building the chart.
  final double optimalEdge;

  /// The code for hard [total] (4-21) against [upcard] (rank index).
  ChartCode hard(int total, int upcard) => _hard[total.clamp(4, 21)][upcard];

  /// The code for soft [total] (12-21) against [upcard].
  ChartCode soft(int total, int upcard) => _soft[total.clamp(12, 21)][upcard];

  /// The code for a pair of rank [rank] against [upcard]: [ChartCode.split]
  /// or how to play it when not splitting.
  ChartCode pair(int rank, int upcard) => _pairs[rank][upcard];

  /// The play for a hand of [total] with [cardCount] cards against
  /// [upcard], where [pairRank] is the rank of a two-card pair (-1 if
  /// not), and the flags say what the rules allow for this hand now.
  BlackjackAction decide({
    required HandTotal total,
    required int cardCount,
    required int upcard,
    int pairRank = -1,
    bool canDouble = false,
    bool canSplit = false,
    bool canSurrender = false,
  }) {
    if (total.value >= 21) return BlackjackAction.stand;
    if (pairRank >= 0 && canSplit) {
      final code = pair(pairRank, upcard);
      if (code == ChartCode.split) return BlackjackAction.split;
      if (code == ChartCode.surrenderOrSplit) return canSurrender ? BlackjackAction.surrender : BlackjackAction.split;
      return _apply(code, canDouble, canSurrender);
    }
    var code = total.soft ? soft(total.value, upcard) : hard(total.value, upcard);
    if (code == ChartCode.split || code == ChartCode.surrenderOrSplit) code = ChartCode.hit;
    return _apply(code, canDouble, canSurrender);
  }

  static BlackjackAction _apply(ChartCode code, bool canDouble, bool canSurrender) => switch (code) {
    ChartCode.hit => BlackjackAction.hit,
    ChartCode.stand => BlackjackAction.stand,
    ChartCode.doubleOrHit => canDouble ? BlackjackAction.double : BlackjackAction.hit,
    ChartCode.doubleOrStand => canDouble ? BlackjackAction.double : BlackjackAction.stand,
    ChartCode.surrenderOrHit => canSurrender ? BlackjackAction.surrender : BlackjackAction.hit,
    ChartCode.surrenderOrStand => canSurrender ? BlackjackAction.surrender : BlackjackAction.stand,
    ChartCode.split || ChartCode.surrenderOrSplit => BlackjackAction.split,
  };

  /// [PlayPolicy]: the chart's play among the [allowed] actions.
  @override
  BlackjackAction choose(HandTotal total, int cardCount, int pairRank, int upcard, int allowed) {
    final a = decide(
      total: total,
      cardCount: cardCount,
      upcard: upcard,
      pairRank: pairRank,
      canDouble: allowed & BlackjackAction.double.bit != 0,
      canSplit: allowed & BlackjackAction.split.bit != 0,
      canSurrender: allowed & BlackjackAction.surrender.bit != 0,
    );
    return allowed & a.bit != 0 ? a : BlackjackAction.stand;
  }

  /// The chart as text, rows "hard 4".."hard 21", "soft 12".."soft 21",
  /// "A,A", "2,2".."T,T", columns 2..T then A as charts print them.
  String toText() {
    final b = StringBuffer();
    const cols = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0];
    String row(String name, List<ChartCode> codes) =>
        '${name.padRight(8)} ${[for (final c in cols) codes[c].label.padRight(2)].join(' ')}\n';
    b.write('${''.padRight(8)} ${[for (final c in cols) rankName(c).padRight(2)].join(' ')}\n');
    for (var t = 4; t <= 21; t++) {
      b.write(row('hard $t', _hard[t]));
    }
    for (var t = 12; t <= 21; t++) {
      b.write(row('soft $t', _soft[t]));
    }
    for (final r in cols) {
      b.write(row('${rankName(r)},${rankName(r)}', _pairs[r]));
    }
    return b.toString();
  }

  static BasicStrategyChart _build(BlackjackRules rules) {
    final full = Composition.decks(rules.decks);
    final n = full.total;
    final hard = List.generate(22, (_) => List.filled(rankCount, ChartCode.hit));
    final soft = List.generate(22, (_) => List.filled(rankCount, ChartCode.stand));
    final pairs = List.generate(rankCount, (_) => List.filled(rankCount, ChartCode.hit));
    var edge = 0.0;
    for (var u = 0; u < rankCount; u++) {
      final root = _withoutRank(full, u);
      final calc = EvCalculator(rules, root, u);
      final m = root.total;
      // Weighted sums of each play's value per cell.
      final hardSum = List.generate(22, (_) => List.filled(5, 0.0));
      final hardPairSum = List.generate(22, (_) => List.filled(5, 0.0));
      final softSum = List.generate(22, (_) => List.filled(5, 0.0));
      final hardOk = List.filled(22, false), hardPairOk = List.filled(22, false), softOk = List.filled(22, false);
      for (var a = 0; a < rankCount; a++) {
        for (var c = a; c < rankCount; c++) {
          final w = a == c ? root[a] * (root[a] - 1) / (m * (m - 1)) : 2 * root[a] * root[c] / (m * (m - 1));
          if (w == 0) continue;
          final v = calc.initialValues(a, c);
          var best = double.negativeInfinity;
          for (final x in v) {
            if (!x.isNaN) best = math.max(best, x);
          }
          edge -= full[u] / n * w * best;
          final hasAce = a == aceIndex;
          final pts = rankPoints(a) + rankPoints(c);
          if (a == c) {
            // The pair row keeps the split; the total row drops it.
            pairs[a][u] = _code(v, withSplit: true);
            final noSplit = List<double>.of(v)..[3] = double.nan;
            if (hasAce) {
              _add(softSum[12], noSplit, w);
              softOk[12] = true;
            } else {
              _add(hardPairSum[pts], noSplit, w);
              hardPairOk[pts] = true;
            }
          } else if (hasAce) {
            if (pts + 10 == 21) continue; // blackjack
            _add(softSum[pts + 10], v, w);
            softOk[pts + 10] = true;
          } else {
            _add(hardSum[pts], v, w);
            hardOk[pts] = true;
          }
        }
      }
      for (var t = 4; t <= 21; t++) {
        if (hardOk[t]) {
          hard[t][u] = _code(hardSum[t], withSplit: false);
        } else if (hardPairOk[t]) {
          hard[t][u] = _code(hardPairSum[t], withSplit: false);
        } else {
          hard[t][u] = t >= 17 ? ChartCode.stand : ChartCode.hit;
        }
      }
      for (var t = 12; t <= 21; t++) {
        soft[t][u] = softOk[t] ? _code(softSum[t], withSplit: false) : ChartCode.stand;
      }
    }
    return BasicStrategyChart._(rules, hard, soft, pairs, edge);
  }

  static void _add(List<double> sum, List<double> v, double w) {
    for (var i = 0; i < 5; i++) {
      sum[i] += v[i].isNaN ? double.nan : w * v[i];
    }
  }

  /// The chart code for a cell whose play values (in [playActions] order,
  /// NaN = not allowed) are [v].
  static ChartCode _code(List<double> v, {required bool withSplit}) {
    double at(BlackjackAction a) => v[a.index];
    bool ok(BlackjackAction a) => !at(a).isNaN && (a != BlackjackAction.split || withSplit);
    BlackjackAction bestOf(Iterable<BlackjackAction> options) {
      BlackjackAction? best;
      for (final a in options) {
        if (!ok(a)) continue;
        if (best == null || at(a) > at(best)) best = a;
      }
      return best ?? BlackjackAction.stand;
    }

    const basic = [BlackjackAction.stand, BlackjackAction.hit];
    final best = bestOf(playActions);
    switch (best) {
      case BlackjackAction.double:
        return bestOf(basic) == BlackjackAction.hit ? ChartCode.doubleOrHit : ChartCode.doubleOrStand;
      case BlackjackAction.surrender:
        final fallback = bestOf([...basic, BlackjackAction.split]);
        return switch (fallback) {
          BlackjackAction.hit => ChartCode.surrenderOrHit,
          BlackjackAction.split => ChartCode.surrenderOrSplit,
          _ => ChartCode.surrenderOrStand,
        };
      case BlackjackAction.split:
        return ChartCode.split;
      case BlackjackAction.hit:
        return ChartCode.hit;
      default:
        return ChartCode.stand;
    }
  }

  /// The house edge (fraction of the initial bet) for a player who follows
  /// this chart exactly, with a freshly shuffled shoe every round, never
  /// taking insurance. Takes about as long as building the chart.
  double basicStrategyEdge() => _basicEdge ??= _edgeFollowing(rules, this);

  double? _basicEdge;

  /// Both house edges.
  HouseEdge get houseEdge => HouseEdge(optimal: optimalEdge, basicStrategy: basicStrategyEdge());

  static Composition _withoutRank(Composition c, int rank) =>
      Composition([for (var r = 0; r < rankCount; r++) c[r] - (r == rank ? 1 : 0)]);
}

double _edgeFollowing(BlackjackRules rules, PlayPolicy policy) {
  final full = Composition.decks(rules.decks);
  final n = full.total;
  var ev = 0.0;
  for (var u = 0; u < rankCount; u++) {
    final root = BasicStrategyChart._withoutRank(full, u);
    final calc = EvCalculator(rules, root, u, policy: policy);
    final m = root.total;
    for (var a = 0; a < rankCount; a++) {
      for (var c = a; c < rankCount; c++) {
        final w = a == c ? root[a] * (root[a] - 1) / (m * (m - 1)) : 2 * root[a] * root[c] / (m * (m - 1));
        if (w == 0) continue;
        final v = calc.initialValues(a, c);
        final spot = HandSpot(
          hard: rankPoints(a) + rankPoints(c),
          hasAce: a == aceIndex,
          cardCount: 2,
          pairRank: a == c ? a : -1,
        );
        var allowed = 0;
        for (var i = 0; i < 5; i++) {
          if (!v[i].isNaN) allowed |= playActions[i].bit;
        }
        final choice = spot.isBlackjack
            ? BlackjackAction.stand
            : policy.choose(spot.total, 2, spot.pairRank, u, allowed);
        ev += full[u] / n * w * v[choice.index];
      }
    }
  }
  return -ev;
}

/// The house edge (fraction of the initial bet) for a player following
/// any [policy] (a bot, for example) under [rules], computed exactly with
/// a fresh shoe every round and no insurance.
double houseEdgeFollowing(BlackjackRules rules, PlayPolicy policy) => _edgeFollowing(rules, policy);
