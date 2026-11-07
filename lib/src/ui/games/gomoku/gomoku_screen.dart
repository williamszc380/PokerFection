import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_settings.dart';
import '../../../games/gomoku/app/gomoku_record.dart';
import '../../../games/gomoku/gomoku.dart';
import '../../../l10n/strings.dart';
import '../../kit/coach_panel.dart';
import '../../kit/game_scaffold.dart';
import '../../kit/kit_scope.dart';
import '../../table_controller.dart' show PlaybackSpeed;
import 'gomoku_coach_view.dart';
import 'gomoku_controller.dart';
import 'gomoku_table.dart';
import 'l10n/gomoku_strings.dart';

/// A game of Gomoku against a bot, on the kit's scaffold: the board on the
/// left (on top in a browser held upright), the panel on the right with
/// whose turn it is, the last move's grade, the coach's moves, the two
/// players and the buttons. There is no Undo.
class GomokuScreen extends StatefulWidget {
  const GomokuScreen({
    super.key,
    this.options = const GomokuOptions(),
    this.toggles = const {},
    this.opening = const [],
  });

  /// The setup's choices.
  final GomokuOptions options;

  /// The last game's toggles ('coach'), for the first game here.
  final Map<String, Object?> toggles;

  /// Moves already on the board (tests use it to reach a position quickly).
  final List<String> opening;

  @override
  State<GomokuScreen> createState() => _GomokuScreenState();
}

class _GomokuScreenState extends State<GomokuScreen> {
  late final GomokuController _controller;
  var _speed = PlaybackSpeed.normal;

  /// Where the player aims (touch, a coach row tapped once, the arrow
  /// keys); its coach row is lit.
  GomokuMove? _aim;

  /// The coach row under the mouse: its line shows on the board.
  String? _preview;

  /// The grade card's "Best move: x" under the mouse (the kit's own hover
  /// for it, CoachLook.onPickHover): x was best in the position the card
  /// graded, before the bot's reply, so it gets a ring of its own and never
  /// borrows a line from the coach's moves now. The card stays through the
  /// bot's reply, and so does the ring; the kit ends the hover when the
  /// card goes.
  String? _cardSpot;
  int _moves = 0;

