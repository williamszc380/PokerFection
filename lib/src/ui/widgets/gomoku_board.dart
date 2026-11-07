import 'dart:math';

import 'package:flutter/material.dart';

import '../../app/app_settings.dart';
import '../../games/gomoku/rules.dart' show Stone;

// The engine's own stone colour, so the board and the game never need two
// Stone types side by side (Settings and Home use it through this file).
export '../../games/gomoku/rules.dart' show Stone;

/// How many of the coach's moves the board marks at most (the coach list
/// may show more rows).
const coachMarkLimit = 4;

/// A numbered disc on an empty point: the coach's top moves on the Gomoku
/// table (see [BoardMark.coach]: a gradient from the best, strongest, to
/// the 4th, faintest). Without a label it is a plain dot (a guide pointing
/// at a point).
class BoardMark {
  const BoardMark(
    this.label, {
    this.fill = const Color(0xE6FFFFFF),
    this.ink = const Color(0xFF1B1B1B),
    this.radius = 0.36,
    this.rim,
    this.labelSize = 0.42,
  });

  /// The coach's move of [rank] (0: the best), in [color] (the pick
  /// colour): the best one strongest (opaque, largest), each next one
  /// paler, more see-through and a little smaller, down to the 4th,
  /// faintest. A dark rim keeps every disc readable on any board and the
  /// number stays small and dark. Proofs keep their meaning: [proven] true
  /// (a proven win) gets a gold rim, the winning row's colour, at its
  /// rank's strength (the quicker win first, as the coach lists them);
  /// false (a proven loss) is a faint grey disc.
  factory BoardMark.coach(int rank, {required Color color, bool? proven}) {
    final t = coachFade(rank);
    final label = '${rank + 1}';
    if (proven == false) {
      return BoardMark(
        label,
        fill: const Color(0xFFB0B0B0).withValues(alpha: 0.42),
        ink: const Color(0xFF1B1B1B),
        radius: 0.28,
        rim: Colors.black.withValues(alpha: 0.3),
        labelSize: _coachLabel,
      );
    }
    return BoardMark(
      label,
      fill: Color.lerp(color, Colors.white, 0.5 * t)!.withValues(alpha: 1 - 0.55 * t),
      ink: const Color(0xFF1B1B1B),
      radius: 0.42 - 0.14 * t,
      rim: proven == true ? _provenWin : Colors.black.withValues(alpha: 0.75 - 0.45 * t),
      labelSize: _coachLabel,
    );
  }

  /// How faint the coach's move of [rank] is: 0 for the best, 1 for the
  /// 4th (the same scale however many are marked, so the 2nd move always
  /// looks the same).
  static double coachFade(int rank) => (rank / (coachMarkLimit - 1)).clamp(0.0, 1.0);

  static const _coachLabel = 0.36;
  static const _provenWin = Color(0xFFFFC107);

  final String label;
  final Color fill;
  final Color ink;

  /// The disc's radius, in cells.
  final double radius;

  /// A thin ring around the disc (null: none).
  final Color? rim;

  /// The number's size, in cells.
  final double labelSize;
}

/// A stone with a number on it: a forcing line previewed on the table
/// (see-through), or the moves of a guide's figure.
class BoardStone {
  const BoardStone(this.point, this.stone, [this.label]);

  final (int, int) point;
  final Stone stone;
  final String? label;
}

/// A Gomoku board, square, of any size: the board ([lines] by [lines]
/// grid lines, with their star points), the [stones] (by column and row,
/// from the top left, 0 to lines - 1), and a small red mark on the last
/// one played. The board and the stones follow the settings (Board &
/// Stones), unless given. Settings' previews, Home's emblem, the Gomoku
/// table and its guides use it.
///
/// For play it can also show the winning row, Renju's forbidden points (×),
/// a see-through stone where the player aims or hovers (with cross hairs
/// when aiming by touch), numbered discs (the coach's top moves, at most
/// [coachMarkLimit], see [BoardMark.coach]), numbered
/// stones (a line previewed, a guide's moves), a ring that singles out one
/// point (the grade card's best move, under the mouse), and the coordinates around
/// the edge ("a" to "o" along the bottom, 1 to 15 up the left side, as
/// Renju notation counts rows from the bottom).
class GomokuBoard extends StatelessWidget {
  const GomokuBoard({
    super.key,
    this.lines = 15,
    this.stones = const {},
    this.lastMove,
    this.boardStyle,
    this.stoneStyle,
    this.winLine = const [],
    this.forbidden = const [],
    this.marks = const {},
    this.sequence = const [],
    this.sequenceOpacity = 1,
    this.ghost,
    this.aim = false,
    this.spot,
    this.spotColor = const Color(0xFF29B6F6),
    this.coordinates = false,
    this.showStars = true,
  });

