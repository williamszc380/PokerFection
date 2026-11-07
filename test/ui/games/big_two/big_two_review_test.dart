// The menu's Last game for Big Two: the most recent deal replayed step by
// step, the mover named ("Player" for the player's own seat), the grades
// from the game, the player's next play raised in the hand, All cards, and
// the coach on demand for the player's own choices, at the three sizes in
// the three languages. Screenshots with --dart-define=SHOTS=<folder>.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_record.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/kit/game_record.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_coach_view.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_review.dart';
import 'package:pokerfection/src/ui/games/big_two/l10n/big_two_strings.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';
import 'package:pokerfection/src/ui/kit/coach_panel.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';
import 'package:pokerfection/src/ui/kit/review_kit.dart';

import '../../../kit/shots.dart';
import 'big_two_test_util.dart';

/// Shows the review of [record].
Future<void> pumpReview(
  WidgetTester tester,
  GameRecord record, {
  Size size = const Size(1280, 800),
  AppLanguage language = AppLanguage.english,
}) async {
  await pumpShot(
    tester,
    BigTwoReview(record: record),
    size: size,
    language: language,
    wrap: bigTwoKit(LastGames()),
  );
  await settleGame(tester);
}

String headline(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('review headline'))).data!;

/// Goes to step [i] (the slider's End and Home keys, then ▶).
Future<void> goTo(WidgetTester tester, int i) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.home);
  await settleGame(tester);
  for (var k = 0; k < i; k++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settleGame(tester);
  }
}

/// The first step at or after [from] whose move [test] accepts.
int stepWhere(GameRecord record, bool Function(int index, String move) test, {int from = 0}) {
  for (var i = from; i < record.moves.length; i++) {
    if (test(i, record.moves[i])) return i;
  }
  fail('no such step');
}

bool mine(String move) => bigTwoMoveSeat(move) == 0;

/// The player had a real choice before move [i] (more than Pass alone).
bool realChoice(GameRecord record, int i) => BigTwoRecord.replay(record.upTo(i)).legalMoves().length > 1;

Finder reviewHandFans() =>
    find.descendant(of: find.byKey(const ValueKey('review hand')), matching: find.byType(HandFan));

int raisedCards(WidgetTester tester) =>
    tester.widgetList<HandFan>(reviewHandFans()).fold(0, (sum, fan) => sum + fan.selected.length);

int faceUpCards(WidgetTester tester) =>
    tester.widgetList<GameCardView>(find.byType(GameCardView)).where((c) => c.faceUp).length;

