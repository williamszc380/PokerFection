/// The coach: the exact expected value of every legal action, in two
/// knowledge modes, the best action, reasons, and grades.
///
/// Two modes, because they teach two different things:
/// - FRESH: the unseen cards are a full shoe minus only this round's
///   visible cards. This is what basic strategy assumes, so FRESH's best
///   play is basic strategy for this exact hand.
/// - SEEN: the unseen cards are the shoe minus every card seen since the
///   shuffle. This is perfect play with all public information, which
///   includes everything card counting captures (and more).
///
/// Values are in bets (of the hand's own bet). In a hole card game the
/// dealer has peeked by the time a player plays, so play values are given
/// "no dealer blackjack"; without a hole card they include the dealer's
/// later blackjack. Insurance and early-surrender decisions come before
/// the peek, so their values count the dealer's blackjack.
library;

import 'dart:math' as math;

import 'action.dart';
import 'cards.dart';
import 'count.dart';
import 'round.dart';
import 'rules.dart';
import 'solver.dart';
import 'strategy.dart';

/// What the coach knows about the unseen cards.
enum KnowledgeMode {
  /// A full shoe minus this round's visible cards (basic strategy).
  fresh,

  /// The shoe minus every card seen since the shuffle (perfect play with
  /// public information; what card counting approximates).
  seen,
}

/// A short, machine-readable reason, which the app turns into a one-line
/// explanation in the player's language. The fields say which numbers
/// to put in it.
enum ReasonKind {
  /// Hard 17 or more: stand. ("17 or more: stand")
  standMadeHand,

  /// 11 or less: a hit can't bust. ("11 or less: hit, you can't bust")
  cantBust,

  /// A stiff (12-16) against a dealer 2-6: the dealer busts often, so
  /// stand. ("Dealer's 6 busts often: stand")
  dealerBustsOften,

  /// A stiff against 7 to ace: the dealer will usually make 17 or more,
  /// so hit. ("Dealer's 10 usually makes 17+: hit")
  dealerStrong,

  /// Doubling this total against this upcard wins the most. ("11 vs 6:
  /// double")
  doubleStrong,

  /// Doubling this soft hand against this upcard wins the most. ("Soft 17
  /// vs 4: double")
  doubleSoft,

  /// Always split aces.
  splitAces,

  /// Always split eights: 16 is the worst total.
  splitEights,

  /// Never split tens: 20 is too good to break up.
  neverSplitTens,

  /// Never split fives: 5-5 is a 10, double or hit it.
  neverSplitFives,

  /// Split against a weak upcard: two hands against a likely bust.
  splitVsWeak,

  /// Don't split against a strong upcard.
  noSplitVsStrong,

  /// This hand wins so rarely that giving up half the bet loses less.
  surrenderSaves,

  /// A soft hand: a hit can't bust it.
  softCantBust,

  /// A good soft total: stand.
  softStand,

  /// Insurance (or even money) loses unless more than a third of the
  /// unseen cards are tens. ("Insurance only pays when the count is high")
  insuranceBad,

  /// More than a third of the unseen cards are tens: insurance pays now.
  insuranceGood,

  /// The cards seen since the shuffle change the best play from basic
  /// strategy's. ("The count is high: stand on 16 vs 10 (basic strategy
  /// hits)") [CoachReason.trueCount], [CoachReason.action] (SEEN's play)
  /// and [CoachReason.basicAction] (FRESH's) are set.
  countDeviation,

  /// The exact cards in this hand change the play from the chart's (for
  /// example a three-card 16 against a 10 stands). [CoachReason.action]
  /// is FRESH's play and [CoachReason.basicAction] the chart's.
  exactCardsPlay,

  /// A hit risks busting: [CoachReason.chance] is the chance the next card
  /// busts the hand.
  bustRisk,

  /// Doubling or splitting here loses money against a strong upcard.
  tooRisky,

  /// A stiff against a 2 or 3 (usually 12): those upcards bust less often
  /// than a 4, 5 or 6, not often enough to stand. ("Dealer's 3 busts less
  /// often than you'd think: hit 12")
  dealerBustsLess,

  /// Another play gives up less: [CoachReason.action] is the best play
  /// (FRESH). Given when nothing more specific explains why this play
  /// costs 0.01 bets or more. ("Hit is better here")
  betterPlay,
}

