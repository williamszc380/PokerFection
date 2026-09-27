import 'dart:math';

import '../../engine/actions.dart';
import '../../engine/events.dart';
import '../../engine/poker_hand.dart';
import '../../engine/positions.dart';
import '../../engine/rules.dart';
import '../action_menu.dart';
import '../hand_classes.dart';
import '../spot_strategy.dart';
import 'preflop_solver.dart';
import 'preflop_tree.dart';

/// A solved preflop game (the whole game, or the user's subgame), with the
/// helpers to use it in real hands.
class PreflopAdvisor {
  PreflopAdvisor(this.solution);

  final PreflopSolution solution;

  PreflopTree get tree => solution.tree;

  /// The preflop game for a hand: stacks (given per seat) rearranged into
  /// the solver's preflop order, plus the blinds, ante and raise rule. For
  /// the user's subgame, also their seat, raise sizes and the actions so far.
  static PreflopSpec specFor({
    required List<int> stacksBySeat,
    required int buttonSeat,
    required int smallBlind,
    required int bigBlind,
    required int ante,
    RaiseRule raiseRule = RaiseRule.standard,
    int? heroSeat,
    List<double> raiseMultiples = PreflopSettings.defaultRaiseMultiples,
    List<PreflopAction> history = const [],
  }) {
    final n = stacksBySeat.length;
    final first = bigBlindSeat(n, buttonSeat) + 1;
    return PreflopSpec(
      stacks: [for (var k = 0; k < n; k++) stacksBySeat[(first + k) % n]],
      smallBlind: smallBlind,
      bigBlind: bigBlind,
      ante: ante,
      raiseRule: raiseRule,
      raiseMultiples: raiseMultiples,
      history: history,
      hero: heroSeat == null ? -1 : (heroSeat - first + 2 * n) % n,
    );
  }

  /// Position of [seat] in the solver's preflop order (0 = first to act).
  static int orderOf(PokerHand hand, int seat) =>
      positionsForTable(hand.playerCount).indexOf(hand.positionOf(seat));

  /// [e] as a move in the solver's terms.
  static PreflopAction treeAction(ActionTaken e) => switch (e.kind) {
        ActionKind.fold => const PreflopAction(PreflopMove.fold),
        ActionKind.check => const PreflopAction(PreflopMove.check),
        ActionKind.call => const PreflopAction(PreflopMove.call),
        ActionKind.bet || ActionKind.raise =>
          PreflopAction(e.isAllIn ? PreflopMove.allIn : PreflopMove.raise, e.streetBet),
      };

  /// The tree action matching [e]. A raise size the tree doesn't have is
  /// mapped to the nearest one it has (so bots can keep playing when
  /// someone picks their own sizes); -1 if nothing fits.
  static int matchAction(PreflopDecision node, ActionTaken e) {
    final raised = e.kind == ActionKind.bet || e.kind == ActionKind.raise;
    var nearest = -1, allIn = -1;
    var nearestDistance = double.infinity;
    for (var i = 0; i < node.actions.length; i++) {
      final a = node.actions[i];
      final matches = switch (a.move) {
        PreflopMove.fold => e.kind == ActionKind.fold,
        PreflopMove.check => e.kind == ActionKind.check,
        PreflopMove.call => e.kind == ActionKind.call,
        PreflopMove.raise => raised && !e.isAllIn && e.streetBet == a.raiseTo,
        PreflopMove.allIn => raised && e.isAllIn,
      };
      if (matches) return i;
      if (a.move == PreflopMove.allIn) allIn = i;
      if (raised && a.move == PreflopMove.raise) {
        final distance = (log(a.raiseTo) - log(e.streetBet)).abs();
        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearest = i;
        }
      }
    }
    if (!raised) return -1;
    return e.isAllIn ? (allIn >= 0 ? allIn : nearest) : (nearest >= 0 ? nearest : allIn);
  }

  /// The user's answer at [node] (the start of their subgame), for every
  /// choice of their menu (see [actionMenu]); the ones not allowed here are
  /// greyed out.
  SpotStrategy spotAt(PreflopDecision node, PokerHand hand) {
    final cards = hand.holeCards(hand.toAct!);
    final handClass = handClassOf(cards[0], cards[1]);
    final invested = node.contributions[node.player];
    return answerFor(
      actionMenu(hand, preflopSizes: tree.spec.raiseMultiples, postflopSizes: const []),
      handName: handClassName(handClass),
      indexOf: (choice) => node.actions.indexWhere((a) => switch (choice.kind) {
            SpotActionKind.fold => a.move == PreflopMove.fold,
            SpotActionKind.check => a.move == PreflopMove.check,
            SpotActionKind.call => a.move == PreflopMove.call,
            SpotActionKind.raise => a.move == PreflopMove.raise && a.raiseTo == choice.amount,
            SpotActionKind.allIn => a.move == PreflopMove.allIn,
          }),
      frequency: (i) => solution.frequency(node, i, handClass),
      value: (i) {
        final value = solution.value(node, i, handClass);
        // Relative to folding now: add back what this player has already put in.
        return value.isNaN ? double.nan : (value + invested) / hand.bigBlind;
      },
    );
  }

  /// A move for the bot to act at [node], drawn from the solved strategy
  /// for the bot's starting hand.
  PlayerAction sampleAt(PreflopDecision node, PokerHand hand, Random random) {
    final cards = hand.holeCards(hand.toAct!);
    final handClass = handClassOf(cards[0], cards[1]);
    var roll = random.nextDouble();
    var pick = node.actions.length - 1;
    for (var i = 0; i < node.actions.length; i++) {
      roll -= solution.frequency(node, i, handClass);
      if (roll < 0) {
        pick = i;
        break;
      }
    }
    final a = node.actions[pick];
    final legal = hand.legalActions();
    return switch (a.move) {
      PreflopMove.fold => legal.canFold ? const PlayerAction.fold() : const PlayerAction.check(),
      PreflopMove.check => const PlayerAction.check(),
      PreflopMove.call => const PlayerAction.call(),
      PreflopMove.raise || PreflopMove.allIn => PlayerAction.raiseTo(a.raiseTo.clamp(legal.minRaiseTo, legal.maxRaiseTo)),
    };
  }

}

/// An available action drawn at random from the GTO frequencies of [spot].
PlayerAction drawAction(SpotStrategy spot, Random random) {
  var roll = random.nextDouble();
  var last = -1;
  for (var i = 0; i < spot.actions.length; i++) {
    if (!spot.actions[i].available || spot.frequencies[i] <= 0) continue;
    last = i;
    roll -= spot.frequencies[i];
    if (roll < 0) return spot.actions[i].action;
  }
  return spot.actions[last >= 0 ? last : 1].action;
}
