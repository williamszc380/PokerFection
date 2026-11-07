// The menu's Last game for blackjack: the most recent shoe replayed step by
// step, with the grades from the game and the coach on demand, at the three
// sizes in the three languages. Screenshots with --dart-define=SHOTS=<folder>.
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/blackjack/app/blackjack_grading.dart';
import 'package:pokerfection/src/games/blackjack/app/blackjack_record.dart';
import 'package:pokerfection/src/games/blackjack/blackjack.dart';
import 'package:pokerfection/src/kit/game_record.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/ui/games/blackjack/blackjack_controller.dart';
import 'package:pokerfection/src/ui/games/blackjack/blackjack_review.dart';
import 'package:pokerfection/src/ui/games/blackjack/blackjack_table.dart';
import 'package:pokerfection/src/ui/games/blackjack/l10n/blackjack_strings.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';
import 'package:pokerfection/src/ui/kit/coach_panel.dart';
import 'package:pokerfection/src/ui/kit/game_sounds.dart';
import 'package:pokerfection/src/ui/kit/kit_scope.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';
import 'package:pokerfection/src/ui/kit/move_feedback.dart';

import '../../../kit/shots.dart';
import 'blackjack_scenes.dart';

/// Plays a shoe on the game screen ([moves] does the playing) in
/// [language], leaves, and gives back the shoe as saved.
Future<GameRecord> playShoe(
  WidgetTester tester, {
  AppLanguage language = AppLanguage.english,
  BlackjackSettings settings = const BlackjackSettings(),
  int seed = seed16v10,
  required Future<void> Function() moves,
}) async {
  final store = LastGames();
  await pumpGame(tester, size: const Size(1280, 800), language: language, settings: settings, seed: seed, store: store);
  await moves();
  await closeGame(tester);
  return (await loadLastShoe(store))!;
}

/// A Training shoe: 16 against a ten, stood on, then four more of the
/// chart's plays (or deals).
Future<GameRecord> trainingShoe(WidgetTester tester, {AppLanguage language = AppLanguage.english}) => playShoe(
  tester,
  language: language,
  moves: () async {
    await play(tester, dealMove);
    await play(tester, move0(BlackjackAction.stand));
    await playChart(tester, 4);
  },
);

/// Shows the review of [record].
Future<void> pumpReview(
  WidgetTester tester,
  GameRecord record, {
  Size size = const Size(1280, 800),
  AppLanguage language = AppLanguage.english,
}) async {
  await pumpShot(
    tester,
    BlackjackReview(record: record),
    size: size,
    language: language,
    wrap: kitWrap(LastGames()),
  );
  await tester.pump();
}

/// Steps forward [count] times with ▶.
Future<void> stepOn(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.tap(find.byKey(const ValueKey('step next')));
    await settleGame(tester);
  }
}

String headline(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('review headline'))).data!;

bool holeCardDown(WidgetTester tester) => tester.widgetList<GameCardView>(feltCards).any((c) => !c.faceUp);

Finder inCoach(String text) => find.descendant(of: find.byType(CoachList), matching: find.text(text));

Future<void> toggleCoach(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('coach chip')));
  await settleGame(tester);
}

/// The cards dealt on the felt (each has its place's flight tag), not the
/// backs of the shoe in the corner.
Finder get feltCards => find.byWidgetPredicate((w) => w is GameCardView && w.flightTag != null);

