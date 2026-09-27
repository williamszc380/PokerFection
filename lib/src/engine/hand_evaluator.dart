import 'cards.dart';

enum HandCategory {
  highCard('High Card'),
  pair('Pair'),
  twoPair('Two Pair'),
  trips('Three of a Kind'),
  straight('Straight'),
  flush('Flush'),
  fullHouse('Full House'),
  quads('Four of a Kind'),
  straightFlush('Straight Flush');

  const HandCategory(this.label);
  final String label;
}

/// The strength of the best five-card hand. Higher [score] wins.
///
/// Layout: category in bits 20+, then up to five ranks (0 = deuce ... 12 = ace)
/// in 4-bit slots from most to least important.
class HandValue implements Comparable<HandValue> {
  const HandValue(this.score);

  final int score;

  HandCategory get category => HandCategory.values[score >> 20];

  /// The rank stored in slot [i] (0 = most important).
  int rankAt(int i) => (score >> (16 - 4 * i)) & 0xF;

  @override
  int compareTo(HandValue other) => score.compareTo(other.score);

  bool operator >(HandValue other) => score > other.score;
  bool operator <(HandValue other) => score < other.score;

  @override
  bool operator ==(Object other) => other is HandValue && other.score == score;

  @override
  int get hashCode => score;

  /// Human-readable name, e.g. "Two Pair, Kings and Sevens".
  String describe() {
    final r0 = rankAt(0), r1 = rankAt(1);
    return switch (category) {
      HandCategory.straightFlush =>
        r0 == 12 ? 'Royal Flush' : 'Straight Flush, ${_single[r0]} high',
      HandCategory.quads => 'Four of a Kind, ${_plural[r0]}',
      HandCategory.fullHouse => 'Full House, ${_plural[r0]} full of ${_plural[r1]}',
      HandCategory.flush => 'Flush, ${_single[r0]} high',
      HandCategory.straight => 'Straight, ${_single[r0]} high',
      HandCategory.trips => 'Three of a Kind, ${_plural[r0]}',
      HandCategory.twoPair => 'Two Pair, ${_plural[r0]} and ${_plural[r1]}',
      HandCategory.pair => 'Pair of ${_plural[r0]}',
      HandCategory.highCard => '${_single[r0]} High',
    };
  }

  @override
  String toString() => describe();

  static const _single = [
    'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', //
    'Jack', 'Queen', 'King', 'Ace',
  ];
  static const _plural = [
    'Twos', 'Threes', 'Fours', 'Fives', 'Sixes', 'Sevens', 'Eights', 'Nines', //
    'Tens', 'Jacks', 'Queens', 'Kings', 'Aces',
  ];
}

/// Evaluates the best five-card hand from 5 to 7 cards.
HandValue evaluateHand(Iterable<PlayingCard> cards) =>
    HandValue(evaluateIndices([for (final c in cards) c.index]));

/// Same as [evaluateHand] but on raw card indices (faster, no allocation of
/// [PlayingCard] objects). Used by simulations.
int evaluateIndices(List<int> cards) {
  assert(cards.length >= 5 && cards.length <= 7);
  final rankCounts = List<int>.filled(13, 0);
  final suitCounts = List<int>.filled(4, 0);
  final suitMasks = List<int>.filled(4, 0);
  var rankMask = 0;
  for (final c in cards) {
    final r = c >> 2, s = c & 3;
    rankCounts[r]++;
    suitCounts[s]++;
    suitMasks[s] |= 1 << r;
    rankMask |= 1 << r;
  }

  var flushSuit = -1;
  for (var s = 0; s < 4; s++) {
    if (suitCounts[s] >= 5) {
      final high = _straightHigh(suitMasks[s]);
      if (high >= 0) return _score(HandCategory.straightFlush, [high]);
      flushSuit = s;
    }
  }

  var quad = -1;
  final trips = <int>[];
  final pairs = <int>[];
  for (var r = 12; r >= 0; r--) {
    switch (rankCounts[r]) {
      case 4:
        quad = r;
      case 3:
        trips.add(r);
      case 2:
        pairs.add(r);
    }
  }

  if (quad >= 0) {
    return _score(HandCategory.quads, [quad, ..._topRanks(rankMask, 1, [quad])]);
  }
  if (trips.isNotEmpty && (trips.length > 1 || pairs.isNotEmpty)) {
    final second = trips.length > 1 ? trips[1] : -1;
    final pair = pairs.isNotEmpty ? pairs[0] : -1;
    return _score(HandCategory.fullHouse, [trips[0], second > pair ? second : pair]);
  }
  if (flushSuit >= 0) {
    return _score(HandCategory.flush, _topRanks(suitMasks[flushSuit], 5, const []));
  }
  final straightHigh = _straightHigh(rankMask);
  if (straightHigh >= 0) return _score(HandCategory.straight, [straightHigh]);
  if (trips.isNotEmpty) {
    return _score(HandCategory.trips, [trips[0], ..._topRanks(rankMask, 2, [trips[0]])]);
  }
  if (pairs.length >= 2) {
    final top = [pairs[0], pairs[1]];
    return _score(HandCategory.twoPair, [...top, ..._topRanks(rankMask, 1, top)]);
  }
  if (pairs.length == 1) {
    return _score(HandCategory.pair, [pairs[0], ..._topRanks(rankMask, 3, pairs)]);
  }
  return _score(HandCategory.highCard, _topRanks(rankMask, 5, const []));
}

int _score(HandCategory category, List<int> ranks) {
  var score = category.index << 20;
  for (var i = 0; i < ranks.length; i++) {
    score |= ranks[i] << (16 - 4 * i);
  }
  return score;
}

/// Highest [count] ranks present in [mask], skipping ranks in [exclude].
List<int> _topRanks(int mask, int count, List<int> exclude) {
  final result = <int>[];
  for (var r = 12; r >= 0 && result.length < count; r--) {
    if ((mask >> r) & 1 == 1 && !exclude.contains(r)) result.add(r);
  }
  return result;
}

/// Top rank of the best straight in [mask], or -1. The ace also plays low
/// (A-2-3-4-5 is a "five high" straight, returned as rank 3).
int _straightHigh(int mask) {
  // Shift so bit 0 is a low ace and bit r+1 is rank r.
  final m = (mask << 1) | ((mask >> 12) & 1);
  for (var high = 13; high >= 4; high--) {
    if (((m >> (high - 4)) & 0x1F) == 0x1F) return high - 1;
  }
  return -1;
}
