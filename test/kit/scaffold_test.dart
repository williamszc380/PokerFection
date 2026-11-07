import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/ui/games/big_two/l10n/big_two_strings.dart';
import 'package:pokerfection/src/ui/games/blackjack/l10n/blackjack_strings.dart';
import 'package:pokerfection/src/ui/games/doudizhu/l10n/doudizhu_strings.dart';
import 'package:pokerfection/src/ui/games/gomoku/l10n/gomoku_strings.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';
import 'package:pokerfection/src/ui/kit/coach_panel.dart';
import 'package:pokerfection/src/ui/kit/felt.dart';
import 'package:pokerfection/src/ui/kit/game_scaffold.dart';
import 'package:pokerfection/src/ui/kit/l10n/game_strings.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';
import 'package:pokerfection/src/ui/kit/move_feedback.dart';

import 'nim.dart';
import 'shots.dart';

/// The game names the top bar shows ("Blackjack" isn't in the app's
/// strings yet), with each game's strings.
List<(String, GameStrings)> _games(AppLanguage language) {
  final s = S.forLanguage(language);
  return [
    (s.gomoku, GomokuStrings.forLanguage(language)),
    (s.bigTwo, BigTwoStrings.forLanguage(language)),
    (s.fightTheLandlord, LandlordStrings.forLanguage(language)),
    (language == AppLanguage.chinese ? '二十一点' : 'Blackjack', BlackjackStrings.forLanguage(language)),
  ];
}

const _look = CoachLook(moveText: _take);
String _take(String move) => 'Take $move';

/// A placeholder card table: two bots and a trick on the felt.
Widget _feltTable() => const FeltArea(
      child: Stack(
        children: [
          Align(alignment: Alignment.topLeft, child: SeatBadge(name: 'Ana', cardsLeft: 9, toAct: true)),
          Align(alignment: Alignment.topRight, child: SeatBadge(name: 'Ben', cardsLeft: 13, role: 'Landlord')),
          Align(
            child: TrickRow(cards: [CardFace.suited(5, 0), CardFace.suited(5, 2)], label: 'Pair of 7s', cardWidth: 34),
          ),
        ],
      ),
    );

/// A placeholder board: a square of wood.
Widget _boardTable() => Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(margin: const EdgeInsets.all(8), color: const Color(0xFFD4A35F)),
      ),
    );

/// A placeholder hand of 13 cards.
Widget _hand() => Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: HandFan(cards: [for (var i = 0; i < 13; i++) CardFace.suited(i, i % 4)], selected: const {3, 4}),
    );

/// A placeholder row of action buttons.
Widget _buttons() => Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(child: FilledButton(onPressed: () {}, child: const Text('Play'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton(onPressed: () {}, child: const Text('Pass'))),
        ],
      ),
    );

/// Nim at the player's second turn: the first move was a Mistake (taking 1
/// of 21), the bot answered, and the coach rates all 5 takes. The coach
/// chip is on ([coach]; it starts off).
Future<NimController> _midGame(WidgetTester tester, {bool training = true, bool coach = true}) async {
  final game = NimController(jobs: Jobs.inline(extra: nimJobs), pile: 21, take: 5, training: training);
  await game.newGame();
  if (training && coach) game.coachVisible = true;
  await tester.pump();
  game.humanMove('1');
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
  return game;
}

Future<void> _close(WidgetTester tester, NimController game) async {
  await tester.pumpWidget(const SizedBox());
  game.dispose();
}

/// Think longer shows, and can be pressed: under the coach's moves, or
/// (compact) as an icon at the end of the status line.
void _expectThinkLonger(WidgetTester tester, {required bool compact}) {
  final button = find.byKey(const ValueKey('think longer'));
  expect(button, findsOneWidget, reason: 'never hidden');
  expect(
    find.descendant(of: find.byType(CoachList), matching: button),
    compact ? findsNothing : findsOneWidget,
    reason: compact ? 'no row of its own in the compact panel' : 'under the moves',
  );
  expect(tester.widget<ThinkLongerButton>(button).iconOnly, compact);
  expect(tester.widget<ThinkLongerButton>(button).enabled, isTrue);
  final rect = tester.getRect(button);
  final status = tester.getRect(find.byKey(const ValueKey('status')));
  if (compact) expect(rect.center.dy, moreOrLessEquals(status.center.dy, epsilon: 4), reason: 'on the status line');
}

