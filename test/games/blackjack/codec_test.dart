// The engine's JSON: rules and strategy charts travel to background jobs
// and into saved games, and the coach and the Hard bot play the chart they
// are given rather than one they build or find cached.
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/blackjack/blackjack.dart';

import 'helpers.dart';

/// [chart] with one cell changed: hard [total] against [upcard] becomes [code].
BasicStrategyChart withCell(BasicStrategyChart chart, int total, int upcard, String code) {
  final json = chart.toJson();
  final hard = [...json['hard']! as List<String>];
  final row = hard[total - 4].split('');
  row[upcard] = code;
  hard[total - 4] = row.join();
  return BasicStrategyChart.fromJson({...json, 'hard': hard});
}

void main() {
  group('rules', () {
    test('every preset and a fully custom table survive the round trip', () {
      final tables = [
        for (final p in BlackjackPreset.values) BlackjackRules.preset(p),
        const BlackjackRules(
          decks: 4,
          continuousShuffle: true,
          dealerHitsSoft17: true,
          payout: BlackjackPayout.sixToFive,
          doubling: DoubleRule.tenToEleven,
          doubleAfterSplit: false,
          maxHands: 3,
          resplitAces: true,
          hitSplitAces: true,
          surrender: Surrender.early,
          holeCard: false,
          noHoleCardLoss: NoHoleCardLoss.originalBetsOnly,
          insurance: false,
          penetration: 0.8,
        ),
      ];
      for (final rules in tables) {
        final back = BlackjackRules.fromJson(rules.toJson());
        expect(back, rules);
        expect(back.strategyKey, rules.strategyKey);
        expect(back.toJson(), rules.toJson());
      }
    });

    test('a missing switch takes its default, so older saves still load', () {
      expect(BlackjackRules.fromJson({'decks': 2}), const BlackjackRules(decks: 2));
      expect(BlackjackRules.fromJson(<String, Object?>{}), const BlackjackRules());
    });

    test('a broken value is refused, never played', () {
      for (final broken in <Object?>[
        null,
        'rules',
        {'decks': 'six'},
        {'decks': 9},
        {'penetration': 1.5},
        {'surrender': 'sometimes'},
        {'holeCard': 1},
      ]) {
        expect(() => BlackjackRules.fromJson(broken), throwsFormatException, reason: '$broken');
      }
    });
  });

  group('charts', () {
    final rules = BlackjackRules.preset(BlackjackPreset.vegasStrip);
    final chart = BasicStrategyChart.forRules(rules);

    test('a chart survives the round trip cell for cell, in about half a kilobyte', () {
      final json = chart.toJson();
      final back = BasicStrategyChart.fromJson(json);
      expect(back.toText(), chart.toText());
      expect(back.optimalEdge, chart.optimalEdge);
      expect(back.rules, rules);
      expect(back.toJson(), json);
      final size = json.toString().length;
      expect(size, lessThan(1000), reason: 'small enough to send with every coach job');
    });

    test('rows are ten one-letter codes, upcards ace first', () {
      final json = chart.toJson();
      expect((json['hard']! as List).length, 18, reason: 'hard 4 to 21');
      expect((json['soft']! as List).length, 10, reason: 'soft 12 to 21');
      expect((json['pairs']! as List).length, 10, reason: 'A,A to T,T');
      // Vegas Strip has late surrender: hard 16 against a ten (index 9) is Rh.
      expect((json['hard']! as List)[16 - 4], hasLength(10));
      expect(BasicStrategyChart.fromJson(json).hard(16, tenIndex), ChartCode.surrenderOrHit);
    });

    test('a chart carries exactly the rules asked for, even when another table shares it', () {
      const deep = BlackjackRules(penetration: 0.85);
      const shallow = BlackjackRules(penetration: 0.6);
      expect(BasicStrategyChart.forRules(deep).rules, deep);
      expect(BasicStrategyChart.forRules(shallow).rules, shallow);
      expect(BasicStrategyChart.forRules(shallow).toText(), BasicStrategyChart.forRules(deep).toText());
    });

    test('a broken chart is refused', () {
      final json = chart.toJson();
      for (final broken in <Object?>[
        null,
        {...json, 'hard': (json['hard']! as List).sublist(1)},
        {
          ...json,
          'soft': ['HHHHHHHHHX', ...(json['soft']! as List).skip(1)],
        },
        {
          ...json,
          'pairs': ['HH', ...(json['pairs']! as List).skip(1)],
        },
        {...json, 'edge': 'small'},
        {...json, 'rules': 7},
      ]) {
        expect(() => BasicStrategyChart.fromJson(broken), throwsFormatException);
      }
    });
  });

  group('the chart given is the chart used', () {
    const rules = BlackjackRules();
    final standard = BasicStrategyChart.forRules(rules);
    // A chart that says to stand on 16 against a 7 (upcard index 6).
    final odd = withCell(standard, 16, 6, 'S');

    test('the coach tags the given chart\'s play', () {
      final view = stacked(rules, 'Ts 7h 6d 9c').viewFor(0);
      expect(const BlackjackCoach().analyze(view).chartAction, BlackjackAction.hit);
      expect(const BlackjackCoach().analyze(view, chart: odd).chartAction, BlackjackAction.stand);
      expect(
        const BlackjackCoach().analyze(view, chart: BasicStrategyChart.fromJson(standard.toJson())).chartAction,
        BlackjackAction.hit,
      );
    });

    test('the Hard bot plays the given chart', () {
      final view = stacked(rules, 'Ts 7h 6d 9c').viewFor(0);
      expect(BlackjackBot(BotLevel.hard).chooseAction(view), BlackjackAction.hit);
      expect(BlackjackBot(BotLevel.hard, chart: odd).chooseAction(view), BlackjackAction.stand);
    });

    test('a chart for other rules is refused', () {
      final view = stacked(rules, 'Ts 7h 6d 9c').viewFor(0);
      final h17 = BasicStrategyChart.forRules(const BlackjackRules(dealerHitsSoft17: true));
      expect(() => const BlackjackCoach().analyze(view, chart: h17), throwsArgumentError);
      expect(() => BlackjackBot(BotLevel.hard, chart: h17).chooseAction(view), throwsArgumentError);
    });

    test('rules that differ only where strategy doesn\'t care share a chart', () {
      final view = stacked(const BlackjackRules(penetration: 0.6, insurance: false), 'Ts 7h 6d 9c').viewFor(0);
      expect(const BlackjackCoach().analyze(view, chart: standard).chartAction, BlackjackAction.hit);
    });
  });
}
