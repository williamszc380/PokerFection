import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../kit/coach_answer.dart';
import 'fit_text.dart';
import 'l10n/game_strings.dart';
import 'l10n/kit_strings.dart';

/// How a game shows its moves, reasons and proofs in the coach list and
/// the feedback card, and what hovering, tapping or double tapping a coach
/// row does.
///
/// The same in every game: a single click (tap) on a row SELECTS its move
/// ([onSelect]: the cards pop up in the hand, or the choice's button lights
/// up) and never plays it; a double click (double tap) PLAYS it ([onPlay]).
/// The row of the move selected now ([selected]) is lit.
class CoachLook {
  const CoachLook({
    this.moveText = _same,
    this.moveWidget,
    this.reasonText,
    this.proofText,
    this.onHover,
    this.onSelect,
    this.onPlay,
    this.selected,
    this.onPickHover,
    this.markText,
  });

  static String _same(String move) => move;

  /// A move as text: "h8", "Pair of 7s", "Hit" (default: the notation).
  final String Function(String move) moveText;

  /// A move drawn (mini cards); null: [moveText].
  final Widget Function(BuildContext context, String move)? moveWidget;

  /// A reason code as a few words; null (or a null answer): not shown.
  final String? Function(String code)? reasonText;

  /// A proof ('win:5') as a badge ("Wins in 5"); null: not shown.
  final String? Function(String proof)? proofText;

  /// The mouse is over a row with this move (null: it left, or the row went
  /// away under it), so the game can preview the move on the table.
  final void Function(String? move)? onHover;

  /// A row was tapped once: select the move in the game's own controls
  /// (pick its cards; a choice such as Pass: TurnController.choose). Never
  /// plays it. GameScaffold fills in TurnController.choose when the game
  /// gives none.
  final void Function(String move)? onSelect;

  /// A row was tapped twice in a row (a double click): play the move.
  /// GameScaffold fills in TurnController.playFromCoach when the game gives
  /// none; null in a review (a double tap only selects there).
  final void Function(String move)? onPlay;

  /// The move selected now (its row is lit): the move the picked cards make,
  /// or the chosen choice. GameScaffold fills in TurnController.chosen when
  /// the game gives none.
  final String? selected;

  /// The mouse is over the feedback's "GTO: `best`" (null: it left). That
  /// move was best in the position it graded, before the bots answered, so
  /// a game may show it apart from a coach row's move for the position now;
  /// null: [onHover].
  final void Function(String? move)? onPickHover;

  /// The feedback's moves as text, named in the position of move
  /// [moveIndex] (the graded move's index in the record): Blackjack's
  /// insurance is "Even money" when the player has blackjack. Null:
  /// [moveText]. A [moveWidget] still draws them when the game has one.
  final String Function(String move, int moveIndex)? markText;

  /// What the feedback calls on hover: [onPickHover], else [onHover].
  void Function(String? move)? get pickHover => onPickHover ?? onHover;

  /// This look with the row actions and selection replaced.
  CoachLook copyWith({
    void Function(String move)? onSelect,
    void Function(String move)? onPlay,
    String? Function()? selected,
  }) =>
      CoachLook(
        moveText: moveText,
        moveWidget: moveWidget,
        reasonText: reasonText,
        proofText: proofText,
        onHover: onHover,
        onSelect: onSelect ?? this.onSelect,
        onPlay: onPlay ?? this.onPlay,
        selected: selected == null ? this.selected : selected(),
        onPickHover: onPickHover,
        markText: markText,
      );

  /// The first reason of [codes] that has text.
  String? reason(List<String> codes) {
    final text = reasonText;
    if (text == null) return null;
    for (final code in codes) {
      if (text(code) case final words?) return words;
    }
    return null;
  }
}

/// The coach's moves for the player's position: up to [maxRows] rows, the
/// pick outlined and tagged with the game's pick label. The answer's listed
/// moves (Pass, No bid) are always among the rows (CoachAnswer.shown). A
/// tap selects a row's move, a double tap plays it (see CoachLook).
class CoachList extends StatelessWidget {
  const CoachList({
    super.key,
    required this.answer,
    required this.strings,
    this.look = const CoachLook(),
    this.maxRows = 5,
    this.fitHeight,
    this.dense = false,
    this.thinking = false,
    this.canThinkLonger = false,
    this.onThinkLonger,
  });

