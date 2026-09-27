import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../engine/positions.dart';

/// The spots the Preflop Charts show, with everyone else folding: first in,
/// facing an open, and facing a 3-bet after opening.
enum ChartSpot { open, vsOpen, vs3bet }

/// What GTO does with each starting hand in one spot.
class PreflopChart {
  PreflopChart(this._bytes) : assert(_bytes.length == 169 * 3);

  /// Per starting hand: how often it gets to the spot, then how often it
  /// checks or calls, and raises (percent).
  final Uint8List _bytes;

  /// How often [hand] gets here (0: never, not in the range).
  double reach(int hand) => _bytes[hand * 3] / 100;

  /// How often [hand] raises (any size, all-in included), calls and folds
  /// here, in whole percents adding up to 100.
  List<int> mix(int hand) {
    final call = _bytes[hand * 3 + 1], raise = _bytes[hand * 3 + 2];
    return [raise, call, max(0, 100 - raise - call)];
  }
}

/// Every chart, solved ahead of time by tool/make_charts.dart
/// (assets/preflop_charts.json).
class PreflopCharts {
  PreflopCharts.parse(String json)
      : _charts = ((jsonDecode(json) as Map<String, dynamic>)['charts'] as Map<String, dynamic>).cast();

  /// The stacks (in BB) there are charts for, smallest first (as in the game setup).
  static const stacks = [25, 50, 100];

  final Map<String, String> _charts;

  PreflopChart? chart({
    required int stackBb,
    required int players,
    required Position hero,
    required ChartSpot spot,
    Position? villain,
  }) {
    final key = [stackBb, players, hero.name, spot.name, if (villain != null) villain.name].join('/');
    final data = _charts[key];
    return data == null ? null : PreflopChart(base64Decode(data));
  }

  /// Whether [hero] can be in [spot] at a table of [players].
  static bool hasSpot(int players, Position hero, ChartSpot spot) =>
      villains(players, hero, spot).isNotEmpty || (spot == ChartSpot.open && hero != Position.bb);

  /// Who can make the raise [hero] faces in [spot], in the order of
  /// [allPositions]: players acting before them for an open, after them for
  /// a 3-bet. Empty for [ChartSpot.open].
  static List<Position> villains(int players, Position hero, ChartSpot spot) {
    final order = positionsForTable(players);
    final at = order.indexOf(hero);
    final List<Position> found = switch (spot) {
      ChartSpot.open => const [],
      ChartSpot.vsOpen => order.sublist(0, at),
      ChartSpot.vs3bet => hero == Position.bb ? const [] : order.sublist(at + 1),
    };
    return [for (final p in allPositions) if (found.contains(p)) p];
  }
}
