// Fight the Landlord's new pieces at a sideways phone (568x320), a small PC
// window (900x420), a PC (1280x800) and an upright browser (390x844), in
// English, Spanish and Chinese; each must fit (no overflow):
// - table: both bots' hands as card backs, the match on the status line
// - choose: the coach list with Pass's row selected and its button ringed
// - pick: a play's row selected, its cards up in the hand
// - showcards: Training's Show cards, both hands face up
// - range: a bot's range
// - between: the scores in the panel after a deal; scoreboard: its sheet
// - matchover: the match won, New match
// - setup: Play to
//
// PNGs go to the folder given with --dart-define=SHOTS=<folder>:
//   flutter test test/ui/games/doudizhu/round2_shots_test.dart --dart-define=SHOTS=<folder>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/kit/match.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_controller.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_setup.dart';
import 'package:pokerfection/src/ui/kit/kit_scope.dart';

import '../../../kit/shots.dart';
import 'states.dart';

const sizes = [Size(568, 320), Size(900, 420), Size(1280, 800), Size(390, 844)];

Future<void> each(WidgetTester tester, Future<void> Function(Size size, AppLanguage language, String tag) body) async {
  for (final language in AppLanguage.values) {
    for (final size in sizes) {
      final tag = shotTag(size, language);
      // A new size: what slides into its new place gets there first.
      await tester.pumpWidget(const SizedBox());
      await body(size, language, tag);
      expect(tester.takeException(), isNull, reason: tag);
    }
  }
}

void main() {
  setUpAll(loadShotFonts);

  testWidgets('the table, Pass selected from the coach, a play selected', (tester) async {
    final c = await gameAt(tester, DdzPhase.playing, coach: true, following: true);
    await pumpUntil(tester, () => !c.coachThinking);
    final pass = yours(const DdzPass());
    final play = c.coach!.lines.where((l) => l.move != pass).firstOrNull?.move;
    await each(tester, (size, language, tag) async {
      c.clearSelection();
      await showGame(tester, c, size, language);
      await shot(tester, 'table_$tag');
      c.selectMove(pass);
      await tester.pump();
      await shot(tester, 'choose_$tag');
      if (play != null) {
        c.selectMove(play);
        await tester.pump();
        await shot(tester, 'pick_$tag');
      }
    });
    await closeGame(tester, c);
  });

  testWidgets("Show cards: both bots' hands face up", (tester) async {
    final c = await gameAt(tester, DdzPhase.playing, seed: 2);
    c.clearSelection();
    c.showOpponentCards = true;
    await each(tester, (size, language, tag) async {
      await showGame(tester, c, size, language);
      await shot(tester, 'showcards_$tag');
    });
    await closeGame(tester, c);
  });

  testWidgets("a bot's range", (tester) async {
    final c = await gameAt(tester, DdzPhase.playing, seed: 3);
    c.clearSelection();
    await each(tester, (size, language, tag) async {
      await showGame(tester, c, size, language);
      await tester.tap(find.byKey(const ValueKey('range tap 1')));
      await tester.pump();
      await pumpUntil(tester, () => c.rangeOf(1) != null);
      await tester.pumpAndSettle();
      await shot(tester, 'range_$tag');
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
    });
    await closeGame(tester, c);
  });

  testWidgets('between deals: the scores; the scoreboard', (tester) async {
    final c = await finishedGame(tester, match: const MatchTarget(points: 100));
    await each(tester, (size, language, tag) async {
      await showGame(tester, c, size, language);
      await shot(tester, 'between_$tag');
      await tester.tap(find.byKey(const ValueKey('open scores')));
      await tester.pumpAndSettle();
      await shot(tester, 'scoreboard_$tag');
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
    });
    await closeGame(tester, c);
  });

  testWidgets('the match over', (tester) async {
    final c = await finishedGame(tester, match: const MatchTarget(points: 1));
    await each(tester, (size, language, tag) async {
      await showGame(tester, c, size, language);
      await shot(tester, 'matchover_$tag');
    });
    await closeGame(tester, c);
  });

  testWidgets('the setup: Play to', (tester) async {
    await each(tester, (size, language, tag) async {
      // A fresh page each time, scrolled to the top.
      await tester.pumpWidget(const SizedBox());
      await pumpShot(
        tester,
        const LandlordSetup(),
        size: size,
        language: language,
        wrap: (child) => KitScope(newJobs: Jobs.inline, lastGames: LastGames(), child: child),
      );
      await tester.pumpAndSettle();
      // Scrolled down to Play to, under Training / Free Play.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('scale with players')),
        80,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await shot(tester, 'setup_$tag');
    });
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  test('the controller this harness drives is the game\'s own', () {
    expect(landlordTargets, [20, 30, 50, 100]);
  });
}
