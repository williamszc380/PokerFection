import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/main.dart';
import 'package:pokerfection/src/app/drills.dart';
import 'package:pokerfection/src/game/table_session.dart';
import 'package:pokerfection/src/gto/gto_solutions.dart';
import 'package:pokerfection/src/gto/preflop/preflop_equity.dart';
import 'package:pokerfection/src/ui/glossary.dart';
import 'package:pokerfection/src/ui/home_screen.dart';
import 'package:pokerfection/src/ui/table_controller.dart';
import 'package:pokerfection/src/ui/table_screen.dart';

import 'memory_store.dart';

/// Solves synchronously, with few iterations, so tests stay fast.
GtoSolutions _solutions() => GtoSolutions(
      iterations: 30,
      postflopIterations: 5,
      inBackground: false,
      loadEquity: () async =>
          PreflopEquity.fromBytes(ByteData.sublistView(File('assets/preflop_equity.bin').readAsBytesSync())),
    );

void main() {
  // Drills are off in every game for now (see the "Drills are off for now"
  // notes): their code stays, but nothing leads to them.
  testWidgets(
      'drills are off: only the settings are read and saved, no Drills anywhere, and a Mistake in '
      'training saves nothing', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final stores = <String, MemoryStore>{};
    final settings = await loadSaved((name) => stores[name] = MemoryStore({}, name));
    expect(stores.keys, ['settings'], reason: 'no drills file');
    await tester.pumpWidget(PokerFectionApp(settings: settings));
    expect(find.byType(DrillsScope), findsNothing);

    // Neither Home nor Hold'em's menu has Drills.
    expect(find.textContaining('Drills'), findsNothing);
    await tester.tap(find.text("Hold'em"));
    await tester.pumpAndSettle();
    expect(find.textContaining('Drills'), findsNothing);

    // Training: fold every hand until a Mistake (or a Blunder) shows; the
    // table never says it was saved.
    Navigator.of(tester.element(find.text('Play'))).push(MaterialPageRoute<void>(
      builder: (_) => TableScreen(
        config: TableConfig.quick(playerCount: 2, stackBb: 20, guessGto: true),
        speed: PlaybackSpeed.instant,
        solutions: _solutions(),
      ),
    ));
    var mistakes = 0;
    for (var step = 0; step < 400 && mistakes == 0; step++) {
      await tester.pumpAndSettle();
      expect(find.textContaining('drills'), findsNothing);
      final cont = find.byKey(const ValueKey('continue'));
      if (cont.evaluate().isNotEmpty) {
        if (find.text('Mistake').evaluate().isNotEmpty || find.text('Blunder').evaluate().isNotEmpty) mistakes++;
        await tester.tap(cont);
      } else if (find.text('Next Hand').evaluate().isNotEmpty) {
        await tester.tap(find.text('Next Hand'));
      } else if (find.byKey(const ValueKey('quick fold')).evaluate().isNotEmpty) {
        final fold = find.byKey(const ValueKey('quick fold'));
        final canFold = tester.widget<FilledButton>(fold).onPressed != null;
        await tester.tap(canFold ? fold : find.byKey(const ValueKey('quick call')));
      }
    }
    expect(mistakes, greaterThan(0), reason: 'no Mistake in 400 steps');
    await tester.pumpAndSettle();
    expect(find.textContaining('drills'), findsNothing);

    // ☰ has no Saved Spots, and the glossary no Drills.
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('Saved Spots'), findsNothing);
    await tester.tap(find.text('Glossary'));
    await tester.pumpAndSettle();
    expect(find.byType(GlossaryScreen), findsOneWidget);
    expect(find.text('Free Play'), findsOneWidget, reason: 'the Modes section is on screen');
    expect(find.text('Drills'), findsNothing);
    expect(glossaryTerms(), isNot(contains(GlossaryTerm.drills)));

    expect(stores.keys, ['settings'], reason: 'nothing else was saved');
    expect(stores['settings']!.saved.keys.where((key) => key.contains('drill')), isEmpty);
    expect(find.byType(HomeScreen, skipOffstage: false), findsOneWidget);
    // Leave the table and let any remaining timers run out.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
