import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_settings.dart';
import '../../l10n/strings.dart';
import '../../online/online_client.dart';
import '../../online/protocol.dart';
import '../glossary.dart';
import '../table_controller.dart';
import '../table_screen.dart';
import 'chat.dart';
import 'invite_dialog.dart';
import 'room_widgets.dart';

/// The room before the game (and, for someone who joins during it, until
/// the next hand): its code and invite to share, who sits where, the chat,
/// and the table the host sets up. A new room has only the host: the host
/// adds bots to empty seats (or friends take them), and starts the game
/// once at least 2 seats are taken; everyone then goes to the table.
/// Everyone sees the rules as the host changes them (greyed out: only the
/// host changes them).
///
/// For a room hosted on this device, the host also sees which ways in work:
/// the same Wi-Fi, and the internet (once the router opened the port, or at
/// the public address the host types when it can't be opened automatically).
///
/// When a game is over, everyone is back here (the same seats, bots and
/// rules) until the host starts a new one. A player out of chips can open
/// it over the table ([overTable]) and go back to watching. One who sits
/// out is dealt in again from here too (I'm Back). The host removes a
/// player with a tap on their seat.
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key, required this.client, this.overTable = false});

  /// The connection to the room; the lobby closes it when left, unless the
  /// table took it over.
  final OnlineClient client;

  /// Opened from the table by a player out of chips: the table keeps the
  /// connection and follows the game underneath; Watch goes back to it.
  final bool overTable;

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  late final StreamSubscription<void> _changes;

  /// Back on screen, a dropped connection is tried again at once.
  late final AppLifecycleListener _lifecycle;

  /// The table took over the connection (or keeps it, under this one).
  late bool _atTable = widget.overTable;

  OnlineClient get _client => widget.client;

  @override
  void initState() {
    super.initState();
    _changes = _client.changes.listen((_) {
      if (mounted) setState(() {});
    });
    _lifecycle = AppLifecycleListener(onResume: _client.reconnectNow);
    // After the first frame: the table may open at once.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_atTable) _client.attach(_onMessage);
    });
  }

  @override
  void dispose() {
    unawaited(_changes.cancel());
    _lifecycle.dispose();
    if (!_atTable) {
      _client.detach();
      unawaited(_client.close());
    }
    super.dispose();
  }

  void _onMessage(ServerMessage message) {
    if (_atTable || !mounted) return;
    // The first hand's line-up: the game starts (or this player sits down).
    // Coming back to a room: where its hand is (or the next one).
    final NextHand lineup;
    switch (message) {
      case NextHand():
        lineup = message;
      case Snapshot(hand: final hand?):
        lineup = hand.lineup;
      case Snapshot(next: final next?):
        lineup = next;
      case GameOver(:final seat, :final name):
        // Those waiting here for a seat hear who won too.
        final s = S.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.gameOver(name, you: seat != null && seat == _client.mySeat))),
        );
        return;
      case PlayerRemoved(:final name):
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.of(context).removedNotice(name))));
        return;
      default:
        return;
    }
    _atTable = true;
    _client.detach();
    final controller = OnlineTableController(
      _client,
      lineup,
      start: message is Snapshot ? message : null,
      speed: AppSettings.of(context).speed,
    );
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute<void>(builder: (_) => TableScreen.online(controller: controller)));
  }

  void _change(RoomSettings settings) => _client.send(ChangeSettings(settings: settings));

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final room = _client.room;
    final ended = _client.status == OnlineStatus.closed || _client.status == OnlineStatus.lost;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.room(room?.code ?? _client.welcome?.code ?? '')),
        actions: const [
          HelpButton(section: GlossarySection.online),
          SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ended || room == null
              ? _ended(context, s)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    if (_client.status == OnlineStatus.reconnecting) _reconnecting(context, s),
                    _code(context, s, room.code),
                    RoomSection(
                      title: s.players,
                      help: const HelpButton(
                        section: GlossarySection.online,
                        terms: [GlossaryTerm.host, GlossaryTerm.onlineBots],
                      ),
                      child: RoomSeats(
                        room: room,
                        mySeat: _client.mySeat,
                        host: _client.isHost,
                        onAdd: (style) => _client.send(AddBot(style: style)),
                        onStyle: (seat, style) => _client.send(ChangeSettings(botStyles: {seat: style})),
                        onRemove: (seat) => _client.send(RemoveBot(seat)),
                        onRemovePlayer: (seat, name) => _client.send(RemovePlayer(seat: seat, name: name)),
                      ),
                    ),
                    RoomSection(
                      title: s.chat,
                      help: const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.chat]),
                      child: ChatPanel(client: _client, height: 192),
                    ),
                    RoomRules(room: room, host: _client.isHost, onChange: _change),
                    const SizedBox(height: 28),
                    if (_sittingOut(room)) _back(context, s),
                    _start(context, s, room),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _ended(BuildContext context, S s) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _client.status == OnlineStatus.lost
              ? s.connectionLost
              : switch (_client.failure) {
                  final JoinError failure => s.joinError(failure),
                  null => s.closed(_client.closeReason),
                },
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.ok)),
      ],
    ),
  );

  /// The connection dropped: it comes back by itself (the seat is kept).
  Widget _reconnecting(BuildContext context, S s) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      children: [
        const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            s.reconnecting,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFFFFCC80)),
          ),
        ),
        const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.away]),
      ],
    ),
  );

  /// The room code, big, to read out or copy.
  Widget _code(BuildContext context, S s, String code) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(s.roomCode, style: theme.textTheme.labelLarge),
                      const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.roomCode]),
                    ],
                  ),
                  SelectableText(
                    code,
                    style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 6),
                  ),
                  Text(s.shareCode, style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60)),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    key: const ValueKey('invite'),
                    onPressed: () => showInvite(context, _client, code),
                    icon: const Icon(Icons.share),
                    label: Text(s.invite),
                  ),
                  if (_client.host case final host?) ...[
                    const SizedBox(height: 8),
                    WaysIn(host: host),
                    // For a router that isn't opened automatically: the address set by hand.
                    PublicAddressField(host: host),
                  ],
                ],
              ),
            ),
            IconButton(icon: const Icon(Icons.copy), onPressed: () => copyText(context, code)),
          ],
        ),
      ),
    );
  }

  /// Whether this player sits out (from the game before, say).
  bool _sittingOut(RoomState room) {
    final seat = _client.mySeat;
    return seat != null && seat < room.seats.length && room.seats[seat].sittingOut;
  }

  /// This player sits out: I'm Back deals them in again (from the next hand).
  Widget _back(BuildContext context, S s) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            s.youSitOut,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFFFFCC80)),
          ),
        ),
        const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.sitOut]),
        const SizedBox(width: 8),
        FilledButton.tonalIcon(
          key: const ValueKey('back'),
          onPressed: () => _client.send(const SitOut(false)),
          icon: const Icon(Icons.play_arrow),
          label: Text(s.imBack),
        ),
      ],
    ),
  );

  /// Start for the host (greyed out until 2 seats are taken, with why); for
  /// everyone else, what they are waiting for. Over the table, Watch goes
  /// back to it.
  Widget _start(BuildContext context, S s, RoomState room) {
    if (widget.overTable) {
      return FilledButton.icon(
        key: const ValueKey('watch'),
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.visibility),
        label: Text(s.watch),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      );
    }
    if (_client.isHost && room.phase == RoomPhase.lobby) {
      final ready = room.taken >= minPlayers;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!ready)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      s.needPlayers,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60),
                    ),
                  ),
                  const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.onlineBots]),
                ],
              ),
            ),
          FilledButton.icon(
            key: const ValueKey('start'),
            onPressed: ready ? () => _client.send(const StartGame()) : null,
            icon: const Icon(Icons.play_arrow),
            label: Text(s.start),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ],
      );
    }
    final String text;
    if (room.phase == RoomPhase.playing && room.paused) {
      text = s.waitingForPlayers;
    } else {
      // Back in the lobby after a game, someone who had joined during it waits for the host too.
      text = room.phase == RoomPhase.playing ? s.joinNextHand : s.waitingForHost;
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 10),
        Flexible(child: Text(text)),
      ],
    );
  }
}