  @override
  void initState() {
    super.initState();
    final scope = KitScope.of(context);
    _controller = GomokuController(
      options: widget.options,
      jobs: scope.newJobs(),
      lastGames: scope.lastGames,
      speed: () => _speed,
      toggles: widget.toggles,
      opening: widget.opening,
    );
    // Listened to only after the deal: its first notice comes while this
    // state is still being made, and the first build shows the deal anyway.
    _controller.newGame();
    _moves = _controller.record.moves.length;
    _controller.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _speed = AppSettings.of(context).speed;
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      // A move was made: the aim and a coach row's preview belonged to the
      // position before.
      final moves = _controller.started ? _controller.record.moves.length : 0;
      if (moves != _moves) {
        _moves = moves;
        _aim = null;
        _preview = null;
      }
    });
  }

  bool get _playerToMove {
    final c = _controller;
    final seat = c.started && !c.isOver ? c.seatToAct : null;
    return seat != null && c.isHuman(seat);
  }

  bool get _coachShows => _controller.training && _controller.coachVisible && _playerToMove;

  void _place(GomokuMove move) {
    if (!_playerToMove || !_controller.game.isLegal(move)) return;
    _controller.humanMove(move.notation);
  }

  /// Aims at [move]; whatever was chosen in the coach list before (a
  /// pass) is dropped, so Enter places the stone aimed at.
  void _aimAt(GomokuMove? move) {
    _controller.choose(null);
    setState(() => _aim = move);
  }

  /// The arrow keys move the aim (from the last stone, or the centre).
  void _nudge(int dx, int dy) {
    if (!_playerToMove) return;
    final size = _controller.game.rules.size;
    final from =
        _aim ?? _controller.game.moves.lastWhere((m) => !m.isPass, orElse: () => GomokuMove(size ~/ 2, size ~/ 2));
    _aimAt(GomokuMove((from.x + dx).clamp(0, size - 1), (from.y + dy).clamp(0, size - 1)));
  }

  void _enter() {
    if (_controller.isOver) {
      _controller.newGame();
    } else if (_aim case final aim?) {
      _place(aim);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = GomokuStrings.of(context);
    final c = _controller;
    final game = c.game;
    final analysis = _coachShows ? c.analysis : null;
    final previewLine = switch ((analysis, _preview)) {
      (final a?, final move?) => a.of(GomokuMove.parse(move))?.line ?? const <GomokuMove>[],
      _ => const <GomokuMove>[],
    };
    return GameScaffold(
      title: S.of(context).gomoku,
      strings: strings,
      controller: c,
      squareTable: true,
      table: GomokuTable(
        game: game,
        player: c.playerColor,
        canPlay: _playerToMove,
        aim: _aim,
        onAim: _aimAt,
        onPlace: _place,
        coachMoves: [for (final m in analysis?.moves ?? const <MoveAnalysis>[]) m.move],
        pick: analysis?.best?.move,
        proofs: {
          for (final m in analysis?.moves ?? const <MoveAnalysis>[])
            if (m.isProvenWin || m.isProvenLoss) m.move: m.isProvenWin,
        },
        preview: previewLine,
        spot: _cardSpot == null ? null : GomokuMove.parse(_cardSpot!),
      ),
      panel: _panel(strings),
      status: gomokuPositionProof(strings, analysis),
      coachExtras: [if (previewLine.length > 1) GomokuLineText(line: previewLine, strings: strings)],
      look: gomokuCoachLook(
        strings,
        onHover: (move) {
          if (mounted && move != _preview) setState(() => _preview = move);
        },
        onPickHover: (move) {
          if (mounted && move != _cardSpot) setState(() => _cardSpot = move);
        },
        // One click selects (a point is aimed at, a pass lights its
        // button), a double click places: never a stone on one click.
        onSelect: (move) {
          final m = GomokuMove.parse(move);
          if (m.isPass) {
            c.choose(move);
          } else if (game.isLegal(m)) {
            _aimAt(m);
          }
        },
        onPlay: (move) => _place(GomokuMove.parse(move)),
        selected: _aim?.notation,
      ),
      shortcuts: {
        const SingleActivator(LogicalKeyboardKey.enter): _enter,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _nudge(-1, 0),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _nudge(1, 0),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _nudge(0, 1),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _nudge(0, -1),
      },
    );
  }

  /// The players with their colours, then Place (and Pass under Renju):
  /// on one row on a sideways phone, where height is short (then only the
  /// player's colour), on two rows otherwise.
  Widget _panel(GomokuStrings strings) {
    final c = _controller;
    final game = c.game;
    final canPlay = _playerToMove;
    final aim = _aim;
    final screen = MediaQuery.sizeOf(context);
    final oneRow = screen.width >= screen.height && screen.height < 420;
    const tight = EdgeInsets.symmetric(horizontal: 12);
    // On one row only the player's own colour fits beside the buttons (the
    // status line names the bot while it thinks).
    final tags = [
      if (c.started)
        for (final seat in [0, 1])
          if (!oneRow || c.isHuman(seat))
            Expanded(
              child: GomokuPlayerTag(
                color: GomokuRecord.colorOf(seat),
                name: c.isHuman(seat) ? strings.you : c.seatName(seat),
                toMove: !c.isOver && c.seatToAct == seat,
              ),
            ),
    ];
    // On one row the buttons take what their words need and the players
    // share the rest; on two rows the buttons share the width.
    Widget sized(Widget button) => oneRow ? button : Expanded(child: button);
    final buttons = [
      if (game.rules.winRule == WinRule.renju) ...[
        sized(
          // Lit while the coach list's Pass row is selected.
          ChosenRing(
            lit: c.chosen == GomokuMove.pass.notation,
            child: OutlinedButton(
              key: const ValueKey('pass'),
              // A solid fill while lit: the ring's glow, drawn behind the
              // button, would wash out a clear one.
              style: OutlinedButton.styleFrom(
                padding: tight,
                backgroundColor: c.chosen == GomokuMove.pass.notation ? const Color(0xFF1F2A2F) : null,
              ),
              onPressed: canPlay && game.mustPass ? () => _place(GomokuMove.pass) : null,
              child: Text(strings.pass, maxLines: 1),
            ),
          ),
        ),
        const SizedBox(width: 6),
      ],
      sized(
        FilledButton(
          key: const ValueKey('place'),
          style: FilledButton.styleFrom(padding: tight),
          onPressed: canPlay && aim != null && game.isLegal(aim) ? () => _place(aim) : null,
          child: Text(strings.place, maxLines: 1),
        ),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
      child: oneRow
          ? Row(children: [...tags, const SizedBox(width: 4), ...buttons])
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: tags),
                const SizedBox(height: 6),
                Row(children: buttons),
              ],
            ),
    );
  }
}

/// A player's stone colour and name; the one to move is lit. The room's
/// table shows the same tags, with each seat's wins ([score]).
class GomokuPlayerTag extends StatelessWidget {
  const GomokuPlayerTag({super.key, required this.color, required this.name, required this.toMove, this.score});

  final Stone color;
  final String name;
  final bool toMove;

  /// After the name, muted (the room's seat score); none in a solo game.
  final String? score;

  @override
  Widget build(BuildContext context) {
    final black = color == Stone.black;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: toMove ? Colors.white.withValues(alpha: 0.10) : null,
        border: Border.all(color: toMove ? Theme.of(context).colorScheme.primary : Colors.white12),
      ),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: black ? const Color(0xFF151515) : const Color(0xFFF2F2F2),
              border: Border.all(color: black ? Colors.white54 : Colors.black45),
            ),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: toMove ? FontWeight.w700 : FontWeight.w400),
            ),
          ),
          if (score case final score?) ...[
            const SizedBox(width: 5),
            Text(
              score,
              style: const TextStyle(color: Colors.white60, fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ],
        ],
      ),
    );
  }
}
