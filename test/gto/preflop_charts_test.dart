import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/engine/positions.dart';
import 'package:pokerfection/src/gto/hand_classes.dart';
import 'package:pokerfection/src/gto/preflop/preflop_charts.dart';

void main() {
  final charts = PreflopCharts.parse(File('assets/preflop_charts.json').readAsStringSync());

  PreflopChart chart(int players, Position hero, ChartSpot spot, [Position? villain]) =>
      charts.chart(stackBb: 100, players: players, hero: hero, spot: spot, villain: villain)!;

  /// The share of all starting hands that take the [actions] (0 raise, 1 call, 2 fold).
  double share(PreflopChart chart, List<int> actions) {
    var total = 0.0;
    for (var h = 0; h < handClassCount; h++) {
      final mix = chart.mix(h);
      for (final k in actions) {
        total += handClassCombos(h) * chart.reach(h) * mix[k] / 100;
      }
    }
    return total / 1326;
  }

  final aces = handClassIndex(12, 12, suited: false);
  final sevenDeuce = handClassIndex(5, 0, suited: false);

  test('every spot the screen offers has a chart', () {
    for (final stack in PreflopCharts.stacks) {
      for (var players = 2; players <= 8; players++) {
        for (final hero in positionsForTable(players)) {
          for (final spot in ChartSpot.values) {
            if (!PreflopCharts.hasSpot(players, hero, spot)) continue;
            final villains = spot == ChartSpot.open ? [null] : PreflopCharts.villains(players, hero, spot);
            for (final villain in villains) {
              final found = charts.chart(stackBb: stack, players: players, hero: hero, spot: spot, villain: villain);
              expect(found, isNotNull, reason: '$stack BB, $players players, ${hero.label} $spot ${villain?.label}');
            }
          }
        }
      }
    }
  });

  test('the spots each position can be in', () {
    expect(PreflopCharts.hasSpot(6, Position.bb, ChartSpot.open), isFalse);
    expect(PreflopCharts.hasSpot(6, Position.utg, ChartSpot.vsOpen), isFalse);
    expect(PreflopCharts.villains(6, Position.btn, ChartSpot.vsOpen), [Position.utg, Position.hj, Position.co]);
    expect(PreflopCharts.villains(6, Position.co, ChartSpot.vs3bet), [Position.sb, Position.bb, Position.btn]);
    expect(PreflopCharts.villains(2, Position.bb, ChartSpot.vsOpen), [Position.btn]);
  });

  test('the charts look like poker', () {
    // 6-max: UTG opens tight, the button much wider; aces always, 72o never.
    final utg = chart(6, Position.utg, ChartSpot.open);
    expect(share(utg, [0]), inInclusiveRange(0.10, 0.25));
    expect(share(chart(6, Position.btn, ChartSpot.open), [0]), greaterThan(share(utg, [0]) * 1.5));
    expect(utg.mix(aces)[0], 100);
    expect(utg.mix(sevenDeuce)[0], 0);
    // The big blind defends wider against the button than against UTG.
    expect(share(chart(6, Position.bb, ChartSpot.vsOpen, Position.btn), [0, 1]),
        greaterThan(share(chart(6, Position.bb, ChartSpot.vsOpen, Position.utg), [0, 1])));
    // Facing a 3-bet, only the hands that opened are in the range.
    final vs3bet = chart(6, Position.utg, ChartSpot.vs3bet, Position.btn);
    expect(vs3bet.reach(sevenDeuce), 0);
    expect(vs3bet.reach(aces), 1);
    expect(vs3bet.mix(aces)[2], 0, reason: 'aces never fold');
  });
}