  /// Null while the first answer is on its way.
  final CoachAnswer? answer;
  final GameStrings strings;
  final CoachLook look;
  final int maxRows;

  /// The room the list has (the compact panel's, on a sideways phone): it
  /// then shows as many rows as fit, from 3 up to [maxRows], judged by each
  /// row's own height (a row with a reason line is half as tall again as
  /// one without). Not even three fit: two, the pick and a listed move such
  /// as Pass, rather than leave Pass half out of sight. Null: [maxRows].
  final double? fitHeight;

  /// Tighter rows (the compact panel).
  final bool dense;

  /// A job is working on an answer (a thin bar shows).
  final bool thinking;
  final bool canThinkLonger;
  final VoidCallback? onThinkLonger;

  @override
  Widget build(BuildContext context) {
    final k = KitStrings.of(context);
    final answer = this.answer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 2, child: thinking ? const LinearProgressIndicator(minHeight: 2) : null),
        if (answer != null)
          for (final line in answer.shown(rowsFor(context, answer)))
            // Keyed by move: a row's hover and taps belong to its move.
            _CoachRow(key: ValueKey(line.move), answer: answer, line: line, strings: strings, look: look, dense: dense),
        if (onThinkLonger case final onPressed?)
          Align(
            alignment: Alignment.centerRight,
            child: ThinkLongerButton(enabled: canThinkLonger, onPressed: onPressed, label: k.thinkLonger),
          ),
      ],
    );
  }

  /// How many rows to show of [answer]: [maxRows], or as many as fit in
  /// [fitHeight] (see there).
  @visibleForTesting
  int rowsFor(BuildContext context, CoachAnswer answer) {
    final room = fitHeight;
    if (room == null) return maxRows;
    final heights = CoachRowHeights.of(context, look: look, dense: dense);
    // The thinking bar above the rows.
    final left = room - 2;
    for (var n = maxRows; n >= 3; n--) {
      if (heights.total(answer.shown(n)) <= left) return n;
    }
    return answer.listed.isEmpty ? 3 : 2;
  }
}

/// The height a coach row takes, worked out before it is laid out (the
/// compact list picks how many rows to show from them): its padding, the
/// move's line, and the reason's line when it has one. The lines are
/// measured in the text style and scale in force; a drawn move (mini
/// cards) is taken as [drawnLine] tall, as the card games draw theirs.
class CoachRowHeights {
  CoachRowHeights._(this.look, this.padding, this.moveLine, this.reasonLine);

  factory CoachRowHeights.of(BuildContext context, {required CoachLook look, required bool dense}) {
    final base = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    double line(TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: 'Ag', style: base.merge(style)),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final height = painter.height;
      painter.dispose();
      return height;
    }

    final moveLine = line(_CoachRowState._moveStyle);
    return CoachRowHeights._(
      look,
      // The row's gap (vertical padding) and the inside padding, both sides.
      dense ? 2.0 + 4.0 : 4.0 + 8.0,
      look.moveWidget == null ? moveLine : max(moveLine, drawnLine),
      line(_CoachRowState._reasonStyle),
    );
  }

  /// The tallest a drawn move is taken to be.
  static const drawnLine = 26.0;

  final CoachLook look;
  final double padding, moveLine, reasonLine;

  /// [line]'s row.
  double of(CoachLine line) => padding + moveLine + (look.reason(line.reasons) == null ? 0 : reasonLine);

  /// [lines]' rows, one under the other.
  double total(Iterable<CoachLine> lines) => lines.fold(0.0, (sum, l) => sum + of(l));
}

/// Think longer: a text button, or (the compact panel, where a row of its
/// own would push a coach row out of sight) its icon alone, on the status
/// line. Greyed out unless [enabled]; never hidden.
class ThinkLongerButton extends StatelessWidget {
  const ThinkLongerButton({
    super.key = const ValueKey('think longer'),
    required this.enabled,
    required this.onPressed,
    required this.label,
    this.iconOnly = false,
  });

  final bool enabled;
  final VoidCallback onPressed;

  /// "Think longer" in the app's language (the icon's name when [iconOnly]).
  final String label;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(Icons.psychology_outlined, size: 18, semanticLabel: iconOnly ? label : null);
    if (iconOnly) {
      return IconButton(
        onPressed: enabled ? onPressed : null,
        icon: icon,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 30, height: 26),
        style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        color: Theme.of(context).colorScheme.primary,
      );
    }
    return TextButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: icon,
      label: Text(label),
      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
    );
  }
}

