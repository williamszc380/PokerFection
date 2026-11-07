// Big Two's setup: the table and the rules, pre-filled from the last game,
// with options the other choices rule out greyed out (never hidden), and
// Start handing the game its choices.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_controller.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_screen.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_setup.dart';
import 'package:pokerfection/src/ui/games/big_two/l10n/big_two_strings.dart';
import 'package:pokerfection/src/ui/kit/kit_scope.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';

import '../../../kit/shots.dart';
import 'big_two_test_util.dart';

final en = BigTwoStrings.forLanguage(AppLanguage.english);
final kit = KitStrings.forLanguage(AppLanguage.english);

/// The setup at [size], starting from [initial]; Start keeps the choice in [started].
Future<List<BigTwoSetup>> pumpSetup(
  WidgetTester tester, {
  BigTwoSetup? initial,
  Size size = const Size(1280, 800),
  AppLanguage language = AppLanguage.english,
  Widget Function(Widget child)? wrap,
}) async {
  final started = <BigTwoSetup>[];
  await pumpShot(
    tester,
    BigTwoSetupScreen(initial: initial ?? BigTwoSetup.from(null), onStart: (_, setup) => started.add(setup)),
    size: size,
    language: language,
    wrap: wrap,
  );
  await tester.pump();
  return started;
}

/// The segment labelled [label] in the choice row keyed [row].
Finder segment(String row, String label) => find.descendant(of: find.byKey(ValueKey(row)), matching: find.text(label));

/// Whether the segment labelled [label] in the choice row [row] can be chosen.
bool segmentEnabled(WidgetTester tester, String row, String label) {
  final buttons = tester.widget<SegmentedButton<int>>(
    find.descendant(of: find.byKey(ValueKey(row)), matching: find.byType(SegmentedButton<int>)),
  );
  return buttons.segments.firstWhere((s) => (s.label! as Text).data == label).enabled;
}

bool switchOn(WidgetTester tester, String key) =>
    tester.widget<Switch>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Switch))).value;

bool switchEnabled(WidgetTester tester, String key) =>
    tester.widget<Switch>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Switch))).onChanged !=
    null;

Future<void> tapSwitch(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.tap(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Switch)));
  await tester.pump();
}

