/// The room beside every screen while the user is in one: docked in full
/// on the right of a wide window, a slim rail on a phone held sideways,
/// a bar at the bottom of an upright browser. The rail and the bar open
/// the whole room over the screen with one tap. The game's own screen
/// shows the room in a tab instead, so the shell steps aside there.
library;

import 'dart:math';

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../online/online_client.dart';
import 'room_panel.dart';
import 'room_scope.dart';

/// How the shell shows the room.
enum RoomShellMode {
  /// Not in a room, or the game's screen (with its Room tab) is on top.
  none,

  /// The whole room on the right (a window at least [RoomShell.dockFrom] wide).
  docked,

  /// A slim rail on the right (narrower and held sideways: phones).
  rail,

  /// A bar at the bottom (narrower and upright: a browser on a phone).
  bar,
}

/// The app's screens (its Navigator, [app]) with the room beside them.
/// The screens get the area that is left (their MediaQuery too), so none
/// of them changes for the room; and they keep their state as the room
/// comes, goes or changes its layout.
class RoomShell extends StatelessWidget {
  const RoomShell({super.key, required this.app});

  /// The app's Navigator (MaterialApp.builder's child).
  final Widget app;

  static const dockFrom = 960.0, railWidth = 56.0, barHeight = 48.0;

  /// The docked room's width in a [width] window.
  static double dockWidth(double width) => (width * 0.28).clamp(280.0, 360.0);

  /// How the room shows in a [window] (none out of a room, or while the
  /// game's screen is on top).
  static RoomShellMode modeFor(Size window, RoomService? rooms) {
    if (rooms == null || !rooms.inRoom || rooms.gameOnScreen) return RoomShellMode.none;
    if (window.width >= dockFrom) return RoomShellMode.docked;
    return window.width >= window.height ? RoomShellMode.rail : RoomShellMode.bar;
  }

  @override
  Widget build(BuildContext context) {
    final rooms = RoomScope.maybeOf(context);
    if (rooms == null) return app;
    final mq = MediaQuery.of(context);
    final window = mq.size;
    final mode = modeFor(window, rooms);
    rooms.shellMode = mode;
    // The dock, rail and bar keep their full size: the safe area (a notch) is added to them.
    final right = switch (mode) {
      RoomShellMode.docked => dockWidth(window.width) + mq.padding.right,
      RoomShellMode.rail => railWidth + mq.padding.right,
      _ => 0.0,
    };
    final bottom = mode == RoomShellMode.bar ? barHeight + mq.padding.bottom : 0.0;
    final data = mq.copyWith(
      size: Size(max(0, window.width - right), max(0, window.height - bottom)),
      padding: mq.padding.copyWith(right: right > 0 ? 0 : null, bottom: bottom > 0 ? 0 : null),
      viewPadding: mq.viewPadding.copyWith(right: right > 0 ? 0 : null, bottom: bottom > 0 ? 0 : null),
      viewInsets: mq.viewInsets.copyWith(bottom: max(0.0, mq.viewInsets.bottom - bottom)),
    );
    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          right: right,
          bottom: bottom,
          child: MediaQuery(
            data: data,
            child: KeyedSubtree(key: rooms.appKey, child: app),
          ),
        ),
        if (mode == RoomShellMode.docked)
          Positioned(top: 0, right: 0, bottom: 0, width: right, child: const _DockedPanel()),
        if (mode == RoomShellMode.rail) Positioned(top: 0, right: 0, bottom: 0, width: right, child: const RoomRail()),
        if (mode == RoomShellMode.bar) Positioned(left: 0, right: 0, bottom: 0, height: bottom, child: const RoomBar()),
      ],
    );
  }
}

/// The panels' background.
const roomPanelColor = Color(0xFF12171B);

/// The whole room, docked on the right. It has a Navigator of its own (for
/// the chat's box, the menus), so dialogs opened from it go to the app's
/// (see roomDialogContext). It never takes the keyboard when it comes (the
/// screen beside it keeps its keys; the chat's box gets it when tapped),
/// and it stays clear of a soft keyboard (a tablet).
class _DockedPanel extends StatelessWidget {
  const _DockedPanel();

