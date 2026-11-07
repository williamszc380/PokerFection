// Choosing from the coach list, the same way in every game: one click on a
// row selects the decision (its button gets a bright ring), a double click
// makes it, and every legal decision is among the rows. Then the Training
// helpers about the dealer: ☰ Show cards turns the hole card up, and a tap
// on the dealer shows what the hole card could be.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/blackjack/app/blackjack_record.dart';
import 'package:pokerfection/src/games/blackjack/blackjack.dart';
import 'package:pokerfection/src/ui/games/blackjack/blackjack_controller.dart';
import 'package:pokerfection/src/ui/games/blackjack/blackjack_dealing.dart';
import 'package:pokerfection/src/ui/games/blackjack/l10n/blackjack_strings.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';
import 'package:pokerfection/src/ui/kit/coach_panel.dart';
import 'package:pokerfection/src/ui/kit/game_sounds.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';
import 'package:pokerfection/src/ui/kit/turn_controller.dart';

import '../../../kit/shots.dart';
import 'blackjack_scenes.dart';

final _en = BlackjackStrings.forLanguage(AppLanguage.english);

/// The button of [action] in the panel's grid (or the offer row).
Finder _button(BlackjackAction action, {bool offer = false}) => find.descendant(
  of: find.byKey(ValueKey('${offer ? 'offer' : 'action'} ${action.name}')),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);

/// The coach row that reads [text].
Finder _row(String text) => find.descendant(of: find.byType(CoachList), matching: find.text(text));

Finder get _ring => find.byKey(const ValueKey('chosen ring'));
Finder get _selectedRow => find.byKey(const ValueKey('selected row'));

Future<void> _doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tap(finder);
  await tester.pump();
}

/// The hole card's view on the felt (round [round]).
GameCardView _holeCard(WidgetTester tester, int round) => tester.widget<GameCardView>(
  find.byWidgetPredicate((w) => w is GameCardView && w.flightTag == dealerCardTag(round, 1)),
);

