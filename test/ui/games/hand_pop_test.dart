// Picked cards pop up (no outline) in every game that picks cards, and stay
// inside the hand's box; a long Big Two or Fight the Landlord hand keeps
// every rank readable on a sideways phone. Screenshots of 3 picked cards go to the folder given with
// --dart-define=SHOTS=<folder>:
//   flutter test test/ui/games/hand_pop_test.dart --dart-define=SHOTS=<folder>
import 'dart:math';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_controller.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';
import 'package:pokerfection/src/ui/widgets/card_view.dart';

import '../../kit/shots.dart';
import 'big_two/big_two_test_util.dart' as b2;
import 'doudizhu/states.dart' as ddz;

const _sizes = [Size(568, 320), Size(900, 420), Size(1280, 800)];

/// The four corners of [finder]'s box on screen (after its turn and rise).
List<Offset> _corners(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  final s = box.size;
  return [
    for (final p in [Offset.zero, Offset(s.width, 0), Offset(0, s.height), Offset(s.width, s.height)])
      box.localToGlobal(p),
  ];
}

/// The card drawn inside each GameCardView of the hand (under its rise).
Finder _drawn(Finder card) => find.descendant(of: card, matching: find.byType(AnimatedSlide)).first;

/// Every card of the hand: the picked ones have popped up by about a fifth
/// of their height, the others not at all; none has an outline the others
/// lack; all stay inside the hand's box.
void _expectPopped(WidgetTester tester, String tag) {
  final hand = find.byKey(const ValueKey('hand'));
  final area = tester.getRect(find.byKey(const ValueKey('hand area')));
  final cards = find.descendant(of: hand, matching: find.byType(GameCardView));
  var picked = 0;
  for (final element in cards.evaluate()) {
    final view = element.widget as GameCardView;
    final card = find.byWidget(view);
    final slide = tester.widget<AnimatedSlide>(_drawn(card));
    if (view.selected) {
      picked++;
      expect(slide.offset.dy, closeTo(-GameCardView.selectedLift, 0.001), reason: '$tag: a picked card pops up');
    } else {
      expect(slide.offset.dy, 0, reason: '$tag: the others stay down');
    }
    for (final corner in _corners(tester, find.descendant(of: _drawn(card), matching: find.byType(SizedBox)).first)) {
      expect(corner.dy, greaterThanOrEqualTo(area.top - 0.5), reason: '$tag: ${view.face} stays inside the hand area');
      expect(corner.dy, lessThanOrEqualTo(area.bottom + 0.5), reason: '$tag: ${view.face}');
    }
  }
  expect(picked, 3, reason: tag);
  // No outline: a picked card draws the same boxes, with the same edges, as
  // the cards left down (jokers aside: they are drawn their own way).
  String frame(Element card) => [
    for (final d in find.descendant(of: find.byWidget(card.widget), matching: find.byType(DecoratedBox)).evaluate())
      '${(d.widget as DecoratedBox).decoration}',
  ].join(' | ');
  final suited = cards.evaluate().where((e) => !(e.widget as GameCardView).face!.isJoker);
  String look(Element e) => frame(e).replaceAll(RegExp(r'color: Color\([^)]*\)'), 'color');
  final down = {for (final e in suited.where((e) => !(e.widget as GameCardView).selected)) look(e)};
  for (final e in suited.where((e) => (e.widget as GameCardView).selected)) {
    expect(down, contains(look(e)), reason: '$tag: no outline on a picked card');
  }
}

