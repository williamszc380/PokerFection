// The cards everyone has seen in Fight the Landlord, on the solo table and
// in the review: the card dealt face up, which decided who bids first
// (Pagat), and the kitty in the landlord's hand once taken (when the rules
// show it). They show face up in their holder's seat, among the backs,
// with the kit's eye on the corner; "Everyone can see this card" under
// the mouse or a long-pressing finger. On the player's own hand they carry
// the eye too. Once the deal is over, every hand is face up: no eye.
//
// Screenshots with --dart-define=SHOTS=<folder>: the face-up card in a
// bot's seat and in the player's hand, the label, a bot landlord with the
// shown kitty and the face-up card (four faces), at every size and in
// every language.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_cards.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_controller.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_review.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';
import 'package:pokerfection/src/ui/kit/kit_scope.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';

import '../../../kit/shots.dart';
import 'states.dart';

const sizes = [Size(568, 320), Size(512, 320), Size(900, 420), Size(1280, 800), Size(390, 844)];

const _mark = ValueKey('visible mark');
Finder backs(int seat) => find.byKey(ValueKey('backs $seat'));
final handFinder = find.byKey(const ValueKey('hand'));

/// The cards drawn with the eye under [of], by face.
List<CardFace?> marked(WidgetTester tester, Finder of) => [
  for (final card in tester.widgetList<GameCardView>(find.descendant(of: of, matching: find.byType(GameCardView))))
    if (card.visibleToAll && card.faceUp) card.face,
];

/// The eyes drawn under [of].
Finder marks(Finder of) => find.descendant(of: of, matching: find.byKey(_mark));

/// The marked card drawn in [seat]'s backs.
Finder markedSeatCard(int seat) => find.descendant(
  of: backs(seat),
  matching: find.byWidgetPredicate((w) => w is GameCardView && w.visibleToAll && w.faceUp),
);

/// The player's turn in the auction of a deal whose face-up card [want]s'
/// seat got (seeds tried in turn).
Future<LandlordController> auctionWith(WidgetTester tester, bool Function(int first) want) async {
  for (var s = 1; s < 120; s += 7) {
    final c = await gameAt(tester, DdzPhase.bidding, seed: s);
    if (want(c.game.firstBidder)) return c;
    c.dispose();
  }
  throw StateError('no such deal');
}

/// The player's turn in play, a bot the landlord, [test] holding.
Future<LandlordController> playWith(
  WidgetTester tester,
  bool Function(DdzGame g) test, {
  DdzRules rules = DdzRules.standard,
}) async {
  for (var s = 1; s < 400; s += 3) {
    final c = await gameAt(tester, DdzPhase.playing, seed: s, rules: rules, training: false);
    final lord = c.game.landlord;
    if (lord != null && lord != LandlordController.you && test(c.game)) return c;
    c.dispose();
  }
  throw StateError('no such deal');
}

/// Shows [c]'s game afresh (the screen's state is [c]'s, not the last
/// controller's).
Future<void> showFresh(WidgetTester tester, LandlordController c, Size size, AppLanguage language) async {
  await tester.pumpWidget(const SizedBox());
  await showGame(tester, c, size, language);
}

Future<TestGesture> mouseAt(WidgetTester tester, Offset at) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: at);
  addTearDown(mouse.removePointer);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return mouse;
}

