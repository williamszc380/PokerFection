import 'dart:math';

import 'package:flutter/material.dart';

import '../../app/app_settings.dart';
import '../../engine/cards.dart';

const cardAspectRatio = 1.4;

/// A playing card. Shows the back when [card] is null or [faceUp] is false,
/// and flips over when that changes. The back and the suit colors follow
/// the settings, unless given.
class CardView extends StatelessWidget {
  const CardView({super.key, required this.width, this.card, this.faceUp = true, this.backStyle, this.faceStyle});

  final double width;
  final PlayingCard? card;
  final bool faceUp;
  final CardBackStyle? backStyle;
  final CardFaceStyle? faceStyle;

  @override
  Widget build(BuildContext context) {
    final showFace = faceUp && card != null;
    final settings = AppSettings.of(context);
    return SizedBox(
      width: width,
      height: width * cardAspectRatio,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        transitionBuilder: _flip,
        layoutBuilder: (current, previous) => Stack(children: [...previous, ?current]),
        child: showFace
            ? _CardFace(
                key: ValueKey(card!.index),
                card: card!,
                width: width,
                style: faceStyle ?? settings.cardFaces,
              )
            : _CardBack(key: const ValueKey('back'), width: width, style: backStyle ?? settings.cardBack),
      ),
    );
  }

  static Widget _flip(Widget child, Animation<double> animation) {
    final rotation = Tween(begin: pi, end: 0.0).animate(animation);
    return AnimatedBuilder(
      animation: rotation,
      child: child,
      builder: (context, child) {
        final angle = rotation.value;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0015)
            ..rotateY(angle),
          // Each side is only drawn while it faces the viewer.
          child: Opacity(opacity: angle <= pi / 2 ? 1 : 0, child: child),
        );
      },
    );
  }
}

class _CardFace extends StatelessWidget {
  const _CardFace({super.key, required this.card, required this.width, required this.style});

  final PlayingCard card;
  final double width;
  final CardFaceStyle style;

  @override
  Widget build(BuildContext context) {
    final color = style.ink(card.suit);
    final colored = style == CardFaceStyle.colored;
    return Container(
      width: width,
      height: width * cardAspectRatio,
      decoration: BoxDecoration(
        color: style.face(card.suit),
        borderRadius: BorderRadius.circular(width * 0.1),
        // Colored cards get a white edge so they stand out on the felt.
        border: colored
            ? Border.all(color: Colors.white, width: max(1, width * 0.03))
            : Border.all(color: Colors.black26, width: 0.5),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: Stack(
        children: [
          Positioned(
            left: width * 0.08,
            top: width * 0.02,
            child: Column(
              children: [
                Text(
                  card.rankLabel,
                  style: TextStyle(
                    color: color,
                    fontSize: width * 0.38,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    letterSpacing: card.rank == 8 ? -width * 0.04 : 0,
                  ),
                ),
                SuitIcon(suit: card.suit, size: width * 0.26, color: color),
              ],
            ),
          ),
          Positioned(
            right: width * 0.08,
            bottom: width * 0.08,
            child: SuitIcon(suit: card.suit, size: width * 0.5, color: color),
          ),
        ],
      ),
    );
  }
}

class _CardBack extends StatelessWidget {
  const _CardBack({super.key, required this.width, required this.style});

  final double width;
  final CardBackStyle style;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(width * 0.1);
    return Container(
      width: width,
      height: width * cardAspectRatio,
      padding: EdgeInsets.all(width * 0.07),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: radius,
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width * 0.06),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [style.light, style.dark],
          ),
        ),
        child: CustomPaint(painter: _BackPatternPainter(), size: Size.infinite),
      ),
    );
  }
}

class _BackPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final step = size.width / 4;
    for (var x = -size.height; x < size.width + size.height; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), paint);
      canvas.drawLine(Offset(x + size.height, 0), Offset(x, size.height), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A suit symbol drawn with shapes, so it looks the same on every platform.
class SuitIcon extends StatelessWidget {
  const SuitIcon({super.key, required this.suit, required this.size, required this.color});

  /// 0 clubs, 1 diamonds, 2 hearts, 3 spades.
  final int suit;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _SuitPainter(suit, color));
}

class _SuitPainter extends CustomPainter {
  _SuitPainter(this.suit, this.color);

  final int suit;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    // Each shape is drawn on its own: overlapping shapes in one path could
    // cancel each other out and leave holes.
    void circle(double x, double y, double r) =>
        canvas.drawCircle(Offset(x * w, y * h), r * w, paint);
    void polygon(List<(double, double)> points) {
      final path = Path()..moveTo(points.first.$1 * w, points.first.$2 * h);
      for (final (x, y) in points.skip(1)) {
        path.lineTo(x * w, y * h);
      }
      canvas.drawPath(path..close(), paint);
    }

    switch (suit) {
      case 0: // clubs
        circle(0.5, 0.28, 0.21);
        circle(0.27, 0.58, 0.21);
        circle(0.73, 0.58, 0.21);
        circle(0.5, 0.5, 0.12);
        polygon([(0.5, 0.5), (0.64, 0.98), (0.36, 0.98)]);
      case 1: // diamonds
        polygon([(0.5, 0), (0.9, 0.5), (0.5, 1), (0.1, 0.5)]);
      case 2: // hearts
        circle(0.28, 0.33, 0.25);
        circle(0.72, 0.33, 0.25);
        polygon([(0.04, 0.42), (0.96, 0.42), (0.5, 0.95)]);
      default: // spades
        circle(0.28, 0.58, 0.23);
        circle(0.72, 0.58, 0.23);
        polygon([(0.06, 0.5), (0.94, 0.5), (0.5, 0.02)]);
        polygon([(0.5, 0.6), (0.64, 0.98), (0.36, 0.98)]);
    }
  }

  @override
  bool shouldRepaint(_SuitPainter old) => old.suit != suit || old.color != color;
}
