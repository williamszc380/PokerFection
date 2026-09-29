import '../engine/actions.dart';
import '../engine/events.dart';
import '../engine/poker_hand.dart';
import 'postflop/postflop_tree.dart';
import 'preflop/preflop_tree.dart';
import 'spot_strategy.dart';

/// The user's choices at their decision: fold, check or call, each size of
/// their menu, all-in. Sizes bigger than the player's whole stack are left
/// out; other choices not allowed here stay in the list, marked unavailable
/// with the reason (greyed out), so the buttons move around as little as
/// possible.
///
/// Before the flop the sizes are multiples of the bet faced (2x means a
/// raise to 2 BB when first in); after it, shares of the pot (for a raise,
/// of the pot after calling).
List<SpotAction> actionMenu(
  PokerHand hand, {
  required List<double> preflopSizes,
  required List<double> postflopSizes,
}) {
  final legal = hand.legalActions();
  final preflop = hand.street == Street.preflop;
  final betting = legal.isBet;
  // Same cut-off as the solved games, whose menus must match this one.
  final nearlyAllIn = preflop ? const PreflopSettings().nearlyAllIn : PostflopSpec.nearlyAllIn;
  final actions = <SpotAction>[
    SpotAction(
      kind: SpotActionKind.fold,
      amount: 0,
      action: const PlayerAction.fold(),
      unavailable: legal.canFold ? null : Unavailable.checkIsFree,
    ),
    legal.canCheck
        ? const SpotAction(kind: SpotActionKind.check, amount: 0, action: PlayerAction.check())
        : SpotAction(kind: SpotActionKind.call, amount: legal.toCall, action: const PlayerAction.call()),
  ];
  final seen = <int>{};
  for (final size in preflop ? preflopSizes : postflopSizes) {
    final to = preflop
        ? PreflopTree.raiseSize(legal.currentBet, size)
        : PostflopTree.sizeTo(legal.currentBet, legal.streetBet, legal.pot, size, hand.bigBlind);
    // More than the player has: not shown at all (all-in covers it).
    if (to >= legal.maxRaiseTo) continue;
    final Unavailable? reason;
    if (!legal.canRaise) {
      reason = Unavailable.raisingNotAllowed;
    } else if (to < legal.minRaiseTo) {
      reason = betting ? Unavailable.belowMinBet : Unavailable.belowMinRaise;
    } else if (to >= legal.maxRaiseTo * nearlyAllIn) {
      reason = Unavailable.nearlyAllIn;
    } else if (!seen.add(to)) {
      reason = Unavailable.sameAmount;
    } else {
      reason = null;
    }
    actions.add(SpotAction(
      kind: SpotActionKind.raise,
      amount: to,
      action: PlayerAction.raiseTo(to.clamp(legal.minRaiseTo, legal.maxRaiseTo)),
      multiple: preflop ? size : null,
      potShare: preflop ? null : size,
      unavailable: reason,
    ));
  }
  actions.add(SpotAction(
    kind: SpotActionKind.allIn,
    amount: legal.maxRaiseTo,
    action: PlayerAction.raiseTo(legal.maxRaiseTo),
    unavailable: legal.canRaise ? null : Unavailable.raisingNotAllowed,
  ));
  return actions;
}

/// The GTO answer for the choices of [menu]: each allowed choice's
/// frequency and value come from the solved decision, where [indexOf]
/// finds it (-1 if the solved game doesn't have it).
SpotStrategy answerFor(
  List<SpotAction> menu, {
  required String handName,
  required int Function(SpotAction choice) indexOf,
  required double Function(int index) frequency,
  required double Function(int index) value,
}) {
  final actions = <SpotAction>[];
  final frequencies = <double>[];
  final evs = <double>[];
  for (final choice in menu) {
    final i = choice.available ? indexOf(choice) : -1;
    if (i < 0) {
      actions.add(choice.available ? choice.unavailableBecause(Unavailable.notSolved) : choice);
      frequencies.add(0);
      evs.add(double.nan);
    } else {
      actions.add(choice);
      frequencies.add(frequency(i));
      evs.add(value(i));
    }
  }
  return SpotStrategy.normalized(handName: handName, actions: actions, frequencies: frequencies, evs: evs);
}
