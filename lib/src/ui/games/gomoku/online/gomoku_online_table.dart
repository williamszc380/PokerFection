import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/app_settings.dart';
import '../../../../games/gomoku/gomoku.dart';
import '../../../../games/gomoku/online/gomoku_view_codec.dart';
import '../../../kit/game_sounds.dart';
import '../../../table_controller.dart' show PlaybackSpeed;
import '../../../online/runner_client.dart';
import '../gomoku_screen.dart' show GomokuPlayerTag;
import '../gomoku_table.dart';
import '../l10n/gomoku_strings.dart';

/// The game in [c]'s latest view, replayed by the engine once per view
/// (the table, the buttons and the sounds all read it); null before the
/// first view, or for a view this version can't read.
GomokuOnlineView? gomokuViewOf(RunnerClient c) {
  final view = c.view;
  if (view == null) return null;
  final cached = _views[view];
  if (cached != null) return cached;
  try {
    return _views[view] = GomokuOnlineView.fromJson(view);
  } on FormatException {
    return null;
  }
}

final _views = Expando<GomokuOnlineView>('gomoku view');

/// What the seated player's table and buttons share on this device: the
/// point aimed at (by touch, or the arrow keys), for the position it was
/// aimed in (a move by anyone drops it).
class GomokuOnlineAim extends ChangeNotifier {
  GomokuMove? _aim;
  String _at = '';

  /// The point aimed at in [view]'s position (null: none, or aimed in
  /// another position).
  GomokuMove? at(GomokuOnlineView? view) => view != null && _key(view) == _at ? _aim : null;

  void set(GomokuOnlineView view, GomokuMove? aim) {
    _aim = aim;
    _at = _key(view);
    notifyListeners();
  }

  static String _key(GomokuOnlineView view) => '${view.game.moves.length} ${view.game.lastMove}';

  /// [c]'s own (one per game on this device).
  static GomokuOnlineAim of(RunnerClient c) => _aims[c] ??= GomokuOnlineAim();
  static final _aims = Expando<GomokuOnlineAim>('gomoku aim');
}

/// Gomoku's table in a room: the solo game's board (GomokuTable: the last
/// move, the winning row, Renju's forbidden points ×) and the two players'
/// tags (their colour, name, wins; the one to move lit), beside the board
/// when there is room, above it otherwise.
///
/// - The seated player plays as in the solo game: with a mouse a click
///   places the stone (a see-through one follows the pointer); by touch a
///   tap aims and a second tap (or Place) places it; Enter places the
///   point aimed at and the arrow keys move it.
/// - A spectator with the coach on sees its top moves numbered on the
///   board, the pick in the pick colour, as in the solo game.
/// - Sounds as in the solo game, only while the screen is open: a stone
///   for every move, "your turn" after the opponent's, a win or a loss.
class GomokuOnlineTable extends StatefulWidget {
  const GomokuOnlineTable({super.key, required this.runner});

  final RunnerClient runner;

  @override
  State<GomokuOnlineTable> createState() => _GomokuOnlineTableState();
}

class _GomokuOnlineTableState extends State<GomokuOnlineTable> {
  final _focus = FocusNode(debugLabel: 'gomoku online table');
  late PlaybackSpeed _speed;

  // What the sounds were last played for.
  int _round = 0, _moves = 0;
  bool _myTurn = false, _over = false;

  RunnerClient get _c => widget.runner;
  GomokuOnlineAim get _aim => GomokuOnlineAim.of(_c);

  @override
  void initState() {
    super.initState();
    _remember();
    _c.addListener(_onChange);
    _aim.addListener(_onAim);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _speed = AppSettings.of(context).speed;
  }

