/// The "?" dialog on a phone held sideways: the explanation, not the
/// dialog's frame, gets the screen. A preset's explanation runs to a page,
/// and reading it through a five-line slot would take a dozen scrolls.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/ui/kit/help.dart';
import 'package:pokerfection/src/ui/kit/l10n/game_strings.dart';

import 'shots.dart';

/// A page of explanation: more than any screen holds.
final _long = [
  for (var i = 0; i < 12; i++)
    GameTerm('Term $i', 'A long explanation that wraps over a few lines, as the presets of Big Two do. ' * 3),
];

Future<void> _openHelp(WidgetTester tester, Size size) async {
  await pumpShot(
    tester,
    Scaffold(
      body: Center(
        child: TermsHelpButton(title: 'Presets', terms: _long, all: _long),
      ),
    ),
    size: size,
  );
  await tester.tap(find.byType(TermsHelpButton));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadShotFonts);

  for (final size in const [Size(568, 320), Size(592, 360)]) {
    testWidgets('at $size the words get at least 60% of the height, Glossary and OK beside the title', (tester) async {
      await _openHelp(tester, size);
      final dialog = find.byKey(const ValueKey('terms help'));
      final scroll = find.descendant(of: dialog, matching: find.byType(Scrollable)).first;
      final room = tester.getRect(scroll).height;
      expect(room, greaterThanOrEqualTo(size.height * 0.6), reason: '${room.toStringAsFixed(0)} px of ${size.height}');
      final title = tester.getRect(find.text('Presets'));
      final ok = tester.getRect(find.widgetWithText(FilledButton, 'OK'));
      final glossary = tester.getRect(find.widgetWithText(TextButton, 'Glossary'));
      expect(ok.center.dy, closeTo(title.center.dy, 12), reason: 'OK on the title row');
      expect(glossary.center.dy, closeTo(title.center.dy, 12), reason: 'Glossary on the title row');
      expect(tester.takeException(), isNull);

      await tester.tap(find.widgetWithText(FilledButton, 'OK'));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing, reason: 'OK closes it');
    });
  }

  testWidgets('the compact dialog\'s Glossary opens the whole glossary', (tester) async {
    await _openHelp(tester, const Size(568, 320));
    await tester.tap(find.widgetWithText(TextButton, 'Glossary'));
    await tester.pumpAndSettle();
    expect(find.byType(GameGlossaryScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('terms help')), findsNothing);
  });

  testWidgets('on a tall screen it is the usual dialog: Glossary and OK under the words', (tester) async {
    await _openHelp(tester, const Size(1280, 800));
    final title = tester.getRect(find.text('Presets'));
    final ok = tester.getRect(find.widgetWithText(FilledButton, 'OK'));
    final words = tester.getRect(find.text('Term 0'));
    expect(ok.top, greaterThan(words.top), reason: 'the buttons sit below');
    expect(ok.top, greaterThan(title.bottom + 40));
  });
}
