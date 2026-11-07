// Blackjack on Home and its game menu: Play, Last game (greyed out until a
// shoe is saved, and lit as soon as the player comes back from one) and
// Guides (Rules, Basic strategy), at the three sizes in the three
// languages. Screenshots with --dart-define=SHOTS=<folder>.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/blackjack/app/blackjack_record.dart';
import 'package:pokerfection/src/games/blackjack/blackjack.dart';
import 'package:pokerfection/src/kit/game_record.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/ui/game_menu.dart';
import 'package:pokerfection/src/ui/games/blackjack/blackjack_entry.dart';
import 'package:pokerfection/src/ui/games/blackjack/blackjack_guides.dart';
import 'package:pokerfection/src/ui/games/blackjack/blackjack_screen.dart';
import 'package:pokerfection/src/ui/games/blackjack/blackjack_setup.dart';
import 'package:pokerfection/src/ui/games/blackjack/l10n/blackjack_strings.dart';
import 'package:pokerfection/src/ui/home_screen.dart';
import 'package:pokerfection/src/ui/kit/game_sounds.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';
import 'package:pokerfection/src/ui/kit/review_kit.dart';

import '../../../kit/shots.dart';
import 'blackjack_scenes.dart';

/// A menu button by its text (the first one is filled, the rest outlined).
ButtonStyleButton menuButton(WidgetTester tester, String label) => tester.widget<ButtonStyleButton>(
  find.ancestor(of: find.text(label), matching: find.bySubtype<ButtonStyleButton>()).first,
);

/// A shoe saved as the most recent game: two rounds played by the chart.
GameRecord savedShoe() {
  final play = BlackjackPlay(const BlackjackRules(), shoeSeed: seed16v10);
  var record = newBlackjackRecord(
    rules: const BlackjackRules(),
    seed: seed16v10,
    playerName: 'Player',
    dealerName: 'Dealer',
  );
  for (final move in [dealMove, handMove(0, BlackjackAction.stand), dealMove]) {
    play.apply(move);
    record = record.withMove(move);
  }
  return record;
}

void main() {
  setUpAll(loadShotFonts);
  setUp(() => GameSounds.output = (_) {});

  testWidgets('Home: Blackjack is lit (no "Soon") and opens its menu', (tester) async {
    await pumpShot(tester, const HomeScreen(), size: const Size(1280, 800), wrap: kitWrap(LastGames()));
    await tester.pumpAndSettle();
    final tile = find.byKey(const ValueKey('game blackjack'));
    expect(blackjackGame.ready, isTrue);
    expect(find.descendant(of: tile, matching: find.text(S.forLanguage(AppLanguage.english).soon)), findsNothing);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.byType(GameMenu), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Last game'), findsOneWidget);
    expect(find.text('Guides'), findsOneWidget);
  });

  testWidgets(
    'Last game is greyed out with no shoe saved, and lit on coming back from the first one; it opens the review',
    (tester) async {
      final store = LastGames();
      await pumpShot(
        tester,
        GameMenu(game: blackjackGame),
        size: const Size(1280, 800),
        wrap: kitWrap(store),
      );
      await tester.pumpAndSettle();
      expect(menuButton(tester, 'Last game').onPressed, isNull, reason: 'nothing saved yet');

      // Play: the setup, then Start: the game, a round dealt.
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(find.byType(BlackjackSetup), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('start')));
      await settleGame(tester);
      await tester.pumpAndSettle();
      expect(find.byType(BlackjackScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('deal')));
      await settleGame(tester);

      // ☰ Leave, back to the menu: the shoe is saved, Last game lights up.
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text(S.forLanguage(AppLanguage.english).leave));
      await tester.pumpAndSettle();
      expect(find.byType(GameMenu), findsOneWidget);
      expect(menuButton(tester, 'Last game').onPressed, isNotNull);
      await tester.tap(find.text('Last game'));
      await tester.pumpAndSettle();
      expect(find.byType(ReviewScaffold), findsOneWidget);
      expect(tester.widget<ReviewScaffold>(find.byType(ReviewScaffold)).record.moves, isNotEmpty);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets('a saved shoe that no longer plays back leaves Last game greyed out', (tester) async {
    final store = LastGames();
    // A move the engine doesn't know: the shoe can't be replayed.
    store.save(savedShoe().withMove('x'));
    await pumpShot(
      tester,
      GameMenu(game: blackjackGame),
      size: const Size(1280, 800),
      wrap: kitWrap(store),
    );
    await tester.pumpAndSettle();
    expect(menuButton(tester, 'Last game').onPressed, isNull);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Guides: Rules and Basic strategy open their guides', (tester) async {
    await pumpShot(
      tester,
      GameMenu(game: blackjackGame),
      size: const Size(1280, 800),
      wrap: kitWrap(LastGames()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guides'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rules'));
    await tester.pumpAndSettle();
    expect(find.byType(BlackjackRulesGuide), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Basic strategy'));
    await settleGame(tester);
    expect(find.byType(BlackjackStrategyGuide), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  });

  for (final language in AppLanguage.values) {
    for (final size in gameSizes) {
      final tag = shotTag(size, language);
      testWidgets('menu $tag: Play, Last game lit with a shoe saved, Guides open; nothing overflows', (tester) async {
        final s = S.forLanguage(language);
        final k = KitStrings.forLanguage(language);
        final b = BlackjackStrings.forLanguage(language);
        final store = LastGames()..save(savedShoe());
        await pumpShot(
          tester,
          GameMenu(game: blackjackGame),
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
        for (final label in [s.rules, b.pickLabel]) {
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