  @override
  Widget build(BuildContext context) => Material(
    color: roomPanelColor,
    shape: const Border(left: BorderSide(color: Colors.white12)),
    child: SafeArea(
      left: false,
      // Not animated: the keyboard's insets come animated already, and the box is scrolled into view for the
      // final size.
      child: Padding(
        padding: EdgeInsets.only(
          bottom: max(0.0, MediaQuery.viewInsetsOf(context).bottom - MediaQuery.paddingOf(context).bottom),
        ),
        child: InDockedPanel(
          child: HeroControllerScope.none(
            child: Navigator(
              requestFocus: false,
              onGenerateRoute: (_) => PageRouteBuilder<void>(
                pageBuilder: (_, _, _) => const RoomPanel(mode: RoomPanelMode.docked),
                transitionDuration: Duration.zero,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The colour of the head count (orange when the room is full).
Color headCountColor(OnlineClient? client) {
  final room = client?.room;
  return room != null && room.members.length >= room.cap ? const Color(0xFFFFCC80) : Colors.white70;
}

/// A phone held sideways: the room's code, how many are in it, the chat
/// (with what is new) and Watch (the room's table, once the host picked a
/// game; a green dot while it is played), in a slim rail. A tap opens the whole
/// room over the screen.
class RoomRail extends StatelessWidget {
  const RoomRail({super.key});

  @override
  Widget build(BuildContext context) {
    final rooms = RoomScope.of(context);
    final s = S.of(context);
    final client = rooms.client;
    final room = rooms.room;
    final ended = rooms.stage == RoomStage.ended;
    final code = room?.code ?? client?.welcome?.code ?? '';
    final theme = Theme.of(context);
    return Material(
      key: const ValueKey('room rail'),
      color: roomPanelColor,
      shape: const Border(left: BorderSide(color: Colors.white12)),
      child: SafeArea(
        left: false,
        child: InkWell(
          key: const ValueKey('open room'),
          onTap: rooms.openPanel,
          mouseCursor: WidgetStateMouseCursor.clickable,
          hoverColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          child: Column(
            children: [
              SizedBox(
                height: 44,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        code,
                        maxLines: 1,
                        style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 1),
                      ),
                    ),
                  ),
                ),
              ),
              if (ended)
                const _RailItem(icon: Icons.warning_amber_rounded, color: Color(0xFFFFCC80))
              else ...[
                _RailItem(
                  icon: Icons.groups_outlined,
                  label: room == null ? '' : '${room.members.length}/${room.cap}',
                  color: headCountColor(client),
                ),
                _RailItem(icon: Icons.chat_bubble_outline, label: s.chat, badge: rooms.unreadChat),
                // The room's table (its seats, or its game: the green dot).
                _RailItem(
                  key: const ValueKey('rail watch'),
                  icon: Icons.visibility,
                  label: s.watch,
                  greyed: !(rooms.hasGame && !rooms.gameOnScreen),
                  live: rooms.gameRunning && !rooms.gameOnScreen,
                  onTap: rooms.hasGame && !rooms.gameOnScreen ? rooms.watch : null,
                ),
              ],
              const Spacer(),
              const SizedBox(height: 40, child: Icon(Icons.chevron_left, color: Colors.white60)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One item of the rail: an icon over a short label, 56 high.
class _RailItem extends StatelessWidget {
  const _RailItem({
    super.key,
    required this.icon,
    this.label,
    this.color,
    this.badge = 0,
    this.live = false,
    this.greyed = false,
    this.onTap,
  });

  final IconData icon;
  final String? label;
  final Color? color;
  final int badge;
  final bool live;
  final bool greyed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = greyed ? Colors.white30 : (color ?? Colors.white70);
    final item = SizedBox(
      height: 56,
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Badged(
            badge: badge,
            live: live && !greyed,
            child: Icon(icon, size: 22, color: shown),
          ),
          if (label case final label?) ...[
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: theme.textTheme.labelSmall?.copyWith(fontSize: 11, color: shown),
                ),
              ),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return item;
    return InkWell(
      onTap: onTap,
      mouseCursor: WidgetStateMouseCursor.clickable,
      hoverColor: theme.colorScheme.primary.withValues(alpha: 0.16),
      child: item,
    );
  }
}

/// An icon with a count of what is new (red), or a green dot while the
/// game runs ([live]).
class _Badged extends StatelessWidget {
  const _Badged({required this.child, this.badge = 0, this.live = false});

  final Widget child;
  final int badge;
  final bool live;

  @override
  Widget build(BuildContext context) {
    if (badge <= 0 && !live) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: badge > 0 ? -8 : -3,
          top: badge > 0 ? -6 : -2,
          child: badge > 0
              ? UnreadBadge(count: badge)
              : Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: Color(0xFF66BB6A), shape: BoxShape.circle),
                ),
        ),
      ],
    );
  }
}

/// How many chat messages are new, in a small red disc.
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('unread'),
    constraints: const BoxConstraints(minWidth: 16),
    height: 16,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    decoration: BoxDecoration(color: const Color(0xFFE53935), borderRadius: BorderRadius.circular(8)),
    alignment: Alignment.center,
    child: Text(
      count > 99 ? '99+' : '$count',
      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700, height: 1.1),
    ),
  );
}

/// An upright browser: the rail's items across a bar at the bottom. A tap
/// opens the whole room from the bottom.
class RoomBar extends StatelessWidget {
  const RoomBar({super.key});

  @override
  Widget build(BuildContext context) {
    final rooms = RoomScope.of(context);
    final s = S.of(context);
    final client = rooms.client;
    final room = rooms.room;
    final ended = rooms.stage == RoomStage.ended;
    final theme = Theme.of(context);
    final labels = MediaQuery.sizeOf(context).width >= 360;
    final small = theme.textTheme.labelSmall?.copyWith(fontSize: 11);
    Widget item(IconData icon, String? label, {Color? color, int badge = 0, bool live = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Badged(
            badge: badge,
            live: live,
            child: Icon(icon, size: 20, color: color ?? Colors.white70),
          ),
          if (labels && label != null) ...[
            const SizedBox(width: 6),
            Text(label, maxLines: 1, style: small?.copyWith(color: color ?? Colors.white70)),
          ],
        ],
      ),
    );
    final canWatch = rooms.hasGame && !rooms.gameOnScreen;
    return Material(
      key: const ValueKey('room bar'),
      color: roomPanelColor,
      shape: const Border(top: BorderSide(color: Colors.white12)),
      child: SafeArea(
        top: false,
        child: InkWell(
          key: const ValueKey('open room'),
          onTap: rooms.openPanel,
          mouseCursor: WidgetStateMouseCursor.clickable,
          hoverColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          child: Row(
            children: [
              const SizedBox(width: 8),
              Text(
                room?.code ?? client?.welcome?.code ?? '',
                style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 1),
              ),
              if (ended)
                item(Icons.warning_amber_rounded, null, color: const Color(0xFFFFCC80))
              else ...[
                item(
                  Icons.groups_outlined,
                  room == null ? null : '${room.members.length}/${room.cap}',
                  color: headCountColor(client),
                ),
                item(Icons.chat_bubble_outline, s.chat, badge: rooms.unreadChat),
                InkWell(
                  key: const ValueKey('bar watch'),
                  onTap: canWatch ? rooms.watch : null,
                  mouseCursor: WidgetStateMouseCursor.clickable,
                  child: SizedBox(
                    height: 48,
                    child: item(
                      Icons.visibility,
                      s.watch,
                      color: canWatch ? null : Colors.white30,
                      live: canWatch && rooms.gameRunning,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.expand_less, color: Colors.white60),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The whole room over the screen, from the rail (from the right) or the
/// bar (from the bottom). Back, a tap beside it or its × closes it; it
/// stays clear of the keyboard.
class RoomPanelRoute extends PopupRoute<void> {
  RoomPanelRoute({required this.rooms, required this.fromBottom});

  final RoomService rooms;
  final bool fromBottom;

  @override
  Color? get barrierColor => Colors.black54;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => S.forLanguage(rooms.settings.language).room(rooms.room?.code ?? '');

  @override
  Duration get transitionDuration => const Duration(milliseconds: 220);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final panel = Material(
      key: const ValueKey('room panel sheet'),
      color: roomPanelColor,
      borderRadius: fromBottom ? const BorderRadius.vertical(top: Radius.circular(12)) : null,
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        left: false,
        top: !fromBottom,
        // Above the keyboard, when it is up (the chat's box stays in view).
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 120),
          padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
          child: const RoomPanel(mode: RoomPanelMode.sheet),
        ),
      ),
    );
    return fromBottom
        ? Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(width: size.width, height: size.height * 0.8, child: panel),
          )
        : Align(
            alignment: Alignment.centerRight,
            child: SizedBox(width: min(360, size.width), height: size.height, child: panel),
          );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => SlideTransition(
    position: Tween(
      begin: fromBottom ? const Offset(0, 1) : const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
    child: child,
  );
}
