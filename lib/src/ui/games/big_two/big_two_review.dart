import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Card;

import '../../../app/last_games.dart';
import '../../../games/big_two/app/big_two_analysis.dart';
import '../../../games/big_two/app/big_two_grading.dart';
import '../../../games/big_two/app/big_two_jobs.dart';
import '../../../games/big_two/app/big_two_match.dart';
import '../../../games/big_two/app/big_two_record.dart';
import '../../../games/big_two/big_two.dart';
import '../../../kit/coach_answer.dart';
import '../../../kit/game_keys.dart';
import '../../../kit/game_record.dart';
import '../../../kit/jobs/jobs_core.dart';
import '../../../kit/match.dart';
import '../../../l10n/strings.dart';
import '../../kit/kit_scope.dart';
import '../../kit/l10n/kit_strings.dart';
import '../../kit/review_kit.dart';
import '../../kit/turn_controller.dart' show JobRequest;
import 'big_two_coach_view.dart';
import 'big_two_controller.dart';
import 'big_two_screen.dart' show BigTwoHandView;
import 'big_two_table.dart';
import 'l10n/big_two_strings.dart';

/// The saved deal, if there is one that plays back (the menu's Last game
/// is greyed out without one).
Future<GameRecord?> loadLastBigTwo(LastGames store) =>
    store.load(GameKeys.bigTwo, version: bigTwoRecordVersion, validate: BigTwoRecord.validate);

/// The game menu's Last game: the most recent deal, step by step (see
/// ReviewScaffold). Each step is the felt before a move, with the play to
/// beat and the seat about to move lit, and the player's hand below, the
/// cards of their next play raised. The panel gives the move, its grade
/// from the game (Training only), and, when the coach chip is on, the
/// coach's answer for the player's own choices (a deep job, graded on the
/// game's scale, which allows for the coach's noise). All cards turns the
/// bots' hands face up.
class BigTwoReview extends StatefulWidget {
  const BigTwoReview({super.key, this.record});

  /// The deal to review; null: the saved one.
  final GameRecord? record;

  @override
  State<BigTwoReview> createState() => _BigTwoReviewState();
}

class _BigTwoReviewState extends State<BigTwoReview> {
  Future<GameRecord?>? _record;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _record ??= widget.record != null
        ? SynchronousFuture(widget.record)
        : loadLastBigTwo(KitScope.of(context).lastGames);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<GameRecord?>(
    future: _record,
    builder: (context, snapshot) => switch (snapshot.data) {
      final record? => _DealReview(record: record),
      // Loading, or the deal went missing after the menu found it (a tiny
      // window): the bar alone, with the back arrow.
      null => Scaffold(
        backgroundColor: const Color(0xFF0B0F12),
        appBar: AppBar(title: Text(S.of(context).bigTwo)),
      ),
    },
  );
}

class _DealReview extends StatefulWidget {
  const _DealReview({required this.record});

  final GameRecord record;

  @override
  State<_DealReview> createState() => _DealReviewState();
}

class _DealReviewState extends State<_DealReview> {
  GameRecord get record => widget.record;

  late final rules = BigTwoRecord.rulesOf(record);

  /// The game's grading: any answer the review grades goes through its
  /// `mark`, which allows for each line's error.
  late final scale = bigTwoScale(rules);

  /// The hand laid out as the game left it: sorted by rank or suit, or in
  /// the player's own order, which keeps the cards played before each drag
  /// where they lay (see HandArrangement.moved).
  late final arrangement = arrangementOf(record.extra);

  /// The points the match counted for this deal (penalties, or the
  /// winner's points), when the deal was part of a match and is over; null:
  /// the deal's own scores.
  late final List<int>? _matchPoints = () {
    final end = _stateAt(record.moves.length);
    if (record.extra[MatchScore.extraKey] == null || !end.isOver) return null;
    return bigTwoDealPoints(rules, end.result);
  }();

