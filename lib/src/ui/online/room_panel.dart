/// The room in one panel, 256 to 420 px wide: docked beside every screen,
/// over the screen from the rail or the bar, and as the Room tab beside
/// the room's game.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../online/online_client.dart';
import '../../online/protocol.dart';
import '../games.dart';
import '../glossary.dart';
import 'chat.dart';
import 'invite_dialog.dart';
import 'room_scope.dart';
import 'room_widgets.dart';

/// Where the panel shows.
enum RoomPanelMode {
  /// Docked on the right of the screen.
  docked,

  /// Over the screen, opened from the rail or the bar.
  sheet,

  /// The Room tab beside the room's game.
  tab,
}

/// The room: its code (copy, Invite, and Close Room for the host or Leave
/// Room for a guest, each asked first), the game it plays (one line, and
/// Watch when its table isn't on screen; the host picks games on Home),
/// the people (those playing, bots marked, and the spectators) and the
/// chat. The seats and the host's controls are on the room's table
/// (RoomSeatsPanel).
///
/// It shows the app's room (RoomScope), or, without one, [client]'s (a
/// table shown alone, in tests): then Close Room and Leave Room close the
/// connection and the screen, and there is no Watch.
class RoomPanel extends StatefulWidget {
  const RoomPanel({super.key, required this.mode, this.client});

  final RoomPanelMode mode;

  /// The room's connection when there is no app room (or none any more).
  final OnlineClient? client;

  /// From this height (docked or over the screen, without the keyboard),
  /// the chat is pinned under the rest, when everyone in the room fits
  /// above it too ([pinnedChatHeight]); else it is the last part of the
  /// scroll, under the people. The keyboard coming up never changes it, so
  /// the box keeps its text and focus.
  static const pinChatFrom = 600.0;

  /// The least and most height of the pinned chat's messages.
  static const minPinnedChat = 96.0, maxPinnedChat = 240.0;

  /// What the pinned chat takes besides its messages (its title, the quick
  /// messages and the box), and what the panel's top takes before the
  /// people (the code, Invite, the game's line, People's title).
  static const _chatAround = 150.0, _top = 240.0, _waysIn = 110.0;

  /// The height of one person's row and of People's two headings.
  static const _row = 50.0, _headings = 50.0;

  /// The pinned chat's messages in a panel [height] high (without the
  /// keyboard) with [people] rows (people and bots) and the ways in
  /// ([waysIn]: a room hosted here): what is left once everyone fits above
  /// it, at most a fifth of the panel; null when even the least doesn't
  /// leave room for everyone, or the panel is too low (then nothing is
  /// pinned).
  static double? pinnedChatHeight(double height, {int people = 0, bool waysIn = false}) {
    if (height < pinChatFrom) return null;
    final above = _top + (waysIn ? _waysIn : 0) + _headings + people * _row;
    final left = height - above - _chatAround;
    if (left < minPinnedChat) return null;
    return min(left, (height * 0.2).clamp(minPinnedChat, maxPinnedChat));
  }

  @override
  State<RoomPanel> createState() => _RoomPanelState();
}

class _RoomPanelState extends State<RoomPanel> {
  StreamSubscription<void>? _changes;
  OnlineClient? _listening;
  ValueNotifier<int>? _flashes;

  /// The chat keeps its state (focus, scroll) as the panel changes layout.
  final _chat = GlobalKey();

