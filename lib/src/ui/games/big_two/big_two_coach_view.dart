import 'package:flutter/material.dart' hide Card;

import '../../../app/app_settings.dart';
import '../../../games/big_two/app/big_two_analysis.dart';
import '../../../games/big_two/app/big_two_record.dart';
import '../../../games/big_two/big_two.dart';
import '../../kit/cards.dart';
import '../../kit/coach_panel.dart';
import '../../kit/help.dart';
import '../../kit/l10n/game_strings.dart';
import '../../widgets/card_view.dart' show SuitIcon;
import 'l10n/big_two_strings.dart';

/// A Big Two card as the kit draws it (poker's rank and suit order).
CardFace bigTwoFace(Card card) => CardFace.suited((card.rank + 1) % 13, switch (card.suit) {
  Suit.clubs => 0,
  Suit.diamonds => 1,
  Suit.hearts => 2,
  Suit.spades => 3,
});

/// A card as text: "10♠".
String cardLabel(Card card) => card.label;

/// A move as text: "7♣ 7♥", or "Pass".
String moveLabel(BigTwoStrings strings, String move) {
  final cards = bigTwoMoveCards(move);
  return cards.isEmpty ? strings.pass : cards.map(cardLabel).join(' ');
}

/// How the coach list and the feedback show Big Two moves: mini cards in
/// the rows and the feedback, card text elsewhere, the reasons and the
/// sure-win badge in the player's language. [onHover] lights a row's cards
/// in the hand while the mouse is over it; [onSelect] takes a single tap
/// (the game: a play's cards are picked, Pass lights its button; the
/// review only lights them); [selected] is the move picked now, whose row
/// is lit. A double tap plays the row (the kit's default).
CoachLook bigTwoLook(
  BigTwoStrings strings, {
  void Function(String? move)? onHover,
  void Function(String move)? onSelect,
  String? selected,
}) => CoachLook(
  moveText: (move) => moveLabel(strings, move),
  moveWidget: (context, move) {
    final cards = bigTwoMoveCards(move);
    if (cards.isEmpty) return Text(strings.pass, style: const TextStyle(fontWeight: FontWeight.w600));
    return MiniCards(cards: cards);
  },
  reasonText: (code) {
    final reason = CoachReason.values.asNameMap()[code];
    return reason == null ? null : strings.reason(reason);
  },
  proofText: (proof) => proof == 'sure' ? strings.sureWin : null,
  onHover: onHover,
  onSelect: onSelect,
  selected: selected,
);

/// Cards as small face chips (rank and suit in the colours set in
/// Settings), for the coach's rows, the hand plan and the guides.
class MiniCards extends StatelessWidget {
  const MiniCards({super.key, required this.cards, this.height = 22, this.dimmed = const {}});

  final List<Card> cards;
  final double height;

  /// Cards drawn faded (the counter's cards already seen).
  final Set<Card> dimmed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final card in cards)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: MiniCard(card: card, height: height, dimmed: dimmed.contains(card)),
          ),
      ],
    );
  }
}

/// One card as a small face chip.
class MiniCard extends StatelessWidget {
  const MiniCard({super.key, required this.card, this.height = 22, this.dimmed = false});

  final Card card;
  final double height;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final style = AppSettings.of(context).cardFaces;
    final suit = bigTwoFace(card).suit;
    final chip = Container(
      height: height,
      constraints: BoxConstraints(minWidth: height * 0.95),
      padding: EdgeInsets.symmetric(horizontal: height * 0.12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: style.face(suit),
        borderRadius: BorderRadius.circular(height * 0.18),
        border: Border.all(color: Colors.black26, width: 0.5),
      ),
      // The suit is drawn, as in poker's history: not every font has it.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            card.rankLabel,
            maxLines: 1,
            style: TextStyle(color: style.ink(suit), fontSize: height * 0.58, fontWeight: FontWeight.w700, height: 1.0),
          ),
          SuitIcon(suit: suit, size: height * 0.46, color: style.ink(suit)),
        ],
      ),
    );
    return dimmed ? Opacity(opacity: 0.3, child: chip) : chip;
  }
}

/// The hand plan (under the coach's moves): the fewest plays that empty
/// the hand, the unbeatable ones outlined, with how many each.
class BigTwoPlanView extends StatelessWidget {
  const BigTwoPlanView({super.key, required this.report, required this.strings});

  final BigTwoReport report;
  final BigTwoStrings strings;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final sure = report.planSure.where((s) => s).length;
    return _Extra(
      key: const ValueKey('hand plan'),
      title: strings.handPlan,
      trailing: Text(
        strings.planSummary(report.plan.length, sure),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: Colors.white70),
      ),
      help: [strings.entry(BigTwoTerm.handPlan), strings.entry(BigTwoTerm.unbeatable)],
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final (i, move) in report.plan.indexed)
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: i < report.planSure.length && report.planSure[i] ? primary : Colors.white24,
                  width: 1.2,
                ),
              ),
              child: MiniCards(cards: bigTwoMoveCards(move), height: 18),
            ),
        ],
      ),
    );
  }
}

/// The card counter (☰ Card counter): the 2s, aces and kings, faded once
/// seen (played, or in the player's hand), and the highest card still out.
class BigTwoCounterView extends StatelessWidget {
  const BigTwoCounterView({super.key, required this.counter, required this.strings});

  final CardCounter counter;
  final BigTwoStrings strings;

  @override
  Widget build(BuildContext context) {
    final rules = counter.view.rules;
    final out = counter.outCards.toSet();
    // Highest suit first, as players read a run of 2s.
    final suits = rules.suitOrder.reversed.toList();
    final highest = counter.highestOut;
    return _Extra(
      key: const ValueKey('card counter'),
      title: strings.cardCounter,
      trailing: highest == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    '${strings.highestOut} ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ),
                MiniCard(card: highest, height: 16),
              ],
            ),
      help: [strings.entry(BigTwoTerm.cardCounter)],
      child: Wrap(
        spacing: 10,
        runSpacing: 4,
        children: [
          for (final rank in const [Ranks.two, Ranks.ace, Ranks.king])
            MiniCards(
              height: 18,
              cards: [for (final suit in suits) Card.of(rank, suit)],
              dimmed: {
                for (final suit in suits)
                  if (!out.contains(Card.of(rank, suit))) Card.of(rank, suit),
              },
            ),
        ],
      ),
    );
  }
}

/// A coach extra's frame: a title row (with "?" and a short note at the
/// right), then its content.
class _Extra extends StatelessWidget {
  const _Extra({super.key, required this.title, this.trailing, required this.help, required this.child});

  final String title;
  final Widget? trailing;
  final List<GameTerm> help;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(8, 2, 6, 6),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(title, maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              TermsHelpButton(title: title, terms: help),
              const SizedBox(width: 4),
              if (trailing case final widget?)
                Expanded(
                  child: Align(alignment: Alignment.centerRight, child: widget),
                ),
            ],
          ),
          child,
        ],
      ),
    );
  }
}
