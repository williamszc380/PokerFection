// The exact solver: every play's expected value, checked against Wizard of
// Odds' combinatorial tables ("Blackjack Appendix 9", e.g.
// https://wizardofodds.com/games/blackjack/appendix/9/6ds17r4/: 6 decks,
// S17, resplit to 4 hands except aces, no drawing to split aces; values
// after the dealer has peeked, or with no hole card for the "euro" tables),
// plus insurance, surrender and the no-hole-card rules.
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/blackjack/blackjack.dart';

import 'helpers.dart';

/// One published row: decks, no hole card, upcard, player cards, then
/// stand, hit, double and (pairs) split without and with double after split.
typedef Row = (int, bool, String, String, double, double, double, double?, double?);

const List<Row> appendix9 = [
  // 6 decks, S17 (appendix/9/6ds17r4).
  (6, false, 'A', '6 5', -0.661883, 0.147596, 0.129710, null, null),
  (6, false, 'A', '7 A', -0.100278, -0.095345, -0.362306, null, null),
  (6, false, 'A', 'T 6', -0.664825, -0.515800, -1.031600, null, null),
  (6, false, '2', '7 A', 0.124001, 0.063289, 0.120980, null, null),
  (6, false, '3', '7 A', 0.151119, 0.090730, 0.179330, null, null),
  (6, false, '4', '4 2', -0.204896, -0.069987, -0.389655, null, null),
  (6, false, '5', '6 5', -0.156277, 0.320645, 0.641289, null, null),
  (6, false, '6', 'T 2', -0.154694, -0.168756, -0.337513, null, null),
  (6, false, '7', '9 3', -0.477959, -0.218241, -0.518061, null, null),
  (6, false, '9', '7 A', -0.182640, -0.098469, -0.284825, null, null),
  (6, false, 'T', '6 5', -0.541929, 0.118582, 0.178451, null, null),
  (6, false, 'T', '9 7', -0.536809, -0.535392, -1.070784, null, null),
  (6, false, 'T', 'T 6', -0.540954, -0.534676, -1.069351, null, null),
  (6, false, 'A', 'A A', -0.666458, -0.022206, -0.620238, 0.127144, 0.127144),
  (6, false, 'A', '8 8', -0.663258, -0.513551, -1.027102, -0.364371, -0.364371),
  (6, false, '2', '2 2', -0.292530, -0.114739, -0.585060, -0.153361, -0.077684),
  (6, false, '5', '4 4', -0.156310, 0.083624, 0.027678, -0.020168, 0.111900),
  (6, false, '6', 'A A', -0.145699, 0.187973, 0.190709, 0.682366, 0.682366),
  (6, false, '6', '6 6', -0.154706, -0.173833, -0.347667, -0.001979, 0.158580),
  (6, false, '6', '9 9', 0.280805, -0.604091, -1.208183, 0.404149, 0.464217),
  (6, false, '7', '9 9', 0.399576, -0.587176, -1.174353, 0.334523, 0.364180),
  (6, false, 'T', '8 8', -0.536853, -0.535361, -1.070722, -0.486276, -0.475385),
  // 2 decks, S17 (appendix/9/2ds17r4): the famous soft 18 against an ace.
  (2, false, 'A', '7 A', -0.100502, -0.100359, -0.360929, null, null),
  (2, false, '6', 'T 6', -0.165609, -0.414113, -0.828226, null, null),
  (2, false, 'T', 'T 6', -0.541889, -0.523992, -1.047984, null, null),
  (2, false, 'A', '8 8', -0.655627, -0.506225, -1.012450, -0.347646, -0.347342),
  (2, false, '6', '9 9', 0.275070, -0.597222, -1.194444, 0.389154, 0.448563),
  // 6 decks, S17, no hole card: every bet loses to a dealer blackjack
  // (appendix/9/euro-6ds17r4).
  (6, true, 'A', '6 5', -0.766929, -0.208939, -0.531948, null, null),
  (6, true, '6', '6 5', -0.150826, 0.341332, 0.682665, null, null),
  (6, true, 'T', '6 5', -0.577507, 0.031702, 0.009251, null, null),
  (6, true, 'A', '8 8', -0.767877, -0.664681, double.nan, -0.922843, -0.922843),
  (6, true, '6', '8 8', -0.157495, -0.425486, double.nan, 0.292983, 0.405899),
  (6, true, 'T', 'A A', -0.571633, -0.132786, -0.612973, 0.026636, 0.026636),
  (6, true, 'T', '8 8', -0.572826, -0.571450, double.nan, -0.616453, -0.616453),
];

