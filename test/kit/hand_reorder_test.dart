// Dragging a card moves it within the hand: it follows the finger or the
// mouse above the others, they slide apart to make room, and it settles
// into its new place at the Animations speed (at once at Instant). The game
// owns the order (HandFan.onReorder); a tap still picks a card.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import 'shots.dart';

/// Eight different cards: 3♣ 4♦ 5♥ 6♠ 7♣ 8♦ 9♥ 10♠.
final _eight = [for (var i = 0; i < 8; i++) CardFace.suited(i + 1, i % 4)];

/// A game around a hand: it keeps the cards' order and the picks by card
/// (as Big Two and Fight the Landlord do), and every move it was told.
class _Game {
  _Game([List<CardFace>? cards]) : cards = [...(cards ?? _eight)];

  List<CardFace> cards;
  final picked = <CardFace>{};
  final moves = <(int, int)>[];
}

Future<_Game> _pump(
  WidgetTester tester, {
  _Game? game,
  PlaybackSpeed speed = PlaybackSpeed.normal,
  bool fanned = true,
  bool reorder = true,
  Size hand = const Size(600, 140),
}) async {
  final g = game ?? _Game();
  await pumpShot(
    tester,
    StatefulBuilder(
      builder: (context, setState) => Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox.fromSize(
          size: hand,
          child: HandFan(
            cards: g.cards,
            fanned: fanned,
            selected: {
              for (final (i, c) in g.cards.indexed)
                if (g.picked.contains(c)) i,
            },
            onToggle: (i) => setState(() => g.picked.contains(g.cards[i]) ? g.picked.remove(g.cards[i]) : g.picked.add(g.cards[i])),
            onReorder: !reorder
                ? null
                : (from, to) => setState(() {
                      g.moves.add((from, to));
                      g.cards = moveCard(g.cards, from, to);
                    }),
          ),
        ),
      ),
    ),
    size: Size(hand.width, hand.height + 60),
    wrap: (app) => AppSettingsScope(settings: AppSettings()..speed = speed, child: app),
  );
  return g;
}

Finder _card(CardFace face) => find.byKey(ValueKey('$face#1'));
Offset _center(WidgetTester tester, CardFace face) => tester.getCenter(_card(face));

/// A point on the part of [face] in view (left of the next card).
Offset _onCard(WidgetTester tester, CardFace face) {
  final box = tester.getRect(_card(face));
  return Offset(box.left + box.width * 0.2, box.center.dy);
}

