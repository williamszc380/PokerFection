import 'dart:math';

import '../engine/actions.dart';
import '../engine/events.dart';
import '../engine/poker_hand.dart';
import '../engine/rules.dart';
import '../online/protocol.dart';
import '../online/timing.dart';

/// One hand at an online table, as the server plays it: the engine with a
/// secure deck, every action's events kept in order (one batch per action,
/// the deal first), and the turns counted, so each move counts once, for
/// the turn it was made at.
class HandRunner {
  HandRunner({
    required List<int> stacks,
    required int button,
    required this.handNumber,
    required int ante,
    required RaiseRule raiseRule,
    required Random random,
    required Iterable<int> botSeats,
  }) : botSeats = Set.unmodifiable(botSeats),
       _total = stacks.fold(0, (sum, s) => sum + s),
       hand = PokerHand(
         stacks: stacks,
         buttonSeat: button,
         smallBlind: onlineSmallBlind,
         bigBlind: onlineBigBlind,
         ante: ante,
         handNumber: handNumber,
         raiseRule: raiseRule,
         random: random,
       ) {
    batches.add(hand.drainEvents());
    _checkChips();
  }

  final int handNumber;
  final PokerHand hand;

  /// Seats bots play in this hand (the host's device decides for them).
  final Set<int> botSeats;

  /// Every batch of events so far: the deal, then one per action.
  final List<List<GameEvent>> batches = [];

  /// The open turn (0 before the first).
  int turnId = 0;

  /// Moves refused at the open turn; after a few, more are ignored.
  int rejects = 0;
  static const maxRejects = 3;

  /// Batches already shown when the last turn opened.
  int _shown = 0;
  final int _total;

  bool get isOver => hand.isOver;

  /// Opens the next turn: who acts, their choices, and the time given to
  /// show the actions since the last turn (at most [OnlineTiming.maxWatch]).
  /// Null once the hand is over.
  Turn? openTurn({required int? Function(int seat) limitMs}) {
    if (hand.isOver) return null;
    final seat = hand.toAct!;
    final watch = playbackMs([for (final b in batches.skip(_shown)) ...b]);
    _shown = batches.length;
    turnId++;
    rejects = 0;
    return Turn.of(
      turnId,
      seat,
      hand.legalActions(),
      ms: limitMs(seat),
      waitMs: min(watch, OnlineTiming.maxWatch.inMilliseconds),
    );
  }

  /// What the server plays when time runs out: check if free, else fold.
  PlayerAction get autoAction => hand.legalActions().canCheck ? const PlayerAction.check() : const PlayerAction.fold();

  /// Plays [action] for the seat to act and returns its events. Throws an
  /// [ArgumentError] or a [StateError] (nothing changes) if it isn't
  /// allowed, including a fold when checking is free.
  List<GameEvent> act(PlayerAction action) {
    if (action.type == ActionType.fold && hand.legalActions().canCheck) {
      throw ArgumentError('Check is free: no fold');
    }
    hand.act(action);
    final batch = hand.drainEvents();
    batches.add(batch);
    _checkChips();
    return batch;
  }

  /// Chips are never made or lost: every stack plus what is in the middle
  /// always adds up to what the table started with.
  void _checkChips() {
    var chips = 0;
    for (var s = 0; s < hand.playerCount; s++) {
      chips += hand.stackOf(s);
    }
    if (!hand.isOver) chips += hand.potTotal;
    if (chips != _total) throw ChipsMissing(chips, _total);
  }
}

/// A bug: the chips at a table no longer add up.
class ChipsMissing extends Error {
  ChipsMissing(this.chips, this.expected);
  final int chips;
  final int expected;

  @override
  String toString() => 'Chips went missing: $chips, not $expected';
}
