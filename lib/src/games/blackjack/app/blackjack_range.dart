/// The dealer's range: what the face-down hole card could be, from the
/// player's side of the table, and what the dealer's first two cards could
/// add up to.
///
/// It is exact, not sampled: the hole card is equally likely to be any card
/// the player hasn't seen since the shuffle (the rest of the shoe and the
/// hole card itself), except that a dealer who has checked for blackjack
/// and played on can't have one. Each of those cards is one "possible deal"
/// in the range, so the kit's tally turns their counts into chances. Only
/// the player's view is used, never the hole card itself (nor the Training
/// option that shows it), so the sheet tells what a player could work out.
library;

import '../../../kit/range.dart';
import '../blackjack.dart';
import 'blackjack_record.dart';

/// The kinds of two-card dealer hands the range names, in the order shown:
/// a blackjack; 17 to 21 (the dealer stands, though a soft 17 draws at some
/// tables); 12 to 16 (the dealer must draw, and a hard total may bust); 11
/// or less (the dealer draws and can't bust on the next card). Every hand
/// is exactly one of them, so their chances add up to 100%.
const dealerStartKinds = ['blackjack', 'total17to21', 'total12to16', 'total11orLess'];

/// The hole card's ranks, lowest first as players order them (2 to 10,
/// then the ace), each at most once: the dealer has one hole card.
final dealerRankOrder = <(String, int)>[
  for (var r = 1; r < rankCount; r++) (rankName(r), 1),
  (rankName(aceIndex), 1),
];

/// Whether [play] has a dealer's range to show: a round has been dealt at a
/// hole-card table (without one, the dealer's second card comes only after
/// the player has played, so there is nothing hidden to work out). Once the
/// hole card is turned over the range is that card, for sure.
bool dealerRangeShows(BlackjackPlay play) {
  final round = play.round;
  return play.rules.holeCard && round != null && (round.holeCardHidden || round.dealerCards.length >= 2);
}

/// The dealer's range in [play] (see the library comment). Throws when
/// [dealerRangeShows] is false.
OpponentRange dealerRange(BlackjackPlay play) {
  if (!dealerRangeShows(play)) throw StateError('no hole card to work out');
  final view = play.round!.viewFor(playerSeat);
  final up = view.dealerUpcard.rank;
  final List<List<String>> holes;
  if (view.holeCardHidden) {
    final unseen = view.unseenSeen;
    holes = [
      for (var r = 0; r < rankCount; r++)
        // A dealer who checked and played on has no blackjack.
        if (!(view.dealerPeeked && _naturalWith(up, r)))
          for (var i = 0; i < unseen[r]; i++) [rankName(r)],
    ];
  } else {
    // Turned over: everyone has seen it.
    holes = [
      [rankName(view.dealerVisible[1].rank)],
    ];
  }
  return OpponentRange.tally(
    seat: dealerSeat,
    hands: holes,
    rankOrder: dealerRankOrder,
    kinds: dealerStartKinds,
    combosOf: (hole) => dealerStartOf(up, rankIndexOf(hole.single)),
  );
}

/// The kind of the dealer's two cards, [up] and [hole] (rank indexes), with
/// the hand as the range writes it: 'upcard+hole', "6+T".
Map<String, Set<String>> dealerStartOf(int up, int hole) {
  final combo = '${rankName(up)}+${rankName(hole)}';
  final total = totalOf(rankPoints(up) + rankPoints(hole), up == aceIndex || hole == aceIndex).value;
  final kind = _naturalWith(up, hole)
      ? 'blackjack'
      : total >= 17
      ? 'total17to21'
      : total >= 12
      ? 'total12to16'
      : 'total11orLess';
  return {
    kind: {combo},
  };
}

/// An ace and a ten-value card.
bool _naturalWith(int a, int b) => (a == aceIndex && b == tenIndex) || (a == tenIndex && b == aceIndex);
