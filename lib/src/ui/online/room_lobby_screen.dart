/// The room's table (rooms v2.1): one screen for the room's game from the
/// host's pick until the room ends. Before the game (and between games) it
/// is the felt with the game's seats (Sit, the host's bots) and the Game
/// tab with Start, the seats and the rules; once the game runs it is the
/// game's own screen (poker's table, or another game's), and after it the
/// seats again.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../app/app_settings.dart';
import '../../l10n/strings.dart';
import '../../online/online_client.dart';
import '../../online/protocol.dart';
import '../games.dart';
import '../glossary.dart';
import '../kit/guide_kit.dart';
import '../table_screen.dart';
import 'online_game_screen.dart';
import 'room_game_frame.dart';
import 'room_panel.dart';
import 'room_scope.dart';
import 'room_seats_panel.dart';
import 'room_widgets.dart';

/// What the room's table route shows: the running game's screen, else the
/// seats ([RoomLobbyScreen]). It changes in place as the game starts and
/// ends, so whoever is at the room's table stays there.
class RoomGamePage extends StatefulWidget {
  const RoomGamePage({super.key, required this.rooms});

  final RoomService rooms;

  @override
  State<RoomGamePage> createState() => _RoomGamePageState();
}

class _RoomGamePageState extends State<RoomGamePage> {
  Object? _shown;

  Object? get _game => widget.rooms.table ?? widget.rooms.runner;

  @override
  void initState() {
    super.initState();
    _shown = _game;
    widget.rooms.addListener(_onRooms);
  }

  @override
  void dispose() {
    widget.rooms.removeListener(_onRooms);
    super.dispose();
  }

  /// Rebuilt only when the game's controller comes or goes.
  void _onRooms() {
    if (_game == _shown || !mounted) return;
    setState(() => _shown = _game);
  }

  @override
  Widget build(BuildContext context) {
    final rooms = widget.rooms;
    if (rooms.table case final table?) {
      return TableScreen.online(key: ObjectKey(table), controller: table, ownsController: false);
    }
    if (rooms.runner case final runner?) return OnlineGameScreen(key: ObjectKey(runner), runner: runner);
    return RoomLobbyScreen(rooms: rooms);
  }
}

/// The room's table before (and between) games: the top bar (the game, and
/// ☰ with Room, Rules, Glossary, Close Room or Leave Room, and Leave), the
/// felt with the game's seats ([RoomSeatsTable]), and beside it the Game
/// tab ([RoomSeatsPanel]: Start, the seats, the switch, the rules) and the
/// Room tab (the people and the chat). Back leaves it at once: no game is
/// running, so nobody waits.
class RoomLobbyScreen extends StatefulWidget {
  const RoomLobbyScreen({super.key, required this.rooms});

  final RoomService rooms;

  @override
  State<RoomLobbyScreen> createState() => _RoomLobbyScreenState();
}

class _RoomLobbyScreenState extends State<RoomLobbyScreen> {
  final _frame = GlobalKey<RoomGameFrameState>();
  StreamSubscription<void>? _changes;
  OnlineClient? _client;

  @override
  void initState() {
    super.initState();
    widget.rooms.addListener(_onRooms);
    _onRooms();
  }

  @override
  void dispose() {
    widget.rooms.removeListener(_onRooms);
    unawaited(_changes?.cancel());
    super.dispose();
  }

  void _onRooms() {
    final client = widget.rooms.client;
    if (client != _client) {
      unawaited(_changes?.cancel());
      _client = client;
      _changes = client?.changes.listen((_) {
        if (mounted) setState(() {});
      });
      if (mounted) setState(() {});
    }
  }

