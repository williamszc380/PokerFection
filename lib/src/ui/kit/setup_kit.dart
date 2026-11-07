import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';
import 'fit_text.dart';
import 'help.dart';
import 'l10n/kit_strings.dart';

/// A game's setup: its choices in two columns on a wide sideways screen
/// (one column otherwise), and Start fixed at the bottom. Enter starts.
class SetupPage extends StatelessWidget {
  const SetupPage({super.key, required this.title, required this.left, this.right = const [], required this.onStart});

  final String title;

  /// The choices: [left] first (the table), then [right] (the rules).
  final List<Widget> left;
  final List<Widget> right;
  final VoidCallback onStart;

  /// Two columns from this width (sideways).
  static const twoColumnsFrom = 760.0;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      appBar: AppBar(title: Text(title), toolbarHeight: size.height < 500 ? 44 : null),
      body: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.enter): onStart},
        child: Focus(
          autofocus: true,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      Widget column(List<Widget> children) => ListView(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            children: children,
                          );
                      if (constraints.maxWidth > twoColumnsFrom && right.isNotEmpty && size.width >= size.height) {
                        return Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1100),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [Expanded(child: column(left)), Expanded(child: column(right))],
                            ),
                          ),
                        );
                      }
                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 640),
                          child: column([...left, ...right]),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const ValueKey('start'),
                          onPressed: onStart,
                          icon: const Icon(Icons.play_arrow),
                          label: Text(s.start),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A labelled group of the setup, with an optional "?" after the label.
class SetupSection extends StatelessWidget {
  const SetupSection({super.key, required this.label, this.help, required this.child});

  final String label;
  final Widget? help;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Flexible(child: Text(label, style: theme.textTheme.titleSmall)), ?help]),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

/// One choice out of [values], as segments. Values the other choices rule
/// out are greyed out, never hidden. When the segments don't fit the width
/// they go on two lines (or more), each a row of segments, so every choice
/// stays in sight (never scrolled off to the side).
class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    this.enabled,
    required this.onChanged,
    this.shrinkWrap = false,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) label;

  /// Whether a value can be chosen now (null: all can).
  final bool Function(T value)? enabled;
  final ValueChanged<T> onChanged;

  /// As wide as its segments (true), so what follows it in a row (a "?")
  /// sits right after the last one; or as wide as it is given (false).
  final bool shrinkWrap;

  /// The gap between two lines of segments.
  static const lineGap = 6.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final picked = values.indexOf(selected);
        final lines = choiceLines(
          [for (final v in values) segmentWidth(context, label(v))],
          constraints.maxWidth,
        );
        Widget line(List<int> indices) => FittedBox(
              // A hair too wide (the widths are worked out ahead): a little
              // smaller, never cut.
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: SegmentedButton<int>(
                segments: [
                  for (final i in indices)
                    ButtonSegment(
                      value: i,
                      label: Text(label(values[i])),
                      enabled: enabled?.call(values[i]) ?? true,
                    ),
                ],
                selected: {if (indices.contains(picked)) picked},
                emptySelectionAllowed: true,
                showSelectedIcon: false,
                style: const ButtonStyle(mouseCursor: WidgetStateMouseCursor.clickable),
                onSelectionChanged: (choice) {
                  if (choice.isNotEmpty) onChanged(values[choice.single]);
                },
              ),
            );
        if (lines.length == 1) {
          return Align(alignment: Alignment.centerLeft, widthFactor: shrinkWrap ? 1 : null, child: line(lines.single));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (k, indices) in lines.indexed)
              Padding(padding: EdgeInsets.only(top: k == 0 ? 0 : lineGap), child: line(indices)),
          ],
        );
      },
    );
  }

  /// How wide a segment showing [text] is: its label in the theme's
  /// labelLarge, the segment's 12 on each side, and its divider.
  static double segmentWidth(BuildContext context, String text) =>
      textWidth(context, text, Theme.of(context).textTheme.labelLarge) + 24 + 2;
}

