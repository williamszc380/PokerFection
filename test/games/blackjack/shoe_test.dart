// The shoe and penetration, the continuous shuffler, what a view may see,
// the Hi-Lo count, and determinism.
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/blackjack/blackjack.dart';

import 'helpers.dart';

void main() {
  group('shoe', () {
    test('a shoe holds every card of its decks once per deck', () {
      final shoe = Shoe(decks: 6, seed: 3);
      expect(shoe.size, 312);
      expect(shoe.cardsLeft, 312);
      expect(shoe.remaining, Composition.decks(6));
      expect(Composition.decks(6)[tenIndex], 96);
      expect(Composition.decks(6)[aceIndex], 24);
    });

    test('the same seed deals the same order; another seed does not', () {
      List<Card> first(int seed) {
        final s = Shoe(decks: 2, seed: seed);
        return [for (var i = 0; i < 20; i++) s.draw()];
      }

      expect(first(5), first(5));
      expect(first(5), isNot(first(6)));
    });

    test('counts per rank go down as cards are dealt', () {
      final shoe = Shoe(decks: 1, seed: 1);
      final c = shoe.draw();
      expect(shoe.remaining[c.rank], (c.rank == tenIndex ? 16 : 4) - 1);
      expect(shoe.dealt, [c]);
    });

    test('the cut card: after the penetration is dealt the next round starts with a shuffle', () {
      final shoe = Shoe(decks: 1, penetration: 0.5, seed: 2);
      expect(shoe.cutCard, 26);
      shoe.startRound();
      for (var i = 0; i < 25; i++) {
        shoe.draw();
      }
      expect(shoe.needsShuffle, isFalse);
      shoe.startRound();
      expect(shoe.shuffles, 1, reason: 'the cut card is not out yet');
      shoe.draw();
      expect(shoe.needsShuffle, isTrue);
      shoe.startRound();
      expect(shoe.shuffles, 2);
      expect(shoe.cardsLeft, 52);
    });

    test('a continuous shuffler deals every round from a full, freshly shuffled shoe', () {
      const csm = BlackjackRules(continuousShuffle: true);
      final table = BlackjackTable(csm, seed: 9);
      for (var i = 0; i < 3; i++) {
        final r = table.deal([1]);
        expect(r.viewFor(0).seenSinceShuffle, r.viewFor(0).seenThisRound, reason: 'nothing earlier to remember');
        while (!r.isOver) {
          r.apply(BlackjackBot(BotLevel.hard).chooseAction(r.viewFor(0)));
        }
      }
      expect(table.shoe.shuffles, 4, reason: 'one at creation and one before each round');
    });

    test('if the shoe runs out mid-round, the cards not on the table are shuffled into a new shoe', () {
      final shoe = Shoe(decks: 1, penetration: 0.99, seed: 4);
      shoe.startRound();
      for (var i = 0; i < 30; i++) {
        shoe.draw();
      }
      shoe.startRound(); // cut card not out: no shuffle
      final onTable = [for (var i = 0; i < 30; i++) shoe.draw()];
      expect(shoe.shuffles, 2, reason: 'the 23rd card of this round needed a reshuffle');
      expect(
        Composition.ofCards(onTable).plus(cardsLeft(shoe)),
        Composition.decks(1),
        reason: 'this round\'s cards plus the rest make exactly one deck',
      );
    });

    test('stacking puts chosen cards on top without changing the counts', () {
      final shoe = Shoe(decks: 1, seed: 1)..stack(cards('As Kd'));
      expect(shoe.remaining, Composition.decks(1));
      expect(shoe.draw(), Card.parse('As'));
      expect(shoe.draw(), Card.parse('Kd'));
      expect(() => shoe.stack(cards('As')), throwsStateError, reason: 'the only ace of spades is gone');
    });
  });

  group('views', () {
    test('a view shows everything except the hole card and the order of the shoe', () {
      final r = stacked(const BlackjackRules(), 'Ts 9s 6h 7s 8s Tc', bets: [1, 1]);
      final v = r.viewFor(1);
      expect(v.dealerVisible, cards('6h'));
      expect(v.holeCardHidden, isTrue);
      expect(v.seenThisRound, cards('Ts 9s 6h 7s 8s'));
      expect(v.seenSinceShuffle, cards('Ts 9s 6h 7s 8s'), reason: 'the hole card (Tc) is not seen');
      expect(v.unseenCount, 312 - 5, reason: 'the shoe plus the hole card');
      expect(v.unseenFresh, shoeWithout(6, 'Ts 9s 6h 7s 8s'));
      expect(v.isMyTurn, isFalse);
      expect(v.legalActions, isEmpty, reason: 'seat 0 acts first');
      expect(r.viewFor(0).legalActions, isNotEmpty);
    });

    test('SEEN knowledge remembers earlier rounds; FRESH only this round', () {
      final table = BlackjackTable(const BlackjackRules(), seed: 11);
      final first = table.deal([1]);
      while (!first.isOver) {
        first.apply(BlackjackAction.stand);
      }
      final earlier = first.dealerCards.length + first.seats[0].hands[0].cards.length;
      final second = table.deal([1]);
      final v = second.viewFor(0);
      expect(v.seenSinceShuffle.length, earlier + v.seenThisRound.length);
      expect(v.unseenSeen.total, 312 - v.seenSinceShuffle.length);
      expect(v.unseenFresh.total, 312 - v.seenThisRound.length);
    });

    test('changing a view cannot change the round', () {
      final r = stacked(const BlackjackRules(), 'Ts 6h 7s Tc');
      final v = r.viewFor(0);
      expect(() => v.seats.add(v.seats.first), throwsUnsupportedError);
      expect(() => v.seats[0].hands[0].cards.add(Card.parse('2c')), throwsUnsupportedError);
    });
  });

  group('Hi-Lo count', () {
    test('2-6 count +1, 7-9 count 0, tens and aces count -1', () {
      expect([for (final c in cards('2c 6d 7h 9s Tc Kd As')) hiLoValue(c)], [1, 1, 0, 0, -1, -1, -1]);
    });

    test('the true count is the running count per unseen deck', () {
      final c = HiLoCount.of(cards('2c 3c 4c 5c 6c 2d'), 156);
      expect(c.running, 6);
      expect(c.decksUnseen, 3);
      expect(c.trueCount, 2);
      expect(const HiLoCount(-5, 104).trueCountFloor, -3);
    });

    test('a view counts every card seen since the shuffle, but not the face-down hole card', () {
      final r = stacked(const BlackjackRules(), '2s 6h 3s Kc');
      final v = r.viewFor(0);
      expect(v.count.running, 3, reason: '2, 6 and 3 seen; the king is the hole card');
      expect(v.count.unseenCards, 312 - 3);
    });
  });

  group('determinism', () {
    test('the same seed and bots give the same rounds, card for card', () {
      List<double> run(int seed) {
        final table = BlackjackTable(const BlackjackRules(), seed: seed);
        final bots = [BlackjackBot(BotLevel.easy), BlackjackBot(BotLevel.medium), BlackjackBot(BotLevel.hard)];
        final out = <double>[];
        for (var i = 0; i < 200; i++) {
          final r = table.deal([1, 2, 3]);
          while (!r.isOver) {
            r.apply(bots[r.turn!.seat].chooseAction(r.viewFor(r.turn!.seat)));
          }
          out.addAll([for (var s = 0; s < 3; s++) r.result(s).net]);
        }
        return out;
      }

      expect(run(21), run(21));
      expect(run(21), isNot(run(22)));
    });
  });
}

/// The cards left in [shoe], as a list (for counting).
List<Card> cardsLeft(Shoe shoe) {
  final c = shoe.copy();
  return [for (var i = c.cardsLeft; i > 0; i--) c.draw()];
}
