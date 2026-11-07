import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_record.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';
import 'package:pokerfection/src/ui/kit/coach_panel.dart';

import '../../../kit/shots.dart';
import 'states.dart';

const pc = Size(1280, 800);

ButtonStyleButton button(WidgetTester tester, String key) =>
    tester.widget<ButtonStyleButton>(find.byKey(ValueKey(key)));

bool enabled(WidgetTester tester, String key) => button(tester, key).onPressed != null;

HandFan hand(WidgetTester tester) => tester.widget<HandFan>(find.byKey(const ValueKey('hand')));

Future<TestGesture> mouseOver(WidgetTester tester, Finder finder) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  await gesture.moveTo(tester.getCenter(finder));
  await tester.pump();
  return gesture;
}

void main() {
  setUpAll(loadShotFonts);

  testWidgets('the auction: bids you can\'t make are greyed out, the coach\'s advice is tagged, a tap bids', (
    tester,
  ) async {
    final c = await gameAt(tester, DdzPhase.bidding, coach: true);
    await showGame(tester, c, pc, AppLanguage.english);
    final legal = c.game.legalMoves();
    for (var b = 0; b <= 3; b++) {
      expect(enabled(tester, 'bid $b'), legal.contains(DdzBid(b)), reason: 'bid $b');
    }
    // The coach's pick wears the "GTO" tag.
    final pick = ddzParseMove(c.coach!.pick).move as DdzBid;
    expect(find.byKey(const ValueKey('advised')), findsOneWidget);
    final tag = tester.getRect(find.byKey(const ValueKey('advised')));
    final advised = tester.getRect(find.byKey(ValueKey('bid ${pick.points}')));
    expect(tag.center.dx, inInclusiveRange(advised.left, advised.right), reason: 'on the advised bid');
    final at = c.record.moves.length;
    await tester.tap(find.byKey(const ValueKey('bid 0')));
    await tester.pump();
    expect(c.record.moves[at], yours(const DdzBid(0)));
    await closeGame(tester, c);
  });

  testWidgets('playing: Play is greyed out until the picked cards can be played; Clear until cards are picked', (
    tester,
  ) async {
    final c = await gameAt(tester, DdzPhase.playing, training: false, leading: true);
    await showGame(tester, c, pc, AppLanguage.english);
    expect(enabled(tester, 'play'), isFalse);
    expect(enabled(tester, 'clear'), isFalse);
    expect(enabled(tester, 'pass'), isFalse, reason: 'you lead: no passing');

    // Two cards of different ranks: no play.
    final ids = c.game.hands[0];
    final low = ids.first;
    final other = ids.firstWhere((id) => rankOfId(id) != rankOfId(low));
    c.toggle(low);
    c.toggle(other);
    await tester.pump();
    expect(enabled(tester, 'clear'), isTrue);
    expect(enabled(tester, 'play'), isFalse);

    // One card is a single: Play lights up and plays it.
    c.toggle(other);
    await tester.pump();
    expect(enabled(tester, 'play'), isTrue);
    final at = c.record.moves.length;
    await tester.tap(find.byKey(const ValueKey('play')));
    await tester.pump();
    expect(ddzParseMove(c.record.moves[at]).cardIds, [low]);
    await closeGame(tester, c);
  });

  testWidgets('tapping a card in the hand picks it; the cards show a hand cursor', (tester) async {
    final c = await gameAt(tester, DdzPhase.playing, training: false, leading: true);
    await showGame(tester, c, pc, AppLanguage.english);
    final cards = find.descendant(of: find.byKey(const ValueKey('hand')), matching: find.byType(GameCardView));
    expect(cards, findsNWidgets(c.game.hands[0].length));
    // Each card's own (the Sort button above them has one too).
    final cursors = find.descendant(
      of: cards,
      matching: find.byWidgetPredicate((w) => w is MouseRegion && w.cursor == SystemMouseCursors.click),
    );
    expect(cursors, findsNWidgets(c.game.hands[0].length));
    await tester.tap(cards.last);
    await tester.pump();
    expect(c.selected, hasLength(1));
    expect(hand(tester).selected, hasLength(1));
    await closeGame(tester, c);
  });

  testWidgets('hovering a coach row previews its play: the other cards of the hand dim, and light up again after', (
    tester,
  ) async {
    final c = await gameAt(tester, DdzPhase.playing, coach: true, seed: 2);
    c.clearSelection();
    await showGame(tester, c, pc, AppLanguage.english);
    final rows = find.descendant(of: find.byType(CoachList), matching: find.byType(InkWell));
    final playRow = [
      for (final (i, line) in c.coach!.lines.take(5).indexed)
        if (ddzParseMove(line.move).move is DdzPlay) (i, line.move),
    ].first;
    final mouse = await mouseOver(tester, rows.at(playRow.$1));
    expect(c.preview, playRow.$2);
    final play = (ddzParseMove(playRow.$2).move as DdzPlay).play;
    expect(hand(tester).dimmed, hasLength(c.game.hands[0].length - play.size));
    await mouse.moveTo(const Offset(5, 5));
    await tester.pump();
    expect(c.preview, isNull);
    expect(hand(tester).dimmed, isEmpty);

    // A tap picks the row's cards (it doesn't play them).
    final moves = c.record.moves.length;
    await tester.tap(rows.at(playRow.$1));
    await tester.pump();
    expect(c.record.moves, hasLength(moves));
    expect(c.selected, hasLength(play.size));
    await closeGame(tester, c);
  });

  testWidgets('Free Play: the coach chip is greyed out and no coach shows', (tester) async {
    final c = await gameAt(tester, DdzPhase.playing, training: false);
    await showGame(tester, c, pc, AppLanguage.english);
    final chip = tester.widget<FilterChip>(find.byKey(const ValueKey('coach chip')));
    expect(chip.onSelected, isNull);
    expect(find.byType(CoachList), findsNothing);
    await closeGame(tester, c);
  });

  testWidgets('☰ Card counter hides and shows the counter, and the choice is kept in the record', (tester) async {
    final c = await gameAt(tester, DdzPhase.playing);
    await showGame(tester, c, pc, AppLanguage.english);
    expect(find.byKey(const ValueKey('card counter')), findsOneWidget);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Card counter'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('card counter')), findsNothing);
    expect(c.record.extra['counter'], false);
    await closeGame(tester, c);
  });

  testWidgets(
    'a finished deal: the result in the status line, the bots\' last cards turned up, Next deal deals again',
    (tester) async {
      final c = await finishedGame(tester);
      await showGame(tester, c, pc, AppLanguage.english);
      final headline = c.winners.contains(0)
          ? 'You win'
          : (c.winners.length == 1 ? '${c.seatName(c.winners.single)} wins' : 'You lose');
      expect(find.text(headline), findsOneWidget);
      for (final seat in [1, 2]) {
        expect(find.byKey(ValueKey('left $seat')), c.game.hands[seat].isEmpty ? findsNothing : findsOneWidget);
      }
      // The match's line, not the session's net: the deal and the totals.
      expect(find.textContaining('Net'), findsNothing);
      expect(find.textContaining('Deal 1 · Player'), findsOneWidget);
      final before = c.record.seed;
      await tester.tap(find.text('Next deal'));
      await tester.pump();
      expect(c.deals, 2);
      expect(c.record.seed, isNot(before), reason: 'a new deal (the bots may have bid already)');
      expect(c.isOver, isFalse);
      await closeGame(tester, c);
    },
  );

  testWidgets('Enter plays the picked cards', (tester) async {
    final c = await gameAt(tester, DdzPhase.playing, training: false, leading: true);
    await showGame(tester, c, pc, AppLanguage.english);
    c.toggle(c.game.hands[0].first);
    await tester.pump();
    final at = c.record.moves.length;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(c.record.moves.length, greaterThan(at));
    await closeGame(tester, c);
  });

  testWidgets('the player\'s own seat is "Player" (Jugador, 玩家) in every language, never "You"', (tester) async {
    final c = await gameAt(tester, DdzPhase.playing, training: false, seed: 3);
    for (final language in AppLanguage.values) {
      await showGame(tester, c, pc, language);
      final player = S.forLanguage(language).you;
      expect(
        find.descendant(of: find.byKey(const ValueKey('seat 0')), matching: find.text(player)),
        findsOneWidget,
        reason: '$language',
      );
      for (final word in ['You', 'Tú', '你']) {
        expect(find.text(word), findsNothing, reason: '$language: "$word"');
      }
    }
    await closeGame(tester, c);
  });

  testWidgets('a deal everyone passed is thrown in: the headline says "Everyone passed", not "Draw"', (tester) async {
    final c = await thrownInGame(tester);
    await showGame(tester, c, pc, AppLanguage.english);
    expect(find.text('Everyone passed'), findsOneWidget);
    expect(find.text('Draw'), findsNothing);
    expect(find.text('Next deal'), findsOneWidget);
    await closeGame(tester, c);
  });

  testWidgets('a pass the player can\'t avoid says "Can\'t beat" and plays itself after the bots\' pause', (
    tester,
  ) async {
    final (c, at) = await forcedPassGame(tester);
    await showGame(tester, c, pc, AppLanguage.english);
    expect(find.text("Can't beat"), findsOneWidget);
    expect(enabled(tester, 'play'), isFalse);
    expect(c.record.moves, hasLength(at), reason: 'not yet: it waits like a bot');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(c.record.moves[at], yours(const DdzPass()));
    expect(c.record.marks.elementAtOrNull(at), isNull, reason: 'not graded');
    await closeGame(tester, c);
  });
}
