import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/engine/cards.dart';
import 'package:pokerfection/src/gto/combos.dart';
import 'package:pokerfection/src/gto/gto_solutions.dart';
import 'package:pokerfection/src/gto/postflop/postflop_tree.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tree.dart';

import 'manual_solves.dart';

/// Lets the queue start whatever is next (jobs start in a microtask).
Future<void> settle() => Future<void>.delayed(Duration.zero);

/// A queue whose jobs finish when the test says, logging when each starts.
class _Jobs {
  _Jobs([int maxRunning = 1]) : queue = SolveQueue(maxRunning: maxRunning);

  final SolveQueue queue;
  final started = <String>[];
  final _finish = <String, Completer<String>>{};

  Future<String> add(String key, SolvePriority priority, {SolveOwner? owner}) =>
      queue.add(key, owner: owner, priority: priority, () {
        started.add(key);
        return (_finish[key] = Completer<String>()).future;
      });

  /// Ends the running job [key] with its name as the answer.
  Future<void> finish(String key) async {
    _finish[key]!.complete(key);
    await settle();
  }
}

void main() {
  group('SolveQueue', () {
    test('runs one job at a time, the most urgent first, the first asked for first among equals', () async {
      final jobs = _Jobs();
      // Asked for in one go: none has started yet, so all are compared.
      jobs.add('ahead', SolvePriority.ahead);
      jobs.add('grade 1', SolvePriority.grade);
      jobs.add('bot', SolvePriority.bot);
      jobs.add('grade 2', SolvePriority.grade);
      jobs.add('next hand', SolvePriority.nextHand);
      jobs.add('shown', SolvePriority.shown);
      expect(jobs.started, isEmpty, reason: 'jobs start in a microtask, not when asked for');
      await settle();
      expect(jobs.started, ['bot']);
      expect(jobs.queue.running, ['bot']);
      expect(jobs.queue.queued, ['shown', 'next hand', 'grade 1', 'grade 2', 'ahead']);

      for (final key in ['bot', 'shown', 'next hand', 'grade 1', 'grade 2']) {
        await jobs.finish(key);
      }
      expect(jobs.started, ['bot', 'shown', 'next hand', 'grade 1', 'grade 2', 'ahead']);
      await jobs.finish('ahead');
      expect(jobs.queue.running, isEmpty);
      expect(jobs.queue.queued, isEmpty);
    });

    test('a running job is never stopped: a more urgent one waits for it', () async {
      final jobs = _Jobs();
      final slow = jobs.add('ahead', SolvePriority.ahead);
      await settle();
      jobs.add('bot', SolvePriority.bot);
      await settle();
      expect(jobs.started, ['ahead']);
      await jobs.finish('ahead');
      expect(await slow, 'ahead');
      expect(jobs.started, ['ahead', 'bot']);
    });

    test('with room for more, that many run at once', () async {
      final jobs = _Jobs(2);
      jobs.add('a', SolvePriority.grade);
      jobs.add('b', SolvePriority.ahead);
      jobs.add('c', SolvePriority.bot);
      await settle();
      expect(jobs.started, ['c', 'a']);
      await jobs.finish('a');
      expect(jobs.started, ['c', 'a', 'b']);
    });

    test('a claim lifts the jobs its owner holds and the ones it asks for later, until it ends', () async {
      final jobs = _Jobs();
      final hand = SolveOwner(7);
      expect(hand.floor, SolvePriority.ahead, reason: 'a new owner lifts nothing');
      jobs.add('busy', SolvePriority.shown);
      jobs.add('mine', SolvePriority.ahead, owner: hand);
      jobs.add('theirs', SolvePriority.grade);
      await settle();
      expect(jobs.queue.queued, ['theirs', 'mine']);

      final waiting = hand.claim(SolvePriority.bot);
      expect(waiting.open, isTrue);
      expect(hand.floor, SolvePriority.bot);
      expect(jobs.queue.queued, ['mine', 'theirs']);
      expect(jobs.queue.priorityOf('mine'), SolvePriority.bot);

      // Asked for later, at a low priority: the claim lifts it too.
      jobs.add('mine later', SolvePriority.ahead, owner: hand);
      expect(jobs.queue.priorityOf('mine later'), SolvePriority.bot);
      expect(jobs.queue.queued, ['mine', 'mine later', 'theirs']);

      // Its reason is over (the bot has moved): each goes back to its own priority.
      waiting.end();
      expect(waiting.open, isFalse);
      expect(hand.floor, SolvePriority.ahead);
      expect(jobs.queue.priorityOf('mine'), SolvePriority.ahead);
      expect(jobs.queue.queued, ['theirs', 'mine', 'mine later']);

      await jobs.finish('busy');
      await jobs.finish('theirs');
      await jobs.finish('mine');
      expect(jobs.started, ['busy', 'theirs', 'mine', 'mine later']);
    });

    test('claims that overlap: the most urgent one open wins, whatever order they end in', () {
      for (final botEndsFirst in [true, false]) {
        final hand = SolveOwner(1);
        // Show GTO goes on, then a bot waits.
        final shown = hand.claim(SolvePriority.shown);
        final bot = hand.claim(SolvePriority.bot);
        expect(hand.floor, SolvePriority.bot);
        if (botEndsFirst) {
          // The bot moves; Show GTO is still on.
          bot.end();
          expect(hand.floor, SolvePriority.shown, reason: 'Show GTO is still on');
          shown.end();
        } else {
          // Show GTO goes off while the bot still waits.
          shown.end();
          expect(hand.floor, SolvePriority.bot, reason: 'the bot still waits');
          bot.end();
        }
        expect(hand.floor, SolvePriority.ahead, reason: 'both reasons are over');
      }
    });

    test('two claims at the same priority (two bots waiting one after the other) each last as long as their own '
        'reason', () {
      final hand = SolveOwner(1);
      final first = hand.claim(SolvePriority.bot);
      final second = hand.claim(SolvePriority.bot);
      first.end();
      expect(hand.floor, SolvePriority.bot, reason: 'the second bot still waits');
      second.end();
      expect(hand.floor, SolvePriority.ahead);
    });

    test('ending a claim twice, or after its hand was dropped or is over, does nothing; and a dropped or finished '
        'hand gets claims that are ended already', () {
      final queue = SolveQueue();
      final hand = SolveOwner(1);
      final shown = hand.claim(SolvePriority.shown);
      final bot = hand.claim(SolvePriority.bot);
      bot
        ..end()
        ..end();
      expect(hand.floor, SolvePriority.shown, reason: "ending the bot's claim again doesn't end Show GTO's");
      expect(shown.open, isTrue);

      final dropped = SolveOwner(2);
      final kept = dropped.claim(SolvePriority.bot);
      queue.drop(dropped);
      expect(dropped.floor, SolvePriority.ahead, reason: 'a dropped hand lifts nothing');
      kept.end();
      expect(dropped.claim(SolvePriority.bot).open, isFalse);
      expect(dropped.floor, SolvePriority.ahead);

      hand.finish();
      expect(shown.open, isFalse, reason: 'every claim ends at hand over');
      shown.end();
      expect(hand.claim(SolvePriority.shown).open, isFalse, reason: 'nothing is urgent in a hand that is over');
      expect(hand.floor, SolvePriority.ahead);
    });

    test('the floor falls while a job runs: the next job is picked by the priorities then', () async {
      final jobs = _Jobs();
      final hand = SolveOwner(1), next = SolveOwner(2);
      final waiting = hand.claim(SolvePriority.bot);
      jobs.add('mine', SolvePriority.grade, owner: hand);
      jobs.add('mine too', SolvePriority.grade, owner: hand);
      jobs.add('next game', SolvePriority.nextHand, owner: next);
      await settle();
      expect(jobs.started, ['mine'], reason: 'the bot waits for its hand');
      // The bot plays its fallback while "mine" runs; it isn't stopped.
      waiting.end();
      expect(jobs.queue.running, ['mine']);
      await jobs.finish('mine');
      expect(jobs.started, ['mine', 'next game'], reason: "the hand's grade goes after the next hand's game now");
    });

    test("a finished hand's solves count as grades at most, behind the next hand's game, whatever they were asked "
        'at', () async {
      final jobs = _Jobs();
      final hand = SolveOwner(1), next = SolveOwner(2);
      jobs.add('busy', SolvePriority.bot);
      jobs.add('street a GTO bot played from', SolvePriority.bot, owner: hand);
      jobs.add('a grade', SolvePriority.grade, owner: hand);
      jobs.add('a guess', SolvePriority.ahead, owner: hand);
      final watching = hand.claim(SolvePriority.shown);
      await settle();
      expect(jobs.queue.priorityOf('a grade'), SolvePriority.shown);

      hand.finish();
      expect(watching.open, isFalse);
      expect(jobs.queue.priorityOf('street a GTO bot played from'), SolvePriority.grade);
      expect(jobs.queue.priorityOf('a grade'), SolvePriority.grade);
      expect(jobs.queue.priorityOf('a guess'), SolvePriority.ahead, reason: 'nothing goes up');
      jobs.add('next game', SolvePriority.nextHand, owner: next);
      expect(jobs.queue.queued, ['next game', 'street a GTO bot played from', 'a grade', 'a guess']);
      // Someone with no hand (the charts screen) still gets what it asked for.
      jobs.queue.join('a grade', priority: SolvePriority.shown);
      expect(jobs.queue.priorityOf('a grade'), SolvePriority.shown);
      expect(jobs.queue.queued, ['a grade', 'next game', 'street a GTO bot played from', 'a guess']);
    });

    test('join shares a job, and a more urgent holder makes it more urgent', () async {
      final jobs = _Jobs();
      final a = SolveOwner(1), b = SolveOwner(2);
      jobs.add('busy', SolvePriority.bot);
      final first = jobs.add('shared', SolvePriority.ahead, owner: a);
      jobs.add('other', SolvePriority.grade);
      await settle();
      expect(jobs.queue.queued, ['other', 'shared']);

      expect(jobs.queue.join('shared', owner: b, priority: SolvePriority.shown), isTrue);
      expect(jobs.queue.priorityOf('shared'), SolvePriority.shown);
      expect(jobs.queue.queued, ['shared', 'other']);
      // Asking again for the same key joins too, and gets the same answer.
      final second = jobs.add('shared', SolvePriority.grade, owner: b);
      expect(jobs.queue.join('nothing like it', priority: SolvePriority.bot), isFalse);

      await jobs.finish('busy');
      await jobs.finish('shared');
      expect(await first, 'shared');
      expect(await second, 'shared');
      expect(jobs.started.where((k) => k == 'shared'), hasLength(1), reason: 'solved once');
      expect(jobs.queue.join('shared', priority: SolvePriority.bot), isFalse, reason: 'it has finished');
    });

    test("a job two hands share is lifted by either hand's claim; when the hand that claimed it is dropped, the job "
        "is back at the other hand's own priority", () async {
      final jobs = _Jobs();
      final waiting = SolveOwner(1), other = SolveOwner(2);
      jobs.add('busy', SolvePriority.bot);
      jobs.add('shared', SolvePriority.grade, owner: waiting);
      expect(jobs.queue.join('shared', owner: other, priority: SolvePriority.ahead), isTrue);
      jobs.add('next game', SolvePriority.nextHand);
      final bot = waiting.claim(SolvePriority.bot);
      await settle();
      expect(jobs.queue.queued, ['shared', 'next game']);

      jobs.queue.drop(waiting);
      expect(bot.open, isFalse, reason: 'a dropped hand lifts nothing');
      bot.end();
      expect(jobs.queue.priorityOf('shared'), SolvePriority.ahead, reason: 'the other hand only looks ahead');
      expect(jobs.queue.queued, ['next game', 'shared']);
      other.finish();
      expect(jobs.queue.priorityOf('shared'), SolvePriority.ahead, reason: 'hand over lowers, never lifts');
    });

    test('drop cancels the queued jobs only that owner holds; shared, ownerless and running jobs go on', () async {
      final jobs = _Jobs();
      final old = SolveOwner(1), next = SolveOwner(2);
      final running = jobs.add('running', SolvePriority.grade, owner: old);
      await settle();
      final alone = jobs.add('alone', SolvePriority.grade, owner: old);
      final shared = jobs.add('shared', SolvePriority.grade, owner: old);
      jobs.queue.join('shared', owner: next, priority: SolvePriority.ahead);
      final ownerless = jobs.add('ownerless', SolvePriority.grade, owner: old);
      jobs.queue.join('ownerless', priority: SolvePriority.ahead);
      // Work done ahead of time that nobody listens to: dropping it must
      // not surface as an unhandled error (the test would fail).
      jobs.add('unheard', SolvePriority.ahead, owner: old);
      final theirs = jobs.add('theirs', SolvePriority.nextHand, owner: next);

      expect(jobs.queue.drop(old), ['alone', 'unheard']);
      expect(old.dropped, isTrue);
      await expectLater(alone, throwsA(isA<SolveCancelled>()));
      expect(jobs.queue.queued, ['theirs', 'shared', 'ownerless']);
      expect(jobs.queue.priorityOf('shared'), SolvePriority.ahead, reason: "only the other hand's claim is left");

      // A dropped hand gets nothing new, but may still share what others want.
      await expectLater(jobs.add('new', SolvePriority.bot, owner: old), throwsA(isA<SolveCancelled>()));
      jobs.add('new, unheard', SolvePriority.bot, owner: old); // no unhandled error either
      final joined = jobs.add('theirs', SolvePriority.bot, owner: old);
      expect(jobs.queue.priorityOf('theirs'), SolvePriority.nextHand, reason: 'a dropped owner lifts nothing');

      await jobs.finish('running');
      expect(await running, 'running');
      for (final key in ['theirs', 'shared', 'ownerless']) {
        await jobs.finish(key);
      }
      expect(await joined, 'theirs');
      expect(await theirs, 'theirs');
      expect(await shared, 'shared');
      expect(await ownerless, 'ownerless');
      expect(jobs.started, ['running', 'theirs', 'shared', 'ownerless']);
    });

    test("a job's error goes to whoever asked, and the next job starts", () async {
      final queue = SolveQueue();
      final failing = queue.add<int>('bad', priority: SolvePriority.bot, () async => throw StateError('no'));
      final good = queue.add('good', priority: SolvePriority.bot, () async => 3);
      await expectLater(failing, throwsStateError);
      expect(await good, 3);
      // A job that throws before its first await is treated the same.
      final sync = queue.add<int>('sync', priority: SolvePriority.bot, () => throw StateError('at once'));
      await expectLater(sync, throwsStateError);
      expect(queue.running, isEmpty);
    });
  });

  group('GtoSolutions through the queue', () {
    final twoPlayers = PreflopSpec(stacks: [2000, 2000]);
    final threePlayers = PreflopSpec(stacks: [2000, 2000, 2000]);
    final subgame = PreflopSpec(stacks: [2000, 2000, 2000], hero: 0);
    Float64List subgameRanges() => Float64List(3 * 169)..fillRange(0, 3 * 169, 1);
    final board = [for (final c in parseCards('Kh Qd 7c 4s 2h')) c.index];
    final river = PostflopSpec(board: board, pot: 1000, stacks: [1000, 1000], bigBlind: 100);
    List<Float64List> streetRanges() => [
          for (var p = 0; p < 2; p++)
            Float64List(comboCount)
              ..fillRange(0, comboCount, 1)
              ..[0] = 0.5,
        ];

    test('solves wait their turn, most urgent first, and the runner hears who asked and how urgently', () async {
      final manual = ManualSolves();
      final solutions = withManualSolves(manual);
      final hand = SolveOwner(3), next = SolveOwner(4);
      // Nothing to say who asks: shown, as every solve was before the queue.
      final busy = solutions.solve(twoPlayers);
      await settle();
      expect(manual.only.kind, SolveKind.whole);
      expect(manual.only.priority, SolvePriority.shown);
      expect(manual.only.owner, isNull);

      final street = solutions.solvePostflop(river, streetRanges(), owner: hand, priority: SolvePriority.grade);
      final nextHand = solutions.solve(threePlayers, owner: next, priority: SolvePriority.nextHand);
      final sub = solutions.solveSubgame(subgame, subgameRanges(), owner: hand, priority: SolvePriority.ahead);
      await settle();
      expect(manual.pending, hasLength(1), reason: 'one at a time');

      manual.only.complete();
      await busy;
      await settle();
      expect(manual.only.kind, SolveKind.whole);
      expect(manual.only.preflop, threePlayers);
      expect(manual.only.owner, next);
      expect(manual.only.priority, SolvePriority.nextHand);

      // The hand's grade becomes something a bot waits for: its street and
      // its subgame both go first now.
      final waiting = hand.claim(SolvePriority.bot);
      manual.only.complete();
      await nextHand;
      await settle();
      expect(manual.only.kind, SolveKind.street);
      expect(manual.only.priority, SolvePriority.bot);
      manual.only.complete();
      await street;
      await settle();
      expect(manual.only.kind, SolveKind.subgame);
      expect(manual.only.priority, SolvePriority.bot);
      waiting.end();
      manual.only.complete();
      await sub;
      expect([for (final s in manual.started) s.kind],
          [SolveKind.whole, SolveKind.whole, SolveKind.street, SolveKind.subgame]);
    });

    test('a second request for the same solve shares it, and can make it more urgent', () async {
      final manual = ManualSolves();
      final solutions = withManualSolves(manual);
      final a = SolveOwner(1), b = SolveOwner(2);
      final busy = solutions.solve(twoPlayers);
      await settle();
      final firstStreet = solutions.solvePostflop(river, streetRanges(), owner: a, priority: SolvePriority.ahead);
      final firstGame = solutions.solve(threePlayers, owner: a, priority: SolvePriority.ahead);
      final other = solutions.solveSubgame(subgame, subgameRanges(), owner: a, priority: SolvePriority.grade);
      // The same street (equal ranges in new arrays) and the same game.
      final secondStreet = solutions.solvePostflop(river, streetRanges(), owner: b, priority: SolvePriority.bot);
      final secondGame = solutions.solve(threePlayers, owner: b, priority: SolvePriority.shown);
      expect(identical(firstStreet, secondStreet), isTrue);
      expect(identical(firstGame, secondGame), isTrue);

      manual.only.complete();
      await busy;
      await settle();
      expect(manual.only.kind, SolveKind.street);
      expect(manual.only.priority, SolvePriority.bot);
      manual.only.complete();
      await settle();
      expect(manual.only.kind, SolveKind.whole);
      expect(manual.only.priority, SolvePriority.shown);
      manual.only.complete();
      await settle();
      manual.only.complete();
      await Future.wait([firstStreet, firstGame, other]);
      expect(manual.started, hasLength(4), reason: 'each solved once');

      // Done: asked for again, the answers are kept.
      expect(await solutions.solvePostflop(river, streetRanges(), owner: b), same(await firstStreet));
      expect(solutions.ready(threePlayers), same(await firstGame));
      expect(manual.started, hasLength(4));
    });

    test("drop takes the hand's waiting solves off at once, so asking again solves again; "
        'ownerless and shared solves stay', () async {
      final manual = ManualSolves();
      final solutions = withManualSolves(manual);
      final old = SolveOwner(1), next = SolveOwner(2);
      final busy = solutions.solve(twoPlayers);
      await settle();
      final street = solutions.solvePostflop(river, streetRanges(), owner: old, priority: SolvePriority.grade);
      final sub = solutions.solveSubgame(subgame, subgameRanges(), owner: old, priority: SolvePriority.grade);
      final game = solutions.solve(threePlayers, owner: old, priority: SolvePriority.ahead);
      // Someone with no hand wants the game too: it is never dropped.
      final charts = solutions.solve(threePlayers);
      expect(solutions.queue.queued, hasLength(3));

      solutions.drop(old);
      await expectLater(street, throwsA(isA<SolveCancelled>()));
      await expectLater(sub, throwsA(isA<SolveCancelled>()));
      expect(solutions.queue.queued, hasLength(1), reason: "the game the charts screen wants is kept");

      // At once (before the cancel's error even arrives elsewhere), the next
      // hand's request for the same street and subgame queues new jobs.
      final again = solutions.solvePostflop(river, streetRanges(), owner: next, priority: SolvePriority.bot);
      final subAgain = solutions.solveSubgame(subgame, subgameRanges(), owner: next, priority: SolvePriority.grade);
      expect(solutions.queue.queued, hasLength(3));
      // The dropped hand gets nothing new.
      await expectLater(solutions.solvePostflop(river, [Float64List(comboCount), Float64List(comboCount)], owner: old),
          throwsA(isA<SolveCancelled>()));
      await expectLater(solutions.solve(PreflopSpec(stacks: [3000, 3000]), owner: old), throwsA(isA<SolveCancelled>()));
      solutions.solveSubgame(subgame, Float64List(3 * 169), owner: old); // unheard: no unhandled error

      manual.only.complete();
      await busy;
      await settle();
      expect(manual.only.kind, SolveKind.street);
      manual.only.complete();
      await again;
      await settle();
      expect(manual.only.kind, SolveKind.whole);
      manual.only.complete();
      expect(await game, same(await charts));
      await settle();
      manual.only.complete();
      await subAgain;
      expect(manual.started, hasLength(4));
    });

    test('a failed solve is not kept: the next request solves again', () async {
      final manual = ManualSolves();
      final solutions = withManualSolves(manual);
      final game = solutions.solve(twoPlayers);
      final street = solutions.solvePostflop(river, streetRanges());
      final sub = solutions.solveSubgame(subgame, subgameRanges());
      for (final failing in [game, street, sub]) {
        await settle();
        manual.only.fail();
        await expectLater(failing, throwsA(anything));
      }
      await settle();
      final again = [
        solutions.solve(twoPlayers),
        solutions.solvePostflop(river, streetRanges()),
        solutions.solveSubgame(subgame, subgameRanges()),
      ];
      for (var k = 0; k < 3; k++) {
        await settle();
        manual.only.complete();
      }
      await Future.wait(again);
      expect(manual.started, hasLength(6));
      expect(solutions.ready(twoPlayers), isNotNull);
    });

    test("the ranges are the caller's when asked for, even if its arrays change before the solve starts", () async {
      final manual = ManualSolves();
      final solutions = withManualSolves(manual);
      final busy = solutions.solve(twoPlayers);
      await settle();
      final ranges = streetRanges(), range = subgameRanges();
      final street = solutions.solvePostflop(river, ranges);
      final sub = solutions.solveSubgame(subgame, range);
      ranges[0][5] = 0;
      range[5] = 0;
      manual.only.complete();
      await busy;
      await settle();
      expect(manual.only.ranges.first[5], 1);
      manual.only.complete();
      await street;
      await settle();
      expect(manual.only.ranges.single[5], 1);
      manual.only.complete();
      await sub;
    });

    test("with warm starts off, every solve starts cold with the full iterations; on, a similar game's answer is "
        'used', () async {
      final manual = ManualSolves(auto: true);
      final solutions = withManualSolves(manual);
      await solutions.solve(threePlayers);
      await solutions.solve(PreflopSpec(stacks: [2100, 2000, 2000]));
      expect([for (final s in manual.started) (s.warmed, s.iterations)], [(false, 30), (false, 30)]);

      solutions.warm = true;
      await solutions.solve(PreflopSpec(stacks: [2200, 2000, 2000]));
      expect(manual.started.last.warmed, isTrue);
      expect(manual.started.last.iterations, solutions.warmIterations);
    });

    test('the answers are the same as solving at once on this thread, and progress ends at 1', () async {
      final manual = ManualSolves();
      final queued = withManualSolves(manual);
      final direct = withManualSolves(ManualSolves(auto: true))..runner = null;
      final spec = PreflopSpec(stacks: [2000, 1500, 2500]);
      final answer = queued.solve(spec);
      expect(queued.progressOf(spec).value, 0);
      await settle();
      manual.only.complete();
      final mine = (await answer).solution;
      final theirs = (await direct.solve(spec)).solution;
      expect(mine.strategy, theirs.strategy);
      expect(queued.progressOf(spec).value, 1);

      final ranges = streetRanges();
      final street = queued.solvePostflop(river, ranges);
      await settle();
      manual.only.complete();
      expect((await street).strategy, (await direct.solvePostflop(river, ranges)).strategy);
    });
  });
}
