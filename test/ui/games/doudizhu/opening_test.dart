// The step that opens every deal of Fight the Landlord: who bids first
// (Pagat: one card is turned face up in the stack, the players draw in
// turn, and whoever draws it bids first). The cards go round the table one
// at a time from a stack in the middle, the face-up card flies out face up
// to its holder's seat and stays there with the eye, then "Ana bids first",
// and only then the auction. About two seconds at Normal, faster at Fast,
// and at Instant only the result. A deal thrown in opens again with a new
// face-up card. The review's first step shows the result, never the deal.
//
// Screenshots with --dart-define=SHOTS=<folder>: the step mid-deal (the
// face-up card in a bot's seat and in the player's hand) and its result, at
// 568x320, 900x420, 1280x800 and 390x844 in every language.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_cards.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_controller.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_opening.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_review.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_table.dart';
import 'package:pokerfection/src/ui/games/doudizhu/l10n/doudizhu_strings.dart';
import 'package:pokerfection/src/ui/kit/card_flights.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';
import 'package:pokerfection/src/ui/kit/kit_scope.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import '../../../kit/shots.dart';
import 'helpers.dart';
import 'states.dart';

const shotSizes = [Size(568, 320), Size(900, 420), Size(1280, 800), Size(390, 844)];

final stack = find.byKey(const ValueKey('deal stack'));
final words = find.byKey(const ValueKey('first bidder'));
final handFinder = find.byKey(const ValueKey('hand'));
Finder backs(int seat) => find.byKey(ValueKey('backs $seat'));
Finder marks(Finder of) => find.descendant(of: of, matching: find.byKey(const ValueKey('visible mark')));

/// The cards each seat's badge counts now.
List<int?> badges(WidgetTester tester) => [
  for (var s = 0; s < 3; s++) tester.widget<SeatBadge>(find.byKey(ValueKey('seat $s'))).cardsLeft,
];

/// The cards in the player's fan now.
int fanCards(WidgetTester tester) => tester.widget<HandFan>(handFinder).cards.length;

/// A seed whose first deal's face-up card goes to a seat [want]s.
int seedWhere(bool Function(int first) want) {
  for (var seed = 1; seed < 200; seed++) {
    final c = testController(seed: seed)..deal();
    final first = c.game.firstBidder;
    c.dispose();
    if (want(first)) return seed;
  }
  throw StateError('no such seed');
}

/// The screen shown at [size] in [language] with [c] not yet dealt, then
/// the deal started: the step runs from now (fake time).
Future<void> startOn(
  WidgetTester tester,
  LandlordController c, {
  Size size = const Size(1280, 800),
  AppLanguage language = AppLanguage.english,
}) async {
  await showGame(tester, c, size, language);
  c.newGame();
  await tester.pump();
}

/// What a card's time is at [speed].
Duration gapAt(PlaybackSpeed speed) => LandlordDealClock.cardGap * speed.factor;

