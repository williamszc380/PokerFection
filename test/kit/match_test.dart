import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/kit/match.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/ui/games/big_two/l10n/big_two_strings.dart';
import 'package:pokerfection/src/ui/kit/felt.dart';
import 'package:pokerfection/src/ui/kit/game_scaffold.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';
import 'package:pokerfection/src/ui/kit/match_view.dart';
import 'package:pokerfection/src/ui/kit/setup_kit.dart';

import 'nim.dart';
import 'shots.dart';

/// Nim played as a match of deals, as Big Two is: each deal the loser takes
/// [penalty] points, and the lowest total wins once a total reaches
/// [target]. In Free Play, so the deals go quickly (no coach jobs).
class _MatchNim extends NimController {
  _MatchNim({required super.jobs, this.target = 10}) : super(rounds: true, pile: 3, training: false);

  final int? target;
  final int penalty = 4;
  int dealPointsAsked = 0;

  @override
  MatchScore? startMatch() =>
      target == null ? null : MatchScore(target: target!, winner: MatchWinner.lowest, seats: 2);

  @override
  List<int>? dealPoints() {
    dealPointsAsked++;
    return [for (var s = 0; s < 2; s++) winners.contains(s) ? 0 : penalty];
  }
}

/// Nim where every deal gives both seats the same points (as Fight the
/// Landlord's two peasants score alike), so the match ends in a tie.
class _TieNim extends _MatchNim {
  _TieNim({required super.jobs}) : super(target: 10);

  @override
  List<int>? dealPoints() => [5, 5];
}