/// One reason with the numbers that go with it.
class CoachReason {
  /// A reason of [kind] about the hand's [total] (soft or not) against
  /// [upcard] (rank index).
  const CoachReason(
    this.kind, {
    required this.total,
    required this.soft,
    required this.upcard,
    this.pairRank = -1,
    this.trueCount,
    this.action,
    this.basicAction,
    this.chance,
  });

  /// What kind of reason.
  final ReasonKind kind;

  /// The player's total.
  final int total;

  /// The total is soft.
  final bool soft;

  /// The dealer's upcard (rank index; [rankName] gives "A", "2".."T").
  final int upcard;

  /// The pair's rank index, or -1.
  final int pairRank;

  /// The Hi-Lo true count, for count reasons.
  final double? trueCount;

  /// The recommended action, for deviation reasons and
  /// [ReasonKind.betterPlay].
  final BlackjackAction? action;

  /// Basic strategy's action, for deviation reasons.
  final BlackjackAction? basicAction;

  /// A probability (0-1), for [ReasonKind.bustRisk].
  final double? chance;

  @override
  String toString() =>
      '${kind.name}(${soft ? 's' : ''}$total v ${rankName(upcard)}'
      '${trueCount == null ? '' : ', tc ${trueCount!.toStringAsFixed(1)}'}'
      '${action == null ? '' : ', ${action!.name}'}${basicAction == null ? '' : ' not ${basicAction!.name}'}'
      '${chance == null ? '' : ', ${(chance! * 100).toStringAsFixed(0)}%'})';
}

/// The coach's numbers for one legal action.
class ActionAnalysis {
  /// See the fields.
  const ActionAnalysis({
    required this.action,
    required this.evFresh,
    required this.evSeen,
    required this.lostFresh,
    required this.lostSeen,
    required this.reasons,
  });

  /// The action.
  final BlackjackAction action;

  /// Expected value in bets with FRESH knowledge.
  final double evFresh;

  /// Expected value in bets with SEEN knowledge.
  final double evSeen;

  /// Bets given up compared with FRESH's best (0 for the best).
  final double lostFresh;

  /// Bets given up compared with SEEN's best (0 for the best).
  final double lostSeen;

  /// Short facts about this action.
  final List<CoachReason> reasons;

  /// The value in [mode].
  double ev(KnowledgeMode mode) => mode == KnowledgeMode.fresh ? evFresh : evSeen;

  /// The loss against the best in [mode].
  double lost(KnowledgeMode mode) => mode == KnowledgeMode.fresh ? lostFresh : lostSeen;

  @override
  String toString() =>
      '${action.name.padRight(11)} fresh ${evFresh.toStringAsFixed(4)}  seen ${evSeen.toStringAsFixed(4)}  '
      '${reasons.join(' ')}';
}

/// The coach's answer for one decision.
class BlackjackAnalysis {
  /// See the fields.
  const BlackjackAnalysis({
    required this.phase,
    required this.actions,
    required this.bestFresh,
    required this.bestSeen,
    required this.chartAction,
    required this.reasons,
    required this.count,
    required this.elapsedMicros,
  });

  /// The phase the decision is in.
  final RoundPhase phase;

  /// Every legal action, best (FRESH) first.
  final List<ActionAnalysis> actions;

  /// The best action with FRESH knowledge: basic strategy for this exact
  /// hand.
  final BlackjackAction bestFresh;

  /// The best action with SEEN knowledge: what a perfect counter plays.
  final BlackjackAction bestSeen;

  /// The basic strategy chart's play (total-dependent; can differ from
  /// [bestFresh] in rare composition-dependent spots). Null outside the
  /// playing phase except for early surrender.
  final BlackjackAction? chartAction;

  /// FRESH and SEEN disagree: the cards seen since the shuffle change the
  /// play.
  bool get differs => bestFresh != bestSeen;

  /// Why the best plays are best.
  final List<CoachReason> reasons;

  /// The Hi-Lo count when the decision was taken.
  final HiLoCount count;

  /// Time taken, in microseconds.
  final int elapsedMicros;

