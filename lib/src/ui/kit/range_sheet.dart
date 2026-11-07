import 'dart:math';

import 'package:flutter/material.dart';

import '../../kit/range.dart';
import 'fit_text.dart';
import 'help.dart';
import 'kit_sheet.dart';
import 'l10n/game_strings.dart';
import 'l10n/kit_strings.dart';
import 'turn_controller.dart';

/// How a game names the ranks and combinations of an opponent's range.
class RangeLook {
  const RangeLook({
    required this.rankLabel,
    required this.comboLabel,
    this.comboText,
    this.comboWidget,
    this.terms = const [],
  });

  /// A rank as the cards show it: 'T' → "10", 'BJ' → "Big joker"'s short
  /// form. Kept short: a column is about 30 px wide on a sideways phone.
  final String Function(String rank) rankLabel;

  /// A kind of combination: 'pair' → "Pairs" ("Parejas", "对子").
  final String Function(String kind) comboLabel;

  /// One combination as text ("7-7", "3-4-5-6-7"); null: as the job gave it.
  final String Function(String combo)? comboText;

  /// One combination drawn (mini cards), when the game has a drawing; it is
  /// scaled down to the row's height.
  final Widget Function(BuildContext context, String combo)? comboWidget;

  /// More "?" entries after the kit's (the game's combination names).
  final List<GameTerm> terms;
}

/// Opens [seat]'s range over the screen (Training only: nothing happens
/// where TurnController.canShowRange says no). The sheet starts the range
/// job and follows the game: after each move it works the range out again.
Future<void> showRangeSheet(
  BuildContext context, {
  required TurnController controller,
  required int seat,
  required RangeLook look,
}) {
  if (!controller.canShowRange(seat)) return Future.value();
  return KitSheet.open(context, RangeSheet(controller: controller, seat: seat, look: look));
}

/// [name] as the start of the sheet's title: a seat named for the middle
/// of a sentence ("la banca", written for "Gana la banca") gets its capital.
String rangeHeadingName(String name) => name.isEmpty ? name : name.substring(0, 1).toUpperCase() + name.substring(1);

/// An opponent's range: the chance they hold at least 1, 2, 3 or 4 of each
/// rank (a grid, shaded by chance), then each kind of combination with the
/// chance they can make one and its likeliest instances.
class RangeSheet extends StatefulWidget {
  const RangeSheet({super.key, required this.controller, required this.seat, required this.look});

  final TurnController controller;
  final int seat;
  final RangeLook look;

  @override
  State<RangeSheet> createState() => _RangeSheetState();
}

class _RangeSheetState extends State<RangeSheet> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    widget.controller.askRange(widget.seat);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  /// A move was made (or the range came): ask for the range of the
  /// position now (nothing new when it is already there or on its way).
  void _changed() {
    if (!mounted) return;
    widget.controller.askRange(widget.seat);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final k = KitStrings.of(context);
    final c = widget.controller;
    final range = c.rangeOf(widget.seat);
    final name = rangeHeadingName(c.seatName(widget.seat));
    final title = [k.term(KitTerm.range), if (range == null) name else k.rangeTitle(name, range.cards)].join(' · ');
    return KitSheet(
      key: const ValueKey('range sheet'),
      title: title,
      help: TermsHelpButton(title: k.term(KitTerm.range), terms: [k.entry(KitTerm.range), ...widget.look.terms]),
      child: range == null
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: c.rangeFailed(widget.seat)
                  ? Text(k.rangeFailed, key: const ValueKey('range failed'))
                  // Nothing is on its way once the game has no range to
                  // work out (Big Two's deal ended behind the sheet): say
                  // so, rather than spin for ever.
                  : !c.canShowRange(widget.seat)
                  ? Text(k.rangeNone, key: const ValueKey('range none'))
                  : Row(
                      children: [
                        const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 12),
                        Flexible(child: Text(k.rangeWorking)),
                      ],
                    ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _heading(context, k.rangeRanks),
                RankGrid(range: range, look: widget.look),
                const SizedBox(height: 10),
                _heading(context, k.rangeCombos),
                for (final combo in range.combos) ComboRow(combo: combo, look: widget.look),
                const SizedBox(height: 6),
                Text(k.rangeSamples(range.samples), style: const TextStyle(fontSize: 11, color: Colors.white54)),
              ],
            ),
    );
  }

  static Widget _heading(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.white70)),
  );
}

/// The ranks in columns (lowest first) and rows "1+", "2+", "3+", "4": each
/// cell the chance of holding at least that many of the rank, shaded by it.
/// Cells a rank can't have (a second joker) stay empty. As wide as it is
/// given; with too little room (about 20 px a column) it scrolls sideways.
class RankGrid extends StatelessWidget {
  const RankGrid({super.key, required this.range, required this.look});

  final OpponentRange range;
  final RangeLook look;

  /// The narrowest a column gets before the grid scrolls.
  static const minColumn = 20.0;

