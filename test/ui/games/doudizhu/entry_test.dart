// Fight the Landlord on Home and its game menu: Play, Last game (greyed out
// until a deal is saved, and lit as soon as the player comes back from one)
// and Guides (Rules, Combinations), at the three sizes in the three
// languages. Screenshots with --dart-define=SHOTS=<folder>.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_jobs.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/ui/game_menu.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_entry.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_guides.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_review.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_screen.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_setup.dart';
import 'package:pokerfection/src/ui/games/doudizhu/l10n/doudizhu_strings.dart';
import 'package:pokerfection/src/ui/home_screen.dart';
import 'package:pokerfection/src/ui/kit/game_scaffold.dart';
import 'package:pokerfection/src/ui/kit/game_sounds.dart';
import 'package:pokerfection/src/ui/kit/kit_scope.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';
import 'package:pokerfection/src/ui/kit/review_kit.dart';

import '../../../kit/shots.dart';

const sizes = [Size(568, 320), Size(390, 844), Size(1280, 800)];

Widget Function(Widget child) kitWrap(LastGames store) =>
    (child) => KitScope(newJobs: Jobs.inline, lastGames: store, child: child);

/// A menu button by its text (the first one is filled, the rest outlined).
ButtonStyleButton menuButton(WidgetTester tester, String label) => tester.widget<ButtonStyleButton>(
  find.ancestor(of: find.text(label), matching: find.bySubtype<ButtonStyleButton>()).first,
);

Future<void> settle(WidgetTester tester, [int rounds = 20]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(loadShotFonts);
  setUp(() => GameSounds.output = (_) {});

  testWidgets('Home: Fight the Landlord is lit (no "Soon") and opens its menu', (tester) async {
    await pumpShot(tester, const HomeScreen(), size: const Size(1280, 800), wrap: kitWrap(LastGames()));
    await tester.pumpAndSettle();
    final tile = find.byKey(const ValueKey('game fightTheLandlord'));
    expect(doudizhuGame.ready, isTrue);
    expect(find.descendant(of: tile, matching: find.text(S.forLanguage(AppLanguage.english).soon)), findsNothing);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.byType(GameMenu), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Last game'), findsOneWidget);
    expect(find.text('Guides'), findsOneWidget);
  });

  testWidgets('Last game is greyed out with no deal saved, and lit on coming back from the first one; '
      'it opens the review', (tester) async {
    final store = LastGames();
    await pumpShot(
      tester,
      GameMenu(game: doudizhuGame),
      size: const Size(1280, 800),
      wrap: kitWrap(store),
    );
    await tester.pumpAndSettle();
    expect(menuButton(tester, 'Last game').onPressed, isNull, reason: 'nothing saved yet');

    // Play: the setup, then Start: the game, a deal dealt.
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    expect(find.byType(LandlordSetup), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('start')));
    await settle(tester);
    expect(find.byType(LandlordScreen), findsOneWidget);
    // Some moves (the bots' bids, maybe the player's turn).
    final game = tester.widget<GameScaffold>(find.byType(GameScaffold)).controller;
    for (var i = 0; i < 100 && game.record.moves.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (game.seatToAct == 0) {
        await tester.tap(
          find.byKey(const ValueKey('bid 0')).evaluate().isEmpty
              ? find.byKey(const ValueKey('call 0'))
              : find.byKey(const ValueKey('bid 0')),
        );
      }
    }
    expect(game.record.moves, isNotEmpty);

    // ☰ Leave, back to the menu: the deal is saved, Last game lights up.
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.forLanguage(AppLanguage.english).leave));
    await tester.pumpAndSettle();
    expect(find.byType(GameMenu), findsOneWidget);
    expect(menuButton(tester, 'Last game').onPressed, isNotNull);
    await tester.tap(find.text('Last game'));
    await tester.pumpAndSettle();
    expect(find.byType(LandlordReview), findsOneWidget);
    expect(tester.widget<ReviewScaffold>(find.byType(ReviewScaffold)).record.moves, isNotEmpty);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a saved deal that no longer plays back leaves Last game greyed out', (tester) async {
    final store = LastGames();
    // A move out of turn: the deal can't be replayed.
    final saved = ddzSampleGame(1);
    store.save(saved.withMove(saved.moves.last));
    await pumpShot(
      tester,
      GameMenu(game: doudizhuGame),
      size: const Size(1280, 800),
      wrap: kitWrap(store),
    );
    await tester.pumpAndSettle();
    expect(menuButton(tester, 'Last game').onPressed, isNull);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Guides: Rules and Combinations open their guides', (tester) async {
    await pumpShot(
      tester,
      GameMenu(game: doudizhuGame),
      size: const Size(1280, 800),
      wrap: kitWrap(LastGames()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guides'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rules'));
    await tester.pumpAndSettle();
    expect(find.byType(LandlordRulesGuide), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Combinations'));
    await tester.pumpAndSettle();
    expect(find.byType(LandlordCombinationsGuide), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  });

  for (final language in AppLanguage.values) {
    for (final size in sizes) {
      final tag = shotTag(size, language);
      testWidgets('menu $tag: Play, Last game lit with a deal saved, Guides open; nothing overflows', (tester) async {
        final s = S.forLanguage(language);
        final k = KitStrings.forLanguage(language);
        final l = LandlordStrings.forLanguage(language);
        final store = LastGames()..save(ddzSampleGame(1));
        await pumpShot(
          tester,
          GameMenu(game: doudizhuGame),
          size: size,
          language: language,
          wrap: kitWrap(store),
        );
        await tester.pumpAndSettle();
        await shot(tester, 'menu_$tag');
        expect(tester.takeException(), isNull);
        expect(menuButton(tester, s.play).onPressed, isNotNull);
        expect(menuButton(tester, k.lastGame).onPressed, isNotNull);
        await tester.tap(find.text(s.guides));
        await tester.pumpAndSettle();
        await shot(tester, 'menu_guides_$tag');
        expect(tester.takeException(), isNull);
        for (final label in [s.rules, l.combinations]) {
          final text = find.text(label);
          expect(text, findsOneWidget);
          // Each choice's name shows whole, on the screen.
          final box = tester.getRect(text);
          expect(
            box.left >= 0 && box.right <= size.width && box.bottom <= size.height,
            isTrue,
            reason: '$label at $box',
          );
          expect(menuButton(tester, label).onPressed, isNotNull);
        }
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
}
