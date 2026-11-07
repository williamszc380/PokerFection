import 'dart:math';

import 'package:flutter/material.dart';

import '../../app/app_settings.dart';

/// A card table: a rounded wooden rail around felt in the colours chosen in
/// Settings (poker's radial gradient), with [child] on top. The card
/// games put their seats and played cards in it.
class FeltArea extends StatelessWidget {
  const FeltArea({super.key, this.child, this.padding = const EdgeInsets.all(6), this.felt});

  final Widget? child;

  /// Space around the rail.
  final EdgeInsets padding;

  /// The felt's colours (null: as set in Settings).
  final FeltStyle? felt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: CustomPaint(
        painter: FeltPainter(felt ?? AppSettings.of(context).felt),
        child: Padding(padding: const EdgeInsets.all(10), child: child),
      ),
    );
  }
}

/// Paints [FeltArea]'s rail and cloth.
class FeltPainter extends CustomPainter {
  FeltPainter(this.felt);

  final FeltStyle felt;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = min(size.shortestSide * 0.18, 60.0);
    final rail = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    canvas.drawRRect(
      rail.shift(const Offset(0, 4)),
      Paint()
        ..color = Colors.black54
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawRRect(
      rail,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF6D4C41), Color(0xFF3E2723)],
        ).createShader(rail.outerRect),
    );
    final cloth = rail.deflate(7);
    canvas.drawRRect(
      cloth,
      Paint()
        ..shader = RadialGradient(
          radius: 0.8,
          colors: [felt.center, felt.middle, felt.edge],
          stops: const [0, 0.65, 1],
        ).createShader(cloth.outerRect),
    );
    canvas.drawRRect(
      cloth.deflate(10),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.08),
    );
  }

  @override
  bool shouldRepaint(FeltPainter oldDelegate) => oldDelegate.felt != felt;
}
