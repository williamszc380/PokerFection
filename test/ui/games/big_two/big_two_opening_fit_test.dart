// Who goes first on a sideways phone: the step's card and words keep off
// the seats' badges (a name or a card count covered for a second is a name
// the player can't read), and the result in the middle reads at the size
// of the felt's other words. Four players on 512x320 and 568x320, the two
// smallest felts, in every language.
// Screenshots with --dart-define=SHOTS=<folder>.
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_controller.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import '../../../kit/shots.dart';
import 'big_two_test_util.dart';

final _step = find.byKey(const ValueKey('opening step'));
final _note = find.byKey(const ValueKey('opening note'));
final _words = find.byKey(const ValueKey('opening words'));
Finder _badge(int seat) => find.descendant(of: find.byKey(ValueKey('seat $seat')), matching: find.byType(SeatBadge));

const _phones = [Size(512, 320), Size(568, 320)];

/// A four-player game at Normal whose starter is the seat across.
Future<BigTwoController> _across() async {
  for (var seed = 1; seed < 200; seed++) {
    final game = seededGame(seed: seed, training: false, speed: PlaybackSpeed.normal);
    await game.newGame();
    if (!game.state.isOver && game.state.startSeat == 2) return game;
    game.dispose();
  }
  fail('no deal like that');
}

Future<void> _close(WidgetTester tester) async {
  await closeGame(tester);
  await tester.pump(const Duration(seconds: 5));
}

/// The rects of [finder]'s widgets that [rect] overlaps by more than a pixel.
bool _covers(WidgetTester tester, Rect rect, Finder finder) {
  for (final e in finder.evaluate()) {
    final box = tester.getRect(find.byWidget(e.widget));
    final both = rect.intersect(box);
    if (both.width > 1 && both.height > 1) return true;
  }
  return false;
}

void main() {
  setUpAll(loadShotFonts);

  for (final language in AppLanguage.values) {
    for (final size in _phones) {
      final tag = shotTag(size, language);
      testWidgets('four players, $tag: the step\'s words and card cover no side seat\'s badge', (tester) async {
        final game = await _across();
        await pumpGame(tester, game, size: size, language: language);
        // Named, not yet flying: the card and the words side by side in
        // the middle.
        await tester.pump(const Duration(milliseconds: 500));
        expect(_words, findsOneWidget);
        await shot(tester, 'review_b2_4p_named_$tag');
        final words = tester.getRect(_words);
        final card = tester.getRect(find.descendant(of: _step, matching: find.byType(GameCardView)).first);
        for (final seat in [1, 3]) {
          expect(_covers(tester, words, _badge(seat)), isFalse, reason: 'the words over seat $seat\'s badge');
          expect(_covers(tester, card, _badge(seat)), isFalse, reason: 'the card over seat $seat\'s badge');
        }
        await _close(tester);
      });

      testWidgets('four players, $tag: the result in the middle reads at a readable size', (tester) async {
        final game = await _across();
        await pumpGame(tester, game, size: size, language: language);
        await tester.pump(const Duration(milliseconds: 2100));
        expect(_note, findsOneWidget);
        await shot(tester, 'review_b2_4p_result_$tag');
        // The note's first line, as drawn (after any scaling down).
        final text = find.descendant(of: _note, matching: find.byType(Text)).first;
        final drawn = tester.getRect(text).height;
        expect(drawn, greaterThanOrEqualTo(10), reason: 'the words are ${drawn.toStringAsFixed(1)} px tall');
        // Its "?" is big enough to tap.
        final help = find.descendant(of: _note, matching: find.byIcon(Icons.help_outline));
        if (help.evaluate().isNotEmpty) {
          expect(tester.getRect(help.first).height, greaterThanOrEqualTo(12), reason: 'the "?"');
        }
        await _close(tester);
      });
    }
  }
}
