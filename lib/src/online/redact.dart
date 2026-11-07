/// The only places hole cards leave the server: [redactFor] (a seat's own,
/// or a spectator's, see [Viewer]), [botCardsFor] (the host's bots, to the
/// host's device) and [shownCardsFor] (a player who shows their cards after
/// the hand). Never sent: the deck, the cards not dealt yet, any seed.
library;

import '../engine/cards.dart';
import '../engine/events.dart';
import '../engine/poker_hand.dart';

/// Who a hand's events are for.
sealed class Viewer {
  const Viewer();
}

/// A seated player: hand seat [seat] sees only its own hole cards (null:
/// seated, but not dealt in this hand, sees none).
final class SeatViewer extends Viewer {
  const SeatViewer(this.seat);
  final int? seat;
}

/// A spectator: sees the hole cards of the hand seats in [visible] (every
/// person's, and the bots' when the host lets spectators see them).
final class SpectatorViewer extends Viewer {
  const SpectatorViewer(this.visible);
  final Set<int> visible;
}

/// [event] as [viewer] may see it. Everything else in a hand is public by
/// the time it happens (the board as it is dealt, hands when they are
/// shown), so the server sends it to everyone as it is.
///
/// Every kind of event is listed, with no default: a new one has to be
/// looked at here before it can be sent.
GameEvent redactFor(GameEvent event, Viewer viewer) => switch (event) {
  HoleCardsDealt() => HoleCardsDealt(
    dealOrder: event.dealOrder,
    cards: {
      for (final MapEntry(key: seat, value: cards) in event.cards.entries)
        if (switch (viewer) {
          SeatViewer(seat: final mine) => seat == mine,
          SpectatorViewer(:final visible) => visible.contains(seat),
        })
          seat: cards,
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
  HandEnded() => event,
};

List<GameEvent> redactBatchFor(Iterable<GameEvent> batch, Viewer viewer) => [
  for (final e in batch) redactFor(e, viewer),
];

/// A whole hand so far (one batch of events per action, the deal first),
/// as [viewer] may see it: for a member who joins or reconnects.
List<List<GameEvent>> redactBatchesFor(Iterable<List<GameEvent>> batches, Viewer viewer) => [
  for (final b in batches) redactBatchFor(b, viewer),
];

/// [batch] as the player in hand seat [viewerSeat] sees it (null: one not
/// dealt in): [redactBatchFor] with a [SeatViewer].
List<GameEvent> redactBatch(Iterable<GameEvent> batch, int? viewerSeat) =>
    redactBatchFor(batch, SeatViewer(viewerSeat));

/// The bots' cards, for the host's device, which plays the bots: only the
/// [botSeats] (never a seat a person holds).
Map<int, List<PlayingCard>> botCardsFor(PokerHand hand, Iterable<int> botSeats) => {
  for (final seat in botSeats)
    if (hand.knows(seat)) seat: hand.holeCards(seat),
};

/// The cards hand seat [seat] shows to everyone once [hand] is over (their
/// own, by their choice); null while it goes on, or for a seat with no
/// cards.
List<PlayingCard>? shownCardsFor(PokerHand hand, {required int seat}) {
  if (!hand.isOver || seat < 0 || seat >= hand.playerCount) return null;
  return hand.knows(seat) ? hand.holeCards(seat) : null;
}
