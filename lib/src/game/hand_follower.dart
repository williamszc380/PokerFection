import 'dart:async';

import '../bots/bot.dart';
import '../engine/events.dart';
import '../engine/poker_hand.dart';
import '../gto/postflop/postflop_tracker.dart';
import '../gto/preflop/preflop_tracker.dart';
import '../gto/solve_queue.dart';
import '../gto/spot_strategy.dart';
import '../online/mirror.dart';

/// GTO's answer for one of the user's decisions: [spot], or none ([none]
/// says why, when known).
typedef GtoAnswer = ({SpotStrategy? spot, NoAnswer? none});

/// The trackers that follow a hand for its answers (see TableSession
/// .trackersFor).
typedef HandTrackers = ({PreflopTracker? preflop, PostflopTracker? postflop});

/// Follows one hand behind the table on the device, for its GTO answers,
/// so the table never waits for a solve.
///
/// It holds a copy of the table's hand (every hole card known), the hand's
/// trackers, and one job chain: each action the table plays is applied to
/// the copy in order, and the trackers do what they need at each step (the
/// user's subgame at their turn before the flop, each street as it
/// begins), waiting for the solves that the next step's inputs come from.
/// So every solve starts from the same finished solves, in the same order,
/// whether the table was quick or slow: a move made before its answer gets
/// the grade it would have got had the table waited.
///
/// At most two are kept: the hand on the table and, while it still has
/// answers to give, the one before.
class HandFollower {
  /// Follows [table] from [deal], its first batch of events; [owner] is
  /// the hand's claim on solves (see SolveOwner).
  HandFollower({required PokerHand table, required List<GameEvent> deal, required this.owner, this.heroSeat = 0})
      : hand = RemoteDeal.fromBatch(
          deal,
          extraKnown: {for (var seat = 0; seat < table.playerCount; seat++) seat: table.holeCards(seat)},
        ).build(
          smallBlind: table.smallBlind,
          bigBlind: table.bigBlind,
          ante: table.ante,
          raiseRule: table.raiseRule,
        );

  /// The hand's solves: claimed while a bot waits, or while the user asks
  /// to see an answer, and finished once the hand is over.
  final SolveOwner owner;

  /// The user's seat.
  final int heroSeat;

  /// The copy of the table's hand, as far as the jobs have got.
  final PokerHand hand;

  /// The hand's trackers, once its whole game is solved ([start]).
  PreflopTracker? preflop;
  PostflopTracker? postflop;

  /// Why no more answers come in this hand, if none do: its whole game
  /// couldn't be solved, or a step failed (each answer starts from the
  /// ones before, so after a failure it would be wrong rather than missing).
  NoAnswer? failed;

  /// Nothing more runs (the table is two hands on, or closed): set by
  /// whoever follows the table, which also drops the [owner]'s solves.
  bool abandoned = false;

  /// Answers asked for and not given yet.
  int pendingAnswers = 0;

  /// Called when the last answer asked for has been given.
  void Function()? onIdle;

  /// Whether the copy has begun the streets after the flop (the trackers
  /// have taken the preflop ranges they start from).
  bool _pastPreflop = false;

  Future<void> _tail = Future.value();

  /// Completes once every job queued so far is done.
  Future<void> get tail => _tail;

  /// Runs [run] once the jobs before it are done (unless the follower is
  /// [abandoned] by then). A job that throws ends the hand's answers.
  void job(Future<void> Function() run) {
    _tail = _tail.then((_) async {
      if (abandoned) return;
      try {
        await run();
      } on Object {
        failed ??= NoAnswer.solveFailed;
      }
    });
  }

  /// The first job: [trackers] makes the hand's trackers, once its whole
  /// game is solved (null: nothing needs them), then the dealt state is
  /// tracked (the user may act first, or the blinds may have put everyone
  /// all-in). If it fails, the hand gets no answers, and the bots keep to
  /// the solved lines without them (see TableSession.decisionOn).
  void start(Future<HandTrackers?> Function() trackers) {
    job(() async {
      final HandTrackers? t;
      try {
        t = await trackers();
      } on Object {
        failed ??= NoAnswer.solveFailed;
        return;
      }
      preflop = t?.preflop;
      postflop = t?.postflop;
      await _track();
    });
  }

  /// The table's next batch of events (an action, and what it led to):
  /// applied to the copy, then tracked as the table used to track it, but
  /// waited for here: at the user's turn before the flop, their subgame
  /// (the bots' replies come from it, as does the user's answer); when a
  /// street begins, the street before is narrowed (once it is solved) and
  /// this one's solve starts, if it is needed.
  void step(List<GameEvent> batch) {
    job(() async {
      applyBatch(hand, batch);
      if (failed == null) await _track();
    });
  }

  Future<void> _track() async {
    final pre = preflop;
    if (pre != null && hand.street == Street.preflop && hand.toAct == heroSeat && !hand.isOver) {
      await pre.prepare(hand);
    }
    await postflop?.update(hand);
    if (hand.street != Street.preflop) _pastPreflop = true;
  }

  /// GTO's answer for the user's decision that the jobs queued so far lead
  /// to, once the chain gets there: [done] gets it with the copy, standing
  /// at that decision (read it there and then: the chain moves on after).
  void answer(void Function(GtoAnswer answer, PokerHand at) done) {
    pendingAnswers++;
    job(() async {
      try {
        done(await _answer(), hand);
      } finally {
        pendingAnswers--;
        if (pendingAnswers == 0) onIdle?.call();
      }
    });
  }

  Future<GtoAnswer> _answer() async {
    final h = hand;
    if (h.isOver || h.toAct != heroSeat) return (spot: null, none: null);
    if (failed case final none?) return (spot: null, none: none);
    final pre = preflop;
    if (pre == null) return (spot: null, none: null);
    if (h.street == Street.preflop) {
      final spot = pre.spotFor(h);
      return (spot: spot, none: spot == null ? pre.unavailable : null);
    }
    final post = postflop;
    if (post == null) return (spot: null, none: pre.unavailable);
    try {
      await post.ready;
    } on Object {
      return (spot: null, none: NoAnswer.solveFailed);
    }
    final spot = post.spotFor(h);
    return (spot: spot, none: spot == null ? (post.unavailable ?? pre.unavailable) : null);
  }

  /// What a bot about to act in [seat] (with [style]) would play from:
  /// the copy caught up with the table (the subgame its reply comes from
  /// included), and after the flop, for a GTO bot, its street solved.
  Future<void> readyFor(int seat, BotStyle? style) async {
    await _tail;
    if (abandoned || failed != null) return;
    if (hand.street != Street.preflop && style == BotStyle.gto) await postflop?.ready;
  }

  /// Lets go of the solved subgames that the answers still to come don't
  /// read (they take memory, up to ~100 MB each at 8 players). An answer
  /// before the flop, and the streets' ranges, start from every subgame
  /// before it, so they all stay until the copy has begun the flop; after
  /// that only the streets' solves are read.
  void trimForAnswers() {
    if (_pastPreflop) preflop?.dropSubgames();
  }
}
