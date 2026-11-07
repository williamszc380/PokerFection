// The middle of the table opens the deal's history at any time, the
// auction included: the bids are turns of the history (ddzPilePlays), so a
// player who wants to check who bid what taps the middle and sees them,
// without waiting for the first card to be played.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_controller.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_table.dart';
import 'package:pokerfection/src/ui/games/doudizhu/l10n/doudizhu_strings.dart';
import 'package:pokerfection/src/ui/kit/table_pile.dart';

import 'helpers.dart';

void main() {
  testWidgets('during the auction, after a bid, tapping the middle opens the history with that bid', (tester) async {
    final english = LandlordStrings.forLanguage(AppLanguage.english);
    LandlordController? found;
    for (var seed = 1; seed < 40 && found == null; seed++) {
      final c = testController(seed: seed, training: false);
      await tester.runAsync(() async {
        await c.newGame();
        await untilYourTurn(c);
        // The player bids once if nobody has yet; the auction goes on.
        if (c.game.phase == DdzPhase.bidding && c.game.history.isEmpty) {
          c.humanMove(easyMove(c));
          await untilYourTurn(c);
        }
      });
      if (c.game.phase == DdzPhase.bidding && c.game.history.isNotEmpty) {
        found = c;
      } else {
        c.dispose();
      }
    }
    final c = found!;
    addTearDown(c.dispose);
    final bids = ddzPilePlays(c.game, english);
    expect(bids, isNotEmpty);
    expect(bids.every((turn) => !turn.hasCards), isTrue, reason: 'only bids so far');

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 500,
            child: LandlordTable(felt: LandlordFelt.of(c), strings: english),
          ),
        ),
      ),
    );
    final middle = find.byKey(const ValueKey('pile'));
    expect(middle, findsOneWidget, reason: 'the middle opens the history even before the first card is played');
    await tester.tap(middle);
    await tester.pumpAndSettle();
    expect(find.byType(PileHistory), findsOneWidget);
    expect(find.text(bids.first.label!), findsWidgets);
  });
}
