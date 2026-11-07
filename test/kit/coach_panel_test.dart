import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/gto/spot_strategy.dart' show DecisionGrade;
import 'package:pokerfection/src/kit/coach_answer.dart';
import 'package:pokerfection/src/kit/grading.dart';
import 'package:pokerfection/src/ui/games/big_two/l10n/big_two_strings.dart';
import 'package:pokerfection/src/ui/games/blackjack/l10n/blackjack_strings.dart';
import 'package:pokerfection/src/ui/games/doudizhu/l10n/doudizhu_strings.dart';
import 'package:pokerfection/src/ui/games/gomoku/l10n/gomoku_strings.dart';
import 'package:pokerfection/src/ui/kit/coach_panel.dart';
import 'package:pokerfection/src/ui/kit/l10n/game_strings.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';
import 'package:pokerfection/src/ui/kit/move_feedback.dart';

import 'shots.dart';

final _gomoku = GomokuStrings.forLanguage(AppLanguage.english);

/// Pumps [child] in a scaffold, with a mouse at the top left corner.
Future<TestGesture> _withMouse(WidgetTester tester, Widget child) async {
  await pumpShot(tester, Scaffold(body: child), size: const Size(400, 300));
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return mouse;
}

/// Every game's strings in [language].
List<GameStrings> _allGames(AppLanguage language) => [
      GomokuStrings.forLanguage(language),
      BigTwoStrings.forLanguage(language),
      LandlordStrings.forLanguage(language),
      BlackjackStrings.forLanguage(language),
    ];

/// A proof badge as long as the games' ("Wins in 2", "Gana en 2", "2步胜").
String _proof(AppLanguage language) => switch (language) {
      AppLanguage.english => 'Wins in 2',
      AppLanguage.spanish => 'Gana en 2',
      AppLanguage.chinese => '2步胜',
    };

/// [text] (the only Text with it) is laid out whole: not cut, not wrapped,
/// and no smaller than [minSize].
void _expectWhole(WidgetTester tester, String text, {double minSize = 9}) {
  final paragraph = tester.renderObject<RenderParagraph>(find.text(text).last);
  expect(paragraph.didExceedMaxLines, isFalse, reason: '"$text" is cut');
  final size = paragraph.text.style?.fontSize ?? 14;
  expect(size, greaterThanOrEqualTo(minSize), reason: '"$text" got too small');
}

/// The panel's width on a 568x320 phone, less its padding: where a coach
/// row and the feedback have the least room.
const _phoneRow = 280.0 - 16;