Finder _menuItem(String text) => find.ancestor(of: find.text(text), matching: find.byType(PopupMenuItem<VoidCallback>));

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadShotFonts);
  setUp(() => GameSounds.output = (_) {});

  group('a click on a coach row', () {
    testWidgets('selects the decision: its button gets a ring, its row is lit, nothing is played', (tester) async {
      final game = await pumpGame(tester, size: const Size(1280, 800), settings: coachOn);
      await play(tester, dealMove);
      expect(_ring, findsNothing);
      await tester.tap(_row('Stand'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(game.record.moves, [dealMove], reason: 'one click never plays');
      expect(game.chosen, move0(BlackjackAction.stand));
      expect(find.descendant(of: _ring, matching: _button(BlackjackAction.stand)), findsOneWidget);
      expect(find.descendant(of: _selectedRow, matching: find.text('Stand')), findsOneWidget);
      // Another row moves the selection there.
      await tester.tap(_row('Hit'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.descendant(of: _ring, matching: _button(BlackjackAction.hit)), findsOneWidget);
      expect(_ring, findsOneWidget);
      expect(game.record.moves, [dealMove]);
      await closeGame(tester);
    });

    testWidgets('then Enter makes it, and the ring goes with the move', (tester) async {
      final game = await pumpGame(tester, size: const Size(1280, 800), settings: coachOn);
      await play(tester, dealMove);
      await tester.tap(_row('Stand'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settleGame(tester);
      expect(game.record.moves, [dealMove, move0(BlackjackAction.stand)]);
      expect(_ring, findsNothing);
      expect(game.chosen, isNull);
      await closeGame(tester);
    });

    testWidgets('then its own button makes it too', (tester) async {
      final game = await pumpGame(tester, size: const Size(1280, 800), settings: coachOn);
      await play(tester, dealMove);
      await tester.tap(_row('Stand'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(_button(BlackjackAction.stand));
      await settleGame(tester);
      expect(game.record.moves.last, move0(BlackjackAction.stand));
      await closeGame(tester);
    });

    testWidgets('hovering only outlines the button (gold); it doesn\'t select', (tester) async {
      final game = await pumpGame(tester, size: const Size(1280, 800), settings: coachOn);
      await play(tester, dealMove);
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: const Offset(1, 1));
      addTearDown(pointer.removePointer);
      await pointer.moveTo(tester.getCenter(_row('Stand')));
      await tester.pump();
      expect(tester.widget<ButtonStyleButton>(_button(BlackjackAction.stand)).style!.side, isNotNull);
      expect(_ring, findsNothing);
      expect(game.chosen, isNull);
      await closeGame(tester);
    });
  });

  testWidgets('a double click on a coach row makes the decision', (tester) async {
    final game = await pumpGame(tester, size: const Size(1280, 800), settings: coachOn);
    await play(tester, dealMove);
    await _doubleTap(tester, _row('Stand'));
    await settleGame(tester);
    expect(game.record.moves, [dealMove, move0(BlackjackAction.stand)]);
    await closeGame(tester);
  });

  testWidgets('a double click while the cards are still flying in does nothing', (tester) async {
    final game = await pumpGame(tester, size: const Size(1280, 800), settings: coachOn);
    game.humanMove(dealMove);
    // The coach answers at once on the test's thread; the cards take longer.
    await tester.pump(const Duration(milliseconds: 20));
    expect(game.dealing.busy, isTrue);
    expect(game.playFromCoach(move0(BlackjackAction.stand)), isFalse);
    expect(game.record.moves, [dealMove]);
    await settleGame(tester);
    expect(game.playFromCoach(move0(BlackjackAction.stand)), isTrue);
    await settleGame(tester);
    await closeGame(tester);
  });

  group('every legal decision is among the rows', () {
    for (final size in gameSizes) {
      final tag = '${size.width.toInt()}x${size.height.toInt()}';
      testWidgets('a pair at a table with surrender: all five at $tag', (tester) async {
        const settings = BlackjackSettings(
          rules: BlackjackRules(surrender: Surrender.late),
          toggles: {'coach': true},
        );
        final game = await pumpGame(tester, size: size, settings: settings, seed: seedEights);
        await play(tester, dealMove);
        final legal = game.play.legalMoves();
        expect(legal, hasLength(5), reason: 'Hit, Stand, Double, Split, Surrender');
        expect(game.listedMoves(playerSeat), legal);
        for (final move in legal) {
          final action = parseHandMove(move)!.action;
          expect(_row(_en.action(action)), findsOneWidget, reason: '$action at $tag');
        }
        await closeGame(tester);
      });
    }

    testWidgets('the insurance offer: both answers', (tester) async {
      final game = await pumpGame(tester, size: const Size(568, 320), settings: coachOn, seed: seedInsurance);
      await play(tester, dealMove);
      expect(game.play.round!.phase, RoundPhase.insurance);
      expect(_row(_en.action(BlackjackAction.insurance)), findsOneWidget);
      expect(_row(_en.action(BlackjackAction.noInsurance)), findsOneWidget);
      await tester.tap(_row(_en.action(BlackjackAction.noInsurance)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.descendant(of: _ring, matching: _button(BlackjackAction.noInsurance, offer: true)), findsOneWidget);
      await closeGame(tester);
    });

    test('between rounds there is no decision to list (the deal is none)', () {
      final play = BlackjackPlay(const BlackjackRules(), shoeSeed: 1);
      expect(blackjackListedMoves(play), isEmpty);
      play.apply(dealMove);
      expect(blackjackListedMoves(play), play.legalMoves());
    });
  });

  group('☰ Show cards (Training)', () {
    testWidgets('turns the hole card face up; the coach\'s answer stays the same', (tester) async {
      final game = await pumpGame(tester, size: const Size(1280, 800), settings: coachOn);
      await play(tester, dealMove);
      expect(_holeCard(tester, 1).faceUp, isFalse);
      final before = [for (final l in game.coach!.lines) (l.move, l.value)];
      await _openMenu(tester);
      expect(tester.widget<PopupMenuItem<VoidCallback>>(_menuItem('Show cards')).enabled, isTrue);
      await tester.tap(find.text('Show cards'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(game.showOpponentCards, isTrue);
      expect(_holeCard(tester, 1).faceUp, isTrue);
      expect(game.record.extra[TurnController.showCardsKey], isTrue);
      expect([for (final l in game.coach!.lines) (l.move, l.value)], before, reason: 'the coach never sees it');
      // The next shoe from the setup keeps it.
      expect(BlackjackSettings.fromRecord(game.record).toggles[TurnController.showCardsKey], isTrue);
      await closeGame(tester);
    });

    testWidgets('is greyed out in Free Play, never hidden', (tester) async {
      await pumpGame(tester, size: const Size(1280, 800), settings: const BlackjackSettings(training: false));
      await play(tester, dealMove);
      await _openMenu(tester);
      expect(_menuItem('Show cards'), findsOneWidget);
      expect(tester.widget<PopupMenuItem<VoidCallback>>(_menuItem('Show cards')).enabled, isFalse);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await closeGame(tester);
    });
  });

  group('tapping the dealer (Training) shows the range', () {
    testWidgets('what the hole card could be, and the two-card totals', (tester) async {
      final game = await pumpGame(tester, size: const Size(1280, 800), seed: seedEights);
      await play(tester, dealMove);
      expect(game.canShowRange(dealerSeat), isTrue);
      await tester.tap(find.byKey(const ValueKey('range tap 1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('range sheet')), findsOneWidget);
      final k = KitStrings.forLanguage(AppLanguage.english);
      expect(find.text('${k.term(KitTerm.range)} · ${k.rangeTitle(_en.dealerSeat, 1)}'), findsOneWidget);
      final sheet = find.byKey(const ValueKey('range sheet'));
      for (final label in [_en.blackjackHand, '17–21', '12–16', '11 or less']) {
        expect(find.descendant(of: sheet, matching: find.text(label)), findsOneWidget, reason: label);
      }
      expect(find.byKey(const ValueKey('rank T 1')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('10')), findsOneWidget, reason: 'the tens read 10');
      await closeGame(tester);
    });

    testWidgets('the dealer is a plain seat in Free Play and before the first deal', (tester) async {
      final game = await pumpGame(tester, size: const Size(1280, 800));
      expect(find.byKey(const ValueKey('range tap 1')), findsNothing, reason: 'nothing dealt yet');
      await closeGame(tester);
      await pumpGame(tester, size: const Size(1280, 800), settings: const BlackjackSettings(training: false));
      await play(tester, dealMove);
      expect(find.byKey(const ValueKey('range tap 1')), findsNothing);
      expect(game.training, isTrue);
      await closeGame(tester);
    });

    testWidgets('at a table without a hole card there is nothing to work out', (tester) async {
      final game = await pumpGame(
        tester,
        size: const Size(1280, 800),
        settings: BlackjackSettings(rules: BlackjackRules.preset(BlackjackPreset.european)),
      );
      await play(tester, dealMove);
      expect(game.canShowRange(dealerSeat), isFalse);
      expect(find.byKey(const ValueKey('range tap 1')), findsNothing);
      await closeGame(tester);
    });
  });
}
