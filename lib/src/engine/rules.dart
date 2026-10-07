/// The version of the betting rules: the engine's (this folder), the raise
/// sizes (lib/src/gto/raise_sizes.dart) and the bots' sizes, rounded to
/// 0.5 BB. Every device at an online table must play the same rules, so a
/// device with other ones can't join. Bump it whenever any of them changes.
const rulesVersion = 1;

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
