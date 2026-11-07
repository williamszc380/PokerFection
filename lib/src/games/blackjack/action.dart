/// The decisions a blackjack player can make.
library;

/// One decision. Which ones are legal depends on the phase of the round
/// and the hand (see `BlackjackRound.legalActions`).
enum BlackjackAction {
  /// Keep the hand as it is.
  stand,

  /// Take one more card.
  hit,

  /// Double the bet, take exactly one more card, and stand.
  double,

  /// Split a pair into two hands, each with the original bet.
  split,

  /// Give up the hand and get half the bet back.
  surrender,

  /// Insurance phase: pay half the bet for insurance, which pays 2 to 1 if
  /// the dealer has blackjack. With a blackjack of your own at a 3:2 table
  /// this is "even money": you are paid 1 to 1 whatever the dealer has. At
  /// 6:5 or 1:1 it stays plain insurance (see
  /// `BlackjackView.offersEvenMoney`).
  insurance,

  /// Insurance phase: no insurance (or no even money).
  noInsurance,

  /// Early surrender phase: don't surrender, play the hand.
  keepPlaying,
}

/// A set of actions as bits (bit `action.index`), for the solver's
/// policies, which are asked thousands of times per answer.
extension ActionBits on BlackjackAction {
  /// This action's bit.
  int get bit => 1 << index;
}

/// The actions in [mask] (built from [ActionBits.bit]).
List<BlackjackAction> actionsIn(int mask) => [
  for (final a in BlackjackAction.values)
    if (mask & a.bit != 0) a,
];
