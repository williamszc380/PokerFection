import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_settings.dart';
import '../app/drills.dart';
import '../bots/bot.dart';
import '../engine/actions.dart';
import '../engine/poker_hand.dart';
import '../game/table_session.dart';
import '../gto/gto_solutions.dart';
import '../online/protocol.dart' show ChatLine;
import 'decision_panel.dart';
import 'drill_screen.dart';
import 'format.dart';
import '../l10n/strings.dart';
import 'glossary.dart';
import 'history_screen.dart';
import 'online/chat.dart';
import 'online/invite_dialog.dart';
import 'online/lobby_screen.dart';
import 'online/room_widgets.dart';
import 'range_screen.dart';
import 'table_controller.dart';
import 'table_geometry.dart';
import 'table_view_state.dart';
import 'widgets/card_view.dart';
import 'widgets/chip_stack.dart';
import 'widgets/seat_widget.dart';

class TableScreen extends StatefulWidget {
  const TableScreen({
    super.key,
    required this.config,
    this.speed = PlaybackSpeed.normal,
    this.solutions,
    this.controller,
  });

  /// An online table, already set up: its controller (see
  /// OnlineTableController), which the screen then owns.
  TableScreen.online({super.key, required OnlineTableController this.controller})
      : config = controller.session.config,
        speed = controller.speed,
        solutions = null;

  /// The mistake drills: the table of each spot played again (see
  /// DrillController, which the screen then owns).
  TableScreen.drills({super.key, required DrillController this.controller})
      : config = controller.session.config,
        speed = controller.speed,
        solutions = null;

  final TableConfig config;
  final PlaybackSpeed speed;

  /// Where solved preflop games come from (the app-wide cache by default).
  final GtoSolutions? solutions;

  /// Runs the table, if not a new one on this device (online).
  final TableController? controller;

  @override
  State<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends State<TableScreen> {
  // Training saves each mistake to the drills.
  late final TableController _controller = widget.controller ??
      TableController(
        widget.config,
        speed: widget.speed,
        solutions: widget.solutions,
        drills: widget.config.guessGto ? Drills.read(context) : null,
      );
  final _panel = GlobalKey<DecisionPanelState>();

  /// Online: the server deals, and some things are up to the host.
  OnlineTableController? get _online => switch (_controller) {
        final OnlineTableController online => online,
        _ => null,
      };

  /// The mistake drills, when they are played here.
  DrillController? get _drill => switch (_controller) {
        final DrillController drill => drill,
        _ => null,
      };

  /// Online: what everyone is told, and others' chat messages, shown for a
  /// moment.
  StreamSubscription<OnlineToast>? _toasts;

  /// Each mistake saved to the drills, shown for a moment.
  StreamSubscription<({bool again, Duration wait})>? _saved;

  /// The notes on screen, oldest first, each until its timer ends.
  final List<_Note> _notes = [];

  /// Online: the chat is open (its messages don't pop up over the table
  /// meanwhile), and the last message seen there (or in the lobby).
  bool _chatOpen = false;
  int _chatSeen = 0;

  /// Online: back on screen, a dropped connection is tried again at once.
  AppLifecycleListener? _lifecycle;

  /// Online, once the game is over: back to the room's lobby when it fires.
  Timer? _toLobby;

  @override
  void initState() {
    super.initState();
    // Online, the server deals.
    final online = _online;
    _saved = _controller.savedToDrills.listen(_showSaved);
    if (online == null) {
      _controller.startNextHand();
    } else {
      _toasts = online.toasts.listen(_showToast);
      _lifecycle = AppLifecycleListener(onResume: online.client.reconnectNow);
      _chatSeen = online.client.chat.lastOrNull?.n ?? 0;
    }
  }

  @override
  void dispose() {
    unawaited(_toasts?.cancel());
    unawaited(_saved?.cancel());
    for (final note in _notes) {
      note.timer.cancel();
    }
    _toLobby?.cancel();
    _lifecycle?.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// "Alice used GTO help", "Bob looked at your cards", "Bob was removed",
  /// or that the host changed the rules: for 3 s at the top of the table
  /// (see [_TableNotes]); another player's chat message for 4 s. Once the
  /// game is over, who won shows over the table for 4 s (anything open over
  /// it, such as the lobby of a player out of chips, closes first), then
  /// everyone is back in the room's lobby.
  void _showToast(OnlineToast toast) {
    if (!mounted) return;
    if (toast.over != null) {
      _toTable();
      _toLobby ??= Timer(const Duration(seconds: 4), _backToLobby);
      return;
    }
    final line = toast.chat;
    // The chat is open: its messages show there.
    if (line != null && _chatOpen) return;
    final s = S.of(context);
    final note = toast.note, removed = toast.removed;
    _addNote(
      line?.text ?? (note != null ? s.note(note) : (removed != null ? s.removedNotice(removed) : s.rulesChanged)),
      chat: line,
    );
  }

  /// A mistake was saved to the drills: "Saved to your drills: first
  /// review in 10 min", for 3 s at the top of the table.
  void _showSaved(({bool again, Duration wait}) saved) {
    if (!mounted) return;
    final s = S.of(context);
    _addNote(s.savedToDrills(formatWait(s, saved.wait), again: saved.again));
  }

  /// Shows [text] (or the chat message [chat]) at the top of the table, a
  /// note for 3 s, a chat message for 4 s. 2 at once at most (they stay
  /// clear of the player's seat): a chat message goes first, then the
  /// oldest note; a chat message never pushes out a note.
  void _addNote(String text, {ChatLine? chat}) {
    final shownChat = _notes.indexWhere((shown) => shown.chat != null);
    if (_notes.length >= 2 && shownChat < 0 && chat != null) return;
    final life = Duration(seconds: chat == null ? 3 : 4);
    late final _Note shown;
    shown = (
      chat: chat,
      text: text,
      life: life,
      timer: Timer(life, () {
        if (mounted) setState(() => _notes.remove(shown));
      }),
    );
    setState(() {
      if (_notes.length >= 2) _notes.removeAt(max(shownChat, 0)).timer.cancel();
      _notes.add(shown);
    });
  }

  /// The game is over: the room's lobby takes the connection back, in place
  /// of the table (and of anything open over it). Unless the room closed
  /// meanwhile: then the table says so.
  void _backToLobby() {
    final online = _online;
    if (!mounted || online == null || online.ended) return;
    _toTable();
    final client = online.handBack();
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => LobbyScreen(client: client)));
  }

