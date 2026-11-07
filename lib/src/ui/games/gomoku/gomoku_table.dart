import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../games/gomoku/gomoku.dart';
import '../../widgets/gomoku_board.dart' show BoardMark, BoardStone, GomokuBoard, GomokuBoardGeometry, coachMarkLimit;

/// The board's point (column, row from the top) for an engine move. The
/// engine counts rows from the bottom ("h1" is on the bottom row), the
/// board widget from the top: every conversion goes through these two.
(int, int) boardPoint(GomokuMove move, int size) => (move.x, size - 1 - move.y);

/// The engine move for a board point (see [boardPoint]).
GomokuMove engineMove((int, int) point, int size) => GomokuMove(point.$1, size - 1 - point.$2);

/// Coordinates are drawn when a cell is at least this wide without them.
const gomokuCoordinatesFrom = 24.0;

/// The Gomoku table: the board with the game on it, where the player
/// places stones.
///
/// - With a mouse: a see-through stone follows the pointer over the points
///   the player may take (with a hand cursor), and a click places it.
/// - By touch: a tap aims (a see-through stone with cross hairs), a second
///   tap on the same point places it; a tap elsewhere moves the aim.
///
/// It also shows the last move, the winning row, Renju's forbidden points,
/// the coach's top moves (at most 4, numbered, in a gradient of the pick
/// colour from the best, strongest, to the 4th, faintest), and a
/// line previewed from the coach (numbered see-through stones), a ring on
/// one point named elsewhere (the grade card's best move, hovered), and in
/// a review the move made next (a plain see-through stone).
class GomokuTable extends StatefulWidget {
  const GomokuTable({
    super.key,
    required this.game,
    required this.player,
    required this.canPlay,
    required this.onPlace,
    required this.onAim,
    this.aim,
    this.coachMoves = const [],
    this.pick,
    this.proofs = const {},
    this.preview = const [],
    this.spot,
    this.next,
  });

  final GomokuGame game;

  /// The player's colour (the see-through stone's).
  final Stone player;

  /// It is the player's turn: points can be aimed at and taken.
  final bool canPlay;
  final ValueChanged<GomokuMove> onPlace;
  final ValueChanged<GomokuMove?> onAim;

  /// Where the player aims (touch, a coach row tapped, or the arrow keys).
  final GomokuMove? aim;

  /// The coach's moves, best first (the first [coachMarkLimit] are marked,
  /// strongest first; the coach list may show more).
  final List<GomokuMove> coachMoves;

  /// The coach's pick. It is the first of [coachMoves], drawn strongest, in
  /// the pick colour; kept for the callers that name it.
  final GomokuMove? pick;

  /// The coach's proofs, by move: true for a proven win (a gold rim), false
  /// for a proven loss (a faint grey disc). Moves left out are estimates.
  final Map<GomokuMove, bool> proofs;

  /// A line to preview, its first move by the side to move.
  final List<GomokuMove> preview;

  /// A point to single out with a ring in the pick colour, even if taken.
  final GomokuMove? spot;

  /// A review's next move, by the side to move: a see-through stone (while
  /// no line is previewed).
  final GomokuMove? next;

  @override
  State<GomokuTable> createState() => _GomokuTableState();
}

class _GomokuTableState extends State<GomokuTable> {
  (int, int)? _hover;
  GomokuGame? _forbiddenFor;
  List<(int, int)> _forbidden = const [];

  /// Renju's forbidden points for this position (worked out once per position).
  List<(int, int)> _forbiddenPoints(GomokuGame game) {
    if (!identical(_forbiddenFor, game)) {
      _forbiddenFor = game;
      final size = game.rules.size;
      _forbidden = [for (final m in game.forbiddenMoves()) boardPoint(m, size)];
    }
    return _forbidden;
  }

  void _hoverAt((int, int)? point) {
    if (point != _hover) setState(() => _hover = point);
  }

  bool _canTake((int, int)? point) {
    if (point == null || !widget.canPlay) return false;
    return widget.game.isLegal(engineMove(point, widget.game.rules.size));
  }

  void _tap(TapUpDetails details, GomokuBoardGeometry geometry) {
    final point = geometry.pointAt(details.localPosition);
    if (!_canTake(point)) return;
    final move = engineMove(point!, widget.game.rules.size);
    if (details.kind == PointerDeviceKind.mouse || widget.aim == move) {
      widget.onPlace(move);
    } else {
      widget.onAim(move);
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final size = game.rules.size;
    final primary = Theme.of(context).colorScheme.primary;
    final stones = <(int, int), Stone>{
      for (var x = 0; x < size; x++)
        for (var y = 0; y < size; y++)
          if (game.stoneAt(x, y) case final Stone stone) boardPoint(GomokuMove(x, y), size): stone,
    };
    final last = game.lastMove;
    final preview = [
      for (final m in widget.preview)
        if (!m.isPass) m,
    ];
    final marks = <(int, int), BoardMark>{
      if (preview.isEmpty)
        for (final (i, m) in widget.coachMoves.where((m) => !m.isPass).take(coachMarkLimit).indexed)
          boardPoint(m, size): BoardMark.coach(i, color: primary, proven: widget.proofs[m]),
    };
    final hoverPoint = _canTake(_hover) ? _hover : null;
    final aimPoint = widget.canPlay && widget.aim != null && !widget.aim!.isPass ? boardPoint(widget.aim!, size) : null;
    final ghostPoint = aimPoint ?? hoverPoint;
    return ColoredBox(
      color: const Color(0xFF0B0F12),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = constraints.biggest.shortestSide;
            final coordinates = side / size >= gomokuCoordinatesFrom;
            final geometry = GomokuBoardGeometry(Size.square(side), size, coordinates: coordinates);
            final forbidden = _forbiddenPoints(game);
            final hoverForbidden = widget.canPlay && _hover != null && forbidden.contains(_hover);
            return Center(
              child: SizedBox.square(
                dimension: side,
                child: MouseRegion(
                  cursor: hoverPoint != null
                      ? SystemMouseCursors.click
                      : (hoverForbidden ? SystemMouseCursors.forbidden : MouseCursor.defer),
                  onEnter: (event) => _hoverAt(geometry.pointAt(event.localPosition)),
                  onHover: (event) => _hoverAt(geometry.pointAt(event.localPosition)),
                  onExit: (_) => setState(() => _hover = null),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) => _tap(details, geometry),
                    child: GomokuBoard(
                      key: const ValueKey('gomoku board'),
                      lines: size,
                      stones: stones,
                      lastMove: last == null || last.isPass ? null : boardPoint(last, size),
                      winLine: [for (final m in game.result?.line ?? const <GomokuMove>[]) boardPoint(m, size)],
                      forbidden: forbidden,
                      marks: marks,
                      sequence: [
                        for (final (i, m) in preview.indexed)
                          BoardStone(boardPoint(m, size), i.isEven ? game.toMove : game.toMove.opponent, '${i + 1}'),
                        if (widget.next case final next? when preview.isEmpty && !next.isPass)
                          BoardStone(boardPoint(next, size), game.toMove),
                      ],
                      sequenceOpacity: 0.72,
                      ghost: ghostPoint == null ? null : BoardStone(ghostPoint, widget.player),
                      aim: aimPoint != null,
                      spot: widget.spot == null || widget.spot!.isPass ? null : boardPoint(widget.spot!, size),
                      spotColor: primary,
                      coordinates: coordinates,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
