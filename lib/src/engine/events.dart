import 'cards.dart';
import 'hand_evaluator.dart';
import 'positions.dart';

enum Street { preflop, flop, turn, river }

/// A pot and the seats that can win it.
class Pot {
  const Pot(this.amount, this.eligibleSeats);
  final int amount;
  final List<int> eligibleSeats;

  @override
  String toString() => 'Pot($amount, $eligibleSeats)';
}

/// Something that happened during a hand. The table UI plays these back one by
/// one as animations; the engine itself never waits for them.
sealed class GameEvent {
  const GameEvent();
}

class HandStarted extends GameEvent {
  const HandStarted({
    required this.handNumber,
    required this.buttonSeat,
    required this.stacks,
    required this.positions,
  });
  final int handNumber;
  final int buttonSeat;
  final List<int> stacks;
  final Map<int, Position> positions;
}

/// Antes go straight into the pot.
class AntesPosted extends GameEvent {
  const AntesPosted(this.amounts);
  final Map<int, int> amounts;
}

class BlindPosted extends GameEvent {
  const BlindPosted({required this.seat, required this.amount, required this.isBigBlind});
  final int seat;
  final int amount;
  final bool isBigBlind;
}

class HoleCardsDealt extends GameEvent {
  const HoleCardsDealt({required this.dealOrder, required this.cards});

  /// Seats in the order they receive cards (starting left of the button).
  final List<int> dealOrder;
  final Map<int, List<PlayingCard>> cards;
}

enum ActionKind { fold, check, call, bet, raise }

class ActionTaken extends GameEvent {
  const ActionTaken({
    required this.seat,
    required this.kind,
    required this.chipsAdded,
    required this.streetBet,
    required this.isAllIn,
    required this.street,
  });
  final int seat;
  final ActionKind kind;

  /// Chips moved from the stack into the bet in front of the player.
  final int chipsAdded;

  /// The player's total bet on this street after acting.
  final int streetBet;
  final bool isAllIn;
  final Street street;
}

/// The part of a bet nobody called goes back to the bettor.
class UncalledBetReturned extends GameEvent {
  const UncalledBetReturned({required this.seat, required this.amount});
  final int seat;
  final int amount;
}

/// All bets move into the middle. [pots] is the state after collecting
/// (main pot first, then side pots).
class BetsCollected extends GameEvent {
  const BetsCollected(this.pots);
  final List<Pot> pots;
}

class BoardDealt extends GameEvent {
  const BoardDealt({required this.street, required this.cards});
  final Street street;
  final List<PlayingCard> cards;
}

/// Hole cards turned face up (showdown, or an all-in with cards to come).
class HandsRevealed extends GameEvent {
  const HandsRevealed(this.cards);
  final Map<int, List<PlayingCard>> cards;
}

class PotAwarded extends GameEvent {
  const PotAwarded({
    required this.potIndex,
    required this.amount,
    required this.shares,
    required this.winningHand,
  });
  final int potIndex;
  final int amount;

  /// Seat -> chips won from this pot.
  final Map<int, int> shares;

  /// The winning hand, or null if everyone else folded.
  final HandValue? winningHand;
}

class HandEnded extends GameEvent {
  const HandEnded({required this.finalStacks, required this.netChange});
  final List<int> finalStacks;

  /// Seat -> chips won (positive) or lost (negative) in this hand.
  final Map<int, int> netChange;
}