  /// Closes whatever is open over the table.
  void _toTable() {
    final table = ModalRoute.of(context);
    if (table != null) Navigator.of(context).popUntil((route) => route == table);
  }

  /// Online, out of chips: the room's lobby over the table, which follows
  /// the game underneath (Watch comes back to it).
  Future<void> _openLobby(BuildContext context, OnlineTableController online) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => LobbyScreen(client: online.client, overTable: true)),
    );
    // Its chat was on screen.
    _chatSeen = online.client.chat.lastOrNull?.n ?? _chatSeen;
  }

  /// Online, from ☰: the whole chat, with the quick messages and the box.
  /// Meanwhile new messages show there, not over the table.
  Future<void> _chat(BuildContext context, OnlineTableController online) async {
    final s = S.of(context);
    _chatOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        // Above the keyboard, when it is up.
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, room) {
              final height = room.maxHeight * 0.85;
              return SizedBox(
                height: height,
                // Too little room (a phone sideways, with the keyboard up): it scrolls.
                child: SingleChildScrollView(
                  child: SizedBox(
                    height: max(height, 256),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Text(s.chat, style: Theme.of(context).textTheme.titleMedium),
                              const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.chat]),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Expanded(child: ChatPanel(client: online.client)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    _chatOpen = false;
    _chatSeen = online.client.chat.lastOrNull?.n ?? _chatSeen;
  }

  /// Online, a click on a seat: that player's range (with help on), or a
  /// look at their cards (when the host allows it; greyed out otherwise).
  Future<void> _onlineSeat(BuildContext context, OnlineTableController online, int seat) async {
    // The session's copy of the hand may still be on the last one (or sit out a hand the user watches).
    final help = _controller.guessGto;
    final ranges = help && !online.watching && _controller.session.hand?.handNumber == online.handNumber;
    if (online.isUserSeat(seat)) {
      if (ranges) _openRange(context, seat);
      return;
    }
    // Without help it is player against player: no ranges, only a look at
    // the cards when the host allows it.
    if (!help && !online.canPeek(seat)) return;
    final s = S.of(context);
    final name = _controller.view.seats[seat].info.name;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(name, style: Theme.of(context).textTheme.titleMedium)),
            if (help)
              ListTile(
                leading: const Icon(Icons.grid_view),
                title: Text(s.showRange),
                enabled: ranges,
                onTap: () => Navigator.of(context).pop('range'),
              ),
            ListTile(
              key: const ValueKey('see cards'),
              leading: const Icon(Icons.visibility),
              title: Text(s.seeCards),
              enabled: online.canPeek(seat),
              trailing: const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.seeCards]),
              onTap: () => Navigator.of(context).pop('cards'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (choice) {
      case 'range':
        _openRange(context, seat);
      case 'cards':
        // Everyone is told: ask first.
        final sure = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            content: Text(s.seeCardsQuestion(name)),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(s.cancel)),
              FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(s.seeCards)),
            ],
          ),
        );
        if (sure == true) online.peek(seat);
    }
  }

  /// With a strategy to enter (or online, one on its way), the buttons in
  /// the panel decide instead of the keys.
  bool get _keysPlay => _controller.heroSpot == null && !(_online?.helpPending ?? false);

  void _foldOrCheck() {
    final options = _controller.heroOptions;
    if (options == null || !_keysPlay) return;
    _controller.heroAct(options.canCheck ? const PlayerAction.check() : const PlayerAction.fold());
  }

  void _checkOrCall() {
    final options = _controller.heroOptions;
    if (options == null || !_keysPlay) return;
    _controller.heroAct(options.canCheck ? const PlayerAction.check() : const PlayerAction.call());
  }

  /// A click on a seat (Guess the GTO mode): that player's range.
  void _openRange(BuildContext context, int seat) {
    final session = _controller.session;
    if (session.hand == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => RangeScreen(session: session, only: seat)),
    );
  }

  /// Everyone at the table (from ☰): stacks, and for bots their style and
  /// whether their cards are shown. Ranges open with a click on a seat.
  Future<void> _players(BuildContext context) async {
    final session = _controller.session;
    final s = S.of(context);
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final hand = session.hand;
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  title: Text(s.editTable, style: Theme.of(context).textTheme.titleMedium),
                  trailing: const HelpButton(section: GlossarySection.styles),
                ),
                for (var seat = 0; seat < session.config.playerCount; seat++)
                  _playerRow(context, s, seat, hand, () => setSheetState(() {})),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _playerRow(BuildContext context, S s, int seat, PokerHand? hand, VoidCallback changed) {
    final session = _controller.session;
    final isHero = seat == TableSession.heroSeat;
    final shown = session.revealedSeats.contains(seat);
    final online = _online;
    final player = session.players[seat];
    final style = session.styles[seat];
    // Online, only the host changes the bots (from the next hand); cards and stacks are the server's.
    final canPickStyle = online == null ? !isHero : online.isHost && player.isBot;
    return ListTile(
      leading: SizedBox(
        width: 52,
        child: Text(hand == null ? '' : hand.positionOf(seat).label, style: const TextStyle(color: Colors.white60)),
      ),
      title: Text(isHero ? s.you : session.players[seat].name),
      // The stack (a new one from the next hand on), and a bot's style, which a click changes.
      subtitle: Text([
        formatBb(hand?.stackOf(seat) ?? session.stacks[seat], unit: true) +
            (session.stackEdits.containsKey(seat)
                ? ' → ${formatBb(session.stackEdits[seat]!, unit: true)} (${s.nextHand})'
                : ''),
        if (!isHero && style != null) session.hiddenStyles[seat] ? s.random : s.style(style),
        // Online, another device plays it: a person, or a bot on the host's device.
        if (player.remote && player.isBot) s.botBadge,
      ].join(' · ')),
      onTap: canPickStyle
          ? () async {
              await _pickStyle(context, seat);
              changed();
            }
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isHero)
            IconButton(
              icon: Icon(shown ? Icons.visibility : Icons.visibility_off),
              onPressed: online != null
                  ? null
                  : () {
                      _controller.toggleCards(seat);
                      changed();
                    },
            ),
          IconButton(
            icon: const Icon(Icons.savings_outlined),
            onPressed: online != null
                ? null
                : () async {
                    await _editStack(context, seat);
                    changed();
                  },
          ),
        ],
      ),
    );
  }

  /// Asks for [seat]'s stack (in BB) for the next hand.
  Future<void> _editStack(BuildContext context, int seat) async {
    final session = _controller.session;
    final s = S.of(context);
    final text = TextEditingController(
      text: formatBb(session.stackEdits[seat] ?? session.hand?.stackOf(seat) ?? session.stacks[seat]),
    );
    final bb = await showDialog<double>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final value = double.tryParse(text.text.trim().replaceAll(',', '.'));
          final valid = value != null && value >= 1 && value <= 10000;
          void done() {
            if (valid) Navigator.of(context).pop(value);
          }

          return AlertDialog(
            title: Text(
                '${seat == TableSession.heroSeat ? s.you : session.players[seat].name} · ${s.stack}'),
            content: TextField(
              controller: text,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(suffixText: 'BB', helperText: s.nextHand),
              onChanged: (_) => setDialogState(() {}),
              onSubmitted: (_) => done(),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.cancel)),
              FilledButton(onPressed: valid ? done : null, child: Text(s.ok)),
            ],
          );
        },
      ),
    );
    if (bb == null) return;
    session.setStack(seat, (bb * TableConfig.bigBlind).round());
  }

  /// Lets the user change one bot's style (Guess the GTO mode).
  Future<void> _pickStyle(BuildContext context, int seat) async {
    final session = _controller.session;
    final current = session.hiddenStyles[seat] ? null : session.styles[seat];
    final s = S.of(context);
    final picked = await showModalBottomSheet<(BotStyle?,)>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text('${session.players[seat].name} · ${s.changeStyle}'),
              trailing: const HelpButton(section: GlossarySection.styles),
            ),
            for (final style in const [BotStyle.gto, BotStyle.tag, BotStyle.lag, BotStyle.station, BotStyle.nit])
              ListTile(
                leading: Icon(style == current ? Icons.check_circle : Icons.radio_button_unchecked),
                title: Text(s.style(style)),
                onTap: () => Navigator.of(context).pop((style,)),
              ),
            // Online, the host can also make a bot random again.
            if (_online != null)
              ListTile(
                leading: Icon(current == null ? Icons.check_circle : Icons.radio_button_unchecked),
                title: Text(s.random),
                onTap: () => Navigator.of(context).pop((null,)),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    _controller.setStyle(seat, picked.$1);
  }

  /// Online: the room as everyone sees it, live: who has each seat and the
  /// rules. The host adds or takes away bots, removes players (a tap on
  /// their seat) and changes the help, the time limit and what players may
  /// see (from the next hand); the table itself stays as set in the lobby.
  /// Greyed out for everyone else.
  Future<void> _tableSettings(BuildContext context, OnlineTableController online) async {
    final s = S.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StreamBuilder<void>(
        stream: online.client.changes,
        builder: (context, _) {
          final room = online.client.room;
          final host = online.isHost && !online.ended;
          final theme = Theme.of(context);
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  Row(
                    children: [
                      Text(s.tableSettings, style: theme.textTheme.titleMedium),
                      const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.host]),
                    ],
                  ),
                  Text(s.fromNextHand, style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60)),
                  // Friends can still join (from the next hand).
                  if (room != null && !online.ended) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 16,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () => showInvite(context, online.client, room.code),
                          icon: const Icon(Icons.share),
                          label: Text(s.invite),
                        ),
                        if (online.client.host case final roomHost?) WaysIn(host: roomHost),
                      ],
                    ),
                  ],
                  if (room != null) ...[
                    RoomSection(
                      title: s.players,
                      child: RoomSeats(
                        room: room,
                        mySeat: online.client.mySeat,
                        host: host,
                        onAdd: (style) => online.addBot(style),
                        onStyle: online.setBotStyle,
                        onRemove: online.removeBot,
                        onRemovePlayer: online.removePlayer,
                      ),
                    ),
                    RoomRules(room: room, host: host, onChange: online.changeSettings),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Everything the top bar offers, behind one ☰ button.
  Widget _menu(BuildContext context) {
    final session = _controller.session;
    final training = _controller.guessGto;
    final online = _online;
    final s = S.of(context);
    return PopupMenuButton<String>(
      icon: const Icon(Icons.menu),
      onSelected: (choice) {
        switch (choice) {
          case 'cards':
            _controller.toggleAllCards();
          case 'players':
            _players(context);
          case 'table':
            if (online != null) _tableSettings(context, online);
          case 'chat':
            if (online != null) _chat(context, online);
          case 'sitOut':
            online?.sitOut(!online.sitsOut);
          case 'history':
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => HistoryScreen(session: session)));
          case 'spots':
            if (_drill case final drill?) {
              Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => SavedSpotsScreen(drills: drill.drills)));
            }
          case 'glossary':
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GlossaryScreen()));
          case 'close':
            online?.closeRoom();
          case 'leave':
            _leave(context);
        }
      },
      itemBuilder: (context) {
        PopupMenuItem<String> item(String value, IconData icon, String text, {bool enabled = true}) =>
            PopupMenuItem(
              value: value,
              enabled: enabled,
              height: 40,
              child: Row(children: [Icon(icon, size: 20), const SizedBox(width: 12), Flexible(child: Text(text))]),
            );
        return [
          // First: the table itself (online, its seats, bots and rules; here,
          // the players' stacks, styles and cards). Online without help,
          // only the host has it (player against player). Drills deal each
          // hand at its own table: greyed out.
          if (online == null)
            item('players', Icons.tune, s.editTable, enabled: _drill == null)
          else if (online.isHost || training)
            item('table', Icons.tune, s.editTable),
          // Online, cards stay hidden and the host picks the help (see the glossary).
          if (training)
            item('cards', _controller.allCardsShown ? Icons.visibility_off : Icons.visibility,
                _controller.allCardsShown ? s.hideAllCards : s.showAllCards,
                enabled: online == null),
          // The scores of past hands: only with help on.
          if (training) item('history', Icons.history, s.history),
          // Drills: every saved spot, with when it is due.
          if (_drill != null) item('spots', Icons.event_repeat, s.savedSpots),
          // Online, the room's chat, with how many messages came since it was last open.
          if (online != null)
            item('chat', Icons.chat_bubble_outline, switch (_unreadChat(online)) {
              0 => s.chat,
              final unread => '${s.chat} ($unread)',
            }),
          // Online: not dealt in from the next hand, or back (greyed out when out of chips).
          if (online != null)
            online.sitsOut
                ? item('sitOut', Icons.play_circle_outline, s.imBack, enabled: online.canSitOut)
                : item('sitOut', Icons.pause_circle_outline, s.sitOut, enabled: online.canSitOut),
          const PopupMenuDivider(),
          item('glossary', Icons.help_outline, s.glossary),
          if (online != null && online.isHost && !online.ended) item('close', Icons.cancel_outlined, s.closeRoom),
          item('leave', Icons.home_outlined, online == null ? s.mainMenu : s.leave),
        ];
      },
    );
  }

  /// Others' chat messages since the chat (or the lobby) was last on screen.
  int _unreadChat(OnlineTableController online) =>
      online.client.chat.where((line) => line.n > _chatSeen && !line.you).length;

  /// Leaves the table; online, after asking (the seat is empty from the
  /// next hand).
  Future<void> _leave(BuildContext context) async {
    final online = _online;
    if (online != null && !online.ended) {
      final s = S.of(context);
      final sure = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(s.leaveTable),
          content: Text(s.leaveWarning(host: online.isHost)),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(s.cancel)),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(s.leave)),
          ],
        ),
      );
      if (sure != true || !context.mounted) return;
    }
    Navigator.of(context).pop();
  }

  /// Enter: deals the next hand, continues after a score, or plays the
  /// choice made in the panel.
  void _nextHand() {
    // Online the table doesn't wait: choosing first, then OK on a score.
    if (_online != null) {
      if (_controller.heroOptions != null && _controller.heroScore == null) {
        _panel.currentState?.submit();
      } else if (_controller.heroScore != null) {
        _controller.continueHand();
      }
      return;
    }
    if (_controller.handOver) {
      _controller.startNextHand();
    } else if (_controller.heroScore != null || _drill?.outcome != null) {
      _controller.continueHand();
    } else if (_controller.heroMenu != null) {
      _panel.currentState?.submit();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final session = _controller.session;
        final s = S.of(context);
        return Scaffold(
          backgroundColor: const Color(0xFF0B0F12),
          // The keyboard (for the chat, over the table) leaves the table as it is.
          resizeToAvoidBottomInset: false,
          appBar: AppBar(
            backgroundColor: const Color(0xFF12171B),
            // Phones are played sideways: keep the bar slim when height is short.
            toolbarHeight: MediaQuery.sizeOf(context).height < 500 ? 44 : null,
            // Leaving the table is in the menu (Main Menu), not a back arrow.
            automaticallyImplyLeading: false,
            title: Text(switch (_controller) {
              final OnlineTableController online => s.room(online.roomCode),
              DrillController() => s.drills,
              _ => _controller.guessGto ? s.training : s.freePlay,
            }),
            actions: [
              if (session.handsFinished > 0)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    // Training: EV given up against optimal play (chips are mostly luck).
                    child: _controller.guessGto
                        ? Text(
                            '${s.evLoss} '
                            '${session.history.fold(0.0, (sum, h) => sum + h.evLost).toStringAsFixed(2)} BB · '
                            '${s.handsPlayed(session.handsFinished)}',
                            style: const TextStyle(color: Color(0xFFFFE082)),
                          )
                        : Text(
                            '${formatSignedBb(session.heroNet)} · ${s.handsPlayed(session.handsFinished)}',
                            style: TextStyle(
                              color: session.heroNet >= 0 ? const Color(0xFF81C784) : const Color(0xFFE57373),
                            ),
                          ),
                  ),
                ),
              _menu(context),
            ],
          ),
          body: PopScope(
            // Online, leaving asks first (the back gesture too).
            canPop: _online == null || _online!.ended,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _leave(context);
            },
            child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.keyF): _foldOrCheck,
                  const SingleActivator(LogicalKeyboardKey.keyC): _checkOrCall,
                  const SingleActivator(LogicalKeyboardKey.keyN): _nextHand,
                  const SingleActivator(LogicalKeyboardKey.enter): _nextHand,
                },
                child: Focus(
                  autofocus: true,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final table = Stack(
                        children: [
                          Positioned.fill(
                            child: LayoutBuilder(
                              builder: (context, area) => _TableArea(
                                controller: _controller,
                                geometry: TableGeometry(
                                  area.biggest,
                                  _controller.view.placeCount,
                                  places: _controller.view.places,
                                ),
                                onSeatTap: switch (_online) {
                                  // Online: a range, or a look at the player's cards.
                                  final online? => (seat) => _onlineSeat(context, online, seat),
                                  null => _controller.guessGto ? (seat) => _openRange(context, seat) : null,
                                },
                              ),
                            ),
                          ),
                          if (_notes.isNotEmpty)
                            Positioned(
                              top: 8,
                              left: 8,
                              right: 8,
                              child: _TableNotes(notes: _notes),
                            ),
                          // Online, once the game is over: who won, until everyone is back in the lobby.
                          if (_online case final online? when online.gameOver != null)
                            Positioned.fill(child: _GameOverBanner(text: _gameOverText(s, online))),
                        ],
                      );
                      final panel = DecisionPanel(
                        key: _panel,
                        controller: _controller,
                        onLobby: switch (_online) {
                          final online? => () => _openLobby(context, online),
                          null => null,
                        },
                      );
                      // Landscape (phones are played sideways): the table on the left
                      // half, the decisions on the right. Portrait: one above the other.
                      if (constraints.maxWidth >= constraints.maxHeight) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: table),
                            SizedBox(width: constraints.maxWidth / 2, child: panel),
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: table),
                          SizedBox(height: constraints.maxHeight * 0.5, child: panel),
                        ],
                      );
                    },
                  ),
                ),
              ),
          ),
        );
      },
    );
  }
}

