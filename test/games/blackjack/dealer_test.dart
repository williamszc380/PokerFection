// Exact dealer outcome probabilities, checked against Wizard of Odds,
// "Dealer Odds in Blackjack under US Rules"
// (https://wizardofodds.com/games/blackjack/dealer-odds-blackjack-us-rules/):
// a full shoe minus the upcard, after the dealer has peeked and has no
// blackjack, rounded to 6 decimals.
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/blackjack/blackjack.dart';

import 'helpers.dart';

/// Rows: upcard A, 2..9, 10; columns 17, 18, 19, 20, 21, bust.
const sixDeckS17 = [
  [0.188071, 0.189235, 0.188906, 0.189362, 0.077394, 0.167033],
  [0.139656, 0.134389, 0.13002, 0.124019, 0.118413, 0.353504],
  [0.134296, 0.130539, 0.125226, 0.120817, 0.114928, 0.374194],
  [0.130556, 0.124062, 0.121272, 0.116441, 0.111866, 0.395805],
  [0.121843, 0.122437, 0.117575, 0.111793, 0.107945, 0.418406],
  [0.165707, 0.106194, 0.106431, 0.101551, 0.097276, 0.422842],
  [0.369208, 0.137931, 0.078428, 0.078682, 0.073816, 0.261936],
  [0.12894, 0.359955, 0.128723, 0.069219, 0.06947, 0.243693],
  [0.12031, 0.117348, 0.351854, 0.120368, 0.060877, 0.229242],
  [0.121273, 0.121007, 0.121306, 0.368447, 0.037729, 0.230239],
];

const sixDeckH17 = [
  [0.082842, 0.206593, 0.206757, 0.207262, 0.095264, 0.201281],
  [0.130071, 0.135978, 0.131607, 0.125662, 0.120022, 0.356661],
  [0.1259, 0.13193, 0.126656, 0.122185, 0.116371, 0.376958],
  [0.122458, 0.125405, 0.12262, 0.11783, 0.113217, 0.39847],
  [0.118089, 0.123042, 0.118216, 0.112435, 0.108586, 0.419632],
  [0.115064, 0.114574, 0.115043, 0.110177, 0.105882, 0.439259],
  [0.369208, 0.137931, 0.078428, 0.078682, 0.073816, 0.261936],
  [0.12894, 0.359955, 0.128723, 0.069219, 0.06947, 0.243693],
  [0.12031, 0.117348, 0.351854, 0.120368, 0.060877, 0.229242],
  [0.121273, 0.121007, 0.121306, 0.368447, 0.037729, 0.230239],
];

const oneDeckS17 = [
  [0.183786, 0.19089, 0.18868, 0.191692, 0.075137, 0.169815],
  [0.138976, 0.131762, 0.131815, 0.123948, 0.120526, 0.352973],
  [0.130313, 0.130946, 0.123761, 0.123345, 0.116047, 0.375588],
  [0.130973, 0.114163, 0.120679, 0.116286, 0.115096, 0.402803],
  [0.119687, 0.123483, 0.116909, 0.104694, 0.106321, 0.428905],
  [0.166948, 0.106454, 0.107192, 0.100705, 0.097879, 0.420823],
  [0.372345, 0.138583, 0.077334, 0.078897, 0.072987, 0.259854],
  [0.130857, 0.362989, 0.129445, 0.06829, 0.069791, 0.238627],
  [0.121886, 0.103921, 0.357391, 0.12225, 0.061109, 0.233442],
  [0.124156, 0.122486, 0.124421, 0.356869, 0.03957, 0.232499],
];

void main() {
  void checkTable(String name, int decks, bool h17, List<List<double>> table) {
    test('$name: every upcard matches the published table to 6 decimals', () {
      for (var up = 0; up < rankCount; up++) {
        final unseen = Composition.decks(decks).without([ofRank(up)]);
        final got = dealerOutcomes(up, unseen, hitsSoft17: h17, peeked: true);
        for (var i = 0; i < 6; i++) {
          expect(got[i], closeTo(table[up][i], 1.5e-6), reason: 'upcard ${rankName(up)}, outcome $i');
        }
      }
    });
  }

  checkTable('6 decks, dealer stands on soft 17', 6, false, sixDeckS17);
  checkTable('6 decks, dealer hits soft 17', 6, true, sixDeckH17);
  checkTable('1 deck, dealer stands on soft 17', 1, false, oneDeckS17);

  test('the outcome probabilities sum to 1, for any upcard, any rules and odd compositions', () {
    final shoes = [
      Composition.decks(8),
      Composition.decks(1),
      Composition([2, 0, 7, 1, 5, 3, 9, 4, 0, 6]), // a strange late-shoe mix
    ];
    for (final shoe in shoes) {
      for (final h17 in [false, true]) {
        for (var up = 0; up < rankCount; up++) {
          final o = dealerOutcomes(up, shoe, hitsSoft17: h17);
          expect(o.reduce((a, b) => a + b), closeTo(1, 1e-12), reason: 'upcard ${rankName(up)}');
          final peeked = dealerOutcomes(up, shoe, hitsSoft17: h17, peeked: true);
          expect(peeked.reduce((a, b) => a + b), closeTo(1, 1e-12));
          expect(peeked[dealerBlackjack], 0);
        }
      }
    }
  });

  test('before the peek, the blackjack chance is the chance the hole card completes 21', () {
    final unseen = Composition.decks(6).without([ofRank(aceIndex)]);
    final o = dealerOutcomes(aceIndex, unseen, hitsSoft17: false);
    expect(o[dealerBlackjack], closeTo(96 / 311, 1e-12));
    final ten = dealerOutcomes(tenIndex, Composition.decks(6).without([ofRank(tenIndex)]), hitsSoft17: false);
    expect(ten[dealerBlackjack], closeTo(24 / 311, 1e-12));
    final six = dealerOutcomes(5, Composition.decks(6).without([ofRank(5)]), hitsSoft17: false);
    expect(six[dealerBlackjack], 0);
  });

  test('the soft 17 rule only matters when the dealer can reach soft 17', () {
    for (final up in [6, 7, 8, 9]) {
      final unseen = Composition.decks(6).without([ofRank(up)]);
      expect(
        dealerOutcomes(up, unseen, hitsSoft17: true),
        dealerOutcomes(up, unseen, hitsSoft17: false),
        reason: 'with a ${rankName(up)} up, A-6 can\'t be the first two cards',
      );
    }
  });

  test('the merged draw graph stays small (a few hundred dealer hands per upcard)', () {
    for (var up = 0; up < rankCount; up++) {
      expect(DealerGraph.of(up, true).nodeCount, lessThan(400));
    }
  });
}
