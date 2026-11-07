// Gomoku on Home and its game menu: Play, Last game (greyed out until a
// game is saved, and lit as soon as the player comes back from one) and
// Guides (Rules, Threats), at the three sizes in the three languages.
// Screenshots with --dart-define=SHOTS=<folder>.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/gomoku/app/gomoku_record.dart';
import 'package:pokerfection/src/games/gomoku/gomoku.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/ui/game_menu.dart';
import 'package:pokerfection/src/ui/games/gomoku/gomoku_entry.dart';
import 'package:pokerfection/src/ui/games/gomoku/gomoku_guides.dart';
import 'package:pokerfection/src/ui/games/gomoku/gomoku_review.dart';
import 'package:pokerfection/src/ui/games/gomoku/gomoku_screen.dart';
import 'package:pokerfection/src/ui/games/gomoku/gomoku_setup.dart';
import 'package:pokerfection/src/ui/games/gomoku/gomoku_table.dart';
import 'package:pokerfection/src/ui/games/gomoku/l10n/gomoku_strings.dart';
import 'package:pokerfection/src/ui/home_screen.dart';
import 'package:pokerfection/src/ui/kit/game_sounds.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';
import 'package:pokerfection/src/ui/kit/review_kit.dart';

import '../../../kit/shots.dart';
import 'gomoku_harness.dart';

/// A menu button by its text (the first one is filled, the rest outlined).
ButtonStyleButton menuButton(WidgetTester tester, String label) => tester.widget<ButtonStyleButton>(
  find.ancestor(of: find.text(label), matching: find.bySubtype<ButtonStyleButton>()).first,
);

/// A short game saved as the most recent one.
LastGames savedGame() =>
    LastGames()..save(GomokuRecord.start(const GomokuOptions(), seed: 3, moves: const ['h8', 'h9', 'i8']));

void main() {
  setUpAll(loadShotFonts);
  setUp(() => GameSounds.output = (_) {});

  testWidgets('Home: Gomoku is lit (no "Soon") and opens its menu', (tester) async {
    await pumpGomoku(tester, const HomeScreen());
    await tester.pumpAndSettle();
    final tile = find.byKey(const ValueKey('game gomoku'));
    expect(gomokuGame.ready, isTrue);
    expect(find.descendant(of: tile, matching: find.text(S.forLanguage(AppLanguage.english).soon)), findsNothing);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.byType(GameMenu), findsOneWidget);
    for (final label in ['Play', 'Last game', 'Guides']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets(
    'Last game is greyed out with no game saved, and lit on coming back from the first one; it opens the review',
    (tester) async {
      final store = LastGames();
      await pumpGomoku(tester, GameMenu(game: gomokuGame), lastGames: store);
      await tester.pumpAndSettle();
      expect(menuButton(tester, 'Last game').onPressed, isNull, reason: 'nothing saved yet');
      expect(find.text('Last game'), findsOneWidget, reason: 'greyed out, not hidden');

      // Play: the setup, then Start: the game.
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(find.byType(GomokuSetup), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('start')));
      await settleGomoku(tester);
      expect(find.byType(GomokuScreen), findsOneWidget);
      // One stone, then the bot's.
      final at = pointOnScreen(tester, boardPoint(GomokuMove.parse('h8'), 15));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: at);
      await mouse.down(at);
      await mouse.up();
      await mouse.removePointer();
      await settleGomoku(tester, rounds: 6);

      // ☰ Leave, back to the menu: the game is saved, Last game lights up.
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text(S.forLanguage(AppLanguage.english).leave));
      await tester.pumpAndSettle();
      expect(find.byType(GameMenu), findsOneWidget);
      expect(menuButton(tester, 'Last game').onPressed, isNotNull);
      await tester.tap(find.text('Last game'));
      await tester.pumpAndSettle();
      expect(find.byType(GomokuReview), findsOneWidget);
      expect(tester.widget<ReviewScaffold>(find.byType(ReviewScaffold)).record.moves.first, 'h8');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets('a saved game that no longer replays leaves Last game greyed out', (tester) async {
    // Two stones on one point: not a legal game.
    final store = LastGames()..save(GomokuRecord.start(const GomokuOptions(), seed: 3, moves: const ['h8', 'h8']));
    await pumpGomoku(tester, GameMenu(game: gomokuGame), lastGames: store);
    await tester.pumpAndSettle();
    expect(menuButton(tester, 'Last game').onPressed, isNull);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Guides: Rules and Threats open their guides', (tester) async {
    await pumpGomoku(tester, GameMenu(game: gomokuGame));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guides'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rules'));
    await tester.pumpAndSettle();
    expect(find.byType(GomokuRulesGuide), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Threats'));
    await tester.pumpAndSettle();
    expect(find.byType(GomokuThreatsGuide), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  });

  for (final size in shotSizes) {
    for (final language in AppLanguage.values) {
      final tag = shotTag(size, language);
      testWidgets('menu $tag: Play, Last game lit with a game saved, Guides open; nothing overflows', (tester) async {
        final s = S.forLanguage(language);
        final k = KitStrings.forLanguage(language);
        final g = GomokuStrings.forLanguage(language);
        await pumpGomoku(tester, GameMenu(game: gomokuGame), size: size, language: language, lastGames: savedGame());
        await tester.pumpAndSettle();
        await shot(tester, 'gomoku_menu_$tag');
        expect(tester.takeException(), isNull);
        expect(menuButton(tester, s.play).onPressed, isNotNull);
        expect(menuButton(tester, k.lastGame).onPressed, isNotNull);
        await tester.tap(find.text(s.guides));
        await tester.pumpAndSettle();
        await shot(tester, 'gomoku_menu_guides_$tag');
        expect(tester.takeException(), isNull);
        for (final label in [s.rules, g.threats]) {
          final text = find.text(label);
          expect(text, findsOneWidget);
          // Each choice's name shows whole, on the screen.
          final box = tester.getRect(text);
          expect(box.left >= 0 && box.right <= size.width && box.bottom <= size.height, isTrue, reason: '$label at $box');
          expect(menuButton(tester, label).onPressed, isNotNull);
        }
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
}
