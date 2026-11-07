// Across the card games: the same words and the same order for the same
// buttons, and the "?" explanations readable on a sideways phone.
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_controller.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_setup.dart';
import 'package:pokerfection/src/ui/games/big_two/l10n/big_two_strings.dart';
import 'package:pokerfection/src/ui/games/doudizhu/l10n/doudizhu_strings.dart';

import '../../kit/shots.dart';
import 'big_two/big_two_test_util.dart' as b2;
import 'doudizhu/states.dart' as dzs;

/// The left-to-right order of the Play, Pass and Clear buttons on screen.
List<String> buttonOrder(WidgetTester tester) {
  final keys = ['play', 'pass', 'clear'];
  keys.sort((a, b) => tester.getCenter(find.byKey(ValueKey(a))).dx.compareTo(tester.getCenter(find.byKey(ValueKey(b))).dx));
  return keys;
}

void main() {
  setUpAll(loadShotFonts);

  for (final language in AppLanguage.values) {
    test('Big Two and Fight the Landlord name Clear and a single card alike (${language.name})', () {
      final b = BigTwoStrings.forLanguage(language), d = LandlordStrings.forLanguage(language);
      expect(b.clear, d.clear, reason: 'the same button');
      expect(b.play, d.play);
      expect(b.kind(PlayKind.single), d.kind(PlayType.solo), reason: 'the same play');
    });
  }

  testWidgets('Big Two and Fight the Landlord put Play, Pass and Clear in the same order', (tester) async {
    final big = b2.seededGame(training: false);
    await b2.pumpGame(tester, big);
    await b2.toMyPlayableTurn(tester, big);
    final bigOrder = buttonOrder(tester);
    await b2.closeGame(tester);
    final c = await dzs.gameAt(tester, DdzPhase.playing, training: false);
    await dzs.showGame(tester, c, const Size(1280, 800), AppLanguage.english);
    final ddzOrder = buttonOrder(tester);
    await dzs.closeGame(tester, c);
    expect(ddzOrder, bigOrder);
  });

  for (final size in const [Size(568, 320), Size(592, 360)]) {
    testWidgets('the presets "?" gives its text at least half of a sideways phone ($size)', (tester) async {
      await pumpShot(tester, BigTwoSetupScreen(initial: BigTwoSetup.from(null)), size: size);
      await tester.pump();
      final help = find.byKey(const ValueKey('presets help'));
      await tester.scrollUntilVisible(help, 100, scrollable: find.byType(Scrollable).first);
      await tester.tap(help);
      await tester.pumpAndSettle();
      final scroll = find.descendant(of: find.byType(AlertDialog), matching: find.byType(Scrollable)).first;
      final room = tester.getRect(scroll).height;
      final position = tester.state<ScrollableState>(scroll).position;
      final text = position.maxScrollExtent + position.viewportDimension;
      expect(room, greaterThanOrEqualTo(size.height * 0.5),
          reason: '${room.toStringAsFixed(0)} px of room for ${text.toStringAsFixed(0)} px of text');
    });
  }
}
