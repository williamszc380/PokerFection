import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/bots/bot.dart';
import 'package:pokerfection/src/engine/actions.dart';
import 'package:pokerfection/src/engine/cards.dart';
import 'package:pokerfection/src/engine/events.dart';
import 'package:pokerfection/src/engine/poker_hand.dart';
import 'package:pokerfection/src/game/table_session.dart';
import 'package:pokerfection/src/gto/preflop/preflop_advisor.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tracker.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tree.dart';
import 'package:pokerfection/src/gto/spot_strategy.dart';

import 'held_solves.dart';

/// A bot with no solve yet plays a move fitted to the bots' menu
/// (PreflopTree.botMenuAt, fitToMenu). The point: whatever it plays, the
/// hand stays on the lines its solves will have, so every later decision
/// can still be answered once they arrive.
void main() {
  String menuOf(List<PreflopAction> actions) => actions.map((a) => a.toString()).join(', ');

  /// Every decision of [tree] but the user's first, with the actions
  /// played to reach it (from the end of the spec's history).
  void eachDecision(PreflopTree tree, void Function(PreflopDecision node, List<PreflopAction> path) visit) {
    void walk(PreflopNode node, List<PreflopAction> path) {
      if (node is! PreflopDecision) return;
      if (!(identical(node, tree.root) && node.player == tree.spec.hero)) visit(node, path);
      for (final (i, a) in node.actions.indexed) {
        walk(node.children[i], [...path, a]);
      }
    }

    walk(tree.root, const []);
  }

  PreflopSpec after(PreflopSpec spec, List<PreflopAction> path) => PreflopSpec(
        stacks: spec.stacks,
        smallBlind: spec.smallBlind,
        bigBlind: spec.bigBlind,
        ante: spec.ante,
        raiseRule: spec.raiseRule,
        history: [...spec.history, ...path],
      );

  group('the bots\' menu', () {
    final games = {
      'heads-up, 100 BB': PreflopSpec(stacks: [10000, 10000]),
      'heads-up, 15 BB': PreflopSpec(stacks: [1500, 1500]),
      'three players, mixed stacks and an ante': PreflopSpec(stacks: [2000, 3500, 1200], ante: 10),
      'six players, 100 BB': PreflopSpec(stacks: List.filled(6, 10000)),
      'six players, two short stacks': PreflopSpec(stacks: [10000, 2500, 10000, 1500, 10000, 6000]),
    };
    for (final MapEntry(key: name, value: spec) in games.entries) {
      test('is every decision of the whole game: $name', () {
        final tree = PreflopTree(spec);
        var decisions = 0;
        eachDecision(tree, (node, path) {
          decisions++;
          expect(menuOf(PreflopTree.botMenuAt(after(spec, path))), menuOf(node.actions), reason: '$path');
        });
        expect(decisions, tree.decisions.length);
      });
    }

    test('is every decision of the user\'s subgames after their first, off-menu moves included', () {
      // The user's first decision at each seat of a six-player table, after
      // everyone before folds or the first player opens: their subgame lets
      // them limp, call too often and pick their own sizes, and the bots'
      // nodes after those moves are what a bot with no subgame yet must hit.
      const fold = PreflopAction(PreflopMove.fold);
      final starts = <(int, List<PreflopAction>)>[
        (0, const []),
        (2, const [fold, fold]),
        (3, const [PreflopAction(PreflopMove.raise, 250), fold, PreflopAction(PreflopMove.call)]),
        (4, const [fold, fold, fold, fold]),
        (5, const [PreflopAction(PreflopMove.call), fold, fold, fold, PreflopAction(PreflopMove.call)]),
      ];
      for (final (hero, history) in starts) {
        final spec = PreflopSpec(stacks: List.filled(6, 10000), history: history, hero: hero);
        final tree = PreflopTree(spec);
        var decisions = 0;
        eachDecision(tree, (node, path) {
          decisions++;
          expect(menuOf(PreflopTree.botMenuAt(after(spec, path))), menuOf(node.actions),
              reason: 'user $hero after $history, then $path');
        });
        expect(decisions, tree.decisions.length - 1);
      }
    });

    test('is empty once nobody acts', () {
      final spec = PreflopSpec(stacks: [10000, 10000]);
      expect(PreflopTree.botMenuAt(after(spec, const [PreflopAction(PreflopMove.fold)])), isEmpty);
      expect(
          PreflopTree.botMenuAt(after(spec, const [PreflopAction(PreflopMove.call), PreflopAction(PreflopMove.check)])),
          isEmpty);
      // A history past the end of the betting.
      expect(
          PreflopTree.botMenuAt(after(spec, const [
            PreflopAction(PreflopMove.fold),
            PreflopAction(PreflopMove.fold),
          ])),
          isEmpty);
    });

    test('has no limp, no third cold call, and only fold or call over an all-in', () {
      final six = PreflopSpec(stacks: List.filled(6, 10000));
      // The first player: fold, open to 2.5 BB, or all-in.
      expect(menuOf(PreflopTree.botMenuAt(six)), 'fold, raise to 250, allIn');
      // After an open and two cold calls, a third player who isn't a blind may only fold or raise.
      const call = PreflopAction(PreflopMove.call);
      final cap = after(six, const [PreflopAction(PreflopMove.raise, 250), call, call]);
      expect(PreflopTree.botMenuAt(cap).map((a) => a.move), isNot(contains(PreflopMove.call)));
      // Over an all-in: fold or call.
      final jam = after(six, const [PreflopAction(PreflopMove.allIn, 10000)]);
      expect(menuOf(PreflopTree.botMenuAt(jam)), 'fold, call');
    });
  });

  group('fitToMenu', () {
    /// A six-player hand (seat 0 first to act) after [moves].
    PokerHand sixAfter(List<PlayerAction> moves, {List<int>? stacks}) {
      final hand = PokerHand(
        stacks: stacks ?? List.filled(6, 10000),
        buttonSeat: 3,
        smallBlind: 50,
        bigBlind: 100,
        random: Random(1),
      );
      expect(hand.toAct, 0);
      for (final m in moves) {
        hand.act(m);
      }
      return hand;
    }

    PlayerAction fit(PokerHand hand, PlayerAction move) =>
        fitToMenu(move, PreflopTree.botMenuAt(PreflopTracker.specAt(hand)), hand.legalActions());

    test('turns a limp into a fold', () {
      expect(fit(sixAfter(const []), const PlayerAction.call()).type, ActionType.fold);
    });

    test('moves a raise to the nearest size on the menu, and keeps an all-in', () {
      final hand = sixAfter(const []);
      // The menu: fold, open to 2.5 BB, all-in. Any raise short of all-in
      // is the open, as the solved game reads it.
      expect(fit(hand, const PlayerAction.raiseTo(400)).amount, 250);
      expect(fit(hand, const PlayerAction.raiseTo(9000)).amount, 250);
      expect(fit(hand, const PlayerAction.raiseTo(10000)).amount, 10000);
      // With no raise size left but all-in, a raise is all-in.
      final short = sixAfter(const [PlayerAction.raiseTo(250), PlayerAction.raiseTo(750), PlayerAction.raiseTo(1750)]);
      final menu = PreflopTree.botMenuAt(PreflopTracker.specAt(short));
      expect(menu.where((a) => a.move == PreflopMove.raise), isEmpty, reason: menu.join(', '));
      expect(fit(short, const PlayerAction.raiseTo(4000)).amount, 10000);
    });

    test('turns one cold call too many into a fold', () {
      final hand = sixAfter(const [PlayerAction.raiseTo(250), PlayerAction.call(), PlayerAction.call()]);
      expect(fit(hand, const PlayerAction.call()).type, ActionType.fold);
    });

    test('turns a raise over an all-in into a call', () {
      // A short stack goes all-in; the next player could re-raise, but the
      // solved game only folds or calls there.
      final hand = sixAfter(const [PlayerAction.raiseTo(1500)], stacks: [1500, ...List.filled(5, 10000)]);
      expect(hand.legalActions().canRaise, isTrue);
      expect(fit(hand, const PlayerAction.raiseTo(4000)).type, ActionType.call);
    });

    test('checks rather than folding for free', () {
      // The small blind completes; the big blind has nothing to call.
      final hand = sixAfter(const [
        PlayerAction.fold(),
        PlayerAction.fold(),
        PlayerAction.fold(),
        PlayerAction.fold(),
        PlayerAction.call(),
      ]);
      expect(hand.legalActions().canCheck, isTrue);
      expect(fit(hand, const PlayerAction.fold()).type, ActionType.check);
    });

    test('leaves moves on the menu as they are', () {
      final hand = sixAfter(const [PlayerAction.raiseTo(250)]);
      for (final move in const [PlayerAction.fold(), PlayerAction.call()]) {
        expect(fit(hand, move).type, move.type);
      }
      final menu = PreflopTree.botMenuAt(PreflopTracker.specAt(hand));
      for (final a in menu.where((a) => a.move == PreflopMove.raise || a.move == PreflopMove.allIn)) {
        expect(fit(hand, PlayerAction.raiseTo(a.raiseTo)).amount, a.raiseTo);
      }
    });
  });

  group('with every solve held, bots on the fallback keep the hand on the solved lines', () {
    /// Plays [hands] hands at a table of [players] on the device in Guess
    /// the GTO mode, with the solves held while the table plays: the hand
    /// follower (here, trackers fed a copy of the hand) catches up only now
    /// and then, or (every other hand) not before the hand is over, with no
    /// whole game at the table at all. The user plays like a person:
    /// limps, odd sizes and all. Then every decision the follower reaches
    /// must have its answer: the user's, and a GTO bot's after the flop.
    Future<void> play({required int players, required int hands, required BotStyle? bots, required int seed}) async {
      final rng = Random(seed);
      final stackBb = [100, 40, 20][seed % 3];
      final table = TableSession(
        TableConfig.quick(
            playerCount: players, stackBb: stackBb, opponentStyle: bots, guessGto: true, resetStacksEachHand: true),
        random: rng,
      );
      final blueprints = <PreflopSpec, PreflopAdvisor>{};
      var answered = 0, botAnswers = 0;
      for (var n = 0; n < hands; n++) {
        // Dealt from a known deck, so that the follower's copy gets the same cards.
        final deck = [for (var c = 0; c < 52; c++) PlayingCard(c)]..shuffle(rng);
        final holeCards = {for (var s = 0; s < players; s++) s: deck.sublist(2 * s, 2 * s + 2)};
        final board = deck.sublist(2 * players, 2 * players + 5);
        table.preset = (holeCards: holeCards, board: board);
        final hand = table.startHand();
        final spec = table.specOf(hand);
        final blueprint = blueprints[spec] ??= evenBlueprint(spec);
        // Every other hand, nothing at all is solved while the table plays.
        final lagging = n.isEven;
        const hero = TableSession.heroSeat;

        // The follower: a copy of the hand, dealt the same, and its trackers.
        final copy = PokerHand(
          stacks: [for (var s = 0; s < players; s++) hand.startingStackOf(s)],
          buttonSeat: hand.buttonSeat,
          smallBlind: hand.smallBlind,
          bigBlind: hand.bigBlind,
          ante: hand.ante,
          handNumber: hand.handNumber,
          raiseRule: hand.raiseRule,
          random: Random(0),
          holeCards: holeCards,
          board: board,
        );
        final trackers = table.trackersFor(copy, blueprint,
            subgames: instantSubgame, streets: instantStreet, needed: table.streetNeeded);
        final pre = trackers.preflop!, post = trackers.postflop!;
        if (!lagging) table.useTrackers(pre, post);
        final played = <ActionTaken>[];
        var followed = 0;
        String where() => 'seed $seed hand $n after ${played.take(followed).map((e) => '${e.seat}:${e.kind.name}'
            '${e.kind == ActionKind.raise || e.kind == ActionKind.bet ? e.streetBet : ''}').join(' ')}';

        // The follower's step: the tracking the table used to wait for.
        Future<void> track() async {
          if (copy.isOver) return;
          if (copy.street == Street.preflop && copy.toAct == hero) await pre.prepare(copy);
          await post.update(copy);
          await post.ready;
          final seat = copy.toAct;
          // Once the user has folded, a hand their own moves took off the
          // whole game (a limp, then a fold) has no lines left for the GTO
          // bots: that is the user's doing, not a fallback's.
          if (seat == null || (bots == BotStyle.gto && copy.isFolded(hero))) return;
          expect(pre.unavailable, isNot(NoAnswer.leftSolvedLines), reason: where());
          // With three or more after the flop, the user plays "the field",
          // and some of the field's moves have no reading in that game (an
          // overcall after the user closes the betting). Bots there play by
          // their rules whatever is solved, so their fallbacks are the moves
          // they always made: nothing to check.
          if (post.approximate) return;
          expect(post.unavailable, isNot(NoAnswer.leftSolvedLines), reason: where());
          if (seat == hero) {
            final spot = copy.street == Street.preflop ? pre.spotFor(copy) : post.spotFor(copy);
            expect(spot, isNotNull, reason: "${where()}: the user's answer");
            answered++;
          } else if (copy.street != Street.preflop && table.styles[seat] == BotStyle.gto && !post.approximate) {
            expect(post.spotFor(copy), isNotNull, reason: "${where()}: the GTO bot's strategy");
            botAnswers++;
          }
        }

        var started = false;
        Future<void> catchUp() async {
          if (!started) {
            started = true;
            await track();
          }
          while (followed < played.length) {
            final e = played[followed++];
            copy.act(switch (e.kind) {
              ActionKind.fold => const PlayerAction.fold(),
              ActionKind.check => const PlayerAction.check(),
              ActionKind.call => const PlayerAction.call(),
              ActionKind.bet || ActionKind.raise => PlayerAction.raiseTo(e.streetBet),
            });
            await track();
          }
        }

        if (!lagging) await catchUp();
        while (!hand.isOver) {
          final seat = hand.toAct!;
          final PlayerAction move;
          if (seat == hero) {
            // Like a person: often their own idea (limps and all), sometimes any size.
            final legal = hand.legalActions();
            final roll = rng.nextDouble();
            if (roll < 0.7) {
              move = Bot(BotStyle.humanLike[rng.nextInt(4)], rng).decide(hand, seat);
            } else if (roll < 0.85 && legal.canRaise) {
              move = PlayerAction.raiseTo(legal.minRaiseTo + rng.nextInt(legal.maxRaiseTo - legal.minRaiseTo + 1));
            } else {
              move = legal.canCheck ? const PlayerAction.check() : const PlayerAction.call();
            }
          } else {
            move = table.botDecision();
          }
          hand.act(move);
          played.addAll(hand.drainEvents().whereType<ActionTaken>());
          if (!lagging && rng.nextDouble() < 0.3) await catchUp();
        }
        await catchUp();
      }
      expect(answered, greaterThan(hands ~/ 2));
      if (bots == BotStyle.gto) expect(botAnswers, greaterThan(0));
    }

    for (final players in [2, 6, 8]) {
      test('$players players, random human-like bots', () async {
        await play(players: players, hands: 300, bots: null, seed: players);
      });
      test('$players players, GTO bots', () async {
        await play(players: players, hands: 300, bots: BotStyle.gto, seed: 100 + players);
      });
    }
  });
}
