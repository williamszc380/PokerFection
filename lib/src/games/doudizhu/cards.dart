/// Cards for Fight the Landlord (Dou Dizhu).
///
/// The game uses one 54-card deck: the 52 standard cards plus a little
/// (black) joker and a big (red) joker. Suits never matter in play, only
/// ranks do, so almost all of the engine works on "rank counts": how many
/// cards of each of the 15 ranks a hand holds. Card ids with suits are kept
/// only so the app can draw the real cards.
///
/// Rank order, low to high (Pagat, https://www.pagat.com/climbing/doudizhu.html):
/// 3 4 5 6 7 8 9 10 J Q K A 2, little joker, big joker.
library;

import 'dart:math';

/// Rank numbers: 0 is the 3, 11 the ace, 12 the 2, 13 the little joker and
/// 14 the big joker. Comparing two ranks is comparing these numbers.
abstract final class Rank {
  static const three = 0;
  static const ten = 7;
  static const jack = 8;
  static const queen = 9;
  static const king = 10;
  static const ace = 11;
  static const two = 12;
  static const littleJoker = 13;
  static const bigJoker = 14;

  /// How many different ranks exist (13 suited ranks plus two jokers).
  static const count = 15;

  /// The highest rank a straight, a pair chain or an airplane may reach.
  /// Pagat: "from 3 up to ace ... Twos and jokers cannot be used."
  static const highestInChain = ace;

  /// One character per rank, as used by [parseRanks] and the tests:
  /// T is the 10, B the little (black) joker and R the big (red) joker.
  static const chars = '3456789TJQKA2BR';

  /// The label shown on a card face.
  static const labels = [
    '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A', '2', //
    'Joker', 'JOKER',
  ];

  /// Short label for compact text, such as a card counter column.
  static String label(int rank) => labels[rank];
}

/// One physical card, numbered 0 to 53.
///
/// Ids 0 to 51 are `rank * 4 + suit` (suits clubs, diamonds, hearts,
/// spades); 52 is the little joker and 53 the big joker. The id is only
/// for showing cards: every rule uses [rank].
class DdzCard {
  const DdzCard(this.id) : assert(id >= 0 && id < 54);

  final int id;

  /// The card's rank number (see [Rank]).
  int get rank => rankOfId(id);

  /// 0 to 3 for clubs, diamonds, hearts and spades; -1 for a joker.
  int get suit => id < 52 ? id & 3 : -1;

  bool get isJoker => id >= 52;

  /// Red cards are diamonds, hearts and the big joker, as printed.
  bool get isRed => id == 53 || (id < 52 && (suit == 1 || suit == 2));

  static const suitSymbols = ['♣', '♦', '♥', '♠'];

  @override
  bool operator ==(Object other) => other is DdzCard && other.id == id;

  @override
  int get hashCode => id;

  @override
  String toString() => isJoker ? Rank.chars[rank] : '${Rank.chars[rank]}${'cdhs'[suit]}';
}

/// The rank of card [id] without making a [DdzCard].
int rankOfId(int id) => id < 52 ? id >> 2 : id - 39;

/// The number of cards a full deck has of [rank]: four, or one of each joker.
int deckCountOf(int rank) => rank >= Rank.littleJoker ? 1 : 4;

/// Rank counts of a full deck.
List<int> fullDeckCounts() => [for (var r = 0; r < Rank.count; r++) deckCountOf(r)];

/// Parses ranks written with [Rank.chars], such as `"333 4"` or `"BR"`
/// (the rocket). Spaces are ignored. Returns the ranks sorted low to high.
List<int> parseRanks(String text) {
  final ranks = <int>[];
  for (final ch in text.split('')) {
    if (ch.trim().isEmpty) continue;
    final r = Rank.chars.indexOf(ch.toUpperCase());
    if (r < 0) throw FormatException('Unknown rank', ch);
    ranks.add(r);
  }
  ranks.sort();
  return ranks;
}

/// Rank counts (15 numbers) of a list of ranks.
List<int> countsOfRanks(Iterable<int> ranks) {
  final counts = List<int>.filled(Rank.count, 0);
  for (final r in ranks) {
    counts[r]++;
  }
  return counts;
}

/// Rank counts of a list of card ids.
List<int> countsOfIds(Iterable<int> ids) => countsOfRanks(ids.map(rankOfId));

/// Writes ranks back as text, low to high, such as `"3334"`.
String ranksText(Iterable<int> ranks) {
  final sorted = ranks.toList()..sort();
  return sorted.map((r) => Rank.chars[r]).join();
}

/// Writes rank counts as text, low to high.
String countsText(List<int> counts) {
  final b = StringBuffer();
  for (var r = 0; r < Rank.count; r++) {
    for (var i = 0; i < counts[r]; i++) {
      b.write(Rank.chars[r]);
    }
  }
  return b.toString();
}

/// A shuffled 54-card deck as card ids, from [random] so a seed repeats it.
List<int> shuffledDeck(Random random) => List<int>.generate(54, (i) => i)..shuffle(random);

/// Card ids for the given ranks, taking the first free suit of each rank.
/// Used by tests and tools to build hands from text.
List<int> idsForRanks(Iterable<int> ranks, {Set<int>? taken}) {
  final used = taken ?? <int>{};
  final ids = <int>[];
  for (final r in ranks) {
    var found = -1;
    if (r >= Rank.littleJoker) {
      final id = r + 39;
      if (!used.contains(id)) found = id;
    } else {
      for (var s = 0; s < 4; s++) {
        final id = r * 4 + s;
        if (!used.contains(id)) {
          found = id;
          break;
        }
      }
    }
    if (found < 0) throw ArgumentError('No card of rank ${Rank.chars[r]} left');
    used.add(found);
    ids.add(found);
  }
  return ids;
}
