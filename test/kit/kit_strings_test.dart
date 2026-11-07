import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/kit/coach_answer.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';

void main() {
  final en = KitStrings.forLanguage(AppLanguage.english);

  test('every shared game word has text in English, Spanish and Chinese', () {
    for (final language in AppLanguage.values) {
      final samples = KitStrings.forLanguage(language).samples();
      expect(samples, hasLength(en.samples().length));
      for (final (i, text) in samples.indexed) {
        expect(text.trim(), isNotEmpty, reason: '${language.name} #$i');
      }
    }
  });

  test('Spanish and Chinese differ from English, except words Spanish borrows (Bots, Coach, pts)', () {
    final english = en.samples();
    const borrowed = {'Bots', 'Coach', '+1.4 pts'};
    for (final language in [AppLanguage.spanish, AppLanguage.chinese]) {
      final other = KitStrings.forLanguage(language).samples();
      for (var i = 0; i < english.length; i++) {
        if (language == AppLanguage.spanish && borrowed.contains(english[i])) continue;
        expect(other[i], isNot(english[i]), reason: '${language.name}: "${english[i]}" is not translated');
      }
    }
  });

  test('"Training" is not poker\'s "GTO Training"', () {
    expect([for (final l in AppLanguage.values) KitStrings.forLanguage(l).trainingMode], ['Training', 'Entrenamiento', '训练']);
  });

  test('amounts carry their unit after the number', () {
    expect(en.amount(ValueUnit.winChance, -0.07), '−7%');
    expect(en.amount(ValueUnit.points, 1.4), '+1.4 pts');
    expect(en.amount(ValueUnit.bets, -0.03), '−0.03 bets');
    expect(KitStrings.forLanguage(AppLanguage.chinese).amount(ValueUnit.bets, -0.03), '−0.03 注');
  });

  test('every kit glossary term has a definition', () {
    for (final language in AppLanguage.values) {
      final k = KitStrings.forLanguage(language);
      for (final term in KitTerm.values) {
        expect(k.entry(term).term, isNotEmpty);
        expect(k.entry(term).definition.length, greaterThan(k.entry(term).term.length));
      }
    }
  });
}
