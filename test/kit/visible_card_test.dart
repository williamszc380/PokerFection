// A card everyone at the table can see (Fight the Landlord's face-up card,
// Big Two's starting card) carries an eye on its top-left corner and says
// so under the mouse or on a long press, without taking taps, picks or
// drags from the hand. Screenshots with --dart-define=SHOTS=<folder>.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';

import 'shots.dart';

/// Eight different cards: 3♣ 4♦ 5♥ 6♠ 7♣ 8♦ 9♥ 10♠.
final _eight = [for (var i = 0; i < 8; i++) CardFace.suited(i + 1, i % 4)];

const _label = 'Everyone can see this card';
final _mark = find.byKey(const ValueKey('visible mark'));
final _labelBox = find.byKey(const ValueKey('visible label'));

class _Game {
  List<CardFace> cards = [..._eight];
  final picked = <CardFace>{};
  final moves = <(int, int)>[];
  var background = 0;

  /// The cards everyone can see.
  final visible = <CardFace>{_eight[0], _eight[3]};
}

Future<_Game> _pump(WidgetTester tester, {Size hand = const Size(600, 140)}) async {
  final g = _Game();
  await pumpShot(
    tester,
    StatefulBuilder(
      builder: (context, setState) => Stack(
        children: [
          // Taps that reach under the hand (and its labels).
          Positioned.fill(
            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => g.background++),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox.fromSize(
              size: hand,
              child: HandFan(
                cards: g.cards,
                selected: {
                  for (final (i, c) in g.cards.indexed)
                    if (g.picked.contains(c)) i,
                },
                visibleToAll: {
                  for (final (i, c) in g.cards.indexed)
                    if (g.visible.contains(c)) i,
                },
                onToggle: (i) => setState(
                  () => g.picked.contains(g.cards[i]) ? g.picked.remove(g.cards[i]) : g.picked.add(g.cards[i]),
                ),
                onReorder: (from, to) => setState(() {
                  g.moves.add((from, to));
                  g.cards = moveCard(g.cards, from, to);
                }),
              ),
            ),
          ),
        ],
      ),
    ),
    size: Size(hand.width, hand.height + 120),
  );
  return g;
}

Finder _card(CardFace face) => find.byKey(ValueKey('$face#1'));

/// A point on the part of [face] in view (left of the next card).
Offset _onCard(WidgetTester tester, CardFace face) {
  final box = tester.getRect(_card(face));
  return Offset(box.left + box.width * 0.2, box.center.dy);
}

Future<TestGesture> _mouseAt(WidgetTester tester, Offset at) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: at);
  addTearDown(mouse.removePointer);
  await tester.pumpAndSettle();
  return mouse;
}

