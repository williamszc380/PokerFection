import 'package:flutter/material.dart';

import '../gto/spot_strategy.dart';
import '../l10n/strings.dart';
import 'format.dart';

/// "You vs GTO" bars plus a table of every action's frequencies and EV.
/// Also used by the history screen.
class StrategyComparison extends StatelessWidget {
  const StrategyComparison({super.key, required this.spot, required this.mix, this.played});

  final SpotStrategy spot;
  final List<double> mix;

  /// Index of the action that was played, to mark it.
  final int? played;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = S.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: Colors.white60);
    var bestEv = double.negativeInfinity;
    for (final ev in spot.evs) {
      if (!ev.isNaN && ev > bestEv) bestEv = ev;
    }
    String percent(double f) => '${(f * 100).round()}%';
    final aggressive = [
      for (var i = 0; i < spot.actions.length; i++)
        if (spot.actions[i].kind == SpotActionKind.raise || spot.actions[i].kind == SpotActionKind.allIn) i,
    ];
    final firstAggressive = aggressive.isEmpty ? -1 : aggressive.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _labelled(context, s.columnYou, MixBar(actions: spot.actions, frequencies: mix)),
        const SizedBox(height: 4),
        _labelled(context, s.columnGto, MixBar(actions: spot.actions, frequencies: spot.frequencies)),
        const SizedBox(height: 6),
        Table(
          columnWidths: const {
            0: FlexColumnWidth(),
            1: FixedColumnWidth(60),
            2: FixedColumnWidth(48),
            3: FixedColumnWidth(72),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(children: [
              Text(spot.handName, style: muted),
              Text(s.columnYou, style: muted, textAlign: TextAlign.right),
              Text(s.columnGto, style: muted, textAlign: TextAlign.right),
              Text(s.columnEvLoss, style: muted, textAlign: TextAlign.right),
            ]),
            for (var i = 0; i < spot.actions.length; i++) ...[
              // The bets or raises as one group first (as when entering the mix),
              // then each size under it.
              if (i == firstAggressive) _groupRow(s, spot, mix, aggressive, percent),
              _actionRow(s, spot, i, mix, bestEv, percent, indent: aggressive.contains(i)),
            ],
          ],
        ),
      ],
    );
  }

  TableRow _actionRow(
    S s,
    SpotStrategy spot,
    int i,
    List<double> mix,
    double bestEv,
    String Function(double) percent, {
    bool indent = false,
  }) {
    final action = spot.actions[i];
    final dim = action.available ? null : Colors.white38;
    final ev = spot.evs[i];
    final best = !ev.isNaN && ev >= bestEv - 0.005;
    return TableRow(children: [
      Padding(
        padding: EdgeInsets.only(top: 2, bottom: 2, left: indent ? 14 : 0),
        child: Row(children: [
          ColorDot(color: action.available ? actionColor(spot.actions, i) : Colors.grey),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              spotActionLabel(s, action),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: dim, fontWeight: played == i ? FontWeight.w700 : null),
            ),
          ),
          // The action that was played.
          if (played == i) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.check, size: 14)),
        ]),
      ),
      Text(action.available ? percent(mix[i]) : '–', textAlign: TextAlign.right, style: TextStyle(color: dim)),
      Text(action.available ? percent(spot.frequencies[i]) : '–',
          textAlign: TextAlign.right, style: TextStyle(color: dim)),
      // How much this action gives up compared with the best one (0 for the best).
      Text(
        ev.isNaN ? '–' : (best ? 0.0 : bestEv - ev).toStringAsFixed(2),
        textAlign: TextAlign.right,
        style: TextStyle(
          color: best ? const Color(0xFF81C784) : dim,
          fontWeight: best ? FontWeight.w700 : FontWeight.normal,
        ),
      ),
    ]);
  }

  /// All raises together: how often you and GTO raise at all.
  TableRow _groupRow(S s, SpotStrategy spot, List<double> mix, List<int> group, String Function(double) percent) {
    final allowed = [for (final i in group) if (spot.actions[i].available) i];
    final color = allowed.isEmpty ? Colors.white38 : null;
    double total(List<double> frequencies) => allowed.fold(0.0, (sum, i) => sum + frequencies[i]);
    final style = TextStyle(color: color, fontWeight: FontWeight.w600);
    return TableRow(children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          ColorDot(color: allowed.isEmpty ? Colors.grey : actionColor(spot.actions, group.first)),
          const SizedBox(width: 6),
          Text(s.raiseAnySize, style: style),
        ]),
      ),
      Text(allowed.isEmpty ? '–' : percent(total(mix)), textAlign: TextAlign.right, style: style),
      Text(allowed.isEmpty ? '–' : percent(total(spot.frequencies)), textAlign: TextAlign.right, style: style),
      const SizedBox.shrink(),
    ]);
  }

  Widget _labelled(BuildContext context, String label, Widget bar) => Row(
        children: [
          SizedBox(width: 60, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
          Expanded(child: bar),
        ],
      );
}

/// Colors per action: blue for fold, green for check/call, warmer for bigger bets.
Color actionColor(List<SpotAction> actions, int index) {
  final action = actions[index];
  switch (action.kind) {
    case SpotActionKind.fold:
      return const Color(0xFF5C7FA3);
    case SpotActionKind.check || SpotActionKind.call:
      return const Color(0xFF43A047);
    case SpotActionKind.allIn:
      return const Color(0xFFB71C1C);
    case SpotActionKind.raise:
      final raises = [for (final a in actions) if (a.kind == SpotActionKind.raise) a];
      const shades = [
        Color(0xFFFFCA28),
        Color(0xFFFFA726),
        Color(0xFFFB8C00),
        Color(0xFFF4511E),
        Color(0xFFD84315),
      ];
      return shades[raises.indexOf(action).clamp(0, shades.length - 1)];
  }
}

/// A bar split into colored parts, one per action, sized by frequency.
class MixBar extends StatelessWidget {
  const MixBar({super.key, required this.actions, required this.frequencies});

  final List<SpotAction> actions;
  final List<double> frequencies;

  @override
  Widget build(BuildContext context) {
    final parts = [for (final f in frequencies) (f * 1000).round()];
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 12,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < actions.length; i++)
              if (parts[i] > 0) Expanded(flex: parts[i], child: ColoredBox(color: actionColor(actions, i))),
            if (parts.every((p) => p == 0)) const Expanded(child: ColoredBox(color: Colors.white12)),
          ],
        ),
      ),
    );
  }
}

class ColorDot extends StatelessWidget {
  const ColorDot({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class GradeChip extends StatelessWidget {
  const GradeChip({super.key, required this.grade});

  final DecisionGrade grade;

  @override
  Widget build(BuildContext context) {
    final color = gradeColor(grade);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Text(S.of(context).grade(grade), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
    );
  }
}

/// A grade's color, from green (best) to red (blunder).
Color gradeColor(DecisionGrade grade) => switch (grade) {
      DecisionGrade.best => const Color(0xFF2E7D32),
      DecisionGrade.good => const Color(0xFF558B2F),
      DecisionGrade.inaccuracy => const Color(0xFFF9A825),
      DecisionGrade.mistake => const Color(0xFFEF6C00),
      DecisionGrade.blunder => const Color(0xFFC62828),
    };
