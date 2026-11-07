import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/bots/bot.dart';
import 'package:pokerfection/src/engine/actions.dart';
import 'package:pokerfection/src/engine/events.dart';
import 'package:pokerfection/src/engine/poker_hand.dart';
import 'package:pokerfection/src/engine/positions.dart';
import 'package:pokerfection/src/game/table_session.dart';
import 'package:pokerfection/src/gto/postflop/postflop_tracker.dart';
import 'package:pokerfection/src/gto/preflop/preflop_advisor.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tracker.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tree.dart';
import 'package:pokerfection/src/gto/spot_strategy.dart';

import '../gto/held_solves.dart';

/// TableSession.decisionOn, the bots' move when the solve it would play
/// from isn't there yet, and the trackers' rules for what gets solved: a
/// fallback may change what a bot does, never whether later decisions can
/// be graded.
void main() {
  /// A Guess the GTO table on the device, with the user in [position], and
  /// its current hand followed by trackers with held solves (the session's
  /// own, as the hand follower would hand them over).
  ({TableSession session, PokerHand hand, HeldSolves held}) training({
    int players = 6,
    Position position = Position.utg,
    BotStyle? bots = BotStyle.tag,
    bool guessGto = true,
    int seed = 1,
  }) {
    final session = TableSession(
      TableConfig.quick(
          playerCount: players, opponentStyle: bots, heroPosition: position, guessGto: guessGto),
      random: Random(seed),
    );
    final hand = session.startHand();
    final held = HeldSolves();
    final trackers = session.trackersFor(hand, evenBlueprint(session.specOf(hand)),
        subgames: held.subgame, streets: held.street, needed: session.streetNeeded);
    session.useTrackers(trackers.preflop, trackers.postflop);
    return (session: session, hand: hand, held: held);
  }

  /// Whether [move] is one of the bots' menu where [hand] is, before the flop.
  bool onMenu(PokerHand hand, PlayerAction move) {
    final menu = PreflopTree.botMenuAt(PreflopTracker.specAt(hand));
    final legal = hand.legalActions();
    return menu.any((a) => switch (a.move) {
          PreflopMove.fold => move.type == ActionType.fold,
          PreflopMove.check => move.type == ActionType.check,
          PreflopMove.call => move.type == ActionType.call,
          PreflopMove.raise => move.type == ActionType.raise && move.amount == a.raiseTo,
          PreflopMove.allIn => move.type == ActionType.raise && move.amount == legal.maxRaiseTo,
        });
  }

  group('before the flop', () {
    test('with no whole game yet, every bot plays a move of the bots\' menu', () {
      for (var seed = 0; seed < 40; seed++) {
        final session = TableSession(
          TableConfig.quick(playerCount: 8, opponentStyle: BotStyle.station, guessGto: true),
          random: Random(seed),
        );
        final hand = session.startHand();
        expect(session.preflop, isNull);
        while (!hand.isOver && hand.street == Street.preflop) {
          final PlayerAction move;
          if (hand.toAct == session.hero) {
            move = hand.legalActions().canCheck ? const PlayerAction.check() : const PlayerAction.fold();
          } else {
            move = session.botDecision();
            expect(onMenu(hand, move), isTrue, reason: 'seed $seed: $move');
          }
          hand.act(move);
        }
        // The whole game arrives: it follows every move made so far.
        final trackers = session.trackersFor(hand, evenBlueprint(session.specOf(hand)), subgames: instantSubgame);
        for (var seat = 0; seat < 8; seat++) {
          expect(trackers.preflop!.rangeOf(hand, seat), isNotNull, reason: 'seed $seed, seat $seat');
        }
      }
    });

    test("after the user's limp, with its subgame held, bots stay on that subgame's lines", () async {
      final t = training();
      final hand = t.hand, pre = t.session.preflop!;
      // The follower starts the user's subgame; it doesn't finish yet.
      final solving = pre.prepare(hand);
      expect(t.held.subgames, hasLength(1));
      hand.act(const PlayerAction.call()); // a limp: not in the whole game
      expect(pre.rangeOf(hand, 1), isNull, reason: 'the whole game alone has no limp');
      while (!hand.isOver && hand.street == Street.preflop && hand.toAct != t.session.hero) {
        final move = t.session.botDecision();
        expect(onMenu(hand, move), isTrue, reason: '$move');
        hand.act(move);
      }
      t.held.subgames.single.complete();
      await solving;
      // The subgame follows the hand: every range, and the user's next answer.
      for (var seat = 0; seat < 6; seat++) {
        expect(pre.rangeOf(hand, seat), isNotNull, reason: 'seat $seat');
      }
      if (hand.toAct == t.session.hero) {
        final next = pre.prepare(hand);
        t.held.completeAll();
        await next;
        expect(t.session.heroSpot(), isNotNull);
      }
    });

    test('a bot draws from the solves when they follow the hand, fitted to the menu', () {
      final t = training(bots: BotStyle.gto);
      t.hand.act(const PlayerAction.fold());
      final pre = t.session.preflop!;
      while (!t.hand.isOver && t.hand.street == Street.preflop) {
        expect(pre.sample(t.hand, Random(0)), isNotNull, reason: 'the whole game covers folds');
        final move = t.session.botDecision();
        expect(onMenu(t.hand, move), isTrue);
        t.hand.act(move);
      }
    });

    test('free play bots with human styles play their own moves, limps and all', () {
      var limps = 0;
      for (var seed = 0; seed < 30; seed++) {
        final session = TableSession(
          TableConfig.quick(playerCount: 6, opponentStyle: BotStyle.station),
          random: Random(seed),
        );
        final hand = session.startHand();
        while (!hand.isOver && hand.street == Street.preflop) {
          if (hand.toAct == session.hero) {
            hand.act(hand.legalActions().canCheck ? const PlayerAction.check() : const PlayerAction.fold());
            continue;
          }
          final blind = {Position.sb, Position.bb}.contains(hand.positionOf(hand.toAct!));
          final unopened = hand.raisesThisStreet == 0;
          final move = session.botDecision();
          if (move.type == ActionType.call && unopened && !blind) limps++;
          hand.act(move);
        }
      }
      expect(limps, greaterThan(0));
    });

    test('trackers belong to their own hand only', () async {
      final t = training();
      final other = PokerHand(
        stacks: List.filled(6, 10000),
        buttonSeat: t.hand.buttonSeat,
        smallBlind: 50,
        bigBlind: 100,
        handNumber: t.hand.handNumber + 1,
        random: Random(3),
      );
      // The same betting, so the same subgame would answer it, but other cards.
      final solving = t.session.preflop!.prepare(t.hand);
      t.held.completeAll();
      await solving;
      expect(t.session.spotAt(t.hand), isNotNull);
      expect(t.session.spotAt(other), isNull);
    });
  });

  group('after the flop', () {
    /// Heads-up against a GTO bot: the user on the button limps, the bot
    /// checks, and the flop's solve is asked for and held.
    Future<({TableSession session, PokerHand hand, HeldSolves held})> onTheFlop() async {
      final t = training(players: 2, position: Position.btn, bots: BotStyle.gto);
      t.hand.act(const PlayerAction.call());
      t.hand.act(const PlayerAction.check());
      expect(t.hand.street, Street.flop);
      await t.session.postflop!.update(t.hand);
      expect(t.held.streets, hasLength(1));
      return t;
    }

    test("a bet is moved to the street's sizes before the solve is done, the same as after", () async {
      final t = await onTheFlop();
      final post = t.session.postflop!;
      const sizes = [150, 300, 700, 2000, 9000];
      final early = [for (final to in sizes) post.snap(t.hand, PlayerAction.raiseTo(to)).amount];
      // With no tracker at all (no whole game yet), the hand alone gives the same.
      final untracked = [
        for (final to in sizes)
          PostflopTracker.snapToBetting(t.hand, PlayerAction.raiseTo(to), heroSeat: 0, bigBlind: 100).amount,
      ];
      expect(untracked, early);
      t.held.streets.single.complete();
      await post.ready;
      final late = [for (final to in [150, 300, 700, 2000, 9000]) post.snap(t.hand, PlayerAction.raiseTo(to)).amount];
      expect(early, late);
    });

    test("a raise the street has no size for goes all-in, and the user's next answer still comes", () async {
      final t = await onTheFlop();
      final hand = t.hand, post = t.session.postflop!;
      hand.act(post.snap(hand, const PlayerAction.raiseTo(150))); // the bot bets
      hand.act(PlayerAction.raiseTo(hand.legalActions().minRaiseTo * 2)); // the user raises
      // The bot faces a raise: the solved street lets it fold, call or go
      // all-in, never raise a little. Its rule raise goes all-in.
      final legal = hand.legalActions();
      final reraise = post.snap(hand, PlayerAction.raiseTo(legal.minRaiseTo));
      expect(reraise.amount, legal.maxRaiseTo);
      hand.act(reraise);
      t.held.streets.single.complete();
      await post.ready;
      // The user's decision facing the all-in is on the solved lines.
      expect(hand.toAct, t.session.hero);
      expect(t.session.heroSpot(), isNotNull);
    });

    test('a GTO bot plays by its rules while the street is held, and the street still follows', () async {
      for (var seed = 0; seed < 20; seed++) {
        final t = training(players: 2, position: Position.btn, bots: BotStyle.gto, seed: seed);
        final hand = t.hand, post = t.session.postflop!;
        hand.act(const PlayerAction.raiseTo(250));
        hand.act(const PlayerAction.call());
        await post.update(hand);
        // Flop: the bot acts first, with nothing solved.
        expect(post.sample(hand, Random(0)), isNull);
        while (!hand.isOver && hand.street == Street.flop) {
          hand.act(hand.toAct == t.session.hero
              ? (hand.legalActions().canCheck ? const PlayerAction.check() : const PlayerAction.call())
              : t.session.botDecision());
        }
        t.held.completeAll();
        await post.ready;
        await post.update(hand);
        expect(post.unavailable, isNot(NoAnswer.leftSolvedLines), reason: 'seed $seed');
        if (!hand.isOver && hand.toAct != null) expect(t.held.streets, hasLength(2), reason: 'seed $seed: the turn');
      }
    });

    test("a street the follower hasn't begun gets the sizes it will have", () async {
      final t = await onTheFlop();
      final hand = t.hand, post = t.session.postflop!;
      hand.act(const PlayerAction.check());
      hand.act(const PlayerAction.check());
      expect(hand.street, Street.turn);
      // The follower is still on the flop: the turn's sizes come from the hand.
      const sizes = [150, 300, 700, 2000];
      final early = [for (final to in sizes) post.snap(hand, PlayerAction.raiseTo(to)).amount];
      final untracked = [
        for (final to in sizes)
          PostflopTracker.snapToBetting(hand, PlayerAction.raiseTo(to), heroSeat: 0, bigBlind: 100).amount,
      ];
      expect(untracked, early);
      t.held.streets.single.complete();
      await post.ready;
      await post.update(hand);
      expect(t.held.streets, hasLength(2));
      t.held.streets.last.complete();
      await post.ready;
      final late = [for (final to in [150, 300, 700, 2000]) post.snap(hand, PlayerAction.raiseTo(to)).amount];
      expect(early, late);
    });
  });

  group('what gets solved', () {
    test('after a failed subgame, no later subgame is asked for and the flop has no answers', () async {
      final t = training();
      final hand = t.hand, pre = t.session.preflop!, post = t.session.postflop!;
      final solving = pre.prepare(hand);
      t.held.subgames.single.fail();
      await solving;
      expect(pre.unavailable, NoAnswer.solveFailed);
      hand.act(const PlayerAction.raiseTo(250));
      hand.act(const PlayerAction.raiseTo(750)); // a 3-bet comes back to the user
      while (hand.toAct != t.session.hero) {
        hand.act(const PlayerAction.fold());
      }
      await pre.prepare(hand);
      expect(t.held.subgames, hasLength(1), reason: 'no subgame from a walk without the failed one');
      hand.act(const PlayerAction.call());
      expect(hand.street, Street.flop);
      await post.update(hand);
      expect(t.held.streets, isEmpty);
      expect(post.unavailable, NoAnswer.solveFailed);
    });

    test("a street nobody needs isn't solved", () async {
      final t = training();
      final hand = t.hand, post = t.session.postflop!;
      hand.act(const PlayerAction.fold()); // the user
      hand.act(const PlayerAction.raiseTo(250));
      while (hand.street == Street.preflop) {
        hand.act(hand.toAct == 5 ? const PlayerAction.call() : const PlayerAction.fold());
      }
      expect(t.session.streetNeeded(hand), isFalse);
      await post.update(hand);
      expect(t.held.streets, isEmpty);
      expect(post.unavailable, NoAnswer.notNeeded);
    });

    test('a street with a GTO bot still in is solved, even after the user folds', () async {
      final t = training();
      final hand = t.hand, post = t.session.postflop!;
      t.session.setStyle(5, BotStyle.gto);
      hand.act(const PlayerAction.fold());
      hand.act(const PlayerAction.raiseTo(250));
      while (hand.street == Street.preflop) {
        hand.act(hand.toAct == 5 ? const PlayerAction.call() : const PlayerAction.fold());
      }
      expect(t.session.streetNeeded(hand), isTrue);
      await post.update(hand);
      expect(t.held.streets, hasLength(1));
    });

    test('letting go of subgames keeps the answers kept, and nothing is worked out without the others',
        () async {
      final t = training();
      final hand = t.hand, pre = t.session.preflop!, post = t.session.postflop!;
      var solving = pre.prepare(hand);
      t.held.completeAll();
      await solving;
      hand.act(const PlayerAction.raiseTo(250));
      hand.act(const PlayerAction.raiseTo(750));
      while (hand.toAct != t.session.hero) {
        hand.act(const PlayerAction.fold());
      }
      solving = pre.prepare(hand);
      t.held.completeAll();
      await solving;
      final k = PreflopTracker.historyOf(hand).length;
      final answer = pre.spotFor(hand);
      expect(answer, isNotNull);
      pre.dropSubgames(keep: {k});
      expect(pre.spotFor(hand)?.frequencies, answer!.frequencies, reason: 'the answer kept');
      expect(pre.rangeOf(hand, 1), isNull, reason: 'its walk starts in the subgame let go of');
      expect(pre.unavailable, NoAnswer.notNeeded);
      hand.act(const PlayerAction.call());
      await post.update(hand);
      expect(t.held.streets, isEmpty);
      expect(t.held.subgames, hasLength(2));
    });

    test('a subgame finishing after it was let go of is not kept', () async {
      final t = training();
      final pre = t.session.preflop!;
      final solving = pre.prepare(t.hand);
      pre.dropSubgames();
      t.held.completeAll();
      await solving;
      expect(pre.spotFor(t.hand), isNull);
    });
  });

  group('the trackers', () {
    test("aren't made for a whole game that isn't the hand's", () {
      final t = training();
      final wrong = evenBlueprint(PreflopAdvisor.specFor(
          stacksBySeat: List.filled(6, 5000), buttonSeat: t.hand.buttonSeat, smallBlind: 50, bigBlind: 100, ante: 0));
      final trackers = t.session.trackersFor(t.hand, wrong, subgames: instantSubgame);
      expect(trackers.preflop, isNull);
      expect(trackers.postflop, isNull);
    });

    test('are left to the hand follower when the session deals without tracking', () {
      final session = TableSession(TableConfig.quick(guessGto: true), random: Random(2),
          solveSubgame: instantSubgame, solvePostflop: instantStreet);
      session.advisor = evenBlueprint(session.upcomingSpec);
      session.startHandWith(track: false);
      expect(session.preflop, isNull);
      expect(session.postflop, isNull);
      // The same table, tracking itself, as today and online.
      final again = TableSession(TableConfig.quick(guessGto: true), random: Random(2),
          solveSubgame: instantSubgame, solvePostflop: instantStreet);
      again.advisor = evenBlueprint(again.upcomingSpec);
      final hand = again.startHand();
      expect(again.preflop?.handNumber, hand.handNumber);
      expect(again.postflop, isNotNull);
    });
  });
}
