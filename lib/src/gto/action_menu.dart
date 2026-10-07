import '../engine/actions.dart';
import '../engine/events.dart';
import '../engine/poker_hand.dart';
import 'postflop/postflop_tree.dart';
import 'raise_sizes.dart';
import 'spot_strategy.dart';

/// The user's choices at their decision: fold, check or call, each raise
/// size, all-in. The sizes follow one rule before and after the flop (see
/// [raiseSizes]): every Fibonacci number of big blinds (1, 2, 3, 5, 8, ...
/// BB) from the min-raise up to all-in. Choices not allowed here stay in the list,
/// marked unavailable with the reason (greyed out).
///
/// Before the flop each size also shows as a multiple of the bet faced
/// (first in, of the big blind); after it, as a share of the pot (for a
/// raise, of the pot after calling).
List<SpotAction> actionMenu(PokerHand hand) {
  final legal = hand.legalActions();
  final preflop = hand.street == Street.preflop;
  final seat = hand.toAct!;
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
  // Same sizes as the solved games, whose menus must match this one.
  final sizes = raiseSizes(
    minTo: legal.minRaiseTo,
    allInTo: coveredAllIn(legal.maxRaiseTo, [
      for (var s = 0; s < hand.playerCount; s++)
        if (s != seat && !hand.isFolded(s)) hand.streetBetOf(s) + hand.stackOf(s),
    ]),
    bigBlind: hand.bigBlind,
  );
  for (final to in sizes) {
    actions.add(SpotAction(
      kind: SpotActionKind.raise,
      amount: to,
      action: PlayerAction.raiseTo(to),
      multiple: preflop ? to / legal.currentBet : null,
      potShare: preflop ? null : PostflopTree.potShareOf(to, legal.currentBet, legal.streetBet, legal.pot),
      unavailable: legal.canRaise ? null : Unavailable.raisingNotAllowed,
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
