// Basic strategy charts generated for a rule set, checked cell by cell
// against Wizard of Odds' published charts:
// - 4-8 decks, dealer stands / hits soft 17
//   (https://wizardofodds.com/games/blackjack/strategy/4-decks/),
// - single deck, dealer hits soft 17
//   (https://wizardofodds.com/games/blackjack/strategy/1-deck/),
// - European no hole card
//   (https://wizardofodds.com/games/blackjack/strategy/european/),
// - early surrender (the list on the European page).
// The published charts serve several rule sets at once: "Ph" means split if
// double after split is allowed, otherwise hit (likewise "Pd", "Ps"), and
// "Rh" / "Rs" / "Rp" apply only with surrender. [expected] resolves them for
// the rules under test.
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/blackjack/blackjack.dart';

/// Columns 2, 3, 4, 5, 6, 7, 8, 9, 10, A.
const columns = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0];

/// A published chart: row name -> 10 codes. Row names: "hard 9",
/// "hard 5-8" (several totals), "soft 13", "pair 8".
typedef PublishedChart = Map<String, String>;

const PublishedChart woo48S17 = {
  'hard 5-8': 'H H H H H H H H H H',
  'hard 9': 'H Dh Dh Dh Dh H H H H H',
  'hard 10': 'Dh Dh Dh Dh Dh Dh Dh Dh H H',
  'hard 11': 'Dh Dh Dh Dh Dh Dh Dh Dh Dh H',
  'hard 12': 'H H S S S H H H H H',
  'hard 13-14': 'S S S S S H H H H H',
  'hard 15': 'S S S S S H H H Rh H',
  'hard 16': 'S S S S S H H Rh Rh Rh',
  'hard 17-21': 'S S S S S S S S S S',
  'soft 13-14': 'H H H Dh Dh H H H H H',
  'soft 15-16': 'H H Dh Dh Dh H H H H H',
  'soft 17': 'H Dh Dh Dh Dh H H H H H',
  'soft 18': 'S Ds Ds Ds Ds S S H H H',
  'soft 19-21': 'S S S S S S S S S S',
  'pair 2': 'Ph Ph P P P P H H H H',
  'pair 3': 'Ph Ph P P P P H H H H',
  'pair 4': 'H H H Ph Ph H H H H H',
  'pair 6': 'Ph P P P P H H H H H',
  'pair 7': 'P P P P P P H H H H',
  'pair 8': 'P P P P P P P P P P',
  'pair 9': 'P P P P P S P P S S',
  'pair A': 'P P P P P P P P P P',
};

const PublishedChart woo48H17 = {
  'hard 5-8': 'H H H H H H H H H H',
  'hard 9': 'H Dh Dh Dh Dh H H H H H',
  'hard 10': 'Dh Dh Dh Dh Dh Dh Dh Dh H H',
  'hard 11': 'Dh Dh Dh Dh Dh Dh Dh Dh Dh Dh',
  'hard 12': 'H H S S S H H H H H',
  'hard 13-14': 'S S S S S H H H H H',
  'hard 15': 'S S S S S H H H Rh Rh',
  'hard 16': 'S S S S S H H Rh Rh Rh',
  'hard 17': 'S S S S S S S S S Rs',
  'hard 18-21': 'S S S S S S S S S S',
  'soft 13-14': 'H H H Dh Dh H H H H H',
  'soft 15-16': 'H H Dh Dh Dh H H H H H',
  'soft 17': 'H Dh Dh Dh Dh H H H H H',
  'soft 18': 'Ds Ds Ds Ds Ds S S H H H',
  'soft 19': 'S S S S Ds S S S S S',
  'soft 20-21': 'S S S S S S S S S S',
  'pair 2': 'Ph Ph P P P P H H H H',
  'pair 3': 'Ph Ph P P P P H H H H',
  'pair 4': 'H H H Ph Ph H H H H H',
  'pair 6': 'Ph P P P P H H H H H',
  'pair 7': 'P P P P P P H H H H',
  'pair 8': 'P P P P P P P P P Rp',
  'pair 9': 'P P P P P S P P S S',
  'pair A': 'P P P P P P P P P P',
};

