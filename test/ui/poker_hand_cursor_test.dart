/// Everything clickable in Hold'em's own screens shows the hand under the
/// mouse, as the new games' screens do: the theme gives it to buttons,
/// but chips and InkWells have to ask for it (Flutter's own default is the
/// hand in a browser only, the plain arrow on Windows).
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/ui/charts_screen.dart';
import 'package:pokerfection/src/ui/glossary.dart';
import 'package:pokerfection/src/ui/settings_screen.dart';
import 'package:pokerfection/src/ui/setup_screen.dart';

import '../kit/shots.dart';

Future<MouseCursor?> _cursorOn(WidgetTester tester, Finder finder) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(tester.getCenter(finder));
  await tester.pump();
  return RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);
}

void main() {
  testWidgets('the game setup: its "?" shows the hand', (tester) async {
    await pumpShot(tester, const SetupScreen(), size: const Size(1280, 800));
    await tester.pumpAndSettle();
    final help = find.byType(HelpButton).first;
    await tester.ensureVisible(help);
    // The scroll starts the app bar's "scrolled under" change; let it finish.
    await tester.pumpAndSettle();
    expect(await _cursorOn(tester, help), SystemMouseCursors.click, reason: '"?"');
  });

  testWidgets('the game setup: its choice chips show the hand', (tester) async {
    await pumpShot(tester, const SetupScreen(), size: const Size(1280, 800));
    await tester.pumpAndSettle();
    final chip = find.byWidgetPredicate((w) => w is ChoiceChip && w.onSelected != null && !w.selected).first;
    expect(await _cursorOn(tester, chip), SystemMouseCursors.click, reason: 'a choice chip');
  });

  testWidgets('Preflop Charts: its choice chips show the hand', (tester) async {
    await pumpShot(tester, const ChartsScreen(), size: const Size(1280, 800));
    await tester.pumpAndSettle();
    final chip = find.byWidgetPredicate((w) => w is ChoiceChip && w.onSelected != null && !w.selected).first;
    expect(await _cursorOn(tester, chip), SystemMouseCursors.click);
  });

  testWidgets('Settings: the card, table and board pictures to pick from show the hand', (tester) async {
    await pumpShot(tester, const SettingsScreen(), size: const Size(1280, 800));
    await tester.pumpAndSettle();
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('Dark Wood'), 200, scrollable: scrollable);
    await tester.pumpAndSettle();
    final picture = find.ancestor(of: find.text('Dark Wood'), matching: find.byType(InkWell)).first;
    expect(await _cursorOn(tester, picture), SystemMouseCursors.click);
  });
}