  Widget _menu(BuildContext context, OnlineClient client, RoomState? room, bool ended) {
    final s = S.of(context);
    final ui = room?.game == null || room!.game!.key == holdemKey ? null : gameUisOf(context)[room.game!.key];
    return PopupMenuButton<String>(
      key: const ValueKey('lobby menu'),
      icon: const Icon(Icons.menu),
      onSelected: (choice) {
        switch (choice) {
          case 'room':
            _frame.currentState?.showRoom();
          case 'rules':
            if (ui != null) {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => GuidePage(title: s.rules, sections: ui.strings(context).rulesSections),
                ),
              );
            }
          case 'glossary':
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GlossaryScreen()));
          case 'close' || 'leave room':
            unawaited(askToLeaveRoom(context, client));
          case 'leave':
            Navigator.of(context).maybePop();
        }
      },
      itemBuilder: (context) {
        PopupMenuItem<String> item(String value, IconData icon, String text) => PopupMenuItem(
          value: value,
          height: 40,
          child: Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 12),
              Flexible(child: Text(text)),
            ],
          ),
        );
        return [
          item('room', Icons.groups_outlined, s.lobby),
          if (ui != null) item('rules', Icons.menu_book_outlined, s.rules),
          const PopupMenuDivider(),
          item('glossary', Icons.help_outline, s.glossary),
          if (!ended)
            client.isHost
                ? item('close', Icons.cancel_outlined, s.closeRoom)
                : item('leave room', Icons.no_meeting_room_outlined, s.leaveRoom),
          item('leave', Icons.logout, s.leave),
        ];
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final client = widget.rooms.client;
    if (client == null) return const Scaffold(backgroundColor: Color(0xFF0B0F12));
    final room = client.room;
    final ended =
        widget.rooms.stage == RoomStage.ended ||
        client.status == OnlineStatus.closed ||
        client.status == OnlineStatus.lost;
    final info = room?.game == null ? null : games.where((g) => roomGameKey(g) == room!.game!.key).firstOrNull;
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F12),
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: const Color(0xFF12171B),
        toolbarHeight: MediaQuery.sizeOf(context).height < 500 ? 44 : null,
        automaticallyImplyLeading: false,
        titleSpacing: 12,
        title: Row(
          children: [
            if (info != null) ...[info.emblem(24), const SizedBox(width: 10)],
            Flexible(
              child: Text(
                info?.name(s) ?? s.room(room?.code ?? ''),
                key: const ValueKey('lobby title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (room != null) ...[
              const SizedBox(width: 10),
              Text(room.code, style: theme.textTheme.labelLarge?.copyWith(color: Colors.white54, letterSpacing: 1)),
            ],
          ],
        ),
        actions: [_menu(context, client, room, ended)],
      ),
      body: RoomGameFrame(
        key: _frame,
        client: client,
        table: room == null ? const SizedBox.expand() : RoomSeatsTable(client: client, room: room),
        game: ended ? _Ended(client: client) : RoomSeatsPanel(client: client),
      ),
    );
  }
}

/// The Game tab once the room has ended: why, and Leave.
class _Ended extends StatelessWidget {
  const _Ended({required this.client});

  final OnlineClient client;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(roomEndedText(s, client), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('lobby leave'),
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.logout),
            label: Text(s.leave),
          ),
        ],
      ),
    );
  }
}

/// Close Room (the host: for everyone) or Leave Room, asked first; the
/// app's room does it, or without one the connection closes and the screen
/// with it.
Future<void> askToLeaveRoom(BuildContext context, OnlineClient client) async {
  final s = S.of(context);
  final host = client.isHost;
  final sure = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(host ? s.closeRoomQuestion : s.leaveRoomQuestion),
      content: host || client.mySeat != null || client.queuedSeat != null ? Text(s.leaveWarning(host: host)) : null,
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
  if (sure != true || !context.mounted) return;
  final rooms = RoomScope.maybeOf(context);
  if (rooms != null && rooms.client == client) {
    await rooms.leave();
    return;
  }
  unawaited(client.close());
  if (context.mounted) await Navigator.of(context).maybePop();
}

/// The felt with the room's seats before the game, for any game: an empty
/// seat says Sit to a member without a seat (and offers the host Sit or a
/// bot); a person's seat shows their name ("Player" for the user's own)
/// and the host's badge; a bot's its name, with the host's × to take it
/// away. The host taps another person's seat to remove them. Laid out on
/// an oval from about 232x200 up; the game's emblem and name in the middle.
class RoomSeatsTable extends StatelessWidget {
  const RoomSeatsTable({super.key, required this.client, required this.room});

  final OnlineClient client;
  final RoomState room;

