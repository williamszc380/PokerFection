/// The order a deal's cards go round the table, for the step that opens
/// every deal: who bids first.
///
/// Pagat: "One card is turned face up and inserted somewhere near the
/// middle of the stack"; the players draw their cards in turn, and "the
/// player who drew the face up card ... is the first to bid". The screens
/// show it as it happens: the cards go out one at a time round the table,
/// the face-up card among them, face up, to its holder.
///
/// The engine keeps no deck order (a hand is a set of cards), so the order
/// shown is made up from what a device may know, and is the same on every
/// device that knows it:
/// - the cards go to the seats in turn, starting from hand seat 0 (one
///   physical place at the table, whichever seat a device draws at the
///   bottom);
/// - the face-up card is drawn in round 7 to 11 of 17 (near the middle of
///   the stack), the round picked by the card itself, which everyone sees;
/// - a hand's other cards come in an order picked by that hand's cards
///   alone, so a seat and a spectator who sees that hand agree, and a hand
///   a device doesn't see (drawn as backs) needs no order at all.
///
/// Nothing here is a secret: it reads the face-up card, its holder and the
/// cards the caller holds, and tells nothing more about any hand.
library;

import 'game.dart';

/// One card of the deal on its way: to [seat], card [id] (for a hand the
/// device doesn't see, a stand-in, drawn as a back).
typedef DdzDealt = ({int seat, int id});

/// The deal's cards in the order they go out (see the library's comment).
class DdzDealOrder {
  const DdzDealOrder._(this.cards, this.faceUpAt, this.firstBidder, this.faceUp);

  /// The order for [game] at the start of its deal (the auction: no card
  /// has moved yet). [firstSeat]: the seat of [game] that is hand seat 0,
  /// where the deal starts (a device that draws its own seat at the bottom
  /// turns the seats: see DdzWireView.rotated).
  factory DdzDealOrder.of(DdzGame game, {int firstSeat = 0}) {
    final faceUp = game.faceUp;
    final first = game.firstBidder;
    final perSeat = [for (var s = 0; s < 3; s++) _handOrder(game.hands[s], s == first ? faceUp : null)];
    final cards = <DdzDealt>[];
    int? faceUpAt;
    final longest = perSeat.fold(0, (n, h) => h.length > n ? h.length : n);
    for (var round = 0; round < longest; round++) {
      for (var k = 0; k < 3; k++) {
        final seat = (firstSeat + k) % 3;
        if (round >= perSeat[seat].length) continue;
        final id = perSeat[seat][round];
        if (id == faceUp && seat == first) faceUpAt = cards.length;
        cards.add((seat: seat, id: id));
      }
    }
    return DdzDealOrder._(List.unmodifiable(cards), faceUpAt, first, faceUp);
  }

  /// Every card dealt to the hands (51 in a real deal), in order.
  final List<DdzDealt> cards;

  /// Where the face-up card is in [cards]; null for a deal without one (a
  /// set-up deal, an old save).
  final int? faceUpAt;

  /// The seat the face-up card goes to: the first to bid.
  final int firstBidder;

  /// The face-up card (null: none).
  final int? faceUp;

  /// The round (0 to 16) the face-up card is drawn in: 6 to 10, near the
  /// middle of the stack, picked by the card.
  static int faceUpRound(int faceUp, int handSize) {
    final round = 6 + faceUp % 5;
    return round < handSize ? round : handSize - 1;
  }

  /// [hand]'s cards in the order they are dealt: [faceUp] (if this hand
  /// has it) in its round, the others in an order picked by the hand's
  /// cards (the same for everyone who sees the hand).
  static List<int> _handOrder(List<int> hand, int? faceUp) {
    final sum = hand.fold(0, (n, id) => n + id);
    // 37 and 61 are coprime and every id is under 61: distinct cards get
    // distinct keys, so the order is a proper shuffle of the hand.
    int key(int id) => ((id + 1) * 37 + sum) % 61;
    final rest = [
      for (final id in hand)
        if (id != faceUp) id,
    ]..sort((a, b) => key(a).compareTo(key(b)));
    if (faceUp == null || !hand.contains(faceUp)) return rest;
    return rest..insert(faceUpRound(faceUp, hand.length), faceUp);
  }

  /// The cards [seat] has been dealt once the first [n] of [cards] are out.
  List<int> dealtTo(int seat, int n) => [
    for (final c in cards.take(n))
      if (c.seat == seat) c.id,
  ];
}
