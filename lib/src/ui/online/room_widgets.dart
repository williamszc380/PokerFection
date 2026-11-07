/// The room's parts: the people (the lobby beside every screen, and the
/// Room tab), and on the room's table the seats, Join game and Leave seat,
/// the host's bots, switch and rules (RoomSeatsPanel). Everyone sees them,
/// live as they change; only the host changes the bots and the rules
/// (greyed out for everyone else), and removes members. The host picks
/// the game on Home (see gamePickable).
library;

import 'package:flutter/material.dart';

import '../../bots/bot.dart';
import '../../engine/rules.dart';
import '../../l10n/strings.dart';
import '../../online/protocol.dart';
import '../../online/timing.dart';
import '../format.dart';
import '../games.dart';
import '../glossary.dart';
import '../kit/l10n/kit_strings.dart';
import 'online_game_ui.dart';
import 'online_game_uis.dart';
import 'room_scope.dart';

/// The bot styles the host can pick, the secret random one last.
const pickableBotStyles = ['gto', 'tag', 'lag', 'station', 'nit', 'random'];

/// A bot style as sent (see botStyleNames), in words; a level of the
/// other games' bots (see botLevelNames) as the kit names it.
String botStyleName(S s, String style, {KitStrings? kit}) {
  final level = KitLevel.values.asNameMap()[style];
  if (level != null && kit != null) return kit.kitLevel(level);
  final known = BotStyle.values.asNameMap()[style];
  return known == null ? s.random : s.style(known);
}

/// The games this app can show online, with the version of each (a room
/// lists its own: RoomState.games): Hold'em, and each game whose online
/// part is in [uis] (onlineGameUis: see online_game_uis.dart).
Map<String, int> appOnlineGamesOf(Map<String, OnlineGameUi> uis) => {
  holdemKey: holdemGv,
  for (final ui in uis.values) ui.key: ui.gv,
};

/// The games this app can show online (see [appOnlineGamesOf]).
Map<String, int> get appOnlineGames => appOnlineGamesOf(onlineGameUis);

/// The games' online parts for [context]: the app room's (tests give
/// their own), else the app's.
Map<String, OnlineGameUi> gameUisOf(BuildContext context) => RoomScope.maybeOf(context)?.gameUis ?? onlineGameUis;

/// The games this app shows online, for [context] (see [gameUisOf]).
Map<String, int> shownGamesOf(BuildContext context) => appOnlineGamesOf(gameUisOf(context));

/// The key [info]'s game has in a room (RoomState.games, ChooseGame).
String roomGameKey(GameInfo info) => info.id == GameId.holdem ? holdemKey : info.id.key;

/// Whether the host may pick [info]'s game in [room]: the room can run it,
/// this app can show it (the same version: [shows], by default
/// [appOnlineGames]), and it is playable here at all (see GameInfo.ready).
/// Anything else is greyed out.
bool gamePickable(GameInfo info, RoomState room, {Map<String, int>? shows}) {
  final key = roomGameKey(info);
  final version = room.games[key];
  return info.ready && version != null && version == (shows ?? appOnlineGames)[key];
}

/// Whether [info]'s game can be played in the room [rooms] is in: Hold'em,
/// or a game whose online part is in the registry (RoomService.gameUis) at
/// the version the room runs ([gamePickable]). Home greys out the rest
/// while the user is in a room.
bool playableInRoom(GameInfo info, RoomService rooms) {
  final shows = appOnlineGamesOf(rooms.gameUis);
  final room = rooms.room;
  if (room == null) return info.ready && shows.containsKey(roomGameKey(info));
  return gamePickable(info, room, shows: shows);
}

/// Whether this app can show the game [room] plays ([shows]: see
/// [gamePickable]): if not, it says "Update the app to watch", and Join
/// game and the empty seats are greyed out (members, chat and the invite
/// still work).
bool showsRoomGame(RoomState room, {Map<String, int>? shows}) {
  final game = room.game;
  if (game == null) return true;
  return (shows ?? appOnlineGames)[game.key] == (game.gv ?? (game.key == holdemKey ? holdemGv : null));
}