Card card(String rank, int suit) => ofRank(rankIndexOf(rank), suit);

void main() {
  group('against Wizard of Odds appendix 9', () {
    for (final row in appendix9) {
      final (decks, nhc, up, hand, stand, hit, dbl, splitNoDas, splitDas) = row;
      test('$decks decks${nhc ? ', no hole card' : ''}: $hand against ${up == 'T' ? '10' : up}', () {
        final ranks = hand.split(' ');
        final player = [for (var i = 0; i < 2; i++) card(ranks[i], i)];
        final upCard = card(up, 2);
        final unseen = Composition.decks(decks).without([...player, upCard]);
        for (final das in [false, true]) {
          final rules = BlackjackRules(decks: decks, doubleAfterSplit: das, holeCard: !nhc);
          final v = EvCalculator(rules, unseen, upCard.rank).playValues(HandSpot.ofCards(player));
          expect(v[BlackjackAction.stand], closeTo(stand, 2e-6));
          expect(v[BlackjackAction.hit], closeTo(hit, 2e-6));
          if (!dbl.isNaN) expect(v[BlackjackAction.double], closeTo(dbl, 2e-6));
          final split = das ? splitDas : splitNoDas;
          if (split != null) {
            expect(v[BlackjackAction.split], closeTo(split, 0.001), reason: 'splits use the documented approximation');
          }
        }
      });
    }
  });

  group('insurance and surrender', () {
    test('insurance is worth 0.5 × (3p − 1): a loser unless over a third of the unseen cards are tens', () {
      final unseen = shoeWithout(6, 'Ts 9s Ah');
      final calc = EvCalculator(const BlackjackRules(), unseen, aceIndex);
      final p = 95 / 309; // one ten among the seen cards
      expect(calc.dealerBlackjackChance, closeTo(p, 1e-12));
      expect(calc.insuranceValue(), closeTo(0.5 * (3 * p - 1), 1e-12));
      expect(calc.insuranceValue(), lessThan(0));
      final rich = EvCalculator(const BlackjackRules(), Composition([4, 4, 4, 4, 4, 4, 4, 4, 4, 40]), aceIndex);
      expect(rich.insuranceValue(), greaterThan(0), reason: '40 tens out of 76 cards');
    });

    test('late surrender is -0.5 after the peek; early surrender is -0.5 before it', () {
      final late = EvCalculator(
        const BlackjackRules(surrender: Surrender.late),
        shoeWithout(6, 'Ts 6s Kh'),
        tenIndex,
      ).playValues(HandSpot.ofCards(cards('Ts 6s')));
      expect(late[BlackjackAction.surrender], -0.5);
      expect(late[BlackjackAction.surrender]! > late[BlackjackAction.hit]!, isTrue, reason: '16 v 10: surrender');
      final early = EvCalculator(
        const BlackjackRules(surrender: Surrender.early),
        shoeWithout(6, 'Ts 6s Ah'),
        aceIndex,
      );
      final cont = early.valueBeforePeek(HandSpot.ofCards(cards('Ts 6s')), withSurrender: false);
      expect(cont, lessThan(-0.5), reason: '16 against an ace before the peek: early surrender saves money');
    });

    test('without a hole card, late surrender loses the whole bet to a dealer blackjack', () {
      final unseen = shoeWithout(6, 'Ts 6s Ah');
      final p = 95 / 309; // one ten among the seen cards
      final v = EvCalculator(
        const BlackjackRules(holeCard: false, surrender: Surrender.late),
        unseen,
        aceIndex,
      ).playValues(HandSpot.ofCards(cards('Ts 6s')));
      expect(v[BlackjackAction.surrender], closeTo(-0.5 * (1 - p) - p, 1e-12));
    });

    test('a blackjack before the peek is worth the payout times the chance the dealer has none', () {
      final calc = EvCalculator(const BlackjackRules(), shoeWithout(6, 'As Ks Ah'), aceIndex);
      final p = 95 / 309; // one ten among the seen cards
      expect(calc.valueBeforePeek(HandSpot.ofCards(cards('As Ks'))), closeTo(1.5 * (1 - p), 1e-12));
      expect(
        calc.valueBeforePeek(HandSpot.ofCards(cards('As Ks'))) + calc.insuranceValue(),
        closeTo(1, 1e-12),
        reason: 'even money is exactly 1',
      );
    });
  });

  group('no hole card', () {
    test('"original bets only" plays exactly like a hole card game (Wikipedia, "Blackjack")', () {
      final unseen = shoeWithout(6, '8s 8d Kh');
      final hole = EvCalculator(const BlackjackRules(), unseen, tenIndex).playValues(HandSpot.ofCards(cards('8s 8d')));
      final obo = EvCalculator(
        const BlackjackRules(holeCard: false, noHoleCardLoss: NoHoleCardLoss.originalBetsOnly),
        unseen,
        tenIndex,
      ).playValues(HandSpot.ofCards(cards('8s 8d')));
      final p = 24 / 309;
      for (final a in hole.keys) {
        // OBO values count the dealer's blackjack (a loss of 1) before the
        // peek; the hole card values are after it.
        expect(obo[a], closeTo((1 - p) * hole[a]! - p, 1e-12), reason: a.name);
      }
    });

    test('with every bet at risk, doubling 11 against a 10 is worse than hitting (Wikipedia)', () {
      final unseen = shoeWithout(6, '6s 5s Kh');
      final v = EvCalculator(
        const BlackjackRules(holeCard: false),
        unseen,
        tenIndex,
      ).playValues(HandSpot.ofCards(cards('6s 5s')));
      expect(v[BlackjackAction.hit]! > v[BlackjackAction.double]!, isTrue);
      final peek = EvCalculator(const BlackjackRules(), unseen, tenIndex).playValues(HandSpot.ofCards(cards('6s 5s')));
      expect(peek[BlackjackAction.double]! > peek[BlackjackAction.hit]!, isTrue);
    });
  });

  group('composition', () {
    test('the exact cards matter: a three-card 16 (4-4-8) stands against a 10, a two-card 16 hits', () {
      for (final (hand, best) in [('Ts 6s', BlackjackAction.hit), ('4s 4d 8c', BlackjackAction.stand)]) {
        final cs = cards(hand);
        final v = EvCalculator(
          const BlackjackRules(),
          Composition.decks(6).without([...cs, Card.parse('Kh')]),
          tenIndex,
        ).playValues(HandSpot.ofCards(cs));
        final pick = v[BlackjackAction.hit]! > v[BlackjackAction.stand]! ? BlackjackAction.hit : BlackjackAction.stand;
        expect(pick, best, reason: hand);
      }
    });

    test('splitting is only offered while the seat has room for another hand', () {
      final calc = EvCalculator(const BlackjackRules(maxHands: 2), shoeWithout(6, '8s 8d 6h'), 5);
      expect(calc.playValues(HandSpot.ofCards(cards('8s 8d')))[BlackjackAction.split], isNotNull);
      expect(
        calc.playValues(HandSpot.ofCards(cards('8s 8d'), splitHand: true, handsAtSeat: 2))[BlackjackAction.split],
        isNull,
      );
    });

    test('split aces with one card each can only stand', () {
      final calc = EvCalculator(const BlackjackRules(), shoeWithout(6, 'As 5d 6h'), 5);
      final v = calc.playValues(HandSpot.ofCards(cards('As 5d'), splitHand: true, splitAces: true, handsAtSeat: 2));
      expect(v.keys, [BlackjackAction.stand]);
    });
  });
}