/// Splits segments of the given [widths] into the fewest lines that fit
/// [maxWidth], as even as can be (3 + 2 rather than 4 + 1): the indices of
/// each line's segments, in order. All the segments of a line are as wide
/// as its widest (as SegmentedButton draws them). One segment wider than
/// the whole width still gets a line of its own.
List<List<int>> choiceLines(List<double> widths, double maxWidth) {
  final n = widths.length;
  if (n == 0) return const [[]];
  bool fits(int from, int to) {
    var widest = 0.0;
    for (var i = from; i < to; i++) {
      widest = widths[i] > widest ? widths[i] : widest;
    }
    return widest * (to - from) + 2 <= maxWidth;
  }

  for (var count = 1; count < n; count++) {
    // [count] lines, the first ones a segment longer when they don't divide evenly.
    final lines = <List<int>>[];
    var from = 0;
    for (var k = 0; k < count; k++) {
      final size = (n - from + (count - k) - 1) ~/ (count - k);
      lines.add([for (var i = from; i < from + size; i++) i]);
      from += size;
    }
    if (lines.every((line) => fits(line.first, line.last + 1))) return lines;
  }
  return [for (var i = 0; i < n; i++) [i]];
}

/// An on/off choice, with an optional "?"; greyed out when not [enabled].
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.help,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final Widget? help;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      mouseCursor: WidgetStateMouseCursor.clickable,
      onTap: enabled ? () => onChanged(!value) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            // The label with its "?" on the left, the switch at the far right.
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(color: enabled ? null : Theme.of(context).disabledColor),
                    ),
                  ),
                  ?help,
                ],
              ),
            ),
            Switch(value: value, onChanged: enabled ? onChanged : null, mouseCursor: WidgetStateMouseCursor.clickable),
          ],
        ),
      ),
    );
  }
}

/// The bots' level: Easy / Medium / Hard, with "?".
class LevelRow extends StatelessWidget {
  const LevelRow({super.key, required this.value, required this.onChanged});

  final KitLevel value;
  final ValueChanged<KitLevel> onChanged;

  @override
  Widget build(BuildContext context) {
    final k = KitStrings.of(context);
    return SetupSection(
      label: k.level,
      help: TermsHelpButton(title: k.term(KitTerm.level), terms: [k.entry(KitTerm.level)]),
      child: ChoiceRow<KitLevel>(values: KitLevel.values, selected: value, label: k.kitLevel, onChanged: onChanged),
    );
  }
}

/// Training (grades and the coach) or Free Play, fixed for the game, with "?".
class ModeRow extends StatelessWidget {
  const ModeRow({super.key, required this.training, required this.onChanged});

  final bool training;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final k = KitStrings.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        children: [
          Flexible(
            child: ChoiceRow<bool>(
              values: const [true, false],
              selected: training,
              label: (t) => t ? k.trainingMode : s.freePlay,
              onChanged: onChanged,
              // The "?" right after Free Play, not at the column's far edge.
              shrinkWrap: true,
            ),
          ),
          TermsHelpButton(
            title: k.trainingMode,
            terms: [k.entry(KitTerm.training), k.entry(KitTerm.freePlay), k.entry(KitTerm.coach)],
          ),
        ],
      ),
    );
  }
}

/// A rules preset, plus Custom: Custom is selected by itself once a switch
/// no longer matches any preset ([selected] null), and greyed out until then.
class PresetRow<P> extends StatelessWidget {
  const PresetRow({
    super.key,
    required this.label,
    required this.presets,
    required this.selected,
    required this.name,
    required this.onChanged,
    this.help,
    this.enabled = true,
  });

  final String label;
  final List<P> presets;

  /// The preset the rules match, or null: Custom.
  final P? selected;
  final String Function(P preset) name;
  final ValueChanged<P> onChanged;
  final Widget? help;

  /// Off: every segment greyed out (a guest sees the host's rules), the
  /// "?" still there to read.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final k = KitStrings.of(context);
    final selected = this.selected;
    // Custom is the last segment (-1).
    final values = [for (var i = 0; i < presets.length; i++) i, -1];
    return SetupSection(
      label: label,
      help: help,
      child: ChoiceRow<int>(
        values: values,
        selected: selected == null ? -1 : presets.indexOf(selected),
        label: (i) => i < 0 ? k.custom : name(presets[i]),
        enabled: (i) => enabled && (i >= 0 || selected == null),
        onChanged: (i) {
          if (enabled && i >= 0) onChanged(presets[i]);
        },
      ),
    );
  }
}
