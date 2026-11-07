// Screenshots of Big Two's screens at every size and language, to look at.
// PNGs are written only with --dart-define=SHOTS=<folder>:
//   flutter test test/ui/games/big_two/big_two_shots_test.dart --dart-define=SHOTS=<folder>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_record.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';

import 'package:pokerfection/src/ui/games/big_two/big_two_controller.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_guides.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_setup.dart';
import 'package:pokerfection/src/ui/kit/help.dart';
import 'package:pokerfection/src/ui/kit/setup_kit.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import '../../../kit/shots.dart';
import 'big_two_test_util.dart';

/// [shot], once the screen's own animations (a coach row's outline moving
/// to the new pick) have run.
Future<void> snap(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 300));
  await shot(tester, name);
}

/// Plays on (the player making the first legal play, or passing) until
/// [plays] cards-on-the-table plays are down.
Future<void> playPlays(WidgetTester tester, BigTwoController game, int plays) async {
  for (var guard = 0; guard < 300 && !game.isOver; guard++) {
    if (game.state.history.where((t) => !t.play.isPass).length >= plays) break;
    await settleGame(tester);
    if (!game.myTurn) continue;
    final legal = game.state.legalMoves();
    game.humanMove(bigTwoMoveText(0, legal.firstWhere((p) => !p.isPass, orElse: () => legal.first)));
  }
  await settleGame(tester);
}