  final int lines;

  /// A new map for each change: the board repaints when it gets another one.
  final Map<(int, int), Stone> stones;
  final (int, int)? lastMove;
  final BoardStyle? boardStyle;
  final StoneStyle? stoneStyle;

  /// The stones of the winning row, lit with a line through them.
  final List<(int, int)> winLine;

  /// Points the player to move may not take (Renju), each crossed out.
  final List<(int, int)> forbidden;

  /// Numbered discs on empty points.
  final Map<(int, int), BoardMark> marks;

  /// Numbered stones over everything else, at [sequenceOpacity].
  final List<BoardStone> sequence;
  final double sequenceOpacity;

  /// A see-through stone: where the mouse is, or where the player aims.
  final BoardStone? ghost;

  /// The [ghost] is a touch aim: cross hairs show its row and column.
  final bool aim;

  /// A point singled out with a ring in [spotColor], drawn over a stone
  /// too: a move named somewhere else (the grade card's best move) may be
  /// taken by now, and it must still be found at a glance.
  final (int, int)? spot;
  final Color spotColor;

  /// Letters and numbers around the edge (the board shrinks to make room).
  final bool coordinates;

  /// The usual star points (a guide's small cut-out of a board has none).
  final bool showStars;

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.of(context);
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: GomokuBoardPainter(
          lines: lines,
          stones: stones,
          lastMove: lastMove,
          board: boardStyle ?? settings.board,
          stoneStyle: stoneStyle ?? settings.stones,
          winLine: winLine,
          forbidden: forbidden,
          marks: marks,
          sequence: sequence,
          sequenceOpacity: sequenceOpacity,
          ghost: ghost,
          aim: aim,
          spot: spot,
          spotColor: spotColor,
          coordinates: coordinates,
          showStars: showStars,
          labelStyle: DefaultTextStyle.of(context).style,
        ),
      ),
    );
  }
}

/// Where a board's points are drawn in a painted area: the largest square
/// that fits, centred, with each point in the middle of a square cell (so
/// the outer lines sit half a cell in from the edge). With [coordinates], a
/// band along the left and the bottom holds the labels.
class GomokuBoardGeometry {
  factory GomokuBoardGeometry(Size size, int lines, {bool coordinates = false}) {
    final side = max(0.0, min(size.width, size.height));
    final corner = Offset((size.width - side) / 2, (size.height - side) / 2);
    final cell = lines < 1 ? 0.0 : side / (lines + (coordinates ? band : 0));
    final left = coordinates ? cell * band : 0.0;
    return GomokuBoardGeometry._(corner, side, cell, corner + Offset(left + cell / 2, cell / 2), lines, coordinates);
  }

  GomokuBoardGeometry._(this.corner, this.side, this.cell, this.origin, this.lines, this.coordinates);

  /// The labels' band, in cells.
  static const band = 0.8;

  /// The board's top-left corner, its side, and one cell's side.
  final Offset corner;
  final double side;
  final double cell;

  /// The centre of point (0, 0), the top left one.
  final Offset origin;
  final int lines;
  final bool coordinates;

  /// The board's whole square.
  Rect get area => corner & Size.square(side);

  /// The centre of [point] (column, row from the top).
  Offset at((int, int) point) => origin + Offset(cell * point.$1, cell * point.$2);

  /// The point under [position], if it is on the board: the nearest one,
  /// within its cell.
  (int, int)? pointAt(Offset position) {
    if (cell <= 0) return null;
    final column = ((position.dx - origin.dx) / cell + 0.5).floor();
    final row = ((position.dy - origin.dy) / cell + 0.5).floor();
    if (column < 0 || row < 0 || column >= lines || row >= lines) return null;
    return (column, row);
  }
}

/// Paints a Gomoku board (see [GomokuBoard]) into the largest square that
/// fits, centered.
class GomokuBoardPainter extends CustomPainter {
  const GomokuBoardPainter({
    required this.lines,
    this.stones = const {},
    this.lastMove,
    required this.board,
    required this.stoneStyle,
    this.winLine = const [],
    this.forbidden = const [],
    this.marks = const {},
    this.sequence = const [],
    this.sequenceOpacity = 1,
    this.ghost,
    this.aim = false,
    this.spot,
    this.spotColor = const Color(0xFF29B6F6),
    this.coordinates = false,
    this.showStars = true,
    this.labelStyle,
  });

  final int lines;
  final Map<(int, int), Stone> stones;
  final (int, int)? lastMove;
  final BoardStyle board;
  final StoneStyle stoneStyle;
  final List<(int, int)> winLine;
  final List<(int, int)> forbidden;
  final Map<(int, int), BoardMark> marks;
  final List<BoardStone> sequence;
  final double sequenceOpacity;
  final BoardStone? ghost;
  final bool aim;
  final (int, int)? spot;
  final Color spotColor;
  final bool coordinates;
  final bool showStars;

