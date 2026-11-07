/// Cards as Big Two players see them.
///
/// A card here is physical: a rank and a suit. Which suit is high changes
/// from one rule set to another (see `BigTwoRules.suitOrder`), so the order
/// of [Suit] means nothing for play. The engine compares cards through the
/// rules, never through this file.
library;

/// The four suits, named by their symbol. Their order here is only the
/// order of the letters in [Card.parse]; the rules decide which suit wins.
enum Suit {
  diamonds('d', '♦'),
  clubs('c', '♣'),
  hearts('h', '♥'),
  spades('s', '♠');

  const Suit(this.letter, this.symbol);

  /// The letter used in short notation such as `3d`.
  final String letter;

  /// The symbol shown on a card face.
  final String symbol;

  /// True for the two red suits, so the app can colour them.
  bool get isRed => this == diamonds || this == hearts;
}

/// Rank numbers run in Big Two order, low to high: 0 is the 3, 11 the ace
/// and 12 the 2. Pagat: "Card Rank (High to Low): 2-A-K-Q-J-10-9-8-7-6-5-4-3"
/// (https://www.pagat.com/climbing/bigtwo.html).
abstract final class Ranks {
  /// The lowest rank, the 3.
  static const three = 0;

  /// The jack, used by straight rules that name it.
  static const jack = 8;

  /// The king, the third highest rank.
  static const king = 10;

  /// The ace, the second highest rank.
  static const ace = 11;

  /// The 2, the highest rank ("Big Two").
  static const two = 12;

  /// Short labels in rank order, as printed on a card face.
  static const labels = ['3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A', '2'];

  /// The one-character form used when parsing (`T` for ten).
  static const chars = '3456789TJQKA2';
}

/// One physical card: `id = rank * 4 + suit.index`, with [rank] in Big Two
/// order (0 = the 3, 12 = the 2).
///
/// An extension type, so a list of cards is a plain list of ints at run time:
/// cheap to copy into a worker message and equal when the ids are equal.
extension type const Card._(int id) {
  /// The card with this Big Two [rank] (0 = the 3 ... 12 = the 2) and [suit].
  Card.of(int rank, Suit suit) : id = rank * 4 + suit.index;

  /// The card with this [id], as stored by [Card.id].
  Card.fromId(int id) : this._(id);

  /// Parses short notation like `3d`, `Ts`, `10h` or `2s`, the same style as
  /// the poker cards elsewhere in the app.
  factory Card.parse(String text) {
    final t = text.trim();
    if (t.length < 2 || t.length > 3) {
      throw FormatException('A card is a rank and a suit, like "3d"', text);
    }
    final rankText = t.substring(0, t.length - 1).toUpperCase();
    final rank = rankText == '10' ? 7 : (rankText.length == 1 ? Ranks.chars.indexOf(rankText) : -1);
    final suitChar = t[t.length - 1].toLowerCase();
    final suit = Suit.values.indexWhere((s) => s.letter == suitChar);
    if (rank < 0 || suit < 0) throw FormatException('Unknown card', text);
    return Card.of(rank, Suit.values[suit]);
  }

  /// Big Two rank: 0 is the 3, 11 the ace, 12 the 2.
  int get rank => id >> 2;

  /// The card's suit.
  Suit get suit => Suit.values[id & 3];

  /// Rank as shown on the card face ("10", not "T").
  String get rankLabel => Ranks.labels[rank];

  /// Readable form such as `3♦` or `10♠`, for logs and tests.
  String get label => '$rankLabel${suit.symbol}';

  /// Short ASCII form that [Card.parse] reads back, such as `3d` or `Ts`.
  String get short => '${Ranks.chars[rank]}${suit.letter}';
}

/// Parses a space-separated list such as `3d 3s Ts`.
List<Card> parseCards(String text) =>
    text.trim().isEmpty ? <Card>[] : text.trim().split(RegExp(r'\s+')).map(Card.parse).toList();

/// All 52 cards in id order.
final List<Card> fullDeck = List<Card>.unmodifiable(List.generate(52, Card.fromId));
