/// Card counting for the app's counter panel: which high cards are still
/// out, how many cards each player holds, and whether your top card is the
/// boss.
library;

import 'cards.dart';
import 'plays.dart' show masksOf;
import 'state.dart';

/// What a seat can count from its view. All lists use physical [Card]s so
/// the app can draw them directly.
class CardCounter {
  CardCounter._(this.view, this.out, this.cardsLeft);

  /// Counts for [view].
  factory CardCounter.of(BigTwoView view) {
    return CardCounter._(view, view.opponentCodes, List.unmodifiable(view.counts));
  }

  /// The view this was counted from.
  final BigTwoView view;

  /// Engine codes of every card this seat hasn't seen played and doesn't
  /// hold, lowest first ([BigTwoView.opponentCodes]). In two-player games
  /// this includes unused cards above the starting card (the ones below it
  /// were never dealt).
  final List<int> out;

  /// Cards each seat still holds.
  final List<int> cardsLeft;

  /// Every card still out, lowest first.
  List<Card> get outCards => [for (final c in out) view.rules.cardOf(c)];

  /// The cards of [rank] still out (0 = the 3 ... 12 = the 2).
  List<Card> outOfRank(int rank) => [for (final c in out) if (c >> 2 == rank) view.rules.cardOf(c)];

  /// The 2s still out, highest first.
  List<Card> get twosOut => outOfRank(Ranks.two).reversed.toList();

  /// The aces still out, highest first.
  List<Card> get acesOut => outOfRank(Ranks.ace).reversed.toList();

  /// The kings still out, highest first.
  List<Card> get kingsOut => outOfRank(Ranks.king).reversed.toList();

  /// The highest single still out, or null if none.
  Card? get highestOut => out.isEmpty ? null : view.rules.cardOf(out.last);

  /// True when your highest card beats every single still out, so leading
  /// or playing it wins the trick ("your 2♠ is the boss").
  bool get myTopSingleWins {
    if (view.handCodes.isEmpty) return false;
    return out.isEmpty || view.handCodes.last > out.last;
  }

  /// True if the cards still out could still make a pair of 2s.
  bool get pairOfTwosPossible => outOfRank(Ranks.two).length >= 2;

  /// True if a four of a kind (or, with the rules' straights, a straight
  /// flush) could still be made from the cards still out, so a bomb or top
  /// five-card hand may be waiting.
  bool get bombPossible {
    final m = masksOf(out);
    for (var r = 0; r < 13; r++) {
      if (m[r] == 15) return true;
    }
    final rules = view.rules;
    for (var pos = 0; pos < rules.straights.order.length; pos++) {
      final start = rules.straightStart(pos);
      for (var s = 0; s < 4; s++) {
        var all = true;
        for (var k = 0; k < 5 && all; k++) {
          if (m[(start + k) % 13] & (1 << s) == 0) all = false;
        }
        if (all) return true;
      }
    }
    return false;
  }

  /// The single the last-card rule made [seat] play as their highest card:
  /// they hold nothing higher (null when nothing is known).
  Card? capOf(int seat) {
    final b = view.bounds[seat];
    return b >= 52 ? null : view.rules.cardOf(b);
  }
}