  /// Where seat [i] of [n] goes in [size], and how big a seat is.
  static ({List<Offset> centers, Size seat}) layout(Size size, int n) {
    final w = size.width, h = size.height;
    final seatHeight = (h * 0.16).clamp(40.0, 58.0);
    var seatWidth = (w * 0.26).clamp(78.0, 140.0);
    final rx = max(w / 2 - seatWidth / 2 - 4, 20.0);
    final ry = max(h / 2 - seatHeight / 2 - 4, 20.0);
    // Six seats or more: half a step round, so no seat sits right at the bottom or top, where two would touch.
    final offset = n >= 6 ? pi / n : 0.0;
    if (n >= 6) seatWidth = min(seatWidth, max(2 * rx * sin(pi / n) - 4, 56.0));
    final center = Offset(w / 2, h / 2);
    return (
      centers: [
        for (var i = 0; i < n; i++)
          center + Offset(rx * cos(pi / 2 + offset + i * 2 * pi / n), ry * sin(pi / 2 + offset + i * 2 * pi / n)),
      ],
      seat: Size(seatWidth, seatHeight),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final game = room.game;
    final info = game == null ? null : games.where((g) => roomGameKey(g) == game.key).firstOrNull;
    final felt = AppSettings.of(context).felt;
    final shows = showsRoomGame(room, shows: shownGamesOf(context));
    final canSit = shows && game != null && room.me?.seat == null;
    final host = client.isHost;
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final n = room.seats.length;
        final (:centers, :seat) = layout(size, n);
        final oval = Rect.fromCenter(
          center: size.center(Offset.zero),
          width: max(size.width - seat.width * 0.9, 40),
          height: max(size.height - seat.height * 0.9, 40),
        );
        final emblem = (min(oval.width, oval.height) * 0.28).clamp(24.0, 72.0);
        return Stack(
          key: const ValueKey('room seats table'),
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: CustomPaint(painter: _FeltPainter(oval, felt))),
            Positioned.fromRect(
              rect: oval.deflate(oval.shortestSide * 0.14),
              child: IgnorePointer(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (info != null) Opacity(opacity: 0.85, child: info.emblem(emblem)),
                        const SizedBox(height: 4),
                        Text(
                          info?.name(s) ?? '',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text('${room.taken}/$n', style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            for (final (i, info) in room.seats.indexed)
              Positioned(
                left: centers[i].dx - seat.width / 2,
                top: centers[i].dy - seat.height / 2,
                width: seat.width,
                height: seat.height,
                child: _SeatBox(
                  seat: info,
                  width: seat.width,
                  room: room,
                  host: host,
                  canSit: canSit && info.joining == null,
                  onSit: () => client.send(TakeSeat(info.seat)),
                  onBot: () => client.send(
                    AddBot(
                      style: botChoicesFor(room).contains(defaultBotStyle)
                          ? defaultBotStyle
                          : botChoicesFor(room).first,
                      seat: info.seat,
                    ),
                  ),
                  onRemoveBot: () => client.send(RemoveBot(info.seat)),
                  onRemovePlayer: info.member == null
                      ? null
                      : () => client.send(RemoveMember(id: info.member!, name: info.name)),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One seat on [RoomSeatsTable].
class _SeatBox extends StatelessWidget {
  const _SeatBox({
    required this.seat,
    required this.width,
    required this.room,
    required this.host,
    required this.canSit,
    required this.onSit,
    required this.onBot,
    required this.onRemoveBot,
    required this.onRemovePlayer,
  });

  final SeatInfo seat;

  /// The box's width: a narrow bot's box leaves its icon out for the name and the host's ×.
  final double width;
  final RoomState room;
  final bool host;
  final bool canSit;
  final VoidCallback onSit;
  final VoidCallback onBot;
  final VoidCallback onRemoveBot;
  final VoidCallback? onRemovePlayer;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final small = theme.textTheme.labelSmall?.copyWith(color: Colors.white60, fontSize: 11);
    final mine = seat.member != null && seat.member == room.you;
    final me = room.me;
    final queued = me != null && me.waiting && me.seat == seat.seat;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(color: mine || queued ? const Color(0xFFFFE082) : Colors.white24),
    );
    Widget box({required Widget child, VoidCallback? onTap, Color color = const Color(0xE6151D22), Key? key}) =>
        Material(
          key: key,
          color: color,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            mouseCursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
            hoverColor: theme.colorScheme.primary.withValues(alpha: 0.18),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Center(child: child),
            ),
          ),
        );
    // [fit]: a short word (Sit, a bot's name) shrinks to fit rather than being cut short.
    Widget lines(String title, String? subtitle, {Color? color, IconData? icon, bool fit = false}) => Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[Icon(icon, size: 16, color: color ?? Colors.white70), const SizedBox(width: 4)],
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MaybeFit(
                fit: fit,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: fit ? TextOverflow.visible : TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(color: color, fontWeight: mine ? FontWeight.w800 : null),
                ),
              ),
              if (subtitle != null) Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: small),
            ],
          ),
        ),
      ],
    );

    if (seat.isEmpty) {
      final joining = seat.joining;
      final label = joining ?? (canSit ? s.sit : s.emptySeat);
      final sub = joining != null ? (room.game?.key == holdemKey ? s.nextHandBadge : s.nextGameBadge) : null;
      // A narrow seat (the smallest phones) leaves the icon out, so the word fits.
      final narrow = width < 100;
      if (host) {
        // The host: Sit (when they can) or a bot, from a menu opened by the seat itself (which lights up
        // under the mouse like every other seat).
        return Builder(
          builder: (context) => box(
            key: ValueKey('table seat ${seat.seat}'),
            color: const Color(0xCC1B262C),
            onTap: () => _hostMenu(context, joining: joining),
            child: lines(
              label,
              sub,
              icon: narrow ? null : Icons.add,
              color: queued ? const Color(0xFFFFE082) : Colors.white70,
              fit: joining == null,
            ),
          ),
        );
      }
      return box(
        key: ValueKey('table seat ${seat.seat}'),
        color: const Color(0xCC1B262C),
        onTap: canSit ? onSit : null,
        child: canSit
            ? lines(s.sit, null, icon: narrow ? null : Icons.login, color: theme.colorScheme.primary, fit: true)
            : lines(label, sub, color: queued ? const Color(0xFFFFE082) : Colors.white38),
      );
    }
    if (seat.kind == SeatKind.bot) {
      return box(
        key: ValueKey('table seat ${seat.seat}'),
        child: Row(
          children: [
            Expanded(
              child: lines(
                seat.name,
                seat.leaving ? s.leavingBadge : s.botBadge,
                icon: host && width < 110 ? null : Icons.smart_toy_outlined,
                color: Colors.white70,
                fit: true,
              ),
            ),
            if (host)
              SizedBox.square(
                dimension: 24,
                child: IconButton(
                  key: ValueKey('table remove bot ${seat.seat}'),
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  icon: const Icon(Icons.close),
                  onPressed: seat.leaving ? null : onRemoveBot,
                ),
              ),
          ],
        ),
      );
    }
    final isHost = seat.member != null && seat.member == room.host;
    final details = [
      if (isHost) s.host,
      if (seat.status == SeatStatus.away) s.awayBadge,
      if (seat.leaving) s.leavingBadge,
    ];
    final removable = host && !mine && !isHost && onRemovePlayer != null;
    return box(
      key: ValueKey('table seat ${seat.seat}'),
      onTap: removable
          ? () => askToRemove(
              context,
              name: seat.name,
              going: seat.status == SeatStatus.left || seat.leaving,
              remove: onRemovePlayer!,
            )
          : null,
      child: lines(
        mine ? s.you : seat.name,
        details.isEmpty ? null : details.join(' · '),
        icon: Icons.person,
        color: mine ? const Color(0xFFFFE082) : null,
      ),
    );
  }
}

