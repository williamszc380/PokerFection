/// How the player's hand is laid out in the climbing games (Big Two, Fight
/// the Landlord): sorted by rank or by suit, or in the player's own order
/// once they drag a card to a new place. Pure Dart, like the rest of
/// lib/src/kit, so a game's record and tests can use it anywhere.
library;

/// What the hand's Sort button shows: the order the hand is in now.
enum HandOrder {
  rank,
  suit,

  /// The player's own: they dragged a card. The button then sorts again.
  own,
}

/// [cards] with the card at [from] moved to [to], [to] being its place in
/// the result (as `insert(to, removeAt(from))`): moving the first of five
/// cards to the end is `moveCard(cards, 0, 4)`. A new list; [cards] is left
/// as it is.
List<T> moveCard<T>(List<T> cards, int from, int to) {
  RangeError.checkValidIndex(from, cards, 'from');
  RangeError.checkValidIndex(to, cards, 'to');
  final moved = [...cards];
  moved.insert(to, moved.removeAt(from));
  return moved;
}

/// The cards of [hand] in the player's [own] order: cards that left the
/// hand (played) drop out of it, the others keep their places among
/// themselves, and cards new to the order (the kitty, given to the
/// landlord) go at the end, in the order [hand] gives them (the game's
/// sort). Equal cards (two decks) are matched one for one.
List<T> keepOwnOrder<T>(List<T> own, List<T> hand) {
  final left = <T, int>{};
  for (final card in hand) {
    left[card] = (left[card] ?? 0) + 1;
  }
  final kept = <T>[];
  for (final card in own) {
    final n = left[card] ?? 0;
    if (n == 0) continue;
    left[card] = n - 1;
    kept.add(card);
  }
  // The rest of the hand, one copy for each not yet placed.
  final placed = <T, int>{};
  for (final card in kept) {
    placed[card] = (placed[card] ?? 0) + 1;
  }
  for (final card in hand) {
    final n = placed[card] ?? 0;
    if (n > 0) {
      placed[card] = n - 1;
    } else {
      kept.add(card);
    }
  }
  return kept;
}

/// How a player's hand is laid out: the sort they last chose (rank or
/// suit), and their own order once they move a card ([own]); never changed
/// in place. A game keeps
/// one in its record's extra ([toExtra], [fromExtra]) and shows
/// `arrange(sortedHand)`.
class HandArrangement<T> {
  /// Sorted by [sort] (rank or suit).
  const HandArrangement.sorted([this.sort = HandOrder.rank])
      : own = null,
        assert(sort != HandOrder.own);

  /// In the player's own order, [sort] being the sort the button goes back to.
  const HandArrangement.own(this.sort, List<T> this.own) : assert(sort != HandOrder.own);

  /// The sort last chosen: rank or suit (never [HandOrder.own]).
  final HandOrder sort;

  /// The player's order (it keeps cards since played, for the review; see
  /// [moved]); null: sorted.
  final List<T>? own;

  /// What the Sort button shows.
  HandOrder get order => own == null ? sort : HandOrder.own;

  /// The hand as the player sees it: [sorted] (the hand in [sort]'s order)
  /// as it is, or in the player's own order with new cards at its end.
  List<T> arrange(List<T> sorted) => switch (own) {
        null => sorted,
        final own => keepOwnOrder(own, sorted),
      };

  /// After the player drags the card at [from] to [to] in [shown] (the hand
  /// as [arrange] gave it): their own order. Unchanged when the card kept
  /// its place.
  ///
  /// The order keeps the cards played since, each right after the card it
  /// followed: the review lays out every step of the deal with the order
  /// the deal ended with, and a card played before the last drag should
  /// show there where it lay, not at the end. ([arrange] still drops them
  /// from the live hand.) On the first drag, the hand having been sorted,
  /// [whole] gives where those cards lay: every card dealt to the player
  /// this deal, in [sort]'s order.
  HandArrangement<T> moved(List<T> shown, int from, int to, {List<T>? whole}) {
    if (from == to) return this;
    final now = moveCard(shown, from, to);
    final before = own ?? whole;
    return HandArrangement.own(sort, before == null ? now : _withPlayed(before, now));
  }

  /// [now] with the cards of [before] it lacks put back, each right after
  /// the card it followed in [before]. Cards that led [before] (played
  /// before any card still held) go right before the first held card that
  /// came after them, not at the very front: a card the player has since
  /// dragged to the front stays first. Equal cards (two decks) are matched
  /// one for one.
  static List<T> _withPlayed<T>(List<T> before, List<T> now) {
    final left = <T, int>{};
    for (final card in now) {
      left[card] = (left[card] ?? 0) + 1;
    }
    // Each card with whether it is one put back (a played copy of a card
    // still held must not be taken for the held one).
    final cards = [for (final card in now) (card, false)];
    final seen = <T, int>{};
    final leading = <T>[];
    int? at;
    for (final card in before) {
      final n = left[card] ?? 0;
      if (n > 0) {
        left[card] = n - 1;
        // This copy of the card in [now].
        final copy = seen[card] = (seen[card] ?? 0) + 1;
        var found = 0;
        for (var i = 0; i < cards.length; i++) {
          if (!cards[i].$2 && cards[i].$1 == card && ++found == copy) {
            if (at == null && leading.isNotEmpty) {
              cards.insertAll(i, [for (final played in leading) (played, true)]);
              i += leading.length;
              leading.clear();
            }
            at = i + 1;
            break;
          }
        }
      } else if (at == null) {
        leading.add(card);
      } else {
        cards.insert(at, (card, true));
        at++;
      }
    }
    // Nothing held at all: the played cards in their old order.
    cards.insertAll(0, [for (final played in leading) (played, true)]);
    return [for (final (card, _) in cards) card];
  }

  /// What a tap on the Sort button does: Rank and Suit switch; from the
  /// player's own order, back to the sort last chosen.
  HandArrangement<T> get next => own != null
      ? HandArrangement<T>.sorted(sort)
      : HandArrangement<T>.sorted(sort == HandOrder.rank ? HandOrder.suit : HandOrder.rank);

  /// A new deal starts sorted again, by the sort last chosen.
  HandArrangement<T> get dealt => HandArrangement<T>.sorted(sort);

  /// The record's extra: `'sort'` (as today: 'rank' or 'suit') and
  /// `'order'` (each card as [encode] gives it, or null when sorted).
  Map<String, Object?> toExtra(Object Function(T card) encode) => {
        'sort': sort.name,
        'order': own == null ? null : [for (final card in own!) encode(card)],
      };

  /// The arrangement [toExtra] wrote; by rank when [extra] has none. Cards
  /// [decode] doesn't know (null) are left out.
  static HandArrangement<T> fromExtra<T>(Map<String, Object?> extra, T? Function(Object? code) decode) {
    final sort = extra['sort'] == HandOrder.suit.name ? HandOrder.suit : HandOrder.rank;
    final order = extra['order'];
    if (order is! List) return HandArrangement<T>.sorted(sort);
    return HandArrangement<T>.own(sort, [
      for (final code in order)
        if (decode(code) case final T card) card,
    ]);
  }

  @override
  bool operator ==(Object other) =>
      other is HandArrangement<T> && other.sort == sort && _sameList(other.own, own);

  @override
  int get hashCode => Object.hash(sort, own == null ? null : Object.hashAll(own!));

  @override
  String toString() => own == null ? 'HandArrangement(${sort.name})' : 'HandArrangement(own $own, ${sort.name})';

  static bool _sameList<T>(List<T>? a, List<T>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
