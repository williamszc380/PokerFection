import 'dart:math';

import 'package:flutter/material.dart';

import '../app/app_settings.dart';
import '../bots/bot.dart';
import '../engine/positions.dart';
import '../engine/rules.dart';
import '../game/table_session.dart';
import '../gto/postflop/postflop_tree.dart';
import '../gto/preflop/preflop_tree.dart';
import '../l10n/strings.dart';
import 'format.dart';
import 'glossary.dart';
import 'table_screen.dart';

/// Quick choices for every opponent's style: random, or one style for all.
const _opponentChoices = <BotStyle?>[null, BotStyle.gto, BotStyle.tag, BotStyle.lag, BotStyle.station, BotStyle.nit];

/// Where the user sets up a game: the table (top), then the rules (bottom).
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _random = Random();
  bool _training = true;
  int _stackBb = 100;

  /// The last quick choice for the opponents' styles (null = random); unset
  /// once single players were changed.
  BotStyle? _opponents;
  bool _opponentsSet = true;
  bool _customize = false;
  late List<PlayerInfo> _players = _withStyles(TableConfig.quickPlayers(count: 2, stackBb: 100), null);
  Position? _position;
  int _ante = 0;
  RaiseRule _raiseRule = RaiseRule.standard;
  bool _resetStacks = false;
  List<double> _preflopSizes = PreflopSettings.defaultRaiseMultiples;
  List<double> _postflopSizes = PostflopSpec.defaultHeroSizes;
  bool _showStyles = false;
  bool _showHands = false;

  static const _stackChoices = [10, 20, 40, 60, 100, 150, 200];
  static const _stackOptions = [5, 10, 15, 20, 25, 30, 40, 50, 60, 80, 100, 125, 150, 200];
  static const _anteChoices = [0, 10, 25];

  int get _count => _players.length;

  /// GTO first, then the human-like styles.
  static const _styleOrder = [BotStyle.gto, BotStyle.tag, BotStyle.lag, BotStyle.station, BotStyle.nit];

  BotStyle _randomStyle() => BotStyle.humanLike[_random.nextInt(BotStyle.humanLike.length)];

  BotStyle _styleFor(BotStyle? choice) => choice ?? _randomStyle();

  List<PlayerInfo> _withStyles(List<PlayerInfo> players, BotStyle? choice) =>
      [for (final p in players) p.isHero ? p : p.withStyle(_styleFor(choice))];

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
      preflopSizes: _preflopSizes,
      postflopSizes: _postflopSizes,
      guessGto: _training,
      showStyles: _showStyles,
      showHands: _showHands,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => TableScreen(config: config, speed: AppSettings.of(context).speed)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
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
                  // Seat order, clockwise from the small blind: blinds first, button last.
                  values: [null, ...seatOrder(_count)],
                  isSelected: (p) => p == _position,
                  label: (p) => p?.label ?? s.rotate,
                  onSelected: (p) => setState(() => _position = p),
                ),
              ),
              const SizedBox(height: 8),
              _switch(s.resetStacks, _resetStacks, (v) => _resetStacks = v),
              _Section(
                title: s.betSizes,
                help: const HelpButton(section: GlossarySection.amounts, terms: [GlossaryTerm.betSizes]),
                child: _betSizes(context, s),
              ),
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

  Widget _switch(String title, bool value, void Function(bool value) set) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        value: value,
        onChanged: (v) => setState(() => set(v)),
      );

  /// Both size menus, editable: × drops a size, "Add" asks for a new one.
  Widget _betSizes(BuildContext context, S s) {
    final theme = Theme.of(context);
    Widget menu({
      required String title,
      required List<double> sizes,
      required String Function(double size) label,
      required Future<double?> Function() ask,
      required ValueChanged<List<double>> onChanged,
    }) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final size in sizes)
                  InputChip(
                    label: Text(label(size)),
                    onDeleted: sizes.length > 1 ? () => onChanged([...sizes]..remove(size)) : null,
                  ),
                if (sizes.length < 6)
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: Text(s.add),
                    onPressed: () async {
                      final size = await ask();
                      if (size != null && !sizes.contains(size)) onChanged([...sizes, size]..sort());
                    },
                  ),
              ],
            ),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        menu(
          title: s.preflop,
          sizes: _preflopSizes,
          label: s.multiple,
          ask: () => _askSize(context, s, s.preflopSizePrompt, suffix: '×', min: 1.25, max: 20),
          onChanged: (sizes) => setState(() => _preflopSizes = sizes),
        ),
        const SizedBox(height: 12),
        menu(
          title: s.postflop,
          sizes: _postflopSizes,
          label: s.potShare,
          ask: () => _askSize(context, s, s.postflopSizePrompt, suffix: '× ${s.potWord}', min: 0.05, max: 5),
          onChanged: (sizes) => setState(() => _postflopSizes = sizes),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => setState(() {
              _preflopSizes = PreflopSettings.defaultRaiseMultiples;
              _postflopSizes = PostflopSpec.defaultHeroSizes;
            }),
            child: Text(s.resetDefaults),
          ),
        ),
      ],
    );
  }

  /// Asks for a number between [min] and [max]; null if cancelled.
  Future<double?> _askSize(BuildContext context, S s, String title,
      {required String suffix, required double min, required double max}) {
    final text = TextEditingController();
    final answer = showDialog<double>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final value = double.tryParse(text.text.trim().replaceAll(',', '.'));
          final valid = value != null && value >= min && value <= max;
          void done() {
            if (valid) Navigator.of(context).pop((value * 100).round() / 100);
          }

          return AlertDialog(
            title: Text(title),
            content: TextField(
              controller: text,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                suffixText: suffix,
                helperText: s.between(S.number(min), S.number(max)),
              ),
              onChanged: (_) => setDialogState(() {}),
              onSubmitted: (_) => done(),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.cancel)),
              FilledButton(onPressed: valid ? done : null, child: Text(s.add)),
            ],
          );
        },
      ),
    );
    return answer.whenComplete(text.dispose);
  }

  Widget _rules(BuildContext context, S s) {
    final theme = Theme.of(context);
    Widget label(String text, Widget help) => Row(children: [Text(text, style: theme.textTheme.labelLarge), help]);
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

  Widget _choices<T>({
    required List<T> values,
    required bool Function(T) isSelected,
    required String Function(T) label,
    required ValueChanged<T> onSelected,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in values)
          ChoiceChip(
            label: Text(label(value)),
            selected: isSelected(value),
            onSelected: (_) => onSelected(value),
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
          Row(children: [Text(title, style: theme.textTheme.titleMedium), ?help]),
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
                for (var i = 0; i < count; i++) const SizedBox(width: dash, child: ColoredBox(color: Colors.white24)),
              ],
            );
          },
        ),
      );
}
