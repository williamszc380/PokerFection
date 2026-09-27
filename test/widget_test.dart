import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/main.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/game/table_session.dart';
import 'package:pokerfection/src/gto/preflop/preflop_equity.dart';
import 'package:pokerfection/src/gto/gto_solutions.dart';
import 'package:pokerfection/src/ui/table_controller.dart';
import 'package:pokerfection/src/ui/charts_screen.dart';
import 'package:pokerfection/src/ui/table_screen.dart';
import 'package:pokerfection/src/ui/widgets/logo.dart';

/// Makes the user's decision if it's their turn: check or call by default
/// (ticked), or fold when [call] is false and folding is allowed. Returns
/// true if it acted.
Future<bool> actIfAsked(WidgetTester tester, {required bool call}) async {
  final play = find.byKey(const ValueKey('play'));
  if (play.evaluate().isEmpty) return false;
  // A greyed-out fold (checking is free) ignores the tap.
  if (!call) await tester.tap(find.byKey(const ValueKey('choice fold')));
  await tester.tap(play);
  return true;
}

void setScreen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Solves synchronously, with few iterations, so tests stay fast.
GtoSolutions testSolutions() => GtoSolutions(
      iterations: 30,
      postflopIterations: 5,
      inBackground: false,
      loadEquity: () async =>
          PreflopEquity.fromBytes(ByteData.sublistView(File('assets/preflop_equity.bin').readAsBytesSync())),
    );

void main() {
  testWidgets('main menu, settings and the game setup', (tester) async {
    setScreen(tester, const Size(800, 1400));
    await tester.pumpWidget(PokerFectionApp(settings: AppSettings()));
    expect(find.byType(LogoMark), findsOneWidget);
    expect(find.text('English'), findsOneWidget, reason: 'the language button');
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Sound'), findsOneWidget);
    expect(find.text('Card Back'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    expect(find.text('GTO Training'), findsOneWidget);
    expect(find.text('Rotate'), findsOneWidget);
    await tester.tap(find.text('Customize Opponents'));
    await tester.pumpAndSettle();
    expect(find.text('Player'), findsOneWidget, reason: 'one row per player');
    expect(find.text('100 BB'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Min-Raise'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('1 BB (House Rule)'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Bet Sizes'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('2.5×'), findsOneWidget);
    expect(find.text('0.5× pot'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Start'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('preflop charts: pick a table, a position and a spot, tap a hand', (tester) async {
    setScreen(tester, const Size(1280, 720));
    await tester.pumpWidget(PokerFectionApp(settings: AppSettings()));
    await tester.tap(find.text('Preflop Charts'));
    await tester.pumpAndSettle();
    expect(find.byType(ChartGrid), findsOneWidget);
    expect(find.text('AA'), findsOneWidget);
    // Heads-up, from the big blind: first in isn't possible, so it's against the button's open.
    await tester.tap(find.widgetWithText(ChoiceChip, '2'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'BB'));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Open')).onSelected, isNull,
        reason: 'greyed out');
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'vs Open')).selected, isTrue);
    expect(find.text('Opener'), findsOneWidget);
    await tester.tap(find.text('AKo'));
    await tester.pumpAndSettle();
    expect(find.text('AKo'), findsNWidgets(2), reason: 'on the grid, and above its numbers');
  });

  testWidgets('Guess the GTO: enter a mix, see the score, keep playing', (tester) async {
    setScreen(tester, const Size(1280, 900));
    await tester.pumpWidget(MaterialApp(
      home: TableScreen(
        config: TableConfig.quick(playerCount: 3, stackBb: 20, guessGto: true),
        speed: PlaybackSpeed.instant,
        solutions: testSolutions(),
      ),
    ));
    var scored = 0;
    for (var hand = 0; hand < 5; hand++) {
      for (var step = 0; step < 40; step++) {
        await tester.pumpAndSettle();
        if (find.text('Next Hand').evaluate().isNotEmpty) break;
        final play = find.byKey(const ValueKey('play'));
        // Percentages to set: a decision with a GTO answer.
        if (play.evaluate().isNotEmpty && find.byType(Slider).evaluate().isNotEmpty) {
          await tester.tap(play);
          await tester.pumpAndSettle();
          expect(find.textContaining('Score '), findsOneWidget);
          expect(find.text('GTO'), findsWidgets);
          scored++;
          await tester.tap(find.byKey(const ValueKey('continue')));
          continue;
        }
        await actIfAsked(tester, call: true);
      }
      expect(find.text('Next Hand'), findsOneWidget, reason: 'hand $hand did not finish');
      await tester.tap(find.text('Next Hand'));
    }
    expect(scored, greaterThan(0));
    expect(find.text('Avg'), findsOneWidget);
  });

  for (final size in const [Size(1280, 800), Size(400, 860)]) {
    testWidgets('plays several hands with instant animations at $size', (tester) async {
      setScreen(tester, size);
      await tester.pumpWidget(MaterialApp(
        home: TableScreen(config: TableConfig.quick(playerCount: 8), speed: PlaybackSpeed.instant),
      ));
      for (var hand = 0; hand < 6; hand++) {
        for (var step = 0; step < 30; step++) {
          await tester.pumpAndSettle();
          if (find.text('Next Hand').evaluate().isNotEmpty) break;
          await actIfAsked(tester, call: hand.isEven);
        }
        expect(find.text('Next Hand'), findsOneWidget, reason: 'hand $hand did not finish');
        await tester.tap(find.text('Next Hand'));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('plays a hand with normal animations', (tester) async {
    setScreen(tester, const Size(1280, 800));
    await tester.pumpWidget(MaterialApp(
      home: TableScreen(config: TableConfig.quick(playerCount: 6, ante: 10)),
    ));
    var finished = false;
    for (var tick = 0; tick < 1200 && !finished; tick++) {
      await tester.pump(const Duration(milliseconds: 100));
      finished = find.text('Next Hand').evaluate().isNotEmpty;
      if (!finished && await actIfAsked(tester, call: true)) {
        await tester.pump();
      }
    }
    expect(finished, isTrue);
    // Leave the table and let any remaining timers run out.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
