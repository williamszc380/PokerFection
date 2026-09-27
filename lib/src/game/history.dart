import '../engine/cards.dart';
import '../engine/events.dart';
import '../engine/positions.dart';
import '../gto/spot_strategy.dart';

/// One decision: what GTO does, what the user entered, and the score.
class DecisionRecord {
  DecisionRecord({
    required this.street,
    required this.board,
    required this.spot,
    required this.mix,
    required this.score,
    this.revealed = false,
  });

  /// The user looked at GTO's answer before playing (Show GTO): the
  /// decision isn't scored, though its EV loss still counts.
  final bool revealed;

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
  HandRecord({required this.handNumber, required this.holeCards, required this.position});

  final int handNumber;
  final List<PlayingCard> holeCards;
  final Position position;
  final List<DecisionRecord> decisions = [];

  /// Chips won (positive) or lost, once the hand is over.
  int? result;

  /// The average score of the scored decisions (not the revealed ones);
  /// null if there are none.
  double? get averageScore {
    final scored = [for (final d in decisions) if (!d.revealed) d.score.score];
    return scored.isEmpty ? null : scored.fold(0, (sum, s) => sum + s) / scored.length;
  }

  double get evLost => decisions.fold(0.0, (sum, d) => sum + d.score.evLoss);
}
