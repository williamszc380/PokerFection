import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/ui/games/big_two/l10n/big_two_strings.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';
import 'package:pokerfection/src/ui/kit/felt.dart';
import 'package:pokerfection/src/ui/kit/game_scaffold.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';
import 'package:pokerfection/src/ui/kit/table_pile.dart';

import 'nim.dart';
import 'shots.dart';

CardFace _c(int rank, int suit) => CardFace.suited(rank, suit);

/// A Big Two deal so far: 3 tricks, passes between the plays.
const _deal = [
  PilePlay(seat: 1, cards: [CardFace.suited(1, 1)], label: 'Single'),
  PilePlay(seat: 2, cards: [CardFace.suited(4, 0)], label: 'Single'),
  PilePlay(seat: 3, pass: true),
  PilePlay(seat: 0, cards: [CardFace.suited(9, 2)], label: 'Single'),
  PilePlay(seat: 1, pass: true),
  PilePlay(seat: 2, pass: true),
  PilePlay(seat: 3, pass: true),
  PilePlay(seat: 0, cards: [CardFace.suited(7, 0), CardFace.suited(7, 3)], label: 'Pair', trick: 1),
  PilePlay(seat: 1, cards: [CardFace.suited(10, 1), CardFace.suited(10, 2)], label: 'Pair', trick: 1),
  PilePlay(seat: 2, pass: true, trick: 1),
  PilePlay(seat: 3, cards: [CardFace.suited(11, 0), CardFace.suited(11, 1)], label: 'Pair', trick: 1),
  PilePlay(seat: 0, pass: true, trick: 1),
  PilePlay(seat: 1, pass: true, trick: 1),
  PilePlay(seat: 2, pass: true, trick: 1),
  PilePlay(
    seat: 3,
    cards: [
      CardFace.suited(2, 0),
      CardFace.suited(3, 2),
      CardFace.suited(4, 3),
      CardFace.suited(5, 1),
      CardFace.suited(6, 0),
    ],
    label: 'Straight',
    trick: 2,
  ),
  PilePlay(
    seat: 0,
    cards: [
      CardFace.suited(3, 1),
      CardFace.suited(4, 2),
      CardFace.suited(5, 3),
      CardFace.suited(6, 2),
      CardFace.suited(7, 1),
    ],
    label: 'Straight',
    trick: 2,
  ),
];

/// The indexes in [_deal] of the turns with cards.
final _played = [
  for (var i = 0; i < _deal.length; i++)
    if (_deal[i].hasCards) i,
];

/// 20 cards: the landlord's hand.
final _twenty = [
  for (var i = 0; i < 18; i++) CardFace.suited(i % 13, i ~/ 13 * 2 + i % 2),
  const CardFace.joker(big: false),
  const CardFace.joker(big: true),
];

List<String> _names(AppLanguage language) => [S.forLanguage(language).you, 'Ana', 'Ben', 'Chen'];

Widget _pile({List<PilePlay> plays = _deal, bool toBeat = true, AppLanguage language = AppLanguage.english}) =>
    Scaffold(
      body: FeltArea(
        child: Center(
          child: TablePile(plays: plays, names: _names(language), toBeat: toBeat, cardWidth: 40),
        ),
      ),
    );

