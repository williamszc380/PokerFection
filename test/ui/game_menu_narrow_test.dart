import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/main.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/ui/game_menu.dart';
import 'package:pokerfection/src/ui/games.dart';
import 'package:pokerfection/src/ui/widgets/game_emblems.dart';

/// Small phones held sideways: an Android phone with its buttons bar on
/// the side (592x360), and a small iPhone's browser (568x320). The old
/// main menu fit both, so the game menu must too.
const _sizes = [Size(592, 360), Size(568, 320)];

void main() {
  for (final size in _sizes) {
    testWidgets("Hold'em's menu at $size fits, Guides open too", (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(PokerFectionApp(settings: AppSettings()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Home');
      await tester.tap(find.byKey(const ValueKey('game holdem')));
      await tester.pumpAndSettle();
      expect(find.byType(GameMenu), findsOneWidget);
      expect(tester.takeException(), isNull, reason: "Hold'em's menu");
      // The emblem stays beside the buttons, and the buttons keep a roomy width.
      final play = tester.getRect(find.widgetWithText(FilledButton, 'Play'));
      expect(tester.getRect(find.descendant(of: find.byType(GameMenu), matching: find.byType(HoldemEmblem))).right, lessThan(play.left));
      expect(play.width, greaterThanOrEqualTo(360));
      expect(play.right, lessThanOrEqualTo(size.width));
      await tester.tap(find.byIcon(Icons.menu_book_outlined));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Guides open');
    });
  }

  testWidgets(
      "a button that can't be used yet (Last game, none saved) is greyed out, and asked again when a screen "
      'opened from the menu closes', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var saved = false;
    var asked = 0;
    final game = GameInfo(
      id: GameId.blackjack,
      name: (s) => s.blackjack,
      emblem: (size) => BlackjackEmblem(size: size),
      menu: [
        GameMenuButton(
          icon: Icons.play_arrow,
          label: (_) => 'Play',
          open: (_) => Scaffold(appBar: AppBar(title: const Text('The game'))),
        ),
        GameMenuButton(
          icon: Icons.history,
          label: (_) => 'Last game',
          open: (_) => const Scaffold(body: Text('The last game')),
          enabled: (_) async {
            asked++;
            return saved;
          },
        ),
        GameMenuButton(
          icon: Icons.bug_report,
          label: (_) => 'Broken',
          open: (_) => const SizedBox(),
          enabled: (_) => Future.error(StateError('no store')),
        ),
      ],
    );
    await tester.pumpWidget(AppSettingsScope(
      settings: AppSettings(),
      child: MaterialApp(home: GameMenu(game: game)),
    ));
    await tester.pumpAndSettle();
    OutlinedButton button(String label) => tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, label));
    expect(asked, 1, reason: 'asked once when the menu opens');
    expect(button('Last game').onPressed, isNull, reason: 'greyed out: nothing saved yet');
    expect(button('Broken').onPressed, isNull, reason: 'a check that fails greys the button out');
    // A game is played and saved; coming back to the menu lights Last game up.
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    saved = true;
    await tester.pumpAndSettle();
    expect(asked, 1, reason: 'not asked while the game is open');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(asked, 2);
    expect(button('Last game').onPressed, isNotNull);
    await tester.tap(find.text('Last game'));
    await tester.pumpAndSettle();
    expect(find.text('The last game'), findsOneWidget);
  });
}
