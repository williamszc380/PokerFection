/// The Hi-Lo card count: the running count and the true count.
///
/// Hi-Lo (Harvey Dubner, 1963; Wizard of Odds, "High-Low Card Counting
/// Strategy", https://wizardofodds.com/games/blackjack/card-counting/high-low/)
/// scores each card seen: 2-6 count +1, 7-9 count 0, tens and aces count
/// -1. A high running count means the unseen cards are rich in tens and
/// aces, which helps the player (more blackjacks, more dealer busts). The
/// true count divides by the decks still unseen, so the same running
/// count means more in a nearly finished shoe.
library;

import 'cards.dart';

/// The Hi-Lo value of a card: +1 for 2-6, 0 for 7-9, -1 for tens and aces.
int hiLoValue(Card card) {
  final r = card.rank;
  if (r == aceIndex || r == tenIndex) return -1;
  if (r <= 5) return 1; // 2..6 are rank indexes 1..5
  return 0;
}

/// A Hi-Lo count from some seen cards.
class HiLoCount {
  /// A count of [running] with [unseenCards] cards not yet seen.
  const HiLoCount(this.running, this.unseenCards);

  /// The count after seeing [seen], with [unseenCards] cards still unseen
  /// (the rest of the shoe plus any face-down card).
  factory HiLoCount.of(Iterable<Card> seen, int unseenCards) {
    var rc = 0;
    for (final c in seen) {
      rc += hiLoValue(c);
    }
    return HiLoCount(rc, unseenCards);
  }

  /// The running count: the sum of the seen cards' values.
  final int running;

  /// Cards not yet seen.
  final int unseenCards;

  /// Decks not yet seen (unseen cards / 52).
  double get decksUnseen => unseenCards / 52;

  /// The true count: running count per unseen deck. Counters usually
  /// round it down; [trueCountFloor] does that.
  double get trueCount => unseenCards == 0 ? 0 : running / decksUnseen;

  /// The true count rounded toward minus infinity, as most counters use
  /// it for strategy changes ("index plays").
  int get trueCountFloor => trueCount.floor();

  @override
  String toString() => 'running $running, true ${trueCount.toStringAsFixed(2)}';
}
