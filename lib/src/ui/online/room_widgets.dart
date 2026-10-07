/// The room's seats and rules, as the lobby and the table (☰ > Edit
/// Table) show them. Everyone sees them, live as the host changes them;
/// only the host changes them (greyed out for everyone else), and removes
/// players.
library;

import 'package:flutter/material.dart';

import '../../bots/bot.dart';
import '../../engine/rules.dart';
import '../../l10n/strings.dart';
import '../../online/protocol.dart';
import '../../online/timing.dart';
import '../format.dart';
import '../glossary.dart';

/// The bot styles the host can pick, the secret random one last.
const pickableBotStyles = ['gto', 'tag', 'lag', 'station', 'nit', 'random'];

/// A bot style as sent (see botStyleNames), in words.
String botStyleName(S s, String style) {
  final known = BotStyle.values.asNameMap()[style];
  return known == null ? s.random : s.style(known);
}

/// One room seat: who has it (or that it is empty) and what is coming at
/// the next hand; for a bot, its style. The host picks a bot's style
/// ([onStyle]) and takes it away ([onRemove]); a tap on another person's
/// seat offers to remove them ([onRemovePlayer], asked first).
class SeatRow extends StatelessWidget {
  const SeatRow({
    super.key,
    required this.seat,
    required this.room,
    required this.mySeat,
    this.onStyle,
    this.onRemove,
    this.onRemovePlayer,
  });

  final SeatInfo seat;
  final RoomState room;

  /// This player's room seat.
  final int? mySeat;
  final ValueChanged<String>? onStyle;
  final VoidCallback? onRemove;
  final VoidCallback? onRemovePlayer;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final mine = seat.seat == mySeat;
    final bot = seat.kind == SeatKind.bot;
    final empty = seat.isEmpty;
    final details = [
      if (seat.seat == room.host) s.host,
      if (bot) s.botBadge,
      if (bot && seat.style != null && onStyle == null) botStyleName(s, seat.style!),
      if (seat.status == SeatStatus.left) s.leftBadge,
      if (seat.out) s.outBadge,
      if (seat.sittingOut) s.sittingOutBadge,
      if (seat.leaving) s.leavingBadge,
      if (seat.joining != null) '${s.nextHandBadge}: ${seat.joining}',
    ];
    final highlight = mine ? const Color(0xFFFFE082) : null;
    // Another person, for the host: a tap offers to remove them.
    final onRemovePlayer = this.onRemovePlayer;
    final person = seat.kind == SeatKind.human && !mine && seat.seat != room.host && onRemovePlayer != null;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: person ? () => _playerOptions(context, s, onRemovePlayer) : null,
      leading: Icon(
        empty ? Icons.event_seat_outlined : (bot ? Icons.smart_toy_outlined : Icons.person),
        color: highlight ?? (bot || empty ? Colors.white38 : null),
      ),
      title: Text(
        empty ? s.emptySeat : seat.name,
        style: TextStyle(
          fontWeight: mine ? FontWeight.w700 : null,
          color: highlight ?? (empty ? Colors.white38 : null),
        ),
      ),
      subtitle: details.isEmpty ? null : Text(details.join(' · ')),
      trailing: bot && (onStyle != null || onRemove != null)
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<String>(
                  value: seat.style ?? defaultBotStyle,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final style in pickableBotStyles)
                      DropdownMenuItem(value: style, child: Text(botStyleName(s, style))),
                  ],
                  onChanged: onStyle == null
                      ? null
                      : (style) {
                          if (style != null) onStyle!(style);
                        },
                ),
                IconButton(
                  tooltip: s.removeBot,
                  icon: const Icon(Icons.close),
                  onPressed: seat.leaving ? null : onRemove,
                ),
              ],
            )
          : (person ? const Icon(Icons.more_vert, color: Colors.white38) : null),
    );
  }

  /// The host's choice for this person: Remove (greyed out once they left,
  /// or go when the hand ends), asked first.
  Future<void> _playerOptions(BuildContext context, S s, VoidCallback remove) async {
    final going = seat.status == SeatStatus.left || seat.leaving;
    final picked = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(seat.name, style: Theme.of(context).textTheme.titleMedium)),
            ListTile(
              key: const ValueKey('remove player'),
              leading: const Icon(Icons.person_remove_outlined),
              title: Text(s.removePlayer),
              enabled: !going,
              trailing: const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.host]),
              onTap: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );
    if (picked != true || !context.mounted) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.removePlayerQuestion(seat.name)),
        content: Text(s.removePlayerWarning),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(s.cancel)),
          FilledButton(
            key: const ValueKey('remove player sure'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.removePlayer),
          ),
        ],
      ),
    );
    if (sure == true) remove();
  }
}

