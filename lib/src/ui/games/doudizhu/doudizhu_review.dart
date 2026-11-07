import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/last_games.dart';
import '../../../games/doudizhu/app/doudizhu_analysis.dart';
import '../../../games/doudizhu/app/doudizhu_grading.dart';
import '../../../games/doudizhu/app/doudizhu_jobs.dart';
import '../../../games/doudizhu/app/doudizhu_record.dart';
import '../../../games/doudizhu/doudizhu.dart';
import '../../../kit/coach_answer.dart';
import '../../../kit/game_keys.dart';
import '../../../kit/game_record.dart';
import '../../../kit/jobs/jobs_core.dart';
import '../../../l10n/strings.dart';
import '../../kit/kit_scope.dart';
import '../../kit/l10n/kit_strings.dart';
import '../../kit/review_kit.dart';
import '../../kit/turn_controller.dart' show JobRequest;
import 'doudizhu_cards.dart';
import 'doudizhu_coach_view.dart';
import 'doudizhu_controller.dart';
import 'doudizhu_table.dart';
import 'l10n/doudizhu_strings.dart';

/// The saved deal, if there is one that plays back (the menu's Last game is
/// greyed out without one, and setup starts from its choices).
Future<GameRecord?> loadLastDeal(LastGames store) =>
    store.load(GameKeys.doudizhu, version: ddzRecordVersion, validate: ddzReplays);

/// The game menu's Last game: the most recent deal, step by step (see
/// ReviewScaffold), the auction included. Each step is the felt before a
/// move, with the player's hand below and the cards of the player's next
/// play raised. The panel gives the move, its grade from the game (Training
/// only; bids in points, plays in win chance), and the coach's answer for
/// the player's decisions when its chip is on. All cards turns the bots'
/// hands and the kitty up.
class LandlordReview extends StatefulWidget {
  const LandlordReview({super.key, this.record});

  /// The deal to review; null: the saved one.
  final GameRecord? record;

  @override
  State<LandlordReview> createState() => _LandlordReviewState();
}