/// Places [child] so that its center is at [point].
Widget _centeredAt(Offset point, Widget child, {Key? key}) => Positioned(
      key: key,
      left: point.dx,
      top: point.dy,
      child: FractionalTranslation(translation: const Offset(-0.5, -0.5), child: child),
    );

/// "Game over: Alice wins" ("you win" for the user).
String _gameOverText(S s, OnlineTableController online) {
  final over = online.gameOver!;
  return s.gameOver(over.name, you: over.seat != null && over.seat == online.client.mySeat);
}

/// Online, once the game is over: who won, big, in the middle of the table
/// (clicks go through).
class _GameOverBanner extends StatelessWidget {
  const _GameOverBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 300),
          builder: (context, t, child) => Opacity(opacity: t, child: child),
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xF0263238),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFD54F), width: 2),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4))],
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: const Color(0xFFFFE082),
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A note shown at the top of an online table for [life]: what everyone is
/// told ([text]), or a chat message ([chat]).
typedef _Note = ({ChatLine? chat, String text, Duration life, Timer timer});

/// Online: what everyone is told, and others' chat messages (2 lines at
/// most: the rest is in ☰ > Chat), one under the other at the top of the
/// table: never over the player's own seat (at the bottom) or the choices
/// (the other half of the screen). Each fades in, then out as it goes.
/// Clicks go through to the seats below.
class _TableNotes extends StatelessWidget {
  const _TableNotes({required this.notes});