  /// The header lights up (Home's room button while docked).
  bool _flash = false;
  Timer? _flashTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final flashes = widget.mode == RoomPanelMode.docked ? RoomScope.maybeOf(context)?.flash : null;
    if (flashes != _flashes) {
      _flashes?.removeListener(_onFlash);
      _flashes = flashes?..addListener(_onFlash);
    }
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    _flashes?.removeListener(_onFlash);
    _flashTimer?.cancel();
    super.dispose();
  }

  void _onFlash() {
    _flashTimer?.cancel();
    setState(() => _flash = true);
    _flashTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _flash = false);
    });
  }

  /// Rebuilds as [client]'s room changes (also without the app's room).
  void _listen(OnlineClient? client) {
    if (client == _listening) return;
    unawaited(_changes?.cancel());
    _listening = client;
    _changes = client?.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final rooms = RoomScope.maybeOf(context);
    final client = rooms?.client ?? widget.client;
    _listen(client);
    if (client == null) return const SizedBox.shrink();
    // On screen (docked, or opened over the screen): what others said is seen.
    if (rooms != null && widget.mode != RoomPanelMode.tab && rooms.unreadChat > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => rooms.markChatSeen());
    }
    final ended = rooms != null && rooms.client == client
        ? rooms.stage == RoomStage.ended
        : client.status == OnlineStatus.closed || client.status == OnlineStatus.lost;
    final draft = rooms != null && rooms.client == client ? rooms.chatDraft : null;
    return LayoutBuilder(
      builder: (context, box) {
        // The height without the keyboard (the panel shrinks above it).
        final full = box.maxHeight + MediaQuery.viewInsetsOf(context).bottom;
        final people = client.room == null
            ? 0
            : client.room!.members.length + client.room!.seats.where((seat) => seat.kind == SeatKind.bot).length;
        final pinnedHeight = widget.mode == RoomPanelMode.tab
            ? null
            : RoomPanel.pinnedChatHeight(full, people: people, waysIn: client.host != null);
        final pinned = pinnedHeight != null;
        final chat = _section(
          context,
          title: S.of(context).chat,
          terms: const [GlossaryTerm.chat],
          child: ChatPanel(key: _chat, client: client, draft: draft, height: pinnedHeight ?? 180),
        );
        final room = client.room;
        final parts = [
          _header(context, rooms, client, room),
          ..._status(context, rooms, client, ended),
          if (room != null)
            // Greyed out once the room has ended (its card above says why).
            AbsorbPointer(
              absorbing: ended,
              child: Opacity(
                opacity: ended ? 0.38 : 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _room(context, rooms, client, room),
                ),
              ),
            ),
        ];
        if (!pinned) {
          return ListView(
            key: const ValueKey('room panel'),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            children: [...parts, chat],
          );
        }
        return Column(
          key: const ValueKey('room panel'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 8), children: parts),
            ),
            const Divider(height: 1),
            // With the keyboard up the chat may not fit: it scrolls, its box (at the bottom) in view.
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: max(0.0, box.maxHeight - 61)),
              child: SingleChildScrollView(
                reverse: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: chat,
              ),
            ),
          ],
        );
      },
    );
  }

  /// The code (copy, "?"), Invite and Close Room or Leave Room; for a room
  /// hosted here, which ways in work.
  Widget _header(BuildContext context, RoomService? rooms, OnlineClient client, RoomState? room) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final code = room?.code ?? client.welcome?.code ?? '';
    final host = client.isHost;
    final invite = FilledButton.tonalIcon(
      key: const ValueKey('invite'),
      onPressed: code.isEmpty ? null : () => showInvite(roomDialogContext(context), client, code),
      icon: const Icon(Icons.share, size: 18),
      label: Text(s.invite, maxLines: 1),
      style: _tight,
    );
    final leave = OutlinedButton.icon(
      key: ValueKey(host ? 'close room' : 'leave room'),
      onPressed: () => _askToLeave(context, rooms, client),
      icon: Icon(host ? Icons.cancel_outlined : Icons.logout, size: 18),
      label: Text(host ? s.closeRoom : s.leaveRoom, maxLines: 1),
      style: _tight,
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: _flash ? theme.colorScheme.primary.withValues(alpha: 0.22) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(
                child: SelectableText(
                  code,
                  maxLines: 1,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 3),
                ),
              ),
              IconButton(
                key: const ValueKey('copy code'),
                icon: const Icon(Icons.copy, size: 20),
                visualDensity: VisualDensity.compact,
                onPressed: code.isEmpty ? null : () => copyText(context, code),
              ),
              const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.roomCode, GlossaryTerm.roomStays]),
              const Spacer(),
              if (widget.mode == RoomPanelMode.sheet)
                IconButton(
                  key: const ValueKey('close panel'),
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
            ],
          ),
          Text(s.shareCode, style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60)),
          const SizedBox(height: 8),
          _SideBySide(first: invite, second: leave, labels: [s.invite, host ? s.closeRoom : s.leaveRoom]),
          if (client.host case final ways?) ...[const SizedBox(height: 8), WaysIn(host: ways)],
        ],
      ),
    );
  }

  static final _tight = ButtonStyle(
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
    minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
    visualDensity: VisualDensity.compact,
  );

  /// Close Room (the room ends for everyone) or Leave Room, asked first.
  Future<void> _askToLeave(BuildContext context, RoomService? rooms, OnlineClient client) async {
    final s = S.of(context);
    final host = client.isHost;
    final seated = client.mySeat != null || client.queuedSeat != null;
    final ended = client.status == OnlineStatus.closed || client.status == OnlineStatus.lost;
    if (!ended) {
      final sure = await showDialog<bool>(
        context: roomDialogContext(context),
        builder: (context) => AlertDialog(
          title: Text(host ? s.closeRoomQuestion : s.leaveRoomQuestion),
          content: host || seated ? Text(s.leaveWarning(host: host)) : null,
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(s.cancel)),
            FilledButton(
              key: ValueKey(host ? 'close room sure' : 'leave room sure'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(host ? s.closeRoom : s.leaveRoom),
            ),
          ],
        ),
      );
      if (sure != true) return;
    }
    if (rooms != null && rooms.client == client) {
      await rooms.leave();
    } else {
      unawaited(client.close());
      if (context.mounted) await Navigator.of(context).maybePop();
    }
  }

  /// Reconnecting, or why the room ended (and OK).
  List<Widget> _status(BuildContext context, RoomService? rooms, OnlineClient client, bool ended) {
    final s = S.of(context);
    final theme = Theme.of(context);
    if (ended) {
      return [
        Card(
          key: const ValueKey('room ended'),
          margin: const EdgeInsets.only(top: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(roomEndedText(s, client), style: theme.textTheme.titleSmall),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    key: const ValueKey('room ok'),
                    onPressed: () {
                      if (rooms != null && rooms.client == client) {
                        rooms.dismiss();
                      } else {
                        unawaited(Navigator.of(context).maybePop());
                      }
                    },
                    child: Text(s.ok),
                  ),
                ),
              ],
            ),
          ),
        ),
      ];
    }
    if (client.status != OnlineStatus.reconnecting) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Flexible(
              child: Text(s.reconnecting, style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFFFFCC80))),
            ),
            const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.away]),
          ],
        ),
      ),
    ];
  }

  /// The room's game (what it plays, or what comes first; Watch when its
  /// table isn't on screen) and the people in the room.
  List<Widget> _room(BuildContext context, RoomService? rooms, OnlineClient client, RoomState room) {
    final s = S.of(context);
    final host = client.isHost;
    void remove(int id, String name) => client.send(RemoveMember(id: id, name: name));
    return [
      ..._game(context, rooms, client, room),
      RoomSection(
        title: s.people,
        help: const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.spectators, GlossaryTerm.host]),
        trailing: HeadCount(room: room),
        child: PeopleList(room: room, onRemove: host ? remove : null),
      ),
    ];
  }

  /// One line, not a picker: the game the room plays (its emblem and name)
  /// and Watch when its table isn't on screen; with none yet, where the
  /// host picks one (Home) or what a guest waits for.
  List<Widget> _game(BuildContext context, RoomService? rooms, OnlineClient client, RoomState room) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: Colors.white70);
    final game = room.game;
    final Widget line;
    if (game == null) {
      line = client.isHost
          ? Text(s.pickGameOnHome, key: const ValueKey('pick game'), style: muted)
          : Row(
              key: const ValueKey('waiting'),
              children: [
                const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Expanded(child: Text(s.waitingForGame, style: muted)),
              ],
            );
    } else {
      final info = games.where((g) => roomGameKey(g) == game.key).firstOrNull;
      final watch = rooms != null && rooms.client == client && widget.mode != RoomPanelMode.tab && !rooms.gameOnScreen;
      line = Row(
        key: const ValueKey('room game'),
        children: [
          if (info != null) ...[info.emblem(28), const SizedBox(width: 10)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info?.name(s) ?? game.key,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  room.phase == RoomPhase.playing ? s.playingNow : '${room.taken}/${room.seats.length} · ${s.seatList}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60),
                ),
              ],
            ),
          ),
          if (watch) ...[
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const ValueKey('watch'),
              onPressed: rooms.watch,
              icon: const Icon(Icons.visibility, size: 18),
              label: Text(s.watch),
              style: _tight,
            ),
          ],
        ],
      );
    }
    return [Padding(padding: const EdgeInsets.only(top: 12), child: line)];
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required List<GlossaryTerm> terms,
    required Widget child,
  }) => RoomSection(
    title: title,
    help: HelpButton(section: GlossarySection.online, terms: terms),
    child: child,
  );
}

