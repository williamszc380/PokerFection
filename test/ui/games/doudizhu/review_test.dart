// The menu's Last game for Fight the Landlord: the most recent deal replayed
// step by step, the auction included, with the grades from the game and the
// coach on demand, at the three sizes in the three languages. Screenshots
// with --dart-define=SHOTS=<folder>.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_record.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/kit/coach_answer.dart';
import 'package:pokerfection/src/kit/game_record.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_review.dart';
import 'package:pokerfection/src/ui/games/doudizhu/l10n/doudizhu_strings.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';
import 'package:pokerfection/src/ui/kit/coach_panel.dart';
import 'package:pokerfection/src/ui/kit/kit_scope.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';
import 'package:pokerfection/src/ui/kit/move_feedback.dart';

import '../../../kit/shots.dart';
import 'states.dart';

const sizes = [Size(568, 320), Size(390, 844), Size(1280, 800)];

/// A Training deal played to its end on fake time (the player like an Easy
/// bot), as the game saved it: bids and plays, graded.
Future<GameRecord> trainingDeal(WidgetTester tester, {int seed = 5}) async {
  final c = await finishedGame(tester, seed: seed);
  final record = c.record;
  c.dispose();
  await tester.pump(const Duration(seconds: 1));
  return record;
}

/// Shows the review of [record].
Future<void> pumpReview(
  WidgetTester tester,
  GameRecord record, {
  Size size = const Size(1280, 800),
  AppLanguage language = AppLanguage.english,
}) async {
  await pumpShot(
    tester,
    LandlordReview(record: record),
    size: size,
    language: language,
    wrap: (child) => KitScope(newJobs: Jobs.inline, lastGames: LastGames(), child: child),
  );
  await tester.pump();
}

/// Lets the coach's job finish and the screen settle (cards that change
/// face turn over in 400 ms).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump(const Duration(milliseconds: 400));
}

/// Goes to step [i] with the keys (Home, then → as many times).
Future<void> goTo(WidgetTester tester, int i) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.home);
  for (var n = 0; n < i; n++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
  }
  await settle(tester);
}

Future<void> leave(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

String headline(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('review headline'))).data!;

int seatOf(GameRecord record, int i) => ddzParseSeat(record.moves[i]);

/// The first step where the player moves and [test] holds for the move.
int firstOfPlayer(GameRecord record, bool Function(DdzMove move, bool graded) test) {
  final rules = ddzRulesOf(record);
  for (final (i, text) in record.moves.indexed) {
    if (seatOf(record, i) != 0) continue;
    if (test(ddzParseMove(text, rules).move, record.marks[i] != null)) return i;
  }
  throw StateError('no such move of the player');
}

HandFan hand(WidgetTester tester) => tester.widget<HandFan>(find.byKey(const ValueKey('hand')));

Future<void> toggle(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await settle(tester);
}

