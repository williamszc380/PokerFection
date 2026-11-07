// The player passes in the auction and, while the bots decide, picks up a
// card to move it. Both bots pass too: the deal is thrown in and the hand
// stays on screen to look at. The card the player was holding must fall
// back into the hand, not stay floating where the finger let go.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';

import '../../../kit/shots.dart';
import 'helpers.dart';
import 'states.dart';

void main() {
  setUpAll(loadShotFonts);

  testWidgets('a card held when the deal is thrown in drops back into the hand', (tester) async {
    for (var s = 1; s < 200; s++) {
      final c = testController(seed: s);
      c.newGame();
      await showGame(tester, c, const Size(900, 420), AppLanguage.english);
      await pumpUntil(tester, () => c.isOver || c.game.phase != DdzPhase.bidding || c.seatToAct == 0);
      if (c.isOver || c.game.phase != DdzPhase.bidding) {
        await closeGame(tester, c);
        continue;
      }
      final id = c.hand[3];
      final before = tester.getCenter(handCard(id));
      // The player picks a card up and carries it along the hand...
      final drag = await tester.startGesture(onCard(tester, id));
      await drag.moveBy(const Offset(40, -30));
      await tester.pump();
      await drag.moveBy(const Offset(40, 0));
      await tester.pump();
      // ...having passed; the bots answer meanwhile.
      c.humanMove(yours(const DdzBid(0)));
      await pumpUntil(tester, () => c.isOver || c.game.phase != DdzPhase.bidding);
      if (!c.thrownIn) {
        await drag.cancel();
        await closeGame(tester, c);
        continue;
      }
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      await shot(tester, 'ddz_thrown_in_mid_drag');
      expect(tester.widget<GameCardView>(handCard(id)).dragging, isFalse, reason: 'seed $s: nothing is being dragged');
      expect(tester.getCenter(handCard(id)), offsetMoreOrLessEquals(before, epsilon: 1),
          reason: 'seed $s: the card is back in its place in the hand');
      await closeGame(tester, c);
      return;
    }
    fail('no deal was thrown in');
  });
}
