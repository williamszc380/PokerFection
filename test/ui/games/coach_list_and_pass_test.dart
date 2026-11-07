// The coach list and Pass in the card games, each a specification the games
// meet:
// - a range sheet left open while the deal ends says what happened instead
//   of "Working it out…" forever (Big Two);
// - Clear puts out a Pass lit from the coach list in Big Two, as in Fight
//   the Landlord;
// - Pass, always listed, is in sight on a sideways phone without scrolling;
// - a card play is never made for the player without a click (Fight the
//   Landlord plays the last card of a lead by itself).
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_record.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_controller.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_controller.dart';

import '../../kit/shots.dart';
import 'big_two/big_two_test_util.dart' as b2;
import 'doudizhu/helpers.dart';
import 'doudizhu/states.dart';

/// Whether [row] lies wholly inside the scrolling area that holds it.
bool inSight(WidgetTester tester, Finder row) {
  final rect = tester.getRect(row);
  final view = tester.getRect(find.ancestor(of: row, matching: find.byType(Scrollable)).first);
  return rect.top >= view.top - 0.5 && rect.bottom <= view.bottom + 0.5;
}

void main() {
  setUpAll(loadShotFonts);

  testWidgets("Big Two: a range sheet open as the deal ends doesn't spin for ever", (tester) async {
    final game = b2.seededGame(rules: BigTwoRules.standard(), toggles: {'coach': true});
    await b2.pumpGame(tester, game, size: const Size(900, 420));
    await b2.toMyPlayableTurn(tester, game);
    await tester.tap(find.byKey(const ValueKey('range tap 1')));
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
    expect(find.byKey(const ValueKey('range sheet')), findsOneWidget);
    // The deal plays on behind the sheet (the bots, the player's moves).
    await b2.playToEnd(tester, game);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await shot(tester, 'b2_range_after_deal_en_900x420');
    expect(
      find.text('Working it out…'),
      findsNothing,
      reason: 'the deal is over: no range job runs, so the sheet must not say one is working',
    );
    await b2.closeGame(tester);
  });

  testWidgets('Big Two: Clear puts out a Pass lit from the coach list, as in Fight the Landlord', (tester) async {
    final game = b2.seededGame(rules: BigTwoRules.standard(), toggles: {'coach': true});
    await b2.pumpGame(tester, game, size: const Size(1280, 800));
    for (var guard = 0; guard < 50 && !(game.myTurn && game.canPass && game.coach != null); guard++) {
      await b2.toMyPlayableTurn(tester, game);
      if (!game.canPass) game.humanMove(game.coach!.pick);
    }
    expect(game.canPass, isTrue);
    game.selectMove(BigTwoController.passMove);
    await tester.pump(const Duration(milliseconds: 300));
    expect(game.passChosen, isTrue);
    final clear = tester.widget<TextButton>(find.byKey(const ValueKey('clear')));
    expect(clear.onPressed, isNotNull, reason: 'Clear (like Esc) should put the lit Pass out, as it does in Fight the Landlord');
    await b2.closeGame(tester);
  });

  for (final size in const [Size(568, 320), Size(592, 360)]) {
    testWidgets('Fight the Landlord: the listed Pass row is in sight at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
      final pass = yours(const DdzPass());
      LandlordController? found;
      for (var seed = 1; seed < 40 && found == null; seed++) {
        final c = await gameAt(tester, DdzPhase.playing, coach: true, following: true, seed: seed);
        await pumpUntil(tester, () => !c.coachThinking);
        final lines = c.coach!.lines;
        final at = lines.indexWhere((l) => l.move == pass);
        if (at >= 3) {
          found = c;
        } else {
          c.dispose();
        }
      }
      expect(found, isNotNull, reason: 'a deal where Pass ranks below the top three');
      final c = found!;
      c.clearSelection();
      await showGame(tester, c, size, AppLanguage.english);
      await tester.pump(const Duration(milliseconds: 400));
      await shot(tester, 'ddz_pass_low_en_${size.width.toInt()}x${size.height.toInt()}');
      final row = find.byKey(ValueKey(pass));
      expect(row, findsOneWidget, reason: 'Pass is listed');
      expect(inSight(tester, row), isTrue, reason: 'Pass must be among the rows the player sees, not below the fold');
      await closeGame(tester, c);
    });
  }

  test('Fight the Landlord: a card play is never made for the player without a click', () async {
    final auto = <String>[];
    for (var seed = 1; seed < 30 && auto.isEmpty; seed++) {
      final c = testController(seed: seed);
      c.addListener(() {
        if (c.isOver || c.seatToAct != LandlordController.you) return;
        if (c.forcedMove(LandlordController.you) case final move?) {
          if (ddzParseMove(move).move is DdzPlay) auto.add(move);
        }
      });
      await c.newGame();
      // The player makes every decision that isn't forced; the kit plays the rest.
      await playDeal(c);
      c.dispose();
    }
    expect(auto, isEmpty, reason: 'these card plays were made by themselves, with no click: $auto');
  });
}