  /// The best action in [mode].
  BlackjackAction best(KnowledgeMode mode) => mode == KnowledgeMode.fresh ? bestFresh : bestSeen;

  /// The numbers for [action] (which must be legal).
  ActionAnalysis of(BlackjackAction action) => actions.firstWhere((a) => a.action == action);
}

/// How good the action played was.
enum MoveGrade {
  /// The best action, or within 0.001 bets of it (a tie, given the
  /// precision of the split method).
  best,

  /// Gives up less than 0.01 bets: under 1% of the bet, about twice the
  /// whole house edge of a good game, on one hand. Close calls such as
  /// 16 against a 10 or 12 against a 4 (hit or stand) land here.
  good,

  /// Gives up 0.01 to 0.03 bets: a real but small error, such as standing
  /// on 12 against a 3 or hitting 13 against a 2.
  inaccuracy,

  /// Gives up 0.03 to 0.10 bets: taking insurance without a count
  /// (about 0.04 in six decks), standing on 16 against a 7.
  mistake,

  /// Gives up 0.10 bets or more: not doubling 11 against a 6, splitting
  /// tens, standing on 11.
  blunder;

  /// Losses up to this many bets grade [best].
  static const double bestLine = 0.001;

  /// Losses under this many bets grade [good] (or [best]).
  static const double goodLine = 0.01;
}

/// A graded action.
class Grading {
  /// See the fields.
  const Grading({required this.action, required this.evLost, required this.grade});

  /// The action played.
  final BlackjackAction action;

  /// Bets given up compared with the best action.
  final double evLost;

  /// The grade.
  final MoveGrade grade;
}

/// Rates every legal action from a [BlackjackView]. Stateless apart from
/// the basic strategy chart cache, so one coach can serve every seat.
///
/// An analysis takes about 2 ms on average natively and 4 ms in
/// JavaScript (median 0.3 ms and 1 ms), but small pairs (2-2, 3-3, 4-4)
/// against a 2, 3 or an ace in shoe games are much slower, because both
/// modes value resplits to four hands: 99.9th percentile about 80-90 ms
/// natively and 140 ms in JavaScript, worst about 140 ms and 220 ms (6
/// decks, several thousand decisions; see tool/games/blackjack_web_bench.dart
/// and `--coach-timing` in tool/games/blackjack_match.dart). Run it in the
/// background worker, never on the UI thread.
/// Without a `chart`, the first analysis for a rule set also builds its
/// chart (about 0.9 s natively, 1.6 s in JavaScript). The app builds the
/// chart once per game in its own job and passes it in, since each job
/// starts in a fresh isolate or worker with empty caches.
class BlackjackCoach {
  /// A coach.
  const BlackjackCoach();

