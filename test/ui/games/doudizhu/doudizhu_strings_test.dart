import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_coach_view.dart';
import 'package:pokerfection/src/ui/games/doudizhu/l10n/doudizhu_strings.dart';

void main() {
  final all = {for (final l in AppLanguage.values) l: LandlordStrings.forLanguage(l)};
  final en = all[AppLanguage.english]!;

  test('the coach is "GTO" in every language', () {
    for (final s in all.values) {
      expect(s.pickLabel, 'GTO');
    }
  });

  test("the kitty is not called by the poker pot's word: one app, one word per thing", () {
    for (final MapEntry(key: language, value: s) in all.entries) {
      final pot = S.forLanguage(language).term(GlossaryTerm.pot).toLowerCase();
      for (final text in [s.kitty, s.kittyShown, s.term(LandlordTerm.kitty), s.definition(LandlordTerm.landlord)]) {
        expect(text.toLowerCase(), isNot(contains(pot)), reason: '$language: $text');
      }
      for (final (_, body) in s.rulesSections) {
        expect(body.toLowerCase(), isNot(contains(pot)), reason: '$language: $body');
      }
    }
  });

  test('every coach reason has a few words in every language, all different', () {
    for (final s in all.values) {
      final words = [for (final r in DdzReason.values) s.reason(r)];
      expect(words, everyElement(isNotEmpty));
      expect(words.toSet(), hasLength(words.length), reason: 'two reasons read the same');
    }
  });

  test('every kind of play has a name and a rule in every language', () {
    for (final s in all.values) {
      final names = [for (final t in PlayType.values) s.kind(t)];
      expect(names, everyElement(isNotEmpty));
      expect(names.toSet(), hasLength(names.length));
      expect([for (final t in PlayType.values) s.kindRule(t)], everyElement(isNotEmpty));
    }
  });

  test('Spanish and Chinese are translated, not copied', () {
    for (final l in [AppLanguage.spanish, AppLanguage.chinese]) {
      final s = all[l]!;
      final same = [
        for (final (i, text) in s.samples().indexed)
          if (text == en.samples()[i]) text,
      ];
      // Only the label "GTO", the multiplier marks and the like stay as they are.
      expect(same.length, lessThan(5), reason: '${l.code}: $same');
    }
  });

  test('the glossary and the rules have the same entries in every language', () {
    for (final s in all.values) {
      expect(s.glossary, hasLength(LandlordTerm.values.length));
      expect(s.rulesSections, hasLength(en.rulesSections.length));
      for (final (title, body) in s.rulesSections) {
        expect(title, isNotEmpty);
        expect(body, isNotEmpty);
      }
      expect(s.samples(), hasLength(en.samples().length));
    }
  });

  test('moves read as players say them', () {
    Play play(String ranks, PlayType type) => classifyPlay(parseRanks(ranks)).firstWhere((p) => p.type == type);
    final zh = all[AppLanguage.chinese]!;
    expect(ddzMoveLabel(en, '0:xpair:77', DdzRules.standard), 'Pair 77');
    expect(ddzMoveLabel(en, '0:b2', DdzRules.standard), 'Bid 2');
    expect(ddzMoveLabel(en, '1:p', DdzRules.standard), 'Pass');
    expect(ddzMoveLabel(en, '2:r1', DdzRules.standard), 'Rob');
    expect(ddzPlayLabel(en, play('9994', PlayType.trioSolo)), 'Trio + 1 999 + 4');
    expect(ddzPlayLabel(en, play('TJQKA', PlayType.straight)), 'Straight 10 J Q K A');
    expect(ddzPlayLabel(en, play('BR', PlayType.rocket)), 'Rocket');
    expect(ddzPlayLabel(en, play('R', PlayType.solo)), 'Big Joker');
    expect(ddzPlayLabel(zh, play('BR', PlayType.rocket)), '王炸');
    expect(ddzMoveLabel(zh, '0:b3', DdzRules.standard), '3分');
  });
}
