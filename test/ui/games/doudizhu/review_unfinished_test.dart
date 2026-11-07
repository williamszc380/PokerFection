// The review of a deal left during the auction: the last step's headline
// must still say something. The kit saves a deal as soon as it is dealt
// (and Next deal replaces the finished one at once), so leaving before
// anyone has bid makes this the menu's Last game.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_record.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/kit/game_record.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/kit/seats.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_review.dart';
import 'package:pokerfection/src/ui/kit/kit_scope.dart';

import '../../../kit/shots.dart';

void main() {
  setUpAll(loadShotFonts);

  testWidgets('a deal left before the first bid: the review\'s last step still has a headline', (tester) async {
    final record = ddzNewRecord(
      seed: 7,
      rules: DdzRules.standard,
      seats: const [
        SeatSpec(human: true, name: 'Player'),
        SeatSpec(human: false, level: KitLevel.easy, name: 'Ana'),
        SeatSpec(human: false, level: KitLevel.easy, name: 'Ben'),
      ],
      firstBidder: 0,
      extra: const {'mode': 'training'},
    );
    expect(ddzReplays(record), isTrue, reason: 'the menu would offer it as Last game');
    await pumpShot(
      tester,
      LandlordReview(record: record),
      size: const Size(1280, 800),
      wrap: (child) => KitScope(newJobs: Jobs.inline, lastGames: LastGames(), child: child),
    );
    await tester.pump();
    final headline = tester.widget<Text>(find.byKey(const ValueKey('review headline'))).data!;
    expect(headline, isNotEmpty, reason: 'Gomoku and Big Two say "Move 1 · Player" here, Blackjack "Net 0"');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
