// With three players the face-up 52nd card goes to a seat the rules name
// (Pagat: "The holder of the three of diamonds adds this extra card to
// their hand", and if it is the 3♦ itself "the holder of the three of
// clubs must take it"). So everyone at the table knows a card the taker
// holds without seeing it:
// - the 52nd card is the 3♦: its taker holds the 3♣ too;
// - a chosen leader (the 3♦ isn't shown): the taker holds the 3♦.
// A guess that puts that card in another seat deals a deal that can't
// have happened. A probe: many deals, every guess checked.
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';

/// The lowest card the taker of the 52nd card must hold, known to all.
int _takerHolds(BigTwoState s) => s.extraCode == 0 ? 1 : 0;

void _probe(BigTwoState s) {
  final lowCode = _takerHolds(s);
  expect(s.handCodesOf(s.extraSeat), contains(lowCode), reason: 'the deal itself follows Pagat');
  for (var seat = 0; seat < 3; seat++) {
    if (seat == s.extraSeat) continue;
    final view = s.viewFor(seat);
    final sampler = DealSampler(view);
    final rng = GameRandom(seat * 7 + 1);
    for (var i = 0; i < 300; i++) {
      final hands = sampler.sample(rng);
      expect(hands[s.extraSeat], contains(lowCode),
          reason: 'seat $seat guessed ${s.rules.cardOf(lowCode)} away from seat ${s.extraSeat}, '
              'who took the 52nd card ${s.rules.cardOf(s.extraCode)}');
    }
    // The proof that shares out the unseen cards keeps it with the taker too.
    final shared = EndgameSolver.sharedState(BigTwoState.fromView(view, sampler.sample(rng)), seat);
    for (var o = 0; o < 3; o++) {
      if (o == seat) continue;
      expect(shared.handCodesOf(o).contains(lowCode), o == s.extraSeat,
          reason: 'the proof for seat $seat gave seat $o the ${s.rules.cardOf(lowCode)}');
    }
    // Known, but nobody turned it over: no eye is drawn on it.
    expect(view.visibleCards.map((v) => v.code), isNot(contains(lowCode)));
    expect(view.knownCards, contains((code: lowCode, seat: s.extraSeat)));
  }
}

void main() {
  final rules = BigTwoRules.standard(players: 3);

  test('the 52nd card is the 3♦: every guess keeps the 3♣ with its taker', () {
    var found = 0;
    for (var seed = 0; seed < 4000 && found < 3; seed++) {
      final s = BigTwoState.deal(rules, seed: seed);
      if (s.extraCode != 0) continue;
      found++;
      _probe(s);
    }
    expect(found, greaterThan(0));
  });

  test('a chosen leader: every guess keeps the 3♦ with the taker of the 52nd card', () {
    for (var seed = 0; seed < 5; seed++) {
      final s = BigTwoState.deal(rules, seed: seed, leader: seed % 3);
      if (s.extraCode == 0) continue;
      _probe(s);
    }
  });
}