void main() {
  setUpAll(loadShotFonts);

  final s = LandlordStrings.forLanguage(AppLanguage.english);
  final k = KitStrings.forLanguage(AppLanguage.english);

  testWidgets('it opens at the first step: the dealt hands, the kitty face down, "Move 1 ·" the first bidder, '
      'and that seat\'s bid', (tester) async {
    final record = await trainingDeal(tester);
    await pumpReview(tester, record);
    final first = seatOf(record, 0);
    final name = first == 0 ? 'Player' : record.seats[first].name;
    expect(headline(tester), 'Move 1 · $name');
    expect(hand(tester).cards, hasLength(17));
    expect(find.byKey(const ValueKey('kitty down')), findsOneWidget);
    expect(find.text(ddzMoveLabelForTest(s, record.moves.first, record)), findsWidgets);
    await leave(tester);
  });

  testWidgets('the player\'s seat is "Player" (Jugador, 玩家) on the felt and in the headline, never "You"', (
    tester,
  ) async {
    final record = await trainingDeal(tester);
    final mine = firstOfPlayer(record, (_, _) => true);
    for (final language in AppLanguage.values) {
      final player = S.forLanguage(language).you;
      await pumpReview(tester, record, language: language);
      await goTo(tester, mine);
      expect(headline(tester), endsWith(' · $player'), reason: '$language');
      expect(find.descendant(of: find.byKey(const ValueKey('seat 0')), matching: find.text(player)), findsOneWidget);
      for (final word in ['You', 'Tú', '你']) {
        expect(find.text(word), findsNothing, reason: '$language: "$word"');
      }
    }
    await leave(tester);
  });

  testWidgets('the player\'s graded bid shows its grade in points, as the game graded the auction', (tester) async {
    final record = await trainingDeal(tester);
    final bid = firstOfPlayer(record, (move, graded) => move is! DdzPlay && move is! DdzPass && graded);
    await pumpReview(tester, record);
    await goTo(tester, bid);
    expect(find.byKey(const ValueKey('review mark')), findsOneWidget);
    final feedback = tester.widget<MoveFeedback>(find.byKey(const ValueKey('review mark')));
    expect(feedback.mark.unit, ValueUnit.points);
    await leave(tester);
  });

  testWidgets('a play of the player: its cards are raised in the hand below, and its grade is in win chance', (
    tester,
  ) async {
    final record = await trainingDeal(tester);
    final rules = ddzRulesOf(record);
    final at = firstOfPlayer(record, (move, graded) => move is DdzPlay && graded);
    await pumpReview(tester, record);
    await goTo(tester, at);
    final ids = ddzParseMove(record.moves[at], rules).cardIds!;
    expect(hand(tester).selected, hasLength(ids.length));
    expect(tester.widget<MoveFeedback>(find.byKey(const ValueKey('review mark'))).mark.unit, ValueUnit.winChance);
    await leave(tester);
  });

  testWidgets('All cards turns the bots\' hands and the kitty face up', (tester) async {
    final record = await trainingDeal(tester);
    await pumpReview(tester, record);
    expect(find.byKey(const ValueKey('hand 1')), findsNothing);
    await toggle(tester, 'all cards');
    expect(find.byKey(const ValueKey('hand 1')), findsOneWidget);
    expect(find.byKey(const ValueKey('hand 2')), findsOneWidget);
    expect(find.byKey(const ValueKey('kitty up')), findsOneWidget);
    await toggle(tester, 'all cards');
    expect(find.byKey(const ValueKey('hand 1')), findsNothing);
    await leave(tester);
  });

  testWidgets('the coach runs only once its chip is on, for the player\'s decisions; a bot\'s move gets none', (
    tester,
  ) async {
    final record = await trainingDeal(tester);
    final mine = firstOfPlayer(record, (_, graded) => graded);
    final bot = [for (var i = 0; i < record.moves.length; i++) i].firstWhere((i) => seatOf(record, i) != 0);
    await pumpReview(tester, record);
    await goTo(tester, mine);
    expect(find.byType(CoachList), findsNothing, reason: 'off until asked for');
    await toggle(tester, 'coach chip');
    expect(find.byType(CoachList), findsOneWidget);
    expect(find.descendant(of: find.byType(CoachList), matching: find.text(s.pickLabel)), findsWidgets);
    await goTo(tester, bot);
    expect(find.byType(CoachList), findsNothing, reason: 'the bots\' moves are not coached');
    await leave(tester);
  });

  testWidgets('the last step says who won and the player\'s points', (tester) async {
    final record = await trainingDeal(tester);
    final game = ddzReplay(record);
    await pumpReview(tester, record);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await settle(tester);
    final points = game.result!.points[0];
    final outcome = game.result!.wonBy(0)
        ? k.youWin
        : (game.landlord == 0 ? k.youLose : k.wins(record.seats[game.landlord!].name));
    expect(headline(tester), startsWith(outcome));
    expect(headline(tester), endsWith(k.net(points > 0 ? '+$points' : '−${-points}')));
    await leave(tester);
  });

  testWidgets('a deal everyone passed ends on "Everyone passed", not "Draw"', (tester) async {
    final c = await thrownInGame(tester);
    final record = c.record;
    c.dispose();
    await tester.pump(const Duration(seconds: 1));
    await pumpReview(tester, record);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await settle(tester);
    expect(headline(tester), s.everyonePassed);
    await leave(tester);
  });

  for (final language in AppLanguage.values) {
    for (final size in sizes) {
      final tag = shotTag(size, language);
      testWidgets('review $tag: the first step, a graded play with the coach and all cards, the end; '
          'nothing overflows', (tester) async {
        final record = await trainingDeal(tester);
        await pumpReview(tester, record, size: size, language: language);
        expect(tester.takeException(), isNull);
        await shot(tester, 'review_first_$tag');
        final bid = firstOfPlayer(record, (move, graded) => move is! DdzPlay && move is! DdzPass && graded);
        await goTo(tester, bid);
        await toggle(tester, 'coach chip');
        expect(tester.takeException(), isNull);
        await shot(tester, 'review_bid_$tag');
        await toggle(tester, 'all cards');
        await goTo(tester, firstOfPlayer(record, (move, graded) => move is DdzPlay && graded));
        expect(tester.takeException(), isNull);
        expect(find.byType(CoachList), findsOneWidget);
        await shot(tester, 'review_play_$tag');
        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        await settle(tester);
        expect(tester.takeException(), isNull);
        await shot(tester, 'review_end_$tag');
        await leave(tester);
      });
    }
  }
}

/// The words the review gives a move (as the coach rows do).
String ddzMoveLabelForTest(LandlordStrings s, String move, GameRecord record) =>
    switch (ddzParseMove(move, ddzRulesOf(record)).move) {
      DdzBid(:final points) => points == 0 ? s.noBid : s.bid(points),
      DdzCall(:final yes) => yes ? s.call : s.noCall,
      DdzRob(:final yes) => yes ? s.rob : s.noRob,
      _ => throw StateError('the first move is a bid'),
    };
