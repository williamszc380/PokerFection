import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/main.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/bots/bot.dart';
import 'package:pokerfection/src/engine/events.dart';
import 'package:pokerfection/src/engine/rules.dart';
import 'package:pokerfection/src/gto/spot_strategy.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

void main() {
  for (final language in AppLanguage.values) {
    test('${language.label}: every glossary entry and label has a text', () {
      final s = S.forLanguage(language);
      for (final section in GlossarySection.values) {
        expect(s.section(section), isNotEmpty);
      }
      for (final term in GlossaryTerm.values) {
        expect(s.term(term), isNot(term.name), reason: '$term has no name');
        expect(s.definition(term).length, greaterThan(3), reason: '$term has no definition');
      }
      final texts = [
        for (final reason in Unavailable.values) s.unavailable(reason),
        for (final reason in [...NoAnswer.values, null]) s.noAnswer(reason),
        for (final grade in DecisionGrade.values) s.grade(grade),
        for (final speed in PlaybackSpeed.values) s.speed(speed),
        for (final style in BotStyle.values) s.style(style),
        for (final rule in RaiseRule.values) s.raiseRule(rule),
        for (final street in Street.values) s.street(street),
        s.potShare(0.33),
        s.potShare(1),
        s.potShare(0.4),
      ];
      expect(texts.every((t) => t.isNotEmpty), isTrue);
    });
  }

  testWidgets('the language button switches the whole app', (tester) async {
    final settings = AppSettings();
    await tester.pumpWidget(PokerFectionApp(settings: settings));
    expect(find.text('Play'), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Español').last);
    await tester.pumpAndSettle();
    expect(settings.language, AppLanguage.spanish);
    expect(find.text('Jugar'), findsOneWidget);
    expect(find.text('Ajustes'), findsOneWidget);
    settings.update((s) => s.language = AppLanguage.chinese);
    await tester.pumpAndSettle();
    expect(find.text('开始游戏'), findsOneWidget);
    // Material's own texts follow too (for example the back button's name).
    expect(MaterialLocalizations.of(tester.element(find.text('开始游戏'))).backButtonTooltip, '返回');
  });
}
