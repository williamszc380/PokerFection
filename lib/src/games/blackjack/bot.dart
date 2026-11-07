/// Computer players at three levels, each a fixed strategy so its cost can
/// be measured exactly ([houseEdgeFollowing]).
library;

import 'action.dart';
import 'cards.dart';
import 'round.dart';
import 'rules.dart';
import 'solver.dart';
import 'strategy.dart';

/// How well a bot plays.
enum BotLevel {
  /// A typical beginner ([BeginnerPolicy]): never risks busting, doubles
  /// any 10 or 11 (even against a ten or an ace), splits only aces and
  /// eights, takes even money and insures good hands.
  easy,

  /// Simplified basic strategy ([SimplePolicy]): the main rules without
  /// soft doubling or the close calls; never takes insurance.
  medium,

  /// Full basic strategy for the table's rules ([BasicStrategyChart]).
  hard,
}

/// A typical beginner's play, used by the Easy bot.
///
/// Wizard of Odds ("Blackjack basics",
/// https://wizardofodds.com/games/blackjack/basics/) puts the "never
/// bust" strategy (never hitting hard 12 or more, otherwise correct) at a
/// 3.91% house edge; this beginner also doubles 10 and 11 against
/// anything, never doubles soft hands or 9s, and splits nothing but aces
/// and eights, so it does a little worse.
class BeginnerPolicy implements PlayPolicy {
  /// The beginner.
  const BeginnerPolicy();

  @override
  BlackjackAction choose(HandTotal total, int cardCount, int pairRank, int upcard, int allowed) {
    bool can(BlackjackAction a) => allowed & a.bit != 0;
    if (can(BlackjackAction.split) && (pairRank == aceIndex || pairRank == 7 /* eights */ )) {
      return BlackjackAction.split;
    }
    if (!total.soft && (total.value == 10 || total.value == 11) && can(BlackjackAction.double)) {
      return BlackjackAction.double;
    }
    if (total.soft) return total.value <= 17 && can(BlackjackAction.hit) ? BlackjackAction.hit : BlackjackAction.stand;
    return total.value <= 11 && can(BlackjackAction.hit) ? BlackjackAction.hit : BlackjackAction.stand;
  }
}

/// Simplified basic strategy, used by the Medium bot: right for the
/// common hands, but it never doubles soft hands, never splits fours,
/// surrenders only 16 against a ten, and ignores the rule-specific
/// details (soft 17, double after split).
class SimplePolicy implements PlayPolicy {
  /// The simplified strategy.
  const SimplePolicy();

  @override
  BlackjackAction choose(HandTotal total, int cardCount, int pairRank, int upcard, int allowed) {
    bool can(BlackjackAction a) => allowed & a.bit != 0;
    // Dealer upcard as points with the ace high: 2..11.
    final up = upcard == aceIndex ? 11 : rankPoints(upcard);
    final t = total.value;
    if (can(BlackjackAction.split) && pairRank >= 0) {
      final p = pairRank == aceIndex ? 11 : rankPoints(pairRank);
      final split = switch (p) {
        11 || 8 => true,
        2 || 3 || 7 => up <= 7,
        6 => up <= 6,
        9 => up <= 9 && up != 7,
        _ => false,
      };
      if (split) return BlackjackAction.split;
    }
    if (!total.soft && t == 16 && up == 10 && can(BlackjackAction.surrender)) return BlackjackAction.surrender;
    if (total.soft) {
      if (t >= 19) return BlackjackAction.stand;
      if (t == 18) return up <= 8 ? BlackjackAction.stand : BlackjackAction.hit;
      return BlackjackAction.hit;
    }
    if (t == 11 && up <= 10 && can(BlackjackAction.double)) return BlackjackAction.double;
    if (t == 10 && up <= 9 && can(BlackjackAction.double)) return BlackjackAction.double;
    if (t >= 17) return BlackjackAction.stand;
    if (t >= 13) return up <= 6 ? BlackjackAction.stand : BlackjackAction.hit;
    if (t == 12) return up >= 4 && up <= 6 ? BlackjackAction.stand : BlackjackAction.hit;
    return BlackjackAction.hit;
  }
}

/// A computer player. Deterministic: the same view always gets the same
/// action.
class BlackjackBot {
  /// A bot at [level]. [chart]: the basic strategy chart the Hard bot
  /// plays, for the table's rules; without one it comes from
  /// [BasicStrategyChart.forRules] (built on first use, about a second).
  /// The app's bot job passes the chart its game built once, because each
  /// job starts with empty caches.
  BlackjackBot(this.level, {this.chart});

  /// How well it plays.
  final BotLevel level;

  /// The Hard bot's chart, or null: the cached one.
  final BasicStrategyChart? chart;

  BasicStrategyChart _chartFor(BlackjackRules rules) {
    final given = chart;
    if (given == null) return BasicStrategyChart.forRules(rules);
    if (given.rules.strategyKey != rules.strategyKey) {
      throw ArgumentError('the chart is for ${given.rules}, not $rules');
    }
    return given;
  }

  /// The strategy it plays hands with, for [rules].
  PlayPolicy policyFor(BlackjackRules rules) => switch (level) {
    BotLevel.easy => const BeginnerPolicy(),
    BotLevel.medium => const SimplePolicy(),
    BotLevel.hard => _chartFor(rules),
  };

  /// Picks one of [BlackjackView.legalActions] for the seat's turn.
  BlackjackAction chooseAction(BlackjackView view) {
    final legal = view.legalActions;
    if (legal.isEmpty) throw StateError('not this seat\'s turn');
    if (legal.length == 1) return legal.first;
    final seat = view.seats[view.seat];
    final hand = view.turn!.hand;
    final h = seat.hands[hand];
    final up = view.dealerUpcard.rank;
    switch (view.phase) {
      case RoundPhase.insurance:
        // Easy takes even money and insures a good hand; the others
        // never insure (it only pays with a big count of tens).
        if (level == BotLevel.easy && (seat.hasBlackjack || h.total.value >= 19)) return BlackjackAction.insurance;
        return BlackjackAction.noInsurance;
      case RoundPhase.earlySurrender:
        if (level != BotLevel.hard) return BlackjackAction.keepPlaying;
        final spot = HandSpot.ofCards(h.cards);
        final a = _chartFor(view.rules).decide(
          total: spot.total,
          cardCount: 2,
          upcard: up,
          pairRank: spot.pairRank,
          canDouble: true,
          canSplit: view.rules.canSplit,
          canSurrender: true,
        );
        return a == BlackjackAction.surrender ? BlackjackAction.surrender : BlackjackAction.keepPlaying;
      case RoundPhase.playing:
        var allowed = 0;
        for (final a in legal) {
          allowed |= a.bit;
        }
        final cards = h.cards;
        final pairRank = h.isPair ? cards[0].rank : -1;
        final a = policyFor(view.rules).choose(h.total, cards.length, pairRank, up, allowed);
        return legal.contains(a) ? a : BlackjackAction.stand;
      case RoundPhase.over:
        throw StateError('the round is over');
    }
  }
}
