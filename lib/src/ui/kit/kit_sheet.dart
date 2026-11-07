import 'package:flutter/material.dart';

import 'help.dart';

/// A dialog for the kit's sheets (an opponent's range, the scoreboard): a
/// one-line title with an optional "?" and a close button, then [child],
/// scrolling when it doesn't fit. On a phone held sideways (568x320) it
/// takes almost the whole screen, its margins and title kept slim so the
/// numbers get the room; on a PC it is at most [maxWidth] wide.
class KitSheet extends StatelessWidget {
  const KitSheet({super.key, required this.title, this.help, required this.child, this.maxWidth = 640});

  final String title;

  /// The "?" after the title (a TermsHelpButton).
  final Widget? help;
  final Widget child;
  final double maxWidth;

  /// Shows [sheet] over the screen; closes with the X, Escape or a tap outside.
  static Future<void> open(BuildContext context, Widget sheet) =>
      showDialog<void>(context: context, builder: (_) => sheet);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final short = size.height < TermsHelpButton.compactBelow;
    final narrow = size.width < 600;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: narrow ? 8 : 24, vertical: short ? 8 : 24),
      backgroundColor: const Color(0xFF161C21),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(14, short ? 2 : 8, 4, 0),
              child: Row(
                children: [
                  // The title takes what it needs, its "?" right after it.
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            key: const ValueKey('sheet title'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        ?help,
                      ],
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('sheet close'),
                    icon: const Icon(Icons.close, size: 20),
                    visualDensity: VisualDensity.compact,
                    mouseCursor: WidgetStateMouseCursor.clickable,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(padding: EdgeInsets.fromLTRB(14, 0, 14, short ? 8 : 14), child: child),
            ),
          ],
        ),
      ),
    );
  }
}

/// A chance as the sheets show it, without its "%": "62", "<1" for a small
/// one that isn't zero, "100" only when certain; empty for zero.
String chanceText(double p) {
  if (p <= 0) return '';
  if (p >= 1) return '100';
  final pct = p * 100;
  if (pct < 0.5) return '<1';
  // Never "100" for something that isn't certain.
  return pct >= 99.5 ? '>99' : pct.round().toString();
}
