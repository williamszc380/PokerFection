import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/app_settings.dart';
import '../app/build_info.dart';
import '../l10n/strings.dart';
import '../online/protocol.dart' show protocolVersion;
import 'game_menu.dart';
import 'games.dart';
import 'online/online_screen.dart';
import 'online/room_scope.dart';
import 'online/room_widgets.dart' show playableInRoom;
import 'settings_screen.dart';
import 'widgets/logo.dart';

/// The first screen: the logo, the games (see [games]; one not built yet
/// is greyed out and marked "Soon"), then Multiplayer and Settings, which
/// every game shares. The language is in the top corner, the version in
/// the bottom-right one (build_info.dart).
///
/// The five games sit in one row when there is room (a PC), three above
/// two otherwise: in a browser on a phone held upright, and on a phone
/// held sideways, which puts the logo and the two buttons beside the
/// games, as there isn't the height for them above and below.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  /// The gap between the tiles, and between the tiles and the buttons.
  static const _gap = 12.0;

  /// The room on each side of a game's name in its tile.
  static const tilePadding = 8.0;

  /// The style of the games' names (the word-fit test measures with it).
  static TextStyle? nameStyle(ThemeData theme) =>
      theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.2);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, actions: const [LanguageButton(), SizedBox(width: 8)]),
      extendBodyBehindAppBar: true,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: LayoutBuilder(builder: _layout)),
            // Which version this is, to compare copies of the game (the app
            // and the website, say): see build_info.dart.
            // Tapped: About (the version, who made the app).
            Positioned(
              right: 4,
              bottom: 2,
              child: Semantics(
                button: true,
                label: S.of(context).about,
                child: InkWell(
                  key: const ValueKey('about'),
                  onTap: () => showAbout(context),
                  mouseCursor: SystemMouseCursors.click,
                  borderRadius: BorderRadius.circular(6),
                  hoverColor: theme.colorScheme.primary.withValues(alpha: 0.16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Text(
                      buildLabel,
                      key: const ValueKey('version'),
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.white38),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _layout(BuildContext context, BoxConstraints constraints) {
    final width = constraints.maxWidth, height = constraints.maxHeight;
    // Phones held sideways: the logo, with Multiplayer and Settings under
    // it, beside the games. There isn't the height for two rows of games
    // and the buttons below them.
    if (width > height && height < 520) {
      const padding = 12.0, buttons = 2 * 44 + 8 + 12;
      // Narrower than the smallest phone (the room's rail beside Home on one): tighter, so every word of
      // every name still fits its tile.
      final tight = width < 560;
      final logo = min((height * 0.46).clamp(100.0, tight ? 120.0 : 190.0), height - 2 * padding - buttons);
      final side = max(logo, tight ? 120.0 : 150.0);
      final gap = tight ? 16.0 : 32.0, edge = tight ? 12.0 : 24.0;
      final rest = min(width - side - gap - 2 * edge, 600.0);
      return Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: edge, vertical: padding),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: side,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: LogoMark(size: logo, name: true)),
                    const SizedBox(height: 12),
                    for (final (i, button) in _buttons(context, small: true).indexed) ...[
                      if (i > 0) const SizedBox(height: 8),
                      button,
                    ],
                  ],
                ),
              ),
              SizedBox(width: gap),
              SizedBox(width: rest, child: _games(context, oneRow: false, small: true)),
            ],
          ),
        ),
      );
    }
    final oneRow = width >= 600;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: oneRow ? 660 : 400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: LogoMark(size: height < 720 ? 170 : 210, name: true)),
              const SizedBox(height: 28),
              _games(context, oneRow: oneRow, small: false),
              const SizedBox(height: 20),
              Row(
                children: [
                  for (final (i, button) in _buttons(context, small: false).indexed) ...[
                    if (i > 0) const SizedBox(width: _gap),
                    Expanded(child: button),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Multiplayer and Settings, which every game shares. [small]: stacked
  /// under the logo on a phone held sideways. In a room, Multiplayer is
  /// the room's button: it shows the room (see RoomService.openPanel).
  List<Widget> _buttons(BuildContext context, {required bool small}) {
    final s = S.of(context);
    final rooms = RoomScope.maybeOf(context);
    final code = rooms != null && rooms.inRoom ? (rooms.room?.code ?? rooms.client?.welcome?.code ?? '') : null;
    void open(Widget screen, {RoomRoute? tag}) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: RouteSettings(arguments: tag),
        builder: (_) => screen,
      ),
    );
    Widget button(String key, IconData icon, String label, Widget screen, {VoidCallback? onPressed}) =>
        OutlinedButton.icon(
          key: ValueKey(key),
          onPressed: onPressed ?? () => open(screen),
          icon: Icon(icon),
          label: Text(label, textAlign: TextAlign.center, maxLines: 1),
          style: OutlinedButton.styleFrom(
            minimumSize: Size.fromHeight(small ? 44 : 48),
            padding: small ? const EdgeInsets.symmetric(horizontal: 12) : null,
            tapTargetSize: small ? MaterialTapTargetSize.shrinkWrap : null,
          ),
        );
    return [
      if (code != null)
        button('multiplayer', Icons.groups, s.room(code), const SizedBox(), onPressed: rooms!.openPanel)
      else
        button(
          'multiplayer',
          Icons.public,
          s.multiplayer,
          const OnlineScreen(),
          onPressed: () => open(const OnlineScreen(), tag: RoomRoute.online),
        ),
      button('settings', Icons.settings, s.settings, const SettingsScreen()),
    ];
  }

  /// The games, in one row ([oneRow]) or three above two, the second row
  /// in the middle. [small]: a phone held sideways, short of height, so
  /// smaller emblems and tighter tiles.
  Widget _games(BuildContext context, {required bool oneRow, required bool small}) {
    final columns = oneRow ? games.length : 3;
    return LayoutBuilder(
      builder: (context, constraints) {
        final tile = (constraints.maxWidth - _gap * (columns - 1)) / columns;
        final emblem = small ? (tile * 0.4).clamp(36.0, 44.0) : (tile * 0.5).clamp(40.0, 88.0);
        return Column(
          children: [
            for (var row = 0; row < games.length; row += columns) ...[
              if (row > 0) SizedBox(height: small ? 8 : _gap),
              // The tiles of a row are as tall as the tallest (a name on
              // two lines).
              IntrinsicHeight(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = row; i < min(row + columns, games.length); i++) ...[
                      if (i > row) const SizedBox(width: _gap),
                      SizedBox(
                        width: tile,
                        child: _GameTile(game: games[i], emblem: emblem, small: small),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// A game on Home: its emblem and name. A game that is ready opens its
/// menu and lights up under the mouse; one that isn't is greyed out, with
/// "Soon" under its name. In a room (host or guest), a game not playable
/// online yet is greyed out too, with "Online soon" (see playableInRoom),
/// until the room ends (then the solo games are back at once).
class _GameTile extends StatefulWidget {
  const _GameTile({required this.game, required this.emblem, required this.small});

  final GameInfo game;

  /// The emblem's size.
  final double emblem;

  /// Tighter, for a phone held sideways.
  final bool small;

  @override
  State<_GameTile> createState() => _GameTileState();
}

class _GameTileState extends State<_GameTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = S.of(context);
    final game = widget.game;
    final rooms = RoomScope.maybeOf(context);
    // In a room: only the games that can be played online.
    final offline = game.ready && rooms != null && rooms.stage == RoomStage.open && !playableInRoom(game, rooms);
    final ready = game.ready && !offline;
    final accent = theme.colorScheme.primary;
    final border = ready && _hovered ? accent : (ready ? Colors.white24 : Colors.white10);
    return Material(
      key: ValueKey('game ${game.id.name}'),
      color: ready ? const Color(0xFF151D22) : const Color(0xFF10161A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: border, width: ready && _hovered ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: ready
            ? () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GameMenu(game: game)))
            : null,
        onHover: (hovered) => setState(() => _hovered = hovered),
        // The hand on a game that opens; the arrow on one that is greyed out.
        mouseCursor: WidgetStateMouseCursor.clickable,
        hoverColor: accent.withValues(alpha: 0.12),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: HomeScreen.tilePadding, vertical: widget.small ? 6 : 12),
          child: Column(
            // The emblems and names in line across a row.
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              // Greyed out: a game that isn't built yet.
              Opacity(
                opacity: ready ? 1 : 0.35,
                child: Column(
                  children: [
                    SizedBox.square(
                      key: ValueKey('emblem ${game.id.name}'),
                      dimension: widget.emblem,
                      child: game.emblem(widget.emblem),
                    ),
                    SizedBox(height: widget.small ? 4 : 8),
                    // At most two lines, broken between words (every word
                    // fits a tile: see home_test.dart).
                    Text(game.name(s), textAlign: TextAlign.center, maxLines: 2, style: HomeScreen.nameStyle(theme)),
                  ],
                ),
              ),
              if (!ready) ...[
                SizedBox(height: widget.small ? 3 : 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    offline ? s.onlineSoon : s.soon,
                    key: ValueKey(offline ? 'online soon ${game.id.name}' : 'soon ${game.id.name}'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(color: Colors.white60),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Picks the app's language (Home's top corner).
class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.of(context);
    return PopupMenuButton<AppLanguage>(
      initialValue: settings.language,
      onSelected: (language) => settings.update((s) => s.language = language),
      itemBuilder: (context) => [
        for (final language in AppLanguage.values)
          PopupMenuItem(value: language, mouseCursor: WidgetStateMouseCursor.clickable, child: Text(language.label)),
      ],
      // The menu's own InkWell has no cursor setting: the hand comes from here.
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [const Icon(Icons.language), const SizedBox(width: 6), Text(settings.language.label)],
          ),
        ),
      ),
    );
  }
}

/// The app's author, shown in About (a name: never translated).
const appAuthor = 'Williams Zhang Cen';

/// About (Home's version, tapped): the logo and the app's name, the
/// version ([label], as the corner shows it), the build (how many commits,
/// and whether the code had local changes; see build_info.dart), who made
/// it, the games it teaches, online play and where it runs.
Future<void> showAbout(BuildContext context, {String label = buildLabel}) {
  final s = S.of(context);
  final theme = Theme.of(context);
  final platform = kIsWeb
      ? 'Web'
      : switch (defaultTargetPlatform) {
          TargetPlatform.windows => 'Windows',
          TargetPlatform.android => 'Android',
          TargetPlatform.iOS => 'iOS',
          TargetPlatform.macOS => 'macOS',
          TargetPlatform.linux => 'Linux',
          TargetPlatform.fuchsia => 'Fuchsia',
        };
  final build = parseBuildLabel(label);
  // A phone held sideways: less room around the box and in it, so more
  // of it shows without scrolling.
  final short = MediaQuery.sizeOf(context).height < 420;
  final muted = theme.textTheme.bodyMedium?.copyWith(color: Colors.white70);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey('about dialog'),
      insetPadding: short
          ? const EdgeInsets.symmetric(horizontal: 40, vertical: 12)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      titlePadding: short ? const EdgeInsets.fromLTRB(24, 14, 24, 0) : null,
      contentPadding: short ? const EdgeInsets.fromLTRB(24, 10, 24, 4) : null,
      actionsPadding: short ? const EdgeInsets.fromLTRB(24, 4, 24, 12) : null,
      title: Row(
        children: [
          LogoMark(size: short ? 30 : 40),
          const SizedBox(width: 12),
          Flexible(child: Text('PokerFection', maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.versionNumber(build == null ? '$appMajorVersion' : label),
                key: const ValueKey('about version'),
                style: theme.textTheme.titleMedium,
              ),
              Text(
                build == null ? s.devBuild : s.buildCommits(build.commits, changed: build.changed),
                key: const ValueKey('about build'),
                style: muted,
              ),
              const SizedBox(height: 12),
              Text(s.madeBy(appAuthor), key: const ValueKey('about author'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 12),
              Text(
                s.gamesList([for (final game in games) game.name(s)].join(' · ')),
                key: const ValueKey('about games'),
                style: muted,
              ),
              const SizedBox(height: 6),
              Text(s.onlineRooms(protocolVersion), style: muted),
              const SizedBox(height: 6),
              Text(s.runningOn(platform), style: muted),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          key: const ValueKey('about close'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.close),
        ),
      ],
    ),
  );
}