  @override
  void didUpdateWidget(GomokuOnlineTable old) {
    super.didUpdateWidget(old);
    if (old.runner != widget.runner) {
      old.runner.removeListener(_onChange);
      GomokuOnlineAim.of(old.runner).removeListener(_onAim);
      _remember();
      _c.addListener(_onChange);
      _aim.addListener(_onAim);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    _aim.removeListener(_onAim);
    _focus.dispose();
    super.dispose();
  }

  void _onAim() {
    if (mounted) setState(() {});
  }

  /// The position as heard, so only what comes next makes a sound.
  void _remember() {
    final view = gomokuViewOf(_c);
    _round = _c.round;
    _moves = view?.game.moves.length ?? 0;
    _myTurn = _c.myTurn;
    _over = _c.over != null;
  }

  /// The solo game's sounds for what just happened, while on screen.
  void _onChange() {
    final view = gomokuViewOf(_c);
    final moves = view?.game.moves.length ?? 0;
    final sameRound = _c.round == _round;
    final over = _c.over != null;
    if (_c.onScreen && view != null) {
      if (sameRound && moves > _moves) GameSounds.play(SoundEffect.stone, speed: _speed);
      if (_c.myTurn && !_myTurn && moves > 0) GameSounds.play(SoundEffect.yourTurn, speed: _speed);
      if (over && !_over && _c.you != null && view.winner != null) {
        GameSounds.play(view.winner == _c.you ? SoundEffect.win : SoundEffect.lose, speed: _speed);
      }
    }
    _remember();
  }

  void _place(GomokuOnlineView view, GomokuMove move) {
    if (_c.myTurn && view.game.isLegal(move)) _c.move(move.notation);
  }

  /// The arrow keys move the aim (from the last stone, or the centre).
  void _nudge(GomokuOnlineView view, int dx, int dy) {
    if (!_c.myTurn) return;
    final game = view.game;
    final size = game.rules.size;
    final from =
        _aim.at(view) ?? game.moves.lastWhere((m) => !m.isPass, orElse: () => GomokuMove(size ~/ 2, size ~/ 2));
    _aim.set(view, GomokuMove((from.x + dx).clamp(0, size - 1), (from.y + dy).clamp(0, size - 1)));
  }

  @override
  Widget build(BuildContext context) {
    final view = gomokuViewOf(_c);
    if (view == null) return const SizedBox.expand();
    final strings = GomokuStrings.of(context);
    final c = _c;
    final game = view.game;
    final you = c.you;
    final canPlay = c.myTurn;
    // A spectator's coach, once it has answered for this position.
    final analysis = c.spectating && c.coachOn && !c.coachThinking && !game.isOver
        ? c.coach?.detail as GomokuAnalysis?
        : null;
    final coachMoves = [
      for (final m in analysis?.moves ?? const <MoveAnalysis>[])
        if (game.isLegal(m.move)) m.move,
    ];
    final board = GomokuTable(
      key: const ValueKey('gomoku online board'),
      game: game,
      player: you == null ? game.toMove : view.colorOf(you),
      canPlay: canPlay,
      aim: _aim.at(view),
      onAim: (move) => _aim.set(view, move),
      onPlace: (move) => _place(view, move),
      coachMoves: coachMoves,
      pick: coachMoves.isEmpty ? null : analysis?.best?.move,
    );
    Widget tag(int seat) {
      final score = c.seatInfo(seat)?.score;
      return GomokuPlayerTag(
        key: ValueKey('gomoku tag $seat'),
        color: view.colorOf(seat),
        name: seat == you ? strings.you : c.nameOf(seat),
        toMove: view.seatToAct == seat && c.over == null,
        score: score == null ? null : _scoreText(score),
      );
    }

    // Black's tag first (left, or on top), White's after.
    final seats = [view.black, 1 - view.black];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (_aim.at(view) case final aim?) _place(view, aim);
        },
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _nudge(view, -1, 0),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _nudge(view, 1, 0),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _nudge(view, 0, 1),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _nudge(view, 0, -1),
      },
      child: Focus(
        focusNode: _focus,
        autofocus: you != null,
        child: LayoutBuilder(
          builder: (context, box) {
            const sideWidth = 132.0, topHeight = 34.0;
            final w = box.maxWidth, h = box.maxHeight;
            // Whichever leaves the bigger board: the tags beside it, or above it.
            final besideBoard = min(h, w - 2 * sideWidth);
            final underTags = min(w, h - topHeight);
            if (besideBoard >= underTags) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: sideWidth,
                    child: Padding(padding: const EdgeInsets.fromLTRB(6, 10, 0, 0), child: tag(seats[0])),
                  ),
                  Expanded(child: board),
                  SizedBox(
                    width: sideWidth,
                    child: Padding(padding: const EdgeInsets.fromLTRB(0, 10, 6, 0), child: tag(seats[1])),
                  ),
                ],
              );
            }
            return Column(
              children: [
                // As wide as the board under them (at least two tags' worth).
                Center(
                  child: SizedBox(
                    height: topHeight,
                    width: max(underTags, min(w, 2 * sideWidth)),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                      child: Row(children: [for (final seat in seats) Expanded(child: tag(seat))]),
                    ),
                  ),
                ),
                Expanded(child: board),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A seat's score as the tags show it: whole numbers without a point.
String _scoreText(num score) => score == score.roundToDouble() ? '${score.round()}' : '$score';

/// The seated player's buttons in the Game tab, as in the solo game: Place
/// (the point aimed at by touch or the arrow keys) and, under Renju, Pass
/// (only when every free point is forbidden to Black); greyed out unless
/// it is the player's turn.
class GomokuOnlineActions extends StatelessWidget {
  const GomokuOnlineActions({super.key, required this.runner});

  final RunnerClient runner;

  @override
  Widget build(BuildContext context) {
    final c = runner;
    final aim = GomokuOnlineAim.of(c);
    return ListenableBuilder(
      listenable: aim,
      builder: (context, _) {
        final strings = GomokuStrings.of(context);
        final view = gomokuViewOf(c);
        final game = view?.game;
        final canPlay = c.myTurn && game != null;
        final point = aim.at(view);
        const tight = EdgeInsets.symmetric(horizontal: 12);
        return Row(
          children: [
            if (game?.rules.winRule == WinRule.renju) ...[
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('pass'),
                  style: OutlinedButton.styleFrom(padding: tight),
                  onPressed: canPlay && game.mustPass ? () => c.move(GomokuMove.pass.notation) : null,
                  child: Text(strings.pass, maxLines: 1),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: FilledButton(
                key: const ValueKey('place'),
                style: FilledButton.styleFrom(padding: tight),
                onPressed: canPlay && point != null && game.isLegal(point) ? () => c.move(point.notation) : null,
                child: Text(strings.place, maxLines: 1),
              ),
            ),
          ],
        );
      },
    );
  }
}