void main() {
  setUpAll(loadShotFonts);

  testWidgets('the eye shows only on the marked cards, face up', (tester) async {
    await _pump(tester);
    expect(_mark, findsNWidgets(2));
    for (final face in [_eight[0], _eight[3]]) {
      expect(find.descendant(of: _card(face), matching: _mark), findsOneWidget);
    }
    for (final face in [_eight[1], _eight[2], _eight[7]]) {
      expect(find.descendant(of: _card(face), matching: _mark), findsNothing);
    }
    // A back never carries it, nor a card that isn't marked.
    await pumpShot(
      tester,
      Row(
        children: [
          GameCardView(width: 40, face: _eight[0], faceUp: false, visibleToAll: true),
          GameCardView(width: 40, face: _eight[1]),
          GameCardView(width: 40, face: null, visibleToAll: true),
        ],
      ),
      size: const Size(400, 200),
    );
    expect(_mark, findsNothing);
  });

  testWidgets('the eye sits on the corner, above the rank: about 13 px on 27 px cards, 20 on big ones', (tester) async {
    expect(GameCardView.markSize(27), 13);
    expect(GameCardView.markSize(76), 20);
    await pumpShot(
      tester,
      Center(child: GameCardView(key: const ValueKey('card'), width: 27, face: _eight[7], visibleToAll: true)),
      size: const Size(200, 200),
    );
    final card = tester.getRect(find.byKey(const ValueKey('card')));
    final mark = tester.getRect(_mark);
    expect(mark.width, 13);
    // Mostly above the card's top edge, at its left: the rank below it stays clear.
    expect(mark.top, lessThan(card.top - 0.7 * mark.height));
    expect(mark.bottom, lessThanOrEqualTo(card.top + 0.2 * mark.height + 0.01));
    expect(mark.left, closeTo(card.left - 1.3, 0.01));
  });

  testWidgets('the label shows while the mouse is over a marked card, never over another', (tester) async {
    await _pump(tester);
    final mouse = await _mouseAt(tester, const Offset(5, 5));
    expect(find.text(_label), findsNothing);
    await mouse.moveTo(_onCard(tester, _eight[3]));
    await tester.pumpAndSettle();
    expect(find.text(_label), findsOneWidget);
    // Above the card, centered on it.
    final label = tester.getRect(_labelBox), card = tester.getRect(_card(_eight[3]));
    expect(label.bottom, lessThan(card.top));
    expect(label.center.dx, closeTo(card.center.dx, 1));
    await mouse.moveTo(_onCard(tester, _eight[5]));
    await tester.pumpAndSettle();
    expect(find.text(_label), findsNothing);
    await mouse.moveTo(_onCard(tester, _eight[0]));
    await tester.pumpAndSettle();
    expect(find.text(_label), findsOneWidget);
    await mouse.moveTo(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text(_label), findsNothing);
  });

  testWidgets('the label takes no taps: a tap on it reaches what lies under it', (tester) async {
    final g = await _pump(tester);
    await _mouseAt(tester, _onCard(tester, _eight[3]));
    final label = tester.getCenter(_labelBox);
    await tester.tapAt(label);
    await tester.pumpAndSettle();
    expect(g.background, 1);
    expect(g.picked, isEmpty);
  });

  testWidgets('a long press shows the label until the finger lifts, and picks nothing', (tester) async {
    final g = await _pump(tester);
    final finger = await tester.startGesture(_onCard(tester, _eight[3]));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(_label), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(_label), findsOneWidget);
    await finger.up();
    await tester.pumpAndSettle();
    expect(find.text(_label), findsNothing);
    expect(g.picked, isEmpty);
    expect(g.moves, isEmpty);
    // The next tap picks it as always.
    await tester.tapAt(_onCard(tester, _eight[3]));
    await tester.pumpAndSettle();
    expect(g.picked, {_eight[3]});
  });

  testWidgets('a long press on a card that is not marked shows nothing, and picks as before', (tester) async {
    final g = await _pump(tester);
    final finger = await tester.startGesture(_onCard(tester, _eight[5]));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text(_label), findsNothing);
    await finger.up();
    await tester.pumpAndSettle();
    expect(g.picked, {_eight[5]});
  });

  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    final by = kind == PointerDeviceKind.touch ? 'by touch' : 'with the mouse';

    testWidgets('$by: taps pick and unpick a marked card, no label left behind by touch', (tester) async {
      final g = await _pump(tester);
      await tester.tapAt(_onCard(tester, _eight[0]), kind: kind);
      await tester.pumpAndSettle();
      expect(g.picked, {_eight[0]});
      if (kind == PointerDeviceKind.touch) expect(find.text(_label), findsNothing);
      await tester.tapAt(_onCard(tester, _eight[0]) - Offset(0, tester.getSize(_card(_eight[0])).height * 0.2), kind: kind);
      await tester.pumpAndSettle();
      expect(g.picked, isEmpty);
      expect(g.moves, isEmpty);
    });

    testWidgets('$by: a marked card drags to a new place, the eye going with it', (tester) async {
      final g = await _pump(tester);
      final from = _onCard(tester, _eight[0]);
      final to = from + tester.getCenter(_card(_eight[6])) - tester.getCenter(_card(_eight[0]));
      final gesture = await tester.startGesture(from, kind: kind);
      for (var k = 1; k <= 10; k++) {
        await gesture.moveTo(Offset.lerp(from, to, k / 10)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      // No label while a card is dragged.
      expect(find.text(_label), findsNothing);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(g.moves, [(0, 6)]);
      expect(g.cards[6], _eight[0]);
      expect(find.descendant(of: _card(_eight[0]), matching: _mark), findsOneWidget);
      expect(g.picked, isEmpty);
    });
  }

  testWidgets('a finger held until the label shows can still drag the card; the label goes', (tester) async {
    final g = await _pump(tester);
    final from = _onCard(tester, _eight[3]);
    final finger = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text(_label), findsOneWidget);
    final to = from + tester.getCenter(_card(_eight[7])) - tester.getCenter(_card(_eight[3]));
    for (var k = 1; k <= 10; k++) {
      await finger.moveTo(Offset.lerp(from, to, k / 10)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text(_label), findsNothing);
    await finger.up();
    await tester.pumpAndSettle();
    expect(g.moves, [(3, 7)]);
    expect(g.picked, isEmpty);
  });

  testWidgets('the Sort button stays clear of the eye on the hand\'s first card, even picked', (tester) async {
    const size = Size(276, 70), corner = Size(60, 26);
    final plain = HandFanGeometry(20, size, 76, showing: 0.46, corner: corner);
    final marked = HandFanGeometry(20, size, 76, showing: 0.46, corner: corner, marked: {0});
    expect(plain.width, marked.width, reason: 'the cards keep their size');
    final eyeTop = marked.bounds(0).top - GameCardView.maxLift * marked.height - GameCardView.markRise(marked.width);
    expect(marked.corner!.bottom, lessThanOrEqualTo(eyeTop - HandFanGeometry.cornerGap + 0.01));
    expect(marked.corner!.top, lessThan(plain.corner!.top));
    // A mark elsewhere moves nothing.
    expect(HandFanGeometry(20, size, 76, showing: 0.46, corner: corner, marked: {12}).corner, plain.corner);
  });

  group('at a seat', () {
    Future<void> seat(WidgetTester tester, SeatHand hand) => pumpShot(
          tester,
          Center(child: SizedBox(width: 300, child: Center(child: hand))),
          size: const Size(400, 200),
        );

    testWidgets('without visible cards it lays out as before', (tester) async {
      await seat(tester, const SeatHand(count: 10, cardWidth: 30));
      expect(tester.getSize(find.byKey(const ValueKey('seat backs'))).width, closeTo(30 + 5 * 0.32 * 30, 0.01));
      await seat(tester, SeatHand(count: 4, faces: _eight.sublist(0, 4), cardWidth: 30));
      expect(tester.getSize(find.byKey(const ValueKey('seat faces'))).width, closeTo(30 + 3 * 0.45 * 30, 0.01));
      expect(_mark, findsNothing);
    });

    testWidgets('a visible card shows face up after the backs, whole, with the eye and the label', (tester) async {
      await seat(tester, SeatHand(count: 17, cardWidth: 30, visibleToAll: [_eight[4]]));
      final cards = tester.widgetList<GameCardView>(find.byType(GameCardView)).toList();
      expect(cards, hasLength(7), reason: '6 backs, then the visible card');
      expect([for (final c in cards) c.faceUp], [...List.filled(6, false), true]);
      expect(cards.last.face, _eight[4]);
      expect(_mark, findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('seat backs'))).width, closeTo(30 + 6 * 0.32 * 30, 0.01));
      final mouse = await _mouseAt(tester, tester.getCenter(find.byWidget(cards.last)));
      expect(find.text(_label), findsOneWidget);
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(find.text(_label), findsNothing);
    });

    testWidgets('among faces shown, the visible ones carry the eye where they are', (tester) async {
      await seat(tester, SeatHand(count: 5, faces: _eight.sublist(0, 5), cardWidth: 30, visibleToAll: [_eight[2]]));
      expect(_mark, findsOneWidget);
      expect(find.descendant(of: find.byWidgetPredicate((w) => w is GameCardView && w.face == _eight[2]), matching: _mark), findsOneWidget);
    });

    testWidgets('a long press shows the label at a seat too', (tester) async {
      await seat(tester, SeatHand(count: 3, cardWidth: 30, visibleToAll: [_eight[4]]));
      final finger = await tester.startGesture(tester.getCenter(find.byWidgetPredicate((w) => w is GameCardView && w.faceUp)));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text(_label), findsOneWidget);
      await finger.up();
      await tester.pumpAndSettle();
      expect(find.text(_label), findsNothing);
    });
  });

  test('the label in English, Spanish and Chinese', () {
    expect([for (final l in AppLanguage.values) KitStrings.forLanguage(l).visibleToAll], [
      'Everyone can see this card',
      'Todos ven esta carta',
      '所有人都能看到这张牌',
    ]);
  });

  // A table as the card games lay it out: an opponent's seat at the top
  // with their face-up card among backs, the player's 20 cards fanned
  // under the felt (about 27 px wide on a sideways phone), the first one
  // and one in the middle marked, the mouse over the middle one.
  for (final size in const [Size(568, 320), Size(900, 420), Size(1280, 800)]) {
    for (final language in AppLanguage.values) {
      testWidgets('shot: a hand with a marked card, hovered, ${shotTag(size, language)}', (tester) async {
        final hand = [
          for (var i = 0; i < 20; i++) CardFace.suited((i * 52 ~/ 20) ~/ 4, (i * 52 ~/ 20) % 4),
        ];
        final phone = size.width < 700;
        final panel = phone ? size.width * 0.42 : size.width * 0.3;
        final handBox = Size(size.width - panel - 16, phone ? 70 : size.height * 0.24);
        await pumpShot(
          tester,
          Scaffold(
            backgroundColor: const Color(0xFF12171B),
            body: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1F6B45),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: const Color(0xFF5A3A22), width: 5),
                          ),
                          alignment: Alignment.topCenter,
                          padding: const EdgeInsets.only(top: 18),
                          child: SeatHand(
                            count: 17,
                            cardWidth: phone ? 24 : 40,
                            visibleToAll: [const CardFace.suited(12, 2)],
                          ),
                        ),
                      ),
                      SizedBox.fromSize(
                        size: handBox,
                        child: HandFan(
                          cards: hand,
                          selected: const {3},
                          visibleToAll: const {0, 9},
                          onToggle: (_) {},
                          onReorder: (_, _) {},
                          sortOrder: HandOrder.rank,
                          onSort: () {},
                          maxCardWidth: 76,
                          showing: 0.46,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
                Container(width: panel, color: const Color(0xFF1B2328)),
              ],
            ),
          ),
          size: size,
          language: language,
        );
        await tester.pumpAndSettle();
        final card = find.byKey(ValueKey('${hand[9]}#1'));
        await _mouseAt(tester, tester.getRect(card).topLeft + Offset(tester.getSize(card).width * 0.2, tester.getSize(card).height * 0.5));
        expect(find.text(KitStrings.forLanguage(language).visibleToAll), findsOneWidget);
        expect(tester.takeException(), isNull);
        await shot(tester, 'eye_${shotTag(size, language)}');
        // As a phone's screen shows it, three pixels to one.
        if (size.width < 700) await shot(tester, 'eye_${shotTag(size, language)}_x3', pixelRatio: 3);
      });
    }
  }
}
