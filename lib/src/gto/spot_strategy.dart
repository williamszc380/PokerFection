import 'dart:math';

import '../engine/actions.dart';

enum SpotActionKind { fold, check, call, raise, allIn }

/// Why a choice isn't allowed at a decision (it stays in the list, greyed out).
enum Unavailable { checkIsFree, raisingNotAllowed, belowMinBet, belowMinRaise, nearlyAllIn, sameAmount, notSolved }

/// Why a decision has no GTO answer.
enum NoAnswer { multiway, leftSolvedLines, solveFailed }

/// One choice the user can put a percentage on.
class SpotAction {
  const SpotAction({
    required this.kind,
    required this.amount,
    required this.action,
    this.multiple,
    this.potShare,
    this.unavailable,
  });

  /// Why this choice isn't allowed here (it is still shown, greyed out, so
  /// the choices look the same at every decision); null if it is allowed.
  final Unavailable? unavailable;

  bool get available => unavailable == null;

  final SpotActionKind kind;

  /// Chips: the amount to call, or the total bet after raising. 0 for fold and check.
  final int amount;

  /// What the game engine should do if this choice is played.
  final PlayerAction action;

  /// For sized raises before the flop: the multiple of the bet faced (2.5 = 2.5×).
  final double? multiple;

  /// For sized raises after the flop: the multiple of the pot (0.5 = 0.5× pot).
  final double? potShare;

  /// The same choice, not allowed here for [reason].
  SpotAction unavailableBecause(Unavailable reason) => SpotAction(
        kind: kind,
        amount: amount,
        action: action,
        multiple: multiple,
        potShare: potShare,
        unavailable: reason,
      );
}

/// The GTO answer for one decision with one specific starting hand.
class SpotStrategy {
  const SpotStrategy({
    required this.handName,
    required this.actions,
    required this.frequencies,
    required this.evs,
  });

  /// Builds the answer from raw solver numbers: frequencies are rescaled to
  /// add up to 1, and a choice GTO (almost) never makes is never shown as
  /// better than the best one it does make (small solver noise).
  factory SpotStrategy.normalized({
    required String handName,
    required List<SpotAction> actions,
    required List<double> frequencies,
    required List<double> evs,
  }) {
    final total = frequencies.fold(0.0, (a, b) => a + b);
    final shares = [for (final f in frequencies) total > 0 ? f / total : 0.0];
    var bestUsed = double.negativeInfinity;
    for (var i = 0; i < evs.length; i++) {
      if (shares[i] >= 0.01 && !evs[i].isNaN) bestUsed = max(bestUsed, evs[i]);
    }
    return SpotStrategy(
      handName: handName,
      actions: actions,
      frequencies: shares,
      evs: [
        for (var i = 0; i < evs.length; i++)
          shares[i] < 0.01 && !evs[i].isNaN && bestUsed.isFinite ? min(evs[i], bestUsed) : evs[i],
      ],
    );
  }

  /// Starting hand, e.g. "AJo".
  final String handName;
  final List<SpotAction> actions;

  /// How often GTO takes each action (0-1, adding up to 1).
  final List<double> frequencies;

  /// Expected big blinds won from this point for each action; folding is 0.
  /// NaN for unavailable actions.
  final List<double> evs;
}

enum DecisionGrade {
  best('Best'),
  good('Good'),
  inaccuracy('Inaccuracy'),
  mistake('Mistake'),
  blunder('Blunder');

  const DecisionGrade(this.label);
  final String label;

  /// Grade for an EV loss in big blinds.
  static DecisionGrade forLoss(double evLoss) => switch (evLoss) {
        <= 0.02 => best,
        <= 0.08 => good,
        <= 0.25 => inaccuracy,
        <= 0.75 => mistake,
        _ => blunder,
      };
}

class DecisionScore {
  const DecisionScore({required this.mixMatch, required this.evLoss, required this.scoredLoss});

  /// How close the user's percentages are to GTO's, 1 meaning identical:
  /// mostly how often they fold, check or call, and raise; how the raises
  /// are split between sizes counts for [sizeWeight].
  final double mixMatch;

  /// Big blinds given up compared with GTO's own mix (0 or more).
  final double evLoss;

  /// [evLoss] with the part lost to worse raise sizes counting for
  /// [sizeWeight]: what the grade and the score go by.
  final double scoredLoss;

  DecisionGrade get grade => DecisionGrade.forLoss(scoredLoss);

  /// 0-100: half for matching the mix, half for not losing EV (losing
  /// 0.25 bb costs about 32 of those 50 points).
  int get score => (50 * mixMatch + 50 * exp(-scoredLoss / 0.25)).round();
}

/// How much raise sizes count in a score, next to the choice between
/// folding, checking or calling, and raising (any size).
const sizeWeight = 0.1;