  /// The app's text style, for the numbers and letters (its font).
  final TextStyle? labelStyle;

  static const _lastMoveColor = Color(0xFFE53935);
  static const _winColor = Color(0xFFFFC107);
  static const _forbiddenColor = Color(0xFFD32F2F);
  static const _aimColor = Color(0xFF29B6F6);

  /// The star points of a board with [lines] lines: the 4 corner ones and
  /// the center (and the edge midpoints from 19 lines on), as boards are
  /// usually printed; none on boards too small to have them.
  static List<(int, int)> starPoints(int lines) {
    if (lines < 7) return const [];
    final center = lines.isOdd ? lines ~/ 2 : null;
    if (lines < 9) return [if (center != null) (center, center)];
    final near = lines >= 13 ? 3 : 2, far = lines - 1 - near;
    return [
      for (final column in [near, far])
        for (final row in [near, far]) (column, row),
      if (center != null) (center, center),
      if (lines >= 19 && center != null) ...[(near, center), (far, center), (center, near), (center, far)],
    ];
  }

  /// The point under [position] (in the painted [size]), if it is on the
  /// board: the nearest one, within its cell.
  static (int, int)? pointAt(Offset position, Size size, int lines, {bool coordinates = false}) =>
      GomokuBoardGeometry(size, lines, coordinates: coordinates).pointAt(position);

  bool _on((int, int) p) => p.$1 >= 0 && p.$2 >= 0 && p.$1 < lines && p.$2 < lines;

  @override
  void paint(Canvas canvas, Size size) {
    final g = GomokuBoardGeometry(size, lines, coordinates: coordinates);
    if (g.side <= 0 || lines < 1) return;
    final area = g.area;
    canvas.drawRect(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [board.light, board.dark],
        ).createShader(area),
    );

    final cell = g.cell;
    final ink = Paint()
      ..color = board.lines.withValues(alpha: 0.85)
      ..strokeWidth = max(0.5, cell * 0.035);
    for (var i = 0; i < lines; i++) {
      canvas.drawLine(g.at((i, 0)), g.at((i, lines - 1)), ink);
      canvas.drawLine(g.at((0, i)), g.at((lines - 1, i)), ink);
    }
    if (showStars) {
      for (final point in starPoints(lines)) {
        canvas.drawCircle(g.at(point), max(1.0, cell * 0.11), Paint()..color = board.lines);
      }
    }
    if (coordinates) _coordinates(canvas, g);

    // Cross hairs under the stones, so the aimed row and column read at once.
    if (ghost case final ghost? when aim && _on(ghost.point)) {
      final hair = Paint()
        ..color = _aimColor.withValues(alpha: 0.7)
        ..strokeWidth = max(1.0, cell * 0.06);
      canvas.drawLine(g.at((ghost.point.$1, 0)), g.at((ghost.point.$1, lines - 1)), hair);
      canvas.drawLine(g.at((0, ghost.point.$2)), g.at((lines - 1, ghost.point.$2)), hair);
    }

    final radius = cell * 0.46;
    for (final MapEntry(key: point, value: stone) in stones.entries) {
      if (!_on(point)) continue;
      _stone(canvas, g.at(point), radius, stone);
    }
    if (lastMove case final last? when stones.containsKey(last)) {
      canvas.drawCircle(g.at(last), cell * 0.13, Paint()..color = _lastMoveColor);
    }

    // The winning row: a line through its stones and a ring on each.
    final win = [
      for (final p in winLine)
        if (_on(p)) p,
    ];
    if (win.length >= 2) {
      final glow = Paint()
        ..color = _winColor.withValues(alpha: 0.85)
        ..strokeWidth = max(2.0, cell * 0.14)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(g.at(win.first), g.at(win.last), glow);
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..color = _winColor
        ..strokeWidth = max(1.0, cell * 0.08);
      for (final p in win) {
        canvas.drawCircle(g.at(p), radius, ring);
      }
    }

    for (final p in forbidden) {
      if (!_on(p) || stones.containsKey(p)) continue;
      final c = g.at(p), r = cell * 0.24;
      final cross = Paint()
        ..color = _forbiddenColor
        ..strokeWidth = max(1.0, cell * 0.08)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(c - Offset(r, r), c + Offset(r, r), cross);
      canvas.drawLine(c + Offset(-r, r), c + Offset(r, -r), cross);
    }

