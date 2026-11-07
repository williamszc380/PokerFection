import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_record.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/kit/coach_answer.dart';
import 'package:pokerfection/src/kit/game_keys.dart';
import 'package:pokerfection/src/kit/jobs/job_registry.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/kit/seats.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_controller.dart';

import '../../../kit/fakes.dart';
import 'helpers.dart';

void main() {
  test(
    'a whole deal against bots ends, and every turn of yours is a real choice (forced passes play themselves)',
    () async {
      final c = testController(training: false, levels: const [KitLevel.hard, KitLevel.medium]);
      await c.newGame();
      var turns = 0;
      for (var guard = 0; guard < 200 && !c.isOver; guard++) {
        await untilYourTurn(c);
        if (c.isOver) break;
        final legal = c.game.legalMoves();
        expect(legal.length > 1 || legal.single is! DdzPass, isTrue, reason: 'a forced pass is never left to you');
        c.humanMove(easyMove(c));
        turns++;
      }
      expect(c.isOver, isTrue);
      expect(turns, greaterThan(0));
      expect(c.between, isTrue, reason: 'Next deal follows');
      if (!c.thrownIn) {
        expect(c.winners, isNotEmpty);
        expect(c.record.result!['points'], c.game.result!.points);
        expect(c.sessionNet, c.game.result!.points[0]);
      }
      expect(ddzReplays(c.record), isTrue, reason: 'the record replays the deal');
      c.dispose();
    },
  );

  test(
    "a pass the player can't avoid (要不起) plays itself, with no coach and no grade; a card never does",
    () async {
      // Seen as each turn begins, before the kit plays it.
      final forced = <int, String>{};
      for (var seed = 1; seed < 30 && forced.isEmpty; seed++) {
        final c = testController(seed: seed);
        c.addListener(() {
          if (c.isOver || c.seatToAct != LandlordController.you) return;
          if (c.forcedMove(LandlordController.you) case final move?) {
            forced[c.record.moves.length] = move;
            expect(c.coachJobs, isEmpty, reason: 'nothing to coach');
          }
        });
        await c.newGame();
        await playDeal(c);
        for (final MapEntry(key: i, value: move) in forced.entries) {
          expect(ddzParseMove(move).move, isA<DdzPass>(), reason: 'only a pass plays itself: $move');
          expect(c.record.moves[i], move, reason: 'played by itself');
          expect(c.record.marks.elementAtOrNull(i), isNull, reason: 'nothing to grade');
        }
        c.dispose();
      }
      expect(forced, isNotEmpty, reason: 'some deal left the player no choice');
    },
  );

  test('the last card of a lead waits for the click, with no coach and no grade (nothing to choose)', () async {
    LandlordController? found;
    for (var seed = 1; seed < 60 && found == null; seed++) {
      final c = testController(seed: seed);
      await c.newGame();
      var lone = false;
      for (var guard = 0; guard < 200 && !c.isOver; guard++) {
        await untilYourTurn(c);
        if (c.isOver) break;
        final legal = c.game.legalMoves();
        if (c.game.phase == DdzPhase.playing && legal.length == 1 && legal.single is DdzPlay) {
          lone = true;
          break;
        }
        c.humanMove(easyMove(c));
      }
      if (lone) {
        found = c;
      } else {
        c.dispose();
      }
    }
    expect(found, isNotNull, reason: 'a deal where the player leads their last card');
    final c = found!;
    final at = c.record.moves.length;
    await runUntil(() => false, rounds: 200);
    expect(c.record.moves.length, at, reason: 'never played without a click');
    expect(c.seatToAct, LandlordController.you);
    expect(c.forcedMove(LandlordController.you), isNull);
    expect(c.coachWanted(LandlordController.you), isFalse);
    expect(c.coachJobs, isEmpty, reason: 'one legal move: nothing to coach');
    final move = ddzMoveTextFor(c.game, c.game.legalMoves().single);
    c.humanMove(move);
    expect(c.record.marks.elementAtOrNull(at), isNull, reason: 'nothing to grade');
    c.dispose();
  });

  test('in Training your moves are graded, and the auction is graded on points', () async {
    final c = testController();
    await c.newGame();
    await untilYourTurn(c);
    // The auction (or the first play): the coach answers this turn.
    await runUntil(() => c.coach != null);
    final answer = c.coach!;
    if (c.game.phase == DdzPhase.bidding) {
      expect(answer.unit, ValueUnit.points);
      expect(answer.lines, hasLength(c.game.legalMoves().length), reason: 'every bid rated');
    }
    await playDeal(c);
    final graded = c.record.marks.whereType<Object>().toList();
    expect(graded, isNotEmpty);
    expect(c.averageScore, isNotNull);
    for (final (i, mark) in c.record.marks.indexed) {
      if (mark != null) expect(ddzParseMove(c.record.moves[i]).seat, 0, reason: 'only your moves are graded');
    }
    c.dispose();
  });

  test('a move the first answer left out is graded after asking the coach again with it included', () async {
    final c = testController(seed: 3);
    await c.newGame();
    String? left;
    for (var guard = 0; guard < 200 && !c.isOver; guard++) {
      await untilYourTurn(c);
      if (c.isOver) break;
      await runUntil(() => c.coach != null);
      final answer = c.coach!;
      // A legal move the coach didn't rate, if there is one.
      final unrated = [
        for (final m in c.game.legalMoves())
          if (!answer.rates(ddzMoveTextFor(c.game, m))) ddzMoveTextFor(c.game, m),
      ];
      if (left == null && unrated.isNotEmpty) {
        left = unrated.first;
        final at = c.record.moves.length;
        c.humanMove(left);
        await runUntil(() => c.record.marks[at] != null);
        expect(c.record.marks[at], isNotNull, reason: '$left graded with include');
        expect(c.record.marks[at]!.played, ddzMoveKey(left));
        break;
      }
      c.humanMove(easyMove(c));
    }
    expect(left, isNotNull, reason: 'some lead had more moves than the coach rates');
    c.dispose();
  });

  test('Free Play starts no coach and grades nothing', () async {
    final c = testController(training: false);
    await c.newGame();
    for (var guard = 0; guard < 200 && !c.isOver; guard++) {
      await untilYourTurn(c);
      if (c.isOver) break;
      expect(c.coachJobs, isEmpty);
      expect(c.coach, isNull);
      c.humanMove(easyMove(c));
    }
    expect(c.record.marks.every((m) => m == null), isTrue);
    expect(c.averageScore, isNull);
    c.dispose();
  });

  test('a new game cancels the coach and the bots, and Next deal keeps the seats, rules and toggles', () async {
    final backend = ManualBackend(kitJobs);
    final c = testController(jobs: Jobs.using(backend), rules: DdzRules.app, seed: 5);
    await c.newGame();
    await settle();
    expect(backend.running, isNotEmpty, reason: 'a bot or the coach is working');
    final working = [...backend.running];
    await c.newGame();
    expect(working.every((job) => job.token.isCancelled), isTrue);
    c.dispose();

    final d = testController(rules: DdzRules.app, seed: 6);
    await d.newGame();
    d.setExtra('counter', false);
    d.coachVisible = true;
    final seats = d.record.seats;
    await playDeal(d);
    await d.nextRound();
    expect(d.record.moves, isEmpty, reason: 'a new deal');
    expect(d.record.seats, seats);
    expect(ddzRulesOf(d.record), DdzRules.app);
    expect(d.record.extra['counter'], false);
    expect(d.coachVisible, isTrue, reason: 'the coach the player turned on stays on');
    expect(d.deals, 2);
    d.dispose();
  });

  test("the toggles (and the hand's sort) survive a new game too, and the next session starts with them", () async {
    final c = testController();
    await c.newGame();
    c.setExtra('counter', false);
    c.coachVisible = true;
    await c.newGame();
    expect(c.record.extra['counter'], false);
    expect(c.coachVisible, isTrue);
    final next = LandlordChoice.of(c.record);
    expect(next.extra, {'coach': true, 'counter': false, 'sort': 'rank'});
    c.dispose();

    final d = testController(extra: next.extra);
    await d.newGame();
    expect(d.record.extra['counter'], false);
    expect(d.coachVisible, isTrue);
    d.dispose();
  });

  test('a fresh game starts with the coach hidden; the move is still graded', () async {
    final c = testController();
    await c.newGame();
    expect(c.coachVisible, isFalse, reason: 'the best moves wait for the coach chip');
    expect(
      LandlordChoice.of(c.record).extra.containsKey('coach'),
      isFalse,
      reason: 'nothing to carry over until the player taps the chip',
    );
    await untilYourTurn(c);
    final at = c.record.moves.length;
    c.humanMove(easyMove(c));
    await runUntil(() => c.record.marks.elementAtOrNull(at) != null);
    expect(c.record.marks.elementAtOrNull(at), isNotNull, reason: 'Training still grades the move');
    c.dispose();
  });

  test('the record is saved at the start and after every move, and loads back as the same deal', () async {
    final store = LastGames();
    final c = testController(lastGames: store, training: false);
    await c.newGame();
    await store.flush();
    final atStart = await store.load(GameKeys.doudizhu, version: ddzRecordVersion, validate: ddzReplays);
    expect(atStart, isNotNull);
    for (var i = 0; i < 3 && !c.isOver; i++) {
      await untilYourTurn(c);
      if (c.isOver) break;
      c.humanMove(easyMove(c));
      final now = c.record.moves;
      await store.flush();
      final saved = await store.load(GameKeys.doudizhu, version: ddzRecordVersion, validate: ddzReplays);
      // The bots may have moved since (saved in their turn): this move is in.
      expect(saved!.moves.take(now.length), now);
    }
    c.dispose();
  });

  test('the selection: picked cards make a play only when it is legal now', () async {
    for (var seed = 1; seed < 20; seed++) {
      final c = testController(training: false, seed: seed);
      await c.newGame();
      for (var guard = 0; guard < 200 && !c.isOver; guard++) {
        await untilYourTurn(c);
        if (c.isOver) break;
        final hand = [...c.game.hands[0]];
        final ranks = {for (final id in hand) rankOfId(id)};
        if (c.game.phase == DdzPhase.playing && c.game.isLead && ranks.length > 1) {
          // One card always makes a single; two different ranks never a play.
          c.toggle(hand.first);
          expect(c.selectedPlay?.type, PlayType.solo);
          final other = hand.firstWhere((id) => rankOfId(id) != rankOfId(hand.first));
          c.toggle(other);
          expect(c.selectedPlay, isNull);
          expect(c.selectedMove, isNull);
          c.toggle(other);
          final at = c.record.moves.length;
          c.playSelection();
          expect(ddzParseMove(c.record.moves[at]).cardIds, [hand.first]);
          expect(c.selected, isEmpty);
          c.dispose();
          return;
        }
        c.humanMove(easyMove(c));
      }
      c.dispose();
    }
    fail('you never led');
  });

  test('the coach\'s "select" picks the cards of its move without playing it', () async {
    final c = testController(seed: 2);
    await c.newGame();
    for (var guard = 0; guard < 200 && !c.isOver; guard++) {
      await untilYourTurn(c);
      if (c.isOver) break;
      if (c.game.phase == DdzPhase.playing) {
        await runUntil(() => c.coach != null);
        final pick = c.coach!.pick;
        final moves = c.record.moves.length;
        c.selectMove(pick);
        expect(c.record.moves, hasLength(moves), reason: 'not played');
        if (ddzParseMove(pick).move is DdzPlay) expect(c.selectedMove, isNot(isNull));
        c.preview = pick;
        expect(c.previewCards.length, c.selected.length);
        c.dispose();
        return;
      }
      c.humanMove(easyMove(c));
    }
    fail('you never played');
  });
}
