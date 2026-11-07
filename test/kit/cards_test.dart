import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;
import 'package:pokerfection/src/ui/widgets/card_view.dart';

import 'shots.dart';

/// 20 cards: the most a hand holds (the landlord's).
final _twenty = [
  for (var i = 0; i < 18; i++) CardFace.suited(i % 13, i ~/ 13 * 2),
  const CardFace.joker(big: false),
  const CardFace.joker(big: true),
];

void main() {
  setUpAll(loadShotFonts);

  testWidgets('jokers are drawn with JOKER down the corner; other faces and backs are poker\'s cards', (tester) async {
    await pumpShot(
      tester,
      const Scaffold(
        body: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GameCardView(width: 60, face: CardFace.joker(big: true)),
              GameCardView(width: 60, face: CardFace.joker(big: false)),
              GameCardView(width: 60, face: CardFace.suited(12, 3)),
              GameCardView(width: 60, face: CardFace.joker(big: true), faceUp: false),
            ],
          ),
        ),
      ),
      size: const Size(400, 200),
    );
    expect(find.text('K'), findsNWidgets(2), reason: 'J-O-K-E-R down the two face-up jokers');
    expect(find.byType(CardView), findsNWidgets(2), reason: 'the ace of spades, and the face-down joker');
    await shot(tester, 'cards_jokers');
  });

  test('converting a game\'s cards: rank in poker order, suit 0 clubs to 3 spades', () {
    expect(const CardFace.suited(0, 0).toString(), '2c');
    expect(const CardFace.suited(12, 3).toString(), 'As');
    expect(const CardFace.joker(big: true).isJoker, isTrue);
    expect(const CardFace.joker(big: true), isNot(const CardFace.joker(big: false)));
  });

  testWidgets('a hand of 20 fits a 568-wide phone, at least 18% of every card showing', (tester) async {
    await pumpShot(
      tester,
      Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(width: 568, height: 83, child: HandFan(cards: _twenty)),
        ),
      ),
      size: const Size(568, 200),
    );
    final rects = [for (final e in find.byType(GameCardView).evaluate()) tester.getRect(find.byWidget(e.widget))];
    expect(rects, hasLength(20));
    for (final r in rects) {
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(568));
    }
    final width = rects.first.width;
    for (var i = 1; i < rects.length; i++) {
      expect(rects[i].left - rects[i - 1].left, greaterThanOrEqualTo(width * HandFan.minShowing - 0.01));
    }
    expect(width, greaterThan(30), reason: 'still readable');
    await shot(tester, 'cards_fan20');
  });

  test("a fanned hand of 20 fits the table's width on a sideways phone, on a gentle arc with a slight tilt", () {
    // The hand under the table at 568x320: about 276 x 82 inside its padding.
    const size = Size(276, 82);
    final g = HandFanGeometry(20, size, 72);
    expect(g.width, greaterThan(40), reason: 'still readable');
    for (var i = 0; i < 20; i++) {
      final c = g.center(i);
      // The tilted card's corners stay inside the hand's box.
      final reach = g.width / 2 * cos(g.angle(i)).abs() + g.height / 2 * sin(g.angle(i)).abs();
      expect(c.dx - reach, greaterThanOrEqualTo(-0.01));
      expect(c.dx + reach, lessThanOrEqualTo(size.width + 0.01));
      final below = g.height / 2 * cos(g.angle(i)).abs() + g.width / 2 * sin(g.angle(i)).abs();
      expect(c.dy + below, lessThanOrEqualTo(size.height + 0.01));
      if (i > 0) {
        expect(c.dx - g.center(i - 1).dx, greaterThanOrEqualTo(g.width * HandFan.minShowing - 0.01));
        expect(g.angle(i), greaterThan(g.angle(i - 1)), reason: 'each a little more turned');
      }
    }
    expect(g.angle(0), closeTo(-g.angle(19), 1e-9));
    expect(g.angle(19), lessThanOrEqualTo(HandFan.maxTilt + 1e-9), reason: 'a slight tilt');
    expect(g.angle(19), greaterThan(0.02), reason: 'but a fan');
    expect(g.center(0).dy, greaterThan(g.center(10).dy), reason: 'the ends dip: an arc');
    expect(g.center(0).dy - g.center(10).dy, lessThanOrEqualTo(HandFan.maxDrop * g.height + 0.01));
    expect(
      g.center(10).dy - g.height / 2,
      greaterThanOrEqualTo(g.height * GameCardView.maxLift - 0.5),
      reason: 'room for a picked card to pop up, under the mouse too',
    );
    // A game that wants more of each card in view (Big Two: 35%) gets
    // smaller cards rather than more overlap.
    final roomy = HandFanGeometry(13, const Size(232, 82), 76, showing: 0.35);
    expect(roomy.step / roomy.width, greaterThanOrEqualTo(0.35 - 1e-9));
    // Unfanned: a straight row, as before.
    final row = HandFanGeometry(20, size, 72, fanned: false);
    expect([for (var i = 0; i < 20; i++) row.angle(i)].every((a) => a == 0), isTrue);
    expect(row.center(0).dy, row.center(19).dy);
    expect(HandFan.layout(20, size, 72), (
      width: row.width,
      step: row.step,
    ), reason: 'layout() is the row unless asked');
  });

  testWidgets('in a fan of 20, the visible strip of each card taps that card, and the cards keep their order', (
    tester,
  ) async {
    final selected = <int>{};
    await pumpShot(
      tester,
      StatefulBuilder(
        builder: (context, setState) => Align(
          alignment: Alignment.bottomLeft,
          child: SizedBox(
            width: 276,
            height: 82,
            child: HandFan(
              cards: _twenty,
              selected: selected,
              onToggle: (i) => setState(() => selected.contains(i) ? selected.remove(i) : selected.add(i)),
            ),
          ),
        ),
      ),
      size: const Size(568, 320),
    );
    final g = HandFanGeometry(20, const Size(276, 82), 72);
    final origin = tester.getTopLeft(find.byType(HandFan));
    // A point on card i's own strip: left of where the next card starts.
    Offset strip(int i) {
      final along = Offset(cos(g.angle(i)), sin(g.angle(i)));
      return origin +
          g.center(i) +
          along * (-g.width / 2 + g.step * 0.4) +
          Offset(-sin(g.angle(i)), cos(g.angle(i))) * (-g.height * 0.3);
    }

    final xs = [for (var i = 0; i < 20; i++) tester.getCenter(find.byKey(ValueKey('${_twenty[i]}#1'))).dx];
    expect(xs, orderedEquals([...xs]..sort()), reason: "left to right in the order given (sorting is the game's)");
    for (final i in [0, 7, 13, 19]) {
      await tester.tapAt(strip(i));
      await tester.pump();
      expect(selected, {i}, reason: 'card $i');
      await tester.tapAt(strip(i) + Offset(0, -g.height * GameCardView.selectedLift * 0.5));
      await tester.pump();
      expect(selected, isEmpty, reason: 'card $i, standing up, taps off again');
    }
    // Picking several cards is a tap on each.
    for (var i = 4; i <= 9; i++) {
      await tester.tapAt(strip(i));
      await tester.pump();
    }
    expect(selected, {4, 5, 6, 7, 8, 9});
    // Picked cards stand up (each along its own tilt).
    final slide = tester.widget<AnimatedSlide>(
      find.descendant(of: find.byKey(ValueKey('${_twenty[5]}#1')), matching: find.byType(AnimatedSlide)),
    );
    expect(slide.offset.dy, lessThanOrEqualTo(-GameCardView.selectedLift));
    await shot(tester, 'cards_fan20_selected');
  });

  testWidgets('under the mouse, the visible strip of a fanned card shows the hand and lifts that card', (tester) async {
    await pumpShot(
      tester,
      Align(
        alignment: Alignment.bottomLeft,
        child: SizedBox(
          width: 276,
          height: 82,
          child: HandFan(cards: _twenty, onToggle: (_) {}),
        ),
      ),
      size: const Size(568, 320),
    );
    final g = HandFanGeometry(20, const Size(276, 82), 72);
    final origin = tester.getTopLeft(find.byType(HandFan));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    final along = Offset(cos(g.angle(11)), sin(g.angle(11)));
    await mouse.moveTo(origin + g.center(11) + along * (-g.width / 2 + g.step * 0.4));
    await tester.pumpAndSettle();
    expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.click);
    double lift(int i) => tester
        .widget<AnimatedSlide>(
          find.descendant(of: find.byKey(ValueKey('${_twenty[i]}#1')), matching: find.byType(AnimatedSlide)),
        )
        .offset
        .dy;
    expect(lift(11), lessThan(0), reason: 'the card under the mouse');
    expect(lift(10), 0);
    expect(lift(12), 0, reason: 'not the one on top of it');
  });

  for (final speed in PlaybackSpeed.values) {
    testWidgets(
      'a picked card pops up a fifth of its height with no outline; rising and turning over at ${speed.label}',
      (tester) async {
        var picked = false;
        var faceUp = false;
        late StateSetter set;
        await pumpShot(
          tester,
          Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (context, setState) {
                  set = setState;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GameCardView(
                        key: const ValueKey('picked'),
                        width: 60,
                        face: const CardFace.suited(8, 2),
                        selected: picked,
                        onTap: () {},
                      ),
                      const GameCardView(key: ValueKey('down'), width: 60, face: CardFace.suited(7, 2), onTap: _noop),
                      GameCardView(
                        key: const ValueKey('flip'),
                        width: 60,
                        face: const CardFace.suited(5, 0),
                        faceUp: faceUp,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          size: const Size(400, 240),
          wrap: (app) => AppSettingsScope(settings: AppSettings()..speed = speed, child: app),
        );
        AnimatedSlide slide(String key) => tester.widget<AnimatedSlide>(
          find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(AnimatedSlide)),
        );
        expect(slide('picked').duration, GameCardView.liftTime * speed.factor);
        if (speed == PlaybackSpeed.instant) expect(slide('picked').duration, Duration.zero);
        final down = tester.getRect(find.byKey(const ValueKey('down')));
        set(() => picked = true);
        await tester.pump();
        if (speed != PlaybackSpeed.instant) {
          // On its way up.
          await tester.pump(GameCardView.liftTime * speed.factor * 0.5);
          final card = tester.getRect(
            find.descendant(of: find.byKey(const ValueKey('picked')), matching: find.byType(CardView)),
          );
          expect(card.top, lessThan(down.top));
          expect(card.top, greaterThan(down.top - down.height * GameCardView.selectedLift));
        }
        await tester.pump(GameCardView.liftTime);
        final card = tester.getRect(
          find.descendant(of: find.byKey(const ValueKey('picked')), matching: find.byType(CardView)),
        );
        expect(card.top, closeTo(down.top - down.height * GameCardView.selectedLift, 0.5), reason: 'about a fifth up');
        expect(GameCardView.selectedLift, closeTo(0.2, 0.02));
        // No outline: the picked card draws exactly the boxes of the one left down.
        List<String> boxes(String key) => [
          for (final e
              in find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(DecoratedBox)).evaluate())
            '${(e.widget as DecoratedBox).decoration}',
        ];
        expect(boxes('picked'), boxes('down'));
        // Turning over: poker's 400 ms at Normal, quicker at Fast, at once at Instant.
        expect(
          tester
              .widget<AnimatedSwitcher>(
                find.descendant(of: find.byKey(const ValueKey('flip')), matching: find.byType(AnimatedSwitcher)),
              )
              .duration,
          CardView.flipTime * speed.factor,
        );
        set(() => faceUp = true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));
        final turning = find.descendant(of: find.byKey(const ValueKey('flip')), matching: find.byType(Transform));
        expect(
          turning,
          speed == PlaybackSpeed.instant ? findsOneWidget : findsNWidgets(2),
          reason: speed == PlaybackSpeed.instant ? 'face up at once' : 'both sides while it turns',
        );
        await tester.pumpAndSettle();
      },
    );
  }

  test("poker's cards flip in 400 ms at Normal, at the Animations setting's speed unless given", () {
    expect(CardView.flipTime, const Duration(milliseconds: 400));
    expect(const CardView(width: 50).flipDuration, isNull);
  });

  testWidgets('tapping a card toggles it; a drag across cards picks none (dragging moves cards)', (tester) async {
    final selected = <int>{};
    final moves = <(int, int)>[];
    await pumpShot(
      tester,
      StatefulBuilder(
        builder: (context, setState) => Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 600,
            height: 120,
            child: HandFan(
              cards: _twenty.sublist(0, 10),
              selected: selected,
              onToggle: (i) => setState(() => selected.contains(i) ? selected.remove(i) : selected.add(i)),
              onReorder: (from, to) => moves.add((from, to)),
            ),
          ),
        ),
      ),
      size: const Size(600, 200),
    );
    final cards = find.byType(GameCardView);
    await tester.tap(cards.at(2));
    await tester.pump();
    expect(selected, {2});
    await tester.tap(cards.at(2));
    await tester.pump();
    expect(selected, isEmpty);

    final from = tester.getRect(cards.at(4)).center;
    final to = tester.getRect(cards.at(7)).center;
    await tester.dragFrom(from, to - from);
    await tester.pumpAndSettle();
    expect(selected, isEmpty, reason: 'the sweep-to-pick gesture is gone');
    expect(moves, [(4, 7)], reason: 'the drag moved card 4 instead');
  });

  testWidgets('a card that can be tapped shows a hand cursor and rises a little under the mouse', (tester) async {
    await pumpShot(
      tester,
      Center(
        child: GameCardView(width: 60, face: const CardFace.suited(5, 1), onTap: () {}),
      ),
      size: const Size(200, 200),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    final before = tester.getRect(find.byType(CardView));
    await mouse.moveTo(tester.getCenter(find.byType(GameCardView)));
    await tester.pumpAndSettle();
    expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.click);
    expect(tester.getRect(find.byType(CardView)).top, lessThan(before.top));
  });

  testWidgets('a seat badge on a small felt gets smaller, then cuts the name, and never overflows', (tester) async {
    Future<void> badge(double width, String name) => pumpShot(
      tester,
      Center(
        child: SizedBox(
          width: width,
          child: Align(
            alignment: Alignment.centerLeft,
            child: SeatBadge(name: name, cardsLeft: 17, role: 'Terrateniente'),
          ),
        ),
      ),
      size: const Size(568, 320),
      language: AppLanguage.spanish,
    );
    RenderParagraph text(String t) => tester.renderObject<RenderParagraph>(find.text(t));

    await badge(400, 'Ana');
    final natural = tester.getRect(find.byType(SeatBadge)).width;

    // Fight the Landlord's badge on a sideways phone: about 120 px for ~150.
    await badge(natural * 0.8, 'Ana');
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byType(SeatBadge)).width, lessThanOrEqualTo(natural * 0.8 + 0.01));
    for (final t in ['Ana', 'Terrateniente', '17']) {
      expect(text(t).didExceedMaxLines, isFalse, reason: '"$t" reads in full, a little smaller');
    }

    await badge(natural * 0.8, 'Anastasia Valentina');
    expect(tester.takeException(), isNull);
    expect(text('Anastasia Valentina').didExceedMaxLines, isTrue, reason: 'a long name is cut first');
    expect(text('Terrateniente').didExceedMaxLines, isFalse);
    expect(text('17').didExceedMaxLines, isFalse);

    await badge(70, 'Ana');
    expect(tester.takeException(), isNull, reason: 'even far too small: cut, never overflowing');
    expect(find.text('17'), findsOneWidget);
  });

  testWidgets('seat badges and tricks fit their names and cards', (tester) async {
    await pumpShot(
      tester,
      const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SeatBadge(name: 'Yuki', cardsLeft: 13, toAct: true, role: 'Landlord'),
            SizedBox(height: 8),
            TrickRow(cards: [CardFace.suited(5, 0), CardFace.suited(5, 2)], label: 'Pair of 7s'),
          ],
        ),
      ),
      size: const Size(300, 200),
    );
    expect(find.text('Yuki'), findsOneWidget);
    expect(find.text('13'), findsOneWidget);
    expect(find.text('Pair of 7s'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}
