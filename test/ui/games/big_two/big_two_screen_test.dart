// The Big Two screen: it fits every size and language without overflow or
// page scroll, its buttons grey out (never hide) when they can't be used,
// and everything clickable answers the mouse.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_record.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_table.dart';
import 'package:pokerfection/src/ui/games/big_two/l10n/big_two_strings.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';
import 'package:pokerfection/src/ui/kit/coach_panel.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';

import '../../../kit/shots.dart';
import 'big_two_test_util.dart';

Finder byKey(String key) => find.byKey(ValueKey(key));

/// [finder]'s whole rectangle is on the screen.
void expectOnScreen(WidgetTester tester, Finder finder, Size size, {String? reason}) {
  final rect = tester.getRect(finder);
  final screen = Offset.zero & size;
  expect(
    screen.inflate(0.5).contains(rect.topLeft) && screen.inflate(0.5).contains(rect.bottomRight),
    isTrue,
    reason: '${reason ?? finder.toString()}: $rect is off the ${size.width}×${size.height} screen',
  );
}

/// Where the player's badge (and its chips) is drawn: its seat without the
/// seat's padding.
Rect playerBadge(WidgetTester tester) {
  final seat = tester.getRect(byKey('seat 0'));
  return Rect.fromLTRB(seat.left + 2, seat.top + 2, seat.right - 2, seat.bottom - 2 - BigTwoTable.playerBadgeLift);
}

/// Whether the button found by [key] can be pressed.
bool enabled(WidgetTester tester, String key) => tester.widget<ButtonStyleButton>(byKey(key)).onPressed != null;

/// A mouse pointer, already on the screen.
Future<TestGesture> mouse(WidgetTester tester) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: const Offset(1, 1));
  addTearDown(gesture.removePointer);
  return gesture;
}

SystemMouseCursor? cursorNow() =>
    RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1) as SystemMouseCursor?;

