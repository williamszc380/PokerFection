// The rules of a round: dealing, dealer play, blackjacks, peeking and no
// hole card, insurance, splitting, doubling, surrender and settlement.
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/blackjack/blackjack.dart';

import 'helpers.dart';

const stand = BlackjackAction.stand;
const hit = BlackjackAction.hit;
const dbl = BlackjackAction.double;
const split = BlackjackAction.split;
const surrender = BlackjackAction.surrender;
const insure = BlackjackAction.insurance;
const noInsure = BlackjackAction.noInsurance;
const keepPlaying = BlackjackAction.keepPlaying;

void main() {
  const standard = BlackjackRules();

  group('dealing', () {
    test('cards go round as at a table: seats, upcard, seats again, then the hole card', () {
      final r = stacked(standard, 'Ts 9s 6h 7s 8s Tc', bets: [10, 20]);
      expect(r.seats[0].hands[0].cards, cards('Ts 7s'));
      expect(r.seats[1].hands[0].cards, cards('9s 8s'));
      expect(r.dealerUpcard, Card.parse('6h'));
      expect(r.dealerCards, cards('6h Tc'));
      expect(r.dealerVisible, cards('6h'), reason: 'the hole card is face down');
      expect(r.turn, const Turn(0, 0));
    });

    test('without a hole card the dealer gets one card until the players are done', () {
      final r = stacked(standard.copyWith(holeCard: false), 'Ts 6h 7s');
      expect(r.dealerCards, cards('6h'));
      expect(r.holeCardHidden, isFalse);
    });

    test('seats act in order, first base first, and each seat is settled on its own bet', () {
      final r = stacked(standard, 'Ts 9s 6h 7s 8s Tc 5c', bets: [10, 20]);
      expect(r.turn, const Turn(0, 0));
      r.apply(stand);
      expect(r.turn, const Turn(1, 0));
      r.apply(stand);
      expect(r.isOver, isTrue);
      expect(r.dealerCards, cards('6h Tc 5c'));
      expect(r.result(0).net, -10);
      expect(r.result(1).net, -20);
    });

    test('an illegal action is refused, and copy() gives an independent round', () {
      final r = stacked(standard, 'Ts 6h 7s Tc 5c');
      expect(() => r.apply(insure), throwsStateError);
      final c = r.copy();
      c.apply(hit);
      expect(c.seats[0].hands[0].cards, hasLength(3));
      expect(r.seats[0].hands[0].cards, hasLength(2), reason: 'the original is untouched');
      expect(r.shoe.cardsLeft, c.shoe.cardsLeft + 1);
    });

    test('1 to 7 seats, bets of at least 1', () {
      expect(() => BlackjackRound.deal(standard, Shoe(decks: 6), []), throwsArgumentError);
      expect(() => BlackjackRound.deal(standard, Shoe(decks: 6), List.filled(8, 1)), throwsArgumentError);
      expect(() => BlackjackRound.deal(standard, Shoe(decks: 6), [0]), throwsArgumentError);
      expect(BlackjackRound.deal(standard, Shoe(decks: 6), List.filled(7, 5)).seats, hasLength(7));
    });
  });

  group('dealer play', () {
    test('the dealer stands on soft 17 (S17) and hits it (H17)', () {
      final s17 = stacked(standard, 'Ts 6h 9s Ac 3d')..apply(stand);
      expect(s17.dealerCards, cards('6h Ac'));
      expect(s17.result(0).net, 10, reason: '19 beats 17');
      final h17 = stacked(standard.copyWith(dealerHitsSoft17: true), 'Ts 6h 9s Ac 3d')..apply(stand);
      expect(h17.dealerCards, cards('6h Ac 3d'));
      expect(h17.result(0).net, -10, reason: 'soft 20 beats 19');
    });

    test('the dealer draws to 17 and can bust', () {
      final r = stacked(standard, 'Ts 6h 8s Tc 9d')..apply(stand);
      expect(r.seats[0].hands[0].outcome, HandOutcome.win);
      expect(r.result(0).net, 10);
    });

    test('the dealer does not draw when every hand has busted', () {
      final r = stacked(standard, 'Ts 6h 6s Tc Kd 5h')..apply(hit);
      expect(r.isOver, isTrue);
      expect(r.dealerCards, cards('6h Tc'));
      expect(r.seats[0].hands[0].outcome, HandOutcome.bust);
      expect(r.result(0).net, -10);
    });

    test('a hand that reaches 21 stands by itself', () {
      final r = stacked(standard, 'Ts 9s 6h 5s 8s Tc 6d', bets: [10, 10]);
      expect(r.seats[0].hands[0].cards, cards('Ts 5s'));
      r.apply(hit); // Ts 5s 6d = 21
      expect(r.seats[0].hands[0].done, isTrue);
      expect(r.turn, const Turn(1, 0));
    });
  });

  group('blackjack', () {
    test('a blackjack pays 3 to 2, or 6 to 5, or 1 to 1, and needs no decisions', () {
      for (final (payout, win) in [
        (BlackjackPayout.threeToTwo, 15.0),
        (BlackjackPayout.sixToFive, 12.0),
        (BlackjackPayout.oneToOne, 10.0),
      ]) {
        final r = stacked(standard.copyWith(payout: payout), 'As 9h Kd 7c');
        expect(r.isOver, isTrue);
        expect(r.seats[0].hands[0].outcome, HandOutcome.blackjack);
        expect(r.result(0).net, win);
        expect(r.dealerCards, cards('9h 7c'), reason: 'nobody left to beat: the dealer does not draw');
      }
    });

    test('21 after splitting aces is not a blackjack: it pays 1 to 1', () {
      final r = stacked(standard, 'As 9h Ad 7c Kh Kc 2d')..apply(split);
      expect(r.isOver, isTrue, reason: 'split aces take one card each');
      for (final h in r.seats[0].hands) {
        expect(h.total.value, 21);
        expect(h.isBlackjack, isFalse);
        expect(h.outcome, HandOutcome.win);
      }
      expect(r.result(0).net, 20);
    });

    test('a blackjack against a dealer blackjack is a push', () {
      final r = stacked(standard.copyWith(insurance: false), 'As Ah Kd Kc');
      expect(r.isOver, isTrue);
      expect(r.seats[0].hands[0].outcome, HandOutcome.push);
      expect(r.result(0).net, 0);
    });
  });

  group('peek and no hole card', () {
    test('with an ace up the dealer peeks after insurance; a blackjack ends the round before anyone plays', () {
      final r = stacked(standard, 'Ts As 7s Kc');
      expect(r.phase, RoundPhase.insurance);
      r.apply(noInsure);
      expect(r.isOver, isTrue);
      expect(r.dealerVisible, cards('As Kc'));
      expect(r.seats[0].hands[0].outcome, HandOutcome.dealerBlackjack);
      expect(r.result(0).net, -10);
    });

    test('with a ten up the dealer peeks at once', () {
      final r = stacked(standard, 'Ts Kh 7s Ac');
      expect(r.isOver, isTrue);
      expect(r.result(0).net, -10);
      final noBj = stacked(standard, 'Ts Kh 7s 9c');
      expect(noBj.phase, RoundPhase.playing);
      expect(noBj.dealerPeeked, isTrue);
      expect(noBj.holeCardHidden, isTrue);
    });

    test('no hole card: a dealer blackjack takes doubles too, unless only original bets lose', () {
      final allBets = standard.copyWith(holeCard: false);
      final r = stacked(allBets, '5s Th 6s 9c Ad')..apply(dbl);
      expect(r.dealerCards, cards('Th Ad'));
      expect(r.result(0).net, -20);
      final obo = stacked(allBets.copyWith(noHoleCardLoss: NoHoleCardLoss.originalBetsOnly), '5s Th 6s 9c Ad')
        ..apply(dbl);
      expect(obo.result(0).net, -10);
    });

    test('no hole card: a dealer blackjack takes split hands too, unless only original bets lose', () {
      final allBets = standard.copyWith(holeCard: false);
      final r = stacked(allBets, '8s Th 8d 3c 2c Ad');
      play(r, [split, stand, stand]);
      expect(r.seats[0].hands, hasLength(2));
      expect(r.result(0).net, -20);
      final obo = stacked(allBets.copyWith(noHoleCardLoss: NoHoleCardLoss.originalBetsOnly), '8s Th 8d 3c 2c Ad');
      play(obo, [split, stand, stand]);
      expect(obo.result(0).net, -10);
    });

    test('no hole card: a player blackjack waits for the dealer\'s second card', () {
      final nhc = standard.copyWith(holeCard: false);
      expect(stacked(nhc, 'As Th Kd Ac').result(0).net, 0);
      expect(stacked(nhc, 'As Th Kd 7c').result(0).net, 15);
    });
  });

  group('insurance and even money', () {
    test('insurance costs half the bet and pays 2 to 1 against a blackjack', () {
      final r = stacked(standard, 'Ts As 9s Kc')..apply(insure);
      expect(r.isOver, isTrue);
      final res = r.result(0);
      expect(res.insuranceNet, 10);
      expect(res.net, 0, reason: 'the hand loses 10, insurance wins 10');
    });

    test('insurance is lost when the dealer has no blackjack, and play goes on', () {
      final r = stacked(standard, 'Ts As 9s 7c')..apply(insure);
      expect(r.phase, RoundPhase.playing);
      r.apply(stand);
      final res = r.result(0);
      expect(res.insuranceNet, -5);
      expect(res.net, 5, reason: '19 beats soft 18 (+10), insurance -5');
    });

    test('even money: a blackjack against an ace is paid 1 to 1 whatever the dealer has', () {
      final r = stacked(standard, 'As Ad Kh 7c');
      expect(r.viewFor(0).offersEvenMoney, isTrue);
      r.apply(insure);
      expect(r.result(0).net, 10);
      final r2 = stacked(standard, 'As Ad Kh Kc')..apply(insure);
      expect(r2.result(0).net, 10);
      final declined = stacked(standard, 'As Ad Kh 7c')..apply(noInsure);
      expect(declined.result(0).net, 15);
    });

    test('at 6:5 and 1:1 insuring a blackjack is plain insurance, not "even money"', () {
      // Las Vegas Advisor, "Even money at 6-5 blackjack": insuring a 6:5
      // blackjack nets +7 on 10 when the dealer has no blackjack.
      for (final (payout, net) in [(BlackjackPayout.sixToFive, 7.0), (BlackjackPayout.oneToOne, 5.0)]) {
        final rules = standard.copyWith(payout: payout);
        final r = stacked(rules, 'As Ad Kh 7c');
        expect(r.phase, RoundPhase.insurance, reason: 'insurance is still offered');
        expect(r.viewFor(0).offersEvenMoney, isFalse, reason: payout.name);
        r.apply(insure);
        expect(r.result(0).net, net, reason: '${payout.name}: the blackjack wins, the insurance loses 5');
      }
    });

    test('insurance is not offered when the rules turn it off, or without an ace up', () {
      expect(stacked(standard.copyWith(insurance: false), 'Ts As 9s 7c').phase, RoundPhase.playing);
      expect(stacked(standard, 'Ts Kh 9s 7c').phase, RoundPhase.playing);
    });

    test('every seat is asked in turn', () {
      final r = stacked(standard, 'Ts 9s As 9h 8h 7c', bets: [10, 10]);
      expect(r.turn, const Turn(0, 0));
      r.apply(insure);
      expect(r.turn, const Turn(1, 0));
      expect(r.phase, RoundPhase.insurance);
      r.apply(noInsure);
      expect(r.phase, RoundPhase.playing);
      expect(r.seats[0].insurance, isTrue);
      expect(r.seats[1].insurance, isFalse);
    });
  });

  group('splitting', () {
    test('pairs split up to four hands, each with its own bet, played in order', () {
      final r = stacked(standard, '8s 6h 8d Tc 8c 8h 3c 2d 4s Kc 9d');
      r.apply(split); // 8s | 8d, the first gets 8c
      expect(r.seats[0].hands[0].cards, cards('8s 8c'));
      expect(r.legalActions(), contains(split));
      r.apply(split); // 8s 8h | 8c | 8d
      r.apply(split); // 8s 3c | 8h | 8c | 8d
      expect(r.seats[0].hands, hasLength(4));
      expect(r.seats[0].hands[0].cards, cards('8s 3c'));
      expect(r.legalActions(), isNot(contains(split)));
      play(r, [stand, stand, stand, stand]);
      expect([for (final h in r.seats[0].hands) h.total.value], [11, 10, 12, 18]);
      expect(r.dealerCards, cards('6h Tc 9d'));
      expect(r.result(0).net, 40);
    });

    test('split to 2 hands only: no resplitting', () {
      final r = stacked(standard.copyWith(maxHands: 2), '8s 6h 8d Tc 8c')..apply(split);
      expect(r.seats[0].hands[0].cards, cards('8s 8c'));
      expect(r.legalActions(), isNot(contains(split)));
      final none = stacked(standard.copyWith(maxHands: 1), '8s 6h 8d Tc');
      expect(none.legalActions(), isNot(contains(split)));
    });

    test('any two ten-value cards are a pair', () {
      expect(stacked(standard, 'Ks 6h Qd Tc').legalActions(), contains(split));
    });

    test('split aces get one card each', () {
      final r = stacked(standard, 'As 6h Ad Tc 5c 9d 9s')..apply(split);
      expect(r.isOver, isTrue);
      expect([for (final h in r.seats[0].hands) h.cards.length], [2, 2]);
      expect(r.result(0).net, 20);
    });

    test('a split ace that draws another ace can be split again only with resplit aces', () {
      final no = stacked(standard, 'As 6h Ad Tc Ac 9d 2c 9s')..apply(split);
      expect(no.seats[0].hands, hasLength(2));
      expect(no.seats[0].hands[0].cards, cards('As Ac'));
      expect(no.isOver, isTrue, reason: 'soft 12 stands: one card only');
      final rsa = stacked(standard.copyWith(resplitAces: true), 'As 6h Ad Tc Ac 9d 2c 9s')..apply(split);
      expect(rsa.legalActions(), [stand, split]);
      rsa.apply(split);
      expect(rsa.seats[0].hands, hasLength(3));
    });

    test('split aces can be hit (and doubled after split) only when the rules allow it', () {
      final r = stacked(standard.copyWith(hitSplitAces: true), 'As 6h Ad Tc 5c')..apply(split);
      expect(r.legalActions(), containsAll([stand, hit, dbl]));
      final noDas = stacked(standard.copyWith(hitSplitAces: true, doubleAfterSplit: false), 'As 6h Ad Tc 5c')
        ..apply(split);
      expect(noDas.legalActions(), [stand, hit]);
    });
  });

  group('doubling', () {
    test('a double takes exactly one card on twice the bet', () {
      final r = stacked(standard, '5s 6h 6s Tc 9c 5d')..apply(dbl);
      expect(r.seats[0].hands[0].cards, cards('5s 6s 9c'));
      expect(r.seats[0].hands[0].stake, 20);
      expect(r.dealerCards, cards('6h Tc 5d'));
      expect(r.result(0).net, -20, reason: 'dealer 21 beats 20');
    });

    test('doubling on any two, on 9-11 only, or on 10-11 only', () {
      const soft17 = 'As 6h 6s Tc';
      const hard9 = '4s 6h 5s Tc';
      const hard8 = '3s 6h 5s Tc';
      const hard11 = '5s 6h 6s Tc';
      bool canDouble(BlackjackRules rules, String deal) => stacked(rules, deal).legalActions().contains(dbl);
      expect(canDouble(standard, soft17), isTrue);
      expect(canDouble(standard, hard8), isTrue);
      final reno = standard.copyWith(doubling: DoubleRule.nineToEleven);
      expect(
        [canDouble(reno, soft17), canDouble(reno, hard8), canDouble(reno, hard9), canDouble(reno, hard11)],
        [false, false, true, true],
      );
      final euro = standard.copyWith(doubling: DoubleRule.tenToEleven);
      expect([canDouble(euro, hard9), canDouble(euro, hard11)], [false, true]);
    });

    test('no doubling after three cards, and after a split only with double after split', () {
      final r = stacked(standard, '2s 6h 3s Tc 4d')..apply(hit);
      expect(r.legalActions(), [stand, hit]);
      final das = stacked(standard, '8s 6h 8d Tc 3c')..apply(split);
      expect(das.legalActions(), contains(dbl));
      final noDas = stacked(standard.copyWith(doubleAfterSplit: false), '8s 6h 8d Tc 3c')..apply(split);
      expect(noDas.legalActions(), isNot(contains(dbl)));
    });
  });

  group('surrender', () {
    test('no surrender unless the rules offer it', () {
      expect(stacked(standard, '9s Th 7s 8c').legalActions(), isNot(contains(surrender)));
    });

    test('late surrender: half the bet back, on the first two cards only, not after a split', () {
      final late = standard.copyWith(surrender: Surrender.late);
      final r = stacked(late, '9s Th 7s 8c');
      expect(r.legalActions(), contains(surrender));
      r.apply(surrender);
      expect(r.isOver, isTrue);
      expect(r.seats[0].hands[0].outcome, HandOutcome.surrender);
      expect(r.result(0).net, -5);
      final afterHit = stacked(late, '2s Th 3s 8c 4d')..apply(hit);
      expect(afterHit.legalActions(), isNot(contains(surrender)));
      final afterSplit = stacked(late, '8s Th 8d 7c 3c')..apply(split);
      expect(afterSplit.legalActions(), isNot(contains(surrender)));
    });

    test('early surrender comes before the peek: half back even against a blackjack', () {
      final early = standard.copyWith(surrender: Surrender.early);
      final r = stacked(early, 'Ts As 6s Kc');
      expect(r.phase, RoundPhase.earlySurrender);
      expect(r.legalActions(), [surrender, keepPlaying]);
      r.apply(surrender);
      expect(r.isOver, isTrue, reason: 'the only seat surrendered, so no insurance offer; the dealer has blackjack');
      expect(r.result(0).net, -5);
    });

    test('early surrender declined: insurance, the peek, then play without surrender', () {
      final early = standard.copyWith(surrender: Surrender.early);
      final r = stacked(early, 'Ts As 6s 7c')..apply(keepPlaying);
      expect(r.phase, RoundPhase.insurance);
      r.apply(noInsure);
      expect(r.phase, RoundPhase.playing);
      expect(r.legalActions(), isNot(contains(surrender)));
      final vsSix = stacked(early, 'Ts 6h 6s 7c');
      expect(vsSix.phase, RoundPhase.playing, reason: 'no peek against a 6, so surrender is a normal first play');
      expect(vsSix.legalActions(), contains(surrender));
    });

    test('late surrender without a hole card only counts if the dealer has no blackjack', () {
      final nhc = standard.copyWith(holeCard: false, surrender: Surrender.late);
      expect((stacked(nhc, '9s Th 7s Ac')..apply(surrender)).result(0).net, -10);
      expect((stacked(nhc, '9s Th 7s 5c')..apply(surrender)).result(0).net, -5);
      final earlyNhc = standard.copyWith(holeCard: false, surrender: Surrender.early);
      expect((stacked(earlyNhc, '9s Th 7s Ac')..apply(surrender)).result(0).net, -5);
    });
  });
}