const PublishedChart woo1H17 = {
  'hard 5-7': 'H H H H H H H H H H',
  'hard 8': 'H H H Dh Dh H H H H H',
  'hard 9': 'Dh Dh Dh Dh Dh H H H H H',
  'hard 10': 'Dh Dh Dh Dh Dh Dh Dh Dh H H',
  'hard 11': 'Dh Dh Dh Dh Dh Dh Dh Dh Dh Dh',
  'hard 12': 'H H S S S H H H H H',
  'hard 13-14': 'S S S S S H H H H H',
  'hard 15': 'S S S S S H H H H Rh',
  'hard 16': 'S S S S S H H H Rh Rh',
  'hard 17': 'S S S S S S S S S Rs',
  'hard 18-21': 'S S S S S S S S S S',
  'soft 13-16': 'H H Dh Dh Dh H H H H H',
  'soft 17': 'Dh Dh Dh Dh Dh H H H H H',
  'soft 18': 'S Ds Ds Ds Ds S S H H H',
  'soft 19': 'S S S S Ds S S S S S',
  'soft 20-21': 'S S S S S S S S S S',
  'pair 2': 'Ph P P P P P H H H H',
  'pair 3': 'Ph Ph P P P P Ph H H H',
  'pair 4': 'H H Ph Pd Pd H H H H H',
  'pair 6': 'P P P P P Ph H H H H',
  'pair 7': 'P P P P P P Ph H Rs Rh',
  'pair 8': 'P P P P P P P P P P',
  'pair 9': 'P P P P P S P P S Ps',
  'pair A': 'P P P P P P P P P P',
};

const PublishedChart wooEuropean = {
  'hard 5-8': 'H H H H H H H H H H',
  'hard 9': 'H Dh Dh Dh Dh H H H H H',
  'hard 10-11': 'Dh Dh Dh Dh Dh Dh Dh Dh H H',
  'hard 12': 'H H S S S H H H H H',
  'hard 13-16': 'S S S S S H H H H H',
  'hard 17-21': 'S S S S S S S S S S',
  'soft 13-17': 'H H H H H H H H H H',
  'soft 18': 'S S S S S S S H H H',
  'soft 19-21': 'S S S S S S S S S S',
  'pair 2': 'P P P P P P H H H H',
  'pair 3': 'P P P P P P H H H H',
  'pair 4': 'H H H P P H H H H H',
  'pair 5': 'Dh Dh Dh Dh Dh Dh Dh Dh H H',
  'pair 6': 'P P P P P H H H H H',
  'pair 7': 'P P P P P P H H H H',
  'pair 8': 'P P P P P P P P H H',
  'pair 9': 'P P P P P S P P S S',
  'pair T': 'S S S S S S S S S S',
  'pair A': 'P P P P P P P P P H',
};

/// The code a published cell means under [rules].
String expected(String code, BlackjackRules rules) {
  final das = rules.doubleAfterSplit;
  final surrender = rules.surrender != Surrender.none;
  return switch (code) {
    'Ph' => das ? 'P' : 'H',
    'Pd' => das ? 'P' : 'Dh',
    'Ps' => das ? 'P' : 'S',
    'Rh' => surrender ? 'Rh' : 'H',
    'Rs' => surrender ? 'Rs' : 'S',
    'Rp' => surrender ? 'Rp' : 'P',
    _ => code,
  };
}

void compare(PublishedChart published, BlackjackRules rules) {
  final chart = BasicStrategyChart.forRules(rules);
  final mismatches = <String>[];
  published.forEach((row, codes) {
    final parts = row.split(' ');
    final kind = parts[0];
    final cells = codes.split(' ');
    expect(cells, hasLength(10), reason: row);
    final totals = <int>[];
    if (kind == 'pair') {
      totals.add(rankIndexOf(parts[1]));
    } else {
      final range = parts[1].split('-').map(int.parse).toList();
      for (var t = range.first; t <= range.last; t++) {
        totals.add(t);
      }
    }
    for (final t in totals) {
      for (var c = 0; c < 10; c++) {
        final up = columns[c];
        final got = switch (kind) {
          'hard' => chart.hard(t, up),
          'soft' => chart.soft(t, up),
          _ => chart.pair(t, up),
        }.label;
        final want = expected(cells[c], rules);
        if (got != want) mismatches.add('$kind $t vs ${rankName(up)}: got $got, published $want');
      }
    }
  });
  expect(mismatches, isEmpty, reason: '$rules');
}