void main() {
  setUpAll(loadShotFonts);

  // The hand in the player's own order with its Sort button, a card in
  // the middle of a drag, and the hand late in a deal (few cards: the
  // button follows the fan's left end toward the middle).
  for (final size in const [Size(568, 320), Size(900, 420), Size(1280, 800), Size(390, 844)]) {
    for (final language in AppLanguage.values) {
      final tag = shotTag(size, language);

      testWidgets('reordered hand, Sort and a drag $tag', (tester) async {
        final game = seededGame(training: false, seed: 3);
        await pumpGame(tester, game, size: size, language: language);
        await toMyPlayableTurn(tester, game);
        await snap(tester, 'big_two_sort_rank_$tag');
        Offset at(int i) => tester.getCenter(find.byKey(ValueKey('${bigTwoFaceKey(game.hand[i])}#1')));
        // The highest card dragged to the left end: the player's own order.
        game.reorder(game.hand.length - 1, 0);
        game.toggle(game.hand[3]);
        await tester.pump();
        await snap(tester, 'big_two_sort_own_$tag');
        // A card picked up and carried over its neighbours.
        final from = at(1), to = at(5);
        final gesture = await tester.startGesture(from);
        for (var i = 1; i <= 6; i++) {
          await gesture.moveTo(Offset.lerp(from, to, i / 6)! + const Offset(0, -6));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pump(const Duration(milliseconds: 300));
        await shot(tester, 'big_two_drag_mid_$tag');
        await gesture.up();
        await tester.pumpAndSettle();
        await closeGame(tester);
      });

      testWidgets('few cards left $tag', (tester) async {
        final game = seededGame(training: false, seed: 4);
        await pumpGame(tester, game, size: size, language: language);
        for (var guard = 0; guard < 400 && !game.isOver && game.state.handOf(0).length > 3; guard++) {
          await settleGame(tester);
          if (!game.myTurn) continue;
          final legal = game.state.legalMoves();
          game.humanMove(bigTwoMoveText(0, legal.firstWhere((p) => !p.isPass, orElse: () => legal.first)));
        }
        await settleGame(tester);
        await snap(tester, 'big_two_sort_few_$tag');
        await closeGame(tester);
      });
    }
  }

  for (final size in bigTwoSizes) {
    for (final language in AppLanguage.values) {
      final tag = shotTag(size, language);

      testWidgets('game and coach $tag', (tester) async {
        final game = seededGame(toggles: const {'counter': true, 'coach': true});
        await pumpGame(tester, game, size: size, language: language);
        await toMyPlayableTurn(tester, game);
        await snap(tester, 'big_two_coach_$tag');
        // Pick the coach's move: Play lights up.
        game.selectMove(game.coach!.pick);
        await tester.pump();
        await snap(tester, 'big_two_picked_$tag');
        // Play the coach's lowest-scoring move: the feedback shows the grade and the pick.
        final lines = game.coach!.lines;
        game.humanMove(lines.reduce((a, b) => a.value <= b.value ? a : b).move);
        await toMyPlayableTurn(tester, game);
        await snap(tester, 'big_two_feedback_$tag');
        await closeGame(tester);
      });

      testWidgets('free play $tag', (tester) async {
        final game = seededGame(training: false, rules: BigTwoRules.standard(players: 3), seed: 5);
        await pumpGame(tester, game, size: size, language: language);
        await toMyPlayableTurn(tester, game);
        game.humanMove(bigTwoMoveText(0, game.state.legalMoves().firstWhere((p) => !p.isPass)));
        await settleGame(tester);
        await snap(tester, 'big_two_free_$tag');
        await closeGame(tester);
      });

      testWidgets('face-up card and the biggest hand $tag', (tester) async {
        // Three players: a deal where a bot took the face-up last card.
        var seed = 1;
        while (true) {
          final probe = seededGame(rules: BigTwoRules.standard(players: 3), seed: seed);
          final taken = BigTwoRecord.replay(probe.deal()).extraSeat;
          probe.dispose();
          if (taken != 0) break;
          seed++;
        }
        final three = seededGame(rules: BigTwoRules.standard(players: 3), seed: seed);
        await pumpGame(tester, three, size: size, language: language);
        await toMyPlayableTurn(tester, three);
        await snap(tester, 'big_two_faceup_$tag');
        await closeGame(tester);
        // Two players with 21 cards each.
        final two = seededGame(rules: BigTwoRules.standard(players: 2).copyWith(cardsEach: 21), seed: 2);
        await pumpGame(tester, two, size: size, language: language);
        await toMyPlayableTurn(tester, two);
        await snap(tester, 'big_two_two21_$tag');
        await closeGame(tester);
      });

      testWidgets('pile and history $tag', (tester) async {
        // Two players, 21 cards each: a long hand, and a pile a few plays deep.
        final two = seededGame(
          rules: BigTwoRules.standard(players: 2).copyWith(cardsEach: 21),
          seed: 2,
          training: false,
        );
        await pumpGame(tester, two, size: size, language: language);
        await playPlays(tester, two, 5);
        await snap(tester, 'big_two_pile_$tag');
        await tester.tap(find.byKey(const ValueKey('pile')));
        await tester.pumpAndSettle();
        await snap(tester, 'big_two_history_$tag');
        await closeGame(tester);
        // Four players with the coach on: the pile keeps clear of the side seats.
        final four = seededGame(seed: 6, toggles: const {'coach': true});
        await pumpGame(tester, four, size: size, language: language);
        await playPlays(tester, four, 6);
        await toMyPlayableTurn(tester, four);
        await snap(tester, 'big_two_pile4_$tag');
        await closeGame(tester);
      });

      if (size == bigTwoSizes.first) {
        testWidgets('a play in the air $tag', (tester) async {
          final game = seededGame(training: false, seed: 5, speed: PlaybackSpeed.normal);
          await pumpGame(tester, game, size: size, language: language);
          for (var i = 0; i < 400 && !game.myTurn; i++) {
            await tester.pump(const Duration(milliseconds: 40));
          }
          // Frame by frame, so the bots' cards have landed.
          for (var i = 0; i < 30; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          final legal = game.state.legalMoves().where((p) => !p.isPass).toList()
            ..sort((a, b) => b.size.compareTo(a.size));
          game.humanMove(bigTwoMoveText(0, legal.first));
          await tester.pump();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 150));
          await shot(tester, 'big_two_flight_$tag');
          await closeGame(tester);
          await tester.pump(const Duration(seconds: 2));
        });
      }

      testWidgets('game over $tag', (tester) async {
        final game = seededGame(seed: 9);
        await pumpGame(tester, game, size: size, language: language);
        await playToEnd(tester, game);
        await snap(tester, 'big_two_over_$tag');
        await closeGame(tester);
      });

      testWidgets('setup $tag', (tester) async {
        await pumpShot(
          tester,
          BigTwoSetupScreen(initial: BigTwoSetup.from(null)),
          size: size,
          language: language,
        );
        await tester.pump();
        await snap(tester, 'big_two_setup_$tag');
      });

      testWidgets('guides $tag', (tester) async {
        await pumpShot(
          tester,
          BigTwoHandRanksGuide(rules: BigTwoRules.taiwan()),
          size: size,
          language: language,
        );
        await tester.pump();
        await snap(tester, 'big_two_ranks_$tag');
        await pumpShot(tester, const BigTwoRulesGuide(), size: size, language: language);
        await tester.pump();
        await snap(tester, 'big_two_rules_$tag');
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('preset table')),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await snap(tester, 'big_two_compare_$tag');
      });

      testWidgets('the presets explained $tag', (tester) async {
        await pumpShot(
          tester,
          BigTwoSetupScreen(initial: BigTwoSetup.from(null)),
          size: size,
          language: language,
        );
        await tester.pump();
        // A phone lists the choices in one scrolling column, built as it scrolls.
        final page = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(find.byKey(const ValueKey('presets help')), 120, scrollable: page);
        // Clear of the Start bar at the foot of the page.
        await Scrollable.ensureVisible(tester.element(find.byKey(const ValueKey('presets help'))), alignment: 0.3);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('presets help')));
        await tester.pumpAndSettle();
        await snap(tester, 'big_two_help_presets_$tag');
        await tester.tap(find.text(S.forLanguage(language).ok));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.byKey(const ValueKey('straights')), 120, scrollable: page);
        final straights = find.descendant(
          of: find.ancestor(of: find.byKey(const ValueKey('straights')), matching: find.byType(SetupSection)).first,
          matching: find.byType(TermsHelpButton),
        );
        // Clear of the Start bar too: a tap that missed would start a game.
        await Scrollable.ensureVisible(tester.element(straights), alignment: 0.3);
        await tester.pumpAndSettle();
        await tester.tap(straights);
        await tester.pumpAndSettle();
        await snap(tester, 'big_two_help_straights_$tag');
      });
    }
  }
}
