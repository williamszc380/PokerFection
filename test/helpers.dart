import 'dart:math';

import 'package:pokerfection/src/engine/actions.dart';

/// Picks a random legal action, including odd raise sizes and all-ins.
PlayerAction randomAction(LegalActions legal, Random rng) {
  final roll = rng.nextDouble();
  if (legal.canRaise && roll < 0.3) {
    if (roll < 0.05) return PlayerAction.raiseTo(legal.maxRaiseTo);
    final span = legal.maxRaiseTo - legal.minRaiseTo;
    return PlayerAction.raiseTo(legal.minRaiseTo + (span == 0 ? 0 : rng.nextInt(span + 1)));
  }
  if (legal.canCheck) return const PlayerAction.check();
  return roll < 0.75 ? const PlayerAction.call() : const PlayerAction.fold();
}