/// A sample game screen: four seats round the pile, and the landlord's 20
/// cards fanned under the table, two of them picked.
Future<NimController> _sampleTable(WidgetTester tester, Size size, AppLanguage language) async {
  final game = NimController(jobs: Jobs.inline(extra: nimJobs), pile: 21, take: 5);
  await game.newGame();
  game.coachVisible = true;
  await tester.pump();
  game.humanMove('1');
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
  final names = _names(language);
  await pumpShot(
    tester,
    GameScaffold(
      title: S.forLanguage(language).bigTwo,
      strings: BigTwoStrings.forLanguage(language),
      controller: game,
      table: FeltArea(
        child: LayoutBuilder(
          builder: (context, box) {
            // As Big Two sizes the cards in the middle.
            final cardWidth = (box.maxWidth / 9).clamp(20.0, box.maxHeight / 4.6).clamp(20.0, 52.0);
            return Stack(
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: SeatBadge(name: names[2], cardsLeft: 6),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: SeatBadge(name: names[1], cardsLeft: 9),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SeatBadge(name: names[3], cardsLeft: 3, toAct: true),
                ),
                // Between the side seats.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 26),
                  child: Center(
                    child: TablePile(plays: _deal, names: names, cardWidth: cardWidth),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      bottom: Padding(
        padding: const EdgeInsets.fromLTRB(6, 2, 6, 4),
        child: HandFan(cards: _twenty, selected: const {6, 7}, onToggle: (_) {}),
      ),
      panel: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: FilledButton(onPressed: () {}, child: const Text('Play')),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(onPressed: () {}, child: const Text('Pass')),
            ),
          ],
        ),
      ),
    ),
    size: size,
    language: language,
  );
  await tester.pump();
  return game;
}