  final List<_Note> notes;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final note in notes)
            TweenAnimationBuilder<double>(
              key: ObjectKey(note.timer),
              tween: Tween(begin: 0, end: 1),
              duration: note.life,
              builder: (context, t, child) {
                final ms = note.life.inMilliseconds;
                final opacity = min(t * ms / 200, (1 - t) * ms / 400).clamp(0.0, 1.0);
                return Opacity(opacity: opacity, child: child);
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 4),
                constraints: const BoxConstraints(maxWidth: 420),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  color: const Color(0xEB263238),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 2))],
                ),
                child: switch (note.chat) {
                  final line? => ChatLineText(line: line, maxLines: 2, textAlign: TextAlign.center),
                  null => Text(note.text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _TableArea extends StatelessWidget {
  const _TableArea({required this.controller, required this.geometry, this.onSeatTap});

  final TableController controller;
  final TableGeometry geometry;

  /// Opens a seat's options (Guess the GTO mode).
  final ValueChanged<int>? onSeatTap;

  @override
  Widget build(BuildContext context) {
    final g = geometry;
    final view = controller.view;
    final seatSize = SeatWidget.sizeFor(g);
    final livePots = [for (final (i, amount) in view.pots.indexed) if (amount > 0) (i, amount)];

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: CustomPaint(painter: _FeltPainter(g, AppSettings.of(context).felt))),

        for (final (i, card) in view.board.indexed)
          _centeredAt(g.boardSlot(i), CardView(width: g.cardWidth, card: card), key: ValueKey('board$i')),

        if (livePots.isNotEmpty)
          _centeredAt(
            g.pot,
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (_, amount) in livePots)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4 * g.scale),
                    child: ChipStack(amount: amount, chipSize: g.chipSize * 1.1),
                  ),
              ],
            ),
            key: const ValueKey('pot'),
          ),

        for (final (i, seat) in view.seats.indexed)
          if (seat.bet > 0)
            _centeredAt(g.bet(i), ChipStack(amount: seat.bet, chipSize: g.chipSize),
                key: ValueKey('bet$i')),

        for (final (i, seat) in view.seats.indexed)
          Positioned(
            key: ValueKey('seat$i'),
            left: g.seat(i).dx - seatSize.width / 2,
            top: g.seat(i).dy - g.seatBoxSize.height / 2 - g.seatCardsAbove,
            child: _Hoverable(
              onTap: onSeatTap == null ? null : () => onSeatTap!(i),
              builder: (hovered) => SeatWidget(
                seat: seat,
                geometry: g,
                isActing: view.actingSeat == i,
                isHero: controller.isUserSeat(i),
                showStyle: switch (controller) {
                  // Online, a bot's style as the server shows it.
                  final OnlineTableController online => online.showStyles && seat.info.isBot,
                  _ => controller.session.config.stylesVisible && !controller.session.hiddenStyles[i],
                },
                hovered: hovered,
                turnEnds: view.actingSeat == i ? view.turnEnds : null,
                turnLimit: view.turnLimit,
              ),
            ),
          ),

        // Online: those out of chips, at the table without playing.
        for (final other in view.others)
          Positioned(
            key: ValueKey('other${other.roomSeat}'),
            left: g.place(other.place).dx - seatSize.width / 2,
            top: g.place(other.place).dy - g.seatBoxSize.height / 2 - g.seatCardsAbove,
            child: SeatWidget(seat: other.view, geometry: g, isActing: false, isHero: other.user),
          ),

        if (view.buttonSeat != null)
          AnimatedPositioned(
            key: const ValueKey('dealer'),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            left: g.dealerButton(view.buttonSeat!).dx - 11 * g.scale,
            top: g.dealerButton(view.buttonSeat!).dy - 11 * g.scale,
            child: _DealerButton(size: 22 * g.scale),
          ),

        if (view.results.isNotEmpty)
          _centeredAt(
            g.center + Offset(0, g.cardHeight / 2 + 34 * g.scale),
            Container(
              constraints: BoxConstraints(maxWidth: g.size.width * 0.8),
              padding: EdgeInsets.symmetric(horizontal: 12 * g.scale, vertical: 6 * g.scale),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10 * g.scale),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final result in view.results)
                    Text(
                      _resultLine(S.of(context), result, view, controller.isUserSeat),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: const Color(0xFFFFE082), fontSize: 12.5 * g.scale),
                    ),
                ],
              ),
            ),
            key: const ValueKey('results'),
          ),

        for (final item in controller.flying) _Flight(key: ValueKey('flight${item.id}'), item: item, g: g),
      ],
    );
  }
}