/// Whether Join game can take a seat in [room] for a member without one:
/// this app shows the game, and some seat is empty or a bot's (a bot gives
/// its seat to a person) with nobody else waiting for it.
bool canJoinGame(RoomState room, {Map<String, int>? shows}) =>
    showsRoomGame(room, shows: shows) && room.seats.any((seat) => seat.kind != SeatKind.human && seat.joining == null);

/// How many seats [room]'s game needs taken for the host's Start (and for
/// each round): Hold'em [minPlayers]; another game every seat, or its
/// least for one dealt to the seats taken (its SeatRange, from [uis]).
/// Null with no game, or one this app can't show.
int? seatsNeeded(RoomState room, Map<String, OnlineGameUi> uis) {
  final game = room.game;
  if (game == null) return null;
  if (game.key == holdemKey) return minPlayers;
  final online = uis[game.key]?.online, rules = game.setup?['rules'];
  if (online == null) return null;
  try {
    final range = online.seatsFor(online.readRules(rules));
    final needed = range.needed(room.seats.length);
    return needed > range.min ? needed : range.min;
  } on FormatException {
    return null;
  }
}

/// The bot styles (Hold'em) or levels (the other games) the host can pick
/// in [room]'s game.
List<String> botChoicesFor(RoomState room) =>
    room.game == null || room.game!.key == holdemKey ? pickableBotStyles : botLevelNames;

