/// The rules that carry a table from one hand to the next, shared by the
/// table on this device (TableSession) and the online server.
library;

/// Stacks (chips, by seat) and button for the next hand.
typedef NextHand = ({List<int> stacks, int button});

/// The next hand after one that ended with [stacks] and had the button in
/// [button] (for the first hand: [stacks] and [button] are its own).
///
/// Play carries on from hand to hand: anyone who went broke buys back in
/// for their starting stack ([startingStacks]), and with [resetStacks]
/// everyone starts each hand with it. Then [edits] (chips, by seat) are
/// applied. The button moves one seat to the left.
NextHand nextHandSetup({
  required List<int> stacks,
  required List<int> startingStacks,
  required int button,
  bool firstHand = false,
  bool resetStacks = false,
  Map<int, int> edits = const {},
}) {
  final n = stacks.length;
  final nextStacks = resetStacks
      ? [for (var seat = 0; seat < n; seat++) startingStacks[seat]]
      : [for (var seat = 0; seat < n; seat++) stacks[seat] == 0 ? startingStacks[seat] : stacks[seat]];
  for (final MapEntry(key: seat, value: chips) in edits.entries) {
    nextStacks[seat] = chips;
  }
  return (stacks: nextStacks, button: firstHand ? button : (button + 1) % n);
}
