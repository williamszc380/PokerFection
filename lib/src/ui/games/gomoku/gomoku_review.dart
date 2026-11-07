import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/last_games.dart';
import '../../../games/gomoku/app/gomoku_analysis.dart';
import '../../../games/gomoku/app/gomoku_jobs.dart';
import '../../../games/gomoku/app/gomoku_record.dart';
import '../../../games/gomoku/gomoku.dart';
import '../../../kit/coach_answer.dart';
import '../../../kit/game_keys.dart';
import '../../../kit/game_record.dart';
import '../../../kit/jobs/jobs_core.dart';
import '../../../l10n/strings.dart';
import '../../kit/kit_scope.dart';
import '../../kit/l10n/kit_strings.dart';
import '../../kit/review_kit.dart';
import '../../kit/turn_controller.dart' show JobRequest;
import 'gomoku_coach_view.dart';
import 'gomoku_table.dart';
import 'l10n/gomoku_strings.dart';

/// The saved game, if there is one that replays (the menu's Last game is
/// greyed out without one).
Future<GameRecord?> loadLastGomoku(LastGames store) =>
    store.load(GameKeys.gomoku, version: gomokuRecordVersion, validate: GomokuRecord.validate);

/// The game menu's Last game: the most recent game, move by move (see
/// ReviewScaffold). Each step is the board before a move, with that move
/// as a see-through stone; the last step is the final board, with the
/// winning row. The panel gives the move, its grade from the game
/// (Training only) and, when the coach chip is on, the coach's moves for
/// the Player's turns. Hovering a coach row shows its line on the board;
/// hovering the grade's "Best move: x" rings x.
class GomokuReview extends StatefulWidget {
  const GomokuReview({super.key, this.record});

  /// The game to review; null: the saved one.
  final GameRecord? record;

  @override
  State<GomokuReview> createState() => _GomokuReviewState();
}

