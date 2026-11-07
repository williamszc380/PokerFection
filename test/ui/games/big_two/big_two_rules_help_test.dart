// What the presets change, explained: the "?" beside the Rules preset row
// and beside each rule switch (Straights first: which runs count in each
// preset and how they rank), the glossary, and the presets side by side in
// the Rules guide, in English, Spanish and Chinese, each citing the sources
// the engine follows. The words are read from the engine's rules, so these
// tests check them against the engine.
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_controller.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_guides.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_setup.dart';
import 'package:pokerfection/src/ui/games/big_two/l10n/big_two_strings.dart';
import 'package:pokerfection/src/ui/kit/help.dart';
import 'package:pokerfection/src/ui/kit/setup_kit.dart';

import '../../../kit/shots.dart';
import 'big_two_test_util.dart';

String run(int start) => BigTwoStrings.runText(start);

/// The "?" in the setup row (a SwitchRow or SetupSection) holding [key].
Finder helpBeside(String key) {
  final row = find.ancestor(of: find.byKey(ValueKey(key)), matching: find.byType(SetupSection));
  return find.descendant(
    of: row.evaluate().isEmpty ? find.byKey(ValueKey(key)) : row.first,
    matching: find.byType(TermsHelpButton),
  );
}

Future<void> openHelp(WidgetTester tester, Finder help) async {
  await tester.ensureVisible(help);
  await tester.tap(help);
  await tester.pumpAndSettle();
}

