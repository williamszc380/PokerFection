/// The combinations of Fight the Landlord and how they compare.
///
/// Source for every rule here: Pagat (https://www.pagat.com/climbing/doudizhu.html)
/// and Wikipedia (https://en.wikipedia.org/wiki/Dou_dizhu). House rules
/// that differ are switches in [DdzRules].
library;

import 'cards.dart';
import 'rules.dart';

/// The kinds of play. A play can only be beaten by the same kind with the
/// same length and a higher main rank, or by a bomb or the rocket.
enum PlayType {
  /// One card, any rank.
  solo,

  /// Two cards of one rank (the jokers are not a pair: together they are
  /// the rocket).
  pair,

  /// Three cards of one rank.
  trio,

  /// A trio with one card of another rank attached ("6-6-6-8").
  trioSolo,

  /// A trio with a pair of another rank attached ("Q-Q-Q-6-6").
  trioPair,

  /// Five or more solos in a row, from 3 up to the ace.
  straight,

  /// Three or more pairs in a row, from 3 up to the ace.
  pairStraight,

  /// Two or more trios in a row, from 3 up to the ace (an "airplane").
  airplane,

  /// An airplane with one extra card per trio (its "wings"). Pagat: the
  /// attached cards "must be different from all the triplets but may form a
  /// pair", e.g. 4-4-4-5-5-5-9-9.
  airplaneSolos,

  /// An airplane with one extra pair per trio. Pagat: the pairs "must be
  /// different in rank from each other and from all the triplets".
  airplanePairs,

  /// Four of a kind with two solos of different ranks ("6-6-6-6-8-9"). Not
  /// a bomb: it is beaten only by a higher four-with-two, a bomb or rocket.
  fourTwoSolos,

  /// Four of a kind with two pairs of different ranks.
  fourTwoPairs,

  /// Four of a kind. Beats every play that isn't a bomb or the rocket; a
  /// higher bomb beats a lower one.
  bomb,

  /// Both jokers. Beats everything.
  rocket;

  /// Whether this kind is made of consecutive ranks, so its length matters.
  bool get isChain =>
      this == straight || this == pairStraight || this == airplane || this == airplaneSolos || this == airplanePairs;

  /// How many cards of each rank of the main part: 1 for straights, 2 for
  /// pair chains, 3 for trios and airplanes, 4 for fours.
  int get mainCopies => switch (this) {
        solo || straight => 1,
        pair || pairStraight || rocket => 2,
        trio || trioSolo || trioPair || airplane || airplaneSolos || airplanePairs => 3,
        fourTwoSolos || fourTwoPairs || bomb => 4,
      };

  /// The fewest units a chain of this kind needs (Pagat: five solos, three
  /// pairs, two trios); 1 for other kinds.
  int get minLength => switch (this) {
        straight => 5,
        pairStraight => 3,
        airplane || airplaneSolos || airplanePairs => 2,
        _ => 1,
      };

  /// Cards each unit of the main part carries as kickers: one solo, one pair
  /// (2 cards), or for fours two solos / two pairs.
  int get kickerCardsPerUnit => switch (this) {
        trioSolo || airplaneSolos => 1,
        trioPair || airplanePairs => 2,
        fourTwoSolos => 2,
        fourTwoPairs => 4,
        _ => 0,
      };
}

/// One play: what was played, as ranks (suits never matter).
///
/// [rank] is the lowest rank of the main part (the trio of a trio-with-solo,
/// the lowest trio of an airplane, the four of a four-with-two) and is what
/// decides which play is higher. [length] is the number of units in a chain
/// (5 for a 5-card straight, 2 for an airplane of two trios); 1 otherwise.
class Play {
  Play(this.type, this.rank, this.length, List<int> ranks) : ranks = List.unmodifiable(ranks..sort());

  /// The kind of play.
  final PlayType type;

  /// The lowest rank of the main part. See the class comment.
  final int rank;

  /// Units in a chain, 1 for anything else.
  final int length;

  /// Every card of the play as a rank, low to high.
  final List<int> ranks;

  /// Number of cards.
  int get size => ranks.length;

  /// The highest rank of the main part (the top of a straight).
  int get topRank => rank + length - 1;

  bool get isBomb => type == PlayType.bomb;
  bool get isRocket => type == PlayType.rocket;

  /// Bombs and the rocket double the stake and beat other kinds.
  bool get isBombLike => type == PlayType.bomb || type == PlayType.rocket;

