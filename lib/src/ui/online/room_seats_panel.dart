/// The room's game, its seats and the host's controls, on the room's table
/// (rooms v2.1): the Game tab before the game, and the Seats sheet during
/// it (from the bar on the table's top edge, which also has the host's End
/// game). The room's lobby beside the other screens shows only the people
/// and the chat (RoomPanel).
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../online/online_client.dart';
import '../../online/protocol.dart';
import '../games.dart';
import '../glossary.dart';
import 'room_scope.dart';
import 'room_shell.dart' show roomPanelColor;
import 'room_widgets.dart';

/// What comes next (the host's Start before the game, End game during it;
/// what a guest waits for), the game's seats (a tap on an empty one sits
/// there, queued during a round; the host's bots), Join game or Leave seat,
/// the host's "Spectators see bots' cards" and the game's rules. Laid out
/// for 256 to 420 px wide; it scrolls.
class RoomSeatsPanel extends StatefulWidget {
  const RoomSeatsPanel({super.key, required this.client, this.inSheet = false});

  /// The room's connection.
  final OnlineClient client;

  /// In the Seats sheet during the game: the host's End game is on the
  /// table's bar instead.
  final bool inSheet;

  @override
  State<RoomSeatsPanel> createState() => _RoomSeatsPanelState();
}

class _RoomSeatsPanelState extends State<RoomSeatsPanel> {
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(RoomSeatsPanel old) {
    super.didUpdateWidget(old);
    if (old.client != widget.client) {
      unawaited(_changes?.cancel());
      _listen();
    }
  }

  void _listen() => _changes = widget.client.changes.listen((_) {
    if (mounted) setState(() {});
  });

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    final room = client.room;
    if (room == null) return const SizedBox.shrink();
    final s = S.of(context);
    final theme = Theme.of(context);
    final host = client.isHost;
    final hasGame = room.game != null;
    final uis = gameUisOf(context);
    final shows = showsRoomGame(room, shows: appOnlineGamesOf(uis));
    final runnerUi = room.game?.key == holdemKey ? null : uis[room.game?.key];
    final canTake = shows && hasGame && room.me?.seat == null;
    void remove(int id, String name) => client.send(RemoveMember(id: id, name: name));
    return ListView(
      key: const ValueKey('seats panel'),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      children: [
        ..._next(context, client, room),
        if (!shows)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              s.updateToWatch,
              key: const ValueKey('update to watch'),
              style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFFFFCC80)),
            ),
          ),
        RoomSection(
          title: s.seatList,
          help: const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.roomGame, GlossaryTerm.onlineBots]),
          trailing: Text('${room.taken}/${room.seats.length}', style: const TextStyle(color: Colors.white60)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!hasGame)
                Text(
                  s.seatsAfterGame,
                  key: const ValueKey('seats after game'),
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white60),
                )
              else
                RoomSeats(
                  room: room,
                  host: host,
                  onAdd: (style) => client.send(AddBot(style: style)),
                  onStyle: (seat, style) => client.send(ChangeSettings(botStyles: {seat: style})),
                  onRemove: (seat) => client.send(RemoveBot(seat)),
                  onRemoveMember: remove,
                  onTake: canTake ? (seat) => client.send(TakeSeat(seat)) : null,
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: SeatActions(
                  room: room,
                  onJoin: () => client.send(const TakeSeat()),
                  onLeave: () => client.send(const LeaveSeat()),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        HostSwitches(
          room: room,
          onChange: host ? (on) => client.send(HostSettings(seeBots: on)) : null,
        ),
        Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const ValueKey('rules'),
            enabled: hasGame,
            tilePadding: const EdgeInsets.symmetric(horizontal: 4),
            childrenPadding: EdgeInsets.zero,
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            dense: true,
            title: Text(s.rules, style: theme.textTheme.titleSmall?.copyWith(color: hasGame ? null : Colors.white38)),
            children: [
              if (room.game?.key == holdemKey && room.settings != null)
                RoomRules(room: room, host: host, onChange: (settings) => client.send(ChangeSettings(settings: settings)))
              else if ((room.game, runnerUi) case (final game?, final ui?) when shows)
                RunnerRules(
                  room: room,
                  ui: ui,
                  host: host,
                  onChange: (setup) => client.send(ChooseGame(game: game.key, setup: setup)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// The host: Start (greyed out until the game's seats allow it, with
  /// why) or End game. A guest: what they wait for. A seated player sitting
  /// out: I'm Back.
  List<Widget> _next(BuildContext context, OnlineClient client, RoomState room) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final rooms = RoomScope.maybeOf(context);
    final host = client.isHost;
    final playing = room.phase == RoomPhase.playing;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: Colors.white70);
    Widget waiting(String text) => Row(
      key: const ValueKey('waiting'),
      children: [
        const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: muted)),
      ],
    );
    final sittingOut = switch (client.mySeat) {
      final seat? => seat < room.seats.length && room.seats[seat].sittingOut,
      null => false,
    };
    // Start needs the game's seats taken (Hold'em 2; another game every seat, or its least).
    final needed = seatsNeeded(room, gameUisOf(context));
    final ready = needed != null && room.taken >= needed;
    final why = room.game?.key == holdemKey || needed == null ? s.needPlayers : s.needSeats(needed);
    final items = <Widget>[
      if (host && !playing && room.game != null) ...[
        if (!ready)
          Row(
            children: [
              Expanded(
                child: Text(why, style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60)),
              ),
              const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.onlineBots]),
            ],
          ),
        FilledButton.icon(
          key: const ValueKey('start'),
          onPressed: ready && showsRoomGame(room, shows: shownGamesOf(context))
              ? () {
                  if (rooms != null && rooms.client == client) rooms.expectGame();
                  client.send(const StartGame());
                }
              : null,
          icon: const Icon(Icons.play_arrow),
          label: Text(s.start),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
        ),
      ] else if (host && playing) ...[
        if (room.paused) waiting(s.waitingForPlayers),
        if (!widget.inSheet)
          OutlinedButton.icon(
            key: const ValueKey('end game'),
            onPressed: () => client.send(const EndGame()),
            icon: const Icon(Icons.stop),
            label: Text(s.endGame),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
          ),
      ] else if (!host && room.game == null)
        waiting(s.waitingForGame)
      else if (!host && !playing)
        waiting(s.waitingForHost)
      else if (!host && room.paused)
        waiting(s.waitingForPlayers)
      else if (!host && client.queuedSeat != null)
        waiting(s.joinNextHand),
      if (sittingOut)
        Row(
          children: [
            Expanded(
              child: Text(s.youSitOut, style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFFFFCC80))),
            ),
            const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.sitOut]),
            FilledButton.tonal(
              key: const ValueKey('back'),
              onPressed: () => client.send(const SitOut(false)),
              child: Text(s.imBack),
            ),
          ],
        ),
    ];
    return [for (final item in items) Padding(padding: const EdgeInsets.only(top: 12), child: item)];
  }
}