/// Asks the host whether to remove [name] (who is [going] already: greyed
/// out), then whether they are sure; [remove] does it. From the docked
/// room, both open over the screen beside it (see roomDialogContext).
Future<void> askToRemove(
  BuildContext context, {
  required String name,
  required bool going,
  required VoidCallback remove,
}) async {
  final s = S.of(context);
  final target = roomDialogContext(context);
  final picked = await showModalBottomSheet<bool>(
    context: target,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: Text(name, style: Theme.of(context).textTheme.titleMedium)),
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
  if (picked != true || !target.mounted) return;
  final sure = await showDialog<bool>(
    context: target,
    builder: (context) => AlertDialog(
      title: Text(s.removePlayerQuestion(name)),
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

/// One room seat: who has it (or that it is empty) and what is coming at
/// the next hand; for a bot, its style. A tap on an empty seat takes it
/// ([onTake]: greyed out when this member can't sit). The host picks a
/// bot's style ([onStyle]) and takes it away ([onRemove]); a tap on
/// another person's seat offers to remove them ([onRemovePlayer], asked
/// first).
class SeatRow extends StatelessWidget {
  const SeatRow({
    super.key,
    required this.seat,
    required this.room,
    this.onTake,
    this.onStyle,
    this.onRemove,
    this.onRemovePlayer,
  });

  final SeatInfo seat;
  final RoomState room;
  final VoidCallback? onTake;
  final ValueChanged<String>? onStyle;
  final VoidCallback? onRemove;
  final VoidCallback? onRemovePlayer;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final k = KitStrings.of(context);
    final theme = Theme.of(context);
    // The member's own seat, or the one they wait for.
    final mine = seat.member != null && seat.member == room.you;
    final bot = seat.kind == SeatKind.bot;
    final empty = seat.isEmpty;
    final choices = botChoicesFor(room);
    final details = [
      if (seat.member != null && seat.member == room.host) s.host,
      if (bot) s.botBadge,
      if (bot && seat.style != null && onStyle == null) botStyleName(s, seat.style!, kit: k),
      if (seat.score case final score?) '${k.term(KitTerm.score)}: ${_score(score)}',
      if (seat.status == SeatStatus.away) s.awayBadge,
      if (seat.status == SeatStatus.left) s.leftBadge,
      if (seat.out) s.outBadge,
      if (seat.sittingOut) s.sittingOutBadge,
      if (seat.leaving) s.leavingBadge,
      if (seat.joining != null) '${room.game?.key == holdemKey ? s.nextHandBadge : s.nextGameBadge}: ${seat.joining}',
    ];
    // Or the seat the member waits for (theirs from the next hand).
    final me = room.me;
    final queued = me != null && me.waiting && me.seat == seat.seat;
    final highlight = mine || queued ? const Color(0xFFFFE082) : null;
    // Another person, for the host: a tap offers to remove them.
    final onRemovePlayer = this.onRemovePlayer;
    final person = seat.kind == SeatKind.human && !mine && seat.member != room.host && onRemovePlayer != null;
    final take = empty ? onTake : null;
    return ListTile(
      key: ValueKey('seat ${seat.seat}'),
      dense: true,
      mouseCursor: WidgetStateMouseCursor.clickable,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      hoverColor: theme.colorScheme.primary.withValues(alpha: 0.12),
      onTap: take ?? (person ? () => _remove(context) : null),
      leading: Icon(
        empty ? Icons.event_seat_outlined : (bot ? Icons.smart_toy_outlined : Icons.person),
        color: highlight ?? (take != null ? theme.colorScheme.primary : (bot || empty ? Colors.white38 : null)),
      ),
      title: Text(
        empty ? s.emptySeat : seat.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: mine ? FontWeight.w700 : null,
          color: highlight ?? (empty ? (take != null ? Colors.white70 : Colors.white38) : null),
        ),
      ),
      subtitle: details.isEmpty ? null : Text(details.join(' · ')),
      trailing: bot && (onStyle != null || onRemove != null)
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<String>(
                  value: choices.contains(seat.style) ? seat.style : choices.first,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final style in choices)
                      DropdownMenuItem(
                        value: style,
                        child: Text(botStyleName(s, style, kit: k)),
                      ),
                  ],
                  onChanged: onStyle == null
                      ? null
                      : (style) {
                          if (style != null) onStyle!(style);
                        },
                ),
                IconButton(
                  key: ValueKey('remove bot ${seat.seat}'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close),
                  onPressed: seat.leaving ? null : onRemove,
                ),
              ],
            )
          : (person
                ? const Icon(Icons.more_vert, color: Colors.white38)
                : (take != null ? Icon(Icons.login, size: 18, color: theme.colorScheme.primary) : null)),
    );
  }

  /// A score as shown: whole numbers without decimals.
  static String _score(num score) => score == score.roundToDouble() ? '${score.round()}' : score.toStringAsFixed(1);

  /// The host's choice for this person: Remove (greyed out once they left,
  /// or go when the hand ends), asked first.
  Future<void> _remove(BuildContext context) => askToRemove(
    context,
    name: seat.name,
    going: seat.status == SeatStatus.left || seat.leaving,
    remove: onRemovePlayer!,
  );
}

/// The host's Add Bot, with the new bot's style. Greyed out ([onAdd] null)
/// when every seat is taken, and for everyone else.
class AddBotRow extends StatefulWidget {
  const AddBotRow({super.key, required this.onAdd, this.choices = pickableBotStyles});

  final ValueChanged<String>? onAdd;

  /// The styles (Hold'em) or levels (the other games) to pick from, the
  /// first picked at first.
  final List<String> choices;

  @override
  State<AddBotRow> createState() => _AddBotRowState();
}