void main() {
  setUpAll(loadShotFonts);
  setUp(() => GameSounds.output = (_) {});

  final b = BlackjackStrings.forLanguage(AppLanguage.english);
  final k = KitStrings.forLanguage(AppLanguage.english);

  testWidgets('it opens at the first step: the empty felt before the first deal, "Move 1", the move Deal', (
    tester,
  ) async {
    final record = await trainingShoe(tester);
    expect(record.moves.take(2), [dealMove, move0(BlackjackAction.stand)]);
    await pumpReview(tester, record);
    expect(tester.takeException(), isNull);
    expect(headline(tester), k.moveNumber(1), reason: 'no round yet; one player, so no seat named');
    expect(find.byKey(const ValueKey('review move')), findsOneWidget, reason: 'a deal is not graded');
    expect(tester.widget<Text>(find.byKey(const ValueKey('review move'))).data, k.deal);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('step back'))).onPressed, isNull);
    expect(feltCards, findsNothing);
    await closeGame(tester);
  });

  testWidgets('a decision step: the cards as the player saw them, the hole card down, and the grade from the game; '
      'All cards turns the hole card up', (tester) async {
    final record = await trainingShoe(tester);
    expect(record.marks[1], isNotNull, reason: 'Training grades every decision');
    await pumpReview(tester, record);
    await stepOn(tester, 1);
    expect(headline(tester), '${b.round(1)} · ${k.moveNumber(2)}');
    expect(find.byKey(const ValueKey('review mark')), findsOneWidget);
    expect(feltCards, findsNWidgets(4));
    expect(holeCardDown(tester), isTrue);
    await tester.tap(find.byKey(const ValueKey('all cards')));
    await settleGame(tester);
    expect(holeCardDown(tester), isFalse);
    expect(tester.widget<BlackjackTableView>(find.byType(BlackjackTableView)).showHoleCard, isTrue);
    await closeGame(tester);
  });

  testWidgets('the coach runs only once its chip is on: a decision gets every action valued, the chart\'s play '
      'tagged Basic strategy; a deal gets no coach', (tester) async {
    final record = await trainingShoe(tester);
    await pumpReview(tester, record);
    await stepOn(tester, 1);
    expect(find.byType(CoachList), findsNothing, reason: 'off until asked for');
    await toggleCoach(tester);
    expect(find.byType(CoachList), findsOneWidget);
    expect(inCoach(b.pickLabel), findsOneWidget);
    expect(inCoach(b.action(BlackjackAction.hit)), findsOneWidget);
    expect(inCoach(b.action(BlackjackAction.stand)), findsOneWidget);
    // Back to the deal: nothing to coach.
    await tester.tap(find.byKey(const ValueKey('step back')));
    await settleGame(tester);
    expect(find.byType(CoachList), findsNothing);
    // Off again: the list goes.
    await stepOn(tester, 1);
    expect(find.byType(CoachList), findsOneWidget);
    await toggleCoach(tester);
    expect(find.byType(CoachList), findsNothing);
    await closeGame(tester);
  });

  testWidgets('keys: → and ← step, End jumps to the last step (the net of a shoe left early), Home back', (
    tester,
  ) async {
    final record = await trainingShoe(tester);
    expect(record.result, isNull, reason: 'left before the cut card');
    await pumpReview(tester, record);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settleGame(tester);
    expect(headline(tester), '${b.round(1)} · ${k.moveNumber(2)}');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await settleGame(tester);
    expect(headline(tester), k.moveNumber(1));
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await settleGame(tester);
    expect(headline(tester), k.net(betsText(BlackjackPlay.replay(record).net)));
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('step next'))).onPressed, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await settleGame(tester);
    expect(headline(tester), k.moveNumber(1));
    await closeGame(tester);
  });

  testWidgets('a shoe played to its end: the last step says who came out ahead, and by how much', (tester) async {
    final record = await playShoe(
      tester,
      settings: BlackjackSettings(rules: BlackjackRules.preset(BlackjackPreset.singleDeck)),
      seed: seedSeen,
      moves: () => playToEnd(tester),
    );
    expect(record.result, isNotNull);
    final net = BlackjackPlay.replay(record).net;
    final outcome = net > 0
        ? k.youWin
        : net < 0
        ? k.wins(b.dealerSeat)
        : k.draw;
    await pumpReview(tester, record);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await settleGame(tester);
    expect(headline(tester), '$outcome · ${k.net(betsText(net))}');
    await closeGame(tester);
  });

  testWidgets('Free Play: no grades, and the coach still answers', (tester) async {
    final record = await playShoe(
      tester,
      settings: const BlackjackSettings(training: false),
      moves: () async {
        await play(tester, dealMove);
        await play(tester, move0(BlackjackAction.stand));
      },
    );
    expect(record.marks.every((m) => m == null), isTrue);
    await pumpReview(tester, record);
    await stepOn(tester, 1);
    expect(find.byKey(const ValueKey('review mark')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const ValueKey('review move'))).data, b.action(BlackjackAction.stand));
    await toggleCoach(tester);
    expect(inCoach(b.pickLabel), findsOneWidget);
    await closeGame(tester);
  });

  testWidgets('Cards seen: the count shows on the felt, and the coach tags the count\'s play', (tester) async {
    final record = await playShoe(
      tester,
      settings: BlackjackSettings(rules: BlackjackRules.preset(BlackjackPreset.singleDeck), coachMode: CoachMode.seen),
      seed: seedSeen,
      moves: () => playChart(tester, 4),
    );
    await pumpReview(tester, record);
    expect(find.byKey(const ValueKey('count')), findsOneWidget);
    await stepOn(tester, 3);
    await toggleCoach(tester);
    expect(inCoach(b.tagLabel('count')!), findsOneWidget);
    await closeGame(tester);
  });

  testWidgets('the strategy chart is made once, when the coach is first switched on, however many steps it answers', (
    tester,
  ) async {
    final record = await trainingShoe(tester);
    expect(record.extra.keys, isNot(contains('chart')), reason: 'the game keeps nothing beyond itself');
    final chartJob = CountingChartJob();
    await pumpShot(
      tester,
      BlackjackReview(record: record),
      size: const Size(1280, 800),
      wrap: (child) => KitScope(
        newJobs: () => Jobs.inline(extra: {chartJob.name: chartJob}),
        lastGames: LastGames(),
        child: child,
      ),
    );
    await tester.pump();
    await stepOn(tester, 1);
    expect(chartJob.runs, 0, reason: 'not before the coach is wanted');
    await toggleCoach(tester);
    expect(inCoach(b.pickLabel), findsOneWidget);
    await stepOn(tester, 3);
    await toggleCoach(tester);
    await toggleCoach(tester);
    expect(chartJob.runs, 1);
    await closeGame(tester);
  });

  testWidgets('taking even money is named "Even money" in the review too, by the offer that move answered', (
    tester,
  ) async {
    final record = await playShoe(
      tester,
      seed: seedEvenMoney,
      moves: () async {
        await play(tester, dealMove);
        await play(tester, move0(BlackjackAction.insurance));
      },
    );
    await pumpReview(tester, record);
    await stepOn(tester, 1);
    expect(find.descendant(of: find.byType(MoveFeedback), matching: find.text(b.evenMoney)), findsOneWidget);
    await closeGame(tester);
  });

  for (final language in AppLanguage.values) {
    for (final size in gameSizes) {
      final tag = shotTag(size, language);
      testWidgets('review $tag: first step, a graded decision with the coach and all cards, the end; nothing '
          'overflows and the slider stays on screen', (tester) async {
        final record = await playShoe(
          tester,
          language: language,
          settings: BlackjackSettings(
            rules: BlackjackRules.preset(BlackjackPreset.singleDeck),
            coachMode: CoachMode.seen,
          ),
          seed: seedSeen,
          moves: () => playChart(tester, 8),
        );
        await pumpReview(tester, record, size: size, language: language);
        void fits() {
          expect(tester.takeException(), isNull);
          final slider = tester.getRect(find.byKey(const ValueKey('step slider')));
          expect(slider.bottom <= size.height && slider.right <= size.width, isTrue, reason: 'slider at $slider');
        }

        await snap(tester, 'review_$tag');
        fits();
        await stepOn(tester, 3);
        await toggleCoach(tester);
        await tester.tap(find.byKey(const ValueKey('all cards')));
        await settleGame(tester);
        await snap(tester, 'review_coach_$tag');
        fits();
        expect(find.byType(CoachList), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        await settleGame(tester);
        await snap(tester, 'review_end_$tag');
        fits();
        await closeGame(tester);
      });
    }
  }
}
