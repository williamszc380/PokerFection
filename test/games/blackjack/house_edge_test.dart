// House edges, checked against Wizard of Odds' "Blackjack House Edge
// Calculator" (https://wizardofodds.com/games/blackjack/calculator/). Its
// "optimal results" are perfect composition-dependent play with a fresh
// shoe every round; its "basic strategy with continuous shuffler" adds the
// cost of total-dependent basic strategy (a per-deck constant in its
// script). The target was 0.05% of the bet; the engine lands within 0.01%.
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/blackjack/blackjack.dart';

/// Rule set, the calculator's optimal edge (%), and its basic strategy
/// edge with a continuous shuffler (%) where checked.
const cases = <(String, BlackjackRules, double, double?)>[
  ('6 decks S17 DAS (Standard)', BlackjackRules(), 0.403115, 0.406215),
  ('6 decks H17 DAS', BlackjackRules(dealerHitsSoft17: true), 0.615626, 0.618726),
  ('6 decks H17 DAS late surrender', BlackjackRules(dealerHitsSoft17: true, surrender: Surrender.late), 0.527409, null),
  (
    '8 decks S17 DAS late surrender (Atlantic City)',
    BlackjackRules(decks: 8, surrender: Surrender.late),
    0.355143,
    null,
  ),
  ('8 decks H17 DAS', BlackjackRules(decks: 8, dealerHitsSoft17: true), 0.644928, null),
  ('4 decks S17 DAS', BlackjackRules(decks: 4), 0.347486, null),
  (
    '2 decks H17 DAS (Downtown)',
    BlackjackRules(decks: 2, dealerHitsSoft17: true, penetration: 0.65),
    0.379879,
    0.393879,
  ),
  (
    '1 deck H17 no DAS (Single deck)',
    BlackjackRules(decks: 1, dealerHitsSoft17: true, doubleAfterSplit: false),
    0.151762,
    0.190462,
  ),
  ('1 deck S17 DAS', BlackjackRules(decks: 1), -0.182895, null),
  // Las Vegas Advisor ("Best blackjack rules", Anthony Curtis): the old
  // Strip single deck, S17, double any two, no double after split, "a
  // player edge of .04%"; the calculator gives -0.041620.
  ('1 deck S17 no DAS (old Las Vegas Strip rules)', BlackjackRules(decks: 1, doubleAfterSplit: false), -0.041620, null),
  ('6 decks S17 no DAS', BlackjackRules(doubleAfterSplit: false), 0.544889, null),
  ('6 decks S17 DAS, split to 3 hands', BlackjackRules(maxHands: 3), 0.411761, null),
  ('6 decks S17 DAS, double 10-11 only', BlackjackRules(doubling: DoubleRule.tenToEleven), 0.595195, null),
  ('6 decks S17 DAS, hit split aces', BlackjackRules(hitSplitAces: true), 0.215706, null),
  (
    '6 decks S17 DAS RSA late surrender (Vegas Strip)',
    BlackjackRules(resplitAces: true, surrender: Surrender.late),
    0.261970,
    null,
  ),
  ('6 decks S17 no hole card, all bets lost', BlackjackRules(holeCard: false), 0.514166, null),
  (
    'European preset (9-11, split to 2, no hole card)',
    BlackjackRules(doubling: DoubleRule.nineToEleven, maxHands: 2, holeCard: false),
    0.661190,
    null,
  ),
  ('6 decks S17 DAS, blackjack pays 6:5', BlackjackRules(payout: BlackjackPayout.sixToFive), 0.403115 + 1.359690, null),
];

void main() {
  group('optimal play matches the published house edge within 0.01%', () {
    for (final (name, rules, optimal, _) in cases) {
      test(name, () {
        final edge = BasicStrategyChart.forRules(rules).optimalEdge * 100;
        expect(edge, closeTo(optimal, 0.01));
      });
    }
  });

  group('basic strategy (the chart) matches the published house edge within 0.01%', () {
    for (final (name, rules, _, basic) in cases) {
      if (basic == null) continue;
      test(name, () {
        final chart = BasicStrategyChart.forRules(rules);
        final edge = chart.basicStrategyEdge() * 100;
        expect(edge, closeTo(basic, 0.01));
        expect(
          chart.basicStrategyEdge(),
          greaterThanOrEqualTo(chart.optimalEdge),
          reason: 'a chart can\'t beat perfect play',
        );
      });
    }
  });

  test('"original bets only" without a hole card has exactly the hole card game\'s edge', () {
    final hole = BasicStrategyChart.forRules(const BlackjackRules()).optimalEdge;
    final obo = BasicStrategyChart.forRules(
      const BlackjackRules(holeCard: false, noHoleCardLoss: NoHoleCardLoss.originalBetsOnly),
    ).optimalEdge;
    expect(obo, closeTo(hole, 1e-12));
  });

  test('rule effects point the published way (Wizard of Odds, "Blackjack Rule Variations")', () {
    double edge(BlackjackRules r) => BasicStrategyChart.forRules(r).optimalEdge * 100;
    final base = edge(const BlackjackRules());
    expect(edge(const BlackjackRules(dealerHitsSoft17: true)) - base, closeTo(0.22, 0.03), reason: 'H17: -0.22%');
    expect(
      base - edge(const BlackjackRules(surrender: Surrender.early)),
      closeTo(0.39 + 0.24, 0.05),
      reason: 'early surrender against ace (+0.39%) and ten (+0.24%)',
    );
    expect(
      edge(const BlackjackRules(payout: BlackjackPayout.oneToOne)) - base,
      closeTo(2.27, 0.05),
      reason: 'blackjacks at 1:1 lose the 3:2 bonus worth about 2.3%',
    );
    expect(edge(const BlackjackRules(maxHands: 1)) - base, closeTo(0.57, 0.05), reason: 'no splitting: -0.57%');
  });

  test('the bots\' strategies cost what their level suggests', () {
    const rules = BlackjackRules();
    final hard = BasicStrategyChart.forRules(rules).basicStrategyEdge();
    final medium = houseEdgeFollowing(rules, const SimplePolicy());
    final easy = houseEdgeFollowing(rules, const BeginnerPolicy());
    expect(houseEdgeFollowing(rules, BasicStrategyChart.forRules(rules)), closeTo(hard, 1e-12));
    expect(medium, greaterThan(hard));
    expect(medium, lessThan(hard + 0.005), reason: 'simplified basic strategy costs well under half a percent');
    expect(easy, greaterThan(0.039), reason: 'worse than "never bust" (3.91% under Atlantic City rules)');
  });
}
