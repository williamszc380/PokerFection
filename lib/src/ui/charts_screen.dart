import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/positions.dart';
import '../gto/hand_classes.dart';
import '../gto/preflop/preflop_charts.dart';
import '../l10n/strings.dart';
import 'glossary.dart';
import 'strategy_panel.dart';

/// Raise, call and fold: the colors those choices have at the table.
const chartColors = [Color(0xFFFFCA28), Color(0xFF43A047), Color(0xFF5C7FA3)];

/// Preflop Charts: what GTO does with every starting hand in the common
/// spots before the flop, for 2 to 8 players and a few stacks. The charts
/// are solved ahead of time (tool/make_charts.dart), so they show at once.
class ChartsScreen extends StatefulWidget {
  const ChartsScreen({super.key});

  @override
  State<ChartsScreen> createState() => _ChartsScreenState();
}

class _ChartsScreenState extends State<ChartsScreen> {
  static Future<PreflopCharts>? _charts;

  int _players = 6;
  int _stack = 100;
  Position _hero = Position.btn;
  ChartSpot _spot = ChartSpot.open;
  Position? _villain;

  /// The starting hand whose numbers are shown (tapped on the grid).
  int? _hand;

  @override
  void initState() {
    super.initState();
    _charts ??= rootBundle.load('assets/preflop_charts.json').then(
        (data) => PreflopCharts.parse(utf8.decode(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes))));
  }

  /// Keeps the choices possible after one of them changed: the position at
  /// this table, a spot it can be in, and who raised.
  void _fix() {
    final order = positionsForTable(_players);
    if (!order.contains(_hero)) _hero = Position.btn;
    if (!PreflopCharts.hasSpot(_players, _hero, _spot)) {
      _spot = ChartSpot.values.firstWhere((spot) => PreflopCharts.hasSpot(_players, _hero, spot));
    }
    if (_spot == ChartSpot.open) {
      _villain = null;
    } else if (!PreflopCharts.villains(_players, _hero, _spot).contains(_villain)) {
      // The nearest raiser: the last to act before, or the first after.
      final at = order.indexOf(_hero);
      _villain = order[_spot == ChartSpot.vsOpen ? at - 1 : at + 1];
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.preflopCharts),
        actions: const [
          HelpButton(
            section: GlossarySection.strategy,
            terms: [GlossaryTerm.charts, GlossaryTerm.open, GlossaryTerm.threeBet, GlossaryTerm.rangeGrid],
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<PreflopCharts>(
          future: _charts,
          builder: (context, snapshot) {
            final charts = snapshot.data;
            if (charts == null) return const Center(child: CircularProgressIndicator());
            final chart = charts.chart(
              stackBb: _stack,
              players: _players,
              hero: _hero,
              spot: _spot,
              villain: _villain,
            );
            return _layout(context, chart);
          },
        ),
      ),
    );
  }

  Widget _layout(BuildContext context, PreflopChart? chart) {
    final grid = chart == null
        ? const SizedBox.shrink()
        : ChartGrid(chart: chart, selected: _hand, onSelect: (hand) => setState(() => _hand = hand));
    final side = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_choices(context), if (chart != null) _key(context, chart)],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Sideways: the grid as big as the height allows, the choices beside it.
        if (constraints.maxWidth >= constraints.maxHeight) {
          final size = min(constraints.maxHeight - 16, constraints.maxWidth * 0.6);
          return Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox.square(dimension: size, child: grid),
                const SizedBox(width: 16),
                Expanded(child: SingleChildScrollView(child: side)),
              ],
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [side, const SizedBox(height: 12), AspectRatio(aspectRatio: 1, child: grid)],
          ),
        );
      },
    );
  }

  Widget _choices(BuildContext context) {
    final s = S.of(context);
    final muted = Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.white60);
    Widget line(String title, List<Widget> chips, {Widget? help}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [Text(title, style: muted), ?help]),
              if (help == null) const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 6, children: chips),
            ],
          ),
        );
    Widget chip<T>(String label, T value, T current, void Function(T) set, {bool enabled = true}) => ChoiceChip(
          label: Text(label),
          selected: value == current,
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onSelected: enabled
              ? (_) => setState(() {
                    set(value);
                    _fix();
                  })
              : null,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        line(s.players, [for (var n = 2; n <= 8; n++) chip('$n', n, _players, (v) => _players = v)]),
        line(s.stack, [for (final bb in PreflopCharts.stacks) chip('$bb BB', bb, _stack, (v) => _stack = v)]),
        line(
          s.position,
          [
            for (final p in allPositions)
              chip(p.label, p, _hero, (v) => _hero = v, enabled: positionsForTable(_players).contains(p)),
          ],
          help: const HelpButton(section: GlossarySection.positions),
        ),
        line(
          s.spot,
          [
            for (final spot in ChartSpot.values)
              chip(s.chartSpot(spot), spot, _spot, (v) => _spot = v,
                  enabled: PreflopCharts.hasSpot(_players, _hero, spot)),
          ],
          help: const HelpButton(section: GlossarySection.actions, terms: [GlossaryTerm.open, GlossaryTerm.threeBet]),
        ),
        if (_spot != ChartSpot.open)
          line(s.chartVillain(_spot), [
            for (final p in allPositions)
              chip<Position?>(p.label, p, _villain, (v) => _villain = v,
                  enabled: PreflopCharts.villains(_players, _hero, _spot).contains(p)),
          ]),
      ],
    );
  }

  /// The colors, how the whole range splits between them, and the tapped
  /// hand's numbers.
  Widget _key(BuildContext context, PreflopChart chart) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final names = [s.raiseAnySize, s.callWord, s.fold];
    var inRange = 0.0;
    final totals = [0.0, 0.0, 0.0];
    for (var h = 0; h < handClassCount; h++) {
      final combos = handClassCombos(h) * chart.reach(h);
      inRange += combos;
      final mix = chart.mix(h);
      for (var k = 0; k < 3; k++) {
        totals[k] += combos * mix[k] / 100;
      }
    }
    Widget part(int k, String value) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [ColorDot(color: chartColors[k]), const SizedBox(width: 6), Text('${names[k]} $value')],
        );
    final hand = _hand;
    final reach = hand == null ? 0.0 : chart.reach(hand);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            for (var k = 0; k < 3; k++) part(k, inRange == 0 ? '–' : '${(totals[k] / inRange * 100).round()}%'),
          ],
        ),
        if (inRange < 1325)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(s.inRange((inRange / 1326 * 100).round()), style: theme.textTheme.bodySmall),
          ),
        if (hand != null) ...[
          const SizedBox(height: 10),
          Text(handClassName(hand), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          if (reach == 0)
            Text(s.inRange(0), style: theme.textTheme.bodySmall)
          else ...[
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                for (var k = 0; k < 3; k++)
                  if (chart.mix(hand)[k] > 0) part(k, '${chart.mix(hand)[k]}%'),
              ],
            ),
            if (reach < 1)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(s.inRange((reach * 100).round()), style: theme.textTheme.bodySmall),
              ),
          ],
        ],
      ],
    );
  }
}