  /// The deal replayed to each step looked at, kept while the review is
  /// open (sliding back and forth replays nothing twice).
  final _states = <int, BigTwoState>{};

  BigTwoState _stateAt(int step) => _states[step] ??= BigTwoRecord.replay(record.upTo(step));

  /// The coach move under the mouse: the hand lights its cards.
  String? _preview;

  void _hover(String? move) {
    if (move == _preview || !mounted) return;
    setState(() => _preview = move);
  }

  /// The coach for the player's own choices; none for the bots' moves, or
  /// when Pass was the only move (the game grades nothing there either).
  JobRequest? _coachRequest(GameRecord position, int seat, int seed) {
    if (seat != 0 || _stateAt(position.moves.length).legalMoves().length < 2) return null;
    return JobRequest(
      const BigTwoCoachJob(),
      BigTwoCoachInput(record: position.jobJson(), seat: seat, seed: seed, deep: true),
      JobKind.coachDeep,
    );
  }

  String _name(BuildContext context, int seat) {
    final names = BigTwoTable.seatNames(context, record.seats);
    return seat < names.length ? names[seat] : '';
  }

  /// "Move 12 · Ana"; the player's own seat is "Player".
  String _stepTitle(BuildContext context, int index, int seat) =>
      '${KitStrings.of(context).moveNumber(index + 1)} · ${_name(context, seat)}';

  /// The last step: who won and the player's points ("Ana wins · −9 pts");
  /// for a deal left before its end, whose move it was.
  String _result(BuildContext context, GameRecord record) {
    final k = KitStrings.of(context);
    final end = _stateAt(record.moves.length);
    if (!end.isOver) return _stepTitle(context, record.moves.length, end.toMove);
    final winner = end.winner;
    final points = end.result.scores[0];
    final signed = points > 0 ? '+$points' : (points < 0 ? '−${-points}' : '0');
    return '${winner == 0 ? k.youWin : k.wins(_name(context, winner))} · ${k.pointsValue(signed)}';
  }

  @override
  Widget build(BuildContext context) {
    final t = BigTwoStrings.of(context);
    return ReviewScaffold(
      title: S.of(context).bigTwo,
      strings: t,
      record: record,
      unit: ValueUnit.points,
      seatOf: (record, i) => bigTwoMoveSeat(record.moves[i]),
      table: (context, step) => BigTwoTable(
        state: _stateAt(step.index),
        names: BigTwoTable.seatNames(context, record.seats),
        strings: t,
        toAct: step.seat,
        handsUp: step.allCards,
        seed: record.seed,
        points: _matchPoints,
      ),
      bottom: (context, step) {
        final hand = arrangedHand(rules, _stateAt(step.index).handOf(0), arrangement);
        // The player's next play stands up; a coach row under the mouse
        // fades the cards it doesn't use.
        final next = step.seat == 0 && step.next != null ? bigTwoMoveCards(step.next!).toSet() : const <Card>{};
        final preview = _preview == null || step.seat != 0 ? null : bigTwoMoveCards(_preview!).toSet();
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
          child: BigTwoHandView(
            key: const ValueKey('review hand'),
            cards: hand,
            selected: next,
            // The cards everyone had seen at this step carry the eye.
            visible: {..._stateAt(step.index).visibleIn(0)},
            // The order the game was in; greyed out: a review sorts nothing.
            sortOrder: arrangement.order,
            dimmed: preview == null
                ? const {}
                : {
                    for (final card in hand)
                      if (!preview.contains(card)) card,
                  },
          ),
        );
      },
      coachRequest: _coachRequest,
      // Pass is always among the coach's rows when it was legal.
      listedMoves: (position, seat) => bigTwoListedMoves(_stateAt(position.moves.length), seat),
      toAnswer: (output) => bigTwoAnswer(output! as BigTwoReport, scale),
      look: bigTwoLook(t, onHover: _hover),
      cards: true,
      stepTitle: (context, step) => _stepTitle(context, step.index, step.seat!),
      resultText: _result,
    );
  }
}
