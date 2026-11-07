import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/ui/games/big_two/l10n/big_two_strings.dart';
import 'package:pokerfection/src/ui/games/blackjack/l10n/blackjack_strings.dart';
import 'package:pokerfection/src/ui/games/doudizhu/l10n/doudizhu_strings.dart';
import 'package:pokerfection/src/ui/games/gomoku/l10n/gomoku_strings.dart';
import 'package:pokerfection/src/ui/kit/l10n/game_strings.dart';

/// Each game's strings, by its key.
final _games = <String, GameStrings Function(AppLanguage language)>{
  'gomoku': GomokuStrings.forLanguage,
  'big_two': BigTwoStrings.forLanguage,
  'doudizhu': LandlordStrings.forLanguage,
  'blackjack': BlackjackStrings.forLanguage,
};

void main() {
  for (final MapEntry(key: game, value: strings) in _games.entries) {
    group(game, () {
      final english = strings(AppLanguage.english);

      test('every text is there in all three languages, with as many samples and glossary entries', () {
        for (final language in AppLanguage.values) {
          final s = strings(language);
          expect(s.pickLabel, isNotEmpty);
          expect(s.samples(), hasLength(english.samples().length), reason: language.name);
          expect(s.samples().every((text) => text.trim().isNotEmpty), isTrue, reason: language.name);
          expect(s.glossary, hasLength(english.glossary.length), reason: language.name);
          for (final term in s.glossary) {
            expect([term.term.trim(), term.definition.trim()], everyElement(isNotEmpty));
          }
          expect(s.rulesSections, hasLength(english.rulesSections.length), reason: language.name);
        }
      });

      test('at least half of the Spanish and Chinese texts differ from English ("GTO" may stay)', () {
        // The pick label can be the same everywhere: "GTO" is a name.
        final englishTexts = english.samples().where((t) => t != english.pickLabel).toList();
        for (final language in [AppLanguage.spanish, AppLanguage.chinese]) {
          final s = strings(language);
          final texts = s.samples().where((t) => t != s.pickLabel).toList();
          final differ = [for (var i = 0; i < texts.length; i++) if (texts[i] != englishTexts[i]) i];
          expect(differ.length * 2, greaterThanOrEqualTo(texts.length), reason: language.name);
        }
      });
    });
  }

  test("the coach's labels are the user's: Best move, GTO, GTO, Basic strategy", () {
    expect([for (final s in _games.values) s(AppLanguage.english).pickLabel], ['Best move', 'GTO', 'GTO', 'Basic strategy']);
    expect(BlackjackStrings.forLanguage(AppLanguage.spanish).pickLabel, 'Estrategia básica');
    expect(BlackjackStrings.forLanguage(AppLanguage.chinese).pickLabel, '基本策略');
    expect(
      [for (final l in AppLanguage.values) BlackjackStrings.forLanguage(l).tagLabel('count')],
      ['Count', 'Conteo', '算牌'],
    );
  });
}
