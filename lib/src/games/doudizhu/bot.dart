/// Computer players at three levels.
///
/// - Easy plays by rules of thumb (policy.dart): sensible, cooperative,
///   and beatable by someone who counts cards and plans ahead.
/// - Medium asks the coach with a small budget, so it looks a few hundred
///   deals ahead.
/// - Hard asks the coach with a bigger budget and solves endgames exactly.
///
/// A bot only ever sees its own seat's [DdzView], never other hands.
library;

import 'dart:math';

import 'coach.dart';
import 'game.dart';
import 'policy.dart';
import 'rules.dart';
import 'view.dart';

/// How strong a bot plays.
enum DdzLevel { easy, medium, hard }

/// A computer player. Give each bot its own [Random] (seeded in tests) so
/// games repeat exactly.
class DdzBot {
  DdzBot(this.level, {Random? random, DdzBudget? budget})
      : random = random ?? Random(),
        budget = budget ?? (level == DdzLevel.hard ? DdzBudget.hard : DdzBudget.medium);

  final DdzLevel level;
  final Random random;

  /// The coach's budget for Medium and Hard.
  final DdzBudget budget;

  static const _policy = HeuristicPolicy();

  /// The bot's move for [view]; it must be the bot's turn.
  DdzMove chooseMove(DdzView view) {
    if (!view.myTurn) throw StateError('Not seat ${view.seat}\'s turn');
    final legal = view.legalMoves;
    if (legal.length == 1) return legal.single;
    if (view.phase == DdzPhase.bidding) return _bid(view);
    if (level == DdzLevel.easy) {
      final p = _policy.choose(situationOf(view));
      return p == null ? const DdzPass() : DdzPlay(p);
    }
    final analysis = DdzCoach(budget: budget).analyze(view, random: random);
    return analysis.best.move;
  }

  DdzMove _bid(DdzView view) {
    final legal = view.legalMoves;
    if (level == DdzLevel.easy) {
      final want = _policy.bidFor(view.counts);
      return switch (view.rules.bidding) {
        BiddingStyle.points => legal.contains(DdzBid(want)) ? DdzBid(want) : const DdzBid(0),
        BiddingStyle.callRob => legal.first is DdzRob ? DdzRob(want >= 3) : DdzCall(want >= 1),
      };
    }
    // Medium and Hard: how often the hand wins as landlord, from play-outs.
    final deals = level == DdzLevel.hard ? 160 : 60;
    final est = const DdzCoach().estimateBidding(view, random, deals: deals);
    final w = est.landlordWin;
    final edge = est.landlordPointsPerStake - est.peasantPointsPerStake;
    switch (view.rules.bidding) {
      case BiddingStyle.points:
        final want = edge <= 0 ? 0 : (w >= 0.62 ? 3 : (w >= 0.55 ? 2 : 1));
        return legal.contains(DdzBid(want)) ? DdzBid(want) : const DdzBid(0);
      case BiddingStyle.callRob:
        if (legal.first is DdzRob) return DdzRob(edge > 0 && w >= 0.6);
        return DdzCall(edge > 0);
    }
  }
}

/// Plays one whole deal between three bots and returns the finished game
/// (thrown in when everyone passed and the rules say redeal). For tools and
/// tests.
DdzGame playOut(DdzGame game, List<DdzBot> bots, {void Function(DdzGame game, DdzMove move, Duration took)? onMove}) {
  while (game.phase == DdzPhase.bidding || game.phase == DdzPhase.playing) {
    final seat = game.toAct;
    final watch = Stopwatch()..start();
    final move = bots[seat].chooseMove(game.viewFor(seat));
    final took = watch.elapsed;
    game.act(move);
    onMove?.call(game, move, took);
  }
  return game;
}