void main() {
  setUpAll(loadShotFonts);

  test('the step takes about two seconds at Normal, under one at Fast, nothing at Instant', () {
    final normal = LandlordDealClock.total(PlaybackSpeed.normal.factor);
    expect(normal.inMilliseconds, inInclusiveRange(1800, 2200));
    expect(LandlordDealClock.total(PlaybackSpeed.fast.factor).inMilliseconds, inInclusiveRange(500, 800));
    expect(LandlordDealClock.total(PlaybackSpeed.instant.factor), Duration.zero);
  });

  testWidgets('at Normal the cards go round one at a time from the stack, seat after seat, and nobody bids yet', (
    tester,
  ) async {
    final seed = seedWhere((first) => first != LandlordController.you);
    final c = testController(seed: seed, speed: PlaybackSpeed.normal);
    await startOn(tester, c);
    final order = DdzDealOrder.of(c.game);
    expect(stack, findsOneWidget, reason: 'the stack is in the middle');
    expect(badges(tester), [0, 0, 0], reason: 'nothing dealt yet');
    expect(fanCards(tester), 0);
    expect(c.preparing, isTrue, reason: 'the auction waits for the step');
    expect(c.playerToMove, isFalse);
    // Card by card, before the face-up card: each seat in turn.
    final before = order.faceUpAt!;
    var elapsed = Duration.zero;
    for (final k in [1, 2, 3, 4, 7, before]) {
      final at = LandlordDealClock.cardGap * k + const Duration(milliseconds: 5);
      await tester.pump(at - elapsed);
      elapsed = at;
      expect(badges(tester), [for (var s = 0; s < 3; s++) (k - s + 2) ~/ 3], reason: '$k cards out');
      expect(fanCards(tester), (k + 2) ~/ 3);
      expect(words, findsNothing, reason: 'nobody is named before the face-up card lands');
      expect(c.preparing, isTrue);
    }
    // Every card out: the stack is gone, the first bidder named; the
    // auction still waits a moment.
    final allOut = LandlordDealClock.cardGap * 51 + const Duration(milliseconds: 5);
    await tester.pump(allOut - elapsed);
    elapsed = allOut;
    expect(stack, findsNothing);
    expect(badges(tester), [17, 17, 17]);
    expect(fanCards(tester), 17);
    expect(words, findsOneWidget);
    expect(c.preparing, isTrue, reason: 'the result holds a moment');
    // Then the auction opens, at its first bidder.
    await tester.pump(LandlordDealClock.total(1) - elapsed + const Duration(milliseconds: 10));
    expect(c.preparing, isFalse);
    expect(c.game.toAct, c.game.firstBidder);
    expect(c.game.history, isEmpty);
    await closeGame(tester, c);
  });

  testWidgets("the face-up card flies out face up to a bot's seat, lands there with the eye, and then the bot is "
      'named', (tester) async {
    final seed = seedWhere((first) => first != LandlordController.you);
    final c = testController(seed: seed, speed: PlaybackSpeed.normal);
    await startOn(tester, c);
    final holder = c.game.firstBidder, up = c.game.faceUp!;
    final order = DdzDealOrder.of(c.game);
    final at = order.faceUpAt!;
    final name = c.seatName(holder);
    // Just after it leaves the stack: in the air, face up.
    await tester.pump(LandlordDealClock.cardGap * (at + 1) + const Duration(milliseconds: 40));
    final flying = find.byKey(CardFlights.flyingKey(LandlordTable.faceUpTag(holder)));
    expect(flying, findsOneWidget);
    final card = tester.widget<GameCardView>(find.descendant(of: flying, matching: find.byType(GameCardView)));
    expect(card.face, ddzFace(up));
    expect(card.faceUp, isTrue);
    expect(marks(backs(holder)), findsNothing, reason: 'not landed yet');
    expect(words, findsNothing);
    // Landed: face up among the holder's backs with the eye; named in the
    // middle and in the headline; outlined as the one to act.
    await tester.pump(LandlordDealClock.cardGap * (LandlordDealing.landingCards + 1));
    expect(marks(backs(holder)), findsOneWidget);
    expect(find.descendant(of: words, matching: find.text('$name bids first')), findsOneWidget);
    expect(find.text('$name bids first'), findsNWidgets(2), reason: 'the middle of the felt and the headline');
    expect(tester.widget<SeatBadge>(find.byKey(ValueKey('seat $holder'))).toAct, isTrue);
    for (var s = 0; s < 3; s++) {
      if (s != holder && s != LandlordController.you) expect(marks(backs(s)), findsNothing);
    }
    expect(marks(handFinder), findsNothing);
    // The deal goes on to its end; the card stays.
    await tester.pump(LandlordDealClock.total(1));
    expect(marks(backs(holder)), findsOneWidget);
    await closeGame(tester, c);
  });

  testWidgets("the player's own face-up card comes into the fan with the eye, and the player is named", (tester) async {
    final seed = seedWhere((first) => first == LandlordController.you);
    final c = testController(seed: seed, speed: PlaybackSpeed.normal);
    await startOn(tester, c);
    final up = c.game.faceUp!;
    final at = DdzDealOrder.of(c.game).faceUpAt!;
    await tester.pump(LandlordDealClock.cardGap * at + const Duration(milliseconds: 5));
    expect(marks(handFinder), findsNothing);
    await tester.pump(LandlordDealClock.cardGap + const Duration(milliseconds: 40));
    expect(
      find.byKey(CardFlights.flyingKey(HandFan.flightTag(ddzFace(up)))),
      findsOneWidget,
      reason: 'it flies into its place in the fan',
    );
    await tester.pump(LandlordDealClock.cardGap * (LandlordDealing.landingCards + 1));
    expect(c.visibleInHand, {up});
    expect(marks(handFinder), findsOneWidget);
    expect(find.text('Player bids first'), findsNWidgets(2));
    await tester.pump(LandlordDealClock.total(1));
    expect(c.playerToMove, isTrue, reason: 'the player opens the auction');
    expect(find.text('Player bids first'), findsOneWidget, reason: 'the middle keeps it until the first bid');
    c.humanMove(yours(const DdzBid(1)));
    await tester.pump();
    expect(words, findsNothing, reason: 'the bids take the middle');
    await closeGame(tester, c);
  });

  testWidgets("nothing in the hand moves while the cards are dealt, and the buttons are greyed out", (tester) async {
    final c = testController(seed: seedWhere((first) => first == LandlordController.you), speed: PlaybackSpeed.normal);
    await startOn(tester, c);
    await tester.pump(LandlordDealClock.cardGap * 20);
    final fan = tester.widget<HandFan>(handFinder);
    expect(fan.onToggle, isNull);
    expect(fan.onReorder, isNull);
    expect(fan.onSort, isNull);
    c.toggle(c.hand.first);
    expect(c.selected, isEmpty);
    final bid = tester.widget<FilledButton>(find.byKey(const ValueKey('bid 1')));
    expect(bid.onPressed, isNull);
    expect(() => c.humanMove(yours(const DdzBid(1))), throwsStateError);
    await tester.pump(LandlordDealClock.total(1));
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('bid 1'))).onPressed, isNotNull);
    await closeGame(tester, c);
  });

  testWidgets('at Fast the same step, about a third as long', (tester) async {
    final c = testController(seed: seedWhere((first) => first != LandlordController.you), speed: PlaybackSpeed.fast);
    await startOn(tester, c);
    final gap = gapAt(PlaybackSpeed.fast);
    await tester.pump(gap * 10 + const Duration(milliseconds: 2));
    expect(badges(tester), [4, 3, 3]);
    expect(stack, findsOneWidget);
    await tester.pump(gap * 41);
    expect(badges(tester), [17, 17, 17]);
    expect(words, findsOneWidget);
    expect(c.preparing, isTrue);
    await tester.pump(LandlordDealClock.total(PlaybackSpeed.fast.factor) - gap * 51);
    expect(c.preparing, isFalse, reason: 'the auction opens after about 0.7 s');
    await closeGame(tester, c);
  });

  testWidgets('at Instant nothing moves: the cards are dealt, the face-up card in its seat, the first bidder named '
      'in the middle until the first bid', (tester) async {
    final seed = seedWhere((first) => first == LandlordController.you);
    final c = testController(seed: seed);
    await startOn(tester, c);
    expect(stack, findsNothing, reason: 'no stack: no deal to watch');
    expect(find.byType(CardFlightLayer), findsOneWidget);
    expect(badges(tester), [17, 17, 17]);
    expect(c.preparing, isFalse);
    expect(c.playerToMove, isTrue);
    expect(marks(handFinder), findsOneWidget);
    expect(find.descendant(of: words, matching: find.text('Player bids first')), findsOneWidget);
    expect(find.text('Player bids first'), findsOneWidget, reason: 'the headline is the kit\'s own: Your turn');
    c.humanMove(yours(const DdzBid(0)));
    await tester.pump();
    expect(words, findsNothing);
    await closeGame(tester, c);
  });

  testWidgets('the "?" on the words opens the face-up card in the glossary', (tester) async {
    final c = testController(seed: 3);
    await startOn(tester, c);
    await tester.tap(find.descendant(of: words, matching: find.byIcon(Icons.help_outline)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('terms help')), findsOneWidget);
    expect(find.text('Face-up card'), findsWidgets);
    expect(find.textContaining('Whoever gets it bids first'), findsOneWidget);
    await closeGame(tester, c);
  });

  testWidgets('a deal thrown in (everyone passed) opens again with a new face-up card', (tester) async {
    final (c, before) = await _thrownInAt(tester, PlaybackSpeed.normal);
    await showGame(tester, c, const Size(1280, 800), AppLanguage.english);
    expect(find.text('Everyone passed'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('again')));
    await tester.pump();
    expect(c.preparing, isTrue);
    expect(stack, findsOneWidget, reason: 'the cards go round again');
    expect(c.game.faceUp, isNot(before), reason: 'a new deal, a new face-up card');
    await tester.pump(LandlordDealClock.total(1) + const Duration(milliseconds: 10));
    expect(c.preparing, isFalse);
    expect(words, findsOneWidget);
    await closeGame(tester, c);
  });

  testWidgets("the review's first step shows the result: the face-up card with the eye, the first bidder named, "
      'no stack', (tester) async {
    final c = await finishedGame(tester);
    final record = c.record;
    await closeGame(tester, c);
    final first = record.deal['firstBidder']! as int;
    await pumpShot(
      tester,
      LandlordReview(record: record),
      size: const Size(1280, 800),
      wrap: (child) => KitScope(newJobs: Jobs.inline, lastGames: LastGames(), child: child),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(stack, findsNothing);
    final name = first == LandlordController.you ? 'Player' : record.seats[first].name;
    expect(find.descendant(of: words, matching: find.text('$name bids first')), findsOneWidget);
    expect(marks(first == LandlordController.you ? handFinder : backs(first)), findsOneWidget);
    // The next step has the first bid in the middle instead.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 500));
    expect(words, findsNothing);
    // On a sideways phone, in every language.
    for (final language in AppLanguage.values) {
      await tester.pumpWidget(const SizedBox());
      await pumpShot(
        tester,
        LandlordReview(record: record),
        size: const Size(568, 320),
        language: language,
        wrap: (child) => KitScope(newJobs: Jobs.inline, lastGames: LastGames(), child: child),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(words, findsOneWidget);
      expect(tester.takeException(), isNull);
      await shot(tester, 'review_first_step_${language.name}_568x320');
    }
  });

  testWidgets('the words in every language, under both auctions', (tester) async {
    for (final language in AppLanguage.values) {
      final s = LandlordStrings.forLanguage(language);
      for (final style in BiddingStyle.values) {
        final c = testController(seed: 3, rules: DdzRules.standard.copyWith(bidding: style));
        await startOn(tester, c, language: language);
        final name = c.seatName(c.game.firstBidder);
        expect(
          find.descendant(of: words, matching: find.text(s.firstToBid(name, style))),
          findsOneWidget,
          reason: '$language $style',
        );
        await closeGame(tester, c);
      }
    }
    expect(LandlordStrings.forLanguage(AppLanguage.english).firstToBid('Ana', BiddingStyle.points), 'Ana bids first');
    expect(LandlordStrings.forLanguage(AppLanguage.english).firstToBid('Ana', BiddingStyle.callRob), 'Ana calls first');
    expect(LandlordStrings.forLanguage(AppLanguage.spanish).firstToBid('Ana', BiddingStyle.points), 'Ana puja primero');
    expect(LandlordStrings.forLanguage(AppLanguage.chinese).firstToBid('Ana', BiddingStyle.points), 'Ana先叫');
  });

  testWidgets('mid-deal and its result fit every size in every language (screenshots with SHOTS)', (tester) async {
    for (final holderIsYou in [false, true]) {
      final seed = seedWhere((first) => (first == LandlordController.you) == holderIsYou);
      for (final language in AppLanguage.values) {
        for (final size in shotSizes) {
          final c = testController(seed: seed, speed: PlaybackSpeed.normal);
          await startOn(tester, c, size: size, language: language);
          final at = DdzDealOrder.of(c.game).faceUpAt!;
          final tag = '${holderIsYou ? 'yours' : 'bot'}_${language.name}_${size.width.round()}x${size.height.round()}';
          var elapsed = Duration.zero;
          // Frame by frame, as a screen draws it (the flights run on frames).
          Future<void> until(Duration at) async {
            const frame = Duration(milliseconds: 16);
            while (at - elapsed > frame) {
              await tester.pump(frame);
              elapsed += frame;
            }
            await tester.pump(at - elapsed);
            elapsed = at;
          }

          // The face-up card in the air.
          await until(LandlordDealClock.cardGap * (at + 1) + const Duration(milliseconds: 150));
          expect(tester.takeException(), isNull, reason: tag);
          await shot(tester, 'step_flying_$tag');
          // Landed, the deal going on, the first bidder named.
          await until(
            LandlordDealClock.cardGap * (at + LandlordDealing.landingCards + 2) + const Duration(milliseconds: 5),
          );
          expect(words, findsOneWidget, reason: tag);
          expect(tester.takeException(), isNull, reason: tag);
          await shot(tester, 'step_landed_$tag');
          // The result: every card out, the auction about to open.
          await until(LandlordDealClock.cardGap * 51 + const Duration(milliseconds: 300));
          expect(stack, findsNothing, reason: tag);
          expect(words, findsOneWidget, reason: tag);
          expect(c.preparing, isTrue, reason: tag);
          expect(tester.takeException(), isNull, reason: tag);
          await shot(tester, 'step_result_$tag');
          await closeGame(tester, c);
        }
      }
    }
  });
}

/// A deal at [speed] that everyone passed (the default rules throw it in),
/// and its face-up card.
Future<(LandlordController, int?)> _thrownInAt(WidgetTester tester, PlaybackSpeed speed) async {
  for (var s = 1; s < 200; s++) {
    var now = PlaybackSpeed.instant;
    final c = testController(seed: s, speedNow: () => now);
    c.newGame();
    for (var guard = 0; guard < 10 && c.game.phase == DdzPhase.bidding; guard++) {
      await pumpUntil(tester, () => c.isOver || c.game.phase != DdzPhase.bidding || c.playerToMove);
      if (c.isOver || c.game.phase != DdzPhase.bidding) break;
      c.humanMove(yours(const DdzBid(0)));
    }
    await pumpUntil(tester, () => c.isOver || c.game.phase != DdzPhase.bidding);
    if (c.thrownIn) {
      now = speed;
      return (c, c.game.faceUp);
    }
    c.dispose();
  }
  throw StateError('nobody threw a deal in');
}
