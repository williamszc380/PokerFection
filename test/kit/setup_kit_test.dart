import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/ui/kit/guide_kit.dart';
import 'package:pokerfection/src/ui/kit/help.dart';
import 'package:pokerfection/src/ui/kit/l10n/game_strings.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';
import 'package:pokerfection/src/ui/kit/setup_kit.dart';

import 'shots.dart';

/// A setup with a preset row, a board-size row and the level and mode rows.
class _Setup extends StatefulWidget {
  const _Setup({required this.onStart});

  final VoidCallback onStart;

  @override
  State<_Setup> createState() => _SetupState();
}

class _SetupState extends State<_Setup> {
  String? preset = 'Standard';
  int size = 15;
  bool renju = false;
  KitLevel level = KitLevel.medium;
  bool training = true;

  @override
  Widget build(BuildContext context) => SetupPage(
        title: 'Gomoku',
        onStart: widget.onStart,
        left: [
          PresetRow<String>(
            label: 'Preset',
            presets: const ['Standard', 'Renju'],
            selected: preset,
            name: (p) => p,
            onChanged: (p) => setState(() {
              preset = p;
              renju = p == 'Renju';
            }),
          ),
          SetupSection(
            label: 'Board',
            child: ChoiceRow<int>(
              values: const [15, 19],
              selected: size,
              label: (n) => '$n×$n',
              enabled: (n) => n == 15 || !renju,
              onChanged: (n) => setState(() => size = n),
            ),
          ),
          SwitchRow(label: 'Swap', value: preset == null, onChanged: (v) => setState(() => preset = v ? null : 'Standard')),
        ],
        right: [
          LevelRow(value: level, onChanged: (l) => setState(() => level = l)),
          ModeRow(training: training, onChanged: (t) => setState(() => training = t)),
        ],
      );
}

