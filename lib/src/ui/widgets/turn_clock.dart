import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

/// Online: the time the acting player has left, counting down by itself
/// (so nothing else rebuilds while it runs). A ring with the seconds in it
/// sits on the acting seat; a bar with the seconds goes in the decision
/// panel. Full until the actions before the turn have been shown, then
/// green, amber and, for the last quarter, red.
class TurnClock extends StatefulWidget {
  /// A ring of [size] (its diameter) with the seconds in the middle.
  const TurnClock.ring({super.key, required this.ends, required this.limit, required double this.size})
    : text = null,
      style = null;

  /// A bar, with [text] (the seconds left) above it.
  const TurnClock.bar({super.key, required this.ends, required this.limit, required this.text, this.style})
    : size = null;

  /// When the time runs out.
  final DateTime ends;

  /// The whole time to decide.
  final Duration limit;
  final double? size;
  final String Function(int seconds)? text;
  final TextStyle? style;

  @override
  State<TurnClock> createState() => _TurnClockState();
}

class _TurnClockState extends State<TurnClock> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  static Color _color(double left) => left > 0.5
      ? const Color(0xFF81C784)
      : left > 0.25
      ? const Color(0xFFFFCA28)
      : const Color(0xFFE57373);

  @override
  Widget build(BuildContext context) {
    final leftMs = max(0, widget.ends.difference(DateTime.now()).inMilliseconds);
    final limitMs = max(1, widget.limit.inMilliseconds);
    final left = min(1.0, leftMs / limitMs);
    final seconds = (min(leftMs, limitMs) / 1000).ceil();
    final color = _color(left);
    final size = widget.size;
    if (size != null) {
      return SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RingPainter(left: left, color: color),
          child: Center(
            child: Text(
              '$seconds',
              style: TextStyle(color: Colors.white, fontSize: size * 0.4, fontWeight: FontWeight.w700, height: 1),
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.text!(seconds), style: widget.style),
        const SizedBox(height: 2),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(value: left, minHeight: 4, color: color, backgroundColor: Colors.white12),
        ),
      ],
    );
  }
}

/// A dark disc with an arc for the time left, starting at the top.
class _RingPainter extends CustomPainter {
  _RingPainter({required this.left, required this.color});

  final double left;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.14;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawCircle(size.center(Offset.zero), size.width / 2, Paint()..color = const Color(0xEE15191C));
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = Colors.white12;
    canvas.drawArc(rect, 0, 2 * pi, false, track);
    canvas.drawArc(
      rect,
      -pi / 2,
      2 * pi * left,
      false,
      track
        ..color = color
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.left != left || old.color != color;
}
