/// The only places hole cards leave the server: [redactFor] (a player's
/// own), [botCardsFor] (the host's bots) and [peekCardsFor] (a look the
/// host allows).
library;

import '../engine/cards.dart';
import '../engine/events.dart';
import '../engine/poker_hand.dart';

/// [event] as the player in [viewerSeat] may see it (null: someone with no
/// seat): only their own hole cards. Everything else in a hand is public
/// by the time it happens (the board as it is dealt, hands when they are
/// shown), so the server sends it to everyone as it is.
///
/// Every kind of event is listed, with no default: a new one has to be
/// looked at here before it can be sent.
GameEvent redactFor(GameEvent event, int? viewerSeat) => switch (event) {
      HoleCardsDealt() => HoleCardsDealt(
          dealOrder: event.dealOrder,
          cards: {
            if (viewerSeat != null && event.cards.containsKey(viewerSeat)) viewerSeat: event.cards[viewerSeat]!,
          },
        ),
      HandStarted() ||
      AntesPosted() ||
      BlindPosted() ||
      ActionTaken() ||
      UncalledBetReturned() ||
      BetsCollected() ||
      BoardDealt() ||
      HandsRevealed() ||
      PotAwarded() ||
      HandEnded() =>
        event,
    };

List<GameEvent> redactBatch(Iterable<GameEvent> batch, int? viewerSeat) =>
    [for (final e in batch) redactFor(e, viewerSeat)];

/// A whole hand so far (one batch of events per action, the deal first),
/// as [viewerSeat] may see it: for a player who reconnects.
List<List<GameEvent>> redactBatches(Iterable<List<GameEvent>> batches, int? viewerSeat) =>
    [for (final b in batches) redactBatch(b, viewerSeat)];

/// The bots' cards, for the host's device, which plays the bots: only the
/// [botSeats] (never a seat a person holds).
Map<int, List<PlayingCard>> botCardsFor(PokerHand hand, Iterable<int> botSeats) => {
      for (final seat in botSeats)
        if (hand.knows(seat)) seat: hand.holeCards(seat),
    };

/// The cards of [seat] for the player in [viewerSeat] who asked to see them
/// (only while the hand runs, and when the host lets players look: [allowed]).
/// Null when they may not: looking is off, the hand is over, the seat is
/// their own or not in the hand.
/// The cards hand seat [seat] shows to everyone once [hand] is over (their
/// own, by their choice); null while it goes on, or for a seat with no
/// cards.
List<PlayingCard>? shownCardsFor(PokerHand hand, {required int seat}) {
  if (!hand.isOver || seat < 0 || seat >= hand.playerCount) return null;
  return hand.knows(seat) ? hand.holeCards(seat) : null;
}

List<PlayingCard>? peekCardsFor(PokerHand hand, {required int seat, required int viewerSeat, required bool allowed}) {
  if (!allowed || hand.isOver || seat == viewerSeat) return null;
  if (seat < 0 || seat >= hand.playerCount || viewerSeat < 0 || viewerSeat >= hand.playerCount) return null;
  return hand.knows(seat) ? hand.holeCards(seat) : null;
}
