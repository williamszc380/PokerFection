// Screenshots of blackjack in every state worth looking at, at the three
// sizes and in the three languages. PNGs are written only with
// --dart-define=SHOTS=<folder>; without it this runs as one more overflow
// check of each state.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/blackjack/app/blackjack_grading.dart';
import 'package:pokerfection/src/games/blackjack/app/blackjack_record.dart';
import 'package:pokerfection/src/games/blackjack/blackjack.dart';
import 'package:pokerfection/src/ui/games/blackjack/blackjack_controller.dart';
import 'package:pokerfection/src/ui/games/blackjack/blackjack_guides.dart';
import 'package:pokerfection/src/ui/games/blackjack/blackjack_setup.dart';
import 'package:pokerfection/src/ui/kit/game_sounds.dart';

import '../../../kit/shots.dart';
import 'blackjack_scenes.dart';

void main() {
  setUpAll(loadShotFonts);
  setUp(() => GameSounds.output = (_) {});

  for (final language in AppLanguage.values) {
    for (final size in gameSizes) {
      final tag = shotTag(size, language);

      testWidgets('blackjack shots $tag', (tester) async {
        // Setup.
        await pumpShot(tester, const BlackjackSetup(), size: size, language: language, wrap: kitWrap(LastGames()));
        await tester.pump();
        await snap(tester, 'setup_$tag');

        // A round: 16 against a ten, dealt from the shoe; the coach starts
        // hidden.
        await pumpGame(tester, size: size, language: language);
        await snap(tester, 'deal_$tag');
        gameOf(tester).humanMove(dealMove);
        // The cards on their way from the shoe, the buttons waiting.
        await frames(tester, 560);
        await shot(tester, 'dealing_$tag');
        await settleGame(tester);
        await snap(tester, 'coach_hidden_$tag');
        await closeGame(tester);

        // The same round with the coach on.
        await pumpGame(tester, size: size, language: language, settings: coachOn);
        await play(tester, dealMove);
        await snap(tester, 'coach_$tag');
        // Hitting: the round ends, its result on the felt and in the
        // panel's headline, the grade shown.
        await play(tester, move0(BlackjackAction.hit));
        await snap(tester, 'round_over_$tag');
        await closeGame(tester);

        // A long hand: five hits to a seven-card 19, then the dealer's turn
        // (the hole card turning over, a card on its way), then the result.
        await pumpGame(tester, size: size, language: language, seed: seedLong);
        await play(tester, dealMove);
        for (var i = 0; i < 5; i++) {
          await play(tester, move0(BlackjackAction.hit));
        }
        await snap(tester, 'long_hand_$tag');
        gameOf(tester).humanMove(move0(BlackjackAction.stand));
        await frames(tester, 140);
        await shot(tester, 'dealer_turning_$tag');
        await frames(tester, 620);
        await shot(tester, 'dealer_drawing_$tag');
        await settleGame(tester);
        await snap(tester, 'long_hand_over_$tag');
        await closeGame(tester);

        // A split pair of eights.
        await pumpGame(tester, size: size, language: language, seed: seedEights);
        await play(tester, dealMove);
        await play(tester, move0(BlackjackAction.split));
        await snap(tester, 'split_$tag');
        await closeGame(tester);

        // Insurance offered, with the count showing.
        final game = await pumpGame(tester, size: size, language: language, seed: seedInsurance);
        game.showCount = true;
        await play(tester, dealMove);
        await snap(tester, 'insurance_$tag');
        // ☰ with Count checked.
        await tester.tap(find.byIcon(Icons.menu));
        await tester.pumpAndSettle();
        await shot(tester, 'count_menu_$tag');
        await closeGame(tester);

        // Cards seen: the count's play tagged.
        await pumpGame(
          tester,
          size: size,
          language: language,
          seed: seedSeen,
          settings: BlackjackSettings(
            rules: BlackjackRules.preset(BlackjackPreset.singleDeck),
            coachMode: CoachMode.seen,
            toggles: const {'coach': true},
          ),
        );
        await playChart(tester, 3);
        await snap(tester, 'seen_$tag');
        // The chart's play, graded against the count's: "Count: Hit".
        await play(tester, gameOf(tester).coach!.pick);
        await snap(tester, 'seen_graded_$tag');
        // The shoe to its end: New shoe.
        await playToEnd(tester);
        await snap(tester, 'over_$tag');
        await closeGame(tester);

        // Guides.
        await pumpShot(
          tester,
          const BlackjackStrategyGuide(),
          size: size,
          language: language,
          wrap: kitWrap(LastGames()),
        );
        await settleGame(tester);
        await snap(tester, 'guide_strategy_$tag');
        await pumpShot(tester, const BlackjackRulesGuide(), size: size, language: language);
        await tester.pump();
        await snap(tester, 'guide_rules_$tag');
        await closeGame(tester);
      });
    }
  }
}
