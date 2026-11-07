// A card everyone at the table has seen shows face up in its holder's seat
// with the kit's eye, and says so under the mouse ("Everyone can see this
// card"): Big Two's starting card (the 3♦ with four players, the lowest
// card dealt with two), from the deal until it is played, and a
// three-player deal's face-up card. On the player's own fan it carries the
// eye too; once the deal is over there is none. Screenshots with
// --dart-define=SHOTS=<folder>.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_record.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_coach_view.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_controller.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_review.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import '../../../kit/shots.dart';
import 'big_two_test_util.dart';

final _mark = find.byKey(const ValueKey('visible mark'));
final _label = find.byKey(const ValueKey('visible label'));
Finder _seat(int seat) => find.byKey(ValueKey('seat $seat'));
final _hand = find.byKey(const ValueKey('hand'));

/// The face-up card in [within] that carries the eye, showing [card].
Finder _markedCard(Finder within, Card card) => find.descendant(
  of: within,
  matching: find.byWidgetPredicate(
    (w) => w is GameCardView && w.faceUp && w.visibleToAll && w.face == bigTwoFace(card),
  ),
);

/// A game at a new deal whose starting card [wanted] accepts (its holder,
/// the deal), just after who goes first has shown (its cards landed in
/// their seats), the bots waiting their normal pause so nothing is played
/// yet. Fails when no seed under 60 deals one.
Future<BigTwoController> _dealWhere(
  WidgetTester tester,
  bool Function(BigTwoState state) wanted, {
  BigTwoRules? rules,
  Size size = const Size(1280, 800),
  AppLanguage language = AppLanguage.english,
}) async {
  for (var seed = 1; seed < 60; seed++) {
    final game = seededGame(rules: rules, seed: seed, training: false, speed: PlaybackSpeed.normal);
    await pumpGame(tester, game, size: size, language: language);
    await _afterOpening(tester, game);
    if (game.started && game.state.history.isEmpty && !game.state.isOver && wanted(game.state)) return game;
    await _close(tester);
  }
  fail('no deal like that');
}

/// Lets [game]'s who-goes-first step end (see big_two_opening_test.dart),
/// short of the bot's pause after it.
Future<void> _afterOpening(WidgetTester tester, BigTwoController game) async {
  await tester.pump(game.openingLength + const Duration(milliseconds: 50));
  expect(game.openingPlaying, isFalse);
}

/// A mouse resting on [card]'s left part (the part a neighbour never
/// covers); the caller takes it away ([TestGesture.removePointer]).
Future<TestGesture> _hover(WidgetTester tester, Finder card) async {
  final rect = tester.getRect(card.first);
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset(rect.left + rect.width * 0.2, rect.center.dy));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return mouse;
}

/// Closes the screen and lets the bots' pauses run out (the deals here
/// keep the normal pace, so nothing is played before the test looks).
Future<void> _close(WidgetTester tester) async {
  await closeGame(tester);
  await tester.pump(const Duration(seconds: 10));
}