class _AddBotRowState extends State<AddBotRow> {
  String? _picked;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final k = KitStrings.of(context);
    final onAdd = widget.onAdd;
    final choices = widget.choices;
    final style = choices.contains(_picked)
        ? _picked!
        : (choices.contains(defaultBotStyle) ? defaultBotStyle : choices.first);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('add bot'),
            onPressed: onAdd == null ? null : () => onAdd(style),
            icon: const Icon(Icons.smart_toy_outlined, size: 18),
            label: Text(s.addBot),
          ),
          DropdownButton<String>(
            value: style,
            underline: const SizedBox.shrink(),
            items: [
              for (final choice in choices)
                DropdownMenuItem(
                  value: choice,
                  child: Text(botStyleName(s, choice, kit: k)),
                ),
            ],
            onChanged: onAdd == null
                ? null
                : (choice) {
                    if (choice != null) setState(() => _picked = choice);
                  },
          ),
          const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.onlineBots]),
        ],
      ),
    );
  }
}

/// Every seat of the room, and the host's Add Bot. A tap on an empty seat
/// takes it ([onTake]: null when this member can't sit there now).
class RoomSeats extends StatelessWidget {
  const RoomSeats({
    super.key,
    required this.room,
    required this.host,
    required this.onAdd,
    required this.onStyle,
    required this.onRemove,
    required this.onRemoveMember,
    this.onTake,
  });

  final RoomState room;

  /// The host, still in the room: seats, bots and players can change.
  final bool host;
  final ValueChanged<String> onAdd;
  final void Function(int seat, String style) onStyle;
  final ValueChanged<int> onRemove;

  /// The host removes a member (by id, and name: see RemoveMember).
  final void Function(int id, String name) onRemoveMember;
  final ValueChanged<int>? onTake;

  @override
  Widget build(BuildContext context) {
    final free = room.seats.any((seat) => seat.isEmpty && seat.joining == null);
    final onTake = this.onTake;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final seat in room.seats)
          SeatRow(
            seat: seat,
            room: room,
            onTake: onTake != null && seat.joining == null ? () => onTake(seat.seat) : null,
            onStyle: host ? (style) => onStyle(seat.seat, style) : null,
            onRemove: host ? () => onRemove(seat.seat) : null,
            onRemovePlayer: host && seat.member != null ? () => onRemoveMember(seat.member!, seat.name) : null,
          ),
        AddBotRow(onAdd: host && free ? onAdd : null, choices: botChoicesFor(room)),
      ],
    );
  }
}

/// Join game (the first free seat, else a bot's), or Leave seat for a
/// member who has one or waits for one: never greyed out (during a hand
/// it counts from the next). Join game is greyed out when this app can't
/// show the game, or every seat is a person's ([canJoinGame]).
class SeatActions extends StatelessWidget {
  const SeatActions({super.key, required this.room, required this.onJoin, required this.onLeave, this.shows});

  final RoomState room;
  final VoidCallback onJoin;
  final VoidCallback onLeave;

  /// The games this app shows online (see [canJoinGame]); null: the
  /// context's ([shownGamesOf]).
  final Map<String, int>? shows;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final seated = room.me?.seat != null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          if (seated)
            OutlinedButton.icon(
              key: const ValueKey('leave seat'),
              onPressed: onLeave,
              icon: const Icon(Icons.event_seat_outlined, size: 18),
              label: Text(s.leaveSeat),
            )
          else
            FilledButton.icon(
              key: const ValueKey('join game'),
              onPressed: canJoinGame(room, shows: shows ?? shownGamesOf(context)) ? onJoin : null,
              icon: const Icon(Icons.login, size: 18),
              label: Text(s.joinGame),
            ),
          const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.spectators]),
        ],
      ),
    );
  }
}

/// Everyone in the room, as its lobby shows them: under Playing, the seats
/// taken in the room's game, in seat order (people, and bots marked with
/// their icon and "Bot"); under Spectators, the members watching (or
/// waiting for a seat). The host has its badge wherever it is. The host
/// taps another person to remove them ([onRemove], asked first).
class PeopleList extends StatelessWidget {
  const PeopleList({super.key, required this.room, this.onRemove});

