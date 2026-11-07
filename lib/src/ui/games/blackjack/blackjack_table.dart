import 'dart:math';

import 'package:flutter/material.dart' hide Card;

import '../../../games/blackjack/app/blackjack_record.dart';
import '../../../games/blackjack/blackjack.dart';
import '../../kit/card_flights.dart';
import '../../kit/cards.dart';
import '../../kit/felt.dart';
import 'blackjack_dealing.dart';
import 'l10n/blackjack_strings.dart';

/// A blackjack card as the kit draws it (rank 0 = '2' … 12 = 'A', the same
/// suit order).
CardFace blackjackFace(Card card) => CardFace.suited(card.face == 1 ? 12 : card.face - 2, card.suit);

/// Bets won or lost, with the sign and no needless decimals: "+1", "−0.5",
/// "+1.5", "0".
String betsText(double net) {
  if (net == 0) return '0';
  final abs = net.abs();
  final text = abs == abs.roundToDouble() ? abs.toStringAsFixed(0) : abs.toString();
  return net < 0 ? '−$text' : '+$text';
}

/// A finished round in a few words, for the panel between rounds: each
/// hand's outcome, then what the round won or lost, insurance included
/// ("Win +1", "Blackjack +1.5", "Push", and "Win · Bust" when a split's
/// hands cancel out).
String roundResultText(BlackjackStrings strings, BlackjackRound round) {
  final outcomes = [for (final hand in round.seats[playerSeat].hands) strings.outcome(hand.outcome)];
  final net = round.result(playerSeat).net;
  return [outcomes.join(' · '), if (net != 0) betsText(net)].join(' ');
}

/// The felt: the dealer's cards at the top (the hole card face down until
/// the dealer plays), the shoe in the corner, the player's hands at the
/// bottom (several after a split, the one to play outlined), each with its
/// total, its bet and, once the round is over, how it ended; the round's
/// result in the middle; and, with ☰ Count on, the running count and the
/// cards left in the other corner.
///
/// In a game, [dealing] holds back the cards still to come of the move just
/// made: they fly in from the shoe one by one (see BlackjackDealing), each
/// total counts the cards that have landed, and the results wait for the
/// dealer's last card.
class BlackjackTableView extends StatelessWidget {
  const BlackjackTableView({
    super.key,
    required this.play,
    this.showCount = false,
    this.showHoleCard = false,
    this.dealing,
    this.flipInstantly = false,
    this.dealerWrap,
  });

  /// The shoe being played (null: none yet). A review passes the shoe
  /// replayed to the move it shows.
  final BlackjackPlay? play;

  /// ☰ Count: the running count, the true count and the cards left.
  final bool showCount;

  /// The hole card face up even before the dealer plays (a review's All
  /// cards, the game's ☰ Show cards); the count still leaves it out.
  final bool showHoleCard;

  /// The move playing out on the felt (a game; null: a review shows each
  /// step whole).
  final BlackjackDealing? dealing;

  /// The hole card turns face up at once, without flipping over (the
  /// Animations setting is Instant).
  final bool flipInstantly;

  /// Wraps the dealer's label and cards (the game: a tap opens the
  /// dealer's range in Training); null: shown as they are.
  final Widget Function(Widget dealer)? dealerWrap;

  /// Space for a hand's or the dealer's label line.
  static const _labelHeight = 20.0;

  /// How much of each card shows under the next one.
  static const _step = 0.44;

  /// The shoe's card width on a felt [height] tall.
  static double shoeWidth(double height) => (height * 0.09).clamp(18.0, 40.0);

  @override
  Widget build(BuildContext context) {
    final flights = CardFlights.maybeOf(context);
    final listenables = <Listenable>[?dealing, ?flights];
    return FeltArea(
      child: LayoutBuilder(
        builder: (context, constraints) => listenables.isEmpty
            ? _felt(context, constraints, null)
            : ListenableBuilder(
                listenable: Listenable.merge(listenables),
                builder: (context, _) => _felt(context, constraints, flights),
              ),
      ),
    );
  }