/// Compares the user's mix ([user], adding up to 1) with the GTO answer.
DecisionScore scoreDecision(SpotStrategy spot, List<double> user) {
  assert(user.length == spot.actions.length);
  final actions = spot.actions, gto = spot.frequencies, evs = spot.evs;
  // 0: fold, 1: check or call, 2: raise (any size, or all-in).
  int group(int i) => switch (actions[i].kind) {
        SpotActionKind.fold => 0,
        SpotActionKind.check || SpotActionKind.call => 1,
        SpotActionKind.raise || SpotActionKind.allIn => 2,
      };
  var best = double.negativeInfinity, bestRaise = double.negativeInfinity;
  for (var i = 0; i < evs.length; i++) {
    if (evs[i].isNaN) continue;
    best = max(best, evs[i]);
    if (group(i) == 2) bestRaise = max(bestRaise, evs[i]);
  }
  final userGroups = [0.0, 0.0, 0.0], gtoGroups = [0.0, 0.0, 0.0];
  for (var i = 0; i < user.length; i++) {
    userGroups[group(i)] += user[i];
    gtoGroups[group(i)] += gto[i];
  }
  // What a mix gives up against the best action: for choosing to fold, call
  // or raise at all, and then for the raise sizes.
  (double, double) losses(List<double> mix) {
    var choice = 0.0, size = 0.0;
    for (var i = 0; i < mix.length; i++) {
      if (evs[i].isNaN) continue;
      if (group(i) == 2) {
        choice += mix[i] * (best - bestRaise);
        size += mix[i] * (bestRaise - evs[i]);
      } else {
        choice += mix[i] * (best - evs[i]);
      }
    }
    return (choice, size);
  }

  // Losses count from GTO's own mix: the solver stops a little short of
  // perfect, so the actions it mixes aren't worth exactly the same, and
  // playing its mix must not lose anything.
  final (userChoice, userSize) = losses(user);
  final (gtoChoice, gtoSize) = losses(gto);
  final choiceLoss = userChoice - gtoChoice, sizeLoss = userSize - gtoSize;
  var choiceDifference = 0.0;
  for (var g = 0; g < 3; g++) {
    choiceDifference += (userGroups[g] - gtoGroups[g]).abs();
  }
  // How the raises are split between sizes, when both raise.
  var sizeDifference = 0.0;
  if (userGroups[2] > 1e-9 && gtoGroups[2] > 1e-9) {
    for (var i = 0; i < user.length; i++) {
      if (group(i) == 2) sizeDifference += (user[i] / userGroups[2] - gto[i] / gtoGroups[2]).abs();
    }
  }
  final match = (1 - sizeWeight) * (1 - choiceDifference / 2) + sizeWeight * (1 - sizeDifference / 2);
  return DecisionScore(
    mixMatch: match.clamp(0.0, 1.0),
    evLoss: max(0.0, choiceLoss + sizeLoss),
    scoredLoss: max(0.0, choiceLoss + sizeWeight * sizeLoss),
  );
}

/// Sets `percents[index]` to [value] and rescales the other entries so the
/// total stays 100. Values move in steps of [step].
List<int> rebalancePercents(List<int> percents, int index, int value, {int step = 1}) {
  final result = List.of(percents);
  final target = ((value / step).round() * step).clamp(0, 100);
  if (percents.length == 1) return [100];
  result[index] = target;
  final others = [for (var i = 0; i < percents.length; i++) if (i != index) i];
  final othersTotal = others.fold(0, (sum, i) => sum + percents[i]);
  final units = (100 - target) ~/ step;
  if (othersTotal == 0) {
    // Nothing to scale: give the rest to the next choice.
    for (final i in others) {
      result[i] = 0;
    }
    result[others.firstWhere((i) => i > index, orElse: () => others.first)] = units * step;
    return result;
  }
  // Share the remaining steps in proportion to the current values.
  final shares = splitWhole([for (final i in others) percents[i].toDouble()], units);
  for (var k = 0; k < others.length; k++) {
    result[others[k]] = shares[k] * step;
  }
  return result;
}

/// Splits [total] whole units in proportion to [weights] (at least one of
/// them positive); the largest remainders get the leftover units.
List<int> splitWhole(List<double> weights, int total) {
  final sum = weights.fold(0.0, (a, b) => a + b);
  final exact = [for (final w in weights) w / sum * total];
  final floors = [for (final e in exact) e.floor()];
  var left = total - floors.fold(0, (a, b) => a + b);
  final order = [for (var k = 0; k < weights.length; k++) k]
    ..sort((a, b) => (exact[b] - floors[b]).compareTo(exact[a] - floors[a]));
  for (final k in order) {
    if (left <= 0) break;
    floors[k]++;
    left--;
  }
  return floors;
}