  /// The ranks of the main part, with repeats (e.g. 333444 of an airplane).
  List<int> get mainRanks => [
        if (type == PlayType.rocket) ...[Rank.littleJoker, Rank.bigJoker]
        else
          for (var r = rank; r < rank + length; r++)
            for (var i = 0; i < type.mainCopies; i++) r,
      ];

  /// The attached cards (kickers or wings), low to high.
  List<int> get kickers {
    final rest = countsOfRanks(ranks);
    for (final r in mainRanks) {
      rest[r]--;
    }
    return [
      for (var r = 0; r < Rank.count; r++)
        for (var i = 0; i < rest[r]; i++) r,
    ];
  }

  /// Rank counts of the play.
  List<int> get counts => countsOfRanks(ranks);

  /// Whether this play may follow [other]: same kind and length with a
  /// higher main rank; a bomb beats anything but a higher bomb or the
  /// rocket; the rocket beats everything (Pagat).
  bool beats(Play other) {
    if (other.type == PlayType.rocket) return false;
    if (type == PlayType.rocket) return true;
    if (type == PlayType.bomb) return other.type != PlayType.bomb || rank > other.rank;
    if (other.type == PlayType.bomb) return false;
    return type == other.type && length == other.length && size == other.size && rank > other.rank;
  }

  /// A short machine-readable form, such as `"trioSolo:3334"`, for online
  /// messages and saved games. [Play.decode] reads it back.
  String encode() => '${type.name}:${ranksText(ranks)}';

  /// Reads [encode]. Throws [FormatException] when it isn't a valid play.
  static Play decode(String text, [DdzRules rules = DdzRules.standard]) {
    final colon = text.indexOf(':');
    if (colon < 0) throw FormatException('Not a play', text);
    final type = PlayType.values.asNameMap()[text.substring(0, colon)];
    final ranks = parseRanks(text.substring(colon + 1));
    for (final p in classifyPlay(ranks, rules)) {
      if (p.type == type) return p;
    }
    throw FormatException('Not a valid play', text);
  }

