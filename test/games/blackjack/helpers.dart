import 'package:pokerfection/src/games/blackjack/blackjack.dart';

/// Cards from short text ("As Kd 7h", "T" = ten).
List<Card> cards(String text) => [
  for (final t in text.split(' '))
    if (t.isNotEmpty) Card.parse(t),
];

/// A round whose shoe starts with [top] (in dealing order: each seat's first
/// card, the dealer's upcard, each seat's second card, the hole card in hole
/// card games, then every card drawn after), with one bet per seat.
BlackjackRound stacked(BlackjackRules rules, String top, {List<int> bets = const [10], int seed = 1}) {
  final shoe = Shoe.forRules(rules, seed: seed)..stack(cards(top));
  return BlackjackRound.deal(rules, shoe, bets);
}

/// Plays [actions] in order for whoever is to act.
void play(BlackjackRound round, List<BlackjackAction> actions) {
  for (final a in actions) {
    round.apply(a);
  }
}

/// A card of blackjack rank index [rank] (any suit).
Card ofRank(int rank, [int suit = 0]) => Card.of(rank == tenIndex ? 10 : rank + 1, suit);

/// A full shoe of [decks] decks minus [gone].
Composition shoeWithout(int decks, String gone) => Composition.decks(decks).without(cards(gone));
