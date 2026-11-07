/// Cards, the ten blackjack ranks, hand totals and shoe compositions.
///
/// Blackjack only cares about ten kinds of card: the ace, 2 to 9, and the
/// "ten-value" cards (10, J, Q, K all count 10). The engine keeps every
/// count and probability per rank index:
///
///   index 0 = ace, 1 = two, ..., 8 = nine, 9 = any ten-value card.
///
/// A real [Card] still has its face and suit so the app can draw it.
library;

import 'dart:typed_data';

/// The number of distinct blackjack ranks (ace, 2..9, ten-value).
const int rankCount = 10;

/// The rank index of the ace.
const int aceIndex = 0;

/// The rank index of the ten-value cards (10, J, Q, K).
const int tenIndex = 9;

/// The hard points of the rank at [index]: the ace counts 1 (the soft 11
/// is added by [handTotal]), the ten-value cards 10.
int rankPoints(int index) => index + 1;

/// The short name of a rank index as charts write it: A, 2..9, T.
String rankName(int index) => index == aceIndex
    ? 'A'
    : index == tenIndex
    ? 'T'
    : '${index + 1}';

/// The rank index for a chart-style name ('A', '2'..'9', 'T', '10', 'J',
/// 'Q', 'K'). Throws on anything else.
int rankIndexOf(String name) {
  switch (name.toUpperCase()) {
    case 'A':
      return aceIndex;
    case 'T':
    case '10':
    case 'J':
    case 'Q':
    case 'K':
      return tenIndex;
  }
  final v = int.tryParse(name);
  if (v == null || v < 2 || v > 9) throw FormatException('Not a blackjack rank: $name');
  return v - 1;
}

/// One playing card from a 52-card deck.
///
/// Cards are canonical instances ([Card.of]), so `==` and `identical`
/// agree and a shoe of 8 decks costs no more than a list of references.
class Card {
  const Card._(this.face, this.suit);

  /// The card with this [face] (1 = ace, 2..10, 11 = jack, 12 = queen,
  /// 13 = king) and [suit] (0 clubs, 1 diamonds, 2 hearts, 3 spades).
  factory Card.of(int face, int suit) {
    if (face < 1 || face > 13 || suit < 0 || suit > 3) throw RangeError('Card $face/$suit');
    return _all[(face - 1) * 4 + suit];
  }

  /// Reads "As", "Td", "10h", "Kc" (face then suit letter c/d/h/s). Used by
  /// tests and the command-line tool.
  factory Card.parse(String text) {
    final t = text.trim();
    final suitChar = t[t.length - 1].toLowerCase();
    final suit = 'cdhs'.indexOf(suitChar);
    if (suit < 0) throw FormatException('Bad suit in $text');
    final f = t.substring(0, t.length - 1).toUpperCase();
    final face = switch (f) {
      'A' => 1,
      'T' || '10' => 10,
      'J' => 11,
      'Q' => 12,
      'K' => 13,
      _ => int.tryParse(f) ?? 0,
    };
    return Card.of(face, suit);
  }

  static final List<Card> _all = [
    for (var face = 1; face <= 13; face++)
      for (var suit = 0; suit < 4; suit++) Card._(face, suit),
  ];

  /// Every card of one deck, in a fixed order.
  static List<Card> get deck => List.unmodifiable(_all);

  /// 1 = ace, 2..10, 11 = jack, 12 = queen, 13 = king.
  final int face;

  /// 0 clubs, 1 diamonds, 2 hearts, 3 spades.
  final int suit;

  /// The blackjack rank index (see the library comment): what the maths
  /// uses, since a king and a ten play the same.
  int get rank => face >= 10 ? tenIndex : face - 1;

  /// The card's hard points: ace 1, faces 10.
  int get points => rankPoints(rank);

  /// The card's index 0..51 in [deck] order (handy for compact storage).
  int get code => (face - 1) * 4 + suit;

  @override
  String toString() {
    const faces = ['A', '2', '3', '4', '5', '6', '7', '8', '9', 'T', 'J', 'Q', 'K'];
    return '${faces[face - 1]}${'cdhs'[suit]}';
  }
}

/// A hand's total as a player counts it.
class HandTotal {
  /// A total of [value] points, [soft] when an ace is counted as 11.
  const HandTotal(this.value, this.soft);

  /// The best total not over 21 if there is one (an ace counts 11 when
  /// that doesn't bust), otherwise the hard total.
  final int value;

  /// True when an ace is counted as 11, so one more card can't bust it.
  final bool soft;

  /// Over 21.
  bool get isBust => value > 21;

  @override
  bool operator ==(Object other) => other is HandTotal && other.value == value && other.soft == soft;

  @override
  int get hashCode => value * 2 + (soft ? 1 : 0);

  @override
  String toString() => '${soft ? 'soft ' : ''}$value';
}

/// The total of a hand with these hard points ([hard], aces as 1) and
/// [hasAce]: the soft total when an ace can count 11 without busting.
HandTotal totalOf(int hard, bool hasAce) =>
    hasAce && hard + 10 <= 21 ? HandTotal(hard + 10, true) : HandTotal(hard, false);

/// The total of [cards].
HandTotal handTotal(Iterable<Card> cards) {
  var hard = 0;
  var ace = false;
  for (final c in cards) {
    hard += c.points;
    if (c.rank == aceIndex) ace = true;
  }
  return totalOf(hard, ace);
}

/// How many cards of each rank are in some set of cards (a shoe, the
/// unseen cards, a hand). The maths works on these counts, not on card
/// order: every order of the unseen cards is equally likely, so only the
/// counts matter for probabilities.
class Composition {
  /// A composition with these ten counts (ace first, ten-value last).
  Composition(List<int> counts) : _counts = Int32List.fromList(counts) {
    if (counts.length != rankCount) throw ArgumentError('need $rankCount counts');
    for (final c in _counts) {
      if (c < 0) throw ArgumentError('negative count');
    }
  }

  /// The cards of [decks] full decks: 4 of each rank per deck and 16
  /// ten-value cards.
  factory Composition.decks(int decks) =>
      Composition([for (var r = 0; r < rankCount; r++) r == tenIndex ? 16 * decks : 4 * decks]);

  /// The counts of [cards].
  factory Composition.ofCards(Iterable<Card> cards) {
    final c = List<int>.filled(rankCount, 0);
    for (final card in cards) {
      c[card.rank]++;
    }
    return Composition(c);
  }

  final Int32List _counts;

  /// The count of rank [index].
  int operator [](int index) => _counts[index];

  /// The number of cards in all.
  int get total {
    var t = 0;
    for (final c in _counts) {
      t += c;
    }
    return t;
  }

  /// The ten counts, as a fresh list.
  List<int> get counts => List<int>.of(_counts);

  /// This composition without [cards]. Throws if a card isn't there,
  /// which would mean a bookkeeping bug.
  Composition without(Iterable<Card> cards) {
    final c = List<int>.of(_counts);
    for (final card in cards) {
      if (--c[card.rank] < 0) throw StateError('removing a ${rankName(card.rank)} that is not there');
    }
    return Composition(c);
  }

  /// This composition with [cards] added.
  Composition plus(Iterable<Card> cards) {
    final c = List<int>.of(_counts);
    for (final card in cards) {
      c[card.rank]++;
    }
    return Composition(c);
  }

  @override
  bool operator ==(Object other) {
    if (other is! Composition) return false;
    for (var r = 0; r < rankCount; r++) {
      if (other._counts[r] != _counts[r]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_counts);

  @override
  String toString() => [for (var r = 0; r < rankCount; r++) '${rankName(r)}:${_counts[r]}'].join(' ');
}
