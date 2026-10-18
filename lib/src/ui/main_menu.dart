import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_settings.dart';
import '../app/build_info.dart';
import '../app/drills.dart';
import '../l10n/strings.dart';
import 'charts_screen.dart';
import 'drill_screen.dart';
import 'hand_rankings_screen.dart';
import 'online/online_screen.dart';
import 'settings_screen.dart';
import 'setup_screen.dart';
import 'widgets/logo.dart';

/// The first screen: the logo, then Play (Solo or Multiplayer), Drills (with
/// how many saved spots are due), Guides (Hand Rankings or Preflop Charts)
/// and Settings, with the language in the top corner. Play and Guides open
/// their choices right under them: the menu always keeps room for one row
/// of choices at its bottom, so opening one only slides the buttons below
/// it down, and nothing above moves. The version shows in the bottom-right
/// corner (build_info.dart).
class MainMenu extends StatefulWidget {
  const MainMenu({super.key});

  @override
  State<MainMenu> createState() => _MainMenuState();
}

enum _Group { play, guides }

class _MainMenuState extends State<MainMenu> {
  /// The group whose choices are open, if any.
  _Group? _open;

  /// One row of choices (with the gap above it), and how fast it opens.
  static const _choicesHeight = 52.0;
  static const _slide = Duration(milliseconds: 180);

  /// Shows the menu again when the next saved spot falls due (its count on
  /// Drills goes up), at [_wakeAt]: a day at most later, as browsers can't
  /// wait much longer than 24 days.
  Timer? _wake;
  DateTime? _wakeAt;

  void _wakeWhenDue(DateTime? at) {
    if (at == _wakeAt) return;
    _wake?.cancel();
    _wakeAt = at;
    if (at == null) return;
    final wait = at.difference(DateTime.now()) + const Duration(seconds: 1);
    const longest = Duration(days: 1);
    _wake = Timer(wait.isNegative ? Duration.zero : (wait > longest ? longest : wait), () {
      if (mounted) setState(() => _wakeAt = null);
    });
  }

  @override
  void dispose() {
    _wake?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = S.of(context);
    final drills = Drills.maybeOf(context);
    _wakeWhenDue(drills?.nextDue);
    void open(Widget screen) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    void toggle(_Group group) => setState(() => _open = _open == group ? null : group);

    Widget group(_Group which, IconData icon, String label, List<(IconData, String, Widget)> choices,
            {bool main = false}) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            main
                ? FilledButton.icon(
                    onPressed: () => toggle(which),
                    icon: Icon(icon),
                    label: Text(label),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      textStyle: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  )
                : OutlinedButton.icon(
                    onPressed: () => toggle(which),
                    icon: Icon(icon),
                    label: Text(label),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  ),
            AnimatedContainer(
              duration: _slide,
              curve: Curves.easeOut,
              height: _open == which ? _choicesHeight : 0,
              clipBehavior: Clip.hardEdge,
              decoration: const BoxDecoration(),
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minHeight: _choicesHeight,
                maxHeight: _choicesHeight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      for (final (k, (icon, text, screen)) in choices.indexed) ...[
                        if (k > 0) const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: _open == which ? () => open(screen) : null,
                            icon: Icon(icon, size: 20),
                            label: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(44),
                              maximumSize: const Size.fromHeight(44),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        );

    final buttons = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        group(_Group.play, Icons.play_arrow, s.play, main: true, [
          (Icons.person, s.solo, const SetupScreen()),
          (Icons.public, s.multiplayer, const OnlineScreen()),
        ]),
        const SizedBox(height: 12),
        // Mistakes saved in training, played again when due.
        OutlinedButton.icon(
          key: const ValueKey('drills'),
          onPressed: drills == null ? null : () => open(DrillScreen(drills: drills)),
          icon: const Icon(Icons.event_repeat),
          label: Text(s.drillsDue(drills?.dueCount ?? 0)),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        const SizedBox(height: 12),
        group(_Group.guides, Icons.menu_book_outlined, s.guides, [
          (Icons.format_list_numbered, s.handRankings, const HandRankingsScreen()),
          (Icons.grid_view, s.preflopCharts, const ChartsScreen()),
        ]),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => open(const SettingsScreen()),
          icon: const Icon(Icons.settings),
          label: Text(s.settings),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        // The room a row of choices takes when one is open: the menu keeps
        // the same height, so it doesn't move on screen.
        AnimatedContainer(duration: _slide, curve: Curves.easeOut, height: _open == null ? _choicesHeight : 0),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: const [LanguageButton(), SizedBox(width: 8)],
      ),
      extendBodyBehindAppBar: true,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _menu(buttons)),
            // Which version this is, to compare copies of the game (the app
            // and the website, say): see build_info.dart.
            Positioned(
              right: 12,
              bottom: 8,
              child: Text(
                buildLabel,
                key: const ValueKey('version'),
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white38),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The logo and [buttons], centered.
  Widget _menu(Widget buttons) => LayoutBuilder(
        builder: (context, constraints) {
          // Phones held sideways: the logo beside the buttons.
          if (constraints.maxWidth > constraints.maxHeight && constraints.maxHeight < 520) {
            return Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LogoMark(size: 190, name: true),
                  const SizedBox(width: 48),
                  SizedBox(width: 280, child: buttons),
                ],
              ),
            );
          }
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: LogoMark(size: 220, name: true)),
                    const SizedBox(height: 32),
                    buttons,
                  ],
                ),
              ),
            ),
          );
        },
      );
}

/// Picks the app's language (top corner of the main menu).
class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.of(context);
    return PopupMenuButton<AppLanguage>(
      initialValue: settings.language,
      onSelected: (language) => settings.update((s) => s.language = language),
      itemBuilder: (context) => [
        for (final language in AppLanguage.values) PopupMenuItem(value: language, child: Text(language.label)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [const Icon(Icons.language), const SizedBox(width: 6), Text(settings.language.label)],
        ),
      ),
    );
  }
}
