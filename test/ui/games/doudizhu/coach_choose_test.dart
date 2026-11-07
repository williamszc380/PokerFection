// The coach list in Fight the Landlord: a single tap selects a row's move
// (a play's cards pop up; Pass or a bid lights its button), never playing
// it; a double tap plays it; Pass, No bid and the bids are always listed
// when they are legal, with their values.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_jobs.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_record.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_controller.dart';

import '../../../kit/shots.dart';
import 'states.dart';

const pc = Size(1280, 800);

Finder row(String move) => find.byKey(ValueKey(move));

/// The ring a choice selected from the coach list wears, on the button [key].
Finder ringOn(String key) => find.ancestor(of: find.byKey(ValueKey(key)), matching: find.byKey(const ValueKey('chosen ring')));

/// Waits for the coach's whole answer: the listed moves it left out added.
Future<void> coachDone(WidgetTester tester, LandlordController c) async {
  await pumpUntil(tester, () => c.coach != null && !c.coachThinking);
  await tester.pump();
}

Future<void> doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 80));
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(loadShotFonts);

  group('playing', () {
    testWidgets("a single tap on a play's row picks its cards and plays nothing, however long the player waits", (
      tester,
    ) async {
      final c = await gameAt(tester, DdzPhase.playing, coach: true, leading: true);
      c.clearSelection();
      await showGame(tester, c, pc, AppLanguage.english);
      final line = c.coach!.lines.firstWhere((l) => !l.move.endsWith(':p'));
      final at = c.record.moves.length;
      await tester.tap(row(line.move));
      await tester.pump(const Duration(seconds: 2));
      expect(c.record.moves.length, at, reason: 'not played');
      expect(c.selectedKey, line.move, reason: 'its cards are picked');
      expect(find.byKey(const ValueKey('selected row')), findsOneWidget, reason: 'its row is lit');
      await closeGame(tester, c);
    });

    testWidgets("a double tap on a play's row plays it, with the cards a tap picks", (tester) async {
      final c = await gameAt(tester, DdzPhase.playing, coach: true, leading: true);
      await showGame(tester, c, pc, AppLanguage.english);
      final line = c.coach!.lines.first;
      final hand = [...c.game.hands[0]];
      final at = c.record.moves.length;
      await doubleTap(tester, row(line.move));
      expect(c.record.moves.length, greaterThan(at));
      expect(ddzMoveKey(c.record.moves[at]), line.move);
      final played = ddzParseMove(c.record.moves[at]).cardIds;
      expect(played, isNotNull, reason: 'the record keeps the cards, as for a play from the hand');
      expect(played!.every(hand.contains), isTrue);
      await closeGame(tester, c);
    });

    testWidgets('following, Pass is always on the list with its value', (tester) async {
      for (final seed in [1, 2, 3]) {
        final c = await gameAt(tester, DdzPhase.playing, coach: true, following: true, seed: seed);
        await coachDone(tester, c);
        final pass = yours(const DdzPass());
        expect(c.listedMoves(0), [pass]);
        expect(c.coach!.lineFor(pass), isNotNull, reason: 'seed $seed: rated, even when the coach left it out');
        await showGame(tester, c, pc, AppLanguage.english);
        expect(row(pass), findsOneWidget, reason: 'seed $seed: shown, however low it ranks');
        await closeGame(tester, c);
      }
    });

    testWidgets('leading, Pass is not legal and not listed', (tester) async {
      final c = await gameAt(tester, DdzPhase.playing, coach: true, leading: true);
      expect(c.listedMoves(0), isEmpty);
      await closeGame(tester, c);
    });

    testWidgets("a tap on Pass's row rings the Pass button and drops the picked cards; it doesn't pass", (
      tester,
    ) async {
      final c = await gameAt(tester, DdzPhase.playing, coach: true, following: true);
      await coachDone(tester, c);
      await showGame(tester, c, pc, AppLanguage.english);
      final pass = yours(const DdzPass());
      final at = c.record.moves.length;
      await tester.tap(row(pass));
      await tester.pump(const Duration(seconds: 1));
      expect(c.record.moves.length, at, reason: 'still the player\'s turn');
      expect(c.chosen, pass);
      expect(c.selected, isEmpty);
      expect(ringOn('pass'), findsOneWidget);
      expect(find.byKey(const ValueKey('selected row')), findsOneWidget);
      // Picking a card by hand puts the ring out.
      c.toggle(c.game.hands[0].first);
      await tester.pump();
      expect(c.chosen, isNull);
      expect(ringOn('pass'), findsNothing);
      await closeGame(tester, c);
    });

    testWidgets("Enter passes once Pass's row is tapped; a double tap on it passes too", (tester) async {
      final c = await gameAt(tester, DdzPhase.playing, coach: true, following: true);
      await coachDone(tester, c);
      await showGame(tester, c, pc, AppLanguage.english);
      final pass = yours(const DdzPass());
      final at = c.record.moves.length;
      await tester.tap(row(pass));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(c.record.moves[at], pass);
      await closeGame(tester, c);

      final d = await gameAt(tester, DdzPhase.playing, coach: true, following: true, seed: 2);
      await coachDone(tester, d);
      await showGame(tester, d, pc, AppLanguage.english);
      final from = d.record.moves.length;
      await doubleTap(tester, row(pass));
      expect(d.record.moves[from], pass);
      await closeGame(tester, d);
    });

    testWidgets('Clear puts out a lit Pass too', (tester) async {
      final c = await gameAt(tester, DdzPhase.playing, coach: true, following: true);
      await coachDone(tester, c);
      await showGame(tester, c, pc, AppLanguage.english);
      await tester.tap(row(yours(const DdzPass())));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('clear')));
      await tester.pump();
      expect(c.chosen, isNull);
      await closeGame(tester, c);
    });
  });

  group('the auction', () {
    testWidgets('No bid and every legal bid are listed, each with its value', (tester) async {
      final c = await gameAt(tester, DdzPhase.bidding, coach: true);
      await coachDone(tester, c);
      final legal = [for (final m in c.game.legalMoves()) yours(m)];
      expect(c.listedMoves(0), legal);
      expect(legal, contains(yours(const DdzBid(0))));
      await showGame(tester, c, pc, AppLanguage.english);
      for (final move in legal) {
        expect(c.coach!.lineFor(move), isNotNull, reason: move);
        expect(row(move), findsOneWidget, reason: move);
      }
      await closeGame(tester, c);
    });

    testWidgets("a tap on a bid's row rings its button and bids nothing; a double tap bids", (tester) async {
      final c = await gameAt(tester, DdzPhase.bidding, coach: true);
      await coachDone(tester, c);
      await showGame(tester, c, pc, AppLanguage.english);
      final noBid = yours(const DdzBid(0));
      final at = c.record.moves.length;
      await tester.tap(row(noBid));
      await tester.pump(const Duration(seconds: 1));
      expect(c.record.moves.length, at);
      expect(ringOn('bid 0'), findsOneWidget);
      await doubleTap(tester, row(noBid));
      expect(c.record.moves[at], noBid);
      await closeGame(tester, c);
    });

    testWidgets('the review lists Pass and the bids too', (tester) async {
      final game = ddzReplay(ddzSampleGame(1), upTo: 0);
      expect(ddzListedMoves(game, game.toAct), [for (final m in game.legalMoves()) ddzMoveText(game.toAct, m)]);
      expect(ddzListedMoves(game, (game.toAct + 1) % 3), isEmpty, reason: "not that seat's turn");
    });
  });
}
