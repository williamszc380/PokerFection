import 'dart:math';

import 'package:flutter/material.dart';

import '../../game/table_session.dart';
import '../format.dart';

/// A small pile of casino chips, optionally with the amount (in big blinds) beside it.
class ChipStack extends StatelessWidget {
  const ChipStack({super.key, required this.amount, required this.chipSize, this.showLabel = true});

  final int amount;
  final double chipSize;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final bb = amount / TableConfig.bigBlind;
    final count = (log(bb * 2 + 1) / ln2).round().clamp(1, 5);
    final color = _chipColor(bb);
    final pile = SizedBox(
      width: chipSize,
      height: chipSize + (count - 1) * chipSize * 0.16,
      child: Stack(
        children: [
          for (var i = 0; i < count; i++)
            Positioned(
              left: 0,
              bottom: i * chipSize * 0.16,
              child: CustomPaint(size: Size.square(chipSize), painter: _ChipPainter(color)),
            ),
        ],
      ),
    );
    if (!showLabel) return pile;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        pile,
        const SizedBox(width: 3),
        Container(
          padding: EdgeInsets.symmetric(horizontal: chipSize * 0.25, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(chipSize),
          ),
          child: Text(
            formatBb(amount),
            style: TextStyle(
              color: Colors.white,
              fontSize: chipSize * 0.62,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  static Color _chipColor(double bb) {
    if (bb < 1) return const Color(0xFFE0E0E0);
    if (bb < 5) return const Color(0xFFC62828);
    if (bb < 25) return const Color(0xFF2E7D32);
    if (bb < 100) return const Color(0xFF212121);
    return const Color(0xFF6A1B9A);
  }
}

class _ChipPainter extends CustomPainter {
  _ChipPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2;
    final light = color.computeLuminance() > 0.5;
    final stripe = light ? const Color(0xFF1565C0) : Colors.white;

    canvas.drawCircle(center.translate(0, r * 0.08), r, Paint()..color = Colors.black38);
    canvas.drawCircle(center, r, Paint()..color = color);
    // Edge stripes.
    final stripePaint = Paint()
      ..color = stripe
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.28;
    for (var i = 0; i < 6; i++) {
      final start = i * pi / 3;
      canvas.drawArc(Rect.fromCircle(center: center, radius: r * 0.84), start, pi / 9, false, stripePaint);
    }
    canvas.drawCircle(
      center,
      r * 0.55,
      Paint()
        ..color = stripe.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.08,
    );
  }

  @override
  bool shouldRepaint(_ChipPainter old) => old.color != color;
}
