/// The room's game, for the games other than Hold'em: the game's table on
/// the left (its seated player's hand under it), and the two tabs beside
/// it: Game (what is going on, the seated player's buttons, or a
/// spectator's coach and Join game) and Room.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../online/online_client.dart';
import '../../online/protocol.dart' show JoinError;
import '../games.dart';
import '../glossary.dart';
import '../kit/coach_panel.dart';
import '../kit/guide_kit.dart';
import '../kit/l10n/kit_strings.dart';
import 'room_game_frame.dart';
import 'room_scope.dart';
import 'room_seats_panel.dart';
import 'room_widgets.dart';
import 'runner_client.dart';

/// The game's screen (see the library comment). The app's room keeps the
/// game running ([runner]) whether or not this is open; with
/// [ownsRunner] (a test showing it alone) the screen disposes of it.
///
/// Back: a spectator leaves at once (the game goes on: Watch comes back to
/// it); a seated player is asked first and gives the seat up, and the
/// screen closes once it is free (at the round's end), so no round waits
/// for them.
class OnlineGameScreen extends StatefulWidget {
  const OnlineGameScreen({super.key, required this.runner, this.ownsRunner = false});

  final RunnerClient runner;
  final bool ownsRunner;

  @override
  State<OnlineGameScreen> createState() => _OnlineGameScreenState();
}

class _OnlineGameScreenState extends State<OnlineGameScreen> {
  final _frame = GlobalKey<RoomGameFrameState>();

  /// Leave seat was pressed: the screen closes once the seat is free.
  bool _popWhenSpectator = false;
  StreamSubscription<void>? _seatChanges;

  RunnerClient get _c => widget.runner;

  @override
  void initState() {
    super.initState();
    // On screen: the spectator's coach works.
    _c.onScreen = true;
    _seatChanges = _c.client.changes.listen((_) => _popIfSpectator());
  }

  @override
  void dispose() {
    unawaited(_seatChanges?.cancel());
    _c.onScreen = false;
    if (widget.ownsRunner) _c.dispose();
    super.dispose();
  }

  bool get _seated => !_c.ended && !_c.gameOver && _c.client.mySeat != null;

  void _popIfSpectator() {
    if (!_popWhenSpectator || !mounted || _c.client.mySeat != null) return;
    _popWhenSpectator = false;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    final navigator = Navigator.of(context);
    navigator.popUntil((r) => r == route);
    navigator.pop();
  }

  /// Leaves the screen: a spectator at once; a seated player is asked
  /// first, and gives the seat up (the screen closes once it is free).
  Future<void> _leave(BuildContext context) async {
    if (_seated) {
      final s = S.of(context);
      final sure = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(s.leaveSeatQuestion),
          content: Text(s.leaveSeatWarningRound),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(s.cancel)),
            FilledButton(
              key: const ValueKey('leave seat sure'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(s.leaveSeat),
            ),
          ],
        ),
      );
      if (sure != true || !context.mounted) return;
      _popWhenSpectator = true;
      _c.leaveSeat();
      _popIfSpectator();
      return;
    }
    Navigator.of(context).pop();
  }

  /// Close Room (the host: for everyone) or Leave Room, asked first.
  Future<void> _leaveRoom(BuildContext context) async {
    final s = S.of(context);
    final host = _c.isHost;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(host ? s.closeRoomQuestion : s.leaveRoomQuestion),
        content: host || _c.client.mySeat != null ? Text(s.leaveWarning(host: host)) : null,
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
    if (rooms != null && rooms.client == _c.client) {
      await rooms.leave();
      return;
    }
    unawaited(_c.client.close());
    Navigator.of(context).pop();
  }

  Widget _menu(BuildContext context) {
    final s = S.of(context);
    return PopupMenuButton<String>(
      key: const ValueKey('game menu'),
      icon: const Icon(Icons.menu),
      onSelected: (choice) {
        switch (choice) {
          case 'room':
            _frame.currentState?.showRoom();
          case 'rules':
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => GuidePage(title: s.rules, sections: _c.ui.strings(context).rulesSections),
              ),
            );
          case 'glossary':
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GlossaryScreen()));
          case 'close' || 'leave room':
            _leaveRoom(context);
          case 'leave':
            _leave(context);
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
          item('rules', Icons.menu_book_outlined, s.rules),
          const PopupMenuDivider(),
          item('glossary', Icons.help_outline, s.glossary),
          if (!_c.ended)
            _c.isHost
                ? item('close', Icons.cancel_outlined, s.closeRoom)
                : item('leave room', Icons.no_meeting_room_outlined, s.leaveRoom),
          item('leave', Icons.logout, s.leave),
        ];
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final s = S.of(context);
        final info = games.where((g) => roomGameKey(g) == _c.ui.key).firstOrNull;
        final seated = _c.seated;
        return Scaffold(
          backgroundColor: const Color(0xFF0B0F12),
          resizeToAvoidBottomInset: false,
          appBar: AppBar(
            backgroundColor: const Color(0xFF12171B),
            toolbarHeight: 44,
            automaticallyImplyLeading: false,
            titleSpacing: 12,
            title: Row(
              children: [
                if (info != null) ...[info.emblem(22), const SizedBox(width: 8)],
                Flexible(
                  child: Text(info?.name(s) ?? s.room(_c.roomCode), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            actions: [
              // A spectator turns the coach on or off, on this device.
              if (_c.spectating) RunnerCoachChip(runner: _c),
              _menu(context),
            ],
          ),
          body: PopScope(
            // A seated player is asked first (the back gesture too).
            canPop: !_seated,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _leave(context);
            },
            child: RoomGameFrame(
              key: _frame,
              client: _c.client,
              // The room's seats and the host's End game, on the table's top edge.
              tableBar: RoomTableBar(client: _c.client),
              table: ColoredBox(
                color: const Color(0xFF0B0F12),
                child: _c.state == null ? const SizedBox.expand() : _c.ui.table(context, _c),
              ),
              bottom: seated && _c.state != null ? _c.ui.bottom(context, _c) : null,
              game: OnlineGamePanel(runner: _c),
            ),
          ),
        );
      },
    );
  }
}

