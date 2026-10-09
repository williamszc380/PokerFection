import 'dart:typed_data';

import 'showdown.dart';

/// Scratch space for [addSameRankWins], for [hands] hands.
class SameRankScratch {
  SameRankScratch(int hands)
      : heldP = Float64List(hands),
        heldQ = Float64List(hands),
        minusOne = Float64List(hands)..fillRange(0, hands, -1);

  final Float64List heldP;
  final Float64List heldQ;
  final Float64List minusOne;
  final showdown = ShowdownScratch();
}

/// A group of rivers ranking every hand alike ([RunoutRanking.sameRank]),
/// shown down at once for two players: adds to `winsP[c]` how much of
/// [weightsQ] hand `c` beats (ties half) summed over the group's rivers,
/// that is on the `seen[c]` rivers `c` doesn't hold, less, for each
/// opponent hand, the `held` rivers that one holds; and the same for
/// `winsQ` against [weightsP].
void addSameRankWins(
  RunoutRanking ranking,
  Float64List weightsP,
  Float64List weightsQ,
  Float64List held,
  Float64List seen,
  Float64List winsP,
  Float64List winsQ,
  SameRankScratch scratch,
) {
  final heldP = scratch.heldP, heldQ = scratch.heldQ;
  for (var c = 0; c < heldP.length; c++) {
    heldP[c] = weightsP[c] * held[c];
    heldQ[c] = weightsQ[c] * held[c];
  }
  addShowdownWinsForBoth(ranking, weightsP, weightsQ, winsP, winsQ, scratch.showdown, scale: seen);
  addShowdownWinsForBoth(ranking, heldP, heldQ, winsP, winsQ, scratch.showdown, scale: scratch.minusOne);
}