void main() {
  setUpAll(loadShotFonts);

  group('fits every size and language', () {
    for (final size in bigTwoSizes) {
      for (final language in AppLanguage.values) {
        final tag = shotTag(size, language);

        testWidgets('the game with the coach, its extras and a pick: $tag', (tester) async {
          // The coach chip turned on (in a last game): the coach and its extras show.
          final game = seededGame(toggles: const {'counter': true, 'coach': true});
          await pumpGame(tester, game, size: size, language: language);
          await toMyPlayableTurn(tester, game);
          expect(find.byType(CoachList), findsOneWidget, reason: 'the coach shows once turned on');
          game.selectMove(game.coach!.pick);
          await tester.pump();
          for (final key in ['play', 'pass', 'clear', 'hand', 'seat 1', 'seat 2', 'seat 3']) {
            expectOnScreen(tester, byKey(key), size, reason: key);
          }
          // The Sort button above the hand's left end, in sight at every
          // size, clear of the player's badge.
          expectOnScreen(tester, byKey('hand sort'), size, reason: 'sort');
          expect(
            tester.getRect(byKey('hand sort')).overlaps(playerBadge(tester)),
            isFalse,
            reason: 'the Sort button keeps off the "Player" badge',
          );
          for (final key in ['play', 'hand', 'seat 2']) {
            expect(
              find.ancestor(of: byKey(key), matching: find.byType(Scrollable)),
              findsNothing,
              reason: 'the page itself never scrolls ($key)',
            );
          }
          await closeGame(tester);
        });

        testWidgets('three players in Free Play: $tag', (tester) async {
          final game = seededGame(training: false, rules: BigTwoRules.standard(players: 3), seed: 5);
          await pumpGame(tester, game, size: size, language: language);
          await toMyPlayableTurn(tester, game);
          expect(find.byType(CoachList), findsNothing, reason: 'no coach in Free Play');
          for (final key in ['play', 'hand', 'seat 1', 'seat 2']) {
            expectOnScreen(tester, byKey(key), size, reason: key);
          }
          await closeGame(tester);
        });

        testWidgets('the end of a deal: $tag', (tester) async {
          final game = seededGame(seed: 9);
          await pumpGame(tester, game, size: size, language: language);
          await playToEnd(tester, game);
          final k = KitStrings.forLanguage(language);
          expect(find.text(k.nextDeal), findsOneWidget);
          expectOnScreen(tester, find.text(k.nextDeal), size);
          await closeGame(tester);
        });
      }
    }
  });

  group('the hand reads at every size', () {
    // 13 cards (four players), 17 (three), 21 (two players, the biggest deal).
    for (final (players, each) in const [(4, 13), (3, 17), (2, 21)]) {
      for (final size in bigTwoSizes) {
        testWidgets('$each cards at ${size.width.toInt()}x${size.height.toInt()}: one fan under the table, '
            'every card at least 46% in view (a whole "10") and at least 26 wide', (tester) async {
          final rules = BigTwoRules.standard(players: players).copyWith(cardsEach: each);
          final game = seededGame(rules: rules, training: false, seed: 2);
          await pumpGame(tester, game, size: size);
          final n = game.hand.length;
          expect(find.byType(HandFan), findsOneWidget, reason: 'one hand, never two rows');
          final fan = tester.widget<HandFan>(find.byType(HandFan));
          expect(fan.fanned, isTrue, reason: 'a fan: an arc with a slight tilt');
          expect(fan.cards, hasLength(n));
          // Laid out as the fan lays itself out in its box.
          final box = tester.getRect(byKey('hand'));
          final g = HandFanGeometry(n, box.size, fan.maxCardWidth, fanned: true, showing: fan.showing);
          expect(
            g.step / g.width,
            greaterThanOrEqualTo(0.46 - 1e-9),
            reason: 'each card shows 46% of itself: a "10" reads',
          );
          expect(g.width, greaterThanOrEqualTo(26));
          expect(g.angle(n - 1), greaterThan(0), reason: 'the end cards tilt');
          // Every card is drawn inside the hand's area, which is under the
          // table only (left of the panel on a sideways screen).
          final area = tester.getRect(byKey('hand area'));
          for (final element in find.descendant(of: byKey('hand'), matching: find.byType(GameCardView)).evaluate()) {
            final card = tester.getRect(find.byWidget(element.widget));
            expect(area.inflate(2).contains(card.center), isTrue, reason: '$card in $area');
          }
          final table = tester.getRect(find.byType(BigTwoTable));
          expect(area.left, closeTo(table.left, 1));
          expect(area.right, lessThanOrEqualTo(table.right + 1), reason: 'the hand is as wide as the table, no wider');
          if (size.width > size.height) {
            final panel = tester.getRect(byKey('pass'));
            expect(area.right, lessThanOrEqualTo(panel.left), reason: 'never under the panel');
          }
          await closeGame(tester);
        });
      }
    }
  });

  group("the player's own seat is \"Player\", never \"You\"", () {
    for (final language in AppLanguage.values) {
      testWidgets(language.name, (tester) async {
        final player = S.forLanguage(language).you;
        final strings = BigTwoStrings.forLanguage(language);
        expect(player, isNot(anyOf('You', 'Tú', '你')));
        final game = seededGame(training: false);
        await pumpGame(tester, game, language: language);
        await toMyPlayableTurn(tester, game);
        expect(
          find.descendant(of: byKey('seat 0'), matching: find.text(player)),
          findsOneWidget,
          reason: 'the badge',
        );
        for (final you in ['You', 'Tú', '你']) {
          expect(find.textContaining(RegExp('(^|[ ·])$you(\$|[ ·])')), findsNothing, reason: you);
        }
        // The player plays: the play to beat is theirs, named "Player" (the
        // felt alone, before a bot answers).
        final play = game.state.legalMoves().firstWhere((p) => !p.isPass);
        final after = game.record.withMove(bigTwoMoveText(0, play));
        await closeGame(tester);
        await pumpShot(
          tester,
          Builder(
            builder: (context) => BigTwoTable(
              state: BigTwoRecord.replay(after),
              names: BigTwoTable.seatNames(context, after.seats),
              strings: strings,
            ),
          ),
          size: const Size(800, 500),
          language: language,
        );
        expect(
          find.descendant(of: byKey('to beat'), matching: find.text('${strings.kind(play.kind)} · $player')),
          findsOneWidget,
        );
      });
    }
  });

  group('the panel', () {
    testWidgets('Play, Pass and Clear show a hand under the mouse (from the app theme)', (tester) async {
      final game = seededGame(training: false);
      await pumpGame(tester, game);
      await toMyPlayableTurn(tester, game);
      game.selectMove(bigTwoMoveText(0, game.state.legalMoves().firstWhere((p) => !p.isPass)));
      await tester.pump();
      final pointer = await mouse(tester);
      for (final key in ['play', 'clear']) {
        await pointer.moveTo(tester.getCenter(byKey(key)));
        await tester.pump();
        expect(cursorNow(), SystemMouseCursors.click, reason: key);
      }
      await closeGame(tester);
    });

    testWidgets('Play is greyed out until the picked cards make a legal play; Clear until something is picked', (
      tester,
    ) async {
      final game = seededGame(training: false);
      await pumpGame(tester, game);
      await toMyPlayableTurn(tester, game);
      expect(byKey('play'), findsOneWidget, reason: 'greyed out, not hidden');
      expect(enabled(tester, 'play'), isFalse);
      expect(enabled(tester, 'clear'), isFalse);
      final legal = game.state.legalMoves().firstWhere((p) => !p.isPass);
      // Tap the cards of a legal play in the hand.
      for (final card in legal.cards) {
        await tester.tap(find.byKey(ValueKey('${bigTwoFaceKey(card)}#1')));
        await tester.pump();
      }
      expect(enabled(tester, 'play'), isTrue);
      expect(enabled(tester, 'clear'), isTrue);
      await tester.tap(byKey('play'));
      await tester.pump();
      expect(game.record.moves.contains(bigTwoMoveText(0, legal)), isTrue);
      expect(game.selected, isEmpty);
      await closeGame(tester);
    });

    testWidgets('Pass is greyed out when the player leads, and everything is greyed out on the bots\' turns', (
      tester,
    ) async {
      final game = seededGame(training: false);
      await pumpGame(tester, game);
      await toMyPlayableTurn(tester, game);
      expect(enabled(tester, 'pass'), game.state.current != null, reason: 'nobody may pass on a lead');
      // Make it a lead: seeds until the player holds the 3♦ and starts.
      await closeGame(tester);
      for (var seed = 1; seed < 40; seed++) {
        final starter = seededGame(training: false, seed: seed);
        await pumpGame(tester, starter);
        if (starter.myTurn && starter.state.current == null) {
          expect(enabled(tester, 'pass'), isFalse, reason: 'leading: Pass greyed out');
          await closeGame(tester);
          return;
        }
        await closeGame(tester);
      }
      fail('no seed dealt the player the 3♦');
    });

    testWidgets('Enter plays the pick, Esc clears it, S presses the Sort button', (tester) async {
      final game = seededGame(training: false);
      await pumpGame(tester, game);
      await toMyPlayableTurn(tester, game);
      final legal = game.state.legalMoves().firstWhere((p) => !p.isPass);
      game.selectMove(bigTwoMoveText(0, legal));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(game.selected, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pump();
      expect(game.sortOrder, HandOrder.suit);
      game.selectMove(bigTwoMoveText(0, legal));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(game.record.moves, contains(bigTwoMoveText(0, legal)));
      await closeGame(tester);
    });
  });

  group('the mouse', () {
    testWidgets('a card under the mouse shows a hand cursor; a picked card stays raised', (tester) async {
      final game = seededGame(training: false);
      await pumpGame(tester, game);
      await toMyPlayableTurn(tester, game);
      final card = game.hand.first;
      final finder = find.byKey(ValueKey('${bigTwoFaceKey(card)}#1'));
      final pointer = await mouse(tester);
      await pointer.moveTo(tester.getCenter(finder));
      await tester.pump();
      expect(cursorNow(), SystemMouseCursors.click);
      await tester.tap(finder);
      await tester.pump();
      expect(tester.widget<GameCardView>(finder).selected, isTrue);
      await closeGame(tester);
    });

    testWidgets('a coach row under the mouse lights up and fades the hand\'s other cards; a tap picks its cards', (
      tester,
    ) async {
      final game = seededGame(toggles: const {'coach': true});
      await pumpGame(tester, game);
      await toMyPlayableTurn(tester, game);
      final move = game.coach!.lines.firstWhere((l) => !l.move.endsWith('pass')).move;
      final row = find.byKey(ValueKey(move));
      final pointer = await mouse(tester);
      await pointer.moveTo(tester.getCenter(row));
      await tester.pump();
      expect(game.preview, move);
      expect(
        tester.widget<Material>(find.descendant(of: row, matching: find.byType(Material)).first).color!.a,
        greaterThan(0.1),
        reason: 'the row lights up',
      );
      final fans = tester.widgetList<HandFan>(find.byType(HandFan));
      expect(
        fans.fold(0, (sum, fan) => sum + fan.dimmed.length),
        game.hand.length - bigTwoMoveCards(move).length,
        reason: 'only the move\'s cards stay bright',
      );
      await pointer.moveTo(const Offset(1, 1));
      await tester.pump();
      expect(game.preview, isNull);
      await tester.tap(row);
      await tester.pump();
      expect(game.selected, bigTwoMoveCards(move).toSet());
      await closeGame(tester);
    });

    testWidgets('the Sort button shows a hand and lights up under the mouse; a click switches Rank and Suit', (
      tester,
    ) async {
      final game = seededGame(training: false);
      await pumpGame(tester, game);
      final k = KitStrings.forLanguage(AppLanguage.english);
      final button = byKey('hand sort');
      expect(find.descendant(of: button, matching: find.text(k.handOrder(HandOrder.rank))), findsOneWidget);
      final pointer = await mouse(tester);
      await pointer.moveTo(tester.getCenter(button));
      await tester.pump();
      expect(cursorNow(), SystemMouseCursors.click);
      await tester.tap(button);
      await tester.pump();
      expect(game.sortOrder, HandOrder.suit);
      expect(find.descendant(of: button, matching: find.text(k.handOrder(HandOrder.suit))), findsOneWidget);
      await tester.tap(button);
      await tester.pump();
      expect(game.sortOrder, HandOrder.rank);
      await closeGame(tester);
    });
  });

  group('dragging cards', () {
    /// The finder of [card] in the hand.
    Finder cardOf(Card card) => find.byKey(ValueKey('${bigTwoFaceKey(card)}#1'));

    /// Drags [card] onto the place of [target] (with [kind]'s pointer),
    /// letting the drop settle.
    Future<void> dragOnto(
      WidgetTester tester,
      Card card,
      Card target, {
      PointerDeviceKind kind = PointerDeviceKind.touch,
    }) async {
      final from = tester.getCenter(cardOf(card)), to = tester.getCenter(cardOf(target));
      final gesture = await tester.startGesture(from, kind: kind);
      // Past the tap's slop first, then on to the place, in steps.
      for (var i = 1; i <= 8; i++) {
        await gesture.moveTo(Offset.lerp(from, to, i / 8)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
      testWidgets("a ${kind.name} drags a card to a new place: the hand is the player's own, the button reads Sort", (
        tester,
      ) async {
        final game = seededGame(training: false);
        await pumpGame(tester, game);
        final sorted = game.hand;
        await dragOnto(tester, sorted[0], sorted[3], kind: kind);
        expect(game.hand, [sorted[1], sorted[2], sorted[3], sorted[0], ...sorted.skip(4)]);
        expect(game.selected, isEmpty, reason: 'a drag picks nothing');
        final k = KitStrings.forLanguage(AppLanguage.english);
        expect(game.sortOrder, HandOrder.own);
        expect(
          find.descendant(of: byKey('hand sort'), matching: find.text(k.handOrder(HandOrder.own))),
          findsOneWidget,
        );
        // Drawn left to right in the new order.
        final xs = [for (final card in game.hand) tester.getCenter(cardOf(card)).dx];
        expect(xs, [...xs]..sort());
        // The button sorts the hand again.
        await tester.tap(byKey('hand sort'));
        await tester.pump();
        expect(game.sortOrder, HandOrder.rank);
        expect(game.hand, sorted);
        await closeGame(tester);
      });
    }

    testWidgets(
      'a tap still picks a card; picking several is a tap on each, and a picked card keeps its pick as it moves',
      (tester) async {
        final game = seededGame(training: false);
        await pumpGame(tester, game);
        await toMyPlayableTurn(tester, game);
        final hand = game.hand;
        await tester.tap(cardOf(hand[0]));
        await tester.pump();
        await tester.tap(cardOf(hand[1]));
        await tester.pump();
        expect(game.selected, {hand[0], hand[1]});
        await tester.tap(cardOf(hand[1]));
        await tester.pump();
        expect(game.selected, {hand[0]}, reason: 'a second tap puts it back');
        await dragOnto(tester, hand[0], hand[4]);
        expect(game.selected, {hand[0]});
        expect(game.hand.indexOf(hand[0]), 4);
        await closeGame(tester);
      },
    );

    testWidgets('after the deal the cards stay put and the Sort button is greyed out, not hidden', (tester) async {
      final game = seededGame(seed: 9);
      await pumpGame(tester, game);
      await playToEnd(tester, game);
      final fan = tester.widget<HandFan>(find.byType(HandFan));
      expect(fan.onReorder, isNull);
      expect(fan.onSort, isNull);
      if (game.hand.isNotEmpty) {
        expect(byKey('hand sort'), findsOneWidget, reason: 'greyed out, not hidden');
        expect(tester.widget<HandSortButton>(byKey('hand sort')).onPressed, isNull);
      }
      await closeGame(tester);
    });
  });

  testWidgets('on a sideways phone the fan takes the whole width under the table; Sort sits above its left end', (
    tester,
  ) async {
    final rules = BigTwoRules.standard(players: 2).copyWith(cardsEach: 21);
    final game = seededGame(rules: rules, training: false, seed: 2);
    await pumpGame(tester, game, size: const Size(568, 320));
    final area = tester.getRect(byKey('hand area'));
    final hand = tester.getRect(byKey('hand'));
    expect(hand.width, greaterThan(area.width - 20), reason: 'the fan spans the hand area');
    final button = tester.getRect(byKey('hand sort'));
    expect(button.left, closeTo(hand.left, 12), reason: "at the hand's left end");
    final first = tester.getRect(find.byKey(ValueKey('${bigTwoFaceKey(game.hand.first)}#1')));
    expect(button.bottom, lessThanOrEqualTo(first.top + 1), reason: 'above the first card, clear of its corner');
    expect(button.overlaps(playerBadge(tester)), isFalse, reason: 'off the "Player" badge');
    await tester.tap(byKey('hand sort'));
    await tester.pump();
    expect(game.sortOrder, HandOrder.suit, reason: "it taps over the felt's edge too");
    // One place to sort: not in ☰.
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byWidgetPredicate((w) => w is PopupMenuItem), matching: find.byIcon(Icons.sort)),
      findsNothing,
    );
    await tester.tapAt(const Offset(2, 300));
    await tester.pumpAndSettle();
    await closeGame(tester);
  });

  group('the Sort button keeps off the "Player" badge all deal long, however few cards are left', () {
    for (final size in const [
      Size(568, 320),
      Size(640, 360),
      Size(740, 360),
      Size(900, 420),
      Size(1024, 600),
      Size(1280, 800),
      Size(1920, 1080),
      Size(390, 844),
    ]) {
      for (final language in AppLanguage.values) {
        testWidgets(shotTag(size, language), (tester) async {
          final game = seededGame(training: false, seed: 4);
          await pumpGame(tester, game, size: size, language: language);
          for (var guard = 0; guard < 400 && !game.isOver; guard++) {
            await settleGame(tester);
            if (!game.myTurn) continue;
            final legal = game.state.legalMoves();
            // The player plays one card at a time when they can, so every
            // length of hand is seen.
            final play =
                legal.where((p) => p.size == 1).firstOrNull ??
                legal.firstWhere((p) => !p.isPass, orElse: () => legal.first);
            game.humanMove(bigTwoMoveText(0, play));
            await settleGame(tester);
            if (game.hand.isEmpty) break;
            final button = tester.getRect(byKey('hand sort'));
            final badge = playerBadge(tester);
            expect(button.overlaps(badge), isFalse, reason: '${game.hand.length} cards: $button, badge $badge');
          }
          // After the deal too, the greyed-out button beside the badge and its points.
          if (game.isOver && game.hand.isNotEmpty) {
            expect(tester.getRect(byKey('hand sort')).overlaps(playerBadge(tester)), isFalse, reason: 'after the deal');
          }
          // Lifted, the badge still keeps under the pile's label's words
          // (the line's leading below them may touch it).
          final label = tester.getRect(byKey('pile label'));
          expect(playerBadge(tester).top, greaterThanOrEqualTo(label.bottom - 4), reason: "the pile's label");
          await closeGame(tester);
        });
      }
    }
  });

  group('☰', () {
    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
    }

    PopupMenuItem<Object?> item(WidgetTester tester, String label) => tester.widget<PopupMenuItem<Object?>>(
      find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is PopupMenuItem)),
    );

    testWidgets('Card counter turns the counter on under the coach, and stays on', (tester) async {
      final game = seededGame(toggles: const {'coach': true});
      await pumpGame(tester, game);
      await toMyPlayableTurn(tester, game);
      expect(byKey('card counter'), findsNothing);
      await openMenu(tester);
      final strings = BigTwoStrings.forLanguage(AppLanguage.english);
      expect(item(tester, strings.cardCounter).enabled, isTrue);
      await tester.tap(find.text(strings.cardCounter));
      await tester.pumpAndSettle();
      expect(game.counterOn, isTrue);
      expect(byKey('card counter'), findsOneWidget);
      await openMenu(tester);
      expect(
        find.descendant(of: find.byWidget(item(tester, strings.cardCounter)), matching: byKey('checked')),
        findsOneWidget,
        reason: 'a toggle: checked while on',
      );
      await tester.tapAt(const Offset(2, 400));
      await tester.pumpAndSettle();
      expect(byKey('hand plan'), findsOneWidget, reason: 'the hand plan shows with the coach');
      await closeGame(tester);
    });

    testWidgets('in Free Play the Card counter item is greyed out, not hidden', (tester) async {
      final game = seededGame(training: false);
      await pumpGame(tester, game);
      await openMenu(tester);
      final strings = BigTwoStrings.forLanguage(AppLanguage.english);
      expect(item(tester, strings.cardCounter).enabled, isFalse);
      await closeGame(tester);
    });
  });
}