/// The 169 starting hands on a 13 × 13 grid (pairs on the diagonal, suited
/// above it), each split side by side into raise, call and fold by how often
/// GTO does them, over as much of its width as how often the hand gets
/// there (the rest stays dark).
class ChartGrid extends StatefulWidget {
  const ChartGrid({super.key, required this.chart, this.selected, this.onSelect});

  final PreflopChart chart;

  /// The hand outlined in white.
  final int? selected;
  final ValueChanged<int>? onSelect;

  @override
  State<ChartGrid> createState() => _ChartGridState();
}

class _ChartGridState extends State<ChartGrid> {
  int? _hovered;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = min(constraints.maxWidth, constraints.maxHeight);
        return Center(
          child: SizedBox.square(
            dimension: side,
            child: Column(
              children: [
                for (var row = 0; row < 13; row++)
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var col = 0; col < 13; col++) Expanded(child: _cell(row, col, side / 13)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _cell(int row, int col, double size) {
    final rowRank = 12 - row, colRank = 12 - col;
    final hand = row == col
        ? handClassIndex(rowRank, rowRank, suited: false)
        : handClassIndex(rowRank, colRank, suited: col > row);
    final chart = widget.chart;
    final reach = chart.reach(hand);
    final mix = chart.mix(hand);
    final selected = hand == widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = hand),
      onExit: (_) => setState(() => _hovered = _hovered == hand ? null : _hovered),
      child: GestureDetector(
        onTap: () => widget.onSelect?.call(hand),
        child: Container(
          margin: const EdgeInsets.all(0.5),
          decoration: BoxDecoration(
            color: const Color(0xFF20262A),
            border: selected || hand == _hovered
                ? Border.all(
                    color: selected ? Colors.white : Colors.white54,
                    width: selected ? max(2.5, size * 0.08) : max(1.5, size * 0.05),
                  )
                : null,
            boxShadow: selected ? const [BoxShadow(color: Colors.black87, blurRadius: 6)] : null,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (reach > 0)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: reach,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var k = 0; k < 3; k++)
                          if (mix[k] > 0) Expanded(flex: mix[k], child: ColoredBox(color: chartColors[k])),
                      ],
                    ),
                  ),
                ),
              Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.all(1),
                    child: Text(
                      handClassName(hand),
                      style: TextStyle(
                        fontSize: size * 0.3,
                        fontWeight: FontWeight.w700,
                        color: reach > 0 ? Colors.white : Colors.white38,
                        shadows: reach > 0 ? const [Shadow(color: Colors.black87, blurRadius: 3)] : null,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