/// The host's Add Bot, with the new bot's style. Greyed out ([onAdd] null)
/// when every seat is taken, and for everyone else.
class AddBotRow extends StatefulWidget {
  const AddBotRow({super.key, required this.onAdd});

  final ValueChanged<String>? onAdd;

  @override
  State<AddBotRow> createState() => _AddBotRowState();
}

class _AddBotRowState extends State<AddBotRow> {
  String _style = defaultBotStyle;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final onAdd = widget.onAdd;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('add bot'),
            onPressed: onAdd == null ? null : () => onAdd(_style),
            icon: const Icon(Icons.smart_toy_outlined, size: 18),
            label: Text(s.addBot),
          ),
          DropdownButton<String>(
            value: _style,
            underline: const SizedBox.shrink(),
            items: [
              for (final style in pickableBotStyles)
                DropdownMenuItem(value: style, child: Text(botStyleName(s, style))),
            ],
            onChanged: onAdd == null
                ? null
                : (style) {
                    if (style != null) setState(() => _style = style);
                  },
          ),
          const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.onlineBots]),
        ],
      ),
    );
  }
}

/// Every seat of the room, and the host's Add Bot.
class RoomSeats extends StatelessWidget {
  const RoomSeats({
    super.key,
    required this.room,
    required this.mySeat,
    required this.host,
    required this.onAdd,
    required this.onStyle,
    required this.onRemove,
    required this.onRemovePlayer,
  });

  final RoomState room;
  final int? mySeat;

  /// The host, still at the table: seats, bots and players can change.
  final bool host;
  final ValueChanged<String> onAdd;
  final void Function(int seat, String style) onStyle;
  final ValueChanged<int> onRemove;

  /// The host removes the person in a seat (by name: see RemovePlayer).
  final void Function(int seat, String name) onRemovePlayer;

  @override
  Widget build(BuildContext context) {
    final free = room.seats.any((seat) => seat.isEmpty && seat.joining == null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final seat in room.seats)
          SeatRow(
            seat: seat,
            room: room,
            mySeat: mySeat,
            onStyle: host ? (style) => onStyle(seat.seat, style) : null,
            onRemove: host ? () => onRemove(seat.seat) : null,
            onRemovePlayer: host ? () => onRemovePlayer(seat.seat, seat.name) : null,
          ),
        AddBotRow(onAdd: host && free ? onAdd : null),
      ],
    );
  }
}

/// The room's rules: seats, stacks, ante, min-raise, help, time, rebuys,
/// and what players may see. The host changes the table itself (rebuys
/// too) only in the lobby, the rest at any time (during the game, from the
/// next hand).
class RoomRules extends StatelessWidget {
  const RoomRules({super.key, required this.room, required this.host, required this.onChange});

  final RoomState room;

  /// The host, still at the table: the rules can change.
  final bool host;
  final ValueChanged<RoomSettings> onChange;