void main() {
  setUpAll(loadShotFonts);

  test("each play's offset and tilt is small, and the same every time", () {
    for (var i = 0; i < 40; i++) {
      final a = TablePile.mess(i, 40), b = TablePile.mess(i, 40);
      expect(a, b, reason: 'stable across redraws');
      expect(a.offset.dx.abs(), lessThanOrEqualTo(TablePile.strayX * 40));
      expect(a.offset.dy.abs(), lessThanOrEqualTo(TablePile.strayY * 40));
      expect(a.angle.abs(), lessThanOrEqualTo(TablePile.maxTurn));
    }
    final spots = {for (var i = 0; i < 10; i++) TablePile.mess(i, 40).offset};
    expect(spots, hasLength(10), reason: 'every play lies a little differently');
    expect(TablePile.mess(3, 40, seed: 1), isNot(TablePile.mess(3, 40, seed: 2)), reason: 'and every deal');
  });

  testWidgets('the pile keeps the last plays in sight, darker under the latest, which is on top and lit', (
    tester,
  ) async {
    await pumpShot(tester, _pile(), size: const Size(568, 320));
    expect(tester.takeException(), isNull);
    final shown = _played.sublist(_played.length - 6);
    for (final i in _played) {
      expect(find.byKey(ValueKey('pile play $i')), shown.contains(i) ? findsOneWidget : findsNothing);
    }
    // Painted in order: the latest last, on top of the rest.
    final stack = tester.widget<Stack>(
      find.ancestor(of: find.byKey(ValueKey('pile play ${_played.last}')), matching: find.byType(Stack)).first,
    );
    final keys = [for (final child in stack.children) child.key];
    expect(
      keys.indexOf(ValueKey('pile play ${_played.last}')),
      greaterThan(keys.indexOf(ValueKey('pile play ${shown[4]}'))),
    );
    bool darkened(int i) => find
        .descendant(of: find.byKey(ValueKey('pile play $i')), matching: find.byType(ColorFiltered))
        .evaluate()
        .isNotEmpty;
    expect(darkened(_played.last), isFalse, reason: 'the play to beat is bright');
    for (final i in shown.take(5)) {
      expect(darkened(i), isTrue, reason: 'earlier plays are darker');
    }
    // Earlier plays still show: some of their cards lie outside the latest's.
    final top = tester.getRect(find.byKey(ValueKey('pile play ${_played.last}')));
    final under = tester.getRect(find.byKey(ValueKey('pile play ${shown[4]}')));
    expect(top == under, isFalse);
    expect(find.text('Straight · Player'), findsOneWidget, reason: "the latest play's kind and maker");
    await shot(tester, 'pile_568x320');

    // Everyone passed on it: darkened like the rest, its maker leads next.
    await pumpShot(tester, _pile(toBeat: false), size: const Size(568, 320));
    expect(darkened(_played.last), isTrue);
  });

  testWidgets('a redraw leaves every play where it lay', (tester) async {
    await pumpShot(tester, _pile(plays: _deal.sublist(0, 11)), size: const Size(568, 320));
    final before = {
      for (final i in [0, 1, 3, 7]) i: tester.getRect(find.byKey(ValueKey('pile play $i'))),
    };
    await pumpShot(tester, _pile(plays: _deal.sublist(0, 11)), size: const Size(568, 320));
    for (final MapEntry(key: i, value: rect) in before.entries) {
      expect(tester.getRect(find.byKey(ValueKey('pile play $i'))), rect);
    }
  });

  testWidgets('the pile shows the hand under the mouse and lights up', (tester) async {
    await pumpShot(tester, _pile(), size: const Size(568, 320));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('pile'))));
    await tester.pumpAndSettle();
    expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.click);
    final box = tester.widget<AnimatedContainer>(
      find.descendant(of: find.byKey(const ValueKey('pile')), matching: find.byType(AnimatedContainer)),
    );
    expect((box.decoration! as BoxDecoration).color, isNot(Colors.transparent));
  });

  for (final language in AppLanguage.values) {
    for (final size in const [Size(568, 320), Size(390, 844), Size(1280, 800)]) {
      final tag = shotTag(size, language);
      testWidgets('at $tag, tapping the pile opens the history: every turn in order, by trick, closable', (
        tester,
      ) async {
        final k = KitStrings.forLanguage(language);
        final s = S.forLanguage(language);
        await pumpShot(
          tester,
          _pile(language: language),
          size: size,
          language: language,
        );
        await tester.tap(find.byKey(const ValueKey('pile')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('pile history')), findsOneWidget);
        expect(find.text(s.history), findsOneWidget);
        // The newest turn is in sight when it opens, at the bottom.
        final last = find.byKey(ValueKey('history ${_deal.length - 1}'));
        expect(last, findsOneWidget);
        final dialog = tester.getRect(find.byKey(const ValueKey('pile history')));
        expect(dialog.left >= 0 && dialog.right <= size.width && dialog.bottom <= size.height, isTrue);
        expect(tester.getRect(last).bottom, lessThanOrEqualTo(dialog.bottom));
        expect(find.text(k.trick(3)), findsOneWidget, reason: 'where the last trick begins');
        // Scrolled back to the start, every turn is there in order.
        await tester.drag(find.byType(ListView), const Offset(0, 2000));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('history 0')), findsOneWidget);
        expect(find.text(k.trick(1)), findsOneWidget);
        var previous = double.negativeInfinity;
        for (var i = 0; i < _deal.length; i++) {
          final row = find.byKey(ValueKey('history $i'));
          if (row.evaluate().isEmpty) continue;
          final top = tester.getRect(row).top;
          expect(top, greaterThan(previous), reason: 'turn $i after turn ${i - 1}');
          previous = top;
        }
        expect(find.text(k.pass), findsWidgets, reason: 'passes are listed too');
        expect(
          find.descendant(of: find.byKey(const ValueKey('history 0')), matching: find.text('Ana')),
          findsOneWidget,
        );
        final small = find.descendant(of: find.byKey(const ValueKey('history 0')), matching: find.byType(GameCardView));
        expect(tester.widget<GameCardView>(small).width, PileHistory.cardWidth, reason: 'cards drawn small');
        for (final text in tester.widgetList<Text>(
          find.descendant(of: find.byKey(const ValueKey('pile history')), matching: find.byType(Text)),
        )) {
          final paragraph = tester.renderObject<RenderParagraph>(find.byWidget(text));
          if (text.data != 'Chen') expect(paragraph.didExceedMaxLines, isFalse, reason: '"${text.data}" reads in full');
        }
        await shot(tester, 'pile_history_$tag');
        await tester.tap(find.byKey(const ValueKey('close history')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('pile history')), findsNothing);
        // Esc closes it too.
        await tester.tap(find.byKey(const ValueKey('pile')));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('pile history')), findsNothing);
      });

      testWidgets('a sample table at $tag: 20 cards fanned under the table, a messy pile, the history open', (
        tester,
      ) async {
        final game = await _sampleTable(tester, size, language);
        expect(tester.takeException(), isNull);
        final hand = tester.getRect(find.byKey(const ValueKey('hand area')));
        final cards = find.descendant(of: find.byType(HandFan), matching: find.byType(GameCardView));
        expect(cards, findsNWidgets(20));
        for (final card in tester.widgetList(cards)) {
          final rect = tester.getRect(find.byWidget(card));
          expect(rect.left >= hand.left && rect.right <= hand.right, isTrue, reason: 'the fan fits the table width');
        }
        expect(find.byKey(const ValueKey('pile')), findsOneWidget);
        await shot(tester, 'table_$tag');
        await tester.tap(find.byKey(const ValueKey('pile')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await shot(tester, 'table_history_$tag');
        await tester.pumpWidget(const SizedBox());
        game.dispose();
      });
    }
  }

  test('a turn of words (a bid) and a long play are kept as given', () {
    final bid = const PilePlay(seat: 2, label: 'Bid 2');
    expect(bid.hasCards, isFalse);
    expect(PilePlay(seat: 0, cards: [_c(1, 1), _c(2, 2)]).hasCards, isTrue);
  });
  /// Fight the Landlord's auction, then the first trick.
  const auction = [
    PilePlay(seat: 1, label: 'No bid', trick: -1, heading: 'Bidding'),
    PilePlay(seat: 2, label: 'Bid 2', trick: -1, heading: 'Bidding'),
    PilePlay(seat: 0, label: 'Bid 3', trick: -1, heading: 'Bidding'),
  ];

  testWidgets('turns that are not a trick (the bids) go under their own heading, the first trick under "Trick 1"', (
    tester,
  ) async {
    final k = KitStrings.forLanguage(AppLanguage.english);
    await pumpShot(
      tester,
      _pile(
        plays: [
          ...auction,
          PilePlay(seat: 0, cards: [_c(5, 0)], label: 'Single'),
          const PilePlay(seat: 1, pass: true),
        ],
      ),
      size: const Size(1280, 800),
    );
    await tester.tap(find.byKey(const ValueKey('pile')));
    await tester.pumpAndSettle();
    expect(find.text('Bidding'), findsOneWidget, reason: 'one heading over the three bids');
    expect(find.text(k.trick(1)), findsOneWidget);
    expect(find.text(k.trick(0)), findsNothing, reason: 'the bids are not numbered as a trick');
    final bidding = tester.getRect(find.text('Bidding'));
    final trick = tester.getRect(find.text(k.trick(1)));
    expect(bidding.top, lessThan(tester.getRect(find.byKey(const ValueKey('history 0'))).top));
    expect(trick.top, greaterThan(tester.getRect(find.byKey(const ValueKey('history 2'))).top));
    expect(trick.top, lessThan(tester.getRect(find.byKey(const ValueKey('history 3'))).top));
  });

  testWidgets('during the auction (words, no cards yet) the middle is an empty spot that opens the history', (
    tester,
  ) async {
    await pumpShot(tester, _pile(plays: auction), size: const Size(568, 320));
    final spot = find.byKey(const ValueKey('pile'));
    expect(spot, findsOneWidget);
    expect(find.byType(GameCardView), findsNothing, reason: 'nothing drawn on it');
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: tester.getCenter(spot));
    await tester.pump();
    expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.click);
    await tester.tap(spot);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pile history')), findsOneWidget);
    expect(find.text('Bid 2'), findsOneWidget);
  });

  testWidgets('a deal with no turns yet has nothing in the middle to tap', (tester) async {
    await pumpShot(tester, _pile(plays: const []), size: const Size(568, 320));
    expect(find.byKey(const ValueKey('pile')), findsNothing);
  });
}
