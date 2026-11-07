/// The shoe: a shuffled order of cards plus counts per rank, shuffled from
/// a seed (solo games, replayed from their record) or from a given Random
/// (online, the room's `Random.secure()`, so there is no seed at all).
library;

import 'dart:math' as math;

import 'cards.dart';
import 'random.dart';
import 'rules.dart';

/// The cards waiting to be dealt, in order, and what has been dealt since
/// the last shuffle.
///
/// The order is the only secret: everything dealt face up since the
/// shuffle is public (a player at the table could have watched it), so
/// views and the coach may use [dealt] freely, except the dealer's hole
/// card while it is face down (the round keeps that out of views).
class Shoe {
  /// A freshly shuffled shoe of [decks] decks. With [penetration] the cut
  /// card sits after that share of the cards; [continuous] makes it a
  /// continuous shuffler (see [startRound]).
  ///
  /// [random]: every shuffle draws from it instead of a generator seeded
  /// with [seed]. Online the room passes its `Random.secure()`: a seed could
  /// be searched from the cards a player sees, and then the whole shoe
  /// would be known. A seeded shoe replays the same everywhere (the solo
  /// game's record keeps only the seed); a shoe with [random] never can.
  Shoe({required this.decks, this.penetration = 0.75, this.continuous = false, int seed = 0, math.Random? random})
    : _random = random == null ? GameRandom(seed) : null,
      _secure = random {
    shuffle();
  }

  /// A shoe for [rules] (see the constructor for [seed] and [random]).
  factory Shoe.forRules(BlackjackRules rules, {int seed = 0, math.Random? random}) => Shoe(
    decks: rules.decks,
    penetration: rules.penetration,
    continuous: rules.continuousShuffle,
    seed: seed,
    random: random,
  );

  /// A copy of a shoe shuffled from a given Random shares that Random: its
  /// next shuffles come from the same source, so the copy can't replay the
  /// original's (nothing online copies a shoe: look-ahead is a solo thing).
  Shoe._copy(Shoe other)
    : decks = other.decks,
      penetration = other.penetration,
      continuous = other.continuous,
      _random = other._random?.copy(),
      _secure = other._secure,
      _order = List<Card>.of(other._order),
      _next = other._next,
      _roundStart = other._roundStart,
      _shuffles = other._shuffles;

  /// Decks in the shoe.
  final int decks;

  /// Share of the shoe dealt before the cut card comes out.
  final double penetration;

  /// A continuous shuffling machine: every round starts from a freshly
  /// shuffled full shoe.
  final bool continuous;

  /// The seeded generator, or (null) the given Random [_secure].
  final GameRandom? _random;
  final math.Random? _secure;
  List<Card> _order = const [];
  int _next = 0;
  int _roundStart = 0;
  int _shuffles = 0;

  /// An independent copy (same order, same position, same random stream).
  Shoe copy() => Shoe._copy(this);

  /// Cards in the full shoe.
  int get size => decks * 52;

  /// Cards not dealt yet.
  int get cardsLeft => _order.length - _next;

  /// Where the cut card is: once this many cards are dealt, the shoe is
  /// reshuffled before the next round.
  int get cutCard => (size * penetration).round();

  /// The cut card has come out (or the shoe is a continuous shuffler), so
  /// the next round starts with a shuffle.
  bool get needsShuffle => continuous || _next >= cutCard;

  /// How many times the shoe has been shuffled (1 after creation).
  int get shuffles => _shuffles;

  /// Every card dealt since the last shuffle, in order.
  List<Card> get dealt => List.unmodifiable(_order.sublist(0, _next));

  /// The cards dealt since the shuffle before this round started.
  List<Card> get dealtBeforeRound => List.unmodifiable(_order.sublist(0, _roundStart));

  /// Counts of the cards not dealt yet.
  Composition get remaining => Composition.ofCards(_order.sublist(_next));

  /// The cards still to come, in order: the shoe's secret. Never for a
  /// view or anything sent; the online game's tests use it to check that
  /// no message holds a card nobody may see yet.
  List<Card> get cardsToCome => List.unmodifiable(_order.sublist(_next));

  /// A number in 0 .. [max] - 1 from the shoe's source.
  int _nextInt(int max) => _secure?.nextInt(max) ?? _random!.nextInt(max);

  /// Shuffles [list] in place (Fisher–Yates) from the shoe's source: the
  /// seeded generator's own shuffle, so seeded shoes deal as they always
  /// have.
  void _shuffle(List<Card> list) {
    final random = _random;
    if (random != null) return random.shuffle(list);
    for (var i = list.length - 1; i > 0; i--) {
      final j = _nextInt(i + 1);
      final t = list[i];
      list[i] = list[j];
      list[j] = t;
    }
  }

  /// Shuffles every card back into the shoe.
  void shuffle() {
    final cards = <Card>[for (var d = 0; d < decks; d++) ...Card.deck];
    _shuffle(cards);
    _order = cards;
    _next = 0;
    _roundStart = 0;
    _shuffles++;
  }

  /// Called before a round's first card: shuffles if the cut card has
  /// come out (always, for a continuous shuffler).
  void startRound() {
    if (needsShuffle) shuffle();
    _roundStart = _next;
  }

  /// Deals the next card. If the shoe runs out mid-round (possible only
  /// with very deep cuts and many seats), the cards not on the table are
  /// shuffled into a new shoe, as a dealer would do with the discards.
  Card draw() {
    if (_next >= _order.length) _reshuffleDiscards();
    return _order[_next++];
  }

  void _reshuffleDiscards() {
    final onTable = _order.sublist(_roundStart, _next);
    // Every card of the shoe except those on the table.
    final pool = <Card>[];
    final need = List<int>.filled(52, decks);
    for (final c in onTable) {
      need[c.code]--;
    }
    for (final c in Card.deck) {
      for (var i = 0; i < need[c.code]; i++) {
        pool.add(c);
      }
    }
    if (pool.isEmpty) {
      // Every card is on the table (only conceivable with one deck and
      // seven seats): open a fresh deck's worth.
      for (var d = 0; d < decks; d++) {
        pool.addAll(Card.deck);
      }
    }
    _shuffle(pool);
    _order = [...onTable, ...pool];
    _next = onTable.length;
    _roundStart = 0;
    _shuffles++;
  }

  /// Puts specific cards on top of the shoe (dealt next, in order). For
  /// tests and lessons that need an exact deal; the cards are taken out of
  /// the rest of the shoe so the counts stay right.
  ///
  /// With several decks there are several copies of each card. The copy
  /// taken out is picked at random, so the cards under the stacked ones
  /// stay in a fair random order. Always taking the first copy would push
  /// the other copies deeper than chance would put them, and every deal
  /// after a stacked one (a lesson, a scripted hand, a simulation) would
  /// be biased.
  void stack(List<Card> top) {
    final rest = List<Card>.of(_order.sublist(_next));
    for (final c in top) {
      final copies = <int>[
        for (var i = 0; i < rest.length; i++)
          if (rest[i] == c) i,
      ];
      if (copies.isEmpty) throw StateError('$c is not left in the shoe');
      // Only one copy: nothing to choose, and the random stream is left
      // alone (single-deck deals replay exactly as before).
      rest.removeAt(copies.length == 1 ? copies.first : copies[_nextInt(copies.length)]);
    }
    _order = [..._order.sublist(0, _next), ...top, ...rest];
  }
}
