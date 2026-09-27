enum Position {
  utg('UTG'),
  utg1('UTG+1'),
  lj('LJ'),
  hj('HJ'),
  co('CO'),
  btn('BTN'),
  sb('SB'),
  bb('BB');

  const Position(this.label);
  final String label;
}

/// Positions in preflop acting order for a table of [playerCount] players.
///
/// Heads-up, the button posts the small blind and is labelled BTN.
List<Position> positionsForTable(int playerCount) {
  assert(playerCount >= 2 && playerCount <= 8);
  if (playerCount == 2) return const [Position.btn, Position.bb];
  if (playerCount == 3) return const [Position.btn, Position.sb, Position.bb];
  const middle = [Position.utg1, Position.lj, Position.hj, Position.co];
  return [
    Position.utg,
    ...middle.sublist(4 - (playerCount - 4)),
    Position.btn,
    Position.sb,
    Position.bb,
  ];
}

int smallBlindSeat(int playerCount, int buttonSeat) =>
    playerCount == 2 ? buttonSeat : (buttonSeat + 1) % playerCount;

int bigBlindSeat(int playerCount, int buttonSeat) =>
    (buttonSeat + (playerCount == 2 ? 1 : 2)) % playerCount;

/// Position of every seat, given where the button is.
Map<int, Position> positionsBySeat(int playerCount, int buttonSeat) {
  final order = positionsForTable(playerCount);
  final first = bigBlindSeat(playerCount, buttonSeat) + 1;
  return {
    for (var k = 0; k < playerCount; k++) (first + k) % playerCount: order[k],
  };
}

/// Where the button must be so that [seat] ends up in [position].
int buttonSeatFor(int playerCount, int seat, Position position) {
  final k = positionsForTable(playerCount).indexOf(position);
  if (k < 0) {
    throw ArgumentError('$position does not exist with $playerCount players');
  }
  final offset = (playerCount == 2 ? 2 : 3) + k;
  return ((seat - offset) % playerCount + playerCount) % playerCount;
}

/// Every position in seat order at a full table: the blinds first, the
/// button last. Lists of positions keep this order at every table size (the
/// ones a smaller table doesn't have greyed out), so each one stays in place.
const allPositions = [
  Position.sb,
  Position.bb,
  Position.utg,
  Position.utg1,
  Position.lj,
  Position.hj,
  Position.co,
  Position.btn,
];