  static const _stackChoices = [10, 20, 40, 60, 100, 150, 200];
  static const _anteChoices = [0, 10, 25];

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final settings = room.settings;
    final table = host && room.phase == RoomPhase.lobby;
    final titleStyle = Theme.of(context).textTheme.titleMedium;
    Widget toggle(String title, bool value, ValueChanged<bool>? onChanged, {Widget? help}) => SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Row(
        children: [
          Flexible(child: Text(title, style: titleStyle)),
          ?help,
        ],
      ),
      value: value,
      onChanged: onChanged,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RoomSection(
          title: s.seats,
          child: choiceChips<int>(
            values: [for (var n = 2; n <= 8; n++) n],
            selected: settings.seats,
            label: (n) => '$n',
            // Never fewer than are taken.
            enabled: (n) => table && n >= room.taken,
            onSelected: (n) => onChange(settings.copyWith(seats: n)),
          ),
        ),
        RoomSection(
          title: s.stack,
          child: choiceChips<int>(
            values: {..._stackChoices, settings.stackBb}.toList()..sort(),
            selected: settings.stackBb,
            label: (bb) => '$bb BB',
            enabled: (_) => table,
            onSelected: (bb) => onChange(settings.copyWith(stackBb: bb)),
          ),
        ),
        RoomSection(
          title: s.ante,
          help: const HelpButton(section: GlossarySection.amounts, terms: [GlossaryTerm.ante]),
          child: choiceChips<int>(
            values: {..._anteChoices, settings.ante}.toList()..sort(),
            selected: settings.ante,
            label: (a) => a == 0 ? s.noAnte : formatBb(a, unit: true),
            enabled: (_) => table,
            onSelected: (a) => onChange(settings.copyWith(ante: a)),
          ),
        ),
        RoomSection(
          title: s.minRaise,
          help: const HelpButton(
            section: GlossarySection.rules,
            terms: [GlossaryTerm.minRaise, GlossaryTerm.houseRule],
          ),
          child: choiceChips<RaiseRule>(
            values: RaiseRule.values,
            selected: settings.raiseRule,
            label: s.raiseRule,
            enabled: (_) => table,
            onSelected: (r) => onChange(settings.copyWith(raiseRule: r)),
          ),
        ),
        RoomSection(
          title: s.help,
          help: const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.helpLevel]),
          child: choiceChips<HelpLevel>(
            values: HelpLevel.values,
            selected: settings.help,
            label: s.helpLevel,
            enabled: (_) => host,
            onSelected: (level) => onChange(settings.copyWith(help: level)),
          ),
        ),
        RoomSection(
          title: s.timeLimit,
          help: const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.timeLimit]),
          child: choiceChips<int>(
            values: OnlineTiming.turnLimits,
            selected: settings.turnLimit,
            label: s.turnLimit,
            enabled: (_) => host,
            onSelected: (seconds) => onChange(settings.copyWith(turnLimit: seconds)),
          ),
        ),
        const SizedBox(height: 8),
        // Nobody runs out of chips when stacks are reset every hand: greyed out then.
        toggle(
          s.rebuys,
          settings.rebuys,
          table && !settings.resetStacks ? (v) => onChange(settings.copyWith(rebuys: v)) : null,
          help: const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.rebuys]),
        ),
        toggle(s.resetStacks, settings.resetStacks, table ? (v) => onChange(settings.copyWith(resetStacks: v)) : null),
        toggle(s.showStyles, settings.showStyles, host ? (v) => onChange(settings.copyWith(showStyles: v)) : null),
        toggle(
          s.allowSeeCards,
          settings.showCards,
          host ? (v) => onChange(settings.copyWith(showCards: v)) : null,
          help: const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.seeCards]),
        ),
      ],
    );
  }
}

/// Chips for [values]; the ones not [enabled] are greyed out.
Widget choiceChips<T>({
  required List<T> values,
  required T selected,
  required String Function(T) label,
  required bool Function(T) enabled,
  required ValueChanged<T> onSelected,
}) => Wrap(
  spacing: 8,
  runSpacing: 8,
  children: [
    for (final value in values)
      ChoiceChip(
        label: Text(label(value)),
        selected: value == selected,
        onSelected: enabled(value)
            ? (_) {
                if (value != selected) onSelected(value);
              }
            : null,
      ),
  ],
);

/// A titled part of the room's page.
class RoomSection extends StatelessWidget {
  const RoomSection({super.key, required this.title, this.help, required this.child});

  final String title;

  /// A "?" button right after the title.
  final Widget? help;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            ?help,
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );
}