/// Drags [face] by [kind] until its center is over [target]'s place, in
/// small steps, and lets go.
Future<void> _drag(
  WidgetTester tester,
  CardFace face,
  CardFace target, {
  PointerDeviceKind kind = PointerDeviceKind.touch,
}) async {
  final from = _onCard(tester, face), to = from + _center(tester, target) - _center(tester, face);
  final gesture = await tester.startGesture(from, kind: kind);
  for (var k = 1; k <= 10; k++) {
    await gesture.moveTo(Offset.lerp(from, to, k / 10)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadShotFonts);

  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    final by = kind == PointerDeviceKind.touch ? 'by touch' : 'with the mouse';

    testWidgets('$by: the first card dragged past the last goes to the end', (tester) async {
      final g = await _pump(tester);
      await _drag(tester, _eight[0], _eight[7], kind: kind);
      expect(g.moves, [(0, 7)]);
      expect(g.cards, [..._eight.sublist(1), _eight[0]]);
      // Drawn where the game put it: rightmost.
      final xs = [for (final c in g.cards) _center(tester, c).dx];
      expect(xs, orderedEquals([...xs]..sort()));
    });

    testWidgets('$by: the last card dragged to the front goes first', (tester) async {
      final g = await _pump(tester);
      await _drag(tester, _eight[7], _eight[0], kind: kind);
      expect(g.moves, [(7, 0)]);
      expect(g.cards, [_eight[7], ..._eight.sublist(0, 7)]);
    });

    testWidgets('$by: a card in the middle moves right and left, between two others', (tester) async {
      final g = await _pump(tester);
      await _drag(tester, _eight[2], _eight[5], kind: kind);
      expect(g.moves, [(2, 5)]);
      expect(g.cards, [_eight[0], _eight[1], _eight[3], _eight[4], _eight[5], _eight[2], _eight[6], _eight[7]]);
      await _drag(tester, _eight[6], _eight[1], kind: kind);
      expect(g.moves.last, (6, 1));
      expect(g.cards.indexOf(_eight[6]), 1);
    });

    testWidgets('$by: a tap picks the card and moves nothing', (tester) async {
      final g = await _pump(tester);
      await tester.tapAt(_center(tester, _eight[3]), kind: kind);
      await tester.pumpAndSettle();
      expect(g.picked, {_eight[3]});
      expect(g.moves, isEmpty);
    });
  }

  testWidgets('a tap that wobbles a little is still a tap: 3 px with the mouse, 12 px by touch', (tester) async {
    final g = await _pump(tester);
    for (final (kind, wobble, face) in [
      (PointerDeviceKind.mouse, 3.0, _eight[2]),
      (PointerDeviceKind.touch, 12.0, _eight[5]),
    ]) {
      final at = _center(tester, face);
      final gesture = await tester.startGesture(at, kind: kind);
      await gesture.moveBy(Offset(wobble, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(g.picked, contains(face), reason: '$kind');
    }
    expect(g.moves, isEmpty);
  });

  testWidgets('picked cards keep their pick while one moves: the dragged one stays up', (tester) async {
    final g = _Game()..picked.addAll([_eight[1], _eight[4]]);
    await _pump(tester, game: g);
    await tester.pumpAndSettle();
    double lift(CardFace face) => tester
        .widget<AnimatedSlide>(find.descendant(of: _card(face), matching: find.byType(AnimatedSlide)))
        .offset
        .dy;
    // Mid-drag, the picked card being moved is still up.
    final from = _center(tester, _eight[1]);
    final gesture = await tester.startGesture(from);
    await gesture.moveTo(_center(tester, _eight[6]));
    await tester.pump();
    expect(tester.widget<GameCardView>(_card(_eight[1])).selected, isTrue);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(g.cards.indexOf(_eight[1]), 6);
    expect(g.picked, {_eight[1], _eight[4]}, reason: 'no pick changed');
    expect(lift(_eight[1]), lessThanOrEqualTo(-GameCardView.selectedLift), reason: 'still up, in its new place');
    expect(lift(_eight[4]), lessThanOrEqualTo(-GameCardView.selectedLift));
    expect(lift(_eight[2]), 0);
  });

  testWidgets('a drag that ends where it began moves nothing', (tester) async {
    final g = await _pump(tester);
    final from = _center(tester, _eight[3]);
    final gesture = await tester.startGesture(from);
    await gesture.moveTo(_center(tester, _eight[6]));
    await tester.pump();
    await gesture.moveTo(from + const Offset(2, -6));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(g.moves, isEmpty);
    expect(g.picked, isEmpty, reason: 'and picks nothing: it was a drag');
    expect(g.cards, _eight);
  });

  testWidgets('without onReorder the cards stay put under a drag', (tester) async {
    final g = await _pump(tester, reorder: false);
    final before = _center(tester, _eight[0]);
    final gesture = await tester.startGesture(before);
    await gesture.moveBy(const Offset(200, 0));
    await tester.pump();
    expect(_center(tester, _eight[0]), before);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(g.cards, _eight);
  });

  testWidgets('mid-drag: the card follows the pointer, held above the others; the grab cursor shows', (tester) async {
    await _pump(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    final from = _center(tester, _eight[2]);
    await mouse.moveTo(from);
    await tester.pumpAndSettle();
    expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.click);
    await mouse.down(from);
    for (final step in [const Offset(30, -10), const Offset(80, -24), const Offset(150, -18)]) {
      await mouse.moveTo(from + step);
      await tester.pumpAndSettle();
      expect(
        (_center(tester, _eight[2]) - (from + step)).distance,
        lessThan(2),
        reason: 'it follows the mouse, wherever it goes',
      );
    }
    expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.grabbing);
    final drawn = find.byType(GameCardView).evaluate().map((e) => e.widget.key).toList();
    expect(drawn.last, ValueKey('${_eight[2]}#1'), reason: 'drawn last: above the others');
    final held = tester.widget<AnimatedScale>(find.descendant(of: find.byType(HandFan), matching: find.byType(AnimatedScale)).at(drawn.length - 1));
    expect(held.scale, HandFan.heldScale);
    await mouse.up();
    await tester.pumpAndSettle();
    expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.click, reason: 'back to the hand');
  });

  for (final speed in PlaybackSpeed.values) {
    testWidgets('the others make room and the card settles at ${speed.label}', (tester) async {
      final g = await _pump(tester, speed: speed);
      final places = [for (final c in _eight) _center(tester, c)];
      // Card 0 over card 3's place: cards 1–3 shift one place left.
      final gesture = await tester.startGesture(places[0]);
      await gesture.moveTo(places[0] + const Offset(30, 0));
      await tester.pump();
      await gesture.moveTo(places[3] + const Offset(0, -20));
      await tester.pump();
      final slide = HandFan.slideTime * speed.factor;
      if (speed == PlaybackSpeed.instant) {
        expect(_center(tester, _eight[2]).dx, closeTo(places[1].dx, 0.5), reason: 'at once');
      } else {
        await tester.pump(slide * 0.5);
        final x = _center(tester, _eight[2]).dx;
        expect(x, lessThan(places[2].dx - 1), reason: 'on its way left');
        expect(x, greaterThan(places[1].dx + 1));
        await tester.pump(slide);
        expect(_center(tester, _eight[2]).dx, closeTo(places[1].dx, 0.5));
      }
      expect(_center(tester, _eight[4]).dx, closeTo(places[4].dx, 0.5), reason: 'cards past it stay');
      // Let go 20 px above its new place: it settles there.
      await gesture.up();
      await tester.pump();
      expect(g.moves, [(0, 3)]);
      if (speed != PlaybackSpeed.instant) {
        await tester.pump(slide * 0.5);
        final y = _center(tester, _eight[0]).dy;
        expect(y, lessThan(places[3].dy - 1), reason: 'on its way down');
        expect(find.byType(GameCardView).evaluate().last.widget.key, ValueKey('${_eight[0]}#1'), reason: 'still on top while it lands');
      }
      await tester.pump(slide + const Duration(milliseconds: 20));
      expect((_center(tester, _eight[0]) - places[3]).distance, lessThan(0.5));
      expect(find.byType(GameCardView).evaluate().last.widget.key, ValueKey('${_eight[7]}#1'), reason: 'landed: back in its place in the pile');
      expect(tester.binding.hasScheduledFrame, isFalse, reason: 'nothing left moving');
    });
  }

  testWidgets('several moves in one frame (a phone sends touches in bursts) still land the card right', (tester) async {
    final g = await _pump(tester);
    final step = _center(tester, _eight[1]).dx - _center(tester, _eight[0]).dx;
    final gesture = await tester.startGesture(_center(tester, _eight[1]));
    await gesture.moveBy(Offset(step * 0.6, 0));
    await gesture.moveBy(Offset(step, 0));
    await gesture.moveBy(Offset(step, 0)); // no pump between
    await gesture.up();
    await tester.pumpAndSettle();
    expect(g.moves, [(1, 4)]);
  });

  testWidgets('in a straight row too', (tester) async {
    final g = await _pump(tester, fanned: false);
    await _drag(tester, _eight[5], _eight[2]);
    expect(g.moves, [(5, 2)]);
  });

  testWidgets('a card that leaves the hand mid-drag ends the drag', (tester) async {
    late StateSetter set;
    var cards = [..._eight];
    final moves = <(int, int)>[];
    await pumpShot(
      tester,
      StatefulBuilder(builder: (context, setState) {
        set = setState;
        return Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 600,
            height: 140,
            child: HandFan(cards: cards, onToggle: (_) {}, onReorder: (f, t) => moves.add((f, t))),
          ),
        );
      }),
      size: const Size(600, 200),
    );
    final gesture = await tester.startGesture(_center(tester, _eight[2]));
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump();
    set(() => cards = [..._eight]..removeAt(2));
    await tester.pump();
    await gesture.moveBy(const Offset(40, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(moves, isEmpty);
    expect(find.byType(GameCardView), findsNWidgets(7));
  });

  // The game stops taking drags while the player holds a card: a bot plays
  // out, or the deal is thrown in, and the hand is only to look at.
  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    for (final speed in [PlaybackSpeed.normal, PlaybackSpeed.instant]) {
      testWidgets('${kind.name}, ${speed.label}: the deal ends mid-drag; the held card goes back to its place', (
        tester,
      ) async {
        late StateSetter set;
        var live = true;
        final moves = <(int, int)>[];
        await pumpShot(
          tester,
          StatefulBuilder(builder: (context, setState) {
            set = setState;
            return Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 600,
                height: 140,
                child: HandFan(
                  cards: _eight,
                  onToggle: live ? (_) {} : null,
                  onReorder: live ? (f, t) => moves.add((f, t)) : null,
                  sortOrder: HandOrder.rank,
                  onSort: live ? () {} : null,
                ),
              ),
            );
          }),
          size: const Size(600, 200),
          wrap: (app) => AppSettingsScope(settings: AppSettings()..speed = speed, child: app),
        );
        final before = _center(tester, _eight[2]), size = tester.getRect(_card(_eight[2])).size;
        final gesture = await tester.startGesture(before, kind: kind);
        await gesture.moveBy(const Offset(60, -50));
        await tester.pump();
        await gesture.moveBy(const Offset(60, 0));
        await tester.pump();
        expect(tester.widget<GameCardView>(_card(_eight[2])).dragging, isTrue);
        set(() => live = false);
        await tester.pump();
        if (speed == PlaybackSpeed.instant) {
          expect(_center(tester, _eight[2]), offsetMoreOrLessEquals(before, epsilon: 1), reason: 'at once');
        }
        await gesture.up();
        await tester.pumpAndSettle();

        expect(moves, isEmpty, reason: 'nothing moved');
        for (final face in _eight) {
          expect(tester.widget<GameCardView>(_card(face)).dragging, isFalse, reason: 'no card is being dragged');
        }
        expect(_center(tester, _eight[2]), offsetMoreOrLessEquals(before, epsilon: 1),
            reason: 'back in its place in the hand, not where the finger let go');
        expect(tester.getRect(_card(_eight[2])).size.width, moreOrLessEquals(size.width, epsilon: 0.5),
            reason: 'no longer drawn bigger');
      });
    }
  }

  testWidgets('a hand of 20 at 568x320: a card dragged across the fan lands where it was let go', (tester) async {
    final twenty = [
      for (var i = 0; i < 18; i++) CardFace.suited(i % 13, i ~/ 13 * 2 + (i % 2)),
      const CardFace.joker(big: false),
      const CardFace.joker(big: true),
    ];
    final g = await _pump(tester, game: _Game(twenty), hand: const Size(276, 77));
    await _drag(tester, twenty[17], twenty[3]);
    expect(g.moves, [(17, 3)]);
    await _drag(tester, twenty[19], twenty[0], kind: PointerDeviceKind.mouse);
    expect(g.cards.first, twenty[19]);
  });
}
