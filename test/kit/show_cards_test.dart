import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/ui/games/big_two/l10n/big_two_strings.dart';
import 'package:pokerfection/src/ui/kit/felt.dart';
import 'package:pokerfection/src/ui/kit/game_scaffold.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';
import 'package:pokerfection/src/ui/kit/turn_controller.dart';

import 'nim.dart';
import 'shots.dart';

Finder _item(String label) => find.ancestor(of: find.text(label), matching: find.byType(PopupMenuItem<VoidCallback>));

Future<NimController> _pump(WidgetTester tester, NimController game, {AppLanguage language = AppLanguage.english, Size size = const Size(900, 420)}) async {
  await game.newGame();
  await pumpShot(
    tester,
    GameScaffold(
      title: S.forLanguage(language).bigTwo,
      strings: BigTwoStrings.forLanguage(language),
      controller: game,
      table: const FeltArea(),
      panel: const SizedBox(height: 48),
      opponentCards: true,
    ),
    size: size,
    language: language,
  );
  await tester.pump();
  return game;
}

Future<void> _close(WidgetTester tester, NimController game) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox());
  game.dispose();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(loadShotFonts);

  testWidgets('☰ Show cards: off at first, a check mark once on, kept in the record\'s extra', (tester) async {
    final game = await _pump(tester, NimController(jobs: Jobs.inline(extra: nimJobs)));
    expect(game.showOpponentCards, isFalse);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(tester.widget<PopupMenuItem<VoidCallback>>(_item('Show cards')).enabled, isTrue);
    await shot(tester, 'show_cards_menu_en_900x420');
    await tester.tap(find.text('Show cards'));
    await tester.pumpAndSettle();
    expect(game.showOpponentCards, isTrue);
    expect(game.record.extra[TurnController.showCardsKey], isTrue);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.descendant(of: _item('Show cards'), matching: find.byKey(const ValueKey('checked'))), findsOneWidget);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    await _close(tester, game);
  });

  testWidgets('in Free Play it is greyed out, not hidden, and never on', (tester) async {
    final game = await _pump(
      tester,
      NimController(jobs: Jobs.inline(extra: nimJobs), training: false, extraAtStart: {TurnController.showCardsKey: true}),
    );
    expect(game.showOpponentCards, isFalse, reason: 'a Free Play game shows no cards, whatever the record says');
    game.showOpponentCards = true;
    expect(game.showOpponentCards, isFalse);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(_item('Show cards'), findsOneWidget);
    expect(tester.widget<PopupMenuItem<VoidCallback>>(_item('Show cards')).enabled, isFalse);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    await _close(tester, game);
  });

  test('carried into the next deal and the next game, like the other toggles', () async {
    final game = NimController(jobs: Jobs.inline(extra: nimJobs), rounds: true, pile: 3, training: true);
    await game.newGame();
    game.showOpponentCards = true;
    game.humanMove('3');
    await Future<void>.delayed(Duration.zero);
    await game.nextRound();
    expect(game.showOpponentCards, isTrue);
    await game.newGame();
    expect(game.showOpponentCards, isTrue);
    game.dispose();
  });

  test('only the screen reads it: coach and bot jobs get no extra', () async {
    final game = NimController(jobs: Jobs.inline(extra: nimJobs));
    await game.newGame();
    game.showOpponentCards = true;
    final position = game.coachRequest(game.record, 0, seed: 1).input! as Map<String, Object?>;
    expect((position['record']! as Map).containsKey('extra'), isFalse);
    game.dispose();
  });

  test('its words in every language', () {
    expect([for (final l in AppLanguage.values) KitStrings.forLanguage(l).showCards], ['Show cards', 'Mostrar cartas', '显示手牌']);
  });
}
