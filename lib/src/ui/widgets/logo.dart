import 'dart:math';

import 'package:flutter/material.dart';

/// Gold used for the P and F of the logo.
const logoGold = Color(0xFFFFC107);

/// The logo mark: a casino chip with "PF" in gold. The letters are drawn as
/// shapes (not a font), so the logo and the app icons made from it look the
/// same everywhere.
class LogoMark extends StatelessWidget {
  const LogoMark({super.key, required this.size, this.name = false});

  final double size;

  /// Write "Poker" and "Fection" on two lines instead of "PF".
  final bool name;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: LogoPainter(name: name, fontFamily: DefaultTextStyle.of(context).style.fontFamily),
      );
}

/// Paints the chip with "PF". With [background], fills the whole square
/// first and draws the chip a little smaller (for app icons that can't be
/// see-through). [chip] is the chip's diameter as a share of the square.
class LogoPainter extends CustomPainter {
  const LogoPainter({this.background, this.chip, this.name = false, this.fontFamily});

  final Color? background;
  final double? chip;

  /// "Poker" and "Fection" on two lines (P and F in gold) instead of "PF".
  final bool name;
  final String? fontFamily;

  @override
  void paint(Canvas canvas, Size size) {
    final side = min(size.width, size.height);
    final center = size.center(Offset.zero);
    if (background != null) {
      canvas.drawRect(Offset.zero & size, Paint()..color = background!);
    }
    final r = side / 2 * (chip ?? (background == null ? 0.96 : 0.84));

    // Shadow, then the chip's body.
    canvas.drawCircle(
      center + Offset(0, r * 0.04),
      r,
      Paint()
        ..color = Colors.black54
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.05),
    );
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFE53935), Color(0xFFB71C1C), Color(0xFF7F0000)],
          stops: [0, 0.7, 1],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );

    // White inserts around the edge, like a casino chip.
    final insert = Paint()..color = const Color(0xFFF5F5F5);
    const inserts = 8, span = pi / 11;
    for (var i = 0; i < inserts; i++) {
      final a = i * 2 * pi / inserts;
      final path = Path()
        ..arcTo(Rect.fromCircle(center: center, radius: r * 0.98), a - span / 2, span, true)
        ..arcTo(Rect.fromCircle(center: center, radius: r * 0.76), a + span / 2, -span, false)
        ..close();
      canvas.drawPath(path, insert);
    }

    // Gold ring, then the dark center.
    canvas.drawCircle(
      center,
      r * 0.69,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.035
        ..color = logoGold,
    );
    canvas.drawCircle(
      center,
      r * 0.64,
      Paint()
        ..shader = const RadialGradient(colors: [Color(0xFF263238), Color(0xFF0E1417)])
            .createShader(Rect.fromCircle(center: center, radius: r * 0.64)),
    );

    if (name) {
      _paintName(canvas, center, r);
    } else {
      _paintLetters(canvas, center, r * 0.62);
    }
  }

  /// "Poker" over "Fection", centered in the dark middle of a chip of radius [r].
  void _paintName(Canvas canvas, Offset center, double r) {
    List<TextPainter> layout(double size) => [
          for (final (first, rest) in const [('P', 'oker'), ('F', 'ection')])
            TextPainter(text: _word(first, rest, size), textDirection: TextDirection.ltr)..layout(),
        ];
    // As big as fits inside the dark middle.
    var lines = layout(r * 0.26);
    final widest = lines.fold(0.0, (w, line) => max(w, line.width));
    if (widest > r * 1.02) {
      final fitted = r * 0.26 * r * 1.02 / widest;
      for (final line in lines) {
        line.dispose();
      }
      lines = layout(fitted);
    }
    final height = lines.fold(0.0, (h, line) => h + line.height);
    var y = center.dy - height / 2;
    for (final line in lines) {
      line.paint(canvas, Offset(center.dx - line.width / 2, y));
      y += line.height;
      line.dispose();
    }
  }

  TextSpan _word(String first, String rest, double size) => TextSpan(children: [
          TextSpan(
            text: first,
            style: TextStyle(
              color: logoGold,
              fontSize: size * 1.3,
              fontWeight: FontWeight.w900,
              height: 1.05,
              fontFamily: fontFamily,
            ),
          ),
          TextSpan(
            text: rest,
            style: TextStyle(
              color: Colors.white,
              fontSize: size,
              fontWeight: FontWeight.w700,
              height: 1.05,
              fontFamily: fontFamily,
            ),
          ),
        ]);

  /// "PF" in a box 1.14 wide and 1 high (in units of [height]), centered.
  void _paintLetters(Canvas canvas, Offset center, double height) {
    const w = 0.2; // stroke
    final left = center.dx - 1.14 / 2 * height, top = center.dy - height / 2;
    Rect box(double x0, double y0, double x1, double y1) =>
        Rect.fromLTRB(left + x0 * height, top + y0 * height, left + x1 * height, top + y1 * height);
    final gold = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFE082), logoGold, Color(0xFFFFA000)],
      ).createShader(box(0, 0, 1.14, 1));

    // P: stem, and a bowl made of a thick stroke.
    canvas.drawRect(box(0, 0, w, 1), gold);
    const bowlRadius = 0.2, bowlRight = 0.54;
    final arcCenterX = bowlRight - w / 2 - bowlRadius;
    final bowl = Path()
      ..moveTo(left + w / 2 * height, top + w / 2 * height)
      ..lineTo(left + arcCenterX * height, top + w / 2 * height)
      ..arcTo(
        Rect.fromCircle(
          center: Offset(left + arcCenterX * height, top + (w / 2 + bowlRadius) * height),
          radius: bowlRadius * height,
        ),
        -pi / 2,
        pi,
        false,
      )
      ..lineTo(left + w / 2 * height, top + (w / 2 + 2 * bowlRadius) * height);
    canvas.drawPath(
      bowl,
      Paint()
        ..shader = gold.shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * height
        ..strokeJoin = StrokeJoin.miter,
    );

    // F: stem, top bar, middle bar.
    const f = 0.66;
    canvas.drawRect(box(f, 0, f + w, 1), gold);
    canvas.drawRect(box(f, 0, 1.14, w), gold);
    canvas.drawRect(box(f, 0.42, 1.06, 0.42 + w), gold);
  }

  @override
  bool shouldRepaint(LogoPainter old) =>
      old.background != background || old.chip != chip || old.name != name || old.fontFamily != fontFamily;
}
