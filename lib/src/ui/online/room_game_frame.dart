/// The room's game on screen: the table on the left (on top, upright), and
/// beside it a panel with two tabs, Game (the player's choices, or a
/// spectator's coach) and Room (the room itself, as docked elsewhere).
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../online/online_client.dart';
import 'room_panel.dart';
import 'room_scope.dart';
import 'room_shell.dart' show UnreadBadge, roomPanelColor;

/// The table ([table], with [bottom] under it: a card game's hand) and the
/// tabbed panel: [game] and the room. The app's room shell steps aside
/// while this is the top screen (see RoomTabHost), so the frame keeps
/// clear of a notch itself (sideways phones), and the panel of the soft
/// keyboard (the chat's box stays in view). The app's room remembers the
/// tab, so it stays as the seats turn into the game and back.
class RoomGameFrame extends StatefulWidget {
  const RoomGameFrame({
    super.key,
    required this.table,
    this.tableBar,
    this.bottom,
    required this.game,
    required this.client,
  });

  /// The felt (or board) with the seats.
  final Widget table;

  /// On the table's top edge during the game: the room's Seats and the
  /// host's End game (RoomTableBar).
  final Widget? tableBar;

  /// A card game's own hand, under the table (the seated player's).
  final Widget? bottom;

  /// The Game tab.
  final Widget game;

  /// The room's connection (the Room tab's room when the app has none).
  final OnlineClient client;

  @override
  State<RoomGameFrame> createState() => RoomGameFrameState();
}

class RoomGameFrameState extends State<RoomGameFrame> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this, initialIndex: _rooms?.frameTab ?? 0)
    ..addListener(_onTab);
  StreamSubscription<void>? _changes;

  /// The app's room, when this frame shows it (not a table shown alone).
  RoomService? get _rooms {
    final rooms = context.getInheritedWidgetOfExactType<RoomScope>()?.notifier;
    return rooms != null && rooms.client == widget.client ? rooms : null;
  }

  /// The last chat message seen here, without the app's room.
  late int _seen = widget.client.chat.lastOrNull?.n ?? 0;

  @override
  void initState() {
    super.initState();
    _changes = widget.client.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    _tabs.dispose();
    super.dispose();
  }

  /// To the Room tab (☰ > Room, or the out-of-chips Room button).
  void showRoom() => _tabs.animateTo(1);

  /// To the Game tab.
  void showGame() => _tabs.animateTo(0);

  void _onTab() {
    if (_tabs.index == 1) _markSeen();
    _rooms?.frameTab = _tabs.index;
    setState(() {});
  }

  void _markSeen() {
    final rooms = RoomScope.maybeOf(context);
    if (rooms != null && rooms.client == widget.client) {
      rooms.markChatSeen();
    } else {
      _seen = widget.client.chat.lastOrNull?.n ?? _seen;
    }
  }

  int _unread(RoomService? rooms) => rooms != null && rooms.client == widget.client
      ? rooms.unreadChat
      : widget.client.chat.where((line) => line.n > _seen && !line.you).length;

  @override
  Widget build(BuildContext context) {
    final rooms = RoomScope.maybeOf(context);
    final unread = _unread(rooms);
    // The Room tab is on screen: the chat in it is seen as it comes.
    if (_tabs.index == 1 && unread > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _markSeen() : null);
    }
    final mq = MediaQuery.of(context);
    // The soft keyboard's part over the panel (it covers the safe area's bottom too).
    final keyboard = max(0.0, mq.viewInsets.bottom - mq.padding.bottom);
    return RoomTabHost(
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, box) {
            final sideways = box.maxWidth >= box.maxHeight;
            final h = box.maxHeight;
            final bottom = widget.bottom;
            final bar = widget.tableBar;
            final table = bar == null
                ? widget.table
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      bar,
                      Expanded(child: widget.table),
                    ],
                  );
            if (sideways) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: table),
                        if (bottom != null) SizedBox(height: (h * 0.32).clamp(80.0, 160.0), child: bottom),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: (box.maxWidth * 0.34).clamp(280.0, 420.0),
                    child: _panel(
                      context,
                      unread,
                      h,
                      keyboard: keyboard,
                      border: const Border(left: BorderSide(color: Colors.white12)),
                    ),
                  ),
                ],
              );
            }
            // Upright with the keyboard up, the table gives the panel room for the chat.
            final shrink = keyboard > 0 ? ((h - keyboard) / h).clamp(0.5, 1.0) : 1.0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: h * (bottom == null ? 0.5 : 0.42) * shrink, child: table),
                if (bottom != null) SizedBox(height: h * 0.22 * shrink, child: bottom),
                Expanded(
                  child: _panel(
                    context,
                    unread,
                    h,
                    keyboard: keyboard,
                    border: const Border(top: BorderSide(color: Colors.white12)),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _panel(
    BuildContext context,
    int unread,
    double height, {
    required double keyboard,
    required ShapeBorder border,
  }) {
    final s = S.of(context);
    final tabHeight = height < 500 ? 36.0 : 40.0;
    return Material(
      color: roomPanelColor,
      shape: border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tabs,
            labelPadding: const EdgeInsets.symmetric(horizontal: 8),
            dividerColor: Colors.white12,
            tabs: [
              Tab(key: const ValueKey('game tab'), height: tabHeight, text: s.game),
              Tab(
                key: const ValueKey('room tab'),
                height: tabHeight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: Text(s.lobby, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    if (unread > 0 && _tabs.index == 0) ...[const SizedBox(width: 6), UnreadBadge(count: unread)],
                  ],
                ),
              ),
            ],
          ),
          Expanded(
            // Above the soft keyboard (the chat's box), when it is up.
            child: Padding(
              // Not animated: the keyboard's insets come animated already, and the box is scrolled into view
              // for the final size.
              padding: EdgeInsets.only(bottom: keyboard),
              child: IndexedStack(
                index: _tabs.index,
                sizing: StackFit.expand,
                children: [
                  widget.game,
                  RoomPanel(mode: RoomPanelMode.tab, client: widget.client),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tells the app's room that the screen it sits in shows the room itself
/// (the game's Room tab), so the room's dock, rail or bar step aside while
/// that screen is on top.
class RoomTabHost extends StatefulWidget {
  const RoomTabHost({super.key, required this.child});

  final Widget child;

  @override
  State<RoomTabHost> createState() => _RoomTabHostState();
}

class _RoomTabHostState extends State<RoomTabHost> {
  RoomService? _rooms;
  Route<Object?>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final rooms = RoomScope.maybeOf(context);
    final route = ModalRoute.of(context);
    if (rooms == _rooms && route == _route) return;
    if (_route case final old?) _rooms?.claim(old, false);
    _rooms = rooms;
    _route = route;
    if (route != null) rooms?.claim(route, true);
  }

  @override
  void dispose() {
    if (_route case final route?) _rooms?.claim(route, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