void main() {
  setUpAll(loadShotFonts);

  group('the face-up card on the solo table', () {
    testWidgets("a bot dealt it shows it face up after its backs, with the eye; nobody else's seat shows it", (
      tester,
    ) async {
      final c = await auctionWith(tester, (first) => first != LandlordController.you);
      final holder = c.game.firstBidder, other = 3 - holder;
      for (final size in sizes) {
        await showGame(tester, c, size, AppLanguage.english);
        expect(marked(tester, backs(holder)), [ddzFace(c.game.faceUp!)], reason: '$size');
        expect(marks(backs(holder)), findsOneWidget);
        expect(tester.widget<SeatHand>(backs(holder)).count, 17, reason: 'the badge still counts every card');
        expect(marked(tester, backs(other)), isEmpty);
        expect(marks(handFinder), findsNothing);
        expect(tester.takeException(), isNull);
      }
      await closeGame(tester, c);
    });

    testWidgets("the player's own face-up card carries the eye in the fan, and no bot's seat shows it", (tester) async {
      final c = await auctionWith(tester, (first) => first == LandlordController.you);
      await showGame(tester, c, const Size(1280, 800), AppLanguage.english);
      final up = c.game.faceUp!;
      expect(c.visibleInHand, {up});
      expect(tester.widget<HandFan>(handFinder).visibleToAll, {c.hand.indexOf(up)});
      expect(marks(find.byKey(ValueKey('${ddzFace(up)}#1'))), findsOneWidget);
      for (final seat in [1, 2]) {
        expect(marked(tester, backs(seat)), isEmpty);
      }
      await closeGame(tester, c);
    });

    testWidgets('under the mouse it says "Everyone can see this card" (Todos ven esta carta, 所有人都能看到这张牌), '
        'on a bot\'s seat and in the hand; a long press says so on touch', (tester) async {
      final bot = await auctionWith(tester, (first) => first != LandlordController.you);
      for (final language in AppLanguage.values) {
        final label = KitStrings.forLanguage(language).visibleToAll;
        await showGame(tester, bot, const Size(1280, 800), language);
        expect(find.text(label), findsNothing);
        final mouse = await mouseAt(tester, tester.getCenter(markedSeatCard(bot.game.firstBidder)));
        expect(find.text(label), findsOneWidget, reason: '$language');
        expect(find.byType(VisibleCardLabel), findsOneWidget);
        await mouse.moveTo(const Offset(640, 400));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text(label), findsNothing);
        await mouse.removePointer();
      }
      // A long press on the phone.
      await showGame(tester, bot, const Size(568, 320), AppLanguage.english);
      final finger = await tester.startGesture(tester.getCenter(markedSeatCard(bot.game.firstBidder)));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Everyone can see this card'), findsOneWidget);
      await finger.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Everyone can see this card'), findsNothing);
      await closeGame(tester, bot);

      final mine = await auctionWith(tester, (first) => first == LandlordController.you);
      await showGame(tester, mine, const Size(1280, 800), AppLanguage.spanish);
      await mouseAt(tester, onCard(tester, mine.game.faceUp!));
      expect(find.text('Todos ven esta carta'), findsOneWidget);
      await closeGame(tester, mine);
    });

    testWidgets('a bot landlord shows the kitty cards it still holds with the eye; with the kitty hidden, none', (
      tester,
    ) async {
      final shown = await playWith(tester, (g) => g.kitty.any(g.hands[g.landlord!].contains));
      final lord = shown.game.landlord!;
      await showGame(tester, shown, const Size(900, 420), AppLanguage.english);
      final held = [
        for (final id in shown.game.kitty)
          if (shown.game.hands[lord].contains(id)) ddzFace(id),
      ];
      expect(marked(tester, backs(lord)), containsAll(held));
      expect(marked(tester, backs(lord)), unorderedEquals([for (final id in shown.game.visibleIn(lord)) ddzFace(id)]));
      await closeGame(tester, shown);

      final hidden = await playWith(
        tester,
        (g) => g.kitty.any(g.hands[g.landlord!].contains),
        rules: DdzRules.standard.copyWith(kittyShown: false),
      );
      final hiddenLord = hidden.game.landlord!;
      await showGame(tester, hidden, const Size(900, 420), AppLanguage.english);
      final faces = marked(tester, backs(hiddenLord));
      for (final id in hidden.game.kitty) {
        expect(faces, isNot(contains(ddzFace(id))), reason: 'a hidden kitty is not seen by everyone');
      }
      expect(faces, [for (final id in hidden.game.visibleIn(hiddenLord)) ddzFace(id)]);
      await closeGame(tester, hidden);
    });

    testWidgets("Training's Show cards: a bot's faces carry the eye where they are", (tester) async {
      final c = await auctionWith(tester, (first) => first != LandlordController.you);
      c.showOpponentCards = true;
      await showGame(tester, c, const Size(1280, 800), AppLanguage.english);
      final holder = c.game.firstBidder;
      final hand = find.byKey(ValueKey('hand $holder'));
      expect(hand, findsOneWidget);
      expect(marked(tester, hand), [ddzFace(c.game.faceUp!)]);
      expect(marks(hand), findsOneWidget);
      expect(tester.takeException(), isNull);
      await closeGame(tester, c);
    });

    testWidgets('once the deal is over no card carries the eye: every hand is face up', (tester) async {
      final c = await finishedGame(tester);
      await showGame(tester, c, const Size(1280, 800), AppLanguage.english);
      expect(find.byKey(_mark), findsNothing);
      expect(c.visibleInHand, isEmpty);
      await closeGame(tester, c);
    });
  });

  group('the face-up card in the review', () {
    testWidgets('the first step shows it with the eye in its holder\'s seat or hand; the deal\'s end shows none', (
      tester,
    ) async {
      final c = await finishedGame(tester, seed: 5);
      final record = c.record;
      c.dispose();
      await tester.pump(const Duration(seconds: 1));
      final first = record.deal['firstBidder']! as int;
      final up = record.deal['faceUp']! as int;
      await pumpShot(
        tester,
        LandlordReview(record: record),
        size: const Size(1280, 800),
        wrap: (child) => KitScope(newJobs: Jobs.inline, lastGames: LastGames(), child: child),
      );
      await tester.pump(const Duration(milliseconds: 500));
      final where = first == LandlordController.you ? handFinder : backs(first);
      expect(marked(tester, where), [ddzFace(up)]);
      await shot(tester, 'review_first_step');
      // The last step: the deal is over.
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(_mark), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('every size and language', () {
    testWidgets('the face-up card in a bot\'s seat, in the player\'s hand, the label, and a bot landlord holding the '
        'shown kitty and the face-up card: nothing overflows (screenshots)', (tester) async {
      final bot = await auctionWith(tester, (first) => first != LandlordController.you);
      final mine = await auctionWith(tester, (first) => first == LandlordController.you);
      final four = await playWith(tester, (g) => g.landlord == g.firstBidder && g.visibleIn(g.landlord!).length == 4);
      for (final language in AppLanguage.values) {
        for (final size in sizes) {
          final tag = shotTag(size, language);
          await showFresh(tester, bot, size, language);
          expect(tester.takeException(), isNull, reason: 'bot $tag');
          expect(marks(backs(bot.game.firstBidder)), findsOneWidget, reason: tag);
          await shot(tester, 'solo_bot_faceup_$tag');
          final mouse = await mouseAt(tester, tester.getCenter(markedSeatCard(bot.game.firstBidder)));
          expect(find.byType(VisibleCardLabel), findsOneWidget, reason: tag);
          await shot(tester, 'solo_hover_$tag');
          await mouse.removePointer();

          await showFresh(tester, mine, size, language);
          expect(tester.takeException(), isNull, reason: 'own $tag');
          expect(marks(handFinder), findsOneWidget, reason: tag);
          await shot(tester, 'solo_own_faceup_$tag');

          await showFresh(tester, four, size, language);
          expect(tester.takeException(), isNull, reason: 'landlord $tag');
          expect(marks(backs(four.game.landlord!)), findsNWidgets(4), reason: tag);
          // The badge and the role keep their room beside the four faces.
          final badge = tester.getRect(find.byKey(ValueKey('seat ${four.game.landlord}')));
          final cards = tester.getRect(backs(four.game.landlord!));
          expect(cards.top, greaterThanOrEqualTo(badge.bottom - 1), reason: tag);
          await shot(tester, 'solo_landlord_kitty_$tag');
        }
      }
      await tester.pumpWidget(const SizedBox());
      for (final c in [bot, mine, four]) {
        c.dispose();
      }
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