  /// Analyzes the decision in [view] (it must be the viewer's turn).
  /// [chart] is the basic strategy chart for the view's rules (any chart
  /// with the same strategy key); without one it comes from
  /// [BasicStrategyChart.forRules], built on first use.
  BlackjackAnalysis analyze(BlackjackView view, {BasicStrategyChart? chart}) {
    final watch = Stopwatch()..start();
    final legal = view.legalActions;
    if (legal.isEmpty) throw StateError('not this seat\'s turn');
    final rules = view.rules;
    final chartObj = _chartFor(rules, chart);
    final seat = view.seats[view.seat];
    final handIndex = view.turn!.hand;
    final hand = seat.hands[handIndex];
    final spot = HandSpot.ofCards(
      hand.cards,
      splitHand: hand.fromSplit,
      splitAces: hand.splitAces,
      handsAtSeat: seat.hands.length,
      originalHand: handIndex == 0,
    );
    final up = view.dealerUpcard.rank;
    final freshCalc = EvCalculator(rules, view.unseenFresh, up);
    // Near the end of a shoe the unseen cards may not last the round; the
    // discards then come back (see BlackjackView.seenMayRunOut), and the
    // full shoe minus the table's cards is the best model of what's next.
    final seenComp = view.seenMayRunOut ? view.unseenFresh : view.unseenSeen;
    final sameKnowledge = seenComp == view.unseenFresh;
    final seenCalc = sameKnowledge ? freshCalc : EvCalculator(rules, seenComp, up);

    final freshValues = _values(view.phase, legal, freshCalc, spot, rules, up);
    final seenValues = sameKnowledge ? freshValues : _values(view.phase, legal, seenCalc, spot, rules, up);
    // Never report a value that isn't a number (it would grade as an
    // infinite loss): FRESH's value stands in.
    seenValues.updateAll((a, v) => v.isFinite ? v : freshValues[a]!);

    BlackjackAction bestOf(Map<BlackjackAction, double> v) {
      var best = legal.first;
      for (final a in legal) {
        if (v[a]! > v[best]! + 1e-12) best = a;
      }
      return best;
    }

    final bestFresh = bestOf(freshValues);
    final bestSeen = bestOf(seenValues);

    BlackjackAction? chartPlay;
    if (view.phase == RoundPhase.playing) {
      chartPlay = chartObj.decide(
        total: spot.total,
        cardCount: spot.cardCount,
        upcard: up,
        pairRank: spot.pairRank,
        canDouble: legal.contains(BlackjackAction.double),
        canSplit: legal.contains(BlackjackAction.split),
        canSurrender: legal.contains(BlackjackAction.surrender),
      );
    } else if (view.phase == RoundPhase.earlySurrender) {
      final a = chartObj.decide(
        total: spot.total,
        cardCount: 2,
        upcard: up,
        pairRank: spot.pairRank,
        canDouble: true,
        canSplit: rules.canSplit,
        canSurrender: true,
      );
      chartPlay = a == BlackjackAction.surrender ? BlackjackAction.surrender : BlackjackAction.keepPlaying;
    } else if (view.phase == RoundPhase.insurance) {
      chartPlay = BlackjackAction.noInsurance;
    }

    final count = view.count;
    final unseen = view.unseenFresh;
    final lostFresh = {for (final a in legal) a: freshValues[bestFresh]! - freshValues[a]!};
    final actions = [
      for (final a in legal)
        ActionAnalysis(
          action: a,
          evFresh: freshValues[a]!,
          evSeen: seenValues[a]!,
          lostFresh: freshValues[bestFresh]! - freshValues[a]!,
          lostSeen: seenValues[bestSeen]! - seenValues[a]!,
          reasons: _actionReasons(a, spot, up, unseen, seenCalc, lostFresh, bestFresh),
        ),
    ]..sort((x, y) => y.evFresh.compareTo(x.evFresh));

    final reasons = <CoachReason>[..._actionReasons(bestFresh, spot, up, unseen, seenCalc, lostFresh, bestFresh)];
    final t = spot.total;
    if (bestFresh != bestSeen) {
      reasons.add(
        CoachReason(
          ReasonKind.countDeviation,
          total: t.value,
          soft: t.soft,
          upcard: up,
          pairRank: spot.pairRank,
          trueCount: count.trueCount,
          action: bestSeen,
          basicAction: bestFresh,
        ),
      );
    }
    if (chartPlay != null && chartPlay != bestFresh && legal.contains(chartPlay)) {
      reasons.add(
        CoachReason(
          ReasonKind.exactCardsPlay,
          total: t.value,
          soft: t.soft,
          upcard: up,
          pairRank: spot.pairRank,
          action: bestFresh,
          basicAction: chartPlay,
        ),
      );
    }
    return BlackjackAnalysis(
      phase: view.phase,
      actions: actions,
      bestFresh: bestFresh,
      bestSeen: bestSeen,
      chartAction: chartPlay,
      reasons: reasons,
      count: count,
      elapsedMicros: watch.elapsedMicroseconds,
    );
  }

  /// [chart] if given (it must fit [rules]), else the cached one.
  static BasicStrategyChart _chartFor(BlackjackRules rules, BasicStrategyChart? chart) {
    if (chart == null) return BasicStrategyChart.forRules(rules);
    if (chart.rules.strategyKey != rules.strategyKey) {
      throw ArgumentError('the chart is for ${chart.rules}, not $rules');
    }
    return chart;
  }

