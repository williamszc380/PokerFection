import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/main.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/ui/settings_screen.dart';
import 'package:pokerfection/src/ui/widgets/gomoku_board.dart';

import 'memory_store.dart';

void main() {
  testWidgets('Settings: General, Cards & Table, then Board & Stones, whose choices are saved and load back',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryStore();
    final settings = AppSettings(store: store);
    await tester.pumpWidget(AppSettingsScope(
      settings: settings,
      child: MaterialApp(theme: PokerFectionApp.theme, home: const SettingsScreen()),
    ));
    final scrollable = find.byType(Scrollable).first;
    for (final group in ['General', 'Cards & Table', 'Board & Stones']) {
      await tester.scrollUntilVisible(find.text(group), 200, scrollable: scrollable);
      expect(find.text(group), findsOneWidget);
    }
    expect(settings.board, BoardStyle.lightWood, reason: 'the default');
    expect(settings.stones, StoneStyle.glossy, reason: 'the default');

    // Each choice is a small board: 4 board colors, 2 stone looks.
    await tester.scrollUntilVisible(find.text('Flat'), 200, scrollable: scrollable);
    expect(find.byType(GomokuBoard), findsNWidgets(BoardStyle.values.length + StoneStyle.values.length));
    await tester.tap(find.text('Dark Wood'));
    await tester.pump();
    await tester.tap(find.text('Flat'));
    await tester.pump();
    expect([settings.board, settings.stones], [BoardStyle.darkWood, StoneStyle.flat]);
    expect([store.saved['board'], store.saved['stones']], ['darkWood', 'flat']);
    // The previews follow: the stone looks on dark wood.
    final previews = tester.widgetList<GomokuBoard>(find.byType(GomokuBoard)).toList();
    expect(previews.last.boardStyle, isNull, reason: 'the board as set');
    final painter = tester
        .widgetList<CustomPaint>(find.descendant(of: find.byWidget(previews.last), matching: find.byType(CustomPaint)))
        .first
        .painter! as GomokuBoardPainter;
    expect(painter.board, BoardStyle.darkWood);

    final again = AppSettings(store: store);
    await again.load();
    expect([again.board, again.stones], [BoardStyle.darkWood, StoneStyle.flat]);
  });

  test('settings saved before Board & Stones, or with choices that no longer exist, load the defaults', () async {
    final old = AppSettings(store: MemoryStore({'language': 'spanish', 'felt': 'blue', 'cardBack': 'red'}));
    await old.load();
    expect([old.language, old.felt, old.cardBack], [AppLanguage.spanish, FeltStyle.blue, CardBackStyle.red]);
    expect([old.board, old.stones], [BoardStyle.lightWood, StoneStyle.glossy]);

    final odd = AppSettings(store: MemoryStore({'board': 'marble', 'stones': 3}));
    await odd.load();
    expect([odd.board, odd.stones], [BoardStyle.lightWood, StoneStyle.glossy]);
  });
}
