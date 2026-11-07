/// Computer players at three levels.
library;

import 'coach.dart';
import 'plays.dart';
import 'policy.dart';
import 'random.dart';
import 'state.dart';

/// How strong a bot plays.
enum BotLevel {
  /// The rule-of-thumb player with some randomness: sheds pairs and
  /// five-card hands, plays low, keeps its 2s, but plans nothing ahead.
  easy,

  /// Guesses the hidden hands a few hundred times and picks the move that
  /// does best in play-outs.
  medium,

  /// The coach at its full budget, with exact endgames.
  hard,
}

/// A computer player. It only ever sees a [BigTwoView], so it can't peek.
class BigTwoBot {
  /// A bot at [level]; [seed] makes its choices reproducible.
  BigTwoBot(this.level, {int seed = 1, CoachBudget? budget, HeuristicPolicy? playoutPolicy})
      : _rng = GameRandom(seed),
        _coach = BigTwoCoach(
          budget: budget ??
              switch (level) {
                BotLevel.hard => CoachBudget.standard,
                _ => CoachBudget.quick,
              },
          policy: playoutPolicy ?? const HeuristicPolicy(noise: 0.3),
        );

  /// How strong it plays.
  final BotLevel level;

  final GameRandom _rng;
  final BigTwoCoach _coach;

  static const _easyPolicy = HeuristicPolicy(noise: 1.0);

  /// Picks a move for the seat of [view], which must be on turn.
  Play chooseMove(BigTwoView view) => decide(view).play;

  /// Picks a move for the seat of [view], which must be on turn, and gives
  /// the analysis it was picked from: Medium and Hard rate every move as
  /// the coach does, so an online host can show that analysis to spectators
  /// without asking the coach again. Easy (and a forced move) has none.
  /// The same seed gives the same move as [chooseMove].
  BigTwoDecision decide(BigTwoView view) {
    final legal = view.legalMoves();
    if (legal.isEmpty) throw StateError('Seat ${view.seat} is not on turn');
    if (legal.length == 1) return BigTwoDecision(legal.first);
    if (level == BotLevel.easy) {
      return BigTwoDecision(_easyPolicy.chooseFrom(BigTwoState.fromView(view, null), legal, _rng));
    }
    final analysis = _coach.analyze(view, seed: _rng.nextSeed());
    return BigTwoDecision(analysis.best.play, analysis: analysis);
  }
}

/// A bot's move, with the analysis behind it when it made one.
class BigTwoDecision {
  /// A move, and the analysis it came from (null: Easy, or a forced move).
  const BigTwoDecision(this.play, {this.analysis});

  /// The move.
  final Play play;

  /// Every legal move rated, as the coach rates them (Medium and Hard).
  final BigTwoAnalysis? analysis;
}
