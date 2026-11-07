import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/last_games.dart';
import '../../../games/blackjack/app/blackjack_analysis_codec.dart';
import '../../../games/blackjack/app/blackjack_grading.dart';
import '../../../games/blackjack/app/blackjack_jobs.dart';
import '../../../games/blackjack/app/blackjack_record.dart';
import '../../../games/blackjack/blackjack.dart';
import '../../../kit/game_keys.dart';
import '../../../kit/game_record.dart';
import '../../../kit/coach_answer.dart';
import '../../../kit/jobs/jobs.dart';
import '../../../kit/jobs/jobs_core.dart';
import '../../../l10n/strings.dart';
import '../../kit/coach_panel.dart';
import '../../kit/kit_scope.dart';
import '../../kit/l10n/kit_strings.dart';
import '../../kit/review_kit.dart';
import '../../kit/turn_controller.dart' show JobRequest;
import 'blackjack_coach_view.dart';
import 'blackjack_controller.dart' show blackjackListedMoves;
import 'blackjack_table.dart';
import 'l10n/blackjack_strings.dart';

/// The saved shoe, if there is one that plays back (the menu's Last game
/// is greyed out without one).
Future<GameRecord?> loadLastShoe(LastGames store) =>
    store.load(GameKeys.blackjack, version: blackjackRecordVersion, validate: blackjackReplays);

/// The game menu's Last game: the most recent shoe, step by step (see
/// ReviewScaffold). Each step is the felt before a move: before a Deal it
/// shows the round just finished, before a decision the cards as the
/// player saw them. The panel gives the move, its grade from the game
/// (Training only), and the coach's answer for decisions when its chip is
/// on; a Deal gets no coach. All cards turns the dealer's hole card up.
class BlackjackReview extends StatefulWidget {
  const BlackjackReview({super.key, this.record});

  /// The shoe to review; null: the saved one.
  final GameRecord? record;

  @override
  State<BlackjackReview> createState() => _BlackjackReviewState();
}

class _BlackjackReviewState extends State<BlackjackReview> {
  Future<GameRecord?>? _record;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _record ??= widget.record != null ? SynchronousFuture(widget.record) : loadLastShoe(KitScope.of(context).lastGames);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<GameRecord?>(
    future: _record,
    builder: (context, snapshot) => switch (snapshot.data) {
      final record? => _ShoeReview(record: record),
      // Loading, or the shoe went missing after the menu found it (a tiny
      // window): the bar alone, with the back arrow.
      null => Scaffold(
        backgroundColor: const Color(0xFF0B0F12),
        appBar: AppBar(title: Text(S.of(context).blackjack)),
      ),
    },
  );
}

class _ShoeReview extends StatefulWidget {
  const _ShoeReview({required this.record});

  final GameRecord record;

  @override
  State<_ShoeReview> createState() => _ShoeReviewState();
}

class _ShoeReviewState extends State<_ShoeReview> {
  GameRecord get record => widget.record;

  late final rules = BlackjackRules.fromJson(record.rules);
  late final coachMode = CoachMode.byName(record.extra['coachMode']);

  /// The strategy chart for the shoe's rules, made once when the coach is
  /// first switched on (about a second; see [_prepareCoach]); each coach
  /// job then gets it rather than building its own.
  BasicStrategyChart? _chart;

  /// The count on the felt as the game had it (☰ Count), and always when
  /// the coach counted the cards seen, so its Count tags can be followed.
  /// Never with a continuous shuffler: there is nothing to count.
  late final showCount = !rules.continuousShuffle && (record.extra['count'] == true || coachMode == CoachMode.seen);

  /// The shoe replayed to each step looked at, kept while the review is
  /// open (sliding back and forth replays nothing twice).
  final _plays = <int, BlackjackPlay>{};

  BlackjackPlay _playAt(int step) => _plays[step] ??= BlackjackPlay.replay(record.upTo(step));

  /// The step on the felt (the table is built before the panel), for the
  /// coach list's move names: Insurance is "Even money" when the player
  /// has blackjack.
  var _shown = 0;

  /// Whether the shoe at [step] stands at an even-money offer.
  bool _evenMoneyAt(int step) {
    final round = _playAt(step).round;
    return round != null && round.phase == RoundPhase.insurance && round.viewFor(playerSeat).offersEvenMoney;
  }

  /// The chart job, run with the review's own jobs (leaving cancels it).
  /// If it fails, the coach jobs go without a chart and make their own.
  Future<void> _prepareCoach(Jobs jobs) async {
    _chart = await jobs.start(const BlackjackChartJob(), rules, kind: JobKind.guide).result;
  }

  /// A step's headline: the round on the felt and the move ("Round 3 ·
  /// Move 12"); before the first deal, the move alone. One player, so
  /// naming the seat would say nothing.
  String _stepTitle(BuildContext context, ReviewStep step) {
    final move = KitStrings.of(context).moveNumber(step.index + 1);
    final rounds = _playAt(step.index).rounds;
    return rounds == 0 ? move : '${BlackjackStrings.of(context).round(rounds)} · $move';
  }

  /// The coach for a decision; none for a Deal. It runs as a deep job, on
  /// the chart made for the review and for the game's coach mode (a Cards seen shoe
  /// gets the count's plays tagged).
  JobRequest? _coachRequest(GameRecord position, int seat, int seed) {
    if (_playAt(position.moves.length).betweenRounds) return null;
    return JobRequest(
      const BlackjackCoachJob(),
      BlackjackDecisionInput(position: position, seat: seat, chart: _chart),
      JobKind.coach,
    );
  }

  /// The last step: who came out ahead and by how much ("You win · Net
  /// +3.5", in the kit's words for a game's result); just the net for a
  /// shoe left before its end.
  String _result(BuildContext context, GameRecord record) {
    final k = KitStrings.of(context);
    final b = BlackjackStrings.of(context);
    final net = k.net(betsText(_playAt(record.moves.length).net));
    final result = record.result;
    if (result == null) return net;
    final winners = result['winners'] as List? ?? const [];
    final outcome = winners.contains(playerSeat)
        ? k.youWin
        : winners.contains(dealerSeat)
        ? k.wins(b.dealerSeat)
        : k.draw;
    return '$outcome · $net';
  }

  @override
  Widget build(BuildContext context) {
    final b = BlackjackStrings.of(context);
    final k = KitStrings.of(context);
    return ReviewScaffold(
      title: S.of(context).blackjack,
      strings: b,
      record: record,
      unit: ValueUnit.bets,
      // One player: the dealer draws inside the engine and never moves.
      seatOf: (_, _) => playerSeat,
      table: (context, step) {
        _shown = step.index;
        return BlackjackTableView(play: _playAt(step.index), showCount: showCount, showHoleCard: step.allCards);
      },
      stepTitle: _stepTitle,
      coachRequest: _coachRequest,
      prepareCoach: _prepareCoach,
      toAnswer: (output) => blackjackAnswer(output! as BlackjackCoachResult, coachMode),
      look: CoachLook(
        moveText: (move) => blackjackMoveText(b, move, evenMoney: _evenMoneyAt(_shown), deal: k.deal),
        markText: (move, index) =>
            blackjackMoveText(b, move, evenMoney: isInsurance(move) && _evenMoneyAt(index), deal: k.deal),
        reasonText: (code) => blackjackReason(b, code),
      ),
      listedMoves: (position, _) => blackjackListedMoves(_playAt(position.moves.length)),
      cards: true,
      resultText: _result,
    );
  }
}