  Widget _felt(BuildContext context, BoxConstraints constraints, CardFlights? flights) {
    final b = BlackjackStrings.of(context);
    final round = play?.round;
    final hands = round?.seats[playerSeat].hands ?? const <BlackjackHand>[];
    final dealerCards = round?.dealerCards ?? const <Card>[];
    // Cards as big as two rows and their labels allow, then as fit the
    // widest row (the hands side by side after a split; the dealer's row
    // clear of the shoe). Sized for every card of the move, so the cards
    // still to come don't push the others about.
    final h = constraints.maxHeight, w = constraints.maxWidth;
    final shoe = shoeWidth(h);
    double units(int cards) => 1 + _step * (max(cards, 2) - 1);
    final handUnits = hands.isEmpty
        ? units(2)
        : hands.map((hand) => units(hand.cards.length)).reduce((a, b) => a + b) + 0.3 * (hands.length - 1);
    final byHeight = (h - 2 * _labelHeight - 40) / 2 / cardAspectRatio;
    final byWidth = min(w / handUnits, (w - 2 * (shoe + 14)) / units(dealerCards.length));
    final cardWidth = max(18.0, min(min(byHeight, byWidth), 120.0));
    // On a big screen the dealer and the hands keep close together in the
    // middle of the felt rather than at its far edges.
    final height = min(h, 2 * (cardWidth * cardAspectRatio + _labelHeight) + 140);
    final dealing = this.dealing;
    final felt = _Felt(
      round: round,
      // Only the round being played out is held back.
      dealing: dealing != null && dealing.active && dealing.round == play?.rounds ? dealing : null,
      flights: flights,
      tagRound: play?.rounds ?? 0,
      showHoleCard: showHoleCard,
      flipInstantly: flipInstantly,
    );
    return Stack(
      children: [
        Center(
          child: SizedBox(
            height: height,
            child: Column(
              children: [
                switch (dealerWrap) {
                  final wrap? => wrap(_DealerRow(felt: felt, cardWidth: cardWidth, strings: b)),
                  null => _DealerRow(felt: felt, cardWidth: cardWidth, strings: b),
                },
                Expanded(
                  child: Center(
                    child: _RoundResult(felt: felt, strings: b),
                  ),
                ),
                _PlayerHands(felt: felt, hands: hands, cardWidth: cardWidth, strings: b),
              ],
            ),
          ),
        ),
        if (play != null) Positioned(right: 6, top: 6, child: _Shoe(width: shoe)),
        if (showCount && play != null)
          Positioned(
            left: 0,
            top: 0,
            child: _CountBadge(play: play!, notSeen: felt.notSeen, strings: b),
          ),
      ],
    );
  }
}

/// What the felt shows of a round: all of it, or (while a move plays out)
/// the cards dealt so far, and of those the ones that have landed.
class _Felt {
  const _Felt({
    required this.round,
    required this.dealing,
    required this.flights,
    required this.tagRound,
    required this.showHoleCard,
    required this.flipInstantly,
  });

  final BlackjackRound? round;
  final BlackjackDealing? dealing;
  final CardFlights? flights;

  /// The round's number, for its cards' flight tags.
  final int tagRound;
  final bool showHoleCard;
  final bool flipInstantly;

  /// A move is playing out: the results wait for its last card.
  bool get settling => dealing != null;

  /// The hole card shows its back.
  bool get holeDown => !showHoleCard && (round!.holeCardHidden || (dealing?.holeDown ?? false));

  int get shownDealer => dealing?.shownDealer(round!.dealerCards.length) ?? round!.dealerCards.length;

  int shownInHand(int hand, int cards) => dealing?.shownInHand(hand, cards) ?? cards;

  /// The card at [tag] is down on the felt (not on its way).
  bool landed(Object tag) => !(flights?.isLanding(tag) ?? false);

  /// The dealer's cards dealt and landed.
  List<Card> get dealerLanded {
    final cards = round!.dealerCards;
    return [
      for (var i = 0; i < shownDealer; i++)
        if (landed(dealerCardTag(tagRound, i))) cards[i],
    ];
  }

  /// The round's cards the player can't see yet: not dealt on the felt
  /// yet, in the air, or the hole card face down (even with a review's All
  /// cards: the count is the player's).
  List<Card> get notSeen {
    final round = this.round;
    if (round == null) return const [];
    final dealer = round.dealerCards;
    final hidden = round.holeCardHidden || (dealing?.holeDown ?? false);
    return [
      for (var i = 0; i < dealer.length; i++)
        if (i >= shownDealer || !landed(dealerCardTag(tagRound, i)) || (i == 1 && hidden)) dealer[i],
      for (final (h, hand) in round.seats[playerSeat].hands.indexed)
        for (var i = 0; i < hand.cards.length; i++)
          if (i >= shownInHand(h, hand.cards.length) || !landed(handCardTag(tagRound, h, i))) hand.cards[i],
    ];
  }

