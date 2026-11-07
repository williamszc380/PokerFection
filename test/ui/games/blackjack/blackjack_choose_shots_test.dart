// Screenshots of this round's Blackjack pieces: a coach row clicked once
// (its button ringed), all five decisions listed on a small screen, ☰ Show
// cards (the hole card up) and the dealer's range, at four sizes in the
// three languages. PNGs are written only with --dart-define=SHOTS=<folder>;
// without it this runs as one more overflow check.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/blackjack/app/blackjack_record.dart';
import 'package:pokerfection/src/games/blackjack/blackjack.dart';
import 'package:pokerfection/src/ui/games/blackjack/blackjack_controller.dart';
import 'package:pokerfection/src/ui/games/blackjack/l10n/blackjack_strings.dart';
import 'package:pokerfection/src/ui/kit/coach_panel.dart';
import 'package:pokerfection/src/ui/kit/game_sounds.dart';

import '../../../kit/shots.dart';
import 'blackjack_scenes.dart';

/// A sideways phone, a wide phone, a PC, a phone upright (a browser).
const _sizes = [Size(568, 320), Size(900, 420), Size(1280, 800), Size(390, 844)];

Finder _row(String text) => find.descendant(of: find.byType(CoachList), matching: find.text(text));

void main() {
  setUpAll(loadShotFonts);
  setUp(() => GameSounds.output = (_) {});

  for (final size in _sizes) {
    for (final language in AppLanguage.values) {
      final tag = shotTag(size, language);
      final b = BlackjackStrings.forLanguage(language);

      testWidgets('blackjack: a coach row selected, and every decision listed, $tag', (tester) async {
        await pumpGame(tester, size: size, language: language, settings: coachOn);
        await play(tester, dealMove);
        await tester.tap(_row(b.action(BlackjackAction.stand)));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byKey(const ValueKey('chosen ring')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await snap(tester, 'bj_row_selected_$tag');
        await closeGame(tester);

        // A pair of eights at a table with late surrender: five decisions,
        // all of them rows, however small the screen.
        await pumpGame(
          tester,
          size: size,
          language: language,
          seed: seedEights,
          settings: const BlackjackSettings(rules: BlackjackRules(surrender: Surrender.late), toggles: {'coach': true}),
        );
        await play(tester, dealMove);
        await tester.tap(_row(b.action(BlackjackAction.split)));
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
        await snap(tester, 'bj_all_rows_$tag');
        await closeGame(tester);
      });

      testWidgets("blackjack: Show cards and the dealer's range, $tag", (tester) async {
        final game = await pumpGame(tester, size: size, language: language, seed: seedEights);
        await play(tester, dealMove);
        game.showOpponentCards = true;
        await settleGame(tester);
        expect(tester.takeException(), isNull);
        await snap(tester, 'bj_show_cards_$tag');
        game.showOpponentCards = false;
        await settleGame(tester);
        await tester.tap(find.byKey(const ValueKey('range tap 1')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('range sheet')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await snap(tester, 'bj_range_$tag');
        await closeGame(tester);

        // The dealer showing a ten, having checked: no ace underneath.
        await pumpGame(tester, size: size, language: language);
        await play(tester, dealMove);
        await tester.tap(find.byKey(const ValueKey('range tap 1')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await snap(tester, 'bj_range_ten_$tag');
        await closeGame(tester);
      });
    }
  }
}