/// Chips or a card travelling across the table.
class _Flight extends StatelessWidget {
  const _Flight({super.key, required this.item, required this.g});

  final FlyingItem item;
  final TableGeometry g;

  @override
  Widget build(BuildContext context) {
    final from = g.resolve(item.from);
    final to = g.resolve(item.to);
    final child = item.isCard
        ? CardView(width: g.cardWidth, card: item.card, faceUp: item.faceUp)
        : ChipStack(amount: item.chips, chipSize: g.chipSize, showLabel: false);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: item.duration,
      curve: Curves.easeInOutCubic,
      child: child,
      builder: (context, t, child) {
        // A slight arc looks more like a toss than a slide.
        final point = Offset.lerp(from, to, t)! - Offset(0, sin(pi * t) * 16 * g.scale);
        return _centeredAt(point, Opacity(opacity: item.fadeOut ? 1 - t : 1, child: child));
      },
    );
  }
}

class _DealerButton extends StatelessWidget {
  const _DealerButton({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: Text(
        'D',
        style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: size * 0.55),
      ),
    );
  }
}

class _FeltPainter extends CustomPainter {
  _FeltPainter(this.g, this.felt);

  final TableGeometry g;
  final FeltStyle felt;

  @override
  void paint(Canvas canvas, Size size) {
    final rail = Rect.fromCenter(center: g.center, width: g.radiusX * 2 * 0.97, height: g.radiusY * 2 * 0.94);
    canvas.drawOval(
      rail.shift(Offset(0, 6 * g.scale)),
      Paint()
        ..color = Colors.black
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 14 * g.scale),
    );
    canvas.drawOval(
      rail,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF6D4C41), Color(0xFF3E2723)],
        ).createShader(rail),
    );
    final cloth = rail.deflate(12 * g.scale);
    canvas.drawOval(
      cloth,
      Paint()
        ..shader = RadialGradient(
          colors: [felt.center, felt.middle, felt.edge],
          stops: const [0, 0.65, 1],
        ).createShader(cloth),
    );
    canvas.drawOval(
      cloth.deflate(20 * g.scale),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * g.scale
        ..color = Colors.white.withValues(alpha: 0.08),
    );
    // Faint outlines where the board cards go.
    final slotPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.12);
    for (var i = 0; i < 5; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: g.boardSlot(i), width: g.cardWidth, height: g.cardHeight),
          Radius.circular(g.cardWidth * 0.1),
        ),
        slotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_FeltPainter old) =>
      old.g.size != g.size || old.g.seatCount != g.seatCount || old.felt != felt;
}

