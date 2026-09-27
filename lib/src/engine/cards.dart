import 'dart:math';

/// A standard playing card.
///
/// [index] runs from 0 to 51: `rank = index ~/ 4` (0 = deuce ... 12 = ace)
/// and `suit = index % 4` (clubs, diamonds, hearts, spades).
class PlayingCard {
  const PlayingCard(this.index) : assert(index >= 0 && index < 52);

  factory PlayingCard.of(int rank, int suit) => PlayingCard(rank * 4 + suit);

  /// Parses short notation such as `As`, `Td` or `7h`.
  factory PlayingCard.parse(String text) {
    if (text.length != 2) {
      throw FormatException('Card must be two characters, like "As"', text);
    }
    final rank = rankChars.indexOf(text[0].toUpperCase());
    final suit = suitChars.indexOf(text[1].toLowerCase());
    if (rank < 0 || suit < 0) throw FormatException('Unknown card', text);
    return PlayingCard.of(rank, suit);
  }

  static const rankChars = '23456789TJQKA';
  static const suitChars = 'cdhs';
  static const suitSymbols = ['♣', '♦', '♥', '♠'];

  final int index;

  int get rank => index >> 2;
  int get suit => index & 3;

  /// Rank as shown on a card face ("10" instead of "T").
  String get rankLabel => rank == 8 ? '10' : rankChars[rank];
  String get suitSymbol => suitSymbols[suit];
  bool get isRed => suit == 1 || suit == 2;

  @override
  bool operator ==(Object other) => other is PlayingCard && other.index == index;

  @override
  int get hashCode => index;

  @override
  String toString() => '${rankChars[rank]}${suitChars[suit]}';
}

/// Parses a space-separated list such as `"As Kd 7h"`.
List<PlayingCard> parseCards(String text) => text
    .split(RegExp(r'\s+'))
    .where((s) => s.isNotEmpty)
    .map(PlayingCard.parse)
    .toList();

/// A shuffled deck. Cards in [exclude] are left out (already dealt or fixed).
class Deck {
  Deck.shuffled(Random random, {Iterable<PlayingCard> exclude = const []}) {
    final excluded = exclude.map((c) => c.index).toSet();
    _cards = [
      for (var i = 0; i < 52; i++)
        if (!excluded.contains(i)) i,
    ]..shuffle(random);
  }

  late final List<int> _cards;
  int _next = 0;

  int get remaining => _cards.length - _next;

  PlayingCard deal() {
    if (_next >= _cards.length) throw StateError('Deck is empty');
    return PlayingCard(_cards[_next++]);
  }
}
