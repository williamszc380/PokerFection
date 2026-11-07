// Blackjack's screens at a sideways phone, an upright phone (browsers) and
// a PC, in English, Spanish and Chinese: the setup, a round with the coach,
// the offers, the end of a shoe and the guides all fit; buttons that can't
// be used are greyed out, not hidden; everything clickable answers the mouse.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/blackjack/app/blackjack_grading.dart';
import 'package:pokerfection/src/games/blackjack/app/blackjack_record.dart';
import 'package:pokerfection/src/games/blackjack/blackjack.dart';
import 'package:pokerfection/src/ui/games/blackjack/blackjack_controller.dart';
import 'package:pokerfection/src/ui/games/blackjack/blackjack_guides.dart';
import 'package:pokerfection/src/ui/games/blackjack/blackjack_screen.dart';
import 'package:pokerfection/src/ui/games/blackjack/blackjack_setup.dart';
import 'package:pokerfection/src/ui/games/blackjack/blackjack_table.dart';
import 'package:pokerfection/src/ui/games/blackjack/l10n/blackjack_strings.dart';
import 'package:pokerfection/src/ui/kit/coach_panel.dart';
import 'package:pokerfection/src/ui/kit/game_sounds.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';
import 'package:pokerfection/src/ui/kit/move_feedback.dart';

import '../../../kit/shots.dart';
import 'blackjack_scenes.dart';

/// The button of [action] (the panel's grid, or the offer row).
Finder actionButton(BlackjackAction action, {bool offer = false}) => find.descendant(
  of: find.byKey(ValueKey('${offer ? 'offer' : 'action'} ${action.name}')),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);

bool enabled(WidgetTester tester, Finder button) => tester.widget<ButtonStyleButton>(button).onPressed != null;

Future<TestGesture> mouse(WidgetTester tester) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: const Offset(1, 1));
  addTearDown(gesture.removePointer);
  return gesture;
}

SystemMouseCursor? cursorNow() =>
    RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1) as SystemMouseCursor?;

/// [finder]'s whole box is on a screen of [size].
void expectOnScreen(WidgetTester tester, Finder finder, Size size) {
  final rect = tester.getRect(finder);
  expect(
    rect.left >= -0.5 && rect.top >= -0.5 && rect.right <= size.width + 0.5 && rect.bottom <= size.height + 0.5,
    isTrue,
    reason: '$finder at $rect',
  );
}

/// The page's own (vertical) scroller, not a row of choices or a chart's.
Finder get pageScroller =>
    find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;

/// The screen itself doesn't scroll: no vertical scroller has anything to
/// scroll, except the coach's list (the kit's, which may hold more rows
/// than a sideways phone shows).
void expectNoPageScroll(WidgetTester tester) {
  final coachArea = find.ancestor(of: find.byType(CoachList), matching: find.byType(Scrollable));
  final allowed = coachArea.evaluate().toSet();
  for (final element in find.byType(Scrollable).evaluate()) {
    final state = (element as StatefulElement).state as ScrollableState;
    if (state.position.axis != Axis.vertical || allowed.contains(element)) continue;
    expect(state.position.maxScrollExtent, 0, reason: 'nothing on the game screen scrolls');
  }
}