/// Why the room ended for [client]'s user.
String roomEndedText(S s, OnlineClient client) => client.status == OnlineStatus.lost
    // Lost because this network can't reach the host directly: what to try instead.
    ? (client.noDirectRoute ? s.noDirectRoute : s.connectionLost)
    : switch (client.failure) {
        final JoinError failure => s.joinError(failure),
        null => s.closed(client.closeReason),
      };

/// Two buttons side by side, half the width each, when their [labels]
/// fit; one above the other otherwise (a narrow panel, a long language).
class _SideBySide extends StatelessWidget {
  const _SideBySide({required this.first, required this.second, required this.labels});

  final Widget first, second;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;
    final scale = MediaQuery.textScalerOf(context);
    final widest = labels
        .map(
          (label) => (TextPainter(
            text: TextSpan(text: label, style: style),
            textDirection: Directionality.of(context),
            textScaler: scale,
            maxLines: 1,
          )..layout()).width,
        )
        .reduce(max);
    return LayoutBuilder(
      builder: (context, box) {
        // The icon, the gap and the button's padding beside the label.
        const gap = 8.0, around = 10 + 18 + 8 + 10 + 4;
        if (widest + around <= (box.maxWidth - gap) / 2) {
          return Row(
            children: [
              Expanded(child: first),
              const SizedBox(width: gap),
              Expanded(child: second),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [first, const SizedBox(height: 6), second],
        );
      },
    );
  }
}
