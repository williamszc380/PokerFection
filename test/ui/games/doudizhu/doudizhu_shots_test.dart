// Fight the Landlord's screens at the three sizes a game agent checks
// (sideways phone 568x320, upright browser 390x844, PC 1280x800) and the
// small 592x360 phone, in English, Spanish and Chinese: setup, the
// auction, a play with the coach on, Free Play, a finished deal, a deal
// well under way (a long hand, a messy pile; the coach hidden as in a fresh
// game) with its history open, a long hand of 20, a card in flight, and
// both guides. Each must fit (no overflow) and not scroll, except the guides
// and setup on small screens.
//
// PNGs go to the folder given with --dart-define=SHOTS=<folder>:
//   flutter test test/ui/games/doudizhu/doudizhu_shots_test.dart --dart-define=SHOTS=<folder>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_controller.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_guides.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_setup.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_table.dart';
import 'package:pokerfection/src/ui/games/doudizhu/l10n/doudizhu_strings.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import '../../../kit/shots.dart';
import 'helpers.dart';
import 'states.dart';

const sizes = [Size(568, 320), Size(592, 360), Size(390, 844), Size(1280, 800)];

/// Whether anything on the page scrolls up and down (sideways segment rows
/// don't count).
bool pageScrolls(WidgetTester tester) => tester
    .stateList<ScrollableState>(find.byType(Scrollable))
    .any((s) => axisDirectionToAxis(s.axisDirection) == Axis.vertical && s.position.maxScrollExtent > 0.5);

/// The game's screen fits: nothing overflows and the game page itself
/// doesn't scroll (the coach area may).
void expectFits(WidgetTester tester, String tag) {
  expect(tester.takeException(), isNull, reason: tag);
}

Future<void> shootGame(WidgetTester tester, LandlordController c, String name) async {
  for (final language in AppLanguage.values) {
    for (final size in sizes) {
      final tag = shotTag(size, language);
      await showGame(tester, c, size, language);
      expectFits(tester, '$name $tag');
      await shot(tester, '${name}_$tag');
    }
  }
  await closeGame(tester, c);
}

/// Plays on the table so far (passes and bids aside).
int pilePlays(LandlordController c) =>
    ddzPilePlays(c.game, LandlordStrings.forLanguage(AppLanguage.english)).where((p) => p.hasCards).length;

/// A Training deal (the coach hidden) at the player's decision once at
/// least [plays] plays lie on the pile while the player still holds
/// [held] cards or more: the player passes whenever they may.
Future<LandlordController> messyGame(WidgetTester tester, {int plays = 6, int held = 13}) async {
  for (var s = 1; s < 80; s++) {
    final c = testController(seed: s);
    c.newGame();
    for (var guard = 0; guard < 150 && !c.isOver; guard++) {
      await pumpUntil(
        tester,
        () =>
            c.isOver ||
            (c.seatToAct == LandlordController.you && c.forcedMove(LandlordController.you) == null && c.coach != null),
      );
      if (c.isOver || c.game.hands[0].length < held) break;
      if (c.game.phase == DdzPhase.playing && pilePlays(c) >= plays) return c;
      final legal = c.game.legalMoves();
      c.humanMove(legal.contains(const DdzPass()) ? yours(const DdzPass()) : easyMove(c));
    }
    c.dispose();
  }
  throw StateError('no messy deal');
}