  /// Hand [hand]'s cards dealt and landed.
  List<Card> handLanded(int hand) {
    final cards = round!.seats[playerSeat].hands[hand].cards;
    return [
      for (var i = 0; i < shownInHand(hand, cards.length); i++)
        if (landed(handCardTag(tagRound, hand, i))) cards[i],
    ];
  }
}

/// Cards overlapped from left to right, [shown] of them drawn (the rest are
/// still to be dealt; their room is kept); [hidden] turns the card at that
/// index face down (the hole card). Each card's place is [tag]ged, for the
/// card flying to it.
class _CardRow extends StatelessWidget {
  const _CardRow({
    required this.cards,
    required this.cardWidth,
    required this.tag,
    required this.shown,
    this.hidden,
    this.flipInstantly = false,
  });

  final List<Card> cards;
  final double cardWidth;
  final Object Function(int i) tag;
  final int shown;
  final int? hidden;
  final bool flipInstantly;

  @override
  Widget build(BuildContext context) {
    final step = cardWidth * BlackjackTableView._step;
    final count = max(cards.length, 1);
    return SizedBox(
      width: cardWidth + step * (count - 1),
      height: cardWidth * cardAspectRatio,
      child: Stack(
        children: [
          for (var i = 0; i < min(shown, cards.length); i++)
            Positioned(
              left: i * step,
              child: GameCardView(
                // At Instant the hole card is simply face up: a new card
                // view, with nothing to flip.
                key: flipInstantly && i == 1 ? ValueKey(('hole card', hidden == 1)) : null,
                width: cardWidth,
                face: blackjackFace(cards[i]),
                faceUp: hidden != i,
                flightTag: tag(i),
              ),
            ),
        ],
      ),
    );
  }
}

/// The shoe the cards are dealt from: a few backs in the felt's corner.
class _Shoe extends StatelessWidget {
  const _Shoe({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final edge = max(1.5, width * 0.06);
    return FlightSpot(
      tag: CardFlights.shoeTag,
      child: SizedBox(
        key: const ValueKey('shoe'),
        width: width + 2 * edge,
        height: width * cardAspectRatio + 2 * edge,
        child: Stack(
          children: [
            for (var i = 2; i >= 0; i--)
              Positioned(
                left: edge * i,
                top: edge * (2 - i),
                child: GameCardView(width: width, face: null, faceUp: false),
              ),
          ],
        ),
      ),
    );
  }
}

/// A short label on the felt: a name or total, in a dark pill.
class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.color = Colors.white, super.key});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(color: const Color(0xB312171B), borderRadius: BorderRadius.circular(9)),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _DealerRow extends StatelessWidget {
  const _DealerRow({required this.felt, required this.cardWidth, required this.strings});

  final _Felt felt;
  final double cardWidth;
  final BlackjackStrings strings;

  @override
  Widget build(BuildContext context) {
    final round = felt.round;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: BlackjackTableView._labelHeight,
          child: Center(
            child: _Pill(key: const ValueKey('dealer total'), text: _label()),
          ),
        ),
        SizedBox(
          height: cardWidth * cardAspectRatio,
          child: round == null
              ? null
              : _CardRow(
                  cards: round.dealerCards,
                  cardWidth: cardWidth,
                  tag: (i) => dealerCardTag(felt.tagRound, i),
                  shown: felt.shownDealer,
                  hidden: felt.holeDown ? 1 : null,
                  flipInstantly: felt.flipInstantly,
                ),
        ),
      ],
    );
  }

  /// "Dealer", "Dealer · 10" while one card shows (as players name an
  /// upcard, not "Soft 11"), "Dealer · 17", "Dealer · Blackjack".
  String _label() {
    final round = felt.round;
    if (round == null) return strings.dealer;
    final cards = felt.dealerLanded;
    if (cards.isEmpty) return strings.dealer;
    if (felt.holeDown || cards.length == 1) {
      return '${strings.dealer} · ${BlackjackStrings.upcard(cards.first.rank)}';
    }
    if (cards.length == 2 && handTotal(cards).value == 21 && round.dealerCards.length == 2) {
      return '${strings.dealer} · ${strings.blackjackHand}';
    }
    return '${strings.dealer} · ${strings.total(handTotal(cards))}';
  }
}

/// The player's hands side by side, the one to play outlined.
class _PlayerHands extends StatelessWidget {
  const _PlayerHands({required this.felt, required this.hands, required this.cardWidth, required this.strings});

  final _Felt felt;
  final List<BlackjackHand> hands;
  final double cardWidth;
  final BlackjackStrings strings;

