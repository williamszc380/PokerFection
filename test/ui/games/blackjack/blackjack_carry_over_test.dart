// What a new game takes from the last one, and leaving a game early:
// - a game started from the setup keeps the last game's screen toggles
//   (☰ Count and the coach chip), as the other games' setups do;
// - a new shoe deals at once: nothing waits for the strategy chart but the
//   coach, and leaving while it is still being made is not an error;
// - the setup uses a PC screen's room, the feedback names even money,
//   and the strategy guide's rule chips answer the mouse with a hand cursor;
// - a table without a hole card can take only the original bets, chosen in
//   the setup and in the strategy guide.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/blackjack/app/blackjack_jobs.dart';
import 'package:pokerfection/src/games/blackjack/app/blackjack_record.dart';
import 'package:pokerfection/src/games/blackjack/blackjack.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/ui/games/blackjack/blackjack_controller.dart';
import 'package:pokerfection/src/ui/games/blackjack/blackjack_guides.dart';
import 'package:pokerfection/src/ui/games/blackjack/blackjack_screen.dart';
import 'package:pokerfection/src/ui/games/blackjack/blackjack_setup.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/ui/games/blackjack/l10n/blackjack_strings.dart';
import 'package:pokerfection/src/ui/kit/game_sounds.dart';
import 'package:pokerfection/src/ui/kit/kit_scope.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';
import 'package:pokerfection/src/ui/kit/move_feedback.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import '../../../kit/fakes.dart';
import '../../../kit/shots.dart';
import 'blackjack_scenes.dart';

