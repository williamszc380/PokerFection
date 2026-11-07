import 'dart:math';

import 'package:flutter/material.dart';

import '../app/app_settings.dart';
import '../bots/bot.dart';
import '../engine/positions.dart';
import '../engine/rules.dart';
import '../game/table_session.dart';
import '../l10n/strings.dart';
import '../online/protocol.dart';
import '../online/timing.dart';
import 'format.dart';
import 'glossary.dart';
import 'online/room_scope.dart';
import 'table_screen.dart';

/// Quick choices for every opponent's style: random, or one style for all.
const _opponentChoices = <BotStyle?>[BotStyle.gto, null, BotStyle.tag, BotStyle.lag, BotStyle.station, BotStyle.nit];

/// Where the user sets up a game: the table (top), then the rules (bottom).
///
/// While the user hosts a room it sets up the room's Hold'em instead (room
/// mode): the help (GTO Training or Free Play), the seats, stacks, time,
/// styles, reset stacks, rebuys and the rules; Open Table makes Hold'em the
/// room's game with them and opens its table for everyone (bots are added
/// there, on the empty seats).
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _random = Random();
  bool _training = true;

  /// Advanced training (percentages and scores) instead of simple.
  bool _advanced = false;
  int _stackBb = 100;

  /// The last quick choice for the opponents' styles (null = random); unset
  /// once single players were changed.
  BotStyle? _opponents = BotStyle.gto;
  bool _opponentsSet = true;
  bool _customize = false;
  late List<PlayerInfo> _players = _withStyles(TableConfig.quickPlayers(count: 2, stackBb: 100), BotStyle.gto);
  Position? _position;
  int _ante = 0;
  RaiseRule _raiseRule = RaiseRule.standard;
  bool _resetStacks = false;
  bool _showStyles = false;
  bool _showHands = false;

  /// Room mode (see the class comment): the room's Hold'em rules as this
  /// screen last read them. When the room's change (the table's Rules,
  /// while this screen waited under the table), they are read again, so
  /// Open Table never sends older rules back.
  RoomSettings? _roomSeen;
  int _seats = 8;
  int _turnLimit = OnlineTiming.defaultTurnLimit;
  bool _rebuys = false;

  static const _stackChoices = [10, 20, 40, 60, 100, 150, 200];
  static const _stackOptions = [5, 10, 15, 20, 25, 30, 40, 50, 60, 80, 100, 125, 150, 200];
  static const _anteChoices = [0, 10, 25];

  int get _count => _players.length;

  /// GTO first, then the human-like styles.
  static const _styleOrder = [BotStyle.gto, BotStyle.tag, BotStyle.lag, BotStyle.station, BotStyle.nit];

  BotStyle _randomStyle() => BotStyle.humanLike[_random.nextInt(BotStyle.humanLike.length)];

  BotStyle _styleFor(BotStyle? choice) => choice ?? _randomStyle();

  List<PlayerInfo> _withStyles(List<PlayerInfo> players, BotStyle? choice) => [
    for (final p in players) p.isHero ? p : p.withStyle(_styleFor(choice)),
  ];

  void _setCount(int count) => setState(() {
    if (count < _count) {
      _players = _players.sublist(0, count);
    } else {
      final used = _players.map((p) => p.name).toSet();
      final free = [...TableConfig.botNames.where((n) => !used.contains(n))];
      _players = [
        ..._players,
        for (var i = _count; i < count; i++)
          PlayerInfo(name: free[i - _count], stackBb: _stackBb, style: _styleFor(_opponents)),
      ];
    }
    if (_position != null && !positionsForTable(count).contains(_position)) _position = null;
  });

  void _setStack(int bb) => setState(() {
    _stackBb = bb;
    _players = [for (final p in _players) p.copyWith(stackBb: bb)];
  });

  void _setOpponents(BotStyle? choice) => setState(() {
    _opponents = choice;
    _opponentsSet = true;
    _players = _withStyles(_players, choice);
  });

  void _start() {
    final config = TableConfig(
      players: List.unmodifiable(_players),
      heroPosition: _position,
      ante: _ante,
      raiseRule: _raiseRule,
      resetStacksEachHand: _resetStacks,
      guessGto: _training,
      advanced: _advanced,
      showStyles: _showStyles,
      showHands: _showHands,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TableScreen(config: config, speed: AppSettings.of(context).speed),
      ),
    );
  }

  /// The room's Hold'em rules as set here.
  RoomSettings get _roomSettings => RoomSettings(
    seats: _seats,
    stackBb: _stackBb,
    ante: _ante,
    raiseRule: _raiseRule,
    resetStacks: _resetStacks,
    rebuys: _rebuys && !_resetStacks,
    help: !_training ? HelpLevel.none : (_advanced ? HelpLevel.advanced : HelpLevel.simple),
    turnLimit: _turnLimit,
    showStyles: _showStyles,
  );

  /// Starts from the room's Hold'em rules (or its defaults), and takes
  /// them again whenever the room's change.
  void _readRoom(RoomState room) {
    final settings = room.game?.key == holdemKey ? (room.settings ?? const RoomSettings()) : const RoomSettings();
    if (settings == _roomSeen) return;
    _roomSeen = settings;
    _seats = settings.seats;
    _stackBb = settings.stackBb;
    _ante = settings.ante;
    _raiseRule = settings.raiseRule;
    _resetStacks = settings.resetStacks;
    _rebuys = settings.rebuys;
    _training = settings.help != HelpLevel.none;
    _advanced = settings.help == HelpLevel.advanced;
    _turnLimit = settings.turnLimit;
    _showStyles = settings.showStyles;
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final rooms = RoomScope.maybeOf(context);
    if (rooms != null && rooms.stage == RoomStage.open && rooms.isHost && rooms.room != null) {
      return _roomSetup(context, rooms, rooms.room!);
    }
    return Scaffold(
      appBar: AppBar(title: Text(s.newGame)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              // The table.
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(value: true, label: Text(s.training), icon: const Icon(Icons.school)),
                        ButtonSegment(value: false, label: Text(s.freePlay), icon: const Icon(Icons.style)),
                      ],
                      selected: {_training},
                      onSelectionChanged: (v) => setState(() => _training = v.single),
                    ),
                  ),
                  const HelpButton(section: GlossarySection.modes),
                ],
              ),
              if (_training) ...[
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, label: Text(s.simple)),
                    ButtonSegment(value: true, label: Text(s.advanced)),
                  ],
                  selected: {_advanced},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => setState(() => _advanced = v.single),
                ),
              ],
              _Section(
                title: s.players,
                child: _choices<int>(
                  values: [for (var n = 2; n <= 8; n++) n],
                  isSelected: (n) => n == _count,
                  label: (n) => '$n',
                  onSelected: _setCount,
                ),
              ),
              _Section(
                title: s.stack,
                child: _choices<int>(
                  values: _stackChoices,
                  isSelected: (bb) => _players.every((p) => p.stackBb == bb),
                  label: (bb) => '$bb BB',
                  onSelected: _setStack,
                ),
              ),
              _Section(
                title: s.opponentStyles,
                help: const HelpButton(section: GlossarySection.styles),
                child: _choices<BotStyle?>(
                  values: _opponentChoices,
                  isSelected: (o) => _opponentsSet && o == _opponents,
                  label: (o) => o == null ? s.random : s.style(o),
                  onSelected: _setOpponents,
                ),
              ),
              const SizedBox(height: 8),
              if (_training) ...[
                _switch(s.showStyles, _showStyles, (v) => _showStyles = v),
                _switch(s.showCards, _showHands, (v) => _showHands = v),
              ],
              _switch(s.customizeSeats, _customize, (v) => _customize = v),
              if (_customize) _playerRows(s),
              _Section(
                title: s.position,
                help: const HelpButton(section: GlossarySection.positions),
                child: _choices<Position?>(
                  // Seat order, clockwise from the small blind: blinds first, button last,
                  // each in the same place at every table size.
                  values: [null, ...allPositions],
                  isEnabled: (p) => p == null || positionsForTable(_count).contains(p),
                  isSelected: (p) => p == _position,
                  label: (p) => p?.label ?? s.rotate,
                  onSelected: (p) => setState(() => _position = p),
                ),
              ),
              const SizedBox(height: 8),
              _switch(s.resetStacks, _resetStacks, (v) => _resetStacks = v),
              // The rules of the game.
              const Padding(padding: EdgeInsets.only(top: 20), child: _DashedLine()),
              _Section(
                title: s.rules,
                help: const HelpButton(section: GlossarySection.rules),
                child: _rules(context, s),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.play_arrow),
                label: Text(s.start),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Room mode: the room's Hold'em (see the class comment).
  Widget _roomSetup(BuildContext context, RoomService rooms, RoomState room) {
    final s = S.of(context);
    final theme = Theme.of(context);
    _readRoom(room);
    // Seats taken stay: never fewer seats than that (Hold'em already picked).
    final taken = room.game?.key == holdemKey ? room.taken : 0;
    final playing = room.phase == RoomPhase.playing;
    return Scaffold(
      appBar: AppBar(title: Text(s.newGame)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            key: const ValueKey('room setup'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Card(
                key: const ValueKey('room setup note'),
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.groups, color: Color(0xFFFFE082)),
                      const SizedBox(width: 12),
                      Expanded(child: Text(s.roomSetupNote(room.code), style: theme.textTheme.bodyMedium)),
                      const HelpButton(
                        section: GlossarySection.online,
                        terms: [GlossaryTerm.roomGame, GlossaryTerm.helpLevel],
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(value: true, label: Text(s.training), icon: const Icon(Icons.school)),
                        ButtonSegment(value: false, label: Text(s.freePlay), icon: const Icon(Icons.style)),
                      ],
                      selected: {_training},
                      onSelectionChanged: (v) => setState(() => _training = v.single),
                    ),
                  ),
                  const HelpButton(section: GlossarySection.modes),
                ],
              ),
              if (_training) ...[
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, label: Text(s.simple)),
                    ButtonSegment(value: true, label: Text(s.advanced)),
                  ],
                  selected: {_advanced},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => setState(() => _advanced = v.single),
                ),
              ],
              _Section(
                title: s.players,
                child: _choices<int>(
                  values: [for (var n = 2; n <= 8; n++) n],
                  isEnabled: (n) => n >= taken,
                  isSelected: (n) => n == _seats,
                  label: (n) => '$n',
                  onSelected: (n) => setState(() => _seats = n),
                ),
              ),
              _Section(
                title: s.stack,
                child: _choices<int>(
                  values: {..._stackChoices, _stackBb}.toList()..sort(),
                  isSelected: (bb) => bb == _stackBb,
                  label: (bb) => '$bb BB',
                  onSelected: (bb) => setState(() => _stackBb = bb),
                ),
              ),
              _Section(
                title: s.timeLimit,
                help: const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.timeLimit]),
                child: _choices<int>(
                  values: OnlineTiming.turnLimits,
                  isSelected: (t) => t == _turnLimit,
                  label: s.turnLimit,
                  onSelected: (t) => setState(() => _turnLimit = t),
                ),
              ),
              const SizedBox(height: 8),
              _switch(s.showStyles, _showStyles, (v) => _showStyles = v),
              _switch(s.resetStacks, _resetStacks, (v) => _resetStacks = v),
              // Nobody runs out of chips when stacks are reset every hand: greyed out then.
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Row(
                  children: [
                    Flexible(child: Text(s.rebuys, style: theme.textTheme.titleMedium)),
                    const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.rebuys]),
                  ],
                ),
                value: _rebuys && !_resetStacks,
                onChanged: _resetStacks ? null : (v) => setState(() => _rebuys = v),
              ),
              const Padding(padding: EdgeInsets.only(top: 20), child: _DashedLine()),
              _Section(
                title: s.rules,
                help: const HelpButton(section: GlossarySection.rules),
                child: _rules(context, s),
              ),
              const SizedBox(height: 28),
              if (playing)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    s.endGameFirst,
                    key: const ValueKey('end game first'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFFFFCC80)),
                  ),
                ),
              FilledButton.icon(
                key: const ValueKey('open table'),
                onPressed: playing ? null : () => rooms.hostPick(holdemKey, holdem: _roomSettings),
                icon: const Icon(Icons.groups),
                label: Text(s.openTable),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _switch(String title, bool value, void Function(bool value) set) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    title: Text(title, style: Theme.of(context).textTheme.titleMedium),
    value: value,
    onChanged: (v) => setState(() => set(v)),
  );

  Widget _rules(BuildContext context, S s) {
    final theme = Theme.of(context);
    Widget label(String text, Widget help) => Row(
      children: [
        Text(text, style: theme.textTheme.labelLarge),
        help,
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label(
          s.minRaise,
          const HelpButton(section: GlossarySection.rules, terms: [GlossaryTerm.minRaise, GlossaryTerm.houseRule]),
        ),
        _choices<RaiseRule>(
          values: RaiseRule.values,
          isSelected: (r) => r == _raiseRule,
          label: s.raiseRule,
          onSelected: (r) => setState(() => _raiseRule = r),
        ),
        const SizedBox(height: 12),
        label(s.ante, const HelpButton(section: GlossarySection.amounts, terms: [GlossaryTerm.ante])),
        _choices<int>(
          values: _anteChoices,
          isSelected: (a) => a == _ante,
          label: (a) => a == 0 ? s.noAnte : formatBb(a, unit: true),
          onSelected: (a) => setState(() => _ante = a),
        ),
      ],
    );
  }

  /// One row per player: name, stack and (for bots) style.
  Widget _playerRows(S s) {
    return Card(
      margin: const EdgeInsets.only(top: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Column(
          children: [
            for (final (i, player) in _players.indexed)
              Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      player.isHero ? s.you : player.name,
                      style: TextStyle(
                        fontWeight: player.isHero ? FontWeight.w700 : FontWeight.normal,
                        color: player.isHero ? const Color(0xFFFFE082) : null,
                      ),
                    ),
                  ),
                  DropdownButton<int>(
                    value: player.stackBb,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final bb in {..._stackOptions, player.stackBb}.toList()..sort())
                        DropdownMenuItem(value: bb, child: Text('$bb BB')),
                    ],
                    onChanged: (bb) => setState(() => _players[i] = player.copyWith(stackBb: bb)),
                  ),
                  const Spacer(),
                  if (!player.isHero)
                    DropdownButton<BotStyle?>(
                      value: player.style,
                      underline: const SizedBox.shrink(),
                      items: [
                        for (final style in _styleOrder) DropdownMenuItem(value: style, child: Text(s.style(style))),
                      ],
                      onChanged: (style) => setState(() {
                        _players[i] = player.withStyle(style);
                        _opponentsSet = false;
                      }),
                    ),
                ],
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _setOpponents(null),
                icon: const Icon(Icons.shuffle),
                label: Text(s.shuffleStyles),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Chips for [values]; the ones [isEnabled] says no to are greyed out.
  Widget _choices<T>({
    required List<T> values,
    required bool Function(T) isSelected,
    required String Function(T) label,
    required ValueChanged<T> onSelected,
    bool Function(T)? isEnabled,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in values)
          ChoiceChip(
            label: Text(label(value)),
            selected: isSelected(value),
            mouseCursor: WidgetStateMouseCursor.clickable,
            onSelected: isEnabled == null || isEnabled(value) ? (_) => onSelected(value) : null,
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.help, required this.child});

  final String title;

  /// A "?" button shown right after the title.
  final Widget? help;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              ?help,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// A thin dashed rule between the table setup and the rules.
class _DashedLine extends StatelessWidget {
  const _DashedLine();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 1,
    child: LayoutBuilder(
      builder: (context, constraints) {
        const dash = 6.0, gap = 4.0;
        final count = (constraints.maxWidth / (dash + gap)).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < count; i++)
              const SizedBox(
                width: dash,
                child: ColoredBox(color: Colors.white24),
              ),
          ],
        );
      },
    ),
  );
}
