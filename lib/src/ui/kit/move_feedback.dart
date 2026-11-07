import 'package:flutter/material.dart';

import '../../gto/spot_strategy.dart' show DecisionGrade;
import '../../kit/coach_answer.dart';
import '../../kit/grading.dart';
import '../../l10n/strings.dart';
import '../strategy_panel.dart' show gradeColor;
import 'coach_panel.dart';
import 'fit_text.dart';
import 'help.dart';
import 'l10n/game_strings.dart';
import 'l10n/kit_strings.dart';

/// The grade of the player's last graded move: the grade chip (with "?"),
/// what it gave up, the move, the coach's pick when it differs, and one
/// short reason. [inline] squeezes it onto one line (the compact panel's
/// status line): the chip, the loss (its number alone) and "GTO: `best`".
///
/// Moves are drawn with CoachLook.moveWidget when the game has one (Big
/// Two's mini cards, as in the coach list), else named by
/// CoachLook.markText or moveText. The pick line says whose move it is:
/// the mark's bestTag ("Count: Stand"), else the game's pick label. The
/// loss is in the mark's own unit when it has one, else [unit].
class MoveFeedback extends StatelessWidget {
  const MoveFeedback({
    super.key,
    required this.mark,
    required this.unit,
    required this.strings,
    this.look = const CoachLook(),
    this.inline = false,
    this.moveIndex,
  });

  final MoveMark mark;
  final ValueUnit unit;
  final GameStrings strings;
  final CoachLook look;
  final bool inline;

  /// The graded move's index in the record, for CoachLook.markText (null:
  /// moveText names the moves).
  final int? moveIndex;

  String _text(String move) {
    final named = look.markText;
    final i = moveIndex;
    return named != null && i != null ? named(move, i) : look.moveText(move);
  }

  @override
  Widget build(BuildContext context) {
    final k = KitStrings.of(context);
    final best = mark.grade == DecisionGrade.best;
    const small = TextStyle(fontSize: 12, color: Colors.white70);
    final chip = GradeChip(grade: mark.grade);
    final lossUnit = mark.unit ?? unit;
    // Inline, the number alone (as the coach rows show theirs): "apuestas"
    // would leave no room for the pick on a sideways phone.
    final loss = best
        ? null
        : Text(
            inline ? formatValue(lossUnit, -mark.loss) : k.amount(lossUnit, -mark.loss),
            key: const ValueKey('loss'),
            maxLines: 1,
            style: const TextStyle(color: Color(0xFFFFE082)),
          );
    final label = mark.bestTag == null ? strings.pickLabel : strings.tagLabel(mark.bestTag!) ?? strings.pickLabel;
    final pick = best
        ? null
        : _PickText(
            label: label,
            text: _text(mark.best),
            drawn: look.moveWidget?.call(context, mark.best),
            move: mark.best,
            look: look,
          );
    final playedDrawn = look.moveWidget?.call(context, mark.played);
    if (inline) {
      return Row(
        children: [
          chip,
          if (loss != null) ...[const SizedBox(width: 6), loss],
          if (pick != null) ...[const SizedBox(width: 6), Flexible(child: pick)],
        ],
      );
    }
    final reason = look.reason(mark.reasons);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: gradeColor(mark.grade).withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              chip,
              TermsHelpButton(title: k.term(KitTerm.grades), terms: [k.entry(KitTerm.grades), k.entry(KitTerm.score)]),
              ?loss,
              const SizedBox(width: 8),
              Expanded(
                child: playedDrawn != null
                    ? Align(
                        alignment: Alignment.centerRight,
                        child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: playedDrawn),
                      )
                    : Text(
                        _text(mark.played),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
              ),
            ],
          ),
          ?pick,
          if (reason != null) Text(reason, maxLines: 1, overflow: TextOverflow.ellipsis, style: small),
        ],
      ),
    );
  }
}

/// A grade as a coloured chip ("Mistake").
class GradeChip extends StatelessWidget {
  const GradeChip({super.key, required this.grade});

  final DecisionGrade grade;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: gradeColor(grade), borderRadius: BorderRadius.circular(10)),
      child: Text(
        S.of(context).grade(grade),
        maxLines: 1,
        style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 12),
      ),
    );
  }
}

/// "GTO: `best`": hovering it lights the move on the table (through
/// CoachLook.pickHover). A long label gets a little smaller before it is
/// cut; a drawn move follows the label and shrinks to fit.
class _PickText extends StatefulWidget {
  const _PickText({required this.label, required this.text, this.drawn, required this.move, required this.look});

  final String label;
  final String text;
  final Widget? drawn;
  final String move;
  final CoachLook look;

  @override
  State<_PickText> createState() => _PickTextState();
}

class _PickTextState extends State<_PickText> {
  bool _hovered = false;

  static const _style = TextStyle(fontSize: 13);

  void _hover(String? move) {
    _hovered = move != null;
    widget.look.pickHover?.call(move);
  }

  @override
  void dispose() {
    // Gone under the mouse (the next move was graded): end the preview.
    if (_hovered) endHoverAfterFrame(widget.look.pickHover);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final drawn = widget.drawn;
    final Widget label = drawn == null
        ? ShrinkText('${widget.label}: ${widget.text}', style: _style)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: ShrinkText('${widget.label}:', style: _style)),
              const SizedBox(width: 4),
              Flexible(
                child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: drawn),
              ),
            ],
          );
    if (widget.look.pickHover == null) return label;
    return MouseRegion(onEnter: (_) => _hover(widget.move), onExit: (_) => _hover(null), child: label);
  }
}
