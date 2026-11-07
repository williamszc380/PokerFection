import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/bots/bot.dart';
import 'package:pokerfection/src/engine/actions.dart';
import 'package:pokerfection/src/engine/events.dart';
import 'package:pokerfection/src/engine/poker_hand.dart';
import 'package:pokerfection/src/engine/positions.dart';
import 'package:pokerfection/src/game/hand_follower.dart';
import 'package:pokerfection/src/game/hand_snapshot.dart';
import 'package:pokerfection/src/game/table_session.dart';
import 'package:pokerfection/src/gto/postflop/postflop_tree.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tracker.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tree.dart';
import 'package:pokerfection/src/gto/solve_queue.dart';
import 'package:pokerfection/src/gto/spot_strategy.dart';
import 'package:pokerfection/src/online/event_codec.dart';

import '../gto/held_solves.dart';

/// The hand follower: a copy of the table's hand that follows it behind
/// the table, one step at a time, waiting for the solves each step starts
/// from, so the table itself never waits.
void main() {
  /// Heads-up Guess the GTO on the device, the user in the big blind (the
  /// bot acts first before the flop, the user first after it), the hand
  /// dealt and its follower started with held solves.
  ({TableSession session, PokerHand table, HandFollower follower, HeldSolves held}) dealt({int seed = 1}) {
    final session = TableSession(
      TableConfig.quick(playerCount: 2, heroPosition: Position.bb, opponentStyle: BotStyle.gto, guessGto: true),
      random: Random(seed),
    );
    final table = session.startHandWith(track: false);
    final held = HeldSolves();
    final follower = HandFollower(table: table, deal: table.drainEvents(), owner: SolveOwner(table.handNumber));
    follower.start(() async => session.trackersFor(follower.hand, evenBlueprint(session.specOf(table)),
        subgames: held.subgame, streets: held.street, needed: session.streetNeeded));
    return (session: session, table: table, follower: follower, held: held);
  }

  /// [move], as the bots' menu has it where [hand] is before the flop.
  PlayerAction onMenu(PokerHand hand, PlayerAction move) =>
      fitToMenu(move, PreflopTree.botMenuAt(PreflopTracker.specAt(hand)), hand.legalActions());

  /// Plays [move] on the table and hands the batch to the follower.
  void play(PokerHand table, HandFollower follower, PlayerAction move) {
    table.act(move);
    follower.step(table.drainEvents());
  }

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  int actionsIn(PokerHand hand) => hand.log.whereType<ActionTaken>().length;

  test('the copy plays every batch of the table, in order, once its solves are in', () async {
    final (:session, :table, :follower, :held) = dealt();
    play(table, follower, onMenu(table, const PlayerAction.raiseTo(250)));
    play(table, follower, const PlayerAction.call());
    for (var street = 0; street < 3; street++) {
      play(table, follower, const PlayerAction.check());
      play(table, follower, const PlayerAction.check());
    }
    expect(table.isOver, isTrue);
    for (var i = 0; i < 6; i++) {
      await flush();
      held.completeAll();
    }
    await follower.tail;
    expect(follower.failed, isNull);
    expect(follower.hand.isOver, isTrue);
    expect(sameEvents(follower.hand.log, table.log), isTrue, reason: 'the same events, in the same order');
    expect(session.hand, same(table), reason: 'the table hand is never touched');
  });

  test("the user's preflop decision holds the copy (not the table) until its subgame is solved", () async {
    final (:session, :table, :follower, :held) = dealt();
    play(table, follower, onMenu(table, const PlayerAction.raiseTo(250)));
    await flush();
    expect(held.subgames, hasLength(1), reason: "the user's subgame, asked for at their turn");
    // The table moves on at once: the user calls, the flop comes.
    play(table, follower, const PlayerAction.call());
    expect(table.street, Street.flop);
    await flush();
    expect(actionsIn(follower.hand), 1, reason: 'the copy waits at the decision');
    expect(held.streets, isEmpty);
    held.subgames.single.complete();
    await follower.tail;
    expect(actionsIn(follower.hand), 2);
    expect(follower.hand.street, Street.flop);
    expect(held.streets, hasLength(1), reason: 'the flop starts solving once the copy reaches it');
    expect(session.hand, same(table));
  });

  test("a street is solved only after the one before it: the turn's ranges come from the flop's solve", () async {
    final (:table, :follower, :held, session: _) = dealt();
    play(table, follower, onMenu(table, const PlayerAction.raiseTo(250)));
    play(table, follower, const PlayerAction.call());
    await flush();
    held.subgames.single.complete();
    await flush();
    play(table, follower, const PlayerAction.check());
    play(table, follower, const PlayerAction.check());
    expect(table.street, Street.turn);
    for (var i = 0; i < 4; i++) {
      await flush();
    }
    expect(held.streets, hasLength(1), reason: 'the turn waits for the flop');
    expect(follower.hand.street, Street.turn, reason: 'the copy is on the turn, its solve not asked for yet');
    held.streets.single.complete();
    await follower.tail;
    expect(held.streets, hasLength(2));
    expect((held.streets.last.spec as PostflopSpec).board, hasLength(4));
  });

  test("an answer is given at its decision, with the copy standing there, though the table moved on", () async {
    final (:table, :follower, :held, session: _) = dealt();
    play(table, follower, onMenu(table, const PlayerAction.raiseTo(250)));
    play(table, follower, const PlayerAction.call());
    // The user's turn on the flop: their answer is asked for, then they play on.
    expect(table.toAct, 0);
    final decision = decisionIdOf(table);
    final answers = <({GtoAnswer answer, int decision, Street street, int? toAct})>[];
    follower.answer((answer, at) =>
        answers.add((answer: answer, decision: decisionIdOf(at), street: at.street, toAct: at.toAct)));
    expect(follower.pendingAnswers, 1);
    play(table, follower, const PlayerAction.check());
    play(table, follower, const PlayerAction.check());
    expect(table.street, Street.turn);
    await flush();
    held.subgames.single.complete();
    await flush();
    expect(answers, isEmpty, reason: 'the flop is still being solved');
    held.streets.single.complete();
    await follower.tail;
    expect(answers, hasLength(1));
    expect(answers.single.answer.spot, isNotNull);
    expect(answers.single.decision, decision);
    expect(answers.single.street, Street.flop);
    expect(answers.single.toAct, 0);
    expect(follower.pendingAnswers, 0);
    expect(follower.hand.street, Street.turn, reason: 'then the copy went on');
  });

  test('an answer whose solve fails says so, and no later answer of the hand is worked out', () async {
    final (:table, :follower, :held, session: _) = dealt();
    play(table, follower, onMenu(table, const PlayerAction.raiseTo(250)));
    final answers = <GtoAnswer>[];
    follower.answer((answer, _) => answers.add(answer));
    await flush();
    held.subgames.single.fail();
    await follower.tail;
    expect(answers.single.spot, isNull);
    expect(answers.single.none, NoAnswer.solveFailed);
    play(table, follower, const PlayerAction.call());
    await follower.tail;
    expect(held.streets, isEmpty, reason: 'the flop would start from the failed subgame');
  });

  group('memory', () {
    test('past the flop, the subgames go: the answers still to come read only the streets', () async {
      final (:table, :follower, :held, session: _) = dealt();
      play(table, follower, onMenu(table, const PlayerAction.raiseTo(250)));
      play(table, follower, const PlayerAction.call());
      await flush();
      held.subgames.single.complete();
      await follower.tail;
      final answers = <GtoAnswer>[];
      follower.answer((answer, _) => answers.add(answer));
      final flop = follower.hand;
      expect(follower.preflop!.rangeOf(flop, 1), isNotNull, reason: 'read through the subgame');
      follower.trimForAnswers();
      expect(follower.preflop!.rangeOf(flop, 1), isNull, reason: 'the subgame is let go');
      held.streets.single.complete();
      await follower.tail;
      expect(answers.single.spot, isNotNull, reason: "the flop's answer still comes");
    });

    test('before the flop, nothing goes: the answer to come starts from every subgame', () async {
      final (:table, :follower, :held, session: _) = dealt();
      play(table, follower, onMenu(table, const PlayerAction.raiseTo(250)));
      final answers = <GtoAnswer>[];
      follower.answer((answer, _) => answers.add(answer));
      follower.trimForAnswers();
      await flush();
      held.subgames.single.complete();
      await follower.tail;
      expect(answers.single.spot, isNotNull);
      expect(follower.preflop!.unavailable, isNull);
    });

    test('an abandoned follower runs nothing more', () async {
      final (:table, :follower, :held, session: _) = dealt();
      await follower.tail;
      follower.abandoned = true;
      var answered = false;
      play(table, follower, onMenu(table, const PlayerAction.raiseTo(250)));
      follower.answer((_, _) => answered = true);
      await follower.tail;
      expect(actionsIn(follower.hand), 0);
      expect(held.subgames, isEmpty);
      expect(answered, isFalse);
    });
  });

  test('a bot waits for the copy to catch up, and a GTO bot after the flop for its street too', () async {
    final (:table, :follower, :held, session: _) = dealt();
    play(table, follower, onMenu(table, const PlayerAction.raiseTo(250)));
    play(table, follower, const PlayerAction.call());
    play(table, follower, const PlayerAction.check());
    var ready = false;
    unawaited(follower.readyFor(1, BotStyle.gto).then((_) => ready = true));
    await flush();
    held.subgames.single.complete();
    await follower.tail;
    await flush();
    expect(ready, isFalse, reason: 'caught up, but the flop is still being solved');
    held.streets.single.complete();
    await flush();
    expect(ready, isTrue);
  });
}
