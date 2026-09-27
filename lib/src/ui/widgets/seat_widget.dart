import 'package:flutter/material.dart';

import '../../bots/bot.dart';
import '../../engine/events.dart';
import '../../l10n/strings.dart';
import '../format.dart';
import '../table_geometry.dart';
import '../table_view_state.dart';
import 'card_view.dart';

/// One player at the table: cards on top, name and stack below, and a label
/// for their last action. Its info box is centered on [TableGeometry.seat].
/// A seat's last action, short: "Call 2.5", "Raise to 7.5", "All-in 40".
String _actionText(S s, ActionTaken e) {
  final amount = formatBb(e.streetBet);
  if (e.isAllIn && e.kind != ActionKind.fold) return s.allIn(amount);
  return switch (e.kind) {
    ActionKind.fold => s.fold,
    ActionKind.check => s.check,
    ActionKind.call => s.call(amount),
    ActionKind.bet || ActionKind.raise => s.raiseTo(amount, null),
  };
}

class SeatWidget extends StatelessWidget {
  const SeatWidget({
    super.key,
    required this.seat,
    required this.geometry,
    required this.isActing,
    required this.isHero,
    this.showStyle = false,
    this.onMore,
    this.hovered = false,
  });

  final SeatView seat;
  final TableGeometry geometry;
  final bool isActing;
  final bool isHero;

  /// Show the bot's playing style under its stack.
  final bool showStyle;

  /// Opens this player's options (a small ⋮ button on the info box).
  final VoidCallback? onMore;

  /// The mouse is over the seat (which can be clicked): light it up.
  final bool hovered;

  /// Total size of the widget; the table uses it to position the seat.
  static Size sizeFor(TableGeometry g) => Size(
        g.seatBoxSize.width + 24 * g.scale,
        g.seatCardsAbove + g.seatBoxSize.height + g.pillHeight / 2,
      );

  @override
  Widget build(BuildContext context) {
    final g = geometry;
    final size = sizeFor(g);
    final box = g.seatBoxSize;
    final cardWidth = isHero ? g.heroCardWidth : g.cardWidth;
    final s = S.of(context);
    final label = _label(s);

    return SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          // Cards, peeking out above the info box.
          Positioned(
            top: g.seatCardsAbove - cardWidth * cardAspectRatio * 0.72,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < seat.cardsHeld; i++)
                  Padding(
                    padding: EdgeInsets.only(left: i == 0 ? 0 : 3 * g.scale),
                    child: CardView(
                      width: cardWidth,
                      card: i < seat.cards.length ? seat.cards[i] : null,
                      faceUp: seat.faceUp,
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            top: g.seatCardsAbove,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: seat.folded ? 0.45 : 1,
              child: _infoBox(context, box),
            ),
          ),
          if (label != null)
            Positioned(
              top: g.seatCardsAbove + box.height - g.pillHeight / 2,
              child: label,
            ),
          if (onMore != null)
            Positioned(
              top: g.seatCardsAbove - 9 * g.scale,
              right: 0,
              child: Material(
                color: const Color(0xFF2A3136),
                shape: const CircleBorder(side: BorderSide(color: Colors.white24)),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onMore,
                  child: Padding(
                    padding: EdgeInsets.all(2 * g.scale),
                    child: Icon(Icons.more_vert, size: 16 * g.scale),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _infoBox(BuildContext context, Size box) {
    final g = geometry;
    final won = seat.won > 0;
    final borderColor = isActing
        ? const Color(0xFFFFC107)
        : won
            ? const Color(0xFFFFD54F)
            : (hovered ? Colors.white70 : Colors.white24);
    final style = showStyle ? seat.style : null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: box.width,
      height: box.height,
      padding: EdgeInsets.symmetric(horizontal: 6 * g.scale),
      decoration: BoxDecoration(
        color: hovered ? const Color(0xEE222A30) : const Color(0xEE15191C),
        borderRadius: BorderRadius.circular(10 * g.scale),
        border: Border.all(color: borderColor, width: isActing || won || hovered ? 2 : 1),
        boxShadow: [
          if (isActing) BoxShadow(color: const Color(0x99FFC107), blurRadius: 12 * g.scale),
          if (hovered && !isActing) BoxShadow(color: Colors.white24, blurRadius: 10 * g.scale),
        ],
      ),
      // Tight line height so three lines fit; if they still don't (large
      // system font), scale the content down instead of overflowing.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: box.width - 12 * g.scale - 4,
          child: DefaultTextStyle.merge(
            style: const TextStyle(height: 1.2),
            child: _infoLines(S.of(context), style),
          ),
        ),
      ),
    );
  }

  Widget _infoLines(S s, BotStyle? style) {
    final g = geometry;
    return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  isHero ? s.you : seat.info.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isHero ? const Color(0xFFFFE082) : Colors.white,
                    fontSize: 12.5 * g.scale,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (seat.position != null) ...[
                SizedBox(width: 4 * g.scale),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 4 * g.scale, vertical: 0.5),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(4 * g.scale),
                  ),
                  child: Text(
                    seat.position!.label,
                    style: TextStyle(color: Colors.white70, fontSize: 9.5 * g.scale),
                  ),
                ),
              ],
            ],
          ),
          Text(
            seat.allIn && seat.stack == 0 ? s.allInBadge : formatBb(seat.stack, unit: true),
            style: TextStyle(
              color: seat.allIn && seat.stack == 0 ? const Color(0xFFFF8A65) : Colors.white,
              fontSize: 12.5 * g.scale,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (style != null)
            Text(
              s.style(style),
              style: TextStyle(color: Colors.white38, fontSize: 9 * g.scale),
            ),
        ],
    );
  }

  Widget? _label(S s) {
    final g = geometry;
    final String text;
    final Color color;
    if (seat.won > 0) {
      text = '+${formatBb(seat.won)}';
      color = const Color(0xFF2E7D32);
    } else if (seat.action != null) {
      text = _actionText(s, seat.action!);
      color = switch (seat.lastAction) {
        _ when seat.allIn && !seat.folded => const Color(0xFFC62828),
        ActionKind.fold => const Color(0xFF546E7A),
        ActionKind.check || ActionKind.call => const Color(0xFF1565C0),
        ActionKind.bet || ActionKind.raise => const Color(0xFFE65100),
        null => const Color(0xFF546E7A),
      };
    } else {
      return null;
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
      child: Container(
        key: ValueKey(text),
        height: g.pillHeight,
        padding: EdgeInsets.symmetric(horizontal: 8 * g.scale),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(g.pillHeight / 2),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
        ),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.white,
            fontSize: 11 * g.scale,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}
