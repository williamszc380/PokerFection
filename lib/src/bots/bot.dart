import 'dart:math';

import '../engine/actions.dart';
import '../engine/equity.dart';
import '../engine/events.dart';
import '../engine/poker_hand.dart';
import '../engine/positions.dart';
import 'preflop_ranking.dart';

enum BotStyle {
  tag('TAG', 'Tight-aggressive: few hands, played hard.',
      looseness: 1.0, aggression: 0.75, bluffing: 0.12, callPickiness: 1.25),
  lag('LAG', 'Loose-aggressive: lots of hands, lots of pressure.',
      looseness: 1.55, aggression: 0.85, bluffing: 0.28, callPickiness: 1.15),
  station('Station', 'Calling station: calls too much, rarely raises.',
      looseness: 1.45, aggression: 0.2, bluffing: 0.03, callPickiness: 0.8),
  nit('Nit', 'Very tight: waits for premium hands.',
      looseness: 0.55, aggression: 0.55, bluffing: 0.03, callPickiness: 1.45),

  /// Plays the solver's strategy wherever there is one; elsewhere (for
  /// example pots with 3+ players after the flop) it plays like a TAG.
  gto('GTO', 'Plays the solver\'s near-optimal strategy.',
      looseness: 1.0, aggression: 0.75, bluffing: 0.12, callPickiness: 1.25);

  /// Styles that imitate human players (picked from when styles are random).
  static const humanLike = [tag, lag, station, nit];

  const BotStyle(
    this.label,
    this.description, {
    required this.looseness,
    required this.aggression,
    required this.bluffing,
    required this.callPickiness,
  });

  final String label;
  final String description;

  /// Multiplies the share of starting hands played.
  final double looseness;

  /// Chance of betting or raising a strong hand instead of checking or calling.
  final double aggression;

  /// Chance of betting a weak hand as a bluff.
  final double bluffing;

  /// Multiplies the equity needed to call a bet (lower = calls more).
  final double callPickiness;
}

/// A simple rule-based opponent. It looks at hand strength, position and the
/// price to call; it is not a solver and is meant to feel like a human player.
class Bot {
  Bot(this.style, this._random);

  final BotStyle style;
  final Random _random;

  PlayerAction decide(PokerHand hand, int seat) {
    final legal = hand.legalActions();
    final action = hand.street == Street.preflop
        ? _preflop(hand, seat, legal)
        : _postflop(hand, seat, legal);
    return _makeLegal(action, legal);
  }

  // ---------------------------------------------------------------------------
  // Before the flop
  // ---------------------------------------------------------------------------

  PlayerAction _preflop(PokerHand hand, int seat, LegalActions legal) {
    final cards = hand.holeCards(seat);
    final noise = (_random.nextDouble() - 0.5) * 0.04;
    final strength = (preflopPercentile(cards[0], cards[1]) + noise).clamp(0.0, 1.0);
    final bb = hand.bigBlind;
    final stackInBb = (legal.stack + legal.streetBet) / bb;
    final raises = hand.raisesThisStreet;

    if (raises == 0) {
      final openRange = _openRange(_playersBehind(hand, seat)) * style.looseness;
      if (strength <= openRange) {
        if (stackInBb <= 12) return PlayerAction.raiseTo(legal.maxRaiseTo);
        final size = (2.5 + hand.callsSinceLastRaise) * bb;
        return PlayerAction.raiseTo(size.round());
      }
      if (legal.canCheck) return const PlayerAction.check();
      // Passive players sometimes limp in with hands just outside their range.
      if (strength <= openRange * 1.5 && _random.nextDouble() > style.aggression) {
        return const PlayerAction.call();
      }
      return const PlayerAction.fold();
    }

    final callCostShare = legal.toCall / (legal.stack + legal.streetBet);
    if (raises == 1) {
      final reraiseRange = 0.035 * style.looseness * style.aggression / 0.75;
      var callRange = 0.15 * style.looseness / style.callPickiness;
      if (hand.positionOf(seat) == Position.bb) callRange *= 1.8; // already has chips in
      if (legal.toCall > 5 * bb) callRange *= 0.6;
      if (strength <= reraiseRange) {
        if (stackInBb <= 25) return PlayerAction.raiseTo(legal.maxRaiseTo);
        final size = hand.currentBet * 3 + hand.callsSinceLastRaise * hand.currentBet;
        return PlayerAction.raiseTo(size);
      }
      if (strength <= callRange && callCostShare < 0.5) return const PlayerAction.call();
      return legal.canCheck ? const PlayerAction.check() : const PlayerAction.fold();
    }

    // Facing a re-raise or more.
    if (strength <= 0.02 * style.looseness) {
      return callCostShare > 0.3
          ? PlayerAction.raiseTo(legal.maxRaiseTo)
          : PlayerAction.raiseTo((hand.currentBet * 2.3).round());
    }
    if (strength <= 0.05 * style.looseness / style.callPickiness) {
      return const PlayerAction.call();
    }
    return legal.canCheck ? const PlayerAction.check() : const PlayerAction.fold();
  }