/// The Coach chip in a spectator's top bar: turns the coach on or off on
/// this device (off by default).
class RunnerCoachChip extends StatelessWidget {
  const RunnerCoachChip({super.key, required this.runner});

  final RunnerClient runner;

  @override
  Widget build(BuildContext context) {
    final on = runner.coachOn;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilterChip(
        key: const ValueKey('coach chip'),
        label: Text(KitStrings.of(context).coach, maxLines: 1, softWrap: false),
        selected: on,
        showCheckmark: false,
        avatar: Icon(on ? Icons.visibility : Icons.visibility_off, size: 16),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        mouseCursor: WidgetStateMouseCursor.clickable,
        onSelected: runner.ended || runner.gameOver ? null : runner.setCoach,
      ),
    );
  }
}

/// The Game tab: what is going on (reconnecting, the host away, the
/// room's end, the game's end), the status line (Your turn, whose turn,
/// the round's result), then for a seated player the game's buttons, for
/// a spectator the coach (or its Coach button while off) and Join game or
/// Leave seat.
class OnlineGamePanel extends StatelessWidget {
  const OnlineGamePanel({super.key, required this.runner});

  final RunnerClient runner;

  @override
  Widget build(BuildContext context) {
    // The table's playback, for a result held back until it is played out.
    final playback = runner.ui.tablePlayback(context, runner);
    if (playback == null) return _build(context);
    return ListenableBuilder(listenable: playback, builder: (context, _) => _build(context));
  }

  Widget _build(BuildContext context) {
    final s = S.of(context);
    final k = KitStrings.of(context);
    final c = runner;
    final theme = Theme.of(context);
    final muted = theme.textTheme.titleSmall?.copyWith(color: Colors.white70);
    final warn = theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFFFFCC80));
    final notices = [if (c.reconnecting) s.reconnecting, if (c.hostAway) s.hostAway, if (c.gameOver) s.gameOver(null)];
    final String? status;
    if (c.ended) {
      status = c.client.status == OnlineStatus.lost
          ? (c.client.noDirectRoute ? s.noDirectRoute : s.connectionLost)
          : switch (c.client.failure) {
              final JoinError failure => s.joinError(failure),
              null => s.closed(c.client.closeReason),
            };
    } else if (c.over != null) {
      status = c.ui.heldResultText(context, c) ?? c.ui.resultText(context, c);
    } else if (c.ui.heldTurnText(context, c) case final held?) {
      status = held.isEmpty ? null : held;
    } else if (c.myTurn) {
      status = k.yourTurn;
    } else if (c.turn case final turn?) {
      status = '${c.nameOf(turn.seat)}…';
    } else {
      status = null;
    }
    final room = c.client.room;
    final seated = c.seated;
    final strings = c.ui.strings(context);
    final Widget middle;
    if (seated || c.ended) {
      middle = const SizedBox.shrink();
    } else if (!c.coachOn) {
      middle = Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonalIcon(
          key: const ValueKey('coach on'),
          onPressed: c.gameOver ? null : () => c.setCoach(true),
          icon: const Icon(Icons.visibility, size: 18),
          label: Text(k.coach),
        ),
      );
    } else if (c.coachHidden) {
      middle = Text('—', key: const ValueKey('coach hidden'), style: theme.textTheme.titleLarge);
    } else {
      middle = CoachList(
        key: const ValueKey('coach list'),
        answer: c.coach,
        strings: strings,
        look: CoachLook(moveText: (move) => c.ui.moveLabel(context, move)),
        thinking: c.coachThinking,
        dense: true,
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      children: [
        for (final notice in notices)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(notice, style: warn),
          ),
        if (status != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(status, key: const ValueKey('game status'), style: muted),
          ),
        if (!seated && !c.ended)
          Row(
            children: [
              Expanded(child: Text(k.coach, style: theme.textTheme.titleMedium)),
              const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.spectators]),
            ],
          ),
        middle,
        const SizedBox(height: 12),
        if (seated && !c.ended)
          c.ui.actions(context, c)
        else if (room != null && !c.ended && !c.gameOver)
          SeatActions(room: room, onJoin: c.joinGame, onLeave: c.leaveSeat, shows: shownGamesOf(context)),
      ],
    );
  }
}
