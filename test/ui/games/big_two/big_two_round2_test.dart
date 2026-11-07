// Big Two's second round: the coach list (a tap selects, a double tap
// plays, Pass always listed), Show cards in Training, an opponent's range
// on a tap, and the match (penalty points to a target, the scoreboard, New
// match), with the setup's Play to.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_match.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_record.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/kit/match.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_controller.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_range_view.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_setup.dart';
import 'package:pokerfection/src/ui/games/big_two/l10n/big_two_strings.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';
import 'package:pokerfection/src/ui/kit/turn_controller.dart';

import '../../../kit/shots.dart';
import 'big_two_test_util.dart';

Finder byKey(String key) => find.byKey(ValueKey(key));

final en = BigTwoStrings.forLanguage(AppLanguage.english);
final kit = KitStrings.forLanguage(AppLanguage.english);
final pass = BigTwoController.passMove;

/// A Training game with the coach shown.
BigTwoController coached({int seed = 3, Map<String, Object?> toggles = const {}, MatchTarget? match}) =>
    seededGame(seed: seed, toggles: {'coach': true, ...toggles}, match: match);

/// On to a turn of the player's where Pass is legal and the coach has
/// answered, its pick not Pass (so Pass has to be pinned to be listed).
Future<void> toPassTurn(WidgetTester tester, BigTwoController game, {bool pickNotPass = false}) async {
  for (var guard = 0; guard < 300; guard++) {
    await settleGame(tester);
    if (game.isOver) fail('the deal ended first');
    if (!game.myTurn) continue;
    final legal = game.state.legalMoves();
    if (legal.length == 1) {
      game.passTurn();
      continue;
    }
    final coach = game.coach;
    if (coach == null || game.coachThinking) continue;
    if (game.canPass && (!pickNotPass || coach.pick != pass)) return;
    game.humanMove(coach.pick);
  }
  fail('never reached a turn with Pass');
}

Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
}

PopupMenuItem<Object?> menuItem(WidgetTester tester, String label) => tester.widget<PopupMenuItem<Object?>>(
  find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is PopupMenuItem)),
);