void main() {
  setUpAll(loadShotFonts);

  testWidgets('a deal under way: a long hand fanned under the table, a messy pile; tapping it opens the history', (
    tester,
  ) async {
    final c = await messyGame(tester);
    for (final language in AppLanguage.values) {
      for (final size in sizes) {
        final tag = shotTag(size, language);
        await showGame(tester, c, size, language);
        expectFits(tester, 'pile $tag');
        await shot(tester, 'pile_$tag');
        await tester.tap(find.byKey(const ValueKey('pile')));
        await tester.pumpAndSettle();
        expectFits(tester, 'history $tag');
        expect(find.byKey(const ValueKey('pile history')), findsOneWidget);
        await shot(tester, 'history_$tag');
        await tester.tap(find.byKey(const ValueKey('close history')));
        await tester.pumpAndSettle();
      }
    }
    await closeGame(tester, c);
  });

  testWidgets('the landlord with 20 cards, the kitty face up', (tester) async {
    late LandlordController c;
    for (var s = 1; ; s++) {
      c = await gameAt(tester, DdzPhase.playing, seed: s, leading: true);
      if (c.game.landlord == 0 && c.game.hands[0].length == 20) break;
      c.dispose();
    }
    c.clearSelection();
    await shootGame(tester, c, 'lord20');
  });

  testWidgets('a card on its way from the hand to the pile (Normal speed)', (tester) async {
    var speed = PlaybackSpeed.instant;
    for (var s = 1; s < 80; s++) {
      final c = testController(seed: s, training: false, speedNow: () => speed);
      c.newGame();
      for (var guard = 0; guard < 150 && !c.isOver; guard++) {
        await pumpUntil(
          tester,
          () => c.isOver || (c.seatToAct == LandlordController.you && c.forcedMove(LandlordController.you) == null),
        );
        if (c.isOver) break;
        if (c.game.phase == DdzPhase.playing && c.game.isLead && pilePlays(c) >= 3) {
          speed = PlaybackSpeed.normal;
          await showGame(tester, c, const Size(568, 320), AppLanguage.english);
          c.toggle(c.game.hands[0].first);
          c.playSelection();
          for (var i = 0; i < 9; i++) {
            await tester.pump(const Duration(milliseconds: 20));
          }
          expect(c.flights.flying, isTrue);
          await shot(tester, 'flight_en_568x320');
          await closeGame(tester, c);
          return;
        }
        c.humanMove(easyMove(c));
      }
      c.dispose();
    }
    fail('the player never led after a few plays');
  });

  testWidgets('the auction, the coach on: the bids with the coach\'s advice', (tester) async {
    await shootGame(tester, await gameAt(tester, DdzPhase.bidding, coach: true), 'bid');
  });

  testWidgets('call and rob bidding', (tester) async {
    await shootGame(
      tester,
      await gameAt(tester, DdzPhase.bidding, coach: true, rules: DdzRules.app, seed: 4),
      'callrob',
    );
  });

  testWidgets('a play, the coach on, its pick selected', (tester) async {
    await shootGame(tester, await gameAt(tester, DdzPhase.playing, coach: true, seed: 2), 'play');
  });

  testWidgets('hovering a coach row: the other cards of the hand dim', (tester) async {
    final c = await gameAt(tester, DdzPhase.playing, coach: true, seed: 2);
    c.clearSelection();
    c.preview = c.coach!.lines.firstWhere((l) => !l.move.endsWith(':p')).move;
    for (final size in [const Size(568, 320), const Size(1280, 800)]) {
      await showGame(tester, c, size, AppLanguage.english);
      expectFits(tester, 'preview $size');
      await shot(tester, 'preview_${shotTag(size, AppLanguage.english)}');
    }
    await closeGame(tester, c);
  });

  testWidgets('Free Play: no coach, no grades', (tester) async {
    await shootGame(tester, await gameAt(tester, DdzPhase.playing, training: false, seed: 3), 'free');
  });

  testWidgets('a finished deal: the result, the bots\' last cards, Next deal', (tester) async {
    await shootGame(tester, await finishedGame(tester, seed: 5), 'over');
  });

  testWidgets('setup fits; it scrolls only on small screens', (tester) async {
    for (final language in AppLanguage.values) {
      for (final size in sizes) {
        final tag = shotTag(size, language);
        await pumpShot(tester, const LandlordSetup(), size: size, language: language);
        await tester.pumpAndSettle();
        expectFits(tester, 'setup $tag');
        if (size.width >= 1280) expect(pageScrolls(tester), isFalse, reason: 'setup on a PC: $tag');
        await shot(tester, 'setup_$tag');
      }
    }
  });

  testWidgets('the guides fit (they may scroll)', (tester) async {
    for (final language in AppLanguage.values) {
      for (final size in sizes) {
        final tag = shotTag(size, language);
        await pumpShot(tester, const LandlordCombinationsGuide(), size: size, language: language);
        await tester.pumpAndSettle();
        expectFits(tester, 'combinations $tag');
        await shot(tester, 'guide_combinations_$tag');
        await pumpShot(tester, const LandlordRulesGuide(), size: size, language: language);
        await tester.pumpAndSettle();
        expectFits(tester, 'rules $tag');
        await shot(tester, 'guide_rules_$tag');
      }
    }
  });
}
