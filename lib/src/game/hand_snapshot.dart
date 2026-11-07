/// What a GTO answer that comes after its move needs to know about the
/// decision it answers: which decision it was, and what the "why" of a
/// mistake reads there. Both are read from the hand as it stood at the
/// decision (on the device, its hand follower, which is still there when
/// the answer comes), never from the table, which may have moved on.
library;

import '../bots/preflop_ranking.dart';
import '../engine/actions.dart';
import '../engine/events.dart';
import '../engine/poker_hand.dart';
import '../gto/hand_read.dart';
import '../gto/postflop/postflop_tracker.dart';

/// Which decision of its hand [hand] is at: how many actions were taken
/// before it. The table and any copy of the hand at the same point agree on
/// it, so an answer worked out on a copy finds the move it grades.
int decisionIdOf(PokerHand hand) => hand.log.whereType<ActionTaken>().length;

/// What the "why" of a mistake is worked out from (see reasonFor): before
/// the flop, how good the user's starting hand is ([percentile]); after it,
/// how often the most dangerous opponent's range beats it ([read]); and the
/// pot odds when facing a bet ([odds]).
typedef WhyInputs = ({double? percentile, HandRead? read, double? odds});

/// The "why" inputs at the user's decision [at] (in [seat], the user's),
/// whose choices are [options]; after the flop, the opponents' ranges come
/// from [postflop], the tracker that follows [at]. Read when the decision is
/// graded, which may be a street or two after it was played.
WhyInputs whyInputs(PokerHand at, LegalActions options, PostflopTracker? postflop, {int seat = 0}) {
  final hole = at.holeCards(seat);
  final odds = options.canCall ? options.toCall / (options.pot + options.toCall) : null;
  if (at.street == Street.preflop) {
    return (percentile: preflopPercentile(hole[0], hole[1]), read: null, odds: odds);
  }
  HandRead? read;
  for (var other = 0; other < at.playerCount; other++) {
    if (other == seat || at.isFolded(other)) continue;
    final range = postflop?.currentRange(at, other);
    final r = range == null ? null : readHand(hole, at.board, range);
    if (r != null && (read == null || r.beaten > read.beaten)) read = r;
  }
  return (percentile: null, read: read, odds: odds);
}