/// How far the "10" in a card's corner reaches from its left edge (CardView's
/// corner: inset 8% of the width, the rank in [style] at 38%, the "10" drawn
/// tight).
double _tenReach(double width, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(
      text: '10',
      style: style.copyWith(letterSpacing: -width * 0.04),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  // The last letter's spacing is after its ink: not part of the "0".
  final reach = width * 0.08 + painter.width + width * 0.04;
  painter.dispose();
  return reach;
}

/// Every card of the hand but the last shows its corner's "10" whole: the
/// next card starts past it.
void _expectTensRead(WidgetTester tester, String tag) {
  final hand = find.byKey(const ValueKey('hand'));
  final cards = find.descendant(of: hand, matching: find.byType(GameCardView)).evaluate().toList();
  expect(cards.length, greaterThan(12), reason: tag);
  final lefts = [for (final e in cards) tester.getTopLeft(find.byWidget(e.widget)).dx]..sort();
  final width = (cards.first.widget as GameCardView).width;
  // The ranks' own style (the app's font), from a card's corner.
  final rank = tester.renderObject<RenderParagraph>(
    find
        .descendant(
          of: find.descendant(of: hand, matching: find.byType(CardView)).first,
          matching: find.byType(RichText),
        )
        .first,
  );
  final need = _tenReach(width, (rank.text as TextSpan).style!);
  var step = double.infinity;
  for (var i = 1; i < lefts.length; i++) {
    step = min(step, lefts[i] - lefts[i - 1]);
  }
  // The "0" ends its ink a little before its advance (about 4% of the size).
  expect(
    step,
    greaterThanOrEqualTo(need - width * 0.38 * 0.04),
    reason: '$tag: a 10 must not read as "1" (${width.toStringAsFixed(1)} px cards)',
  );
  expect(width * 0.38, greaterThanOrEqualTo(10), reason: '$tag: ranks at least 10 px tall');
}

void main() {
  setUpAll(loadShotFonts);

  group('Big Two', () {
    for (final size in _sizes) {
      final tag = shotTag(size, AppLanguage.english);
      testWidgets('3 picked cards pop up, no outline, inside the hand $tag', (tester) async {
        final game = b2.seededGame(training: false, rules: BigTwoRules.standard(players: 2));
        await b2.pumpGame(tester, game, size: size);
        await b2.toMyPlayableTurn(tester, game);
        for (final card in [game.hand[2], game.hand[6], game.hand[7]]) {
          game.toggle(card);
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        _expectPopped(tester, tag);
        await shot(tester, 'big_two_pop3_$tag');
        await b2.closeGame(tester);
      });
    }

    for (final (players, each) in [(2, 17), (2, 21), (3, 17)]) {
      for (final size in const [Size(568, 320), Size(592, 360)]) {
        final tag = '${players}p${each}_${shotTag(size, AppLanguage.english)}';
        testWidgets('a long hand keeps every 10 readable on a sideways phone $tag', (tester) async {
          final game = b2.seededGame(
            training: false,
            rules: BigTwoRules.standard(players: players, cardsEach: each),
          );
          await b2.pumpGame(tester, game, size: size);
          await b2.settleGame(tester);
          _expectTensRead(tester, tag);
          if (size.width == 568) await shot(tester, 'big_two_long_$tag');
          await b2.closeGame(tester);
        });
      }
    }
  });

  group('Fight the Landlord', () {
    for (final size in _sizes) {
      final tag = shotTag(size, AppLanguage.english);
      testWidgets('3 picked cards pop up, no outline, inside the hand $tag', (tester) async {
        final c = await ddz.gameAt(tester, DdzPhase.playing, training: false);
        await ddz.showGame(tester, c, size, AppLanguage.english);
        c.clearSelection();
        final hand = [...c.game.hands[LandlordController.you]]..sort();
        for (final id in [hand[1], hand[5], hand[6]]) {
          c.toggle(id);
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        _expectPopped(tester, tag);
        await shot(tester, 'landlord_pop3_$tag');
        await ddz.closeGame(tester, c);
      });
    }

    for (final landlord in [true, false]) {
      final count = landlord ? 20 : 17;
      for (final size in const [Size(568, 320), Size(592, 360), Size(800, 360), Size(390, 844)]) {
        final tag = '${count}_${shotTag(size, AppLanguage.english)}';
        testWidgets('a hand of $count keeps every 10 readable $tag', (tester) async {
          LandlordController? c;
          for (var seed = 1; c == null; seed++) {
            final at = await ddz.gameAt(tester, DdzPhase.playing, training: false, seed: seed);
            if (at.game.hands[LandlordController.you].length == count) {
              c = at;
            } else {
              at.dispose();
            }
          }
          await ddz.showGame(tester, c, size, AppLanguage.english);
          await tester.pump(const Duration(milliseconds: 300));
          _expectTensRead(tester, tag);
          await shot(tester, 'landlord_long_$tag');
          await ddz.closeGame(tester, c);
        });
      }
    }
  });
}
