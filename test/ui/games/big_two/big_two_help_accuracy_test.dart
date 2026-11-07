// The rules explained, checked against what the engine really does in the
// game a player now starts with (2 players, 17 cards each) and against the
// switch each "?" sits beside: an explanation must not promise a card the
// deal can leave out, a penalty the engine doesn't charge, or a tie-break
// example made of a run that isn't a straight.
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_controller.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_setup.dart';
import 'package:pokerfection/src/ui/games/big_two/l10n/big_two_strings.dart';
import 'package:pokerfection/src/ui/kit/help.dart';

import '../../../kit/shots.dart';

/// A run as plain text ("A-2-3-4-5"), without the word joiners runText puts
/// after each dash.
String plain(String run) => run.replaceAll('⁠', '');

void main() {
  setUpAll(loadShotFonts);

  group('the "?" beside Match 5-card type', () {
    for (final language in AppLanguage.values) {
      testWidgets('says what the switch does: a five-card hand only falls to one of its own type '
          '(${language.name})', (tester) async {
        await pumpShot(
          tester,
          BigTwoSetupScreen(initial: BigTwoSetup.from(null)),
          size: const Size(1280, 800),
          language: language,
        );
        await tester.pump();
        final row = find.byKey(const ValueKey('same type'));
        final help = find.descendant(of: row, matching: find.byType(TermsHelpButton));
        expect(help, findsOneWidget);
        await tester.ensureVisible(help);
        await tester.tap(help);
        await tester.pumpAndSettle();
        final t = BigTwoStrings.forLanguage(language);
        expect(
          find.textContaining(t.sameTypeHint),
          findsOneWidget,
          reason: 'the "?" shows the five-card hand entry and the presets, never what the rule changes',
        );
        await tester.tap(find.text(S.forLanguage(language).ok));
        await tester.pumpAndSettle();
      });
    }
  });

  group('each straight order\'s tie-break example is a straight in that order', () {
    for (final language in AppLanguage.values) {
      test(language.name, () {
        final t = BigTwoStrings.forLanguage(language);
        for (final rule in BigTwoStrings.allStraights) {
          final tie = plain(t.straightTieOf(rule));
          for (var start = 0; start < 13; start++) {
            if (rule.order.contains(start)) continue;
            final run = plain(BigTwoStrings.runText(start));
            expect(
              tie,
              isNot(contains(run)),
              reason: '${t.straightTerm(rule)} lists $run under "not straights", then uses it as its tie example',
            );
          }
        }
      });
    }
  });

  group('penalty scoring as the engine charges it in the default 17-card deal', () {
    test('the engine: 15 of 17 cards left pays 2 per card, 17 of 17 pays 3', () {
      final rules = BigTwoRules.standard(players: BigTwoSetup.defaultPlayers);
      expect(rules.cardsEach, 17);
      final masks = Uint8List(rules.players * 13);
      expect(penaltyFor(rules, masks, 1, 15, 17), 30);
      expect(penaltyFor(rules, masks, 1, 13, 17), 26);
    });

    // The words each language uses for "10 to 12 cards", the 13-card limits.
    const thirteenCardBand = {
      AppLanguage.english: '10 to 12',
      AppLanguage.spanish: '10 a 12',
      AppLanguage.chinese: '10到12',
    };
    for (final language in AppLanguage.values) {
      test('the glossary and the Rules guide don\'t stop the 2-per-card band at 12 (${language.name})', () {
        final t = BigTwoStrings.forLanguage(language);
        final band = thirteenCardBand[language]!;
        expect(
          t.definition(BigTwoTerm.penalty),
          isNot(contains(band)),
          reason: 'with 17 cards each, 13 to 16 cards left also pay 2 per card',
        );
        for (final (title, text) in t.rulesSections) {
          expect(text, isNot(contains(band)), reason: '$title: 13 to 16 cards left also pay 2 per card');
        }
      });
    }
  });

  test('the preset "?" does not say the 3♦ starts when the default 2-player deal leaves it out', () {
    final rules = BigTwoRules.standard(players: BigTwoSetup.defaultPlayers);
    final threeOfDiamonds = rules.codeOf(Card.of(Ranks.three, Suit.diamonds));
    // A deal of the game a player starts with where the 3♦ is one of the 18
    // unused cards: someone else's lowest card starts.
    final deal = [for (var seed = 1; seed < 200; seed++) BigTwoState.deal(rules, seed: seed)]
        .firstWhere((s) => s.startCode != threeOfDiamonds);
    expect(deal.legalMoves().every((p) => !p.containsCode(threeOfDiamonds)), isTrue);
    final t = BigTwoStrings.forLanguage(AppLanguage.english);
    final entry = t.presetEntry(BigTwoPreset.standard).definition;
    expect(
      entry,
      isNot(contains('The 3♦ starts')),
      reason: 'about one 2-player deal in three has no 3♦: the lowest card dealt starts',
    );
    expect(entry, contains('The lowest card dealt starts (the 3♦ when all are dealt)'));
  });

  for (final language in AppLanguage.values) {
    test("the Rules guide's Start says the lowest card dealt, not always the 3♦ (${language.name})", () {
      final t = BigTwoStrings.forLanguage(language);
      final start = t.rulesSections[3].$2;
      expect(
        start,
        contains(
          const {
            AppLanguage.english: 'lowest card dealt',
            AppLanguage.spanish: 'carta más baja repartida',
            AppLanguage.chinese: '发出的最小的牌',
          }[language]!,
        ),
      );
    });
  }
}