Future<void> tapText(WidgetTester tester, Finder finder) async {
  // A column longer than the screen is built as it scrolls: back up to it.
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      -100,
      scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  setUpAll(loadShotFonts);

  group('fits every size and language', () {
    for (final size in bigTwoSizes) {
      for (final language in AppLanguage.values) {
        testWidgets(shotTag(size, language), (tester) async {
          await pumpSetup(tester, size: size, language: language);
          expect(find.byKey(const ValueKey('start')), findsOneWidget);
          if (size.width >= 1000) {
            // A PC shows every choice without scrolling.
            final start = tester.getRect(find.byKey(const ValueKey('start')));
            for (final key in ['double bombs', 'top two']) {
              expect(tester.getRect(find.byKey(ValueKey(key))).bottom, lessThanOrEqualTo(start.top), reason: key);
            }
          }
        });
      }
    }
  });

  testWidgets('it starts on the standard game for 2 players: 17 each, a Medium bot, Training', (tester) async {
    final started = await pumpSetup(tester);
    expect(segmentEnabled(tester, 'cards each', '17'), isTrue);
    expect(segmentEnabled(tester, 'cards each', '13'), isTrue, reason: 'two players may deal 13, 17 or 21');
    expect(find.text(kit.custom), findsOneWidget, reason: 'Custom is there, greyed out');
    await tester.tap(find.byKey(const ValueKey('start')));
    await tester.pump();
    final setup = started.single;
    expect(setup.rules, BigTwoRules.standard(players: 2));
    expect((setup.rules.players, setup.rules.cardsEach), (2, 17));
    expect(setup.levels, [KitLevel.medium]);
    expect(setup.training, isTrue);
    expect(setup.toggles, isEmpty, reason: 'no coach toggle yet: the coach starts hidden');
  });

  testWidgets('four players still deal 13 each only', (tester) async {
    await pumpSetup(tester);
    await tapText(tester, segment('players', '4'));
    expect(segmentEnabled(tester, 'cards each', '17'), isFalse, reason: 'four players: 13 each only, greyed out');
  });

  testWidgets(
    'the presets wrap onto another line rather than scroll: Custom is greyed out until the rules match none',
    (tester) async {
      await pumpSetup(tester, size: const Size(390, 844), language: AppLanguage.spanish);
      final es = BigTwoStrings.forLanguage(AppLanguage.spanish);
      final custom = KitStrings.forLanguage(AppLanguage.spanish).custom;
      Finder inPresets(String label) =>
          find.descendant(of: find.byKey(const ValueKey('presets')), matching: find.text(label));
      // The kit's row: each line of choices is a segmented bar.
      SegmentedButton<int> bar(String label) => tester.widget<SegmentedButton<int>>(
        find.ancestor(of: inPresets(label), matching: find.byType(SegmentedButton<int>)),
      );
      ButtonSegment<int> segment(String label) =>
          bar(label).segments.firstWhere((s) => (s.label! as Text).data == label);
      bool selected(String label) => bar(label).selected.contains(segment(label).value);
      // A phone lists the choices in one column, built as it scrolls.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('presets')),
        100,
        scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first,
      );
      for (final label in [...BigTwoPreset.values.map(es.preset), custom]) {
        await tester.ensureVisible(inPresets(label));
        final rect = tester.getRect(inPresets(label));
        expect(rect.right, lessThanOrEqualTo(390), reason: '"$label" shows');
      }
      expect(
        find.descendant(of: find.byKey(const ValueKey('presets')), matching: find.byType(SegmentedButton<int>)),
        findsNWidgets(2),
        reason: 'too wide for one line at 390 in Spanish: two',
      );
      expect(
        find.ancestor(
          of: inPresets(custom),
          matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.right),
        ),
        findsNothing,
        reason: 'no sideways scrolling',
      );
      expect(selected(es.preset(BigTwoPreset.standard)), isTrue);
      expect(segment(custom).enabled, isFalse, reason: 'greyed out: the rules are a preset');
      // On a phone the switches are further down the page.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('lockout')),
        100,
        scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first,
      );
      await tapSwitch(tester, 'lockout');
      await tester.scrollUntilVisible(
        inPresets(custom),
        -100,
        scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first,
      );
      expect(selected(custom), isTrue, reason: 'the rules match no preset now');
      expect(segment(custom).enabled, isTrue, reason: 'picked, so not greyed out');
      expect(selected(es.preset(BigTwoPreset.standard)), isFalse);
    },
  );

  testWidgets('a preset sets the rules; changing a switch after it makes them Custom', (tester) async {
    final started = await pumpSetup(tester);
    await tapText(tester, find.text(en.preset(BigTwoPreset.taiwan)).first);
    expect(switchOn(tester, 'bombs'), isTrue);
    expect(switchOn(tester, 'same type'), isTrue);
    await tapSwitch(tester, 'lockout');
    await tester.tap(find.byKey(const ValueKey('start')));
    await tester.pump();
    final rules = started.single.rules;
    expect(rules, BigTwoRules.taiwan(players: 2).copyWith(passLockout: true));
  });

  testWidgets('three players deal 17 each; two players choose 13, 17 or 21; the dragon needs 13', (tester) async {
    final started = await pumpSetup(tester);
    await tapText(tester, segment('players', '3'));
    expect(segmentEnabled(tester, 'cards each', '17'), isTrue);
    expect(segmentEnabled(tester, 'cards each', '13'), isFalse);
    expect(switchEnabled(tester, 'dragon'), isFalse, reason: 'no dragon in a 17-card hand: greyed out');
    await tapText(tester, segment('players', '2'));
    for (final n in ['13', '17', '21']) {
      expect(segmentEnabled(tester, 'cards each', n), isTrue, reason: n);
    }
    await tapText(tester, segment('cards each', '13'));
    expect(switchEnabled(tester, 'dragon'), isTrue);
    await tester.tap(find.byKey(const ValueKey('start')));
    await tester.pump();
    expect((started.single.rules.players, started.single.rules.cardsEach), (2, 13));
    expect(started.single.levels, hasLength(1));
  });

  testWidgets('Pusoy Dos scoring greys out the two doublings', (tester) async {
    await pumpSetup(tester);
    expect(switchEnabled(tester, 'double twos'), isTrue);
    await tapText(tester, find.text(en.scoringName(BigTwoScoring.pusoyDos)).last);
    expect(switchEnabled(tester, 'double twos'), isFalse);
    expect(switchEnabled(tester, 'double bombs'), isFalse);
    expect(find.byKey(const ValueKey('double twos')), findsOneWidget, reason: 'greyed out, not hidden');
  });

  testWidgets('Customize seats gives each bot its own level', (tester) async {
    final started = await pumpSetup(tester);
    await tapText(tester, segment('players', '4'));
    await tapSwitch(tester, 'customize seats');
    for (final name in ['Ana', 'Ben', 'Kai']) {
      expect(find.text(name), findsOneWidget);
    }
    final start = tester.getRect(find.byKey(const ValueKey('start')));
    expect(
      tester.getRect(find.byKey(const ValueKey('double bombs'))).bottom,
      lessThanOrEqualTo(start.top),
      reason: 'on a PC everything still fits without scrolling',
    );
    await tapText(
      tester,
      find.descendant(of: find.byKey(const ValueKey('seat 2')), matching: find.text(kit.kitLevel(KitLevel.hard))),
    );
    await tapText(tester, segment('players', '3'));
    expect(find.text('Kai'), findsNothing, reason: 'one level per bot');
    await tester.tap(find.byKey(const ValueKey('start')));
    await tester.pump();
    expect(started.single.levels, [KitLevel.medium, KitLevel.hard]);
    expect(started.single.seatLevels, isNotNull);
  });

  testWidgets('Free Play is chosen here, for the whole game', (tester) async {
    final started = await pumpSetup(tester);
    await tapText(tester, find.text('Free Play'));
    await tester.tap(find.byKey(const ValueKey('start')));
    await tester.pump();
    expect(started.single.training, isFalse);
  });

  testWidgets('without a choice given, it starts from the last game: rules, bots, mode and toggles', (tester) async {
    final store = LastGames();
    final last = seededGame(
      rules: BigTwoRules.hongKong(players: 3),
      training: false,
      toggles: const {'sort': 'suit', 'counter': true},
      lastGames: store,
    );
    await last.newGame();
    last.dispose();
    await store.flush();
    final started = <BigTwoSetup>[];
    await pumpShot(
      tester,
      BigTwoSetupScreen(onStart: (_, setup) => started.add(setup)),
      size: const Size(1280, 800),
      wrap: (child) => KitScope(newJobs: Jobs.inline, lastGames: store, child: child),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start')));
    await tester.pump();
    final setup = started.single;
    expect(setup.rules, BigTwoRules.hongKong(players: 3));
    expect(setup.training, isFalse);
    expect(setup.levels, [KitLevel.easy, KitLevel.easy]);
    expect(setup.toggles, {'sort': 'suit', 'counter': true});
  });

  testWidgets('Start opens the game with the choices', (tester) async {
    await pumpShot(
      tester,
      BigTwoSetupScreen(initial: BigTwoSetup(rules: BigTwoRules.pusoyDos(players: 3), training: false)),
      size: const Size(1280, 800),
      wrap: (child) => KitScope(newJobs: Jobs.inline, lastGames: LastGames(), child: child),
    );
    await tester.tap(find.byKey(const ValueKey('start')));
    await tester.pumpAndSettle();
    final screen = tester.widget<BigTwoScreen>(find.byType(BigTwoScreen));
    expect(screen.setup.rules, BigTwoRules.pusoyDos(players: 3));
    expect(find.byKey(const ValueKey('seat 2')), findsOneWidget);
    expect(find.byKey(const ValueKey('seat 3')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    // A bot may be in its thinking pause (the deal is random): let it end.
    await tester.pump(const Duration(seconds: 1));
  });
}