/// One pot's result, e.g. "Bob wins 12 BB · Two Pair, Ks and 7s", or with
/// side pots "Side pot 1: Alice wins 30 BB · Flush, A high". [isUser] says
/// which seat is the user's.
String _resultLine(S s, PotResult result, TableViewState view, bool Function(int seat) isUser) {
  final e = result.award;
  String name(int seat) => isUser(seat) ? s.you : view.seats[seat].info.name;
  final amount = formatBb(e.amount, unit: true);
  final pot = e.potIndex > 0 ? '${s.sidePot(e.potIndex)}: ' : (result.sidePots ? '${s.mainPot}: ' : '');
  final winners = e.shares.keys.toList();
  final won = winners.length > 1
      ? s.split(s.listNames([for (final seat in winners) name(seat)]), amount)
      : s.wins(name(winners.single), amount, you: isUser(winners.single));
  final hand = e.winningHand;
  return '$pot$won${hand == null ? '' : ' · ${s.hand(hand)}'}';
}

/// Something clickable that lights up under the mouse: shows the hand
/// cursor and tells [builder] when it is hovered.
class _Hoverable extends StatefulWidget {
  const _Hoverable({required this.onTap, required this.builder});

  final VoidCallback? onTap;
  final Widget Function(bool hovered) builder;

  @override
  State<_Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<_Hoverable> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    if (onTap == null) return widget.builder(false);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(onTap: onTap, child: widget.builder(_hovered)),
    );
  }
}
