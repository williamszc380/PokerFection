// Screenshots of Big Two's round-two pieces at every size and language, to
// look at: the bots' cards shown (Training), an opponent's range, the coach
// list with a row selected (cards picked, or Pass lit), the scoreboard
// between deals, the match's result, and the setup's Play to.
// PNGs are written only with --dart-define=SHOTS=<folder>:
//   flutter test test/ui/games/big_two/big_two_round2_shots_test.dart --dart-define=SHOTS=<folder>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/kit/match.dart';
import 'package:pokerfection/src/kit/seats.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_controller.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_setup.dart';
import 'package:pokerfection/src/ui/kit/turn_controller.dart';

import '../../../kit/shots.dart';
import 'big_two_test_util.dart';

Future<void> snap(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 300));
  await shot(tester, name);
}

/// A four-player Training game with the coach shown and a match to [target].
BigTwoController matchGame({int target = 100, int seed = 3, Map<String, Object?> toggles = const {}}) => seededGame(
  rules: BigTwoRules.standard(),
  seed: seed,
  toggles: {'coach': true, ...toggles},
  match: MatchTarget(points: target),
);

void main() {
  setUpAll(loadShotFonts);

  for (final size in const [Size(568, 320), Size(900, 420), Size(1280, 800), Size(390, 844)]) {
    for (final language in AppLanguage.values) {
      final tag = shotTag(size, language);

      testWidgets('show cards, a selected row, the range $tag', (tester) async {
        final game = matchGame(toggles: {TurnController.showCardsKey: true});
        await pumpGame(tester, game, size: size, language: language);
        await toMyPlayableTurn(tester, game);
        await snap(tester, 'b2r2_show_cards_$tag');
        // One tap on the coach's second row: its cards pop up, its row lit.
        final rows = game.coach!.shown(5);
        final cardRow = rows.firstWhere((l) => l.move != BigTwoController.passMove).move;
        game.selectMove(cardRow);
        await tester.pump();
        await snap(tester, 'b2r2_row_selected_$tag');
        // Pass (when it is legal): its button lit.
        if (game.canPass) {
          game.selectMove(BigTwoController.passMove);
          await tester.pump();
          await snap(tester, 'b2r2_pass_lit_$tag');
        }
        await tester.tap(find.byKey(const ValueKey('range tap 1')));
        await tester.pump();
        await tester.pump();
        await tester.pumpAndSettle();
        await snap(tester, 'b2r2_range_$tag');
        await closeGame(tester);
      });

      testWidgets('show cards at three and two players $tag', (tester) async {
        for (final players in const [3, 2]) {
          final game = seededGame(
            rules: BigTwoRules.standard(players: players),
            seed: 6,
            toggles: {'coach': true, TurnController.showCardsKey: true},
          );
          await pumpGame(tester, game, size: size, language: language);
          await toMyPlayableTurn(tester, game);
          await snap(tester, 'b2r2_show_cards_${players}p_$tag');
          await closeGame(tester);
        }
      });

      testWidgets('the scoreboard and the match result $tag', (tester) async {
        final game = matchGame(target: 50, seed: 5);
        await pumpGame(tester, game, size: size, language: language);
        await playToEnd(tester, game);
        await snap(tester, 'b2r2_between_$tag');
        for (var deal = 0; deal < 30 && !game.matchOver; deal++) {
          await game.nextRound();
          await playToEnd(tester, game);
          if (game.match!.deals.length == 3) {
            await tester.tap(find.byKey(const ValueKey('open scores')));
            await tester.pumpAndSettle();
            await snap(tester, 'b2r2_scoreboard_$tag');
            await tester.tapAt(const Offset(4, 4));
            await tester.pumpAndSettle();
          }
        }
        expect(game.matchOver, isTrue);
        await snap(tester, 'b2r2_match_over_$tag');
        await closeGame(tester);
      });

      testWidgets('the setup with Play to $tag', (tester) async {
        await pumpShot(
          tester,
          BigTwoSetupScreen(
            initial: BigTwoSetup(
              rules: BigTwoRules.standard(players: 2),
              level: KitLevel.easy,
              match: const MatchTarget(points: 100, scale: true),
            ),
          ),
          size: size,
          language: language,
        );
        await tester.pump();
        // The setup's columns are built as they scroll.
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('match target')),
          100,
          // The last column: Play to closes the rules (a PC's right column).
          scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).last,
        );
        await Scrollable.ensureVisible(tester.element(find.byKey(const ValueKey('match target'))), alignment: 0.4);
        await tester.pumpAndSettle();
        await snap(tester, 'b2r2_setup_$tag');
      });
    }
  }
}