void main() {
  group('generated charts match the published ones', () {
    test('6 decks, S17, double after split, late surrender', () {
      compare(woo48S17, const BlackjackRules(surrender: Surrender.late));
    });
    test('6 decks, S17, no double after split, no surrender', () {
      compare(woo48S17, const BlackjackRules(doubleAfterSplit: false));
    });
    test('8 decks, S17, double after split (Atlantic City without surrender)', () {
      compare(woo48S17, const BlackjackRules(decks: 8));
    });
    test('6 decks, H17, double after split, late surrender', () {
      compare(woo48H17, const BlackjackRules(dealerHitsSoft17: true, surrender: Surrender.late));
    });
    test('4 decks, H17, no double after split, no surrender', () {
      compare(woo48H17, const BlackjackRules(decks: 4, dealerHitsSoft17: true, doubleAfterSplit: false));
    });
    test('single deck, H17, double after split, late surrender', () {
      compare(woo1H17, const BlackjackRules(decks: 1, dealerHitsSoft17: true, surrender: Surrender.late));
    });
    test('single deck, H17, no double after split (the Single deck preset)', () {
      compare(woo1H17, BlackjackRules.preset(BlackjackPreset.singleDeck));
    });
    test('European no hole card (the European preset)', () {
      compare(wooEuropean, BlackjackRules.preset(BlackjackPreset.european));
    });
  });

  test('early surrender: 5-7 and 12-17 against an ace, 14-16 against a 10, 16 against a 9', () {
    final chart = BasicStrategyChart.forRules(const BlackjackRules(surrender: Surrender.early));
    const ace = aceIndex, ten = tenIndex, nine = 8;
    bool surrenders(ChartCode c) => c.label.startsWith('R');
    for (var t = 4; t <= 21; t++) {
      expect(surrenders(chart.hard(t, ace)), (t >= 5 && t <= 7) || (t >= 12 && t <= 17), reason: 'hard $t v A');
      expect(surrenders(chart.hard(t, ten)), t >= 14 && t <= 16, reason: 'hard $t v T');
      expect(surrenders(chart.hard(t, nine)), t == 16, reason: 'hard $t v 9');
    }
    for (final p in [2, 5, 6, 7]) {
      expect(surrenders(chart.pair(p, ace)), isTrue, reason: 'pair ${rankName(p)} v A');
    }
    expect(surrenders(chart.pair(6, ten)) && surrenders(chart.pair(7, ten)), isTrue, reason: '7-7 and 8-8 v T');
  });

  group('reading the chart', () {
    final chart = BasicStrategyChart.forRules(const BlackjackRules(dealerHitsSoft17: true, surrender: Surrender.late));

    test('"Dh" doubles on two cards and hits after; "Ds" stands after', () {
      expect(
        chart.decide(total: const HandTotal(11, false), cardCount: 2, upcard: 5, canDouble: true),
        BlackjackAction.double,
      );
      expect(chart.decide(total: const HandTotal(11, false), cardCount: 3, upcard: 5), BlackjackAction.hit);
      expect(chart.decide(total: const HandTotal(18, true), cardCount: 3, upcard: 3), BlackjackAction.stand);
    });

    test('"Rh" surrenders when allowed and hits otherwise; "Rp" splits otherwise', () {
      expect(
        chart.decide(total: const HandTotal(16, false), cardCount: 2, upcard: tenIndex, canSurrender: true),
        BlackjackAction.surrender,
      );
      expect(chart.decide(total: const HandTotal(16, false), cardCount: 3, upcard: tenIndex), BlackjackAction.hit);
      expect(
        chart.decide(total: const HandTotal(16, false), cardCount: 2, upcard: aceIndex, pairRank: 7, canSplit: true),
        BlackjackAction.split,
      );
      expect(
        chart.decide(
          total: const HandTotal(16, false),
          cardCount: 2,
          upcard: aceIndex,
          pairRank: 7,
          canSplit: true,
          canSurrender: true,
        ),
        BlackjackAction.surrender,
      );
    });

    test('a pair that can\'t be split again is played as its total', () {
      expect(
        chart.decide(total: const HandTotal(16, false), cardCount: 2, upcard: 9 - 1, pairRank: 7),
        BlackjackAction.hit,
        reason: '16 v 9 without surrender: hit',
      );
      expect(
        chart.decide(total: const HandTotal(20, false), cardCount: 2, upcard: 5, pairRank: tenIndex, canSplit: true),
        BlackjackAction.stand,
      );
    });

    test('the chart prints like a published one, dealer ace last', () {
      final text = chart.toText();
      expect(text.split('\n').first.trim(), '2  3  4  5  6  7  8  9  T  A');
      expect(text, contains('hard 17  S  S  S  S  S  S  S  S  S  Rs'));
    });
  });
}