  final RoomState room;
  final void Function(int id, String name)? onRemove;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final onRemove = this.onRemove;
    final playing = [
      for (final seat in room.seats)
        if (!seat.isEmpty) seat,
    ];
    final watching = [
      for (final m in room.members)
        if (m.spectator) m,
    ];
    Widget heading(String text, String key) => Padding(
      key: ValueKey(key),
      padding: const EdgeInsets.only(top: 6, bottom: 2, left: 4),
      child: Text(text, style: theme.textTheme.labelMedium?.copyWith(color: Colors.white60)),
    );
    Widget row({
      required Key key,
      required IconData icon,
      required String name,
      required List<String> details,
      required bool mine,
      bool dim = false,
      VoidCallback? onTap,
    }) => ListTile(
      key: key,
      dense: true,
      visualDensity: VisualDensity.compact,
      mouseCursor: WidgetStateMouseCursor.clickable,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      hoverColor: theme.colorScheme.primary.withValues(alpha: 0.12),
      onTap: onTap,
      leading: Icon(icon, color: mine ? const Color(0xFFFFE082) : (dim ? Colors.white38 : Colors.white60)),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: mine ? FontWeight.w700 : null, color: mine ? const Color(0xFFFFE082) : null),
      ),
      subtitle: details.isEmpty ? null : Text(details.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: onTap != null ? const Icon(Icons.more_vert, color: Colors.white38) : null,
    );
    VoidCallback? removing(int id, String name, {bool going = false}) {
      if (onRemove == null || id == room.you || id == room.host) return null;
      return () => askToRemove(context, name: name, going: going, remove: () => onRemove(id, name));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (playing.isNotEmpty) heading(s.playingNow, 'people playing'),
        for (final seat in playing)
          if (seat.kind == SeatKind.bot)
            row(
              key: ValueKey('person bot ${seat.seat}'),
              icon: Icons.smart_toy_outlined,
              name: seat.name,
              details: [s.botBadge, if (seat.leaving) s.leavingBadge],
              mine: false,
              dim: true,
            )
          else
            row(
              key: ValueKey('member ${seat.member}'),
              icon: Icons.person,
              name: seat.name,
              details: [
                if (seat.member == room.host) s.host,
                if (seat.status == SeatStatus.away) s.awayBadge,
                if (seat.status == SeatStatus.left) s.leftBadge,
                if (seat.out) s.outBadge,
                if (seat.sittingOut) s.sittingOutBadge,
                if (seat.leaving) s.leavingBadge,
              ],
              mine: seat.member != null && seat.member == room.you,
              onTap: seat.member == null
                  ? null
                  : removing(seat.member!, seat.name, going: seat.status == SeatStatus.left || seat.leaving),
            ),
        if (watching.isNotEmpty) heading(s.spectators, 'people watching'),
        for (final m in watching)
          row(
            key: ValueKey('member ${m.id}'),
            icon: Icons.visibility_outlined,
            name: m.name,
            details: [
              if (m.id == room.host) s.host,
              if (m.status == SeatStatus.away) s.awayBadge,
              if (m.waiting) s.nextHandBadge,
            ],
            mine: m.id == room.you,
            onTap: removing(m.id, m.name),
          ),
      ],
    );
  }
}

/// How many members the room has, of the most it takes (bots don't count).
class HeadCount extends StatelessWidget {
  const HeadCount({super.key, required this.room});

  final RoomState room;

  @override
  Widget build(BuildContext context) {
    final full = room.members.length >= room.cap;
    final color = full ? const Color(0xFFFFCC80) : Colors.white60;
    return Row(
      key: const ValueKey('head count'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.groups_outlined, size: 18, color: color),
        const SizedBox(width: 4),
        Text('${room.members.length}/${room.cap}', style: TextStyle(color: color)),
      ],
    );
  }
}

/// The host's switch: spectators see the bots' cards too (from the next
/// round). The host changes it at any time ([onChange]); greyed out for
/// everyone else.
class HostSwitches extends StatelessWidget {
  const HostSwitches({super.key, required this.room, this.onChange});

