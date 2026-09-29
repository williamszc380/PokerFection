import '../engine/cards.dart';
import '../engine/events.dart';
import '../engine/positions.dart';
import '../gto/spot_strategy.dart';

/// One scored decision: what GTO does, what the user entered, and the score.
class DecisionRecord {
  DecisionRecord({
    required this.street,
    required this.board,
    required this.spot,
    required this.mix,
    required this.score,
    this.oneAction = false,
  });

  /// One action played (simple training) rather than a mix: scored by
  /// [DecisionScore.playScore].
  final bool oneAction;

  /// The decision's score, 0-100.
  int get points => oneAction ? score.playScore : score.score;

  final Street street;
  final List<PlayingCard> board;
  final SpotStrategy spot;

  /// The user's frequencies, one per action in [spot] (adding up to 1).
  final List<double> mix;
  final DecisionScore score;

  /// The action that was played (drawn from [mix]), once known.
  int? played;
}

/// The user's scored decisions in one hand.
class HandRecord {
  HandRecord({
    required this.handNumber,
    required this.holeCards,
    required this.position,
    this.advanced = false,
  });

  /// Played in advanced training (percentages), not simple.
  final bool advanced;

  final int handNumber;
  final List<PlayingCard> holeCards;
  final Position position;
  final List<DecisionRecord> decisions = [];

  /// Chips won (positive) or lost, once the hand is over.
  int? result;

  double? get averageScore => decisions.isEmpty
      ? null
      : decisions.fold(0, (sum, d) => sum + d.points) / decisions.length;

  double get evLost => decisions.fold(0.0, (sum, d) => sum + d.score.evLoss);

}
