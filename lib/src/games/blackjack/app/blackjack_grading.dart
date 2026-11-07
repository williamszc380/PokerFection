/// The coach's analysis as the kit shows and grades it: a [CoachAnswer] in
/// bets with the chart's play tagged "Basic strategy" (and, with the cards
/// seen, the count's play tagged "Count"), and the engine's own grading.
library;

import 'dart:math';

import '../../../gto/spot_strategy.dart' show DecisionGrade;
import '../../../kit/coach_answer.dart';
import '../../../kit/grading.dart';
import '../blackjack.dart';
import 'blackjack_analysis_codec.dart';
import 'blackjack_record.dart';

/// What the coach assumes about the cards, chosen at setup.
enum CoachMode {
  /// A full shoe minus this round's cards: basic strategy. The player is
  /// graded on the chart.
  fresh,

  /// Every card seen since the shuffle: what a card counter knows. The
  /// player is graded on the best play with those cards.
  seen;

  /// The mode named [name] (as saved in a record), Fresh shoe otherwise.
  static CoachMode byName(Object? name) => values.where((m) => m.name == name).firstOrNull ?? fresh;
}

/// Blackjack's grading: losses in bets, the engine's grade lines (0.001,
/// 0.01, 0.03, 0.10), and a score that halves about every 0.02 bets.
const blackjackScale = GradeScale(unit: ValueUnit.bets, cutoffs: [0.001, 0.01, 0.03, 0.10], scoreScale: 0.03);

/// The coach list for [result]: every legal action with its value in bets
/// in [mode], best first.
///
/// - The pick (tagged "Basic strategy") is the chart's play. With a fresh
///   shoe the exact best play counts as Best too ([CoachAnswer.alsoBest]);
///   when it differs from the chart, its row leads with the reason.
/// - With the cards seen, the count's best play is tagged 'count' when it
///   isn't the chart's, and its row leads with the count's reason ("True
///   +2.4: Stand (chart: Hit)", naming the chart's play, the pick): that is
///   the play the move is graded against.
/// - The insurance rows' "Tens 34%" is worked out from the values shown,
///   so with a fresh shoe it is the fresh shoe's tens: the count never
///   leaks into the mode that ignores it, and the words always agree with
///   which row is best.
CoachAnswer blackjackAnswer(BlackjackCoachResult result, CoachMode mode) {
  final a = result.analysis;
  final seen = mode == CoachMode.seen;
  String move(BlackjackAction action) => handMove(result.hand, action);
  final chart = a.chartAction != null && a.actions.any((x) => x.action == a.chartAction) ? a.chartAction! : a.bestFresh;
  // The engine words its count reason against the fresh shoe's best play,
  // which isn't always the chart's. Here it names the chart's play, and it
  // is only given when the count's play isn't the chart's own.
  final countReasons = [
    if (seen && a.bestSeen != chart)
      for (final r in a.reasons)
        if (r.kind == ReasonKind.countDeviation) reasonCode(_withBasicAction(r, chart)),
  ];
  final exactReasons = [
    for (final r in a.reasons)
      if (r.kind == ReasonKind.exactCardsPlay) reasonCode(r),
  ];
  final tens = _insuranceTens(a, seen);
  final lines = [
    for (final x in a.actions)
      CoachLine(
        move: move(x.action),
        value: seen ? x.evSeen : x.evFresh,
        reasons: [
          if (x.action == a.bestSeen) ...countReasons,
          if (x.action == a.bestFresh && chart != a.bestFresh) ...exactReasons,
          for (final r in x.reasons) reasonCode(tens == null ? r : _withTens(r, tens)),
        ],
        tag: seen && x.action == a.bestSeen && a.bestSeen != chart ? 'count' : null,
      ),
  ]..sort((x, y) => y.value.compareTo(x.value));
  return CoachAnswer(
    lines: lines,
    unit: ValueUnit.bets,
    pick: move(chart),
    alsoBest: seen ? const {} : {move(a.bestFresh)},
    detail: result,
  );
}

/// The grade of [played] against [answer] (made by [blackjackAnswer]),
/// with the engine's lines mapped one to one onto the app's grades:
/// - fresh shoe: the chart's play and the exact best are Best; anything
///   else loses what it gives up against the exact best;
/// - cards seen: everything is measured against the best play with the
///   cards seen (the "Count" row, or the chart's play when they agree);
///   the mark's best move then carries the 'count' tag.
/// Null when [played] isn't one of the answer's moves.
MoveMark? gradeBlackjack(CoachAnswer answer, String played, CoachMode mode) {
  final result = answer.detail;
  final parsed = parseHandMove(played);
  if (result is! BlackjackCoachResult || parsed == null || parsed.hand != result.hand) return null;
  final a = result.analysis;
  final x = a.actions.where((x) => x.action == parsed.action).firstOrNull;
  if (x == null) return null;
  final seen = mode == CoachMode.seen;
  final loss = seen
      ? max(0.0, x.lostSeen)
      : (played == answer.pick || x.action == a.bestFresh ? 0.0 : max(0.0, x.lostFresh));
  final best = seen ? handMove(result.hand, a.bestSeen) : answer.pick;
  return MoveMark(
    grade: DecisionGrade.values[BlackjackCoach.gradeFor(loss).index],
    loss: loss,
    score: blackjackScale.scoreFor(loss),
    played: played,
    best: best,
    reasons: answer.lineFor(played)?.reasons ?? const [],
    // The count's play when it isn't the chart's: the feedback then reads
    // "Count: Stand", as the coach row it was measured against is tagged.
    bestTag: best == answer.pick ? null : 'count',
  );
}

/// [r] compared with [basicAction] instead of its own.
CoachReason _withBasicAction(CoachReason r, BlackjackAction basicAction) => CoachReason(
  r.kind,
  total: r.total,
  soft: r.soft,
  upcard: r.upcard,
  pairRank: r.pairRank,
  trueCount: r.trueCount,
  action: r.action,
  basicAction: basicAction,
  chance: r.chance,
);

/// The dealer's chance of a ten under the ace as the insurance rows'
/// values in this mode imply it, or null outside the insurance offer.
///
/// Insuring (or taking even money) is worth exactly the insurance bet
/// more than declining, and that bet (half a bet at 2 to 1) is worth
/// 0.5 × (3p − 1) for a ten chance p, so p = (2 × difference + 1) / 3.
/// Reading it back from the values keeps the reason in the same shoe as
/// the numbers beside it.
double? _insuranceTens(BlackjackAnalysis a, bool seen) {
  if (a.phase != RoundPhase.insurance) return null;
  double? value(BlackjackAction action) {
    final x = a.actions.where((x) => x.action == action).firstOrNull;
    return x == null ? null : (seen ? x.evSeen : x.evFresh);
  }

  final insure = value(BlackjackAction.insurance), decline = value(BlackjackAction.noInsurance);
  if (insure == null || decline == null) return null;
  return (2 * (insure - decline) + 1) / 3;
}

/// [r] with its insurance words worked out from [tens]; other reasons as
/// they are.
CoachReason _withTens(CoachReason r, double tens) {
  if (r.kind != ReasonKind.insuranceGood && r.kind != ReasonKind.insuranceBad) return r;
  return CoachReason(
    tens > 1 / 3 ? ReasonKind.insuranceGood : ReasonKind.insuranceBad,
    total: r.total,
    soft: r.soft,
    upcard: r.upcard,
    pairRank: r.pairRank,
    chance: tens,
  );
}