  @override
  bool operator ==(Object other) {
    if (other is! Play || other.type != type || other.ranks.length != ranks.length) return false;
    for (var i = 0; i < ranks.length; i++) {
      if (other.ranks[i] != ranks[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(type, Object.hashAll(ranks));

  /// Readable text: the main part, then "+" and the kickers.
  @override
  String toString() {
    final k = kickers;
    return k.isEmpty ? ranksText(mainRanks) : '${ranksText(mainRanks)}+${ranksText(k)}';
  }
}

/// A fixed total order of plays (kind, main rank, length, then cards), so
/// sorting gives the same order on every platform and sort algorithm.
int comparePlays(Play a, Play b) {
  var d = a.type.index - b.type.index;
  if (d != 0) return d;
  d = a.rank - b.rank;
  if (d != 0) return d;
  d = a.length - b.length;
  if (d != 0) return d;
  d = a.ranks.length - b.ranks.length;
  if (d != 0) return d;
  for (var i = 0; i < a.ranks.length; i++) {
    d = a.ranks[i] - b.ranks[i];
    if (d != 0) return d;
  }
  return 0;
}

/// Every way [ranks] can be read as one legal play, usually one or none.
///
/// The app turns the cards a player selected into a play with this; when
/// it returns several readings, pick the one that beats the play on the
/// table (see [readPlay]).
List<Play> classifyPlay(List<int> ranks, [DdzRules rules = DdzRules.standard]) {
  final n = ranks.length;
  if (n == 0) return const [];
  final c = countsOfRanks(ranks);
  final sorted = [...ranks]..sort();
  final out = <Play>[];
  final distinct = [for (var r = 0; r < Rank.count; r++) if (c[r] > 0) r];

  // Solo, pair, trio, bomb: one rank only.
  if (distinct.length == 1) {
    final r = distinct.first;
    if (n == 1) out.add(Play(PlayType.solo, r, 1, sorted));
    if (n == 2 && r <= Rank.two) out.add(Play(PlayType.pair, r, 1, sorted));
    if (n == 3) out.add(Play(PlayType.trio, r, 1, sorted));
    if (n == 4) out.add(Play(PlayType.bomb, r, 1, sorted));
  }
  if (n == 2 && c[Rank.littleJoker] == 1 && c[Rank.bigJoker] == 1) {
    out.add(Play(PlayType.rocket, Rank.littleJoker, 1, sorted));
  }

  // Chains whose every rank has the same count.
  if (distinct.isNotEmpty) {
    final lo = distinct.first;
    final hi = distinct.last;
    final copies = c[lo];
    final consecutive = hi - lo + 1 == distinct.length && hi <= Rank.highestInChain;
    final even = distinct.every((r) => c[r] == copies);
    if (consecutive && even) {
      final len = distinct.length;
      if (copies == 1 && len >= 5) out.add(Play(PlayType.straight, lo, len, sorted));
      if (copies == 2 && len >= 3) out.add(Play(PlayType.pairStraight, lo, len, sorted));
      if (copies == 3 && len >= 2) out.add(Play(PlayType.airplane, lo, len, sorted));
    }
  }

  // Trio with a solo or a pair.
  if (n == 4 || n == 5) {
    for (final t in distinct) {
      if (c[t] != 3 || t > Rank.two) continue;
      final rest = [...c]..[t] = 0;
      final restRanks = [for (var r = 0; r < Rank.count; r++) if (rest[r] > 0) r];
      if (n == 4 && restRanks.length == 1) out.add(Play(PlayType.trioSolo, t, 1, sorted));
      if (n == 5 && restRanks.length == 1 && rest[restRanks.first] == 2 && restRanks.first <= Rank.two) {
        out.add(Play(PlayType.trioPair, t, 1, sorted));
      }
    }
  }

  // Airplanes with wings: try every run of trios of the right length.
  for (final (type, perUnit) in const [(PlayType.airplaneSolos, 4), (PlayType.airplanePairs, 5)]) {
    if (n % perUnit != 0) continue;
    final len = n ~/ perUnit;
    if (len < 2) continue;
    for (var start = 0; start + len - 1 <= Rank.highestInChain; start++) {
      var ok = true;
      for (var r = start; r < start + len; r++) {
        // Exactly three: a fourth card of a trio rank would be a wing of the
        // same rank as a triplet, which Pagat forbids.
        if (c[r] != 3) {
          ok = false;
          break;
        }
      }
      if (!ok) continue;
      final wings = [...c];
      for (var r = start; r < start + len; r++) {
        wings[r] = 0;
      }
      if (type == PlayType.airplaneSolos) {
        if (_validSoloKickers(wings, len, 2, rules)) out.add(Play(type, start, len, sorted));
      } else {
        if (_validPairKickers(wings, len)) out.add(Play(type, start, len, sorted));
      }
    }
  }

  // Four with two solos or two pairs.
  if (rules.fourWithTwo && (n == 6 || n == 8)) {
    for (final f in distinct) {
      if (c[f] != 4) continue;
      final rest = [...c]..[f] = 0;
      if (n == 6 && _validSoloKickers(rest, 2, 1, rules)) out.add(Play(PlayType.fourTwoSolos, f, 1, sorted));
      if (n == 8 && _validPairKickers(rest, 2)) out.add(Play(PlayType.fourTwoPairs, f, 1, sorted));
    }
  }
  return out;
}

/// The reading of [ranks] that may be played now: the one that beats
/// [current] (or any reading when leading). Null when none is legal.
Play? readPlay(List<int> ranks, Play? current, [DdzRules rules = DdzRules.standard]) {
  for (final p in classifyPlay(ranks, rules)) {
    if (current == null || p.beats(current)) return p;
  }
  return null;
}

/// Whether the leftover counts [k] are [units] solo kickers with at most
/// [maxPerRank] of any rank, and not both jokers unless the rules allow it.
bool _validSoloKickers(List<int> k, int units, int maxPerRank, DdzRules rules) {
  var total = 0;
  for (var r = 0; r < Rank.count; r++) {
    if (k[r] > maxPerRank) return false;
    total += k[r];
  }
  if (total != units) return false;
  if (!rules.rocketAsKickers && k[Rank.littleJoker] > 0 && k[Rank.bigJoker] > 0) return false;
  return true;
}

/// Whether the leftover counts [k] are exactly [units] pairs of different
/// ranks (jokers can't pair).
bool _validPairKickers(List<int> k, int units) {
  var pairs = 0;
  for (var r = 0; r < Rank.count; r++) {
    if (k[r] == 0) continue;
    if (k[r] != 2 || r > Rank.two) return false;
    pairs++;
  }
  return pairs == units;
}
