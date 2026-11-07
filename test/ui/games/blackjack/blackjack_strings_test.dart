// Blackjack's words: every coach reason, decision, outcome, rule and chart
// letter has text in English, Spanish and Chinese, with its numbers filled in.
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/blackjack/app/blackjack_analysis_codec.dart';
import 'package:pokerfection/src/games/blackjack/app/blackjack_grading.dart';
import 'package:pokerfection/src/games/blackjack/blackjack.dart';
import 'package:pokerfection/src/ui/games/blackjack/blackjack_coach_view.dart';
import 'package:pokerfection/src/ui/games/blackjack/l10n/blackjack_strings.dart';

void main() {
  for (final language in AppLanguage.values) {
    final b = BlackjackStrings.forLanguage(language);

    group(language.name, () {
      test('every coach reason reads as a few words, numbers filled in', () {
        for (final reason in BlackjackStrings.sampleReasons) {
          final text = b.reason(reason);
          expect(text.trim(), isNotEmpty, reason: '${reason.kind}');
          expect(text, isNot(contains('null')), reason: '${reason.kind}');
          expect(text.length, lessThan(60), reason: 'one short line: ${reason.kind} "$text"');
        }
        // The numbers go in: the upcard, the chance, the true count.
        String text(ReasonKind kind) => b.reason(BlackjackStrings.sampleReasons[kind.index]);
        expect(text(ReasonKind.dealerBustsOften), contains('10'));
        expect(text(ReasonKind.bustRisk), contains('62%'));
        expect(text(ReasonKind.countDeviation), contains('+2.5'));
        expect(text(ReasonKind.countDeviation), contains(b.action(BlackjackAction.stand)));
        expect(text(ReasonKind.countDeviation), contains(b.action(BlackjackAction.hit)));
      });

      test('a reason travels as a code and comes back as the same words', () {
        for (final reason in BlackjackStrings.sampleReasons) {
          expect(b.reason(parseReasonCode(reasonCode(reason))), b.reason(reason));
        }
      });

      test('every decision, outcome, rule and coach mode has a name', () {
        final names = [
          for (final a in BlackjackAction.values) b.action(a),
          for (final o in HandOutcome.values) b.outcome(o),
          for (final p in BlackjackPreset.values) b.preset(p),
          for (final r in DoubleRule.values) b.doubleRule(r),
          for (final r in Surrender.values) b.surrenderRule(r),
          for (final m in CoachMode.values) b.coachMode(m),
        ];
        expect(names.every((n) => n.trim().isNotEmpty), isTrue);
        expect({for (final a in BlackjackAction.values) b.action(a)}, hasLength(BlackjackAction.values.length));
      });

      test('the chart\'s letters are all different, each with its meaning', () {
        final letters = [for (final c in ChartCode.values) b.chartLetter(c)];
        expect(letters.toSet(), hasLength(ChartCode.values.length));
        expect(letters.every((l) => l.isNotEmpty && l.length <= 3), isTrue, reason: 'they fit a small cell');
        expect({for (final c in ChartCode.values) b.chartMeaning(c)}, hasLength(ChartCode.values.length));
      });

      test('totals as players say them', () {
        expect(b.total(const HandTotal(17, false)), '17');
        expect(b.total(const HandTotal(17, true)), b.softTotal(17));
        expect(b.total(const HandTotal(24, false)), b.bust);
      });

      test('moves in the coach list are the buttons\' words; insurance on a blackjack is even money', () {
        expect(blackjackMoveText(b, '0:H', deal: 'Deal'), b.action(BlackjackAction.hit));
        expect(blackjackMoveText(b, '1:P', deal: 'Deal'), b.action(BlackjackAction.split));
        expect(blackjackMoveText(b, '0:I', evenMoney: true, deal: 'Deal'), b.evenMoney);
        expect(blackjackMoveText(b, 'd', deal: 'Deal'), 'Deal');
      });

      test('the glossary covers every term, and the rules every part of a round', () {
        expect(b.glossary, hasLength(BlackjackTerm.values.length));
        expect(b.rulesSections, hasLength(8));
      });
    });
  }

  test('the words players use: the coach\'s label and the Count tag', () {
    expect(
      [for (final l in AppLanguage.values) BlackjackStrings.forLanguage(l).pickLabel],
      ['Basic strategy', 'Estrategia básica', '基本策略'],
    );
    expect(
      [for (final l in AppLanguage.values) BlackjackStrings.forLanguage(l).action(BlackjackAction.stand)],
      ['Stand', 'Plantarse', '停牌'],
    );
    expect(
      [for (final l in AppLanguage.values) BlackjackStrings.forLanguage(l).chartLetter(ChartCode.surrenderOrHit)],
      ['Rh', 'R', '降要'],
    );
  });
}
