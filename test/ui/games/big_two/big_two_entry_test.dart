// Big Two on Home and its game menu: Play, Last game (greyed out until a
// deal is saved, and lit as soon as the player comes back from one) and
// Guides (Rules, Hand ranks), at the three sizes in the three languages.
// Screenshots with --dart-define=SHOTS=<folder>.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_record.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/kit/game_record.dart';
import 'package:pokerfection/src/kit/seats.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/ui/game_menu.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_entry.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_guides.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_review.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_screen.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_setup.dart';
import 'package:pokerfection/src/ui/games/big_two/l10n/big_two_strings.dart';
import 'package:pokerfection/src/ui/home_screen.dart';
import 'package:pokerfection/src/ui/kit/game_sounds.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';
import 'package:pokerfection/src/ui/kit/review_kit.dart';

import '../../../kit/shots.dart';
import 'big_two_test_util.dart';

/// A menu button by its text (the first one is filled, the rest outlined).
ButtonStyleButton menuButton(WidgetTester tester, String label) => tester.widget<ButtonStyleButton>(
  find.ancestor(of: find.text(label), matching: find.bySubtype<ButtonStyleButton>()).first,
);

/// A deal under [rules] saved as the most recent game, two moves in.
GameRecord savedRecord({BigTwoRules? rules}) {
  final r = rules ?? BigTwoRules.standard();
  var record = BigTwoRecord.deal(
    rules: r,
    seats: [
      const SeatSpec(human: true, name: 'Player'),
      for (var i = 1; i < r.players; i++) SeatSpec(human: false, level: KitLevel.easy, name: kitBotNames[i - 1]),
    ],
    seed: 11,
  );
  for (var k = 0; k < 2; k++) {
    final state = BigTwoRecord.replay(record);
    record = record.withMove(bigTwoMoveText(state.toMove, state.legalMoves().first));
  }
  return record;
}

/// Lets the menu's checks and the screens' jobs finish.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(loadShotFonts);
  setUp(() => GameSounds.output = (_) {});

  testWidgets('Home: Big Two is lit (no "Soon") and opens its menu', (tester) async {
    await pumpShot(tester, const HomeScreen(), size: const Size(1280, 800), wrap: bigTwoKit(LastGames()));
    await tester.pumpAndSettle();
    final tile = find.byKey(const ValueKey('game bigTwo'));
    expect(bigTwoGame.ready, isTrue);
    expect(find.descendant(of: tile, matching: find.text(S.forLanguage(AppLanguage.english).soon)), findsNothing);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.byType(GameMenu), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Last game'), findsOneWidget);
    expect(find.text('Guides'), findsOneWidget);
  });

  testWidgets(
    'Last game is greyed out with no deal saved, and lit on coming back from the first one; it opens the review',
    (tester) async {
      final store = LastGames();
      await pumpShot(
        tester,
        GameMenu(game: bigTwoGame),
        size: const Size(1280, 800),
        wrap: bigTwoKit(store),
      );
      await tester.pumpAndSettle();
      expect(menuButton(tester, 'Last game').onPressed, isNull, reason: 'nothing saved yet');

      // Play: the setup, then Start: the game, a deal dealt.
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(find.byType(BigTwoSetupScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('start')));
      await settle(tester);
      expect(find.byType(BigTwoScreen), findsOneWidget);

      // ☰ Leave, back to the menu: the deal is saved, Last game lights up.
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text(S.forLanguage(AppLanguage.english).leave));
      await tester.pumpAndSettle();
      expect(find.byType(GameMenu), findsOneWidget);
      expect(menuButton(tester, 'Last game').onPressed, isNotNull);
      await tester.tap(find.text('Last game'));
      await settle(tester);
      expect(find.byType(BigTwoReview), findsOneWidget);
      expect(find.byType(ReviewScaffold), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets('a saved deal that no longer plays back leaves Last game greyed out', (tester) async {
    final store = LastGames();
    // A move out of turn: the deal can't be replayed.
    final record = savedRecord();
    store.save(record.withMove(bigTwoMoveText((bigTwoMoveSeat(record.moves.last) + 2) % 4, Play.pass)));
    await pumpShot(
      tester,
      GameMenu(game: bigTwoGame),
      size: const Size(1280, 800),
      wrap: bigTwoKit(store),
    );
    await tester.pumpAndSettle();
    expect(menuButton(tester, 'Last game').onPressed, isNull);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets("Guides: Rules opens the rules; Hand ranks opens on the last game's rules", (tester) async {
    final store = LastGames()..save(savedRecord(rules: BigTwoRules.taiwan()));
    final t = BigTwoStrings.forLanguage(AppLanguage.english);
    await pumpShot(
      tester,
      GameMenu(game: bigTwoGame),
      size: const Size(1280, 800),
      wrap: bigTwoKit(store),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guides'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rules'));
    await tester.pumpAndSettle();
    expect(find.byType(BigTwoRulesGuide), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.handRanks));
    await settle(tester);
    expect(find.byType(BigTwoHandRanksGuide), findsOneWidget);
    final bar = tester.widget<SegmentedButton<int>>(
      find.ancestor(
        of: find.descendant(
          of: find.byKey(const ValueKey('presets')),
          matching: find.text(t.preset(BigTwoPreset.taiwan)),
        ),
        matching: find.byType(SegmentedButton<int>),
      ),
    );
    expect(bar.selected, {BigTwoPreset.values.indexOf(BigTwoPreset.taiwan)}, reason: 'the last game was Taiwan');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  });

  for (final language in AppLanguage.values) {
    for (final size in bigTwoSizes) {
      final tag = shotTag(size, language);
      testWidgets('menu $tag: Play, Last game lit with a deal saved, Guides open; nothing overflows', (tester) async {
        final s = S.forLanguage(language);
        final k = KitStrings.forLanguage(language);
        final t = BigTwoStrings.forLanguage(language);
        final store = LastGames()..save(savedRecord());
        await pumpShot(
          tester,
          GameMenu(game: bigTwoGame),
          size: size,
          language: language,
          wrap: bigTwoKit(store),
        );
        await tester.pumpAndSettle();
        await shot(tester, 'big_two_menu_$tag');
        expect(tester.takeException(), isNull);
        expect(menuButton(tester, s.play).onPressed, isNotNull);
        expect(menuButton(tester, k.lastGame).onPressed, isNotNull);
        await tester.tap(find.text(s.guides));
        await tester.pumpAndSettle();
        await shot(tester, 'big_two_menu_guides_$tag');
        expect(tester.takeException(), isNull);
        for (final label in [s.rules, t.handRanks]) {
          final text = find.text(label);
          expect(text, findsOneWidget);
          // Each choice's name shows whole, on the screen.
          final box = tester.getRect(text);
          final whole = box.left >= 0 && box.right <= size.width && box.bottom <= size.height;
          expect(whole, isTrue, reason: '$label at $box');
          expect(menuButton(tester, label).onPressed, isNotNull);
        }
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
}
