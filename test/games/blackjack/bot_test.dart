// The bots: Easy plays like a beginner, Medium a simplified basic
// strategy, Hard the full chart for the rules; all only play legal moves.
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/blackjack/blackjack.dart';

import 'helpers.dart';

BlackjackAction choice(BotLevel level, String deal, {BlackjackRules rules = const BlackjackRules()}) =>
    BlackjackBot(level).chooseAction(stacked(rules, deal).viewFor(0));

void main() {
  group('Easy', () {
    test('never risks busting: stands on any hard 12 or more', () {
      expect(choice(BotLevel.easy, 'Ts Th 2d 9c'), BlackjackAction.stand);
      expect(choice(BotLevel.easy, '9s 7h 3d 9c'), BlackjackAction.stand, reason: '12 vs 7: basic strategy hits');
      expect(choice(BotLevel.easy, '5s 7h 4d 9c'), BlackjackAction.hit);
    });

    test('doubles any 10 or 11, even against a ten or an ace, and never a soft hand', () {
      expect(choice(BotLevel.easy, '6s Th 4d 9c'), BlackjackAction.double, reason: '10 vs 10: basic strategy hits');
      expect(choice(BotLevel.easy, 'As 5h 7d 9c'), BlackjackAction.stand, reason: 'soft 18 vs 5: no double');
    });

    test('splits only aces and eights', () {
      expect(choice(BotLevel.easy, '8s Th 8d 9c'), BlackjackAction.split);
      expect(choice(BotLevel.easy, '9s 6h 9d 9c'), BlackjackAction.stand, reason: '9-9 vs 6 should be split');
    });

    test('takes even money and insures a good hand', () {
      expect(choice(BotLevel.easy, 'As Ad Kh 7c'), BlackjackAction.insurance);
      expect(choice(BotLevel.easy, 'Ts Ad 9h 7c'), BlackjackAction.insurance);
      expect(choice(BotLevel.easy, 'Ts Ad 4h 7c'), BlackjackAction.noInsurance);
    });
  });

  group('Medium', () {
    test('plays the main basic strategy rules', () {
      expect(choice(BotLevel.medium, '5s 6h 6d Tc'), BlackjackAction.double, reason: '11 vs 6');
      expect(choice(BotLevel.medium, 'Ts 6h 6d Tc'), BlackjackAction.stand, reason: '16 vs 6');
      expect(choice(BotLevel.medium, 'Ts 7h 6d Tc'), BlackjackAction.hit, reason: '16 vs 7');
      expect(choice(BotLevel.medium, '8s Th 8d 9c'), BlackjackAction.split);
      expect(choice(BotLevel.medium, 'Ts 6h Kd 9c'), BlackjackAction.stand, reason: 'never split tens');
      expect(choice(BotLevel.medium, 'As Ad Kh 7c'), BlackjackAction.noInsurance);
    });

    test('but skips the finer plays, such as doubling soft 18 against a 4', () {
      expect(choice(BotLevel.medium, 'As 4h 7d 9c'), BlackjackAction.stand);
      expect(choice(BotLevel.hard, 'As 4h 7d 9c'), BlackjackAction.double);
    });
  });

  group('Hard', () {
    test('follows the rules\' own chart: 11 vs ace doubles only when the dealer hits soft 17', () {
      expect(choice(BotLevel.hard, '5s Ah 6d 9c', rules: const BlackjackRules(insurance: false)), BlackjackAction.hit);
      expect(
        choice(BotLevel.hard, '5s Ah 6d 9c', rules: const BlackjackRules(insurance: false, dealerHitsSoft17: true)),
        BlackjackAction.double,
      );
    });

    test('surrenders when the chart says so, late or early', () {
      expect(
        choice(BotLevel.hard, 'Ts Th 6d 9c', rules: const BlackjackRules(surrender: Surrender.late)),
        BlackjackAction.surrender,
      );
      expect(
        choice(BotLevel.hard, 'Ts Ah 6d 9c', rules: const BlackjackRules(surrender: Surrender.early)),
        BlackjackAction.surrender,
      );
      expect(
        choice(BotLevel.hard, 'Ts Ah 9d 9c', rules: const BlackjackRules(surrender: Surrender.early)),
        BlackjackAction.keepPlaying,
      );
    });

    test('never takes insurance', () {
      expect(choice(BotLevel.hard, 'As Ad Kh 7c'), BlackjackAction.noInsurance);
    });

    test('plays every decision exactly as the chart reads', () {
      const rules = BlackjackRules(surrender: Surrender.late);
      final chart = BasicStrategyChart.forRules(rules);
      final table = BlackjackTable(rules, seed: 5);
      final bot = BlackjackBot(BotLevel.hard);
      var checked = 0;
      for (var i = 0; i < 300; i++) {
        final r = table.deal([1, 1]);
        while (!r.isOver) {
          final v = r.viewFor(r.turn!.seat);
          final a = bot.chooseAction(v);
          if (v.phase == RoundPhase.playing) {
            final h = v.handToPlay!;
            expect(
              a,
              chart.decide(
                total: h.total,
                cardCount: h.cards.length,
                upcard: v.dealerUpcard.rank,
                pairRank: h.isPair ? h.cards[0].rank : -1,
                canDouble: v.legalActions.contains(BlackjackAction.double),
                canSplit: v.legalActions.contains(BlackjackAction.split),
                canSurrender: v.legalActions.contains(BlackjackAction.surrender),
              ),
            );
            checked++;
          }
          r.apply(a);
        }
      }
      expect(checked, greaterThan(300));
    });
  });

  test('every bot only ever picks a legal action, under every preset', () {
    for (final preset in BlackjackPreset.values) {
      final rules = BlackjackRules.preset(preset);
      final table = BlackjackTable(rules, seed: preset.index + 1);
      final bots = [for (final l in BotLevel.values) BlackjackBot(l)];
      for (var i = 0; i < 150; i++) {
        final r = table.deal([1, 1, 1]);
        while (!r.isOver) {
          final seat = r.turn!.seat;
          final a = bots[seat].chooseAction(r.viewFor(seat));
          expect(r.legalActions(), contains(a), reason: '$preset');
          r.apply(a);
        }
      }
    }
  });

  test('the bot asked out of turn refuses', () {
    final r = stacked(const BlackjackRules(), 'Ts 9s 6h 7s 8s Tc', bets: [1, 1]);
    expect(() => BlackjackBot(BotLevel.hard).chooseAction(r.viewFor(1)), throwsStateError);
  });
}