class _GomokuReviewState extends State<GomokuReview> {
  Future<GameRecord?>? _record;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _record ??= widget.record != null
        ? SynchronousFuture(widget.record)
        : loadLastGomoku(KitScope.of(context).lastGames);
  }

  @override
  void didUpdateWidget(GomokuReview old) {
    super.didUpdateWidget(old);
    if (widget.record != old.record) {
      _record = widget.record != null
          ? SynchronousFuture(widget.record)
          : loadLastGomoku(KitScope.of(context).lastGames);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<GameRecord?>(
    future: _record,
    builder: (context, snapshot) => switch (snapshot.data) {
      // Keyed by the game: another record is another review, from its start.
      final record? => _GameReview(key: ObjectKey(record), record: record),
      // Loading, or the game went missing after the menu found it (a tiny
      // window): the bar alone, with the back arrow.
      null => Scaffold(
        backgroundColor: const Color(0xFF0B0F12),
        appBar: AppBar(title: Text(S.of(context).gomoku)),
      ),
    },
  );
}

class _GameReview extends StatefulWidget {
  const _GameReview({super.key, required this.record});

  final GameRecord record;

  @override
  State<_GameReview> createState() => _GameReviewState();
}

class _GameReviewState extends State<_GameReview> {
  GameRecord get record => widget.record;

  /// The board at each step looked at, kept while the review is open
  /// (sliding back and forth replays nothing twice).
  final _games = <int, GomokuGame>{};

  GomokuGame _gameAt(int step) => _games[step] ??= GomokuRecord.replay(record.upTo(step));

  /// The coach's analysis for each step it answered: a row's line, hovered,
  /// shows on the board. The review asks for one step at a time and drops
  /// the answer of a step it left, so the answer that comes is always for
  /// the step last asked.
  final _analyses = <int, GomokuAnalysis>{};
  int? _asked;

  /// The coach row under the mouse (its line shows on the board), and the
  /// grade's "Best move: x" under the mouse (x is ringed, as in the game).
  String? _preview;
  String? _cardSpot;

  /// The step on the board, so the previews belong to it.
  var _shown = 0;

  int _seatOf(GameRecord record, int move) => move.isEven ? 0 : 1;

  /// The coach for the Player's moves (a bot's move gets none), deep, with
  /// the move played included so its row shows what it was worth.
  JobRequest? _coachRequest(GameRecord position, int seat, int seed) {
    if (!record.seats[seat].human) return null;
    final step = position.moves.length;
    final played = record.moves[step];
    _asked = step;
    return JobRequest(
      const GomokuCoachJob(),
      GomokuCoachInput(
        record: position.jobJson(),
        seat: seat,
        include: played == 'pass' ? null : played,
        depth: GomokuDepth.deep,
      ),
      JobKind.coachDeep,
    );
  }

  CoachAnswer _toAnswer(Object? output) {
    final analysis = output! as GomokuAnalysis;
    if (_asked case final step?) _analyses[step] = analysis;
    return gomokuAnswer(analysis);
  }

  /// The seat's name: "Player" for the user's own, the bot's name else.
  String _name(GomokuStrings g, int seat) => record.seats[seat].human ? g.you : record.seats[seat].name;

  /// "Move 12 · Player" before each move.
  String _stepTitle(BuildContext context, ReviewStep step) =>
      '${KitStrings.of(context).moveNumber(step.index + 1)} · ${_name(GomokuStrings.of(context), step.seat!)}';

  /// The last step: "You win", "Ana wins" or "Draw"; for a game left before
  /// its end, the move it stopped at and whose it was.
  String _result(BuildContext context, GameRecord record) {
    final k = KitStrings.of(context);
    final result = record.result;
    if (result == null) {
      final moves = record.moves.length;
      return '${k.moveNumber(moves + 1)} · ${_name(GomokuStrings.of(context), _seatOf(record, moves))}';
    }
    final winners = [
      for (final w in result['winners'] as List? ?? const [])
        if (w is int && w < record.seats.length) w,
    ];
    if (winners.isEmpty) return k.draw;
    if (record.seats[winners.first].human) return k.youWin;
    return k.wins(record.seats[winners.first].name);
  }

  void _hover(String? move) {
    if (mounted && move != _preview) setState(() => _preview = move);
  }

  void _pickHover(String? move) {
    if (mounted && move != _cardSpot) setState(() => _cardSpot = move);
  }

  @override
  Widget build(BuildContext context) {
    final g = GomokuStrings.of(context);
    return ReviewScaffold(
      title: S.of(context).gomoku,
      strings: g,
      record: record,
      unit: ValueUnit.winChance,
      seatOf: _seatOf,
      squareTable: true,
      table: (context, step) {
        if (step.index != _shown) {
          // Another step: a row hovered before belonged to the board left.
          _shown = step.index;
          _preview = null;
        }
        final game = _gameAt(step.index);
        final player = record.seats[0].human || !record.seats[1].human ? Stone.black : Stone.white;
        final analysis = _analyses[step.index];
        final line = switch ((analysis, _preview)) {
          (final a?, final move?) => a.of(GomokuMove.parse(move))?.line ?? const <GomokuMove>[],
          _ => const <GomokuMove>[],
        };
        return GomokuTable(
          key: const ValueKey('review board'),
          game: game,
          player: player,
          canPlay: false,
          onPlace: (_) {},
          onAim: (_) {},
          preview: line,
          spot: _cardSpot == null ? null : GomokuMove.parse(_cardSpot!),
          next: step.next == null ? null : GomokuMove.parse(step.next!),
        );
      },
      coachRequest: _coachRequest,
      toAnswer: _toAnswer,
      look: gomokuCoachLook(g, onHover: _hover, onPickHover: _pickHover),
      listedMoves: (position, _) => gomokuListedMoves(_gameAt(position.moves.length)),
      stepTitle: _stepTitle,
      resultText: _result,
    );
  }
}