  /// Share of hands to open when nobody has entered the pot yet.
  double _openRange(int playersBehind) => switch (playersBehind) {
        0 => 0.10, // big blind raising limpers
        1 => 0.45, // small blind vs big blind
        2 => 0.42, // button
        3 => 0.27,
        4 => 0.21,
        5 => 0.17,
        6 => 0.14,
        _ => 0.12,
      };

  /// Players still to act after [seat] before the flop (through the big blind).
  int _playersBehind(PokerHand hand, int seat) {
    final n = hand.playerCount;
    final bigBlind = bigBlindSeat(n, hand.buttonSeat);
    var count = 0;
    var s = seat;
    while (s != bigBlind) {
      s = (s + 1) % n;
      if (!hand.isFolded(s)) count++;
    }
    return count;
  }

  // ---------------------------------------------------------------------------
  // After the flop
  // ---------------------------------------------------------------------------

  PlayerAction _postflop(PokerHand hand, int seat, LegalActions legal) {
    final opponents = hand.livePlayerCount - 1;
    final equity = estimateEquity(
      hole: hand.holeCards(seat),
      board: hand.board,
      opponents: opponents,
      random: _random,
      trials: 250,
    );
    // Roughly the chance of beating one opponent, so thresholds work multiway.
    final strength = pow(equity, 1 / opponents).toDouble();
    final pot = legal.pot;
    final roll = _random.nextDouble();

    if (legal.canCheck) {
      if (strength > 0.72 && roll < style.aggression) {
        return _betFraction(legal, 0.5 + _random.nextDouble() * 0.25, pot);
      }
      if (strength > 0.6 && roll < style.aggression * 0.35) {
        return _betFraction(legal, 0.33, pot);
      }
      if (strength < 0.4 && opponents <= 2 && roll < style.bluffing) {
        return _betFraction(legal, 0.5, pot);
      }
      return const PlayerAction.check();
    }

    final potOdds = legal.toCall / (pot + legal.toCall);
    if (strength > 0.85 && legal.canRaise && roll < style.aggression * 0.7) {
      return PlayerAction.raiseTo(legal.currentBet + ((pot + legal.toCall) * 0.8).round());
    }
    if (equity >= potOdds * style.callPickiness) return const PlayerAction.call();
    if (strength < 0.35 && legal.canRaise && roll < style.bluffing * 0.25) {
      return PlayerAction.raiseTo(legal.currentBet + (pot + legal.toCall));
    }
    return const PlayerAction.fold();
  }

  PlayerAction _betFraction(LegalActions legal, double fraction, int pot) =>
      PlayerAction.raiseTo(legal.currentBet + (pot * fraction).round());

  /// Rounds and clamps an intended action so the engine always accepts it.
  PlayerAction _makeLegal(PlayerAction action, LegalActions legal) {
    switch (action.type) {
      case ActionType.fold:
        return legal.canCheck ? const PlayerAction.check() : action;
      case ActionType.check:
        return legal.canCheck ? action : const PlayerAction.fold();
      case ActionType.call:
        return legal.canCall ? action : const PlayerAction.check();
      case ActionType.raise:
        if (!legal.canRaise) {
          return legal.canCall ? const PlayerAction.call() : const PlayerAction.check();
        }
        var to = (action.amount / 10).round() * 10;
        to = to.clamp(legal.minRaiseTo, legal.maxRaiseTo);
        // Don't leave a tiny stack behind: commit fully instead.
        if (to >= legal.maxRaiseTo * 0.7) to = legal.maxRaiseTo;
        return PlayerAction.raiseTo(to);
    }
  }
}
