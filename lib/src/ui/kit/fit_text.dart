import 'package:flutter/material.dart';

/// How wide [text] is on one line in [style] (merged into the surrounding
/// DefaultTextStyle, with the screen's text scale), so a row can share its
/// width by what its words really need before it lays them out.
double textWidth(BuildContext context, String text, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: DefaultTextStyle.of(context).style.merge(style)),
    textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
    textScaler: MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling,
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// One line of text that gets smaller, down to [minFontSize], before it is
/// cut with "…": a short label ("Estrategia básica" on a sideways phone)
/// reads in full a little smaller rather than losing its end.
class ShrinkText extends StatelessWidget {
  const ShrinkText(this.text, {super.key, this.style, this.minFontSize = 10, this.textAlign});

  final String text;
  final TextStyle? style;

  /// The smallest the text gets; past that it is cut.
  final double minFontSize;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final merged = DefaultTextStyle.of(context).style.merge(style);
        final size = merged.fontSize ?? 14;
        var fitted = style;
        if (constraints.maxWidth.isFinite && size > minFontSize) {
          final natural = textWidth(context, text, style);
          if (natural > constraints.maxWidth) {
            // Width grows with the font size, so one step finds the size;
            // a hair under it allows for rounding.
            final scaled = (size * constraints.maxWidth / natural * 0.98).clamp(minFontSize, size);
            fitted = (style ?? const TextStyle()).copyWith(fontSize: scaled);
          }
        }
        return Text(text, style: fitted, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, textAlign: textAlign);
      },
    );
  }
}
