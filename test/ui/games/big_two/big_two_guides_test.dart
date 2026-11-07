// Big Two's guides: Rules, and Hand ranks with real example cards that the
// engine reads as the kinds the guide names, in the order it shows them.
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_guides.dart';
import 'package:pokerfection/src/ui/games/big_two/l10n/big_two_strings.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';
import 'package:pokerfection/src/ui/widgets/card_view.dart' show SuitIcon;

import '../../../kit/shots.dart';
import 'big_two_test_util.dart';

void main() {
  setUpAll(loadShotFonts);

  group('the examples', () {
    for (final preset in BigTwoPreset.values) {
      final rules = BigTwoRules.preset(preset);
      final examples = BigTwoHandExamples(rules);

      test('$preset: each example is the kind it names', () {
        for (final kind in PlayKind.values.where((k) => k != PlayKind.pass)) {
          expect(rules.classify(examples.of(kind))?.kind, kind, reason: '$kind');
        }
      });

      test('$preset: the five-card hands are shown from low to high', () {
        final plays = [for (final kind in BigTwoHandExamples.fiveCardKinds) rules.classify(examples.of(kind))!];
        for (var i = 1; i < plays.length; i++) {
          // Ranked above (under "match the type" only a bomb may still beat it).
          expect(plays[i].key, greaterThan(plays[i - 1].key), reason: '${plays[i]} above ${plays[i - 1]}');
          if (!rules.fiveCardSameType) expect(rules.beats(plays[i], plays[i - 1]), isTrue);
        }
      });

      test('$preset: the lowest and highest straights are straights, and the highest beats the lowest', () {
        final low = rules.classify(examples.lowestStraight)!;
        final high = rules.classify(examples.highestStraight)!;
        expect(low.kind, PlayKind.straight);
        expect(high.kind, PlayKind.straight);
        expect(rules.beats(high, low), isTrue);
      });

      test('$preset: the single is the highest card of all', () {
        final top = rules.classify(examples.of(PlayKind.single))!;
        expect(top.codes.single, 51);
      });
    }
  });

  group('fits every size and language', () {
    for (final size in bigTwoSizes) {
      for (final language in AppLanguage.values) {
        testWidgets(shotTag(size, language), (tester) async {
          await pumpShot(
            tester,
            BigTwoHandRanksGuide(rules: BigTwoRules.taiwan()),
            size: size,
            language: language,
          );
          await tester.pump();
          expect(find.text(BigTwoStrings.forLanguage(language).handRanks), findsOneWidget);
          // The preset row wraps: every preset, and Custom, show on screen.
          final strings = BigTwoStrings.forLanguage(language);
          for (final label in [...BigTwoPreset.values.map(strings.preset), KitStrings.forLanguage(language).custom]) {
            final chip = find.descendant(of: find.byKey(const ValueKey('presets')), matching: find.text(label));
            expect(tester.getRect(chip).right, lessThanOrEqualTo(size.width), reason: '"$label" shows');
          }
          await pumpShot(tester, const BigTwoRulesGuide(), size: size, language: language);
          await tester.pump();
          final first = BigTwoStrings.forLanguage(language).rulesSections.first;
          expect(find.text(first.$1), findsOneWidget);
        });
      }
    }
  });

  testWidgets('the suit order follows the rules, and switches with the preset row', (tester) async {
    await pumpShot(tester, const BigTwoHandRanksGuide(), size: const Size(1280, 800));
    await tester.pump();
    List<int> suitsShown() => [
      for (final icon in tester.widgetList<SuitIcon>(
        find.descendant(of: find.byKey(const ValueKey('suit order')), matching: find.byType(SuitIcon)),
      ))
        icon.suit,
    ];
    // Standard: ♦ < ♣ < ♥ < ♠ (the drawn suits: 1 diamonds, 0 clubs, 2 hearts, 3 spades).
    expect(suitsShown(), [1, 0, 2, 3]);
    final en = BigTwoStrings.forLanguage(AppLanguage.english);
    expect(find.text(en.bombsHint), findsNothing, reason: 'no bombs in the standard game');
    await tester.tap(find.text(en.preset(BigTwoPreset.pusoyDos)));
    await tester.pump();
    expect(suitsShown(), [0, 3, 2, 1], reason: 'Pusoy Dos: ♣ < ♠ < ♥ < ♦');
    await tester.tap(find.text(en.preset(BigTwoPreset.taiwan)));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text(en.bombsHint),
      200,
      scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first,
    );
    expect(find.text(en.bombsHint), findsOneWidget, reason: 'Taiwan has bombs');
  });

  testWidgets('the cards are drawn as Settings set them', (tester) async {
    await pumpShot(tester, const BigTwoHandRanksGuide(), size: const Size(1280, 800));
    await tester.pump();
    expect(find.byType(GameCardView), findsWidgets);
  });
}
