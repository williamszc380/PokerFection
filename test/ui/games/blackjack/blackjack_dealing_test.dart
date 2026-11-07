// The cards on the felt move as a dealer deals them, and the coach waits
// to be asked for:
// - a fresh game starts with the coach hidden (the move is still graded);
//   the chip turns it on and the next shoe keeps it;
// - a deal sends the cards from the shoe one by one, round the table, the
//   hole card face down; the buttons wait for the last card;
// - a Hit's card flies in; a Split's second card slides over to its hand;
// - on a Stand the hole card turns over before the dealer draws, the panel
//   says "Dealer…" meanwhile, and the result waits for the dealer's last
//   card; the totals and ☰ Count only count cards that have landed;
// - at Instant nothing flies and the hole card is just face up.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/blackjack/app/blackjack_record.dart';
import 'package:pokerfection/src/games/blackjack/blackjack.dart';
import 'package:pokerfection/src/ui/games/blackjack/blackjack_dealing.dart';
import 'package:pokerfection/src/ui/games/blackjack/blackjack_setup.dart';
import 'package:pokerfection/src/ui/games/blackjack/blackjack_table.dart';
import 'package:pokerfection/src/ui/games/blackjack/l10n/blackjack_strings.dart';
import 'package:pokerfection/src/ui/kit/card_flights.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';
import 'package:pokerfection/src/ui/kit/coach_panel.dart';
import 'package:pokerfection/src/ui/kit/game_scaffold.dart';
import 'package:pokerfection/src/ui/kit/game_sounds.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';
import 'package:pokerfection/src/ui/kit/move_feedback.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import '../../../kit/shots.dart';
import 'blackjack_scenes.dart';

/// The card drawn at flight place [tag] (none: not dealt on the felt yet).
Finder cardAt(Object tag) => find.byWidgetPredicate((w) => w is GameCardView && w.flightTag == tag);

/// A card in the air on its way to [tag].
Finder flyingTo(Object tag) => find.byKey(CardFlights.flyingKey(tag));

/// Whether the button keyed [key] can be pressed.
bool pressable(WidgetTester tester, String key) => tester
    .widget<ButtonStyleButton>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        matchRoot: true,
      ),
    )
    .enabled;

String status(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('status'))).data!;