Future<void> closeHelp(WidgetTester tester, AppLanguage language) async {
  await tester.tap(find.text(S.forLanguage(language).ok));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadShotFonts);

  group('the words match the engine', () {
    for (final language in AppLanguage.values) {
      final t = BigTwoStrings.forLanguage(language);

      group(language.name, () {
        test('each preset says who starts, its lowest and highest straight, its scoring, and its source', () {
          for (final preset in BigTwoPreset.values) {
            final rules = BigTwoRules.preset(preset);
            final entry = t.presetEntry(preset);
            expect(entry.term, t.presetTerm(preset));
            final text = entry.definition;
            expect(text, contains(Card.of(Ranks.three, rules.suitOrder.first).label), reason: '$preset: who starts');
            expect(text, contains(BigTwoStrings.suitsText(rules)), reason: '$preset: suits');
            expect(text, contains(run(rules.straights.order.first)), reason: '$preset: lowest straight');
            expect(text, contains(run(rules.straights.order.last)), reason: '$preset: highest straight');
            expect(text, contains(t.flushHint(rules.flushOrder)), reason: '$preset: flushes');
            expect(text, contains(rules.bombs ? t.bombsHint : t.noBombs), reason: '$preset: bombs');
            expect(text, contains(rules.passLockout ? t.lockoutOn : t.lockoutOff), reason: '$preset: passing');
            expect(text.contains(t.dragonOn), rules.dragonWins, reason: '$preset: the dragon');
            expect(text, contains(t.scoringName(rules.scoring)), reason: '$preset: scoring');
            for (final source in BigTwoSources.ofPreset(preset)) {
              expect(text, contains(t.sourceName(source)), reason: '$preset cites $source');
            }
          }
        });

        test('the presets differ where the engine says: Hong Kong and Taiwan straights, the 3♣ in Taiwan', () {
          final hk = t.presetEntry(BigTwoPreset.hongKong).definition;
          expect(t.straightsLine(run(0), run(11)), isIn(hk.split('\n')), reason: 'Hong Kong: A-2-3-4-5 tops');
          final tw = t.presetEntry(BigTwoPreset.taiwan).definition;
          expect(t.straightsLine(run(11), run(12)), isIn(tw.split('\n')), reason: 'Taiwan: 2-3-4-5-6 tops');
          expect(tw, contains('3♣'));
          expect(tw, contains(t.sameTypeHint));
          expect(t.presetEntry(BigTwoPreset.standard).definition, contains(t.straightsLine(run(11), run(7))));
        });

        test('each straight order lists its runs low to high, the runs it does not count, and its tie-break', () {
          for (final rule in BigTwoStrings.allStraights) {
            final text = t.straightEntry(rule).definition;
            // The runs shown appear in the engine's order.
            final shown = [...rule.order.take(2), ...rule.order.skip(rule.order.length - 3)];
            var at = -1;
            for (final start in shown) {
              final i = text.indexOf(run(start));
              expect(i, greaterThan(at), reason: '${rule.name}: ${run(start)} after the one below it');
              at = i;
            }
            for (final start in [for (var s = 0; s < 13; s++) s].where((s) => !rule.order.contains(s))) {
              expect(text, contains(run(start)), reason: '${rule.name}: not ${run(start)}');
            }
            expect(text, contains(t.straightTieOf(rule)));
            for (final source in BigTwoSources.ofStraights(rule)) {
              expect(text, contains(t.sourceName(source)));
            }
          }
          expect(
            t.straightEntry(StraightRule.pagat).definition,
            contains(run(8)),
            reason: 'J-Q-K-A-2 is not a straight',
          );
          expect(t.straightEntry(StraightRule.twoHigh).definition, contains(t.noPreset));
        });

        test('the glossary has every preset, straight order and flush order', () {
          final terms = [for (final entry in t.glossary) entry.term];
          for (final preset in BigTwoPreset.values) {
            expect(terms, contains(t.presetTerm(preset)));
          }
          for (final rule in BigTwoStrings.allStraights) {
            expect(terms, contains(t.straightTerm(rule)));
          }
          for (final order in FlushOrder.values) {
            expect(terms, contains(t.flushTerm(order)));
          }
          expect(terms.indexOf(t.straightTerm(StraightRule.pagat)), terms.indexOf(t.term(BigTwoTerm.straight)) + 1);
        });

        test('a rule switch in every preset: Bombs on only in Taiwan', () {
          final lines = t.byPresetEntry((r) => t.onOff(r.bombs), sources: BigTwoSources.bombs).definition.split('\n');
          expect(lines, [
            t.labelled(t.preset(BigTwoPreset.standard), t.off),
            t.labelled(t.preset(BigTwoPreset.hongKong), t.off),
            t.labelled(t.preset(BigTwoPreset.taiwan), t.on),
            t.labelled(t.preset(BigTwoPreset.pusoyDos), t.off),
            t.source([for (final s in BigTwoSources.bombs) t.sourceName(s)]),
          ]);
        });
      });
    }
  });

  group('the setup\'s "?"', () {
    for (final language in AppLanguage.values) {
      final t = BigTwoStrings.forLanguage(language);

      testWidgets('beside the presets: what each one sets (${language.name})', (tester) async {
        await pumpShot(
          tester,
          BigTwoSetupScreen(initial: BigTwoSetup.from(null)),
          size: const Size(1280, 800),
          language: language,
        );
        await tester.pump();
        await openHelp(tester, find.byKey(const ValueKey('presets help')));
        for (final preset in BigTwoPreset.values) {
          expect(find.text(t.presetTerm(preset)), findsOneWidget, reason: '$preset');
        }
        expect(find.textContaining(t.straightsLine(run(0), run(11))), findsOneWidget, reason: 'Hong Kong');
        await closeHelp(tester, language);
      });

      testWidgets('beside Straights: each order\'s runs, then each preset\'s order (${language.name})', (tester) async {
        await pumpShot(
          tester,
          BigTwoSetupScreen(initial: BigTwoSetup.from(null)),
          size: const Size(1280, 800),
          language: language,
        );
        await tester.pump();
        await openHelp(tester, helpBeside('straights'));
        for (final rule in BigTwoStrings.allStraights) {
          expect(find.text(t.straightTerm(rule)), findsOneWidget);
        }
        expect(find.text(t.byPreset), findsOneWidget);
        expect(
          find.textContaining(t.labelled(t.preset(BigTwoPreset.taiwan), t.straightName(StraightRule.taiwan))),
          findsOneWidget,
        );
        await closeHelp(tester, language);
      });
    }

    testWidgets('every rule switch has its "?", with the presets and the source', (tester) async {
      await pumpShot(tester, BigTwoSetupScreen(initial: BigTwoSetup.from(null)), size: const Size(1280, 800));
      await tester.pump();
      for (final key in [
        'flushes',
        'bombs',
        'same type',
        'lockout',
        'last card',
        'dragon',
        'top two',
        'scoring',
        'double twos',
        'double bombs',
      ]) {
        expect(helpBeside(key), findsOneWidget, reason: key);
      }
      final t = BigTwoStrings.forLanguage(AppLanguage.english);
      await openHelp(tester, helpBeside('lockout'));
      expect(find.text(t.byPreset), findsOneWidget);
      expect(find.textContaining(t.sourceName(BigTwoSource.pagatIndonesia)), findsOneWidget);
      await closeHelp(tester, AppLanguage.english);
    });
  });

  group('the Rules guide compares the presets', () {
    testWidgets('one column per preset, the values from the engine, the sources with their links', (tester) async {
      await pumpShot(tester, const BigTwoRulesGuide(), size: const Size(1280, 800));
      await tester.pump();
      final table = find.byKey(const ValueKey('preset table'));
      await tester.scrollUntilVisible(table, 300, scrollable: find.byType(Scrollable).first);
      final t = BigTwoStrings.forLanguage(AppLanguage.english);
      Finder inTable(String text) => find.descendant(of: table, matching: find.text(text));
      for (final preset in BigTwoPreset.values) {
        // At least its column's heading ("Pusoy Dos" is a scoring too).
        expect(inTable(t.preset(preset)), findsWidgets);
      }
      // The switches on in some preset: Taiwan's bombs and same type, Hong Kong's dragon and top 2.
      expect(inTable('✓'), findsNWidgets(4));
      expect(inTable(run(12)), findsOneWidget, reason: 'Taiwan\'s highest straight');
      expect(
        inTable(run(11)),
        findsNWidgets(4),
        reason: 'lowest in Standard, Taiwan and Pusoy Dos; highest in Hong Kong',
      );
      for (final source in BigTwoSource.documents) {
        await tester.scrollUntilVisible(
          find.byKey(ValueKey('source ${source.name}')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.textContaining(source.url), findsOneWidget);
      }
    });

    for (final size in bigTwoSizes) {
      for (final language in AppLanguage.values) {
        testWidgets('the table fits: ${shotTag(size, language)}', (tester) async {
          await pumpShot(tester, const BigTwoRulesGuide(), size: size, language: language);
          await tester.pump();
          final table = find.byKey(const ValueKey('preset table'));
          await tester.scrollUntilVisible(table, 300, scrollable: find.byType(Scrollable).first);
          expect(tester.getRect(table).right, lessThanOrEqualTo(size.width));
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
