// Edge cases of the blackjack engine: even money, the coach's reasons, early
// surrender followed by insurance, stacked shoes and the end of the shoe.
// Each test states the behaviour the engine should have.
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/blackjack/blackjack.dart';

import 'helpers.dart';

const coach = BlackjackCoach();

/// Reason kinds that tell the player to make the play they are attached to.
const recommending = {
  ReasonKind.dealerBustsOften, // "... busts often: stand"
  ReasonKind.doubleStrong, // "11 vs 6: double"
  ReasonKind.doubleSoft, // "Soft 17 vs 4: double"
  ReasonKind.splitVsWeak, // "Split against a weak upcard"
  ReasonKind.softStand, // "A good soft total: stand"
};

void main() {
  group('even money', () {
    // Las Vegas Advisor, "Even money at 6-5 blackjack"
    // (https://www.lasvegasadvisor.com/question/even-money-6-5-blackjack/):
    // at 6:5, insuring a blackjack nets +7 on 10 when the dealer has no
    // blackjack, so it is not even money.
    for (final payout in [BlackjackPayout.sixToFive, BlackjackPayout.oneToOne]) {
      test('an offer called "even money" pays 1 to 1 whatever the dealer has (${payout.name})', () {
        final rules = BlackjackRules(payout: payout);
        final r = stacked(rules, 'As Ad Kh 7c');
        if (!r.viewFor(0).offersEvenMoney) return; // calling it insurance is fine too
        r.apply(BlackjackAction.insurance);
        expect(r.result(0).net, 10, reason: 'the dealer has no blackjack: even money still pays 10');
      });
    }
  });

  group('coach reasons', () {
    // Each case: deal, the action whose reasons are checked. The action is
    // not the best play and gives up 0.01 bets or more, so a reason telling
    // the player to make it contradicts the coach's own numbers.
    const cases = [
      ('7s 3h 5d 9c', BlackjackAction.stand), // 12 vs 3: hit is best
      ('7s 2h 5d 9c', BlackjackAction.stand), // 12 vs 2: hit is best
      ('6s Ah 4d 9c', BlackjackAction.double), // 10 vs A: hit is best
      ('5s 7h 4d 9c', BlackjackAction.double), // 9 vs 7: hit is best
      ('As 2h 2d 9c', BlackjackAction.double), // soft 13 vs 2: hit is best
      ('4s 4h 4d 9c', BlackjackAction.split), // 4-4 vs 4: hit is best
      ('As 9h 7d 5c', BlackjackAction.stand), // soft 18 vs 9: hit is best
    ];
    for (final (deal, action) in cases) {
      test('a losing ${action.name} with $deal is not explained as the play to make', () {
        final a = coach.analyze(stacked(const BlackjackRules(insurance: false), deal).viewFor(0));
        final x = a.of(action);
        expect(a.bestFresh, isNot(action));
        expect(x.lostFresh, greaterThanOrEqualTo(0.01));
        expect(x.reasons.map((r) => r.kind).where(recommending.contains), isEmpty, reason: '${x.reasons}');
      });
    }
  });

  group('early surrender then insurance', () {
    test('keeping the hand is worth what the insurance decision that follows is worth', () {
      const rules = BlackjackRules(decks: 1, surrender: Surrender.early);
      // Round 1 (seven seats stand) uses up 18 small cards, so the rest of
      // the deck is rich in tens; round 2 is T-8 against an ace.
      final shoe = Shoe.forRules(rules, seed: 1)
        ..stack(cards('2c 2d 2h 2s 3c 3d 3h 3s 4c 4d 4h 4s 5c 5d 5h 5s 6c 6d Ts As 8s 9c'));
      final first = BlackjackRound.deal(rules, shoe, List.filled(7, 1));
      while (!first.isOver) {
        first.apply(BlackjackAction.stand);
      }
      final r = BlackjackRound.deal(rules, shoe, [1]);
      final early = coach.analyze(r.viewFor(0));
      expect(early.phase, RoundPhase.earlySurrender);
      r.apply(BlackjackAction.keepPlaying);
      final ins = coach.analyze(r.viewFor(0));
      expect(ins.phase, RoundPhase.insurance);
      final bestAfter = ins.of(ins.bestSeen).evSeen;
      expect(early.of(BlackjackAction.keepPlaying).evSeen, closeTo(bestAfter, 1e-9));
      // And so the decision itself: keeping T-8 and insuring (about -0.45) beats -0.5.
      expect(bestAfter, greaterThan(-0.5));
      expect(
        early.bestSeen,
        BlackjackAction.keepPlaying,
        reason: 'surrendering gives up more than keeping the hand and insuring',
      );
    });
  });

  group('stacking', () {
    test('the cards under a stacked card stay in random order (no copy is pushed down)', () {
      // Two decks hold two identical 8s. Stack one 8s on top: the other 8s
      // should be the very next card 1 time in 103 (103 cards left).
      // Removing the FIRST copy from the shuffled rest leaves the later
      // copy, which is then almost never on top (about 1 time in 5,356).
      const n = 20000;
      var next8s = 0;
      for (var seed = 1; seed <= n; seed++) {
        final shoe = Shoe(decks: 2, seed: seed)..stack(cards('8s'));
        shoe.draw();
        if (shoe.draw() == Card.parse('8s')) next8s++;
      }
      // 194 expected; 4 standard deviations is about 55.
      expect(next8s, inInclusiveRange(194 - 55, 194 + 55));
    });
  });

  group('the end of the shoe', () {
    test('with every card dealt, SEEN values stay finite and sensible (the discards come back)', () {
      const rules = BlackjackRules(decks: 1, holeCard: false);
      final round = cards('6s 2c 3c 4c 5c 7c 8c 9h 2d 5s 3d 4d 6d 7d 8d');
      final rest = [...Card.deck]..removeWhere(round.contains);
      final shoe = Shoe.forRules(rules, seed: 1)..stack([...rest, ...round]);
      shoe.startRound();
      for (var i = 0; i < 37; i++) {
        shoe.draw(); // 37 < the cut card at 39: no shuffle before the next round
      }
      final r = BlackjackRound.deal(rules, shoe, List.filled(7, 1));
      expect(shoe.cardsLeft, 0);
      expect(r.seats[0].hands[0].cards, cards('6s 2d'), reason: '8 against a 9');
      final a = coach.analyze(r.viewFor(0));
      for (final x in a.actions) {
        expect(x.evSeen.isFinite, isTrue, reason: '${x.action.name}: ${x.evSeen}');
      }
      expect(a.bestSeen, BlackjackAction.hit, reason: 'standing on 8 against a 9 is never right');
    });
  });
}