  @override
  Widget build(BuildContext context) {
    final ranks = range.ranks;
    final rows = min(4, ranks.fold(0, (most, r) => max(most, r.atLeast.length)));
    final primary = Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = ranks.length + 1;
        final width = max(constraints.maxWidth, minColumn * columns);
        final cell = width / columns;
        final height = cell.clamp(18.0, 26.0);
        Widget box(String text, {Color? fill, TextStyle? style, Key? key}) => Container(
          key: key,
          width: cell,
          height: height,
          alignment: Alignment.center,
          margin: EdgeInsets.zero,
          decoration: BoxDecoration(
            color: fill,
            border: Border.all(color: Colors.white10, width: 0.5),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(text, maxLines: 1, style: style),
            ),
          ),
        );
        final grid = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                box('%', style: const TextStyle(fontSize: 11, color: Colors.white54)),
                for (final r in ranks)
                  box(look.rankLabel(r.rank), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ],
            ),
            for (var n = 1; n <= rows; n++)
              Row(
                children: [
                  box(n < rows || n < 4 ? '$n+' : '$n', style: const TextStyle(fontSize: 11, color: Colors.white70)),
                  for (final r in ranks)
                    if (n > r.atLeast.length)
                      box('')
                    else
                      box(
                        chanceText(r.chance(n)),
                        key: ValueKey('rank ${r.rank} $n'),
                        fill: r.chance(n) <= 0 ? null : primary.withValues(alpha: 0.12 + 0.68 * r.chance(n)),
                        style: TextStyle(
                          fontSize: 12,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: r.chance(n) > 0.6 ? Colors.white : Colors.white.withValues(alpha: 0.85),
                          fontWeight: r.chance(n) > 0.6 ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                ],
              ),
          ],
        );
        if (width <= constraints.maxWidth) return grid;
        return SingleChildScrollView(scrollDirection: Axis.horizontal, child: grid);
      },
    );
  }
}

/// One kind of combination: its name, the chance they can make one (also
/// drawn as a bar behind the row), and up to three likeliest instances,
/// each with its chance. A kind they can't make is greyed, not left out.
class ComboRow extends StatelessWidget {
  const ComboRow({super.key, required this.combo, required this.look});

  final ComboChance combo;
  final RangeLook look;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final none = combo.chance <= 0;
    final textColor = none ? Theme.of(context).disabledColor : null;
    return Padding(
      key: ValueKey('combo ${combo.kind}'),
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final labelWidth = (constraints.maxWidth * 0.3).clamp(80.0, 170.0);
          return SizedBox(
            height: 26,
            child: Stack(
              children: [
                // The chance as a bar behind the row.
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: combo.chance.clamp(0.0, 1.0),
                      heightFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white10),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: labelWidth,
                          child: ShrinkText(
                            look.comboLabel(combo.kind),
                            style: TextStyle(fontWeight: FontWeight.w600, color: textColor),
                          ),
                        ),
                        SizedBox(
                          width: 40,
                          child: Text(
                            none ? '0%' : '${chanceText(combo.chance)}%',
                            key: const ValueKey('combo chance'),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontFeatures: const [FontFeature.tabularFigures()],
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          // As many instances as have room (about 100 px
                          // each): fewer, whole, rather than three cut short.
                          child: LayoutBuilder(
                            builder: (context, room) => ClipRect(
                              child: Row(
                                children: [
                                  for (final (example, p) in combo.examples.take((room.maxWidth ~/ 100).clamp(1, 3)))
                                    Flexible(
                                      child: _Example(combo: example, chance: p, look: look),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One likely instance: the cards (drawn or as text) and its chance.
class _Example extends StatelessWidget {
  const _Example({required this.combo, required this.chance, required this.look});

  final String combo;
  final double chance;
  final RangeLook look;

  @override
  Widget build(BuildContext context) {
    final drawn = look.comboWidget?.call(context, combo);
    final pct = Text(
      ' ${chanceText(chance)}%',
      maxLines: 1,
      style: const TextStyle(fontSize: 11, color: Colors.white60, fontFeatures: [FontFeature.tabularFigures()]),
    );
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: drawn != null
                ? SizedBox(
                    height: 20,
                    child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: drawn),
                  )
                : Text(
                    look.comboText?.call(combo) ?? combo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
          ),
          pct,
        ],
      ),
    );
  }
}

/// Makes an opponent's seat open their range when tapped (Training, a game
/// with ranges): the hand cursor and a light highlight under the mouse, so
/// it reads as clickable. Elsewhere [child] is shown as it is.
class RangeTap extends StatefulWidget {
  const RangeTap({super.key, required this.controller, required this.seat, required this.look, required this.child});

  final TurnController controller;
  final int seat;
  final RangeLook look;
  final Widget child;

  @override
  State<RangeTap> createState() => _RangeTapState();
}

class _RangeTapState extends State<RangeTap> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    if (!c.canShowRange(widget.seat)) return widget.child;
    return Semantics(
      button: true,
      label: KitStrings.of(context).term(KitTerm.range),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          key: ValueKey('range tap ${widget.seat}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => showRangeSheet(context, controller: c, seat: widget.seat, look: widget.look),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            foregroundDecoration: BoxDecoration(
              color: Colors.white.withValues(alpha: _hovered ? 0.1 : 0),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: _hovered ? 0.35 : 0)),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