class _LandlordReviewState extends State<LandlordReview> {
  Future<GameRecord?>? _record;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _record ??= widget.record != null ? SynchronousFuture(widget.record) : loadLastDeal(KitScope.of(context).lastGames);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<GameRecord?>(
    future: _record,
    builder: (context, snapshot) => switch (snapshot.data) {
      final record? => _DealReview(record: record),
      // Loading, or the deal went missing after the menu found it (a
      // tiny window): the bar alone, with the back arrow.
      null => Scaffold(
        backgroundColor: const Color(0xFF0B0F12),
        appBar: AppBar(title: Text(S.of(context).fightTheLandlord)),
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

  /// The deal's own rules: every move is read back under them (a variant
  /// such as both jokers as kickers makes plays the standard rules can't).
  late final rules = ddzRulesOf(record);

  /// The deal replayed to each step looked at, kept while the review is
  /// open (sliding back and forth replays nothing twice).
  final _games = <int, DdzGame>{};

  DdzGame _gameAt(int step) => _games[step] ??= ddzReplay(record, upTo: step);

  /// How the player laid out their hand, as the deal was saved: every step
  /// shows their cards in that order (the kitty only once it is theirs;
  /// the cards played before each drag where they lay, see
  /// HandArrangement.moved).
  late final _arrangement = ddzArrangementOf(record.extra);

  /// The step on the felt (the table is built before the panel): the coach
  /// rows and the grade card draw plays in the player's suits from then.
  var _shown = 0;

  static const _player = LandlordController.you;

  /// Who made move [i]: the record says so before the colon.
  static int _seatOf(GameRecord record, int i) => ddzParseSeat(record.moves[i]);

  /// The coach for the player's real decisions (deep, as Think longer); a
  /// bot's move and a move the player had no choice in get none.
  JobRequest? _coachRequest(GameRecord position, int seat, int seed) {
    if (seat != _player || _gameAt(position.moves.length).legalMoves().length < 2) return null;
    return JobRequest(
      const DdzCoachJob(),
      DdzCoachInput(record: position.jobJson(), seat: seat, deep: true, seed: seed),
      JobKind.coachDeep,
    );
  }

  String _name(BuildContext context, int seat) =>
      seat == _player ? S.of(context).you : (seat < record.seats.length ? record.seats[seat].name : '');

  /// "Move 12 · Ana", the player's own seat named "Player".
  String _stepTitle(BuildContext context, ReviewStep step) => [
    KitStrings.of(context).moveNumber(step.index + 1),
    if (step.seat case final seat?) _name(context, seat),
  ].join(' · ');

  /// The last step: who won and the player's points ("You win · Net +8"),
  /// or "Everyone passed" for a deal thrown in. A deal left before its end:
  /// the landlord and the multiplier so far, or before anyone bid, whose
  /// turn it was ("Move 1 · Player"). (A finished deal's multiplier
  /// is in its points; the headline has no room for both on a phone.)
  String _result(BuildContext context, GameRecord record) {
    final k = KitStrings.of(context);
    final s = LandlordStrings.of(context);
    final game = _gameAt(record.moves.length);
    if (game.phase == DdzPhase.thrownIn) return s.everyonePassed;
    final lord = game.landlord;
    final times = game.stake == 0 ? null : s.multiplier(game.stake * game.multiplier);
    final result = game.result;
    if (result == null) {
      final sofar = [if (lord != null) '${s.landlord}: ${_name(context, lord)}', ?times];
      // Left before anyone bid: whose turn it was, as the steps say it.
      if (sofar.isEmpty) {
        return [k.moveNumber(record.moves.length + 1), _name(context, game.toAct)].join(' · ');
      }
      return sofar.join(' · ');
    }
    final mine = result.points[_player];
    final outcome = result.wonBy(_player)
        ? k.youWin
        : (lord == _player ? k.youLose : k.wins(_name(context, result.landlord)));
    return '$outcome · ${k.net(mine > 0 ? '+$mine' : (mine < 0 ? '−${-mine}' : '0'))}';
  }

  @override
  Widget build(BuildContext context) {
    final s = LandlordStrings.of(context);
    return ReviewScaffold(
      title: S.of(context).fightTheLandlord,
      strings: s,
      record: record,
      // Play's unit; the auction's marks carry their own (points).
      unit: ValueUnit.winChance,
      seatOf: _seatOf,
      table: (context, step) {
        _shown = step.index;
        final game = _gameAt(step.index);
        final over = game.phase == DdzPhase.finished || game.phase == DdzPhase.thrownIn;
        return LandlordTable(
          felt: LandlordFelt(
            game: game,
            names: [for (var seat = 0; seat < 3; seat++) _name(context, seat)],
            toAct: step.seat,
            over: over,
            winners: [
              for (var seat = 0; seat < 3; seat++)
                if (game.result?.wonBy(seat) ?? false) seat,
            ],
            allCards: step.allCards,
            seed: record.seed,
          ),
          strings: s,
        );
      },
      bottom: (context, step) {
        final next = step.next;
        final mine = next == null || step.seat != _player ? null : ddzParseMove(next, rules);
        final game = _gameAt(step.index);
        final over = game.phase == DdzPhase.finished || game.phase == DdzPhase.thrownIn;
        return LandlordHand(
          cards: _arrangement.arrange(ddzHandSorted(game.hands[_player], _arrangement.sort)),
          // The cards everyone had seen at this step, as in the game.
          visible: over ? const {} : {...game.visibleIn(_player)},
          // The cards the player played here, raised.
          selected: {...?mine?.cardIds},
          // The order the hand was left in, greyed out: the review
          // changes nothing.
          sortOrder: _arrangement.order,
        );
      },
      coachRequest: _coachRequest,
      toAnswer: (output) => ddzAnswer(output! as DdzAdvice),
      // Pass and the bids are always on the coach's list, as in the game.
      listedMoves: (position, seat) => ddzListedMoves(_gameAt(position.moves.length), seat),
      look: ddzLook(s, rules: rules, cards: () => _gameAt(_shown).hands[_player]),
      cards: true,
      stepTitle: _stepTitle,
      resultText: _result,
    );
  }
}
