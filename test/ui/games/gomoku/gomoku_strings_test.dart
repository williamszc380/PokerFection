import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/gomoku/gomoku.dart';
import 'package:pokerfection/src/ui/games/gomoku/gomoku_coach_view.dart';
import 'package:pokerfection/src/ui/games/gomoku/l10n/gomoku_strings.dart';

void main() {
  final all = {for (final l in AppLanguage.values) l: GomokuStrings.forLanguage(l)};
  final en = all[AppLanguage.english]!;

  test('every coach reason has a few words in every language', () {
    for (final strings in all.values) {
      for (final reason in MoveReason.values) {
        final text = strings.reason(reason);
        expect(text.trim(), isNotEmpty, reason: '$reason');
        expect(text.length, lessThan(32), reason: 'one short line: $text');
      }
    }
  });

  test('every term, figure and rule has text in every language, and the other languages are translated', () {
    for (final MapEntry(key: language, value: strings) in all.entries) {
      for (final t in GomokuTerm.values) {
        expect(strings.term(t), isNotEmpty);
        expect(strings.definition(t), isNotEmpty);
        if (language != AppLanguage.english) expect(strings.definition(t), isNot(en.definition(t)), reason: '$t');
      }
      for (final f in GomokuFigure.values) {
        expect(strings.figureTitle(f), isNotEmpty);
        expect(strings.figureCaption(f), isNotEmpty);
      }
      for (final w in WinRule.values) {
        expect(strings.ruleName(w), isNotEmpty);
      }
      expect(strings.glossary, hasLength(GomokuTerm.values.length));
      expect(strings.rulesSections, hasLength(en.rulesSections.length));
      expect(strings.samples(), hasLength(en.samples().length));
    }
  });

  test('moves read as Renju notation, a pass as the word', () {
    for (final strings in all.values) {
      expect(strings.moveName('h8'), 'h8');
      expect(strings.moveName('pass'), strings.pass);
    }
  });

  test('proofs read as badges: "Wins in 3", "Loses in 2"', () {
    expect(gomokuProofText(en, 'win:3'), 'Wins in 3');
    expect(gomokuProofText(en, 'loss:2'), 'Loses in 2');
    expect(gomokuProofText(en, 'sure'), isNull);
    expect(gomokuProofText(all[AppLanguage.spanish]!, 'win:3'), 'Gana en 3');
    expect(gomokuProofText(all[AppLanguage.chinese]!, 'loss:2'), '2步负');
  });

  test("the user's own seat is 'Player', as in Hold'em, never 'You'", () {
    expect([for (final s in all.values) s.you], ['Player', 'Jugador', '玩家']);
    for (final strings in all.values) {
      expect(strings.samples(), isNot(anyOf(contains('You'), contains('Tú'), contains('你'))));
    }
  });

  test('the coach is "Best move" in every language, not "GTO"', () {
    expect([for (final s in all.values) s.pickLabel], ['Best move', 'Mejor jugada', '最佳着法']);
  });

  test('the glossary explains the coach\'s words, the shapes and the rules', () {
    final terms = [for (final t in en.glossary) t.term];
    expect(terms, containsAll(['Best move', 'Open three', 'Four-three', 'VCF', 'Forbidden move', 'Renju']));
  });

  test('"Black\'s edge" never says Renju evens the game: Renju without an opening rule, as played here, is a proven win for Black', () {
    final edge = {for (final MapEntry(:key, :value) in all.entries) key: value.definition(GomokuTerm.firstMove)};
    expect(edge[AppLanguage.english], allOf(isNot(contains('even it out')), contains('still has the edge')));
    expect(edge[AppLanguage.spanish], allOf(isNot(contains('equilibran')), contains('siguen con ventaja')));
    expect(edge[AppLanguage.chinese], allOf(isNot(contains('公平')), contains('仍占优')));
  });
}
