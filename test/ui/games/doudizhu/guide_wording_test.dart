// The Combinations guide shows each kind as "Beats: <rule>". The rule must
// name what the kind beats (a LOWER one of its kind) in every language,
// as the Spanish ("Gana a: Una carta más baja") and Chinese ("能管: 比它小的
// 单张") do; a trainer must not teach that a single beats a higher single.
// The setup's switches explain themselves behind "?": what a four with
// two is, and what "Rocket as kickers" allows.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/ui/games/doudizhu/l10n/doudizhu_strings.dart';
import 'package:pokerfection/src/ui/kit/help.dart';

import '../../../kit/shots.dart';
import 'setup_test.dart' show showSetup;

void main() {
  setUpAll(loadShotFonts);

  test('"Beats:" is followed by what the kind beats: a lower one of its kind', () {
    final en = LandlordStrings.forLanguage(AppLanguage.english);
    for (final type in PlayType.values) {
      if (type == PlayType.bomb || type == PlayType.rocket) continue;
      final line = '${en.beats}: ${en.kindRule(type)}';
      expect(line, contains('lower'), reason: line);
      expect(line, isNot(contains('higher')), reason: line);
    }
    final es = LandlordStrings.forLanguage(AppLanguage.spanish);
    expect('${es.beats}: ${es.kindRule(PlayType.solo)}', contains('más baja'));
  });

  testWidgets('the "?" of "Four with two" says what it is, and of "Rocket as kickers" what it allows', (tester) async {
    await showSetup(tester, LastGames());
    final en = LandlordStrings.forLanguage(AppLanguage.english);
    Future<void> openHelp(String key) async {
      final help = find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TermsHelpButton));
      await tester.ensureVisible(help);
      await tester.tap(help);
      await tester.pumpAndSettle();
    }

    await openHelp('four with two');
    expect(find.text(en.fourWithTwoInfo), findsOneWidget);
    expect(find.textContaining('Four of a kind'), findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    await openHelp('rocket as kickers');
    expect(find.text(en.rocketAsKickersInfo), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
