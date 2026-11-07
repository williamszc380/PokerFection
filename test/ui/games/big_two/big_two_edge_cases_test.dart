// Big Two's edge cases: a move with no choice isn't graded, the three-player
// face-up 52nd card stays on the table, and the setup fits every screen.
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_record.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_coach_view.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_controller.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_setup.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';

import '../../../kit/fakes.dart';
import '../../../kit/shots.dart';
import 'big_two_controller_test.dart' show TestBigTwo, setupOf, playDeal;
import 'big_two_test_util.dart';

void main() {
  setUpAll(loadShotFonts);

  test('a move with no choice (the only legal one, such as a forced pass) is not graded', () async {
    final game = TestBigTwo(setup: setupOf(), jobs: Jobs.inline());
    await game.newGame();
    await playDeal(game);
    final record = game.record;
    final forced = <String>[];
    for (final (i, move) in record.moves.indexed) {
      if (bigTwoMoveSeat(move) != 0) continue;
      final legal = BigTwoRecord.replay(record.upTo(i)).legalMoves();
      if (legal.length == 1 && record.marks[i] != null) forced.add('$i $move: ${record.marks[i]!.grade.name}');
    }
    expect(forced, isEmpty, reason: 'graded although there was nothing to choose');
    game.dispose();
    await settle();
  });

  testWidgets('three players: the face-up 52nd card, and who took it, is on the table while a bot holds it', (
    tester,
  ) async {
    var checked = 0;
    for (var seed = 1; seed < 40 && checked == 0; seed++) {
      final game = seededGame(rules: BigTwoRules.standard(players: 3), seed: seed, training: false);
      await pumpGame(tester, game);
      final state = game.state;
      if (state.extraSeat != 0 && state.extraCode != state.startCode && !state.isPlayed(state.extraCode)) {
        final extra = state.rules.cardOf(state.extraCode);
        // Face up with the eye in the seat that took it.
        final onTable = find.descendant(
          of: find.byKey(ValueKey('seat ${state.extraSeat}')),
          matching: find.byWidgetPredicate(
            (w) => w is GameCardView && w.faceUp && w.visibleToAll && w.face == bigTwoFace(extra),
          ),
        );
        expect(
          onTable,
          findsWidgets,
          reason: 'seed $seed: ${extra.short} went face up to seat ${game.state.extraSeat}',
        );
        checked++;
      }
      await closeGame(tester);
    }
    expect(checked, 1, reason: 'a deal where a bot holds the face-up card');
  });

  for (final size in const [Size(390, 844), Size(568, 320), Size(1280, 800)]) {
    for (final language in AppLanguage.values) {
      testWidgets(
        'setup ${shotTag(size, language)}: every preset, Custom and every straight order show without scrolling sideways',
        (tester) async {
          await pumpShot(
            tester,
            BigTwoSetupScreen(initial: BigTwoSetup.from(null), onStart: (_, _) {}),
            size: size,
            language: language,
          );
          await tester.pump();
          final custom = KitStrings.forLanguage(language).custom;
          final page = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;
          for (final label in [custom, 'J-Q-K-A-2']) {
            // Scroll the page down (never sideways) until the row is built.
            for (var i = 0; i < 30 && find.text(label).evaluate().isEmpty; i++) {
              await tester.drag(page, const Offset(0, -100));
              await tester.pump();
            }
            final rect = tester.getRect(find.text(label));
            // The row's own sideways-scrolling box, if it has one: what of the
            // row shows. A row that wraps instead shows up to the screen's edge.
            final scroller = find.ancestor(
              of: find.text(label),
              matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.right),
            );
            final shows = scroller.evaluate().isEmpty ? size.width : tester.getRect(scroller.first).right;
            expect(
              rect.right,
              lessThanOrEqualTo(shows.clamp(0, size.width)),
              reason: '"$label" ends at x=${rect.right}; its row shows up to x=$shows',
            );
          }
        },
      );
    }
  }
}
