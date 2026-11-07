// Big Two's words in English, Spanish and Chinese: every reason, every kind
// of play, every setup choice and every glossary entry has text in all
// three, and the translations really are translations.
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_rules_codec.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/ui/games/big_two/l10n/big_two_strings.dart';

void main() {
  final en = BigTwoStrings.forLanguage(AppLanguage.english);

  for (final language in AppLanguage.values) {
    final t = BigTwoStrings.forLanguage(language);

    group(language.name, () {
      test('the coach is labelled GTO, as in Fight the Landlord', () {
        expect(t.pickLabel, 'GTO');
        expect(t.tagLabel('count'), isNull, reason: 'no tags besides the pick');
      });

      test('every coach reason and every kind of play has text', () {
        for (final reason in CoachReason.values) {
          expect(t.reason(reason).trim(), isNotEmpty, reason: '$reason');
        }
        for (final kind in PlayKind.values) {
          expect(t.kind(kind).trim(), isNotEmpty, reason: '$kind');
          expect(t.kindHint(kind).trim(), isNotEmpty, reason: '$kind');
        }
      });

      test('every setup choice has a name: presets, straights, flushes, scoring', () {
        for (final preset in BigTwoPreset.values) {
          expect(t.preset(preset), isNotEmpty);
        }
        final straightNames = {for (final rule in BigTwoRulesCodec.straights) t.straightName(rule)};
        expect(straightNames, hasLength(BigTwoRulesCodec.straights.length), reason: 'each straight order its own name');
        expect({for (final o in FlushOrder.values) t.flushOrder(o)}, hasLength(FlushOrder.values.length));
        expect({for (final s in BigTwoScoring.values) t.scoringName(s)}, hasLength(BigTwoScoring.values.length));
      });

      test('the glossary has every term with a meaning, and the rules have every section', () {
        // Every term, plus each straight order, flush order and preset.
        expect(
          t.glossary,
          hasLength(
            BigTwoTerm.values.length +
                BigTwoStrings.allStraights.length +
                FlushOrder.values.length +
                BigTwoPreset.values.length,
          ),
        );
        for (final entry in t.glossary) {
          expect(entry.term.trim(), isNotEmpty);
          expect(entry.definition.trim(), isNotEmpty, reason: entry.term);
        }
        expect(t.rulesSections, hasLength(en.rulesSections.length));
        for (final (title, body) in t.rulesSections) {
          expect(title, isNotEmpty);
          expect(body.length, greaterThan(language == AppLanguage.chinese ? 8 : 20), reason: title);
        }
      });

      test('every sample is text, as many as in English', () {
        final samples = t.samples();
        expect(samples.length, en.samples().length);
        expect(samples.every((s) => s.trim().isNotEmpty), isTrue);
      });

      if (language != AppLanguage.english) {
        test('most texts differ from the English (names and GTO aside)', () {
          final mine = t.samples(), english = en.samples();
          var differ = 0;
          for (var i = 0; i < mine.length; i++) {
            if (mine[i] != english[i]) differ++;
          }
          expect(differ / mine.length, greaterThan(0.8));
        });
      }

      test('button labels are short enough for a phone\'s panel', () {
        for (final label in [t.play, t.pass, t.clear]) {
          expect(label.length, lessThanOrEqualTo(8), reason: label);
        }
      });
    });
  }

  test('Chinese uses the words 锄大地 players use', () {
    final zh = BigTwoStrings.forLanguage(AppLanguage.chinese);
    expect([for (final k in PlayKind.values) zh.kind(k)], ['过', '单张', '对子', '三条', '顺子', '同花', '葫芦', '铁支', '同花顺']);
    expect(zh.cardCounter, '记牌器');
  });
}