Finder get _chip => find.byKey(const ValueKey('coach chip'));

Finder get _coachRows => find.descendant(of: find.byType(CoachList), matching: find.byType(InkWell));

void main() {
  setUpAll(loadShotFonts);

  for (final language in AppLanguage.values) {
    for (final size in shotSizes) {
      final tag = shotTag(size, language);
      // Compact: under 300 tall below the bar, or a panel under 240 tall (the
      // hand strip below it on a sideways phone).
      final compact = size.height < 400;
      // A board game at 592x360 too: its 316 under the bar has no room for
      // the whole grade card above the coach's moves.
      final boardCompact = size.height - (size.height < 500 ? 44 : 56) < GameScaffold.compactBelow;
      if (size == const Size(592, 360)) assert(boardCompact);

      testWidgets('a card game at $tag: everything fits${compact ? ', the panel compact' : ''}', (tester) async {
        final game = await _midGame(tester);
        final (title, strings) = _games(language)[3];
        await pumpShot(
          tester,
          GameScaffold(
            title: title,
            strings: strings,
            controller: game,
            table: _feltTable(),
            panel: _buttons(),
            bottom: _hand(),
            look: _look,
            status: KitStrings.forLanguage(language).net('+3.5'),
          ),
          size: size,
          language: language,
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(game.coach!.lines, hasLength(5));
        expect(game.lastMark, isNotNull);
        // The hand is under the table only, so the panel keeps the whole
        // height: room for 5 moves even when compact.
        expect(_coachRows, findsNWidgets(compact ? 5 : 5 + 1), reason: compact ? '5 rows' : '5 rows and Think longer');
        if (size.width > size.height) {
          final buttonsTop = tester.getRect(find.text('Play')).top;
          for (final row in tester.widgetList(_coachRows)) {
            expect(tester.getRect(find.byWidget(row)).bottom, lessThan(buttonsTop), reason: 'no scrolling to see it');
          }
        }
        final hand = tester.getRect(find.byKey(const ValueKey('hand area')));
        final table = tester.getRect(find.byType(FeltArea));
        final panel = tester.getRect(find.byKey(const ValueKey('status')));
        expect(hand.top, greaterThanOrEqualTo(table.bottom - 0.01), reason: 'the hand under the table');
        if (size.width > size.height) {
          expect(hand.left, moreOrLessEquals(table.left, epsilon: 0.01));
          expect(hand.right, lessThanOrEqualTo(panel.left), reason: 'as wide as the table, never under the panel');
          expect(tester.getRect(find.text('Play')).bottom, greaterThan(hand.top), reason: 'the panel runs down beside the hand');
        }
        for (final card in tester.widgetList(find.byType(GameCardView))) {
          final rect = tester.getRect(find.byWidget(card));
          expect(rect.left >= hand.left - 1 && rect.right <= hand.right + 1, isTrue, reason: 'the fan fits its width');
        }
        _expectThinkLonger(tester, compact: compact);
        expect(
          find.byWidgetPredicate((w) => w is MoveFeedback && w.inline),
          compact ? findsOneWidget : findsNothing,
          reason: 'the grade joins the status line in the compact panel',
        );
        expect(find.byWidgetPredicate((w) => w is MoveFeedback && !w.inline), compact ? findsNothing : findsOneWidget);
        for (final finder in [_chip, find.byKey(const ValueKey('status'))]) {
          final rect = tester.getRect(finder.first);
          expect(rect.left >= 0 && rect.right <= size.width && rect.bottom <= size.height, isTrue, reason: '$finder');
        }
        await shot(tester, 'scaffold_card_$tag');
        await _close(tester, game);
      });

      testWidgets('a board game at $tag: everything fits${boardCompact ? ', the panel compact' : ''}', (tester) async {
        final game = await _midGame(tester);
        final (title, strings) = _games(language)[0];
        await pumpShot(
          tester,
          GameScaffold(
            title: title,
            strings: strings,
            controller: game,
            table: _boardTable(),
            panel: _buttons(),
            look: _look,
            squareTable: true,
          ),
          size: size,
          language: language,
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        // Compact or not, a board game's panel has room for 5 moves (and
        // Think longer under them when not compact), each in sight above the
        // buttons.
        expect(_coachRows, findsNWidgets(boardCompact ? 5 : 6));
        final buttonsTop = tester.getRect(find.text('Play')).top;
        for (final row in tester.widgetList(_coachRows)) {
          expect(tester.getRect(find.byWidget(row)).bottom, lessThan(buttonsTop), reason: 'no scrolling to see it');
        }
        _expectThinkLonger(tester, compact: boardCompact);
        await shot(tester, 'scaffold_board_$tag');
        await _close(tester, game);
      });
    }

    testWidgets('${language.code}: at 568x320 the top bar shows every game\'s name and its whole coach label',
        (tester) async {
      for (final (title, strings) in _games(language)) {
        final game = await _midGame(tester);
        await pumpShot(
          tester,
          GameScaffold(title: title, strings: strings, controller: game, table: _feltTable(), panel: _buttons()),
          size: const Size(568, 320),
          language: language,
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        final label = tester.renderObject<RenderParagraph>(find.descendant(of: _chip, matching: find.text(strings.pickLabel)));
        expect(label.didExceedMaxLines, isFalse, reason: strings.pickLabel);
        expect(label.size.width, greaterThanOrEqualTo(label.getMaxIntrinsicWidth(double.infinity) - 0.5),
            reason: '"${strings.pickLabel}" is not cut');
        expect(find.text(title), findsOneWidget);
        final titleBox = tester.getRect(find.text(title));
        expect(titleBox.width, greaterThan(40), reason: '"$title" stays readable');
        expect(titleBox.right, lessThanOrEqualTo(tester.getRect(_chip).left));
        if (strings is BlackjackStrings) await shot(tester, 'scaffold_bar_${language.code}');
        await _close(tester, game);
      }
    });
  }

  testWidgets('the coach starts hidden; its chip shows and hides it, the grade shows either way, and the choice is kept',
      (tester) async {
    final game = await _midGame(tester, coach: false);
    final strings = GomokuStrings.forLanguage(AppLanguage.english);
    await pumpShot(
      tester,
      GameScaffold(title: 'Gomoku', strings: strings, controller: game, table: _boardTable(), panel: _buttons()),
      size: const Size(1280, 800),
    );
    expect(game.record.extra.containsKey('coach'), isFalse, reason: 'nothing chosen yet');
    expect(find.byType(CoachList), findsNothing, reason: "the best moves are the player's to ask for");
    expect(tester.widget<FilterChip>(_chip).selected, isFalse);
    expect(find.byType(MoveFeedback), findsOneWidget, reason: 'the last move is graded all the same');
    await tester.tap(_chip);
    await tester.pump();
    expect(find.byType(CoachList), findsOneWidget);
    expect(game.record.extra['coach'], isTrue);
    await tester.tap(_chip);
    await tester.pump();
    expect(find.byType(CoachList), findsNothing);
    expect(game.record.extra['coach'], isFalse);
    await tester.tap(_chip);
    await tester.pump();
    await game.newGame();
    await tester.pump();
    expect(game.coachVisible, isTrue, reason: 'the choice carries into the next game');
    await _close(tester, game);
  });

  testWidgets('in Free Play the coach chip is greyed out and nothing is graded', (tester) async {
    final game = await _midGame(tester, training: false);
    await pumpShot(
      tester,
      GameScaffold(
        title: 'Gomoku',
        strings: GomokuStrings.forLanguage(AppLanguage.english),
        controller: game,
        table: _boardTable(),
        panel: _buttons(),
      ),
      size: const Size(1280, 800),
    );
    final chip = tester.widget<FilterChip>(find.byType(FilterChip));
    expect(chip.onSelected, isNull);
    expect(find.byType(CoachList), findsNothing);
    expect(find.byType(MoveFeedback), findsNothing);
    expect(find.textContaining('Score'), findsNothing);
    await _close(tester, game);
  });

  testWidgets('☰ has New game, the game\'s items (greyed out, not hidden), Rules, Glossary and Leave', (tester) async {
    final game = await _midGame(tester);
    await pumpShot(
      tester,
      GameScaffold(
        title: 'Blackjack',
        strings: BlackjackStrings.forLanguage(AppLanguage.english),
        controller: game,
        table: _feltTable(),
        panel: _buttons(),
        newGameLabel: 'New shoe',
        menuItems: [GameMenuItem(icon: Icons.calculate, label: 'Count', onTap: () {}, enabled: false)],
      ),
      size: const Size(1280, 800),
    );
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    for (final item in ['New shoe', 'Count', 'Rules', 'Glossary', 'Leave']) {
      expect(find.text(item), findsOneWidget, reason: item);
    }
    final count = tester.widget<PopupMenuItem<VoidCallback>>(
      find.ancestor(of: find.text('Count'), matching: find.byType(PopupMenuItem<VoidCallback>)),
    );
    expect(count.enabled, isFalse);
    await tester.tap(find.text('Glossary'));
    await tester.pumpAndSettle();
    expect(find.text('Grades'), findsOneWidget, reason: "the kit's terms come first");
    Navigator.of(tester.element(find.text('Grades'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New shoe'));
    await tester.pumpAndSettle();
    expect(game.record.moves, isEmpty);
    expect(game.deals, 2);
    await _close(tester, game);
  });

  testWidgets('after a game, the panel offers the next one (Next deal in card games), and Enter starts it',
      (tester) async {
    final game = NimController(jobs: Jobs.inline(extra: nimJobs), pile: 3, rounds: true);
    await game.newGame();
    await tester.pump();
    game.humanMove('3');
    await tester.pump();
    await pumpShot(
      tester,
      GameScaffold(
        title: 'Big Two',
        strings: BigTwoStrings.forLanguage(AppLanguage.english),
        controller: game,
        table: _feltTable(),
        panel: _buttons(),
      ),
      size: const Size(568, 320),
    );
    expect(find.text('You win'), findsOneWidget);
    expect(find.text('Next deal'), findsOneWidget);
    expect(find.text('Play'), findsNothing, reason: "the game's buttons give way");
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(game.deals, 2);
    expect(find.text('Your turn'), findsOneWidget);
    await _close(tester, game);
  });

  testWidgets("the game's own headline replaces the kit's words, before and after the game ends", (tester) async {
    final game = NimController(jobs: Jobs.inline(extra: nimJobs), pile: 3, rounds: true);
    await game.newGame();
    await tester.pump();
    Widget screen(String? Function(BuildContext)? headline) => GameScaffold(
          title: 'Fight the Landlord',
          strings: LandlordStrings.forLanguage(AppLanguage.english),
          controller: game,
          table: _feltTable(),
          panel: _buttons(),
          headline: headline,
        );
    await pumpShot(tester, screen((context) => game.isOver ? 'Everyone passed' : null), size: const Size(1280, 800));
    expect(find.text('Your turn'), findsOneWidget, reason: "null: the kit's words");
    game.humanMove('3');
    await tester.pump();
    expect(find.text('Everyone passed'), findsOneWidget);
    expect(find.text('You win'), findsNothing);
    await _close(tester, game);
  });

  testWidgets('a ☰ toggle shows a check mark while on, and keeps its room while off', (tester) async {
    final game = await _midGame(tester);
    var count = false;
    late StateSetter rebuild;
    await pumpShot(
      tester,
      StatefulBuilder(builder: (context, setState) {
        rebuild = setState;
        return GameScaffold(
          title: 'Blackjack',
          strings: BlackjackStrings.forLanguage(AppLanguage.english),
          controller: game,
          table: _feltTable(),
          panel: _buttons(),
          menuItems: [
            GameMenuItem(icon: Icons.calculate, label: 'Count', checked: count, onTap: () => rebuild(() => count = !count)),
            GameMenuItem(icon: Icons.sort, label: 'Sort', onTap: () {}),
          ],
        );
      }),
      size: const Size(1280, 800),
    );
    final checks = find.byKey(const ValueKey('checked'));
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(checks, findsNothing);
    final off = tester.getRect(find.text('Count'));
    await tester.tap(find.text('Count'));
    await tester.pumpAndSettle();
    expect(count, isTrue);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(checks, findsOneWidget);
    expect(tester.getRect(find.text('Count')).width, off.width, reason: 'nothing moves');
    expect(tester.getRect(checks).center.dy, moreOrLessEquals(tester.getRect(find.text('Count')).center.dy, epsilon: 2));
    await tester.tap(find.text('Sort'));
    await tester.pumpAndSettle();
    await _close(tester, game);
  });

  testWidgets('the coach chip, ☰ and its items, and the button after a game show the hand under the mouse',
      (tester) async {
    final game = NimController(jobs: Jobs.inline(extra: nimJobs), pile: 3, rounds: true);
    await game.newGame();
    await tester.pump();
    await pumpShot(
      tester,
      GameScaffold(
        title: 'Big Two',
        strings: BigTwoStrings.forLanguage(AppLanguage.english),
        controller: game,
        table: _feltTable(),
        panel: _buttons(),
      ),
      size: const Size(1280, 800),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    Future<MouseCursor?> cursorOn(Finder finder) async {
      await mouse.moveTo(tester.getCenter(finder));
      await tester.pump();
      return RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);
    }

    expect(await cursorOn(_chip), SystemMouseCursors.click);
    expect(await cursorOn(find.text('Play')), SystemMouseCursors.click, reason: "the game's own buttons, by the theme");
    expect(await cursorOn(find.byIcon(Icons.menu)), SystemMouseCursors.click);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(await cursorOn(find.text('Rules')), SystemMouseCursors.click);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    game.humanMove('3');
    await tester.pump();
    expect(await cursorOn(find.text('Next deal')), SystemMouseCursors.click);
    await _close(tester, game);
  });

  testWidgets('the compact panel greys Think longer out when it cannot run, and it runs when it can', (tester) async {
    final game = await _midGame(tester);
    await pumpShot(
      tester,
      GameScaffold(
        title: 'Big Two',
        strings: BigTwoStrings.forLanguage(AppLanguage.english),
        controller: game,
        table: _feltTable(),
        panel: _buttons(),
        bottom: _hand(),
      ),
      size: const Size(800, 360),
    );
    final button = find.byKey(const ValueKey('think longer'));
    expect(tester.widget<ThinkLongerButton>(button).iconOnly, isTrue, reason: 'a phone at 800x360 is compact too');
    await tester.tap(button);
    await tester.pump();
    expect(game.canThinkLonger, isFalse, reason: 'the answer on show is the long one now');
    expect(find.byKey(const ValueKey('think longer')), findsOneWidget, reason: 'still there, greyed out');
    expect(tester.widget<ThinkLongerButton>(button).enabled, isFalse, reason: 'already thinking longer');
    await _close(tester, game);
  });

  testWidgets("while the game prepares, its buttons and keys work and the player's turn shows; a thin bar runs", (
    tester,
  ) async {
    final game = _SlowStartNim(jobs: Jobs.inline(extra: nimJobs));
    unawaited(game.newGame());
    await tester.pump();
    var played = 0;
    await pumpShot(
      tester,
      GameScaffold(
        title: 'Blackjack',
        strings: BlackjackStrings.forLanguage(AppLanguage.english),
        controller: game,
        table: _feltTable(),
        panel: FilledButton(onPressed: () => game.humanMove('1'), child: const Text('Deal')),
        shortcuts: {const SingleActivator(LogicalKeyboardKey.keyD): () => played++},
      ),
      size: const Size(1280, 800),
    );
    expect(game.preparing, isTrue);
    expect(find.text('Your turn'), findsOneWidget, reason: 'nobody waits for prepare()');
    expect(find.byType(LinearProgressIndicator), findsOneWidget, reason: 'a notice only');
    // Not greyed out: a tap reaches the button.
    await tester.tap(find.text('Deal'));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.pump();
    expect(game.record.moves.first, '1', reason: 'the button plays at once');
    expect(played, 1, reason: 'and the keys work');
    game.ready.complete();
    await tester.pump();
    await tester.pump();
    expect(game.preparing, isFalse);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await _close(tester, game);
  });
}

/// Nim whose start-up work (Blackjack's chart) the test finishes by hand.
class _SlowStartNim extends NimController {
  _SlowStartNim({required super.jobs});

  final ready = Completer<void>();

  @override
  Future<void> prepare() => ready.future;
}