extension on _SeatBox {
  /// The host's menu on an empty seat (opened from [context], the seat's):
  /// Sit (when they can) or Add Bot.
  Future<void> _hostMenu(BuildContext context, {required String? joining}) async {
    final s = S.of(context);
    final box = context.findRenderObject()! as RenderBox;
    final overlay = Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final choice = await showMenu<String>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          key: ValueKey('table sit ${seat.seat}'),
          value: 'sit',
          enabled: canSit,
          child: Row(children: [const Icon(Icons.login, size: 20), const SizedBox(width: 12), Text(s.sit)]),
        ),
        PopupMenuItem(
          key: ValueKey('table bot ${seat.seat}'),
          value: 'bot',
          enabled: joining == null,
          child: Row(
            children: [const Icon(Icons.smart_toy_outlined, size: 20), const SizedBox(width: 12), Text(s.addBot)],
          ),
        ),
      ],
    );
    switch (choice) {
      case 'sit':
        onSit();
      case 'bot':
        onBot();
    }
  }
}

/// [child] shrunk to fit when [fit] (a short word), else as it is.
class _MaybeFit extends StatelessWidget {
  const _MaybeFit({required this.fit, required this.child});

  final bool fit;
  final Widget child;

  @override
  Widget build(BuildContext context) => fit ? FittedBox(fit: BoxFit.scaleDown, child: child) : child;
}

/// The felt under the room's seats.
class _FeltPainter extends CustomPainter {
  _FeltPainter(this.oval, this.felt);

  final Rect oval;
  final FeltStyle felt;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawOval(
      oval.shift(const Offset(0, 4)),
      Paint()
        ..color = Colors.black
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawOval(
      oval,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF6D4C41), Color(0xFF3E2723)],
        ).createShader(oval),
    );
    final cloth = oval.deflate(min(10, oval.shortestSide * 0.06));
    canvas.drawOval(
      cloth,
      Paint()
        ..shader = RadialGradient(
          colors: [felt.center, felt.middle, felt.edge],
          stops: const [0, 0.65, 1],
        ).createShader(cloth),
    );
  }

  @override
  bool shouldRepaint(_FeltPainter old) => old.oval != oval || old.felt != felt;
}