void main() {
  setUpAll(loadShotFonts);

  testWidgets('a bot holding the 3♦ shows it face up among its backs, with the eye, until it plays it', (tester) async {
    final game = await _dealWhere(tester, (s) => s.startSeat != 0);
    final holder = game.state.startSeat;
    final three = Card.parse('3d');
    expect(_markedCard(_seat(holder), three), findsOneWidget);
    expect(find.descendant(of: _seat(holder), matching: _mark), findsOneWidget);
    expect(_mark, findsOneWidget, reason: 'no other seat and not the hand');
    final backs = tester.widget<SeatHand>(find.descendant(of: _seat(holder), matching: find.byType(SeatHand)));
    expect(backs.faces, isNull, reason: 'among the backs');
    expect(backs.visibleToAll, [bigTwoFace(three)]);
    // On to its play: the first play holds the 3♦, so the eye goes.
    for (var guard = 0; guard < 50 && game.state.history.isEmpty; guard++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    await settleGame(tester);
    expect(game.state.isPlayed(game.rules.codeOf(three)), isTrue);
    expect(_mark, findsNothing);
    await _close(tester);
  });

  testWidgets('the player holding the 3♦ sees the eye on it in their fan, and no seat shows it', (tester) async {
    final game = await _dealWhere(tester, (s) => s.startSeat == 0);
    final three = Card.parse('3d');
    expect(_markedCard(_hand, three), findsOneWidget);
    expect(_mark, findsOneWidget);
    for (var seat = 1; seat < 4; seat++) {
      expect(find.descendant(of: _seat(seat), matching: _mark), findsNothing);
    }
    // Playing it takes the eye away.
    game.humanMove(bigTwoMoveText(0, game.state.legalMoves().firstWhere((m) => m.size == 1)));
    await settleGame(tester);
    expect(_mark, findsNothing);
    await _close(tester);
  });

  for (final language in AppLanguage.values) {
    testWidgets('the mouse over the visible card says so, in ${language.code}', (tester) async {
      final game = await _dealWhere(tester, (s) => s.startSeat != 0, language: language);
      final text = KitStrings.forLanguage(language).visibleToAll;
      expect(find.text(text), findsNothing);
      final mouse = await _hover(tester, _markedCard(_seat(game.state.startSeat), Card.parse('3d')));
      expect(_label, findsOneWidget);
      expect(find.text(text), findsOneWidget);
      await mouse.removePointer();
      await _close(tester);
    });
  }

  testWidgets('two players: the lowest card dealt is shown in the leader\'s seat, rank and suit', (tester) async {
    final game = await _dealWhere(tester, (s) => s.startSeat == 1, rules: BigTwoRules.standard(players: 2));
    final start = game.rules.cardOf(game.state.startCode);
    expect(_markedCard(_seat(1), start), findsOneWidget);
    await _close(tester);
  });

  testWidgets('three players: the starting card and the face-up card both show in the seat that took them', (
    tester,
  ) async {
    final game = await _dealWhere(
      tester,
      (s) => s.startSeat != 0 && s.extraCode != s.startCode,
      rules: BigTwoRules.standard(players: 3),
    );
    final s = game.state;
    for (final code in [s.startCode, s.extraCode]) {
      expect(_markedCard(_seat(s.startSeat), game.rules.cardOf(code)), findsOneWidget);
    }
    expect(_mark, findsNWidgets(2));
    await _close(tester);
  });

  testWidgets('Show cards: the bot\'s hand face up, the visible card marked where it lies', (tester) async {
    for (var seed = 1; seed < 60; seed++) {
      final game = seededGame(seed: seed, training: true, speed: PlaybackSpeed.normal, toggles: {'showCards': true});
      await pumpGame(tester, game);
      await _afterOpening(tester, game);
      if (game.state.startSeat == 0 || game.state.history.isNotEmpty) {
        await _close(tester);
        continue;
      }
      final rows = tester.widgetList<SeatHand>(
        find.descendant(of: _seat(game.state.startSeat), matching: find.byType(SeatHand)),
      );
      expect(rows.fold(0, (n, row) => n + row.faces!.length), 13, reason: 'every card face up');
      expect(_markedCard(_seat(game.state.startSeat), Card.parse('3d')), findsOneWidget);
      await _close(tester);
      return;
    }
    fail('no deal where a bot leads');
  });

  testWidgets('the review: the step before the first play shows the eye, the deal\'s end none', (tester) async {
    final record = await savedDeal(tester, training: false, seed: 9);
    await pumpShot(
      tester,
      BigTwoReview(record: record),
      size: const Size(1280, 800),
      wrap: bigTwoKit(LastGames()),
    );
    await settleGame(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await settleGame(tester);
    expect(_mark, findsOneWidget, reason: 'the 3♦ in its holder\'s seat or in the player\'s fan');
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await settleGame(tester);
    expect(_mark, findsNothing);
  });

  // No overflow anywhere a visible card shows, 2, 3 and 4 players, and the
  // screens to look at: a bot's seat with the face-up card, the label under
  // the mouse, the player's own fan.
  for (final size in const [Size(568, 320), Size(512, 320), Size(900, 420), Size(1280, 800), Size(390, 844)]) {
    for (final language in AppLanguage.values) {
      final tag = shotTag(size, language);
      testWidgets('shots: visible cards $tag', (tester) async {
        for (final players in [4, 3, 2]) {
          final rules = BigTwoRules.standard(players: players);
          final bot = await _dealWhere(
            tester,
            (s) => s.startSeat != 0 && (players != 3 || s.extraCode != s.startCode),
            rules: rules,
            size: size,
            language: language,
          );
          expect(tester.takeException(), isNull);
          await shot(tester, 'b2v_solo_${players}p_bot_$tag');
          if (players == 4) {
            final mouse = await _hover(tester, _markedCard(_seat(bot.state.startSeat), Card.parse('3d')));
            expect(_label, findsOneWidget);
            await shot(tester, 'b2v_solo_hover_seat_$tag');
            await mouse.removePointer();
          }
          await _close(tester);
        }
        await _dealWhere(tester, (s) => s.startSeat == 0, size: size, language: language);
        final mouse = await _hover(tester, _markedCard(_hand, Card.parse('3d')));
        expect(_label, findsOneWidget);
        expect(tester.takeException(), isNull);
        await shot(tester, 'b2v_solo_hover_hand_$tag');
        await mouse.removePointer();
        await _close(tester);
      });
    }
  }
}
