import 'dart:math';

/// The user's raise sizes, the same rule before and after the flop: every
/// Fibonacci number of big blinds (1, 2, 3, 5, 8, 13, 21, ... BB, as the
/// total "raise to" for the street) from the min-raise ([minTo]) up to
/// all-in, smallest first. All-in is a choice of its own.
///
/// [allInTo] is what the player can really put in: their whole stack, or
/// less when nobody still in the hand could call that much (see
/// [coveredAllIn]). Amounts are in chips.
List<int> raiseSizes({required int minTo, required int allInTo, required int bigBlind}) => [
      for (var (a, b) = (1, 2); a * bigBlind < allInTo; (a, b) = (b, a + b))
        if (a * bigBlind >= minTo) a * bigBlind,
    ];

/// A player's all-in as a raise-to amount, capped at what the biggest
/// other stack still in the hand can match ([othersAllInTo]: each other
/// player's street bet plus chips behind).
int coveredAllIn(int allInTo, Iterable<int> othersAllInTo) => min(allInTo, othersAllInTo.fold(0, max));

/// 0.5 BB in chips: every bot's bet size is a multiple of it (all-ins aside).
int halfBigBlind(int bigBlind) => max(1, bigBlind ~/ 2);

/// [chips] rounded to the nearest 0.5 BB.
int roundToHalfBb(num chips, int bigBlind) {
  final step = halfBigBlind(bigBlind);
  return (chips / step).round() * step;
}
