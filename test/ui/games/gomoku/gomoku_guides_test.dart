import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/ui/games/gomoku/gomoku_guides.dart';
import 'package:pokerfection/src/ui/games/gomoku/l10n/gomoku_strings.dart';
import 'package:pokerfection/src/ui/widgets/gomoku_board.dart';

import '../../../kit/shots.dart';
import 'gomoku_harness.dart';

void main() {
  setUpAll(loadShotFonts);

  group('Threats', () {
    testWidgets('one small board per figure, each with its title and caption', (tester) async {
      await pumpGomoku(tester, const GomokuThreatsGuide(), size: const Size(1280, 800));
      final strings = GomokuStrings.forLanguage(AppLanguage.english);
      for (final spec in gomokuFigures) {
        final board = find.byKey(ValueKey('figure ${spec.figure.name}'), skipOffstage: false);
        await tester.scrollUntilVisible(board, 300, scrollable: find.byType(Scrollable).first);
        expect(tester.widget<GomokuBoard>(board).lines, 9);
        expect(find.text(strings.figureTitle(spec.figure)), findsOneWidget);
        expect(find.text(strings.figureCaption(spec.figure)), findsOneWidget);
      }
      await closeGomoku(tester);
    });

    testWidgets('the VCF figure numbers its moves, and the Renju ones cross out the forbidden point', (tester) async {
      await pumpGomoku(tester, const GomokuThreatsGuide(), size: const Size(1280, 800));
      final vcf = find.byKey(const ValueKey('figure vcf'), skipOffstage: false);
      await tester.scrollUntilVisible(vcf, 300, scrollable: find.byType(Scrollable).first);
      expect([for (final s in boardPainter(tester, board: vcf).sequence) s.label], ['1', '2', '3', '4', '5', '6', '7']);
      final three = find.byKey(const ValueKey('figure forbiddenThree'), skipOffstage: false);
      await tester.scrollUntilVisible(three, 300, scrollable: find.byType(Scrollable).first);
      expect(boardPainter(tester, board: three).forbidden, hasLength(1));
      await closeGomoku(tester);
    });
  });

  group('fits every size and language (guides scroll)', () {
    for (final size in gomokuSizes) {
      for (final language in AppLanguage.values) {
        testWidgets(shotTag(size, language), (tester) async {
          await pumpGomoku(tester, const GomokuThreatsGuide(), size: size, language: language);
          expect(tester.takeException(), isNull);
          await tester.fling(find.byType(Scrollable).first, const Offset(0, -3000), 3000);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await pumpGomoku(tester, const GomokuRulesGuide(), size: size, language: language);
          expect(find.text(GomokuStrings.forLanguage(language).rulesSections.first.$1), findsOneWidget);
          expect(tester.takeException(), isNull);
          await closeGomoku(tester);
        });
      }
    }
  });
}
