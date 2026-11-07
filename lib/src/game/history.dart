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
    this.turnId,
  });

  /// Which decision of the hand this was: online, the server's turn (to
  /// correct [played] if the server played something else, when the time
  /// ran out); on the device, how many actions came before it. Decisions
  /// are kept in this order (see [HandRecord.addDecision]).
  final int? turnId;

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

/// Online: something everyone at the table was told during a hand: [name]
/// pressed Show GTO, or showed their cards ([shown]); a null name is the
/// user.
class HandNote {
  const HandNote({required this.name, this.shown});

  final String? name;

  /// The cards a player showed after the hand.
  final List<PlayingCard>? shown;
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

  /// Online: what everyone at the table was told during the hand.
  final List<HandNote> notes = [];

  double? get averageScore => decisions.isEmpty
      ? null
      : decisions.fold(0, (sum, d) => sum + d.points) / decisions.length;

  double get evLost => decisions.fold(0.0, (sum, d) => sum + d.score.evLoss);

  /// Adds [decision] in the order the hand played its decisions (by
  /// [DecisionRecord.turnId]; one without goes last): a decision graded
  /// after its move may come after a later one graded at once.
  void addDecision(DecisionRecord decision) {
    final turn = decision.turnId;
    var at = decisions.length;
    if (turn != null) {
      while (at > 0 && (decisions[at - 1].turnId ?? turn + 1) > turn) {
        at--;
      }
    }
    decisions.insert(at, decision);
  }
}
