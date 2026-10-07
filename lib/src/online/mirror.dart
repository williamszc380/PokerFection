/// Online, every device keeps its own copy of the server's hand, a
/// [PokerHand.mirror], replaying the server's events on it: it gives the
/// legal actions, the raise sizes and the help, exactly as in a hand played
/// on the device. These helpers build and advance one, checking on the way
/// that it plays out exactly like the server's.
library;

import '../engine/actions.dart';
import '../engine/cards.dart';
import '../engine/events.dart';
import '../engine/poker_hand.dart';
import '../engine/rules.dart';
import 'event_codec.dart';

/// The mirror played out differently from the server's hand (or refused a
/// move): it can't be trusted any more, and is built again from a fresh
/// copy of the hand.
class MirrorMismatch implements Exception {
  MirrorMismatch(this.message);
  final String message;

  @override
  String toString() => 'MirrorMismatch: $message';
}

/// The move [e] records, to replay it.
PlayerAction actionOf(ActionTaken e) => switch (e.kind) {
      ActionKind.fold => const PlayerAction.fold(),
      ActionKind.check => const PlayerAction.check(),
      ActionKind.call => const PlayerAction.call(),
      ActionKind.bet || ActionKind.raise => PlayerAction.raiseTo(e.streetBet),
    };

/// The start of a hand played elsewhere, as one device knows it: the first
/// batch of the server's events (in this device's seats, see SeatMap), and
/// on the host's device the bots' cards too.
class RemoteDeal {
  RemoteDeal({
    required this.handNumber,
    required this.buttonSeat,
    required this.stacks,
    this.known = const {},
    this.board = const [],
    this.revealed = const {},
    this.events = const [],
  });

  /// The deal in [batch], the first batch of a hand (from HandStarted
  /// through the hole cards, and on to the end when the blinds put
  /// everyone all-in), plus the cards known from elsewhere: on the host's
  /// device, the bots' ([extraKnown]).
  factory RemoteDeal.fromBatch(List<GameEvent> batch, {Map<int, List<PlayingCard>> extraKnown = const {}}) {
    final start = batch.isEmpty ? null : batch.first;
    if (start is! HandStarted) throw MirrorMismatch('A hand starts with HandStarted');
    final known = <int, List<PlayingCard>>{...extraKnown};
    final board = <PlayingCard>[];
    final revealed = <int, List<PlayingCard>>{};
    for (final e in batch) {
      switch (e) {
        case HoleCardsDealt():
          known.addAll(e.cards);
        case BoardDealt():
          board.addAll(e.cards);
        case HandsRevealed():
          revealed.addAll(e.cards);
        default:
          break;
      }
    }
    return RemoteDeal(
      handNumber: start.handNumber,
      buttonSeat: start.buttonSeat,
      stacks: start.stacks,
      known: known,
      board: board,
      revealed: revealed,
      events: List.unmodifiable(batch),
    );
  }

  final int handNumber;
  final int buttonSeat;

  /// Everyone's stack when the hand started, by seat.
  final List<int> stacks;

  /// The hole cards this device knows, by seat.
  final Map<int, List<PlayingCard>> known;

  /// Board cards and shown hands already in the first batch.
  final List<PlayingCard> board;
  final Map<int, List<PlayingCard>> revealed;

  /// The server's first batch, to check the mirror against (none: no check).
  final List<GameEvent> events;

  /// A mirror of the hand, with its first events already checked against
  /// the server's and drained. Throws [MirrorMismatch] if they differ.
  PokerHand build({
    required int smallBlind,
    required int bigBlind,
    int ante = 0,
    RaiseRule raiseRule = RaiseRule.standard,
  }) {
    final PokerHand hand;
    try {
      hand = PokerHand.mirror(
        stacks: stacks,
        buttonSeat: buttonSeat,
        smallBlind: smallBlind,
        bigBlind: bigBlind,
        ante: ante,
        handNumber: handNumber,
        raiseRule: raiseRule,
        known: known,
        board: board,
        revealed: revealed,
      );
    } on ArgumentError catch (e) {
      throw MirrorMismatch('$e');
    } on StateError catch (e) {
      throw MirrorMismatch('$e');
    }
    final mine = hand.drainEvents();
    if (events.isNotEmpty && !sameEvents(mine, events)) throw MirrorMismatch('The deal differs');
    return hand;
  }
}

/// Plays one batch of the server's events on [mirror]: the action that
/// starts it, and everything that followed (the board dealt, hands shown,
/// pots paid). Returns the mirror's own events, after checking they are the
/// server's; throws [MirrorMismatch] if they aren't, or the move is refused.
List<GameEvent> applyBatch(PokerHand mirror, List<GameEvent> batch) {
  final first = batch.isEmpty ? null : batch.first;
  if (first is! ActionTaken) throw MirrorMismatch('A batch starts with an action');
  if (mirror.isOver || mirror.toAct != first.seat) throw MirrorMismatch('Seat ${first.seat} is not due to act');
  mirror.drainEvents();
  try {
    // The cards first: the action may deal or show them.
    for (final e in batch) {
      switch (e) {
        case BoardDealt():
          mirror.supplyBoard(e.cards);
        case HandsRevealed():
          mirror.supplyReveal(e.cards);
        default:
          break;
      }
    }
    mirror.act(actionOf(first));
  } on ArgumentError catch (e) {
    throw MirrorMismatch('$e');
  } on StateError catch (e) {
    throw MirrorMismatch('$e');
  }
  final mine = mirror.drainEvents();
  if (!sameEvents(mine, batch)) throw MirrorMismatch('The events differ');
  return mine;
}
