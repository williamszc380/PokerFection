enum ActionType { fold, check, call, raise }

/// A decision by the player to act.
///
/// For [ActionType.raise], [amount] is the player's total bet on this street
/// after the action ("raise to"). With no bet yet on the street, a raise is a bet.
class PlayerAction {
  const PlayerAction.fold() : type = ActionType.fold, amount = 0;
  const PlayerAction.check() : type = ActionType.check, amount = 0;
  const PlayerAction.call() : type = ActionType.call, amount = 0;
  const PlayerAction.raiseTo(this.amount) : type = ActionType.raise;

  final ActionType type;
  final int amount;

  @override
  String toString() => type == ActionType.raise ? 'raise to $amount' : type.name;
}

/// What the player to act is allowed to do.
class LegalActions {
  const LegalActions({
    required this.toCall,
    required this.canRaise,
    required this.minRaiseTo,
    required this.maxRaiseTo,
    required this.currentBet,
    required this.streetBet,
    required this.stack,
    required this.pot,
  });

  /// Chips needed to call, capped at the player's stack.
  final int toCall;
  final bool canRaise;

  /// Smallest legal raise-to amount (equal to [maxRaiseTo] when only an
  /// all-in is possible).
  final int minRaiseTo;

  /// Raise-to amount that puts the player all-in.
  final int maxRaiseTo;

  /// Highest total bet on this street so far.
  final int currentBet;

  /// What this player has already bet on this street.
  final int streetBet;
  final int stack;

  /// Everything in the middle: collected pots plus all bets on this street.
  final int pot;

  bool get canCheck => toCall == 0;
  bool get canCall => toCall > 0;
  bool get canFold => toCall > 0;

  /// True when a raise would be the first bet on this street.
  bool get isBet => currentBet == 0;

  /// Calling puts the player all-in.
  bool get callIsAllIn => toCall > 0 && toCall >= stack;
}
