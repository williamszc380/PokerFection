import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/kit/hand_order.dart';

void main() {
  group('moving a card', () {
    const hand = ['3', '4', '5', '6', '7'];

    test('first to last, last to first, and within the middle; the card lands at the place given', () {
      expect(moveCard(hand, 0, 4), ['4', '5', '6', '7', '3']);
      expect(moveCard(hand, 4, 0), ['7', '3', '4', '5', '6']);
      expect(moveCard(hand, 1, 3), ['3', '5', '6', '4', '7']);
      expect(moveCard(hand, 3, 1), ['3', '6', '4', '5', '7']);
    });

    test('to its own place is the same hand, and the hand given is never changed', () {
      expect(moveCard(hand, 2, 2), hand);
      final mine = [...hand];
      moveCard(mine, 0, 4);
      expect(mine, hand);
    });

    test('a place outside the hand is an error', () {
      expect(() => moveCard(hand, 0, 5), throwsRangeError);
      expect(() => moveCard(hand, -1, 0), throwsRangeError);
    });
  });

  group("keeping the player's own order", () {
    test('played cards drop out; the rest keep their places among themselves', () {
      expect(keepOwnOrder(['K', '3', 'A', '7', '5'], ['3', '5', '7', 'K']), ['K', '3', '7', '5']);
    });

    test("new cards (the kitty) go at the end, in the order the game's sort gives them", () {
      expect(keepOwnOrder(['K', '3', '7'], ['2', '3', '7', '9', 'K']), ['K', '3', '7', '2', '9']);
    });

    test('equal cards (two decks) are matched one for one', () {
      expect(keepOwnOrder(['Q', '4', 'Q'], ['4', 'Q']), ['Q', '4'], reason: 'one queen played');
      expect(keepOwnOrder(['Q', '4'], ['4', 'Q', 'Q']), ['Q', '4', 'Q'], reason: 'a second queen arrives');
    });
  });

  group('a hand arrangement', () {
    // The hand as the game sorts it (by rank here).
    const sorted = ['3', '5', '8', 'J', 'A'];

    test('sorted, it shows the sort; it shows the hand as the game sorted it', () {
      const rank = HandArrangement<String>.sorted();
      expect(rank.order, HandOrder.rank);
      expect(rank.arrange(sorted), sorted);
      expect(const HandArrangement<String>.sorted(HandOrder.suit).order, HandOrder.suit);
    });

    test("after a drag the order is the player's own, and the button reads Sort", () {
      final own = const HandArrangement<String>.sorted(HandOrder.suit).moved(sorted, 4, 0);
      expect(own.order, HandOrder.own);
      expect(own.arrange(sorted), ['A', '3', '5', '8', 'J']);
      expect(own.sort, HandOrder.suit, reason: 'Sort goes back to the sort last chosen');
    });

    test('a drag that leaves the card in its place changes nothing', () {
      const rank = HandArrangement<String>.sorted();
      expect(rank.moved(sorted, 2, 2), same(rank));
    });

    test('the button: Rank and Suit switch; from the own order, back to the sort last chosen', () {
      const rank = HandArrangement<String>.sorted();
      expect(rank.next.order, HandOrder.suit);
      expect(rank.next.next.order, HandOrder.rank);
      final own = rank.next.moved(sorted, 0, 2);
      expect(own.next, const HandArrangement<String>.sorted(HandOrder.suit));
    });

    test('playing cards and getting the kitty keep the own order, new cards at its end', () {
      final own = const HandArrangement<String>.sorted().moved(sorted, 4, 0); // A 3 5 8 J
      expect(own.arrange(['3', '8', 'J']), ['3', '8', 'J'], reason: 'the ace and the 5 played');
      expect(own.arrange(['3', '8', 'J', 'A']), ['A', '3', '8', 'J']);
      expect(own.arrange(['2', '3', '5', '8', 'J', 'K', 'A']), ['A', '3', '5', '8', 'J', '2', 'K']);
    });

    group('for the review (every step laid out with the order the deal ended with)', () {
      test('a card played before the last drag keeps its place among its neighbours', () {
        var a = const HandArrangement<int>.sorted().moved([1, 2, 3, 4, 5], 4, 0); // 5 1 2 3 4
        // The 2 is played (5 1 3 4 left), then the 4 goes next to the 5.
        a = a.moved(a.arrange([1, 3, 4, 5]), 3, 1);
        expect(a.arrange([1, 3, 4, 5]), [5, 4, 1, 3], reason: 'the live hand: the 2 is gone');
        expect(a.arrange([1, 2, 3, 4, 5]), [5, 4, 1, 2, 3], reason: 'a step before the 2 was played');
      });

      test('on the first drag, the cards dealt place the cards played while the hand was sorted', () {
        // Sorted 3 5 8 J A; the 5 is played; then the ace goes first.
        final a = const HandArrangement<String>.sorted().moved(['3', '8', 'J', 'A'], 3, 0, whole: sorted);
        expect(a.arrange(['3', '8', 'J', 'A']), ['A', '3', '8', 'J']);
        expect(a.arrange(sorted), ['A', '3', '5', '8', 'J']);
        expect(
          const HandArrangement<String>.sorted().moved(['3', '8', 'J', 'A'], 3, 0).arrange(sorted),
          ['A', '3', '8', 'J', '5'],
          reason: 'without the cards dealt, the 5 can only go at the end',
        );
      });

      test('a card that led goes back before the card that followed it; equal cards (two decks) one for one', () {
        var a = const HandArrangement<String>.sorted().moved(['3', '5', '5', '8'], 3, 1); // 3 8 5 5
        // A 3 and one 5 are played; the 8 moves to the end.
        a = a.moved(['8', '5'], 0, 1);
        expect(a.arrange(['5', '8']), ['5', '8']);
        expect(a.own, ['5', '5', '3', '8'], reason: 'the 3 before the 8 it led, the played 5 after the 5 it followed');
        expect(a.arrange(['3', '5', '5', '8']), ['5', '5', '3', '8']);
      });

      test('cards that led stay behind a card since dragged to the front', () {
        // Sorted 3 4 5 6 7; the 3 and 4 are played; the 7 goes to the front.
        final a = const HandArrangement<int>.sorted().moved([5, 6, 7], 2, 0, whole: [3, 4, 5, 6, 7]);
        expect(a.arrange([5, 6, 7]), [7, 5, 6]);
        expect(a.arrange([3, 4, 5, 6, 7]), [7, 3, 4, 5, 6], reason: 'only the card dragged has moved');
      });

      test('the kitty, never shown before the drag, still goes at the end until moved', () {
        final a = const HandArrangement<String>.sorted().moved(['3', '5', '8'], 2, 0, whole: ['3', '5', '8']);
        expect(a.arrange(['3', '5', '8', 'J', 'A']), ['8', '3', '5', 'J', 'A']);
      });
    });

    test('a new deal starts sorted, by the sort last chosen', () {
      final own = const HandArrangement<String>.sorted(HandOrder.suit).moved(sorted, 0, 3);
      expect(own.dealt, const HandArrangement<String>.sorted(HandOrder.suit));
    });

    test("kept in the record's extra: 'sort' as before, and the own order", () {
      final own = const HandArrangement<String>.sorted(HandOrder.suit).moved(sorted, 4, 0);
      final extra = own.toExtra((card) => card.toLowerCase());
      expect(extra, {
        'sort': 'suit',
        'order': ['a', '3', '5', '8', 'j'],
      });
      expect(HandArrangement.fromExtra<String>(extra, (code) => (code as String).toUpperCase()), own);
      expect(const HandArrangement<String>.sorted().toExtra((c) => c), {'sort': 'rank', 'order': null});
    });

    test("an older record (only 'sort', or nothing) reads as it did; unknown cards are left out", () {
      String? decode(Object? code) => code is String && code != '?' ? code : null;
      expect(HandArrangement.fromExtra<String>({'sort': 'suit'}, decode), const HandArrangement<String>.sorted(HandOrder.suit));
      expect(HandArrangement.fromExtra<String>({}, decode), const HandArrangement<String>.sorted());
      expect(
        HandArrangement.fromExtra<String>({
          'sort': 'rank',
          'order': ['A', '?', '3'],
        }, decode).own,
        ['A', '3'],
      );
    });
  });
}