  Map<BlackjackAction, double> _values(
    RoundPhase phase,
    List<BlackjackAction> legal,
    EvCalculator calc,
    HandSpot spot,
    BlackjackRules rules,
    int up,
  ) {
    switch (phase) {
      case RoundPhase.playing:
        final v = calc.playValues(spot);
        return {for (final a in legal) a: v[a] ?? double.negativeInfinity};
      case RoundPhase.insurance:
        // After the insurance offer, a late surrender is still possible
        // (not an early one: that offer came first).
        final upTenOrAce = up == aceIndex || up == tenIndex;
        final surrenderLater =
            rules.surrender == Surrender.late ||
            (rules.surrender == Surrender.early && !(rules.holeCard && upTenOrAce));
        final hand = calc.valueBeforePeek(spot, withSurrender: surrenderLater);
        return {BlackjackAction.insurance: hand + calc.insuranceValue(), BlackjackAction.noInsurance: hand};
      case RoundPhase.earlySurrender:
        // Keeping the hand against an ace leads to the insurance offer
        // (when the rules have one), so it is worth the better answer to
        // that offer: the hand plus the insurance bet when insurance pays.
        // That is exactly what the insurance phase's analysis shows one
        // step later. No late surrender follows an early one.
        var keep = calc.valueBeforePeek(spot, withSurrender: false);
        if (up == aceIndex && rules.insurance) keep += math.max(0, calc.insuranceValue());
        return {BlackjackAction.surrender: -0.5, BlackjackAction.keepPlaying: keep};
      case RoundPhase.over:
        return const {};
    }
  }

  /// Short facts about playing [a] with [spot] against [up].
  ///
  /// The facts are rules of thumb, so each one is checked against the
  /// exact numbers before it is given ([lost]: what each legal action
  /// gives up against [best], with FRESH knowledge, since the rules of
  /// thumb are basic strategy's):
  /// - a reason that says "do X" ([_advises]) is kept only if X is within
  ///   the Good line (gives up under 0.01 bets), and, when it is attached
  ///   to another action, only if X beats that action;
  /// - a reason that says "don't do X" ([_discourages]) is kept only if X
  ///   is not the best play;
  /// - an action that gives up 0.01 bets or more and has nothing left that
  ///   says why gets [ReasonKind.betterPlay].
  /// So a learner never reads advice that the coach's own numbers call a
  /// mistake.
  List<CoachReason> _actionReasons(
    BlackjackAction a,
    HandSpot spot,
    int up,
    Composition unseen,
    EvCalculator seenCalc,
    Map<BlackjackAction, double> lost,
    BlackjackAction best,
  ) {
    final t = spot.total;
    CoachReason reason(ReasonKind k, {double? chance, BlackjackAction? action}) => CoachReason(
      k,
      total: t.value,
      soft: t.soft,
      upcard: up,
      pairRank: spot.pairRank,
      chance: chance,
      action: action,
    );
    final raw = <CoachReason>[];
    void add(ReasonKind k, {double? chance}) => raw.add(reason(k, chance: chance));
    final weakUp = up >= 1 && up <= 5; // 2..6
    final stiff = !t.soft && t.value >= 12 && t.value <= 16;
    final good = lost[a]! < MoveGrade.goodLine;
    switch (a) {
      case BlackjackAction.stand:
        if (!t.soft && t.value >= 17) {
          add(ReasonKind.standMadeHand);
        } else if (stiff && weakUp) {
          add(good ? ReasonKind.dealerBustsOften : ReasonKind.dealerBustsLess);
        } else if (t.soft && t.value >= 18) {
          add(ReasonKind.softStand);
        } else if (stiff) {
          add(ReasonKind.dealerStrong);
        }
        if (spot.pairRank == tenIndex) add(ReasonKind.neverSplitTens);
      case BlackjackAction.hit:
        if (t.soft) {
          add(ReasonKind.softCantBust);
        } else if (t.value <= 11) {
          add(ReasonKind.cantBust);
        } else {
          if (stiff && !weakUp) add(ReasonKind.dealerStrong);
          if (stiff && weakUp && a == best) add(ReasonKind.dealerBustsLess);
          add(ReasonKind.bustRisk, chance: _bustChance(t.value, unseen));
        }
        if (spot.pairRank == 4) add(ReasonKind.neverSplitFives);
      case BlackjackAction.double:
        if (good) {
          add(t.soft ? ReasonKind.doubleSoft : ReasonKind.doubleStrong);
        } else if (!weakUp) {
          add(ReasonKind.tooRisky);
        }
        if (spot.pairRank == 4) add(ReasonKind.neverSplitFives);
      case BlackjackAction.split:
        switch (spot.pairRank) {
          case aceIndex:
            add(ReasonKind.splitAces);
          case 7:
            add(ReasonKind.splitEights);
          case tenIndex:
            add(ReasonKind.neverSplitTens);
          case 4:
            add(ReasonKind.neverSplitFives);
          default:
            add(weakUp ? ReasonKind.splitVsWeak : ReasonKind.noSplitVsStrong);
        }
      case BlackjackAction.surrender:
        add(ReasonKind.surrenderSaves);
      case BlackjackAction.insurance:
      case BlackjackAction.noInsurance:
        // About the count, so SEEN's tens decide; nothing to check.
        final tens = seenCalc.dealerBlackjackChance;
        add(tens > 1 / 3 ? ReasonKind.insuranceGood : ReasonKind.insuranceBad, chance: tens);
        return raw;
      case BlackjackAction.keepPlaying:
        break;
    }

    final out = <CoachReason>[];
    var explained = false; // something kept says why a is not the play
    for (final r in raw) {
      final x = _advises(r.kind);
      if (x != null) {
        final lx = lost[x];
        if (lx == null || lx >= MoveGrade.goodLine) continue;
        if (x != a) {
          if (lx >= lost[a]! - MoveGrade.bestLine) continue;
          explained = true;
        }
      }
      final d = _discourages(r.kind, a);
      if (d != null) {
        final ld = lost[d];
        if (ld != null && ld <= MoveGrade.bestLine) continue;
        if (d == a) explained = true;
      }
      out.add(r);
    }
    if (!good && !explained) out.add(reason(ReasonKind.betterPlay, action: best));
    return out;
  }

