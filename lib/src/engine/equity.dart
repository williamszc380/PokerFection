import 'dart:math';

import 'cards.dart';
import 'hand_evaluator.dart';

/// Estimates how often [hole] wins against [opponents] random hands, by
/// dealing [trials] random runouts. Split pots count as a partial win.
double estimateEquity({
  required List<PlayingCard> hole,
  required List<PlayingCard> board,
  required int opponents,
  required Random random,
  int trials = 300,
}) {
  assert(hole.length == 2 && board.length <= 5 && opponents >= 1);
  final known = {for (final c in [...hole, ...board]) c.index};
  final deck = [
    for (var i = 0; i < 52; i++)
      if (!known.contains(i)) i,
  ];
  final missing = 5 - board.length;
  final needed = missing + 2 * opponents;
  final boardCards = [for (final c in board) c.index];
  final mine = List<int>.filled(7, 0)
    ..[0] = hole[0].index
    ..[1] = hole[1].index;
  final theirs = List<int>.filled(7, 0);

  var wins = 0.0;
  for (var t = 0; t < trials; t++) {
    // Move `needed` random cards to the front of the deck.
    for (var i = 0; i < needed; i++) {
      final j = i + random.nextInt(deck.length - i);
      final tmp = deck[i];
      deck[i] = deck[j];
      deck[j] = tmp;
    }
    for (var i = 0; i < 5; i++) {
      final card = i < boardCards.length ? boardCards[i] : deck[i - boardCards.length];
      mine[2 + i] = card;
      theirs[2 + i] = card;
    }
    final myScore = evaluateIndices(mine);
    var tied = 1;
    var beaten = false;
    for (var o = 0; o < opponents; o++) {
      theirs[0] = deck[missing + 2 * o];
      theirs[1] = deck[missing + 2 * o + 1];
      final score = evaluateIndices(theirs);
      if (score > myScore) {
        beaten = true;
        break;
      }
      if (score == myScore) tied++;
    }
    if (!beaten) wins += 1 / tied;
  }
  return wins / trials;
}