void main() {
  setUpAll(loadShotFonts);

  testWidgets('Custom is greyed out until a switch matches no preset, then it is chosen by itself', (tester) async {
    await pumpShot(tester, _Setup(onStart: () {}), size: const Size(1280, 800));
    ButtonSegment<int> segment(String label) => tester
        .widget<SegmentedButton<int>>(find.ancestor(of: find.text(label), matching: find.byType(SegmentedButton<int>)))
        .segments
        .firstWhere((s) => (s.label! as Text).data == label);
    SegmentedButton<int> row(String label) =>
        tester.widget(find.ancestor(of: find.text(label), matching: find.byType(SegmentedButton<int>)));
    expect(segment('Custom').enabled, isFalse);
    await tester.tap(find.text('Swap'));
    await tester.pump();
    expect(segment('Custom').enabled, isTrue);
    expect(row('Custom').selected, {2}, reason: 'Custom, the last segment');
  });

  testWidgets('a choice the others rule out is greyed out, not hidden, and cannot be picked', (tester) async {
    await pumpShot(tester, _Setup(onStart: () {}), size: const Size(1280, 800));
    await tester.tap(find.text('Renju'));
    await tester.pump();
    expect(find.text('19×19'), findsOneWidget);
    await tester.tap(find.text('19×19'), warnIfMissed: false);
    await tester.pump();
    final board = tester.widget<SegmentedButton<int>>(
      find.ancestor(of: find.text('19×19'), matching: find.byType(SegmentedButton<int>)),
    );
    expect(board.selected, {0}, reason: 'still 15×15');
  });

  group('a row of choices that does not fit', () {
    test('goes on the fewest lines, as even as can be, each as wide as its widest segment times its count', () {
      expect(choiceLines([50, 50, 50], 400), [
        [0, 1, 2],
      ]);
      expect(choiceLines([50, 50, 50, 50, 120], 400), [
        [0, 1, 2],
        [3, 4],
      ], reason: '5 × 120 is too wide; 3 + 2, not 4 + 1');
      expect(choiceLines([300, 50], 200), [
        [0],
        [1],
      ], reason: 'a segment wider than the row still gets a line (it is drawn a little smaller)');
    });

    // Big Two's Rules row in Spanish, the one that hid Custom at 390 wide.
    const presets = ['Estándar', 'Taiwán', 'Hong Kong', 'Pusoy Dos', 'Personalizado'];

    testWidgets('keeps every choice in sight at 390 wide, on two lines, and any of them can be picked',
        (tester) async {
      var picked = presets.first;
      await pumpShot(
        tester,
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: StatefulBuilder(
              builder: (context, setState) => ChoiceRow<String>(
                values: presets,
                selected: picked,
                label: (p) => p,
                enabled: (p) => p != 'Personalizado',
                onChanged: (p) => setState(() => picked = p),
              ),
            ),
          ),
        ),
        size: const Size(390, 844),
        language: AppLanguage.spanish,
      );
      expect(tester.takeException(), isNull);
      for (final label in presets) {
        final rect = tester.getRect(find.text(label));
        expect(rect.left >= 0 && rect.right <= 390, isTrue, reason: '"$label" is in sight');
      }
      expect(find.byType(SegmentedButton<int>), findsNWidgets(2));
      expect(tester.getRect(find.text('Personalizado')).top, greaterThan(tester.getRect(find.text('Estándar')).bottom),
          reason: 'on the second line');
      await tester.tap(find.text('Pusoy Dos'));
      await tester.pump();
      expect(picked, 'Pusoy Dos');
      final selected = [
        for (final row in tester.widgetList<SegmentedButton<int>>(find.byType(SegmentedButton<int>))) ...row.selected,
      ];
      expect(selected, [presets.indexOf('Pusoy Dos')], reason: 'one choice selected across the lines');
      await tester.tap(find.text('Personalizado'), warnIfMissed: false);
      await tester.pump();
      expect(picked, 'Pusoy Dos', reason: 'greyed out, not hidden');
      await shot(tester, 'choice_lines_es_390x844');
    });
  });

  testWidgets('segments and switches show the hand under the mouse; a greyed-out one, the arrow', (tester) async {
    await pumpShot(tester, _Setup(onStart: () {}), size: const Size(1280, 800));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    Future<MouseCursor?> cursorOn(Finder finder) async {
      await mouse.moveTo(tester.getCenter(finder));
      await tester.pump();
      return RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);
    }

    expect(await cursorOn(find.text('19×19')), SystemMouseCursors.click);
    expect(await cursorOn(find.byType(Switch)), SystemMouseCursors.click);
    expect(await cursorOn(find.text('Swap')), SystemMouseCursors.click, reason: 'the whole row toggles');
    expect(await cursorOn(find.text('Custom')), SystemMouseCursors.basic, reason: 'greyed out');
  });

  for (final language in AppLanguage.values) {
    for (final size in shotSizes) {
      final tag = shotTag(size, language);
      testWidgets('the setup page at $tag: Start stays at the bottom, nothing overflows; Enter starts', (tester) async {
        var started = 0;
        await pumpShot(tester, _Setup(onStart: () => started++), size: size, language: language);
        expect(tester.takeException(), isNull);
        final start = tester.getRect(find.byKey(const ValueKey('start')));
        expect(start.bottom, lessThanOrEqualTo(size.height));
        expect(find.byType(ListView), findsNWidgets(size.width > SetupPage.twoColumnsFrom ? 2 : 1));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(started, 1);
        await shot(tester, 'setup_$tag');
      });
    }
  }

  testWidgets('a "?" opens its terms, and the whole glossary from there', (tester) async {
    const terms = [GameTerm('Open three', 'Three in a row with both ends open.'), GameTerm('Four', 'Four in a row.')];
    await pumpShot(
      tester,
      const Scaffold(body: Center(child: TermsHelpButton(title: 'Threats', terms: [GameTerm('Four', 'Four in a row.')], all: terms))),
      size: const Size(800, 600),
    );
    await tester.tap(find.byIcon(Icons.help_outline));
    await tester.pumpAndSettle();
    expect(find.text('Four in a row.'), findsOneWidget);
    expect(find.text('Open three'), findsNothing);
    await tester.tap(find.text('Glossary'));
    await tester.pumpAndSettle();
    expect(find.byType(GameGlossaryScreen), findsOneWidget);
    expect(find.text('Open three'), findsOneWidget);
  });

  testWidgets('a guide shows its sections and tables', (tester) async {
    await pumpShot(
      tester,
      GuidePage(
        title: 'Rules',
        sections: const [('The goal', 'Five in a row wins.')],
        children: [
          GuideTable(columns: const ['Hand', '2', '3'], rows: const [
            [Text('16'), Text('S'), Text('S')],
          ]),
        ],
      ),
      size: const Size(568, 320),
    );
    expect(find.text('The goal'), findsOneWidget);
    expect(find.text('16'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(KitStrings.forLanguage(AppLanguage.english).level, 'Level');
  });
}