void main() {
  setUpAll(loadShotFonts);
  setUp(() => GameSounds.output = (_) {});

  for (final language in AppLanguage.values) {
    final b = BlackjackStrings.forLanguage(language);
    final k = KitStrings.forLanguage(language);
    for (final size in gameSizes) {
      final tag = shotTag(size, language);

      testWidgets('setup at $tag: every rule fits, Start stays in view', (tester) async {
        await pumpShot(tester, const BlackjackSetup(), size: size, language: language, wrap: kitWrap(LastGames()));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expectOnScreen(tester, find.byKey(const ValueKey('start')), size);
        expect(find.text(b.preset(BlackjackPreset.standard)), findsOneWidget);
        // Small screens scroll the setup to its last rows.
        await tester.scrollUntilVisible(find.text(b.coachMode(CoachMode.fresh)), 120, scrollable: pageScroller);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a round with the coach at $tag: fits, no page scroll, the chart\'s play tagged', (tester) async {
        final game = await pumpGame(tester, size: size, language: language, settings: coachOn);
        expect(find.byKey(const ValueKey('deal')), findsOneWidget, reason: 'Deal between rounds');
        expectOnScreen(tester, find.byKey(const ValueKey('deal')), size);
        await play(tester, dealMove);
        expect(tester.takeException(), isNull);
        // 16 against a ten: Hit, Stand and Double; no pair, no surrender here.
        expect(game.coach!.lines.map((l) => l.move).toSet(), {'0:H', '0:S', '0:D'});
        expect(find.byType(CoachList), findsOneWidget);
        expect(find.descendant(of: find.byType(CoachList), matching: find.text(b.pickLabel)), findsOneWidget);
        for (final action in [BlackjackAction.hit, BlackjackAction.stand, BlackjackAction.double]) {
          expect(enabled(tester, actionButton(action)), isTrue, reason: '$action');
          expectOnScreen(tester, actionButton(action), size);
        }
        for (final action in [BlackjackAction.split, BlackjackAction.surrender]) {
          expect(actionButton(action), findsOneWidget, reason: 'greyed out, not hidden');
          expect(enabled(tester, actionButton(action)), isFalse, reason: '$action');
        }
        expectNoPageScroll(tester);
        await closeGame(tester);
      });

      testWidgets('offers and a split at $tag: insurance above the greyed decisions, two hands', (tester) async {
        final game = await pumpGame(tester, size: size, language: language, seed: seedInsurance);
        await play(tester, dealMove);
        expect(game.play.round!.phase, RoundPhase.insurance);
        expect(enabled(tester, actionButton(BlackjackAction.insurance, offer: true)), isTrue);
        expect(enabled(tester, actionButton(BlackjackAction.noInsurance, offer: true)), isTrue);
        for (final action in [BlackjackAction.hit, BlackjackAction.stand, BlackjackAction.double]) {
          expect(enabled(tester, actionButton(action)), isFalse, reason: 'the offer comes first: $action');
        }
        expect(find.text(b.action(BlackjackAction.noInsurance)), findsWidgets);
        expect(tester.takeException(), isNull);
        expectNoPageScroll(tester);
        await closeGame(tester);

        final eights = await pumpGame(tester, size: size, language: language, seed: seedEights);
        await play(tester, dealMove);
        expect(enabled(tester, actionButton(BlackjackAction.split)), isTrue);
        await tester.tap(actionButton(BlackjackAction.split));
        await settleGame(tester);
        expect(eights.play.round!.seats[playerSeat].hands, hasLength(2));
        expect(find.byKey(const ValueKey('hand 0')), findsOneWidget);
        expect(find.byKey(const ValueKey('hand 1')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await closeGame(tester);
      });

      testWidgets('the end of a shoe at $tag: the result, and New shoe', (tester) async {
        await pumpGame(
          tester,
          size: size,
          language: language,
          seed: seedSeen,
          settings: BlackjackSettings(rules: BlackjackRules.preset(BlackjackPreset.singleDeck)),
        );
        await playToEnd(tester);
        final game = gameOf(tester);
        expect(game.isOver, isTrue);
        final newShoe = find.widgetWithText(FilledButton, k.newShoe);
        expect(newShoe, findsOneWidget);
        expectOnScreen(tester, newShoe, size);
        final headline = game.play.net > 0 ? k.youWin : (game.play.net < 0 ? k.wins(b.dealerSeat) : k.draw);
        expect(find.text(headline), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(newShoe);
        await settleGame(tester);
        expect(gameOf(tester).isOver, isFalse);
        expect(gameOf(tester).record.moves, isEmpty);
        await closeGame(tester);
      });

      testWidgets('guides at $tag: the chart and the rules fit (they may scroll)', (tester) async {
        await pumpShot(
          tester,
          const BlackjackStrategyGuide(),
          size: size,
          language: language,
          wrap: kitWrap(LastGames()),
        );
        await settleGame(tester);
        expect(find.byKey(ValueKey('${b.hardTotals} 16')), findsOneWidget);
        await tester.scrollUntilVisible(find.byKey(const ValueKey('legend')), 200, scrollable: pageScroller);
        expect(tester.takeException(), isNull);
        await pumpShot(tester, const BlackjackRulesGuide(), size: size, language: language);
        await tester.pump();
        expect(find.text(b.rulesSections.first.$1), findsOneWidget);
        expect(tester.takeException(), isNull);
        await closeGame(tester);
      });
    }
  }

  group('Basic strategy guide', () {
    /// The letter in the chart's row [row] of table [title], column [column]
    /// (0 = dealer 2 ... 8 = dealer 10, 9 = ace).
    Future<String> cell(WidgetTester tester, String title, String row, int column) async {
      final rowFinder = find.byKey(ValueKey('$title $row'));
      await tester.scrollUntilVisible(rowFinder, 200, scrollable: pageScroller);
      final texts = find.descendant(of: rowFinder, matching: find.byType(Text));
      return [for (final e in texts.evaluate()) (e.widget as Text).data!][1 + column];
    }

    Future<void> showChart(WidgetTester tester, BlackjackRules rules) async {
      await pumpShot(
        tester,
        BlackjackStrategyGuide(rules: rules),
        size: const Size(1280, 800),
        wrap: kitWrap(LastGames()),
      );
      await settleGame(tester);
    }

    final b = BlackjackStrings.forLanguage(AppLanguage.english);

    testWidgets('6 decks, dealer hits soft 17, DAS, surrender: 16 vs 10 Rh, 11 vs A D, A7 vs 2 Ds', (tester) async {
      await showChart(tester, const BlackjackRules(dealerHitsSoft17: true, surrender: Surrender.late));
      expect(await cell(tester, b.hardTotals, '16', 8), 'Rh');
      expect(await cell(tester, b.hardTotals, '11', 9), 'D');
      expect(await cell(tester, b.softTotals, 'A,7', 0), 'Ds');
      await closeGame(tester);
    });

    testWidgets('the same game standing on soft 17 hits 11 vs A and stands on A7 vs 2 (the published S17 chart)', (
      tester,
    ) async {
      await showChart(tester, const BlackjackRules(surrender: Surrender.late));
      expect(await cell(tester, b.hardTotals, '16', 8), 'Rh');
      expect(await cell(tester, b.hardTotals, '11', 9), 'H');
      expect(await cell(tester, b.softTotals, 'A,7', 0), 'S');
      expect(await cell(tester, b.pairs, '8,8', 0), 'P');
      await closeGame(tester);
    });

    testWidgets('it opens on the last game\'s rules, and the rules bar changes the chart', (tester) async {
      final store = LastGames();
      store.save(
        newBlackjackRecord(
          rules: BlackjackRules.preset(BlackjackPreset.singleDeck),
          seed: 1,
          playerName: 'Player',
          dealerName: 'Dealer',
        ),
      );
      await pumpShot(tester, const BlackjackStrategyGuide(), size: const Size(1280, 800), wrap: kitWrap(store));
      await settleGame(tester);
      expect(find.text('${b.presetLabel}: ${b.preset(BlackjackPreset.singleDeck)}'), findsOneWidget);
      // Single deck, H17: 11 vs A doubles.
      expect(await cell(tester, b.hardTotals, '11', 9), 'D');
      // Back up to the rules bar (finding the cell scrolled it to the top).
      await tester.scrollUntilVisible(find.byKey(const ValueKey('h17')), -200, scrollable: pageScroller);
      await tester.tap(find.byKey(const ValueKey('h17')));
      await settleGame(tester);
      expect(find.text('${b.presetLabel}: —'), findsOneWidget, reason: 'no preset matches now');
      await closeGame(tester);
    });

    testWidgets('Chinese and Spanish letters come from the strings, with a legend', (tester) async {
      await pumpShot(
        tester,
        const BlackjackStrategyGuide(rules: BlackjackRules(surrender: Surrender.late)),
        size: const Size(1280, 800),
        language: AppLanguage.chinese,
        wrap: kitWrap(LastGames()),
      );
      await settleGame(tester);
      final zh = BlackjackStrings.forLanguage(AppLanguage.chinese);
      expect(await cell(tester, zh.hardTotals, '16', 8), '降要');
      await tester.scrollUntilVisible(find.byKey(const ValueKey('legend')), 200, scrollable: pageScroller);
      expect(find.text(zh.chartMeaning(ChartCode.doubleOrStand)), findsOneWidget);
      await closeGame(tester);
    });
  });

  group('the mouse and the keys', () {
    final b = BlackjackStrings.forLanguage(AppLanguage.english);

    testWidgets('every button answers the mouse with a hand cursor; greyed ones don\'t', (tester) async {
      await pumpGame(tester, size: const Size(1280, 800));
      await play(tester, dealMove);
      final pointer = await mouse(tester);
      await pointer.moveTo(tester.getCenter(actionButton(BlackjackAction.hit)));
      await tester.pumpAndSettle();
      expect(cursorNow(), SystemMouseCursors.click);
      await pointer.moveTo(tester.getCenter(actionButton(BlackjackAction.split)));
      await tester.pump();
      expect(cursorNow(), isNot(SystemMouseCursors.click), reason: 'Split is greyed out');
      await closeGame(tester);
    });

    testWidgets('hovering a coach row lights its button; tapping it never plays', (tester) async {
      final game = await pumpGame(tester, size: const Size(1280, 800), settings: coachOn);
      await play(tester, dealMove);
      final pointer = await mouse(tester);
      final standRow = find.descendant(of: find.byType(CoachList), matching: find.text('Stand'));
      await pointer.moveTo(tester.getCenter(standRow));
      await tester.pump();
      final button = tester.widget<ButtonStyleButton>(actionButton(BlackjackAction.stand));
      expect(button.style!.side!.resolve({})!.color, const Color(0xFFFFD54F));
      await tester.tap(standRow);
      await tester.pump();
      expect(game.record.moves, [dealMove], reason: 'the coach never plays a move');
      await pointer.moveTo(const Offset(1, 1));
      await tester.pump();
      expect(tester.widget<ButtonStyleButton>(actionButton(BlackjackAction.stand)).style!.side, isNull);
      await closeGame(tester);
    });

    testWidgets('between rounds the panel says how the round ended, not "Your turn"', (tester) async {
      final game = await pumpGame(tester, size: const Size(1280, 800));
      String status() => tester.widget<Text>(find.byKey(const ValueKey('status'))).data!;
      expect(status(), 'Your turn', reason: 'before the first deal there is no round to tell');
      await play(tester, dealMove);
      expect(status(), 'Your turn');
      await play(tester, move0(BlackjackAction.stand));
      final round = game.play.round!;
      expect(game.betweenRounds, isTrue);
      final net = round.result(playerSeat).net;
      final outcome = b.outcome(round.seats[playerSeat].hands.single.outcome);
      expect(status(), net == 0 ? outcome : '$outcome ${betsText(net)}');
      expect(status(), roundResultText(b, round));
      await closeGame(tester);
    });

    testWidgets("with the cards seen, the feedback names the count's play 'Count', as its coach row is tagged", (
      tester,
    ) async {
      final game = await pumpGame(
        tester,
        size: const Size(1280, 800),
        seed: seedSeen,
        settings: BlackjackSettings(
          rules: BlackjackRules.preset(BlackjackPreset.singleDeck),
          coachMode: CoachMode.seen,
        ),
      );
      await playChart(tester, 3);
      // 14 against a 2: the chart stands, the count hits. Stand, the chart's play.
      final countRow = game.coach!.lines.firstWhere((l) => l.tag == 'count');
      final chartPlay = game.coach!.pick;
      expect(countRow.move, isNot(chartPlay));
      await play(tester, chartPlay);
      final mark = game.record.marks.last!;
      expect(mark.bestTag, 'count');
      final feedback = find.byType(MoveFeedback);
      expect(find.descendant(of: feedback, matching: find.textContaining(b.tagLabel('count')!)), findsWidgets);
      expect(find.descendant(of: feedback, matching: find.textContaining(b.pickLabel)), findsNothing);
      await closeGame(tester);
    });

    testWidgets('keys: Enter deals, H hits, a key for a greyed button does nothing', (tester) async {
      final game = await pumpGame(tester, size: const Size(1280, 800));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settleGame(tester);
      expect(game.record.moves, [dealMove]);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await settleGame(tester);
      expect(game.record.moves, [dealMove], reason: '16 is not a pair');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await settleGame(tester);
      expect(game.record.moves, [dealMove, '0:H']);
      await closeGame(tester);
    });

    testWidgets('☰ Count shows the running count and is kept; greyed out with a continuous shuffler', (tester) async {
      final game = await pumpGame(tester, size: const Size(1280, 800));
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('checked')), findsNothing, reason: 'off: no check mark');
      await tester.tap(find.text('Count'));
      await tester.pumpAndSettle();
      expect(game.showCount, isTrue);
      expect(find.byKey(const ValueKey('count')), findsOneWidget);
      expect(game.record.extra['count'], isTrue);
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.ancestor(of: find.text('Count'), matching: find.byType(PopupMenuItem<VoidCallback>)),
          matching: find.byKey(const ValueKey('checked')),
        ),
        findsOneWidget,
        reason: 'on: checked',
      );
      await tester.tapAt(const Offset(5, 400));
      await tester.pumpAndSettle();
      await closeGame(tester);

      await pumpGame(
        tester,
        size: const Size(1280, 800),
        settings: const BlackjackSettings(rules: BlackjackRules(continuousShuffle: true)),
      );
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      final item = tester.widget<PopupMenuItem<VoidCallback>>(
        find.ancestor(of: find.text('Count'), matching: find.byType(PopupMenuItem<VoidCallback>)),
      );
      expect(item.enabled, isFalse);
      await tester.tapAt(const Offset(5, 400));
      await tester.pumpAndSettle();
      await closeGame(tester);
    });

    testWidgets('Free Play: the coach chip is greyed out and no coach shows', (tester) async {
      await pumpGame(tester, size: const Size(1280, 800), settings: const BlackjackSettings(training: false));
      await play(tester, dealMove);
      expect(find.byType(CoachList), findsNothing);
      final chip = tester.widget<FilterChip>(find.byKey(const ValueKey('coach chip')));
      expect(chip.onSelected, isNull);
      await closeGame(tester);
    });

    testWidgets('setup: penetration and Cards seen grey out with a continuous shuffler; Start opens the game', (
      tester,
    ) async {
      await pumpShot(tester, const BlackjackSetup(), size: const Size(1280, 800), wrap: kitWrap(LastGames()));
      await tester.pump();
      final b = BlackjackStrings.forLanguage(AppLanguage.english);
      ButtonSegment<Object?> segment(String text) => tester
          .widget<SegmentedButton<Object?>>(
            find.ancestor(of: find.text(text), matching: find.byWidgetPredicate((w) => w is SegmentedButton)),
          )
          .segments
          .firstWhere((s) => (s.label! as Text).data == text);
      await tester.scrollUntilVisible(find.text('75%'), 200, scrollable: pageScroller);
      expect(segment('75%').enabled, isTrue);
      expect(segment(b.coachMode(CoachMode.seen)).enabled, isTrue);
      await tester.tap(find.text(b.continuousShuffle));
      await tester.pump();
      expect(segment('75%').enabled, isFalse);
      expect(segment(b.coachMode(CoachMode.seen)).enabled, isFalse);
      await tester.scrollUntilVisible(
        find.text(KitStrings.forLanguage(AppLanguage.english).custom),
        -200,
        scrollable: pageScroller,
      );
      await tester.tap(find.byKey(const ValueKey('start')));
      await settleGame(tester);
      expect(find.byType(BlackjackScreen), findsOneWidget);
      expect(gameOf(tester).rules.continuousShuffle, isTrue);
      await closeGame(tester);
    });

    testWidgets('setup starts from the last game\'s choices', (tester) async {
      final store = LastGames();
      store.save(
        newBlackjackRecord(
          rules: BlackjackRules.preset(BlackjackPreset.european),
          seed: 1,
          playerName: 'Player',
          dealerName: 'Dealer',
          extra: const BlackjackSettings(coachMode: CoachMode.seen, training: false).extra,
        ),
      );
      await pumpShot(tester, const BlackjackSetup(), size: const Size(1280, 800), wrap: kitWrap(store));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('start')));
      await settleGame(tester);
      final game = gameOf(tester);
      expect(game.rules, BlackjackRules.preset(BlackjackPreset.european));
      expect(game.training, isFalse);
      expect(game.coachMode, CoachMode.seen);
      await closeGame(tester);
    });
  });
}