void main() {
  setUpAll(loadShotFonts);

  group('the target', () {
    test('as chosen, or scaled in proportion to the usual table, to a multiple of 5', () {
      const t = MatchTarget(points: 100, scale: true);
      expect(t.forPlayers(4, standardPlayers: 4), 100);
      expect(t.forPlayers(3, standardPlayers: 4), 75);
      expect(t.forPlayers(2, standardPlayers: 4), 50);
      expect(t.forPlayers(6, standardPlayers: 4), 150);
      expect(const MatchTarget(points: 50, scale: true).forPlayers(3, standardPlayers: 4), 40, reason: '37.5 → 40');
      expect(const MatchTarget(points: 100).forPlayers(6, standardPlayers: 4), 100, reason: 'scaling off');
      expect(const MatchTarget().forPlayers(4, standardPlayers: 4), isNull, reason: 'No limit');
      expect(const MatchTarget(points: 5, scale: true).forPlayers(2, standardPlayers: 4), 5, reason: 'never below 5');
    });

    test("saved as the setup's choice; No limit stays No limit; anything else is the standard", () {
      const standard = MatchTarget(points: 100);
      const chosen = MatchTarget(points: 150, scale: true);
      expect(MatchTarget.fromJson(chosen.toJson(), fallback: standard), chosen);
      expect(MatchTarget.fromJson(const MatchTarget().toJson(), fallback: standard), const MatchTarget());
      expect(MatchTarget.fromJson(null, fallback: standard), standard);
      expect(MatchTarget.fromJson({'points': 'lots'}, fallback: standard), standard);
      expect(MatchTarget.fromJson({'points': -5, 'scale': true}, fallback: standard), const MatchTarget(points: 100, scale: true));
    });
  });

  group('the score', () {
    test('each deal adds up; the match is over once a total reaches the target, not before', () {
      var m = MatchScore(target: 20, winner: MatchWinner.lowest, seats: 3);
      expect(m.totals, [0, 0, 0]);
      expect(m.leaders, isEmpty, reason: 'nobody leads before a deal');
      m = m.add([0, 7, 12]).add([5, 0, 7]);
      expect(m.totals, [5, 7, 19]);
      expect(m.isOver, isFalse, reason: '19 is short of 20');
      m = m.add([1, 0, 1]);
      expect(m.totals, [6, 7, 20]);
      expect(m.isOver, isTrue, reason: 'exactly the target ends it');
      expect(m.deals, hasLength(3));
      expect(() => m.add([1, 2]), throwsArgumentError);
    });

    test('the lowest total wins a penalty match, the highest a points match; ties share a place', () {
      final low = MatchScore(target: 50, winner: MatchWinner.lowest, seats: 4, deals: [
        [0, 10, 3, 3],
      ]);
      expect(low.leaders, [0]);
      expect(low.standings, [0, 2, 3, 1]);
      expect([for (var s = 0; s < 4; s++) low.placeOf(s)], [1, 4, 2, 2]);
      final high = MatchScore(target: 24, winner: MatchWinner.highest, seats: 3, deals: [
        [12, -6, -6],
        [-4, 2, 2],
      ]);
      expect(high.totals, [8, -4, -4]);
      expect(high.leaders, [0]);
      expect(high.standings, [0, 1, 2]);
      expect(high.placeOf(2), 2);
    });

    test("kept in the record's extra as JSON; anything else reads as no match", () {
      final m = MatchScore(target: 30, winner: MatchWinner.highest, seats: 3).add([4, -2, -2]);
      final back = MatchScore.fromJson(m.toJson())!;
      expect(back.totals, m.totals);
      expect(back.target, 30);
      expect(back.winner, MatchWinner.highest);
      expect(MatchScore.fromJson(null), isNull);
      expect(MatchScore.fromJson({'target': 'x'}), isNull);
      expect(MatchScore.fromJson({'target': 0, 'winner': 'lowest', 'seats': 2, 'deals': []}), isNull);
    });
  });

  group('the controller', () {
    /// Plays one deal of [game]: the player takes [take] (3 of 3 wins at
    /// once; 1 of 3 leaves 2, and the bot takes them).
    Future<void> playDeal(_MatchNim game, String take) async {
      game.humanMove(take);
      for (var i = 0; i < 10 && !game.isOver; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(game.isOver, isTrue);
    }

    test('a new game starts a match; each deal adds its points once; Next deal carries the totals', () async {
      final game = _MatchNim(jobs: Jobs.inline(extra: nimJobs));
      await game.newGame();
      expect(game.match!.totals, [0, 0]);
      expect(game.match!.deals, isEmpty);
      await playDeal(game, '1'); // the bot wins: the player takes 4
      expect(game.match!.totals, [4, 0]);
      expect(game.dealPointsAsked, 1);
      expect(game.between, isTrue);
      await game.nextRound();
      expect(game.match!.totals, [4, 0], reason: 'carried into the next deal');
      await playDeal(game, '3'); // the player wins: the bot takes 4
      expect(game.match!.totals, [4, 4]);
      expect(game.match!.deals, hasLength(2));
      expect(game.dealPointsAsked, 2);
      game.dispose();
    });

    test('once a total reaches the target the match is over: no Next deal; a new game is a new match', () async {
      final game = _MatchNim(jobs: Jobs.inline(extra: nimJobs), target: 8);
      await game.newGame();
      await playDeal(game, '1');
      expect(game.matchOver, isFalse);
      await game.nextRound();
      await playDeal(game, '1');
      expect(game.match!.totals, [8, 0]);
      expect(game.matchOver, isTrue);
      expect(game.between, isFalse, reason: 'New match, not Next deal');
      expect(game.match!.leaders, [1]);
      await game.nextRound();
      expect(game.match!.deals, hasLength(2), reason: 'Next deal does nothing once the match is over');
      await game.newGame();
      expect(game.match!.deals, isEmpty);
      expect(game.match!.totals, [0, 0]);
      game.dispose();
    });

    test('No limit: no match in the record, the deals just go on', () async {
      final game = _MatchNim(jobs: Jobs.inline(extra: nimJobs), target: null);
      await game.newGame();
      await playDeal(game, '1');
      expect(game.match, isNull);
      expect(game.record.extra.containsKey(MatchScore.extraKey), isFalse);
      expect(game.between, isTrue);
      game.dispose();
    });

    test("the totals are in the record's JSON once the deal is over (what the last game saves)", () async {
      final game = _MatchNim(jobs: Jobs.inline(extra: nimJobs));
      await game.newGame();
      await playDeal(game, '1');
      final json = jsonDecode(jsonEncode(game.record.toJson())) as Map<String, Object?>;
      final extra = json['extra']! as Map<String, Object?>;
      expect(MatchScore.fromJson(extra[MatchScore.extraKey])?.totals, [4, 0]);
      game.dispose();
    });
  });

  group('on screen', () {
    Future<_MatchNim> pump(WidgetTester tester, _MatchNim game, {Size size = const Size(900, 420), AppLanguage language = AppLanguage.english}) async {
      await game.newGame();
      await pumpShot(
        tester,
        GameScaffold(
          title: S.forLanguage(language).bigTwo,
          strings: BigTwoStrings.forLanguage(language),
          controller: game,
          table: const FeltArea(),
          panel: const SizedBox(height: 48),
          matchPlay: true,
        ),
        size: size,
        language: language,
      );
      await tester.pump();
      return game;
    }

    Future<void> play(WidgetTester tester, _MatchNim game, String take) async {
      game.humanMove(take);
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
    }

    Future<void> close(WidgetTester tester, _MatchNim game) async {
      await tester.pumpWidget(const SizedBox());
      game.dispose();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('the status says the deal, your total and the target; a tap on it opens the scoreboard', (tester) async {
      final game = await pump(tester, _MatchNim(jobs: Jobs.inline(extra: nimJobs)));
      expect(find.text('Deal 1 · You 0 · To 10'), findsOneWidget);
      await play(tester, game, '1');
      expect(find.text('Deal 1 · You 4 · To 10'), findsOneWidget, reason: 'the deal just over');
      expect(find.byKey(const ValueKey('panel scores')), findsOneWidget, reason: 'the scores between deals');
      expect(find.text('Next deal'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('open scores')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scoreboard')), findsOneWidget);
      expect(find.text('Scores · To 10'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sheet close')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next deal'));
      await tester.pump();
      expect(find.text('Deal 2 · You 4 · To 10'), findsOneWidget);
      await close(tester, game);
    });

    testWidgets('the match over: who won it, a trophy, New match; New match starts again from 0', (tester) async {
      final game = await pump(tester, _MatchNim(jobs: Jobs.inline(extra: nimJobs), target: 8));
      await play(tester, game, '1');
      await tester.tap(find.text('Next deal'));
      await tester.pump();
      await play(tester, game, '1');
      expect(find.text('Ana wins the match'), findsOneWidget);
      expect(find.byKey(const ValueKey('match winner')), findsOneWidget);
      expect(find.text('New match'), findsOneWidget);
      expect(find.text('Next deal'), findsNothing);
      await tester.tap(find.text('New match'));
      await tester.pump();
      expect(game.match!.deals, isEmpty);
      expect(find.text('Deal 1 · You 0 · To 10'), findsNothing);
      expect(find.text('Deal 1 · You 0 · To 8'), findsOneWidget);
      await close(tester, game);
    });

    testWidgets('a shared best total ends the match as a tie, never as a win for one of them', (tester) async {
      final game = await pump(tester, _TieNim(jobs: Jobs.inline(extra: nimJobs)));
      await play(tester, game, '1');
      await tester.tap(find.text('Next deal'));
      await tester.pump();
      await play(tester, game, '3');
      expect(game.matchOver, isTrue);
      expect(game.match!.leaders, [0, 1]);
      expect(find.text('Tie: You and Ana'), findsOneWidget);
      expect(find.text('You win the match'), findsNothing);
      expect(find.text('New match'), findsOneWidget);
      await close(tester, game);
    });

    testWidgets('on a sideways phone the status keeps the target in sight: no deal number', (tester) async {
      final game = await pump(tester, _MatchNim(jobs: Jobs.inline(extra: nimJobs)), size: const Size(568, 320));
      final status = tester.widget<Text>(find.byKey(const ValueKey('status 2')));
      expect(status.data, 'You 0 · To 10');
      await close(tester, game);
    });

    testWidgets('☰ Scores opens the scoreboard; greyed out, not hidden, without a target', (tester) async {
      final game = await pump(tester, _MatchNim(jobs: Jobs.inline(extra: nimJobs), target: null));
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      final item = find.ancestor(of: find.text('Scores'), matching: find.byType(PopupMenuItem<VoidCallback>));
      expect(item, findsOneWidget);
      expect(tester.widget<PopupMenuItem<VoidCallback>>(item).enabled, isFalse);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      await close(tester, game);
    });

    for (final language in AppLanguage.values) {
      for (final size in [...shotSizes, const Size(900, 420)]) {
        final tag = shotTag(size, language);
        testWidgets('the scores at $tag: between deals, at the end and on the sheet, nothing overflows', (tester) async {
          final game = await pump(
            tester,
            _MatchNim(jobs: Jobs.inline(extra: nimJobs), target: 12),
            size: size,
            language: language,
          );
          await play(tester, game, '1');
          await shot(tester, 'match_between_$tag');
          for (final take in ['3', '1', '3', '1']) {
            await game.nextRound();
            await tester.pump();
            await play(tester, game, take);
          }
          expect(game.matchOver, isTrue);
          final k = KitStrings.forLanguage(language);
          expect(find.text(k.winsMatch('Ana')), findsOneWidget);
          await shot(tester, 'match_over_$tag');
          await tester.tap(find.byKey(const ValueKey('open scores')));
          await tester.pumpAndSettle();
          final sheet = tester.getRect(find.byKey(const ValueKey('scoreboard')));
          expect(sheet.right, lessThanOrEqualTo(size.width));
          await shot(tester, 'match_sheet_$tag');
          await close(tester, game);
        });
      }
    }
  });

  group('the setup row', () {
    testWidgets("Play to: the game's targets and No limit; Scale with players greyed out under No limit", (tester) async {
      var value = const MatchTarget(points: 100);
      await pumpShot(
        tester,
        StatefulBuilder(
          builder: (context, setState) => SetupPage(
            title: 'Big Two',
            left: [
              MatchTargetRow(
                value: value,
                choices: const [50, 100, 150, 200],
                onChanged: (v) => setState(() => value = v),
              ),
            ],
            onStart: () {},
          ),
        ),
        size: const Size(568, 320),
      );
      expect(find.text('Play to'), findsOneWidget);
      for (final label in ['50', '100', '150', '200', 'No limit']) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('Scale with players'));
      await tester.pump();
      expect(value, const MatchTarget(points: 100, scale: true));
      await shot(tester, 'match_setup_en_568x320');
      await tester.tap(find.text('No limit'));
      await tester.pump();
      expect(value.points, isNull);
      final scale = tester.widget<SwitchRow>(find.byKey(const ValueKey('scale with players')));
      expect(scale.enabled, isFalse, reason: 'greyed out, not hidden');
      await tester.tap(find.text('150'));
      await tester.pump();
      expect(value, const MatchTarget(points: 150, scale: true), reason: 'the switch remembers its place');
    });

    for (final language in AppLanguage.values) {
      testWidgets('the setup row in ${language.code} at 568x320 fits on its lines', (tester) async {
        await pumpShot(
          tester,
          SetupPage(
            title: 'Big Two',
            left: [MatchTargetRow(value: const MatchTarget(points: 100), choices: const [50, 100, 150, 200], onChanged: (_) {})],
            onStart: () {},
          ),
          size: const Size(568, 320),
          language: language,
        );
        await shot(tester, 'match_setup_${language.code}_568x320');
      });
    }
  });
}
