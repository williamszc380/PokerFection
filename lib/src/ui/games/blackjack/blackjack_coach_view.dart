import '../../../games/blackjack/app/blackjack_analysis_codec.dart';
import '../../../games/blackjack/app/blackjack_record.dart';
import '../../../games/blackjack/blackjack.dart';
import '../../kit/coach_panel.dart';
import '../../kit/range_sheet.dart';
import 'blackjack_controller.dart';
import 'l10n/blackjack_strings.dart';

/// A move as the coach list and the feedback write it: the decision's
/// name ("Hit", "Even money"), or Deal.
String blackjackMoveText(BlackjackStrings strings, String move, {bool evenMoney = false, required String deal}) {
  if (move == dealMove) return deal;
  final parsed = parseHandMove(move);
  if (parsed == null) return move;
  if (parsed.action == BlackjackAction.insurance && evenMoney) return strings.evenMoney;
  return strings.action(parsed.action);
}

/// How the coach list and the feedback show blackjack: decisions by name,
/// each row's first reason in a few words, and hovering a row outlining
/// its button in the panel ([onPreview]; null when the mouse leaves).
///
/// A click on a row is the kit's, as in every game: one click selects the
/// decision (TurnController.choose: its button gets a bright ring and its
/// row is lit), a double click makes it (TurnController.playFromCoach).
/// One click never plays. The coach list names insurance by the offer
/// standing now, the feedback by the offer its move answered.
CoachLook blackjackCoachLook({
  required BlackjackStrings strings,
  required BlackjackController controller,
  required String deal,
  required void Function(String? move) onPreview,
}) => CoachLook(
  moveText: (move) => blackjackMoveText(strings, move, evenMoney: controller.offersEvenMoney, deal: deal),
  markText: (move, index) =>
      blackjackMoveText(strings, move, evenMoney: isInsurance(move) && controller.evenMoneyAt(index), deal: deal),
  reasonText: (code) => blackjackReason(strings, code),
  onHover: onPreview,
);

/// Whether [move] takes insurance (or even money): the one move named by
/// the offer it answers.
bool isInsurance(String move) => parseHandMove(move)?.action == BlackjackAction.insurance;

/// A reason code in a few words, or null for one the strings don't know.
String? blackjackReason(BlackjackStrings strings, String code) => switch (tryParseReasonCode(code)) {
  final reason? => strings.reason(reason),
  null => null,
};

/// How the dealer's range reads (tap the dealer in Training): the hole
/// card's ranks as the cards show them (2 to 10, then A), the two-card
/// totals as players group them ("Blackjack", "17–21", "12–16", "11 or
/// less"), each hand as "6 + 10", and "?" entries for those groups and the
/// hole card.
RangeLook blackjackRangeLook(BlackjackStrings strings) {
  String rank(String code) => code == 'T' ? '10' : code;
  return RangeLook(
    rankLabel: rank,
    comboLabel: (kind) => switch (kind) {
      'blackjack' => strings.blackjackHand,
      'total17to21' => strings.totalsFromTo(17, 21),
      'total12to16' => strings.totalsFromTo(12, 16),
      _ => strings.totalOrLess(11),
    },
    comboText: (combo) => combo.split('+').map(rank).join(' + '),
    terms: [strings.entry(BlackjackTerm.dealerStart), strings.entry(BlackjackTerm.holeCard)],
  );
}
