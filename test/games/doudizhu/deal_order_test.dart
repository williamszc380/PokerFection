// How a deal goes round the table in the step that opens it (who bids
// first): the cards go out one at a time, seat after seat, the face-up card
// near the middle of the stack, to the seat it decides. Every device that
// sees a hand deals it in the same order, and the order needs nothing a
// device may not see.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';

void main() {
  test('51 cards go round in turn from hand seat 0, each seat getting its own 17', () {
    for (var seed = 0; seed < 60; seed++) {
      final game = DdzGame.deal(random: Random(seed));
      final order = DdzDealOrder.of(game);
      expect(order.cards, hasLength(51));
      for (final (i, c) in order.cards.indexed) {
        expect(c.seat, i % 3, reason: 'card $i goes to the next seat in turn');
      }
      for (var s = 0; s < 3; s++) {
        expect(order.dealtTo(s, 51)..sort(), game.hands[s], reason: 'seat $s gets exactly its hand');
      }
      expect({for (final c in order.cards) c.id}, hasLength(51), reason: 'no card twice, none of the kitty');
      expect(order.cards.map((c) => c.id), isNot(anyElement(isIn(game.kitty))));
    }
  });

  test('the face-up card is dealt near the middle of the stack (round 7 to 11 of 17), to the first bidder', () {
    final rounds = <int>{};
    for (var seed = 0; seed < 200; seed++) {
      final game = DdzGame.deal(random: Random(seed));
      final order = DdzDealOrder.of(game);
      final at = order.faceUpAt!;
      expect(order.cards[at], (seat: game.firstBidder, id: game.faceUp!));
      final round = at ~/ 3;
      expect(round, inInclusiveRange(6, 10));
      expect(round, DdzDealOrder.faceUpRound(game.faceUp!, 17), reason: 'the card itself picks its round');
      rounds.add(round);
    }
    expect(rounds, {6, 7, 8, 9, 10}, reason: 'each round of the middle comes up');
  });

  test('a hand is dealt in the same order whatever the other hands are: a device needs only the cards it sees', () {
    final game = DdzGame.deal(random: Random(5));
    final first = game.firstBidder;
    // The same first bidder's hand, the others' cards swapped with the kitty.
    final others = [
      for (var s = 0; s < 3; s++)
        if (s != first) s,
    ];
    final swapped = [
      for (final h in game.hands) [...h],
    ];
    final out = swapped[others[0]].removeAt(0);
    swapped[others[0]].add(game.kitty[0]);
    final kitty = [out, ...game.kitty.skip(1)];
    final other = DdzGame.fromCards(hands: swapped, kitty: kitty, firstBidder: first, faceUp: game.faceUp);
    expect(DdzDealOrder.of(other).dealtTo(first, 51), DdzDealOrder.of(game).dealtTo(first, 51));
    expect(DdzDealOrder.of(other).faceUpAt, DdzDealOrder.of(game).faceUpAt);
  });

  test('a device that turns the seats deals from the same place: hand seat 0 first, the same cards to each', () {
    for (var seed = 0; seed < 20; seed++) {
      final game = DdzGame.deal(random: Random(seed));
      final plain = DdzDealOrder.of(game);
      for (final base in [1, 2]) {
        // The game as a device at hand seat [base] draws it: that seat is 0.
        int turn(int seat) => (seat - base) % 3;
        final turned = DdzGame.fromCards(
          hands: [for (var d = 0; d < 3; d++) game.hands[(d + base) % 3]],
          kitty: game.kitty,
          firstBidder: turn(game.firstBidder),
          faceUp: game.faceUp,
        );
        final order = DdzDealOrder.of(turned, firstSeat: turn(0));
        expect([for (final c in order.cards) (seat: (c.seat + base) % 3, id: c.id)], plain.cards);
        expect(order.faceUpAt, plain.faceUpAt);
      }
    }
  });

  test('a deal with no face-up card (a set-up deal, an old save) still goes round, with nothing turned up', () {
    final game = DdzGame.fromRanks(hands: ['33344455', '66677788', '99TTTJJJ'], kitty: 'QQK');
    final order = DdzDealOrder.of(game);
    expect(order.faceUpAt, isNull);
    expect(order.faceUp, isNull);
    expect(order.cards, hasLength(24));
    expect([for (final c in order.cards) c.seat], [for (var i = 0; i < 24; i++) i % 3]);
  });
}