  final RoomState room;
  final ValueChanged<bool>? onChange;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return SwitchListTile(
      key: const ValueKey('see bots'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Row(
        children: [
          Flexible(child: Text(s.spectatorsSeeBots, style: Theme.of(context).textTheme.titleMedium)),
          const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.seeBots]),
        ],
      ),
      value: room.seeBots,
      onChanged: onChange,
    );
  }
}

/// The room's Hold'em rules: seats, stacks, ante, min-raise, help, time,
/// rebuys, reset stacks and showing the bots' styles. The host changes the
/// table itself (rebuys too) only in the lobby, the rest at any time
/// (during the game, from the next hand).
class RoomRules extends StatelessWidget {
  const RoomRules({super.key, required this.room, required this.host, required this.onChange});

  final RoomState room;

  /// The host, still in the room: the rules can change.
  final bool host;
  final ValueChanged<RoomSettings> onChange;

  static const _stackChoices = [10, 20, 40, 60, 100, 150, 200];
  static const _anteChoices = [0, 10, 25];

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    // Shown only while the room plays Hold'em, which has them.
    final settings = room.settings!;
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
      ],
    );
  }
}

/// The rules of a game other than Hold'em: its number of seats (when the
/// host picks it), the time per move and the game's own rules (its
/// OnlineGameUi.rulesForm). The host changes them in the lobby only
/// ([onChange] with the new setup, sent as ChooseGame); greyed out for
/// everyone else.
class RunnerRules extends StatelessWidget {
  const RunnerRules({super.key, required this.room, required this.ui, required this.host, required this.onChange});

  final RoomState room;
  final OnlineGameUi ui;
  final bool host;
  final ValueChanged<Map<String, Object?>> onChange;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final online = ui.online;
    final setup = room.game?.setup ?? const <String, Object?>{};
    final Map<String, Object?> rules;
    try {
      rules = online.readRules(setup['rules'] ?? online.defaultRules);
    } on FormatException {
      return const SizedBox.shrink();
    }
    final range = online.seatsFor(rules);
    final seats = setup['seats'] is int ? setup['seats']! as int : range.first;
    final turnLimit = setup['turnLimit'] is int ? setup['turnLimit']! as int : 0;
    final enabled = host && room.phase == RoomPhase.lobby;
    void change({Map<String, Object?>? newRules, int? newSeats, int? newTurnLimit}) {
      final r = newRules ?? rules;
      final n = newSeats ?? seats;
      final allowed = online.seatsFor(r);
      onChange({'seats': allowed.allows(n) ? n : allowed.first, 'turnLimit': newTurnLimit ?? turnLimit, 'rules': r});
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (range.hostPicks)
          RoomSection(
            title: s.seats,
            child: choiceChips<int>(
              values: [for (var n = range.min; n <= range.max; n++) n],
              selected: seats,
              label: (n) => '$n',
              // Never fewer than are taken.
              enabled: (n) => enabled && n >= room.taken,
              onSelected: (n) => change(newSeats: n),
            ),
          ),
        RoomSection(
          title: s.timeLimit,
          help: const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.timeLimit]),
          child: choiceChips<int>(
            values: OnlineTiming.turnLimits,
            selected: turnLimit,
            label: s.turnLimit,
            enabled: (_) => enabled,
            onSelected: (seconds) => change(newTurnLimit: seconds),
          ),
        ),
        const SizedBox(height: 8),
        ui.rulesForm(
          context,
          rules,
          enabled: enabled,
          onChange: (r) => change(newRules: r),
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
        mouseCursor: WidgetStateMouseCursor.clickable,
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
  const RoomSection({super.key, required this.title, this.help, this.trailing, required this.child});

  final String title;

  /// A "?" button right after the title.
  final Widget? help;

  /// At the end of the title's line (a head count, say).
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
            ?help,
            if (trailing case final trailing?) ...[const Spacer(), trailing],
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );
}