void main() {
  setUpAll(loadShotFonts);

  group('the coach list', () {
    testWidgets('Pass is always among the rows when it is legal, with its value, even when far from the pick', (
      tester,
    ) async {
      final game = coached();
      await pumpGame(tester, game);
      await toPassTurn(tester, game, pickNotPass: true);
      expect(game.listedMoves(0), [pass]);
      final shown = game.coach!.shown(1).map((l) => l.move).toList();
      expect(shown, contains(pass), reason: 'one row asked for: the pick, plus Pass');
      expect(game.coach!.lineFor(pass)?.value, isNotNull);
      expect(find.byKey(ValueKey(pass)), findsOneWidget);
      await closeGame(tester);
    });

    testWidgets('Pass is not listed when the player leads (it is not legal then)', (tester) async {
      for (var seed = 1; seed < 40; seed++) {
        final game = coached(seed: seed);
        await pumpGame(tester, game);
        if (game.myTurn && game.state.current == null) {
          expect(game.listedMoves(0), isEmpty);
          await closeGame(tester);
          return;
        }
        await closeGame(tester);
      }
      fail('no seed let the player lead');
    });

    testWidgets('one tap on a play picks its cards and plays nothing; a second tap soon after plays it', (
      tester,
    ) async {
      final game = coached();
      await pumpGame(tester, game);
      await toPassTurn(tester, game);
      final move = game.coach!.shown(5).map((l) => l.move).firstWhere((m) => m != pass);
      final before = game.record.moves.length;
      await tester.tap(find.byKey(ValueKey(move)));
      await tester.pump(const Duration(seconds: 1));
      expect(game.record.moves.length, before, reason: 'a single tap never plays');
      expect(game.selected, bigTwoMoveCards(move).toSet(), reason: 'its cards are picked (they pop up)');
      expect(game.selectedMove, move);
      expect(byKey('selected row'), findsOneWidget, reason: 'its row is lit');
      await tester.tap(find.byKey(ValueKey(move)));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.byKey(ValueKey(move)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(game.record.moves[before], move, reason: 'a double tap plays it');
      await closeGame(tester);
    });

    testWidgets('one tap on Pass clears the pick and lights the Pass button; a double tap passes', (tester) async {
      final game = coached();
      await pumpGame(tester, game);
      await toPassTurn(tester, game);
      final play = game.coach!.shown(5).map((l) => l.move).firstWhere((m) => m != pass);
      game.selectMove(play);
      await tester.pump();
      final before = game.record.moves.length;
      await tester.tap(find.byKey(ValueKey(pass)));
      await tester.pump(const Duration(seconds: 1));
      expect(game.record.moves.length, before, reason: 'a single tap on Pass does not pass');
      expect(game.selected, isEmpty);
      expect(game.chosen, pass);
      expect(byKey('chosen ring'), findsOneWidget, reason: 'the Pass button is lit');
      expect(byKey('selected row'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey(pass)));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.byKey(ValueKey(pass)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(game.record.moves[before], pass);
      await closeGame(tester);
    });

    testWidgets('Enter plays a lit Pass; tapping a card by hand puts the light out', (tester) async {
      final game = coached();
      await pumpGame(tester, game);
      await toPassTurn(tester, game);
      game.selectMove(pass);
      await tester.pump();
      game.toggle(game.hand.first);
      await tester.pump();
      expect(game.chosen, isNull, reason: 'picking cards drops the lit Pass');
      expect(byKey('chosen ring'), findsNothing);
      game.clearSelection();
      game.selectMove(pass);
      await tester.pump();
      final before = game.record.moves.length;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(game.record.moves[before], pass);
      await closeGame(tester);
    });

    testWidgets('a play tapped after Pass lit puts the light out (the cards are the selection now)', (tester) async {
      final game = coached();
      await pumpGame(tester, game);
      await toPassTurn(tester, game);
      game.selectMove(pass);
      final play = game.coach!.shown(5).map((l) => l.move).firstWhere((m) => m != pass);
      game.selectMove(play);
      expect(game.chosen, isNull);
      expect(game.selectedMove, play);
      await closeGame(tester);
    });
  });

  group('Show cards (Training)', () {
    testWidgets('☰ Show cards turns the bots\' hands face up, and back to backs', (tester) async {
      final game = coached();
      await pumpGame(tester, game);
      await toMyPlayableTurn(tester, game);
      expect(byKey('seat faces'), findsNothing);
      expect(byKey('seat face rows'), findsNothing);
      await openMenu(tester);
      expect(menuItem(tester, kit.showCards).enabled, isTrue);
      await tester.tap(find.text(kit.showCards));
      await tester.pumpAndSettle();
      expect(game.showOpponentCards, isTrue);
      expect(game.record.extra[TurnController.showCardsKey], isTrue, reason: 'kept with the record, carried on');
      for (var seat = 1; seat < 4; seat++) {
        final shown = find.descendant(of: byKey('seat $seat'), matching: find.byType(GameCardView));
        expect(shown, findsNWidgets(game.state.countOf(seat)), reason: 'every card of seat $seat');
        expect(tester.widget<GameCardView>(shown.first).faceUp, isTrue);
      }
      await openMenu(tester);
      await tester.tap(find.text(kit.showCards));
      await tester.pumpAndSettle();
      expect(byKey('seat backs'), findsNWidgets(3));
      await closeGame(tester);
    });

    testWidgets('in Free Play the item is greyed out, not hidden, and nothing is shown', (tester) async {
      final game = seededGame(training: false, toggles: {TurnController.showCardsKey: true});
      await pumpGame(tester, game);
      await openMenu(tester);
      expect(menuItem(tester, kit.showCards).enabled, isFalse);
      await tester.tapAt(const Offset(2, 400));
      await tester.pumpAndSettle();
      expect(game.showOpponentCards, isFalse);
      expect(byKey('seat faces'), findsNothing);
      await closeGame(tester);
    });

    testWidgets('the coach never sees them: its job gets the position without the toggle', (tester) async {
      final game = coached(toggles: {TurnController.showCardsKey: true});
      await pumpGame(tester, game);
      await toMyPlayableTurn(tester, game);
      final request = game.coachRequest(game.record, 0, seed: 1);
      expect(((request.input as dynamic).record as Map).containsKey('extra'), isFalse);
      final range = game.rangeRequest(game.record, 1, seed: 1)!;
      expect(((range.input as dynamic).record as Map).containsKey('extra'), isFalse);
      expect((range.input as dynamic).viewer, 0, reason: 'the range is from the player\'s view');
      await closeGame(tester);
    });

    test('the toggle is carried into the next game by the setup', () {
      final store = LastGames();
      final game = seededGame(lastGames: store);
      addTearDown(game.dispose);
      game.newGame();
      game.showOpponentCards = true;
      final setup = BigTwoSetup.from(game.record);
      expect(setup.toggles[TurnController.showCardsKey], isTrue);
    });
  });

  group('an opponent\'s range', () {
    testWidgets('a tap on a bot opens its range: the ranks and the combinations, worked out from the player\'s view', (
      tester,
    ) async {
      final game = coached();
      await pumpGame(tester, game);
      await toMyPlayableTurn(tester, game);
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: const Offset(1, 1));
      addTearDown(pointer.removePointer);
      await pointer.moveTo(tester.getCenter(byKey('range tap 2')));
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.click,
        reason: 'a bot reads as clickable',
      );
      await tester.tap(byKey('range tap 2'));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(byKey('range sheet'), findsOneWidget);
      final range = game.rangeOf(2)!;
      expect(range.cards, game.state.countOf(2));
      expect(find.textContaining('Ben'), findsWidgets);
      for (final kind in ['pair', 'straight', 'flush', 'twos:1']) {
        expect(byKey('combo $kind'), findsOneWidget);
      }
      expect(find.text(en.kind(PlayKind.fullHouse)), findsOneWidget);
      expect(find.text(en.twosHeld(2)), findsOneWidget);
      await closeGame(tester);
    });

    testWidgets('Free Play has no ranges: the bots are not clickable', (tester) async {
      final game = seededGame(training: false);
      await pumpGame(tester, game);
      expect(byKey('range tap 1'), findsNothing);
      expect(game.canShowRange(1), isFalse);
      await closeGame(tester);
    });

    test('the range sheet names ranks and kinds as the cards and the guides do', () {
      expect(bigTwoRankLabel('T'), '10');
      expect(bigTwoRankLabel('2'), '2');
      expect(bigTwoComboLabel(en, 'quads'), en.kind(PlayKind.fourOfAKind));
      expect(bigTwoComboLabel(en, 'twos:3'), '2s: 3+');
      expect(bigTwoComboText('T-T'), '10 10');
      expect(bigTwoComboText('flush:s'), '♠ ×5');
      expect(bigTwoComboText('2h-2s'), '2♥ 2♠');
    });
  });

  group('the match', () {
    testWidgets('each deal adds the penalties to the totals; no session Net while the match keeps score', (
      tester,
    ) async {
      final game = coached();
      await pumpGame(tester, game);
      expect(game.match!.target, 100);
      expect(game.match!.winner, MatchWinner.lowest);
      expect(find.textContaining(kit.net('')), findsNothing);
      await playToEnd(tester, game);
      expect(game.match!.deals.single, bigTwoDealPoints(game.rules, game.state.result));
      expect(game.match!.totals[game.state.winner], 0);
      expect(byKey('panel scores'), findsOneWidget, reason: 'the scores between deals');
      await tester.tap(byKey('open scores'));
      await tester.pumpAndSettle();
      expect(byKey('scoreboard'), findsOneWidget);
      expect(find.text('Player'), findsWidgets, reason: 'the player\'s seat, in the app\'s language');
      await closeGame(tester);
    });

    testWidgets('once a total reaches the target the lowest total wins, and the button is New match', (tester) async {
      final game = coached(match: const MatchTarget(points: 5));
      await pumpGame(tester, game);
      for (var deal = 0; deal < 20 && !game.matchOver; deal++) {
        if (deal > 0) await game.nextRound();
        await playToEnd(tester, game);
      }
      expect(game.matchOver, isTrue);
      final match = game.match!;
      expect(match.totals.any((t) => t >= 5), isTrue);
      final words = match.leaders.contains(0) ? kit.youWinMatch : kit.winsMatch(game.seatName(match.leaders.first));
      expect(find.text(words), findsOneWidget);
      expect(find.text(kit.newMatch), findsOneWidget);
      await tester.tap(byKey('again'));
      await settleGame(tester);
      expect(game.match!.deals, isEmpty, reason: 'a new match');
      await closeGame(tester);
    });

    testWidgets('No limit plays no match: the session\'s Net shows instead', (tester) async {
      final game = coached(match: const MatchTarget());
      await pumpGame(tester, game);
      expect(game.match, isNull);
      expect(find.textContaining(kit.net(kit.pointsValue('0'))), findsOneWidget);
      await closeGame(tester);
    });

    test('a scaled target follows the table: two players with 13 each play to 45', () {
      final game = seededGame(
        rules: BigTwoRules.standard(players: 2, cardsEach: 13),
        match: const MatchTarget(points: 100, scale: true),
      );
      addTearDown(game.dispose);
      game.newGame();
      expect(game.match!.target, 45);
    });
  });

  group('the setup\'s Play to', () {
    Future<List<BigTwoSetup>> pumpSetup(WidgetTester tester, {BigTwoSetup? initial}) async {
      final started = <BigTwoSetup>[];
      await pumpShot(
        tester,
        BigTwoSetupScreen(initial: initial ?? BigTwoSetup.from(null), onStart: (_, s) => started.add(s)),
        size: const Size(1280, 800),
      );
      await tester.pump();
      return started;
    }

    // On a PC the setup has two columns: the table's choices on the left,
    // the rules and then Play to on the right; each is built as it scrolls.
    Finder column({required bool right}) {
      final columns = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
      return right ? columns.last : columns.first;
    }

    Future<void> tapIn(WidgetTester tester, String row, String label, {bool right = true}) async {
      final finder = find.descendant(of: byKey(row), matching: find.text(label));
      await tester.scrollUntilVisible(byKey(row), 100, scrollable: column(right: right));
      await Scrollable.ensureVisible(tester.element(byKey(row)), alignment: 0.3);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pump();
    }

    testWidgets('the standard is 100; a choice is kept and starts the game with it', (tester) async {
      final started = await pumpSetup(tester);
      await tapIn(tester, 'play to', '150');
      await tester.tap(byKey('start'));
      await tester.pump();
      expect(started.single.match, const MatchTarget(points: 150));
      expect(started.single.extra[BigTwoSetup.matchKey], {'points': 150, 'scale': false});
    });

    testWidgets('Pusoy Dos scoring counts wins: its own choices, the standard 10', (tester) async {
      final started = await pumpSetup(tester);
      await tapIn(tester, 'scoring', en.scoringName(BigTwoScoring.pusoyDos), right: false);
      await tester.scrollUntilVisible(byKey('play to'), 100, scrollable: column(right: true));
      expect(find.descendant(of: byKey('play to'), matching: find.text('20')), findsOneWidget);
      expect(find.descendant(of: byKey('play to'), matching: find.text('200')), findsNothing);
      await tester.tap(byKey('start'));
      await tester.pump();
      expect(started.single.match.points, 10);
    });

    testWidgets('Scale with players says what the target is at this table', (tester) async {
      await pumpSetup(
        tester,
        initial: BigTwoSetup(rules: BigTwoRules.standard(players: 2), level: KitLevel.easy),
      );
      expect(byKey('scaled target'), findsNothing);
      await tester.scrollUntilVisible(byKey('scale with players'), 100, scrollable: column(right: true));
      // Clear of the Start bar at the foot of the page.
      await Scrollable.ensureVisible(tester.element(byKey('scale with players')), alignment: 0.3);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: byKey('scale with players'), matching: find.byType(Switch)));
      await tester.pump();
      expect(find.text(en.scaledTarget(60)), findsOneWidget, reason: 'two players, 17 cards each');
      await tapIn(tester, 'play to', kit.noLimit);
      expect(byKey('scaled target'), findsNothing);
    });

    test('the record brings the last match choice back', () {
      final game = seededGame(match: const MatchTarget(points: 200, scale: true));
      addTearDown(game.dispose);
      game.newGame();
      expect(BigTwoSetup.from(game.record).match, const MatchTarget(points: 200, scale: true));
      final old = game.record.copyWith(extra: {...game.record.extra}..remove(BigTwoSetup.matchKey));
      expect(BigTwoSetup.from(old).match, const MatchTarget(points: 100), reason: 'an older record: the standard');
      expect(BigTwoRecord.rulesOf(old), game.rules);
    });
  });
}