    for (final MapEntry(key: point, value: mark) in marks.entries) {
      if (!_on(point) || stones.containsKey(point)) continue;
      final c = g.at(point);
      canvas.drawCircle(c, cell * mark.radius, Paint()..color = mark.fill);
      if (mark.rim case final rim?) {
        canvas.drawCircle(
          c,
          cell * mark.radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(1.0, cell * 0.06)
            ..color = rim,
        );
      }
      if (mark.label.isNotEmpty) {
        // Never below 7 pixels while the disc holds it (a phone's small board).
        final size = min(max(cell * mark.labelSize, 7.0), cell * mark.radius * 1.7);
        _label(canvas, c, mark.label, max(size, cell * mark.labelSize), mark.ink);
      }
    }

    if (ghost case final ghost? when _on(ghost.point) && !stones.containsKey(ghost.point)) {
      canvas.saveLayer(area, Paint()..color = Colors.white.withValues(alpha: 0.55));
      _stone(canvas, g.at(ghost.point), radius, ghost.stone);
      canvas.restore();
    }

    if (sequence.isNotEmpty) {
      final faded = sequenceOpacity < 1;
      if (faded) canvas.saveLayer(area, Paint()..color = Colors.white.withValues(alpha: sequenceOpacity));
      for (final s in sequence) {
        if (!_on(s.point)) continue;
        _stone(canvas, g.at(s.point), radius, s.stone);
        if (s.label case final label?) {
          _label(
            canvas,
            g.at(s.point),
            label,
            cell * (label.length > 1 ? 0.38 : 0.46),
            s.stone == Stone.black ? Colors.white : Colors.black,
          );
        }
      }
      if (faded) canvas.restore();
    }

    // Last, so nothing covers it: a ring just outside the stone, with a dark
    // edge so it reads on a light board and on a white stone alike.
    if (spot case final spot? when _on(spot)) {
      final c = g.at(spot), r = cell * 0.56;
      final width = max(2.0, cell * 0.12);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width + 2
          ..color = Colors.black.withValues(alpha: 0.55),
      );
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = spotColor,
      );
    }
  }

  void _coordinates(Canvas canvas, GomokuBoardGeometry g) {
    final cell = g.cell;
    final color = board.lines.withValues(alpha: 0.9);
    final band = cell * GomokuBoardGeometry.band;
    for (var i = 0; i < lines; i++) {
      // Columns a, b, c... along the bottom; rows 1, 2, 3... up the left.
      final column = g.at((i, lines - 1));
      _label(
        canvas,
        Offset(column.dx, g.corner.dy + g.side - band / 2),
        String.fromCharCode(97 + i),
        cell * 0.36,
        color,
      );
      final row = g.at((0, i));
      _label(canvas, Offset(g.corner.dx + band / 2, row.dy), '${lines - i}', cell * 0.36, color);
    }
  }

  void _label(Canvas canvas, Offset center, String text, double fontSize, Color color) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: labelStyle?.fontFamily,
          fontFamilyFallback: labelStyle?.fontFamilyFallback,
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
    painter.dispose();
  }

  void _stone(Canvas canvas, Offset center, double radius, Stone stone) {
    final black = stone == Stone.black;
    switch (stoneStyle) {
      case StoneStyle.glossy:
        canvas.drawCircle(
          center + Offset(radius * 0.08, radius * 0.14),
          radius,
          Paint()
            ..color = Colors.black.withValues(alpha: 0.35)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, max(0.5, radius * 0.12)),
        );
        final shine = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          radius: 1.0,
          colors: black
              ? const [Color(0xFF6E6E6E), Color(0xFF1C1C1C), Color(0xFF050505)]
              : const [Color(0xFFFFFFFF), Color(0xFFEDEDED), Color(0xFFB8B8B8)],
          stops: const [0, 0.5, 1],
        );
        canvas.drawCircle(
          center,
          radius,
          Paint()..shader = shine.createShader(Rect.fromCircle(center: center, radius: radius)),
        );
      case StoneStyle.flat:
        canvas.drawCircle(center, radius, Paint()..color = black ? const Color(0xFF151515) : const Color(0xFFF7F7F7));
        if (!black) {
          canvas.drawCircle(
            center,
            radius,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = max(0.5, radius * 0.07)
              ..color = Colors.black.withValues(alpha: 0.45),
          );
        }
    }
  }

  @override
  bool shouldRepaint(GomokuBoardPainter old) =>
      old.lines != lines ||
      old.stones != stones ||
      old.lastMove != lastMove ||
      old.board != board ||
      old.stoneStyle != stoneStyle ||
      old.winLine != winLine ||
      old.forbidden != forbidden ||
      old.marks != marks ||
      old.sequence != sequence ||
      old.sequenceOpacity != sequenceOpacity ||
      old.ghost?.point != ghost?.point ||
      old.ghost?.stone != ghost?.stone ||
      old.aim != aim ||
      old.spot != spot ||
      old.spotColor != spotColor ||
      old.coordinates != coordinates ||
      old.showStars != showStars ||
      old.labelStyle != labelStyle;
}