/// During the room's game, on the table's top edge: Seats (how many are
/// taken), which opens the seats over the screen (see [showRoomSeats]), and
/// the host's End game.
class RoomTableBar extends StatefulWidget {
  const RoomTableBar({super.key, required this.client});

  final OnlineClient client;

  /// The bar's height.
  static const height = 40.0;

  @override
  State<RoomTableBar> createState() => _RoomTableBarState();
}

class _RoomTableBarState extends State<RoomTableBar> {
  StreamSubscription<void>? _changes;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final client = widget.client;
    final room = client.room;
    final ended = client.status == OnlineStatus.closed || client.status == OnlineStatus.lost;
    final playing = room?.phase == RoomPhase.playing;
    final tight = ButtonStyle(
      visualDensity: VisualDensity.compact,
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
      minimumSize: const WidgetStatePropertyAll(Size(0, 32)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Container(
      key: const ValueKey('room table bar'),
      height: RoomTableBar.height,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF0E1317),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                key: const ValueKey('seats button'),
                onPressed: room == null || ended ? null : () => showRoomSeats(context, client),
                icon: const Icon(Icons.event_seat_outlined, size: 18),
                label: Text(room == null ? s.seatList : '${s.seatList} ${room.taken}/${room.seats.length}'),
                style: tight,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (client.isHost && playing && !ended)
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  key: const ValueKey('end game'),
                  onPressed: () => client.send(const EndGame()),
                  icon: const Icon(Icons.stop, size: 18),
                  label: Text(s.endGame),
                  style: tight,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The room's seats over the screen (from the table's bar during the game):
/// [RoomSeatsPanel], up to 90 % of the height, under the game's name and ×.
Future<void> showRoomSeats(BuildContext context, OnlineClient client) {
  final s = S.of(context);
  final key = client.room?.game?.key;
  final info = games.where((g) => roomGameKey(g) == key).firstOrNull;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: roomPanelColor,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) {
      final height = MediaQuery.sizeOf(context).height;
      return SizedBox(
        key: const ValueKey('seats sheet'),
        height: min(height * 0.9, 680),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
              child: Row(
                children: [
                  if (info != null) ...[info.emblem(24), const SizedBox(width: 10)],
                  Expanded(
                    child: Text(
                      info?.name(s) ?? s.seatList,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('close seats'),
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(child: RoomSeatsPanel(client: client, inSheet: true)),
          ],
        ),
      );
    },
  );
}
