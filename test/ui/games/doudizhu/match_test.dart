// Fight the Landlord's match: each deal's points (the bid times the
// doublings, the landlord's twice a peasant's) added up until a total
// reaches the target; the highest total wins. The setup's "Play to", the
// status line, the scores between deals, the match's end and New match.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/kit/match.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_controller.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_screen.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_setup.dart';
import 'package:pokerfection/src/ui/kit/kit_scope.dart';

import '../../../kit/shots.dart';
import 'helpers.dart';
import 'states.dart';

const pc = Size(1280, 800);

void main() {
  setUpAll(loadShotFonts);

  group('the match', () {
    test('a new game starts a match to the setup\'s target, the highest total winning', () {
      final c = testController();
      c.newGame();
      final match = c.match!;
      expect(match.target, 30);
      expect(match.winner, MatchWinner.highest);
      expect(match.totals, [0, 0, 0]);
      expect(match.deals, isEmpty);
      c.dispose();
    });

    test('each deal\'s points go to the totals: the landlord\'s twice each peasant\'s, the sum zero', () async {
      final c = testController();
      c.newGame();
      var deals = 0;
      final sums = [0, 0, 0];
      while (deals < 3) {
        await playDeal(c);
        final points = c.game.result?.points;
        if (points != null) {
          deals++;
          for (var s = 0; s < 3; s++) {
            sums[s] += points[s];
          }
          final lord = c.game.result!.landlord;
          expect(points[lord].abs(), 2 * points[(lord + 1) % 3].abs());
          expect(points.reduce((a, b) => a + b), 0);
        }
        expect(c.match!.deals, hasLength(deals), reason: 'a deal thrown in is no deal of the match');
        expect(c.match!.totals, sums);
        if (c.matchOver) break;
        await c.nextRound();
      }
      c.dispose();
    });

    test('No limit plays no match: the deals just go on', () {
      final c = testController(match: const MatchTarget());
      c.newGame();
      expect(c.match, isNull);
      expect(c.startMatch(), isNull);
      c.dispose();
    });

    test('three players always: the target is never scaled, even with the switch on', () {
      expect(const MatchTarget(points: 50, scale: true).forPlayers(landlordPlayers, standardPlayers: landlordPlayers), 50);
      final c = testController(match: const MatchTarget(points: 50, scale: true));
      c.newGame();
      expect(c.match!.target, 50);
      c.dispose();
    });

    test('the setup\'s choice is saved with the deal and read back', () {
      final c = testController(match: const MatchTarget(points: 100));
      c.newGame();
      expect(LandlordChoice.of(c.record).match, const MatchTarget(points: 100));
      final none = testController(match: const MatchTarget());
      none.newGame();
      expect(LandlordChoice.of(none.record).match, const MatchTarget(), reason: 'No limit, not the standard');
      c.dispose();
      none.dispose();
    });

    testWidgets('the status line shows the deal, the player\'s total and the target, not the session\'s net', (
      tester,
    ) async {
      final c = await gameAt(tester, DdzPhase.playing);
      await showGame(tester, c, pc, AppLanguage.english);
      expect(find.textContaining('Deal 1 · Player 0 · To 30'), findsOneWidget);
      expect(find.textContaining('Net'), findsNothing);
      await closeGame(tester, c);

      final free = await finishedGame(tester, match: const MatchTarget());
      await showGame(tester, free, pc, AppLanguage.english);
      expect(find.textContaining('Net'), findsOneWidget, reason: 'no match: the net as before');
      expect(find.textContaining('Deal 1'), findsNothing);
      await closeGame(tester, free);
    });

    testWidgets('between deals the scores show in the panel, and a tap on the status opens the scoreboard', (
      tester,
    ) async {
      final c = await finishedGame(tester, match: const MatchTarget(points: 100));
      await showGame(tester, c, pc, AppLanguage.english);
      expect(c.between, isTrue);
      expect(find.byKey(const ValueKey('panel scores')), findsOneWidget);
      expect(find.text('Next deal'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('open scores')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scoreboard')), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      // ☰ Scores opens it too.
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scores'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scoreboard')), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      await closeGame(tester, c);
    });

    testWidgets('a total reaching the target ends the match: who won it, and New match starts another', (
      tester,
    ) async {
      // Any deal played out moves at least 1 point.
      final c = await finishedGame(tester, match: const MatchTarget(points: 1));
      await showGame(tester, c, pc, AppLanguage.english);
      expect(c.matchOver, isTrue);
      final won = c.match!.leaders;
      // The two peasants score alike: when they win, they share the top
      // total, and the match is a tie between them, not one's win.
      final words = won.length > 1
          ? 'Tie: ${won.map(c.seatName).join(' and ')}'
          : won.single == 0
          ? 'You win the match'
          : '${c.seatName(won.single)} wins the match';
      expect(find.text(words), findsOneWidget);
      expect(find.text('New match'), findsOneWidget);
      await tester.tap(find.text('New match'));
      await tester.pump();
      expect(c.match!.deals, isEmpty);
      expect(c.match!.totals, [0, 0, 0]);
      expect(c.deals, 1, reason: 'a new session');
      await closeGame(tester, c);
    });
  });

  group('the setup\'s Play to', () {
    Future<void> showSetup(WidgetTester tester, LastGames store) async {
      await pumpShot(
        tester,
        const LandlordSetup(),
        size: pc,
        wrap: (child) => KitScope(newJobs: Jobs.inline, lastGames: store, child: child),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('20, 30, 50, 100 points or No limit, 30 at first; Scale with players greyed out (three players)', (
      tester,
    ) async {
      await showSetup(tester, LastGames());
      final row = find.byKey(const ValueKey('play to'));
      // The row's segments, in order (ChoiceRow numbers them).
      final button = tester.widget<SegmentedButton<int>>(find.descendant(of: row, matching: find.byType(SegmentedButton<int>)));
      expect(button.segments, hasLength(5));
      expect(button.selected, {1}, reason: '30');
      final labels = [for (final t in ['20', '30', '50', '100', 'No limit']) tester.getCenter(find.descendant(of: row, matching: find.text(t))).dx];
      expect([...labels]..sort(), labels, reason: 'smallest first, then No limit');
      final scale = tester.widget<Switch>(
        find.descendant(of: find.byKey(const ValueKey('scale with players')), matching: find.byType(Switch)),
      );
      expect(scale.onChanged, isNull, reason: 'greyed out, not hidden');
      expect(scale.value, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('the chosen target goes to the game', (tester) async {
      await showSetup(tester, LastGames());
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('play to')), matching: find.text('50')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('start')));
      await tester.pump();
      await tester.pump();
      final screen = tester.widget<LandlordScreen>(find.byType(LandlordScreen));
      expect(screen.choice.match, const MatchTarget(points: 50));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