void main() {
  setUpAll(loadShotFonts);
  setUp(() => GameSounds.output = (_) {});

  group('the coach waits to be asked for', () {
    testWidgets('a fresh game hides it, still grades the move, and the chip shows it', (tester) async {
      final game = await pumpGame(tester, size: const Size(1280, 800));
      expect(game.coachVisible, isFalse, reason: 'hidden until the player asks');
      expect(tester.widget<FilterChip>(find.byKey(const ValueKey('coach chip'))).selected, isFalse);
      await play(tester, dealMove);
      expect(find.byType(CoachList), findsNothing);
      expect(game.coach, isNotNull, reason: 'the answer is still worked out: it grades the move');
      await play(tester, move0(BlackjackAction.hit));
      expect(game.record.marks.whereType<Object>(), isNotEmpty, reason: 'graded with the coach hidden');
      expect(find.byType(MoveFeedback), findsOneWidget, reason: 'the grade after a move stays');
      await tester.tap(find.byKey(const ValueKey('coach chip')));
      await settleGame(tester);
      expect(game.coachVisible, isTrue);
      expect(game.record.extra['coach'], isTrue, reason: 'kept, for the next shoe');
      await closeGame(tester);
    });

    testWidgets('the setup with no last game starts it hidden; once on, the next game keeps it', (tester) async {
      final store = LastGames();
      await pumpShot(tester, const BlackjackSetup(), size: const Size(1280, 800), wrap: kitWrap(store));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('start')));
      await settleGame(tester);
      final first = gameOf(tester);
      expect(first.coachVisible, isFalse);
      first.coachVisible = true;
      await settleGame(tester);
      await closeGame(tester);

      await pumpShot(tester, const BlackjackSetup(), size: const Size(1280, 800), wrap: kitWrap(store));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('start')));
      await settleGame(tester);
      expect(gameOf(tester).coachVisible, isTrue, reason: 'the chip carries over as the other toggles do');
      await closeGame(tester);
    });

    testWidgets('☰ Count still shows the count with the coach hidden', (tester) async {
      final game = await pumpGame(tester, size: const Size(1280, 800));
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Count'));
      await tester.pumpAndSettle();
      await play(tester, dealMove);
      expect(game.showCount, isTrue);
      expect(find.byKey(const ValueKey('count')), findsOneWidget);
      expect(find.byType(CoachList), findsNothing);
      await closeGame(tester);
    });
  });

  group('the deal', () {
    testWidgets('cards leave the shoe one by one, round the table, the hole card face down', (tester) async {
      final game = await pumpGame(tester, size: const Size(1280, 800));
      expect(find.byKey(const ValueKey('shoe')), findsOneWidget, reason: 'the shoe sits in the corner');
      game.humanMove(dealMove);
      await tester.pump();
      await tester.pump();
      // The player's first card is on its way; nothing else is on the felt.
      expect(flyingTo(handCardTag(1, 0, 0)), findsOneWidget);
      expect(cardAt(handCardTag(1, 0, 1)), findsNothing);
      expect(cardAt(dealerCardTag(1, 0)), findsNothing);
      expect(game.dealing.busy, isTrue);
      expect(pressable(tester, 'action hit'), isFalse, reason: 'the buttons wait for the cards');
      expect(status(tester), 'Dealer…', reason: 'never "Your turn" over greyed buttons');
      // Then the dealer's upcard, the player's second card, the hole card,
      // each leaving ${BlackjackDealing.gap} after the one before.
      await frames(tester, 270);
      expect(flyingTo(dealerCardTag(1, 0)), findsOneWidget);
      await frames(tester, 230);
      expect(flyingTo(handCardTag(1, 0, 1)), findsOneWidget);
      await frames(tester, 230);
      expect(flyingTo(dealerCardTag(1, 1)), findsOneWidget);
      await settleGame(tester);
      expect(game.dealing.active, isFalse);
      expect(tester.widget<GameCardView>(cardAt(dealerCardTag(1, 1))).faceUp, isFalse, reason: 'the hole card');
      expect(tester.widget<GameCardView>(cardAt(dealerCardTag(1, 0))).faceUp, isTrue);
      expect(pressable(tester, 'action hit'), isTrue);
      expect(status(tester), KitStrings.forLanguage(AppLanguage.english).yourTurn, reason: 'once the cards are down');
      expect(tester.takeException(), isNull);
      await closeGame(tester);
    });

    testWidgets('a hand\'s total counts only the cards that have landed', (tester) async {
      final game = await pumpGame(tester, size: const Size(1280, 800));
      game.humanMove(dealMove);
      await tester.pump();
      await tester.pump();
      final first = game.play.round!.seats[playerSeat].hands.single.cards.first;
      final b = find.descendant(of: find.byKey(const ValueKey('hand 0 total')), matching: find.byType(Text));
      expect(b, findsNothing, reason: 'no card down yet, no total');
      await frames(tester, 400);
      final shown = tester.widget<Text>(b).data!;
      expect(shown, isNot(contains('16')), reason: 'one card down: $first');
      await settleGame(tester);
      expect(tester.widget<Text>(b).data, '16');
      await closeGame(tester);
    });

    testWidgets('a Hit\'s card flies from the shoe to the hand', (tester) async {
      final game = await pumpGame(tester, size: const Size(1280, 800));
      await play(tester, dealMove);
      game.humanMove(move0(BlackjackAction.hit));
      await tester.pump();
      await tester.pump();
      expect(flyingTo(handCardTag(1, 0, 2)), findsOneWidget);
      expect(
        tester.getCenter(flyingTo(handCardTag(1, 0, 2))).dx,
        greaterThan(tester.getCenter(cardAt(handCardTag(1, 0, 0))).dx),
        reason: 'it starts at the shoe, on the right',
      );
      await settleGame(tester);
      expect(flyingTo(handCardTag(1, 0, 2)), findsNothing);
      expect(cardAt(handCardTag(1, 0, 2)), findsOneWidget);
      await closeGame(tester);
    });

    testWidgets('a Split\'s second card slides over to its own hand, then the first hand gets a card', (tester) async {
      final game = await pumpGame(tester, size: const Size(1280, 800), seed: seedEights);
      await play(tester, dealMove);
      final from = tester.getCenter(cardAt(handCardTag(1, 0, 1)));
      game.humanMove(move0(BlackjackAction.split));
      await tester.pump();
      await tester.pump();
      final moving = flyingTo(handCardTag(1, 1, 0));
      expect(moving, findsOneWidget);
      expect((tester.getCenter(moving) - from).distance, lessThan(30), reason: 'it leaves from where it was');
      expect(cardAt(handCardTag(1, 0, 1)), findsNothing, reason: 'the first hand\'s new card is still to come');
      await frames(tester, 270);
      expect(flyingTo(handCardTag(1, 0, 1)), findsOneWidget);
      await settleGame(tester);
      expect(cardAt(handCardTag(1, 1, 0)), findsOneWidget);
      expect(cardAt(handCardTag(1, 0, 1)), findsOneWidget);
      await closeGame(tester);
    });
  });

  group('the dealer\'s turn', () {
    testWidgets('the hole card turns over before the dealer draws; the result waits for the last card', (tester) async {
      final game = await pumpGame(tester, size: const Size(1280, 800));
      final k = KitStrings.forLanguage(AppLanguage.english);
      await play(tester, dealMove);
      game.humanMove(move0(BlackjackAction.stand));
      await tester.pump();
      final round = game.play.round!;
      expect(round.isOver, isTrue, reason: 'the engine has played the round out');
      expect(game.dealing.dealerPlaying, isTrue);
      expect(status(tester), 'Dealer…', reason: 'the dealer plays');
      expect(find.byKey(const ValueKey('round result')), findsNothing, reason: 'not before the dealer\'s cards');
      expect(pressable(tester, 'deal'), isFalse, reason: 'Deal waits for the dealer');
      await frames(tester, 100);
      // The hole card turning over: its view says face up now.
      expect(tester.widget<GameCardView>(cardAt(dealerCardTag(1, 1))).faceUp, isTrue);
      if (round.dealerCards.length > 2) {
        expect(cardAt(dealerCardTag(1, 2)), findsNothing, reason: 'the dealer draws after turning it over');
        await frames(tester, 400);
        expect(flyingTo(dealerCardTag(1, 2)), findsOneWidget);
      }
      await settleGame(tester);
      expect(game.dealing.active, isFalse);
      expect(find.byKey(const ValueKey('round result')), findsOneWidget);
      expect(status(tester), roundResultText(BlackjackStrings.forLanguage(AppLanguage.english), round));
      expect(status(tester), isNot(k.yourTurn));
      expect(pressable(tester, 'deal'), isTrue);
      await closeGame(tester);
    });

    testWidgets('☰ Count leaves out the cards still on their way', (tester) async {
      final game = await pumpGame(tester, size: const Size(1280, 800));
      game.showCount = true;
      game.humanMove(dealMove);
      await tester.pump();
      await tester.pump();
      final b = BlackjackStrings.forLanguage(AppLanguage.english);
      final countText = find.descendant(of: find.byKey(const ValueKey('count')), matching: find.byType(Text));
      String running() => tester.widget<Text>(countText.first).data!;
      expect(running(), b.runningCount(BlackjackStrings.signed(0)), reason: 'no card has landed yet');
      await settleGame(tester);
      final round = game.play.round!;
      final seen = [...round.seats[playerSeat].hands.single.cards, round.dealerUpcard];
      expect(running(), b.runningCount(BlackjackStrings.signed(HiLoCount.of(seen, 300).running)));
      await closeGame(tester);
    });
  });

  testWidgets('at Instant nothing flies and every card shows at once', (tester) async {
    final game = await pumpGame(tester, size: const Size(1280, 800));
    AppSettings.of(tester.element(find.byType(GameScaffold))).speed = PlaybackSpeed.instant;
    game.humanMove(dealMove);
    await tester.pump();
    await tester.pump();
    expect(game.dealing.active, isFalse);
    expect(game.flights.flying, isFalse);
    expect(cardAt(dealerCardTag(1, 1)), findsOneWidget);
    expect(cardAt(handCardTag(1, 0, 1)), findsOneWidget);
    expect(pressable(tester, 'action hit'), isTrue);
    await closeGame(tester);
  });

  group('the plan of a move', () {
    BlackjackPlay shoe(int seed, [BlackjackRules rules = const BlackjackRules()]) =>
        BlackjackPlay(rules, shoeSeed: seed);

    List<Object> targets(DealPlan plan) => [
      for (final step in plan.steps)
        switch (step) {
          DealCard() => step.to,
          TurnHoleCard() => 'turn',
        },
    ];

    test('a deal: player, upcard, player, hole card face down, from the shoe', () {
      final play = shoe(seed16v10);
      final before = FeltBefore.of(play);
      play.apply(dealMove);
      final plan = DealPlan.of(before, play);
      expect(plan.dealing, isTrue);
      expect(targets(plan), [handCardTag(1, 0, 0), dealerCardTag(1, 0), handCardTag(1, 0, 1), dealerCardTag(1, 1)]);
      expect([for (final s in plan.steps.cast<DealCard>()) s.faceUp], [true, true, true, false]);
      expect(plan.steps.cast<DealCard>().every((s) => s.from == CardFlights.shoeTag), isTrue);
      expect(plan.hands, [0]);
      expect(plan.dealer, 0);
    });

    test('a Stand that ends the round: the hole card turns, then the dealer\'s cards', () {
      final play = shoe(seed16v10)..apply(dealMove);
      final before = FeltBefore.of(play);
      play.apply(move0(BlackjackAction.stand));
      final plan = DealPlan.of(before, play);
      expect(plan.dealerPlays, isTrue);
      final dealer = play.round!.dealerCards.length;
      expect(targets(plan), ['turn', for (var i = 2; i < dealer; i++) dealerCardTag(1, i)]);
    });

    test('a Split: the second card moves over, then the first hand\'s new card', () {
      final play = shoe(seedEights)..apply(dealMove);
      final before = FeltBefore.of(play);
      play.apply(move0(BlackjackAction.split));
      final plan = DealPlan.of(before, play, split: true);
      expect(plan.hands, [1, 0]);
      final steps = plan.steps.cast<DealCard>();
      expect(steps.first.from, handCardTag(1, 0, 1));
      expect(steps.first.to, handCardTag(1, 1, 0));
      expect(steps[1].to, handCardTag(1, 0, 1));
      expect(steps[1].from, CardFlights.shoeTag);
    });

    test('without a hole card, the dealer\'s second card comes with the dealer\'s turn, face up', () {
      final rules = BlackjackRules.preset(BlackjackPreset.european);
      final play = shoe(seed16v10, rules);
      final before = FeltBefore.of(play);
      play.apply(dealMove);
      expect(targets(DealPlan.of(before, play)), [handCardTag(1, 0, 0), dealerCardTag(1, 0), handCardTag(1, 0, 1)]);
      final standing = FeltBefore.of(play);
      play.apply(move0(BlackjackAction.stand));
      final plan = DealPlan.of(standing, play);
      expect(plan.steps.whereType<TurnHoleCard>(), isEmpty);
      expect(plan.steps.cast<DealCard>().first.to, dealerCardTag(1, 1));
      expect(plan.steps.cast<DealCard>().every((s) => s.faceUp), isTrue);
    });
  });
}