void main() {
  setUpAll(loadShotFonts);

  testWidgets('each step names who moves, "Player" for the player\'s own moves; the last gives the winner and the '
      'player\'s points', (tester) async {
    final record = await savedDeal(tester);
    final k = KitStrings.forLanguage(AppLanguage.english);
    await pumpReview(tester, record);
    final first = bigTwoMoveSeat(record.moves.first);
    expect(headline(tester), 'Move 1 · ${first == 0 ? 'Player' : record.seats[first].name}');
    final mineAt = stepWhere(record, (_, move) => mine(move));
    await goTo(tester, mineAt);
    expect(headline(tester), 'Move ${mineAt + 1} · Player');
    final botAt = stepWhere(record, (_, move) => !mine(move));
    await goTo(tester, botAt);
    expect(headline(tester), 'Move ${botAt + 1} · ${record.seats[bigTwoMoveSeat(record.moves[botAt])].name}');
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await settleGame(tester);
    final end = BigTwoRecord.replay(record);
    final points = end.result.scores[0];
    final signed = points > 0 ? '+$points' : (points < 0 ? '−${-points}' : '0');
    final who = end.winner == 0 ? k.youWin : k.wins(record.seats[end.winner].name);
    expect(headline(tester), '$who · ${k.pointsValue(signed)}');
    expect(find.text('You'), findsNothing);
  });

  testWidgets("the player's next play stands up in the hand; the bots' cards show only with All cards", (tester) async {
    final record = await savedDeal(tester);
    await pumpReview(tester, record);
    final at = stepWhere(record, (_, move) => mine(move) && !move.endsWith('pass'));
    await goTo(tester, at);
    expect(raisedCards(tester), bigTwoMoveCards(record.moves[at]).length);
    final before = faceUpCards(tester);
    await tester.tap(find.byKey(const ValueKey('all cards')));
    await settleGame(tester);
    final state = BigTwoRecord.replay(record.upTo(at));
    final botCards = [for (var seat = 1; seat < state.players; seat++) state.countOf(seat)].reduce((a, b) => a + b);
    expect(faceUpCards(tester), before + botCards, reason: 'every bot card face up');
    // On a bot's move nothing in the hand stands up.
    await goTo(tester, stepWhere(record, (_, move) => !mine(move)));
    expect(raisedCards(tester), 0);
  });

  testWidgets("the game's grades show on the player's moves, drawn as cards; a bot's move shows as text", (
    tester,
  ) async {
    final record = await savedDeal(tester);
    final strings = BigTwoStrings.forLanguage(AppLanguage.english);
    await pumpReview(tester, record);
    final graded = stepWhere(record, (i, _) => record.marks[i] != null);
    await goTo(tester, graded);
    expect(find.byKey(const ValueKey('review mark')), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const ValueKey('review mark')), matching: find.byType(MiniCards)),
      findsWidgets,
      reason: 'the move is drawn, as in the coach list',
    );
    final bot = stepWhere(record, (_, move) => !mine(move));
    await goTo(tester, bot);
    expect(tester.widget<Text>(find.byKey(const ValueKey('review move'))).data, moveLabel(strings, record.moves[bot]));
    // Forced passes are never graded.
    for (final (i, move) in record.moves.indexed) {
      if (mine(move) && !realChoice(record, i)) expect(record.marks[i], isNull, reason: 'move $i: Pass was all');
    }
  });

  testWidgets("the coach answers the player's own choices, and nothing on the bots' moves", (tester) async {
    final record = await savedDeal(tester);
    await pumpReview(tester, record);
    final choice = stepWhere(record, (i, move) => mine(move) && realChoice(record, i));
    await goTo(tester, choice);
    await tester.tap(find.byKey(const ValueKey('coach chip')));
    await settleGame(tester);
    expect(find.byType(CoachList), findsOneWidget);
    final rows = tester.widget<CoachList>(find.byType(CoachList)).answer!.lines;
    expect(rows, isNotEmpty);
    expect(rows.every((line) => mine(line.move)), isTrue, reason: "the player's moves");
    await goTo(tester, stepWhere(record, (_, move) => !mine(move)));
    expect(find.byType(CoachList), findsNothing, reason: "a bot's move: no coach");
  });

  testWidgets('a coach row under the mouse fades the hand\'s other cards', (tester) async {
    final record = await savedDeal(tester);
    await pumpReview(tester, record);
    final choice = stepWhere(record, (i, move) => mine(move) && realChoice(record, i));
    await goTo(tester, choice);
    await tester.tap(find.byKey(const ValueKey('coach chip')));
    await settleGame(tester);
    final answer = tester.widget<CoachList>(find.byType(CoachList)).answer!;
    final move = answer.lines.firstWhere((l) => !l.move.endsWith('pass')).move;
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: const Offset(1, 1));
    addTearDown(pointer.removePointer);
    await pointer.moveTo(tester.getCenter(find.byKey(ValueKey(move))));
    await tester.pump();
    final hand = BigTwoRecord.replay(record.upTo(choice)).countOf(0);
    final dimmed = tester.widgetList<HandFan>(reviewHandFans()).fold(0, (sum, fan) => sum + fan.dimmed.length);
    expect(dimmed, hand - bigTwoMoveCards(move).length);
  });

  testWidgets('a Free Play deal has no grades, and the coach can still be asked', (tester) async {
    final record = await savedDeal(tester, training: false);
    expect(record.marks.every((m) => m == null), isTrue);
    await pumpReview(tester, record);
    final chip = find.descendant(of: find.byKey(const ValueKey('coach chip')), matching: find.byType(FilterChip));
    expect(tester.widget<FilterChip>(chip).onSelected, isNotNull);
  });

  for (final size in bigTwoSizes) {
    for (final language in AppLanguage.values) {
      final tag = shotTag(size, language);
      testWidgets('fits $tag: a graded move, the coach, the deal over', (tester) async {
        final record = await savedDeal(tester, rules: BigTwoRules.standard(players: 3));
        await pumpReview(tester, record, size: size, language: language);
        final graded = stepWhere(
          record,
          (i, move) => record.marks[i] != null && record.marks[i]!.played != record.marks[i]!.best,
          from: 0,
        );
        await goTo(tester, graded);
        await tester.tap(find.byKey(const ValueKey('coach chip')));
        await settleGame(tester);
        expect(tester.takeException(), isNull);
        for (final key in ['step slider', 'step back', 'step next', 'review headline', 'review hand', 'coach chip']) {
          final rect = tester.getRect(find.byKey(ValueKey(key)));
          expect((Offset.zero & size).inflate(0.5).contains(rect.bottomRight), isTrue, reason: '$key at $rect');
        }
        expect(find.text(S.forLanguage(language).you), findsWidgets, reason: "the player's badge");
        // The step slider's thumb slides to its place.
        await tester.pump(const Duration(milliseconds: 400));
        await shot(tester, 'big_two_review_$tag');
        await tester.tap(find.byKey(const ValueKey('all cards')));
        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        await settleGame(tester);
        expect(tester.takeException(), isNull);
        // The step slider's thumb slides to its place.
        await tester.pump(const Duration(milliseconds: 400));
        await shot(tester, 'big_two_review_end_$tag');
        expect(find.byType(ReviewScaffold), findsOneWidget);
      });
    }
  }
}
