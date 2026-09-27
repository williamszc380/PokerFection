import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A bar split into colored parts that add up to 100%, with a handle at the
/// right end of every part but the last. Dragging a handle moves the border
/// between two parts, in whole percents, pushing the handles in its way.
///
/// The first [upper] handles sit above the bar and the rest below it; the
/// ones below can't push the ones above. Handles in the same place are
/// stacked with the earlier part's on top, and that's the one a drag picks
/// up: from 100% for one part, moving its handle uncovers the next part's
/// handle, and so on.
class MixSlider extends StatefulWidget {
  const MixSlider({
    super.key,
    required this.colors,
    required this.shares,
    required this.upper,
    required this.onChanged,
  });

  /// Each part's color, in order.
  final List<Color> colors;

  /// Each part's share in percent (adding up to 100).
  final List<double> shares;

  /// How many handles, from the left, sit above the bar.
  final int upper;

  /// Called with the new shares while a handle is dragged.
  final ValueChanged<List<double>> onChanged;

  @override
  State<MixSlider> createState() => _MixSliderState();
}

class _MixSliderState extends State<MixSlider> {
  /// How far (px) from a handle's center a drag still picks it up.
  static const _reach = 24.0;

  int? _hovered;
  int? _dragged;

  /// Where the handles were when the drag started: pushed handles go back
  /// if the drag does.
  List<double> _start = const [];
  double _startX = 0;
  double _lastTo = 0;

  double get _width => context.size?.width ?? 0;

  bool _isUpper(int handle) => handle < widget.upper;

  /// Where each handle is (percent from the left): the running totals of the shares.
  List<double> get _handles {
    var total = 0.0;
    return [
      for (var i = 0; i < widget.shares.length - 1; i++) (total += widget.shares[i]).clamp(0.0, 100.0),
    ];
  }

  /// The handle a pointer at [position] picks up: the nearest one within
  /// reach on its side of the bar (or else the other side), and of stacked
  /// ones, the one on top (the earliest).
  int? _handleAt(Offset position) {
    final handles = _handles;
    int? nearestOn({required bool upper}) {
      int? found;
      var nearest = _reach;
      for (var k = 0; k < handles.length; k++) {
        if (_isUpper(k) != upper) continue;
        final distance = (_MixPainter.x(_width, handles[k]) - position.dx).abs();
        if (distance < nearest - 0.5) {
          found = k;
          nearest = distance;
        }
      }
      return found;
    }

    final above = position.dy < (context.size?.height ?? 0) / 2;
    return nearestOn(upper: above) ?? nearestOn(upper: !above);
  }

  void _startDrag(DragStartDetails details) {
    final k = _handleAt(details.localPosition);
    if (k == null) return;
    setState(() {
      _dragged = k;
      _start = _handles;
      _startX = details.localPosition.dx;
      _lastTo = _start[k];
    });
  }

  void _drag(DragUpdateDetails details) {
    final k = _dragged;
    if (k == null || _start.length != widget.shares.length - 1) return;
    final moved = (details.localPosition.dx - _startX) / _MixPainter.usable(_width) * 100;
    // A handle below the bar stops at the last one above it.
    final lowest = _isUpper(k) || widget.upper == 0 ? 0 : _start[widget.upper - 1].ceil();
    final to = (_start[k] + moved).round().clamp(lowest, 100).toDouble();
    if (to == _lastTo) return;
    _lastTo = to;
    final handles = [
      for (var j = 0; j < _start.length; j++)
        j < k ? min(_start[j], to) : (j > k ? max(_start[j], to) : to),
    ];
    widget.onChanged([
      for (var j = 0; j <= handles.length; j++)
        (j < handles.length ? handles[j] : 100.0) - (j > 0 ? handles[j - 1] : 0.0),
    ]);
  }

  void _endDrag() => setState(() => _dragged = null);

  void _hover(PointerHoverEvent event) {
    final k = _handleAt(event.localPosition);
    if (k != _hovered) setState(() => _hovered = k);
  }

  @override
  Widget build(BuildContext context) {
    final active = _dragged ?? _hovered;
    return MouseRegion(
      cursor: active != null ? SystemMouseCursors.resizeLeftRight : MouseCursor.defer,
      onHover: _hover,
      onExit: (_) => setState(() => _hovered = null),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: _startDrag,
        onHorizontalDragUpdate: _drag,
        onHorizontalDragEnd: (_) => _endDrag(),
        onHorizontalDragCancel: _endDrag,
        child: SizedBox(
          height: _MixPainter.height,
          width: double.infinity,
          child: CustomPaint(
            painter: _MixPainter(
              colors: widget.colors,
              handles: _handles,
              upper: widget.upper,
              active: active,
            ),
          ),
        ),
      ),
    );
  }
}

class _MixPainter extends CustomPainter {
  _MixPainter({required this.colors, required this.handles, required this.upper, required this.active});

  final List<Color> colors;
  final List<double> handles;
  final int upper;

  /// The handle drawn larger: hovered or being dragged.
  final int? active;

  static const height = 50.0;
  static const _track = 22.0;
  static const _radius = 11.0;

  /// Room at both ends for the handles at 0% and 100%.
  static const _inset = _radius + 2;

  static double usable(double width) => max(1.0, width - 2 * _inset);

  static double x(double width, double percent) => _inset + percent / 100 * usable(width);

  @override
  void paint(Canvas canvas, Size size) {
    final top = size.height / 2 - _track / 2, bottom = size.height / 2 + _track / 2;
    final track = RRect.fromLTRBR(_inset, top, size.width - _inset, bottom, const Radius.circular(6));
    canvas.save();
    canvas.clipRRect(track);
    // Each part is painted to the end of the bar and covered by the next
    // one, so no seams show between them.
    for (var j = 0; j < colors.length; j++) {
      final from = j == 0 ? 0.0 : handles[j - 1];
      final to = j < handles.length ? handles[j] : 100.0;
      if (to <= from) continue;
      canvas.drawRect(
        Rect.fromLTRB(x(size.width, from), top, track.right, bottom),
        Paint()..color = colors[j],
      );
    }
    // Where each handle cuts the bar.
    for (final h in handles) {
      final at = x(size.width, h);
      canvas.drawLine(Offset(at, top), Offset(at, bottom), Paint()
        ..color = Colors.white70
        ..strokeWidth = 2);
    }
    canvas.restore();
    // The last handle first, so earlier ones end up on top.
    for (var k = handles.length - 1; k >= 0; k--) {
      final center = Offset(x(size.width, handles[k]), k < upper ? top : bottom);
      final radius = k == active ? _radius + 2 : _radius;
      canvas.drawCircle(
        center.translate(0, 1),
        radius,
        Paint()
          ..color = Colors.black54
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
      canvas.drawCircle(center, radius, Paint()..color = colors[k]);
      canvas.drawCircle(
        center,
        radius - 1,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_MixPainter old) =>
      !listEquals(old.colors, colors) ||
      !listEquals(old.handles, handles) ||
      old.upper != upper ||
      old.active != active;
}
