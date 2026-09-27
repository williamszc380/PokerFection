/// The min-raise rule: how small a raise may be.
enum RaiseRule {
  /// Standard No-Limit: a raise must be at least the size of the last bet or
  /// raise on the street (facing a bet of 10, raise to 20 or more).
  standard(
    'No-Limit (Standard)',
    'Standard No-Limit min-raise: at least the size of the last bet or raise.',
  ),

  /// House rule: any raise of at least one big blind.
  bigBlind(
    '1 BB Min-Raise (House Rule)',
    'Home-game rule: any raise of at least one big blind.',
  );

  const RaiseRule(this.label, this.description);
  final String label;
  final String description;

  /// The smallest raise increment, given the last full bet or raise.
  int minimumIncrease(int lastRaise, int bigBlind) => this == standard ? lastRaise : bigBlind;
}