  @override
  Widget build(BuildContext context) {
    final round = felt.round;
    final turn = round == null || round.isOver ? null : round.turn?.hand;
    final primary = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: cardWidth * cardAspectRatio + BlackjackTableView._labelHeight + 6,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < hands.length; i++) ...[
              if (i > 0) SizedBox(width: cardWidth * 0.3),
              Column(
                key: ValueKey('hand $i'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  DecoratedBox(
                    // Drawn over the cards' edges, so the cards can't hide it.
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(cardWidth * 0.12),
                      border: Border.all(
                        color: turn == i && hands.length > 1 ? primary : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: _CardRow(
                        cards: hands[i].cards,
                        cardWidth: cardWidth,
                        tag: (k) => handCardTag(felt.tagRound, i, k),
                        shown: felt.shownInHand(i, hands[i].cards.length),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  SizedBox(height: BlackjackTableView._labelHeight, child: _handLabel(i)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// "17", "Soft 18 · ×2", and once settled "20 · Win +1" (a bust or a
  /// blackjack says so once: "Bust −1", "Blackjack +1.5"). While cards
  /// are coming, the total of those that have landed, and no outcome yet.
  Widget _handLabel(int i) {
    final hand = hands[i];
    final cards = felt.handLanded(i);
    if (cards.isEmpty) return const SizedBox.shrink();
    final doubled = hand.doubled ? ' · ×2' : '';
    final complete = cards.length == hand.cards.length;
    final total = complete && hand.isBlackjack ? strings.blackjackHand : strings.total(handTotal(cards));
    final outcome = hand.outcome;
    final key = ValueKey('hand $i total');
    if (outcome == HandOutcome.pending || felt.settling) return _Pill(key: key, text: '$total$doubled');
    final color = hand.net > 0
        ? const Color(0xFF81C784)
        : hand.net < 0
        ? const Color(0xFFE57373)
        : Colors.white;
    final said = outcome == HandOutcome.bust || outcome == HandOutcome.blackjack;
    final text = said
        ? '${strings.outcome(outcome)}$doubled ${betsText(hand.net)}'
        : '$total$doubled · ${strings.outcome(outcome)} ${betsText(hand.net)}';
    return _Pill(key: key, text: text, color: color);
  }
}

/// The round's result once it is over ("+1.5"), and the insurance taken.
/// While the dealer's cards are still coming, only the insurance.
class _RoundResult extends StatelessWidget {
  const _RoundResult({required this.felt, required this.strings});

  final _Felt felt;
  final BlackjackStrings strings;

  @override
  Widget build(BuildContext context) {
    final round = felt.round;
    if (round == null) return const SizedBox.shrink();
    final seat = round.seats[playerSeat];
    final insured = seat.insurance == true;
    if (!round.isOver || felt.settling) return insured ? _Pill(text: strings.insured) : const SizedBox.shrink();
    final net = round.result(playerSeat).net;
    final color = net > 0
        ? const Color(0xFF81C784)
        : net < 0
        ? const Color(0xFFE57373)
        : Colors.white;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            betsText(net),
            key: const ValueKey('round result'),
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color),
          ),
          if (insured) _Pill(text: strings.insured),
        ],
      ),
    );
  }
}

/// ☰ Count: the running count, the true count and the cards left.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.play, required this.notSeen, required this.strings});

  final BlackjackPlay play;

  /// The round's cards the player can't see yet (still on their way, or
  /// the hole card face down).
  final List<Card> notSeen;
  final BlackjackStrings strings;

  @override
  Widget build(BuildContext context) {
    final shoe = play.table.shoe;
    // What the player has seen: everything dealt since the shuffle but a
    // face-down hole card and the cards still flying in.
    final seen = [...shoe.dealt];
    for (final card in notSeen) {
      seen.remove(card);
    }
    final unseen = shoe.size - seen.length;
    final count = HiLoCount.of(seen, unseen);
    // Narrow enough to clear the dealer's label, centred above the cards.
    return Container(
      key: const ValueKey('count'),
      constraints: const BoxConstraints(maxWidth: 86),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: const Color(0xCC12171B), borderRadius: BorderRadius.circular(8)),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: DefaultTextStyle.merge(
          style: const TextStyle(fontSize: 11, color: Colors.white, height: 1.25),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(strings.runningCount(BlackjackStrings.signed(count.running))),
              Text(strings.trueCount(BlackjackStrings.signed(count.trueCount, decimals: 1))),
              Text(strings.cardsLeft(shoe.cardsLeft), style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }
}
