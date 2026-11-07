import 'package:flutter/material.dart';

import '../../../games/doudizhu/doudizhu.dart';
import '../../kit/cards.dart';

/// A Fight the Landlord card (id 0–53) as the kit draws it: ids 0–51 are
/// `rank * 4 + suit` with rank 0 the 3, so poker's rank is one higher (the
/// 2 wraps to 0); 52 and 53 are the little and big jokers.
CardFace ddzFace(int id) => switch (id) {
  52 => const CardFace.joker(big: false),
  53 => const CardFace.joker(big: true),
  _ => CardFace.suited((rankOfId(id) + 1) % 13, id & 3),
};

/// Cards in the order players hold them: highest on the left (jokers, 2s,
/// aces...), as the Chinese apps sort a hand.
List<int> ddzSorted(Iterable<int> ids) => ids.toList()
  ..sort((a, b) {
    final d = rankOfId(b) - rankOfId(a);
    return d != 0 ? d : b - a;
  });

/// The order of the suits in a hand sorted by suit, left to right: spades,
/// hearts, clubs, diamonds (黑红梅方, as Chinese players name them), so
/// black and red take turns. Indexed by the id's suit (`id & 3`: clubs,
/// diamonds, hearts, spades).
const _suitPlace = [2, 3, 1, 0];

/// Cards by suit: the jokers first, then each suit (see [_suitPlace]),
/// highest first within it, as [ddzSorted] orders ranks.
List<int> ddzSortedBySuit(Iterable<int> ids) => ids.toList()
  ..sort((a, b) {
    int place(int id) => id >= 52 ? -1 : _suitPlace[id & 3];
    final d = place(a) - place(b);
    if (d != 0) return d;
    final r = rankOfId(b) - rankOfId(a);
    return r != 0 ? r : b - a;
  });

/// The player's hand in the sort they chose (the Sort button's Rank or
/// Suit): [ddzSorted] or [ddzSortedBySuit].
List<int> ddzHandSorted(Iterable<int> ids, HandOrder sort) =>
    sort == HandOrder.suit ? ddzSortedBySuit(ids) : ddzSorted(ids);

/// How the player's hand is laid out (their sort, or their own order once
/// they drag a card), as a record's extra keeps it: `'sort'` and `'order'`
/// (the card ids). A card id that isn't one is left out.
HandArrangement<int> ddzArrangementOf(Map<String, Object?> extra) =>
    HandArrangement.fromExtra<int>(extra, (code) => code is int && code >= 0 && code < 54 ? code : null);

/// [arrangement] as the record's extra keeps it (see [ddzArrangementOf]).
Map<String, Object?> ddzArrangementExtra(HandArrangement<int> arrangement) => arrangement.toExtra((id) => id);

/// Some cards in a small overlapped row, lowest first as plays are read
/// ("34567"), for the table, coach rows and guides: [width] each, part of
/// each covered by the next.
class DdzMiniCards extends StatelessWidget {
  const DdzMiniCards({super.key, required this.ids, this.width = 20, this.overlap = 0.55, this.play});

  final List<int> ids;

  /// The play the cards make: its main part then comes before its kickers
  /// ("999 4", as players say it), each part lowest first.
  final Play? play;
  final double width;

  /// The share of each card the next one covers.
  final double overlap;

  @override
  Widget build(BuildContext context) {
    final step = width * (1 - overlap);
    final sorted = ddzPlayOrder(ids, play);
    return SizedBox(
      width: sorted.isEmpty ? 0 : width + step * (sorted.length - 1),
      height: width * cardAspectRatio,
      child: Stack(
        children: [
          for (var i = 0; i < sorted.length; i++)
            Positioned(
              left: i * step,
              child: GameCardView(width: width, face: ddzFace(sorted[i])),
            ),
        ],
      ),
    );
  }
}

/// Cards in the order a play is read ("34567", lowest first); with the
/// [play] they make, its main part first and then its kickers ("999 4", as
/// players say it), each part lowest first. The table, the history, coach
/// rows and guides all draw plays in this order (and a play's card flights
/// land in it).
List<int> ddzPlayOrder(Iterable<int> ids, [Play? play]) {
  final sorted = ddzSorted(ids).reversed.toList();
  if (play == null) return sorted;
  final main = countsOfRanks(play.mainRanks);
  bool isMain(int id) => main[rankOfId(id)] > 0;
  return [...sorted.where(isMain), ...sorted.where((id) => !isMain(id))];
}

/// Card ids that make [ranks]: the [preferred] cards first (the player's
/// own hand), then any free suit. Used to draw a play that is only known by
/// rank (a coach line, a guide's example).
List<int> ddzIdsForRanks(List<int> ranks, {Iterable<int> preferred = const []}) {
  final free = [...preferred];
  final used = <int>{};
  final out = <int>[];
  for (final r in ranks) {
    final i = free.indexWhere((id) => rankOfId(id) == r);
    if (i >= 0) {
      used.add(free[i]);
      out.add(free.removeAt(i));
      continue;
    }
    out.addAll(idsForRanks([r], taken: {...used, ...preferred, ...out}));
  }
  return out;
}
