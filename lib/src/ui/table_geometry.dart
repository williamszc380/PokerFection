import 'dart:math';

import 'package:flutter/widgets.dart';

import 'table_view_state.dart';
import 'widgets/card_view.dart' show cardAspectRatio;

/// Where everything goes on the table, for a given screen area.
///
/// Seats sit on an oval that stretches to fill the space, so the same code
/// works on a tall phone screen and a wide desktop window. The user's seat
/// (seat 0) is at the bottom; the other seats follow clockwise.
class TableGeometry {
  TableGeometry(this.size, this.seatCount) {
    scale = min(size.width / 520, size.height / 470).clamp(0.62, 1.5);
    final yTop = 6 + seatCardsAbove + seatBoxSize.height / 2;
    final yBottom = size.height - 6 - seatBoxSize.height / 2 - pillHeight / 2;
    center = Offset(size.width / 2, (yTop + yBottom) / 2);
    radiusX = max(size.width / 2 - seatBoxSize.width / 2 - 6, 40.0);
    radiusY = max((yBottom - yTop) / 2, 40.0);
  }

  final Size size;
  final int seatCount;
  late final double scale;
  late final Offset center;
  late final double radiusX;
  late final double radiusY;

  double get cardWidth => 40 * scale;
  double get cardHeight => cardWidth * cardAspectRatio;
  double get heroCardWidth => cardWidth * 1.2;
  double get chipSize => 16 * scale;
  Size get seatBoxSize => Size(100 * scale, 54 * scale);
  double get pillHeight => 20 * scale;

  /// How far a seat's cards stick out above its info box.
  double get seatCardsAbove => heroCardWidth * cardAspectRatio * 0.72;

  double get _boardGap => 5 * scale;

  /// Center of a seat's info box.
  Offset seat(int i) {
    final angle = pi / 2 + i * 2 * pi / seatCount;
    return center + Offset(radiusX * cos(angle), radiusY * sin(angle));
  }

  /// Center of a seat's cards.
  Offset seatCards(int i) =>
      seat(i) - Offset(0, seatBoxSize.height / 2 + seatCardsAbove * 0.3);

  Rect get boardRect => Rect.fromCenter(
        center: center,
        width: 5 * cardWidth + 4 * _boardGap,
        height: cardHeight,
      );

  /// Center of board card [slot] (0-4).
  Offset boardSlot(int slot) =>
      center + Offset((slot - 2) * (cardWidth + _boardGap), 0);

  Offset get pot => center - Offset(0, cardHeight / 2 + 22 * scale);

  Offset get deck => center;

  /// Where a seat's bet sits: just outside the seat (its cards, info box and
  /// action label) on the way to the middle, kept clear of the board.
  Offset bet(int i) {
    final s = seat(i);
    final toCenter = center - s;
    final distance = toCenter.distance;
    if (distance == 0) return s;
    final d = toCenter / distance;
    // How far along that direction the seat's own widgets reach.
    final halfWidth = seatBoxSize.width / 2 + 4 * scale;
    final above = seatBoxSize.height / 2 + seatCardsAbove;
    final below = seatBoxSize.height / 2 + pillHeight / 2;
    final exitX = d.dx == 0 ? double.infinity : halfWidth / d.dx.abs();
    final exitY = d.dy == 0 ? double.infinity : (d.dy < 0 ? above : below) / d.dy.abs();
    final along = min(min(exitX, exitY) + chipSize * 1.4, distance * 0.85);
    var b = s + d * along;
    final zone = boardRect.inflate(14 * scale).expandToInclude(
          Rect.fromCenter(center: pot, width: 60 * scale, height: 24 * scale),
        );
    if (zone.contains(b)) {
      b = Offset(b.dx, s.dy < center.dy - 1 ? zone.top - 10 * scale : zone.bottom + 12 * scale);
    }
    return b;
  }

  /// Where the dealer button sits for a seat.
  Offset dealerButton(int i) {
    final s = seat(i);
    final toCenter = center - s;
    final distance = toCenter.distance;
    final dir = distance == 0 ? const Offset(0, -1) : toCenter / distance;
    final side = Offset(-dir.dy, dir.dx);
    return s + dir * (seatBoxSize.height * 0.5 + 12 * scale) + side * (seatBoxSize.width * 0.74);
  }

  Offset resolve(Anchor anchor) => switch (anchor.kind) {
        AnchorKind.seat => seat(anchor.index),
        AnchorKind.seatCards => seatCards(anchor.index),
        AnchorKind.bet => bet(anchor.index),
        AnchorKind.pot => pot,
        AnchorKind.deck => deck,
        AnchorKind.board => boardSlot(anchor.index),
      };
}