  /// The play a reason of [kind] tells the player to make, or null.
  static BlackjackAction? _advises(ReasonKind kind) => switch (kind) {
    ReasonKind.standMadeHand || ReasonKind.dealerBustsOften || ReasonKind.softStand => BlackjackAction.stand,
    ReasonKind.cantBust ||
    ReasonKind.softCantBust ||
    ReasonKind.dealerStrong ||
    ReasonKind.dealerBustsLess => BlackjackAction.hit,
    ReasonKind.doubleStrong || ReasonKind.doubleSoft => BlackjackAction.double,
    ReasonKind.splitAces || ReasonKind.splitEights || ReasonKind.splitVsWeak => BlackjackAction.split,
    ReasonKind.surrenderSaves => BlackjackAction.surrender,
    _ => null,
  };

  /// The play a reason of [kind], attached to [a], tells the player not
  /// to make, or null.
  static BlackjackAction? _discourages(ReasonKind kind, BlackjackAction a) => switch (kind) {
    ReasonKind.neverSplitTens || ReasonKind.neverSplitFives => BlackjackAction.split,
    ReasonKind.tooRisky || ReasonKind.noSplitVsStrong || ReasonKind.betterPlay => a,
    _ => null,
  };

  /// The chance that one more card busts a hard [total].
  static double _bustChance(int total, Composition unseen) {
    final n = unseen.total;
    if (n == 0) return 0;
    var bust = 0;
    for (var r = 0; r < rankCount; r++) {
      if (total + rankPoints(r) > 21) bust += unseen[r];
    }
    return bust / n;
  }

  /// Grades playing [action] against [analysis] in [mode] (FRESH by
  /// default: what a basic strategy learner is judged on).
  Grading grade(BlackjackAction action, BlackjackAnalysis analysis, {KnowledgeMode mode = KnowledgeMode.fresh}) {
    final lost = analysis.of(action).lost(mode);
    return Grading(action: action, evLost: lost, grade: gradeFor(lost));
  }

  /// The grade for giving up [evLost] bets (see [MoveGrade] for why the
  /// lines are where they are).
  static MoveGrade gradeFor(double evLost) {
    if (evLost <= MoveGrade.bestLine) return MoveGrade.best;
    if (evLost < MoveGrade.goodLine) return MoveGrade.good;
    if (evLost < 0.03) return MoveGrade.inaccuracy;
    if (evLost < 0.10) return MoveGrade.mistake;
    return MoveGrade.blunder;
  }
}