void main() {
  setUpAll(loadShotFonts);

  for (final language in AppLanguage.values) {
    testWidgets("${language.code}: on a sideways phone every game's pick label reads in full beside a proof badge "
        'and a tag', (tester) async {
      for (final strings in _allGames(language)) {
        final tag = BlackjackStrings.forLanguage(language).tagLabel('count')!;
        final answer = CoachAnswer(
          unit: ValueUnit.winChance,
          lines: const [
            CoachLine(move: 'j6', value: 0.84, proof: 'win:2'),
            CoachLine(move: 'k7', value: 0.62, tag: 'count'),
          ],
        );
        await pumpShot(
          tester,
          Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: _phoneRow,
                child: CoachList(
                  answer: answer,
                  strings: _TagAll(strings, tag),
                  look: CoachLook(proofText: (p) => _proof(language)),
                ),
              ),
            ),
          ),
          size: const Size(568, 320),
          language: language,
        );
        expect(tester.takeException(), isNull);
        _expectWhole(tester, strings.pickLabel);
        _expectWhole(tester, _proof(language));
        _expectWhole(tester, tag);
        expect(find.text('j6'), findsOneWidget, reason: 'the move keeps its room');
        expect(tester.renderObject<RenderParagraph>(find.text('j6')).didExceedMaxLines, isFalse);
        if (strings is BlackjackStrings) await shot(tester, 'coach_tags_${language.code}');
      }
    });
  }

  testWidgets('the feedback draws moves with moveWidget, names them with markText, and says whose best move it is',
      (tester) async {
    const mark = MoveMark(
      grade: DecisionGrade.mistake,
      loss: 0.5,
      score: 40,
      played: 'insurance',
      best: 'decline',
      bestTag: 'count',
      unit: ValueUnit.bets,
    );
    final blackjack = BlackjackStrings.forLanguage(AppLanguage.english);
    await pumpShot(
      tester,
      Scaffold(
        body: MoveFeedback(
          mark: mark,
          unit: ValueUnit.winChance,
          strings: blackjack,
          moveIndex: 4,
          look: CoachLook(markText: (move, i) => i == 4 && move == 'insurance' ? 'Even money' : 'No thanks'),
        ),
      ),
      size: const Size(400, 300),
    );
    expect(find.text('Even money'), findsOneWidget, reason: 'named in its own position');
    expect(find.text('${blackjack.tagLabel('count')}: No thanks'), findsOneWidget, reason: "the count's move");
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('loss'))).data,
      KitStrings.forLanguage(AppLanguage.english).amount(ValueUnit.bets, -0.5),
      reason: "the mark's own unit (bets), not the panel's",
    );

    await pumpShot(
      tester,
      Scaffold(
        body: MoveFeedback(
          mark: const MoveMark(grade: DecisionGrade.mistake, loss: 1.2, score: 30, played: '7c 7h', best: '2s'),
          unit: ValueUnit.points,
          strings: BigTwoStrings.forLanguage(AppLanguage.english),
          look: CoachLook(moveWidget: (context, move) => Text('[$move]', key: ValueKey('drawn $move'))),
        ),
      ),
      size: const Size(400, 300),
    );
    expect(find.byKey(const ValueKey('drawn 7c 7h')), findsOneWidget, reason: 'the move played, drawn');
    expect(find.byKey(const ValueKey('drawn 2s')), findsOneWidget, reason: 'the pick, drawn after its label');
    expect(find.text('GTO:'), findsOneWidget);
  });

  testWidgets('on a sideways phone the compact feedback\'s "Estrategia básica: x" reads in full', (tester) async {
    final strings = BlackjackStrings.forLanguage(AppLanguage.spanish);
    await pumpShot(
      tester,
      Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: _phoneRow,
            child: MoveFeedback(
              mark: const MoveMark(grade: DecisionGrade.inaccuracy, loss: 0.04, score: 80, played: 'h', best: 's'),
              unit: ValueUnit.bets,
              strings: strings,
              inline: true,
              look: CoachLook(moveText: (m) => m == 's' ? 'Plantarse' : 'Pedir'),
            ),
          ),
        ),
      ),
      size: const Size(568, 320),
      language: AppLanguage.spanish,
    );
    expect(tester.takeException(), isNull);
    _expectWhole(tester, '${strings.pickLabel}: Plantarse', minSize: 10);
    expect(find.text('−0.04'), findsOneWidget, reason: 'the loss inline: its number alone, as the rows show theirs');
  });

  testWidgets("hovering the feedback's best move calls onPickHover when the game gives one, else onHover",
      (tester) async {
    const mark = MoveMark(grade: DecisionGrade.mistake, loss: 0.1, score: 37, played: 'a1', best: 'h8');
    final rows = <String?>[], card = <String?>[];
    final mouse = await _withMouse(
      tester,
      MoveFeedback(
        mark: mark,
        unit: ValueUnit.winChance,
        strings: _gomoku,
        look: CoachLook(onHover: rows.add, onPickHover: card.add),
      ),
    );
    await mouse.moveTo(tester.getCenter(find.text('${_gomoku.pickLabel}: h8')));
    await tester.pump();
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(card, ['h8', null]);
    expect(rows, isEmpty, reason: "a coach row's preview is for the position now");
  });

  testWidgets('a coach row that selects its move shows the hand under the mouse; one that does not, the arrow',
      (tester) async {
    for (final selects in [true, false]) {
      final mouse = await _withMouse(
        tester,
        CoachList(
          answer: CoachAnswer(unit: ValueUnit.winChance, lines: const [CoachLine(move: 'h8', value: 0.6)]),
          strings: _gomoku,
          look: CoachLook(onSelect: selects ? (_) {} : null),
        ),
      );
      await mouse.moveTo(tester.getCenter(find.text('h8')));
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        selects ? SystemMouseCursors.click : SystemMouseCursors.basic,
      );
      await mouse.removePointer();
    }
  });

  testWidgets("a coach row that goes away while the mouse is on it ends the game's preview", (tester) async {
    final hovered = <String?>[];
    final answer = CoachAnswer(unit: ValueUnit.winChance, lines: const [CoachLine(move: 'h8', value: 0.6)]);
    var show = true;
    late StateSetter rebuild;
    final mouse = await _withMouse(
      tester,
      StatefulBuilder(builder: (context, setState) {
        rebuild = setState;
        return show ? CoachList(answer: answer, strings: _gomoku, look: CoachLook(onHover: hovered.add)) : const SizedBox();
      }),
    );
    await mouse.moveTo(tester.getCenter(find.text('h8')));
    await tester.pump();
    expect(hovered, ['h8']);
    rebuild(() => show = false); // The player played (by key or Enter) with the mouse still there.
    await tester.pump();
    expect(hovered, ['h8', null], reason: 'the table would still show the preview of h8');
  });

  testWidgets('when a new answer puts another move under the resting mouse, the preview follows it', (tester) async {
    final hovered = <String?>[];
    var answer = CoachAnswer(unit: ValueUnit.winChance, lines: const [CoachLine(move: 'h8', value: 0.6)]);
    late StateSetter rebuild;
    final mouse = await _withMouse(
      tester,
      StatefulBuilder(builder: (context, setState) {
        rebuild = setState;
        return CoachList(answer: answer, strings: _gomoku, look: CoachLook(onHover: hovered.add));
      }),
    );
    await mouse.moveTo(tester.getCenter(find.text('h8')));
    await tester.pump();
    rebuild(() => answer = CoachAnswer(unit: ValueUnit.winChance, lines: const [CoachLine(move: 'j10', value: 0.7)]));
    await tester.pump();
    await tester.pump();
    expect(hovered, ['h8', null, 'j10']);
  });

  testWidgets('the "GTO: best" line of the feedback ends its preview when it goes away under the mouse',
      (tester) async {
    final hovered = <String?>[];
    const mark = MoveMark(grade: DecisionGrade.mistake, loss: 0.1, score: 37, played: 'a1', best: 'h8');
    var show = true;
    late StateSetter rebuild;
    final mouse = await _withMouse(
      tester,
      StatefulBuilder(builder: (context, setState) {
        rebuild = setState;
        return show
            ? MoveFeedback(mark: mark, unit: ValueUnit.winChance, strings: _gomoku, look: CoachLook(onHover: hovered.add))
            : const SizedBox();
      }),
    );
    await mouse.moveTo(tester.getCenter(find.text('${_gomoku.pickLabel}: h8')));
    await tester.pump();
    expect(hovered, ['h8']);
    rebuild(() => show = false);
    await tester.pump();
    expect(hovered, ['h8', null]);
  });

  testWidgets('a row shows its second number when it has one in another unit, beside the main one', (tester) async {
    Future<List<String>> seconds(CoachAnswer answer) async {
      await pumpShot(
        tester,
        Scaffold(body: CoachList(answer: answer, strings: BigTwoStrings.forLanguage(AppLanguage.english))),
        size: const Size(400, 300),
      );
      return [for (final w in tester.widgetList<Text>(find.byKey(const ValueKey('second number')))) w.data!];
    }

    // Big Two: points first, its win chance beside them.
    expect(
      await seconds(CoachAnswer(unit: ValueUnit.points, lines: const [CoachLine(move: '3d', value: 1.4, winChance: 0.62)])),
      ['Win 62%'],
    );
    expect(find.text('+1.4'), findsOneWidget);
    // Fight the Landlord: win chance first, its points beside it.
    expect(
      await seconds(CoachAnswer(unit: ValueUnit.winChance, lines: const [CoachLine(move: 'pass', value: 0.4, points: -0.5)])),
      ['−0.5 pts'],
    );
    // Nothing in another unit: one number.
    expect(
      await seconds(CoachAnswer(unit: ValueUnit.points, lines: const [CoachLine(move: '3d', value: 1.4, points: 1.4)])),
      isEmpty,
    );
  });

  testWidgets("every row's number keeps the right edge, tagged or not", (tester) async {
    final answer = CoachAnswer(
      unit: ValueUnit.winChance,
      lines: const [CoachLine(move: 'h8', value: 0.84, proof: 'win:5'), CoachLine(move: 'j10', value: 0.62)],
    );
    await pumpShot(
      tester,
      Scaffold(
        body: CoachList(answer: answer, strings: _gomoku, look: CoachLook(proofText: (p) => 'Wins in 5')),
      ),
      size: const Size(400, 300),
    );
    expect(tester.getRect(find.text('84%')).right, moreOrLessEquals(tester.getRect(find.text('62%')).right));
  });

  testWidgets('Think longer is greyed out, not hidden, when it cannot run', (tester) async {
    var asked = 0;
    for (final can in [false, true]) {
      await pumpShot(
        tester,
        Scaffold(
          body: CoachList(
            answer: CoachAnswer(unit: ValueUnit.winChance, lines: const [CoachLine(move: 'h8', value: 0.6)]),
            strings: _gomoku,
            canThinkLonger: can,
            onThinkLonger: () => asked++,
          ),
        ),
        size: const Size(400, 300),
      );
      expect(find.text('Think longer'), findsOneWidget);
      await tester.tap(find.text('Think longer'));
    }
    expect(asked, 1);
  });
}

/// [strings] with [tag] as its 'count' tag, so every game's pick label can
/// be checked beside the longest tag.
class _TagAll implements GameStrings {
  _TagAll(this._strings, this._tag);

  final GameStrings _strings;
  final String _tag;

  @override
  String? tagLabel(String tag) => tag == 'count' ? _tag : _strings.tagLabel(tag);

  @override
  String get pickLabel => _strings.pickLabel;

  @override
  List<GameTerm> get glossary => _strings.glossary;

  @override
  List<(String, String)> get rulesSections => _strings.rulesSections;

  @override
  List<String> samples() => _strings.samples();
}