void main() {
  setUpAll(loadShotFonts);
  setUp(() => GameSounds.output = (_) {});

  testWidgets('a game started from the setup keeps the last game\'s Count and coach chip', (tester) async {
    final store = LastGames();
    store.save(
      newBlackjackRecord(
        rules: const BlackjackRules(),
        seed: 1,
        playerName: 'Player',
        dealerName: 'Dealer',
        extra: {...const BlackjackSettings().extra, 'count': true, 'coach': false},
      ),
    );
    await pumpShot(tester, const BlackjackSetup(), size: const Size(1280, 800), wrap: kitWrap(store));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('start')));
    await settleGame(tester);
    final game = gameOf(tester);
    expect(game.showCount, isTrue, reason: '☰ Count was on in the last game');
    expect(game.coachVisible, isFalse, reason: 'the coach chip was off in the last game');
    await closeGame(tester);
  });

  testWidgets('a new shoe deals at once while the chart is made: Deal and the decisions are not greyed out, the '
      'thin bar runs, and the coach answers once the chart is in', (tester) async {
    final backend = ManualBackend({for (final job in blackjackJobs) job.name: job});
    await pumpShot(
      tester,
      BlackjackScreen(settings: coachOn, random: FixedSeed(seed16v10)),
      size: const Size(1280, 800),
      wrap: (child) => KitScope(newJobs: () => Jobs.using(backend), lastGames: LastGames(), child: child),
    );
    await tester.pump();
    final game = gameOf(tester);
    expect(game.preparing, isTrue);
    expect(backend.on(JobLane.coach)?.name, 'blackjack.chart');
    expect(find.byType(LinearProgressIndicator), findsWidgets, reason: 'a notice that the coach is working');
    final deal = find.byKey(const ValueKey('deal'));
    expect(tester.widget<FilledButton>(deal).onPressed, isNotNull, reason: 'Deal works at once');
    await tester.tap(deal);
    await settleGame(tester);
    expect(game.record.moves, [dealMove]);
    expect(game.betweenRounds, isFalse, reason: 'a hard 16 against a ten: a decision');
    final stand = find.descendant(
      of: find.byKey(const ValueKey('action stand')),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    expect(tester.widget<ButtonStyleButton>(stand).onPressed, isNotNull, reason: 'the decision is not held');
    expect(game.coach, isNull, reason: 'its coach job waits for the chart');
    backend.answer(backend.on(JobLane.coach)!);
    await tester.pump();
    await tester.pump();
    final coach = backend.on(JobLane.coach)!;
    expect(coach.name, 'blackjack.coach');
    expect(coach.request, contains('"chart":'));
    backend.answer(coach);
    await tester.pump();
    await tester.pump();
    expect(game.coach, isNotNull);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await closeGame(tester);
  });

  test('leaving while the chart is being made reports no error', () async {
    final reported = <FlutterErrorDetails>[];
    final before = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = before);
    final backend = ManualBackend({for (final job in blackjackJobs) job.name: job});
    final game = BlackjackController(
      settings: const BlackjackSettings(),
      jobs: Jobs.using(backend),
      lastGames: LastGames(),
      playerName: 'Player',
      dealerName: 'Dealer',
      speed: () => PlaybackSpeed.instant,
    );
    final starting = game.newGame();
    await settle();
    expect(game.preparing, isTrue);
    expect(game.playerToMove, isTrue, reason: 'the chart holds nothing: Deal works at once');
    game.humanMove(dealMove);
    game.dispose(); // the player taps Back during the chart's second
    await starting;
    await settle();
    expect(reported.map((d) => d.exception), isEmpty);
  });

  for (final language in AppLanguage.values) {
    testWidgets('on a PC every table preset (and Custom) is in view, not cut off by its column (${language.name})', (
      tester,
    ) async {
      const size = Size(1280, 800);
      await pumpShot(tester, const BlackjackSetup(), size: size, language: language, wrap: kitWrap(LastGames()));
      await tester.pump();
      final b = BlackjackStrings.forLanguage(language);
      final k = KitStrings.forLanguage(language);
      for (final name in [for (final p in BlackjackPreset.values) b.preset(p), k.custom]) {
        final rect = tester.getRect(find.text(name));
        expect(rect.right <= size.width / 2, isTrue, reason: '$name at $rect is cut off by its column');
      }
    });

    testWidgets('on a PC the setup fits without scrolling, only small screens scroll (${language.name})', (
      tester,
    ) async {
      const size = Size(1280, 800);
      await pumpShot(tester, const BlackjackSetup(), size: size, language: language, wrap: kitWrap(LastGames()));
      await tester.pump();
      for (final element in find.byType(Scrollable).evaluate()) {
        final position = ((element as StatefulElement).state as ScrollableState).position;
        if (position.axis == Axis.vertical) expect(position.maxScrollExtent, 0, reason: 'the PC setup scrolls');
      }
    });
  }

  testWidgets('Custom lights by itself once a switch matches no preset, and is greyed out before', (tester) async {
    await pumpShot(tester, const BlackjackSetup(), size: const Size(1280, 800), wrap: kitWrap(LastGames()));
    await tester.pump();
    // The presets are the kit's PresetRow: segments, Custom the last one.
    SegmentedButton<int> line(String label) =>
        tester.widget(find.ancestor(of: find.text(label), matching: find.byType(SegmentedButton<int>)));
    ButtonSegment<int> segment(String label) =>
        line(label).segments.firstWhere((s) => (s.label! as Text).data == label);
    bool selected(String label) => line(label).selected.contains(segment(label).value);
    expect(selected('Custom'), isFalse);
    expect(segment('Custom').enabled, isFalse, reason: 'greyed out while a preset matches');
    expect(selected('Standard'), isTrue);
    await tester.tap(find.text('85%'));
    await tester.pump();
    expect(selected('Custom'), isTrue);
    expect(selected('Standard'), isFalse);
  });

  test('New shoe keeps the toggles on screen, not the ones the setup brought', () async {
    final game = BlackjackController(
      settings: const BlackjackSettings(training: false, toggles: {'count': true, 'coach': false}),
      jobs: Jobs.inline(),
      lastGames: LastGames(),
      playerName: 'Player',
      dealerName: 'Dealer',
      speed: () => PlaybackSpeed.instant,
    );
    addTearDown(game.dispose);
    await game.newGame();
    expect(game.showCount, isTrue);
    expect(game.coachVisible, isFalse);
    game.showCount = false;
    game.coachVisible = true;
    await game.newGame();
    expect(game.showCount, isFalse);
    expect(game.coachVisible, isTrue);
  });

  testWidgets('taking even money is called "Even money" in the feedback, as on its button', (tester) async {
    await pumpGame(tester, size: const Size(1280, 800), seed: seedEvenMoney);
    await play(tester, dealMove);
    expect(gameOf(tester).coachResult!.evenMoney, isTrue);
    await tester.tap(
      find.descendant(of: find.byKey(const ValueKey('offer insurance')), matching: find.text('Even money')),
    );
    await settleGame(tester);
    expect(gameOf(tester).record.moves, [dealMove, move0(BlackjackAction.insurance)]);
    expect(find.descendant(of: find.byType(MoveFeedback), matching: find.text('Insurance')), findsNothing);
    expect(find.descendant(of: find.byType(MoveFeedback), matching: find.text('Even money')), findsOneWidget);
    await closeGame(tester);
  });

  testWidgets('the strategy guide\'s rule chips show the hand under the mouse', (tester) async {
    await pumpShot(
      tester,
      const BlackjackStrategyGuide(rules: BlackjackRules()),
      size: const Size(1280, 800),
      wrap: kitWrap(LastGames()),
    );
    await settleGame(tester);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(1, 1));
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byKey(const ValueKey('h17'))));
    await tester.pumpAndSettle();
    expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.click);
    await closeGame(tester);
  });

  testWidgets('without a hole card the setup can take only the original bets; with one the choice is greyed out', (
    tester,
  ) async {
    final store = LastGames();
    await pumpShot(tester, const BlackjackSetup(), size: const Size(1280, 800), wrap: kitWrap(store));
    await tester.pump();
    SegmentedButton<int> choice() => tester.widget<SegmentedButton<int>>(
      find.descendant(of: find.byKey(const ValueKey('no hole card loss')), matching: find.byType(SegmentedButton<int>)),
    );
    expect(choice().segments.map((s) => s.enabled), everyElement(isFalse), reason: 'the hole card is on');
    await tester.tap(find.text('Hole card'));
    await tester.pump();
    expect(choice().segments.map((s) => s.enabled), everyElement(isTrue));
    await tester.tap(find.text('Original bet'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('start')));
    await settleGame(tester);
    expect(gameOf(tester).rules.holeCard, isFalse);
    expect(gameOf(tester).rules.noHoleCardLoss, NoHoleCardLoss.originalBetsOnly);
    expect(gameOf(tester).rules.losesOriginalOnly, isTrue);
    await closeGame(tester);
  });

  testWidgets('the strategy guide offers the no-hole-card rule, greyed out while the table has a hole card', (
    tester,
  ) async {
    await pumpShot(
      tester,
      const BlackjackStrategyGuide(rules: BlackjackRules()),
      size: const Size(1280, 800),
      wrap: kitWrap(LastGames()),
    );
    await settleGame(tester);
    PopupMenuButton<NoHoleCardLoss> pick() => tester.widget<PopupMenuButton<NoHoleCardLoss>>(
      find.descendant(
        of: find.byKey(const ValueKey('no hole card loss')),
        matching: find.byType(PopupMenuButton<NoHoleCardLoss>),
      ),
    );
    expect(pick().enabled, isFalse);
    await tester.tap(find.byKey(const ValueKey('hole card')));
    await settleGame(tester);
    expect(pick().enabled, isTrue);
    await closeGame(tester);
  });
}