class _CoachRow extends StatefulWidget {
  const _CoachRow({
    super.key,
    required this.answer,
    required this.line,
    required this.strings,
    required this.look,
    required this.dense,
  });

  final CoachAnswer answer;
  final CoachLine line;
  final GameStrings strings;
  final CoachLook look;
  final bool dense;

  @override
  State<_CoachRow> createState() => _CoachRowState();
}

class _CoachRowState extends State<_CoachRow> {
  bool _hovered = false;

  /// A first tap selected the move; a second one before this runs out
  /// plays it. The select happens at once (no waiting to see whether a
  /// second tap comes), so a single tap feels as quick as before.
  Timer? _secondTap;

  void _tap() {
    final look = widget.look, move = widget.line.move;
    if (_secondTap?.isActive ?? false) {
      _secondTap!.cancel();
      _secondTap = null;
      if (look.onPlay case final play?) return play(move);
      look.onSelect?.call(move);
      return;
    }
    look.onSelect?.call(move);
    if (look.onPlay != null) _secondTap = Timer(kDoubleTapTimeout, () => _secondTap = null);
  }

  static const _tagStyle = TextStyle(fontSize: 11);
  static const _tagGap = 4.0, _tagPadding = 5.0;
  static const _secondStyle = TextStyle(
    fontSize: 12,
    color: Colors.white70,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const _valueStyle = TextStyle(fontFeatures: [FontFeature.tabularFigures()], fontWeight: FontWeight.w600);
  static const _moveStyle = TextStyle(fontWeight: FontWeight.w600);
  static const _reasonStyle = TextStyle(fontSize: 12, color: Colors.white70);

  /// The most each tag may take of a row [width] wide: what it needs, as
  /// long as the numbers keep theirs and the move keeps at least its own
  /// width (a text move, up to 30% of the row) or a quarter of the row (a
  /// drawn one). When that isn't enough, the pick's tag (the first) keeps
  /// its width first and the others share what is left; a tag still short
  /// of room gets smaller, then is cut.
  List<double> _tagWidths(
    BuildContext context,
    double width, {
    required List<String> tags,
    required List<String> numbers,
    String? move,
  }) {
    if (tags.isEmpty) return const [];
    if (!width.isFinite) return [for (final _ in tags) double.infinity];
    double need(String tag) => textWidth(context, tag, _tagStyle) + 2 * _tagPadding + _tagGap + 1;
    final moveRoom = move == null ? width * 0.25 : min(textWidth(context, move, _moveStyle) + 2, width * 0.3);
    final numbersRoom = 8 +
        (numbers.length > 1 ? textWidth(context, numbers.first, _secondStyle) + 6 : 0) +
        textWidth(context, numbers.last, _valueStyle) +
        2;
    var left = max(0.0, width - moveRoom - numbersRoom);
    final needs = [for (final tag in tags) need(tag)];
    final widths = List<double>.filled(tags.length, 0);
    widths[0] = min(needs[0], left);
    left -= widths[0];
    // The others, narrowest first, each taking at most a fair share.
    final rest = [for (var i = 1; i < tags.length; i++) i]..sort((a, b) => needs[a].compareTo(needs[b]));
    for (final (k, i) in rest.indexed) {
      widths[i] = min(needs[i], left / (rest.length - k));
      left -= widths[i];
    }
    // Never so narrow that a tag is only its "...".
    return [for (final w in widths) max(w, 28.0)];
  }

  void _hover(bool inside) {
    setState(() => _hovered = inside);
    widget.look.onHover?.call(inside ? widget.line.move : null);
  }

  @override
  void dispose() {
    // A region that goes away gets no exit (the player moved by key, or a
    // new answer came): end the game's preview.
    if (_hovered) endHoverAfterFrame(widget.look.onHover);
    _secondTap?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final _CoachRow(:answer, :line, :strings, :look, :dense) = widget;
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final isPick = line.move == answer.pick;
    final tags = [
      if (isPick) strings.pickLabel,
      if (line.tag case final tag?) ?strings.tagLabel(tag),
      if (line.proof case final proof?) ?look.proofText?.call(proof),
    ];
    final reason = look.reason(line.reasons);
    final k = KitStrings.of(context);
    // A second number, when the line has one in another unit: Big Two's win
    // chance beside its points, Fight the Landlord's points beside its win chance.
    final second = switch (line) {
      CoachLine(:final winChance?) when answer.unit != ValueUnit.winChance =>
        k.winChance(formatValue(ValueUnit.winChance, winChance)),
      CoachLine(:final points?) when answer.unit != ValueUnit.points =>
        k.pointsValue(formatValue(ValueUnit.points, points)),
      _ => null,
    };
    final drawn = look.moveWidget?.call(context, line.move);
    final move = drawn != null
        ? FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: drawn)
        : Text(
          look.moveText(line.move),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _moveStyle,
        );
    final tappable = look.onSelect != null || look.onPlay != null;
    final selected = look.selected == line.move;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 1 : 2),
      child: Material(
        key: selected ? const ValueKey('selected row') : null,
        // Lit under the mouse (the game previews the move meanwhile), and
        // filled while its move is the one selected.
        color: selected
            ? primary.withValues(alpha: _hovered ? 0.4 : 0.3)
            : Colors.white.withValues(alpha: _hovered ? 0.12 : 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: selected
                ? Colors.white70
                : isPick
                    ? primary
                    : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: MouseRegion(
          onEnter: (_) => _hover(true),
          onExit: (_) => _hover(false),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            // The hand when a tap selects (or a double tap plays) the move.
            mouseCursor: WidgetStateMouseCursor.clickable,
            onTap: tappable ? _tap : null,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: dense ? 2 : 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  LayoutBuilder(
                    // The numbers keep the right edge, the tags read in full
                    // (the pick's first), and the move takes the rest.
                    builder: (context, constraints) {
                      final widths = _tagWidths(
                        context,
                        constraints.maxWidth,
                        tags: tags,
                        numbers: [?second, formatValue(answer.unit, line.value)],
                        move: drawn == null ? look.moveText(line.move) : null,
                      );
                      return Row(
                        children: [
                          Expanded(
                            child: Align(alignment: Alignment.centerLeft, child: move),
                          ),
                          for (final (i, tag) in tags.indexed)
                            ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: widths[i]),
                              child: Container(
                                margin: const EdgeInsets.only(left: _tagGap),
                                padding: const EdgeInsets.symmetric(horizontal: _tagPadding, vertical: 1),
                                decoration: BoxDecoration(
                                  color: (i == 0 && isPick ? primary : Colors.white24).withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: ShrinkText(tag, style: _tagStyle, minFontSize: 9),
                              ),
                            ),
                          const SizedBox(width: 8),
                          if (second != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Text(
                                second,
                                key: const ValueKey('second number'),
                                maxLines: 1,
                                style: _secondStyle,
                              ),
                            ),
                          Text(formatValue(answer.unit, line.value), maxLines: 1, style: _valueStyle),
                        ],
                      );
                    },
                  ),
                  if (reason != null)
                    Text(
                      reason,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _reasonStyle,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tells [onHover] the preview is over once this frame is done: a widget
/// that goes away under the mouse gets no exit, and the game can't rebuild
/// in the middle of a frame.
void endHoverAfterFrame(void Function(String? move)? onHover) {
  if (onHover == null) return;
  SchedulerBinding.instance
    ..addPostFrameCallback((_) => onHover(null))
    ..ensureVisualUpdate();
}

/// A game's button for a choice (Pass, a bid, Hit), lit while that choice
/// is selected from the coach list (TurnController.chosen): a bright ring
/// around it, so the player sees what a double tap, Enter or the button
/// itself will play. Lit, the button sits on a solid fill: an outlined or
/// text button is see-through, and the glow behind it would wash its label
/// out until it looked greyed out.
class ChosenRing extends StatelessWidget {
  const ChosenRing({super.key, required this.lit, required this.child, this.radius = 22});

  /// What a lit button sits on (a filled button covers it).
  static const fill = Color(0xFF12171B);

  final bool lit;
  final Widget child;

  /// The ring's corner radius (a FilledButton's is about 20).
  final double radius;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedContainer(
      key: lit ? const ValueKey('chosen ring') : null,
      duration: const Duration(milliseconds: 120),
      // Drawn over the button's edge and glowing around it: the button
      // keeps its size, lit or not.
      decoration: BoxDecoration(
        color: lit ? fill : fill.withValues(alpha: 0),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [BoxShadow(color: color.withValues(alpha: lit ? 0.8 : 0), blurRadius: 10, spreadRadius: 1)],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: lit ? Colors.white : Colors.transparent, width: 2),
      ),
      child: child,
    );
  }
}
