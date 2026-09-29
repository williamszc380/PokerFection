import 'package:flutter/material.dart';

import '../app/app_settings.dart';
import '../l10n/strings.dart';
import 'charts_screen.dart';
import 'hand_rankings_screen.dart';
import 'settings_screen.dart';
import 'setup_screen.dart';
import 'widgets/logo.dart';

/// The first screen: the logo, Play, Preflop Charts, Hand Rankings and
/// Settings, with the language in the top corner.
class MainMenu extends StatelessWidget {
  const MainMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = S.of(context);
    void open(Widget screen) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    final buttons = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: () => open(const SetupScreen()),
          icon: const Icon(Icons.play_arrow),
          label: Text(s.play),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            textStyle: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => open(const ChartsScreen()),
          icon: const Icon(Icons.grid_view),
          label: Text(s.preflopCharts),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => open(const HandRankingsScreen()),
          icon: const Icon(Icons.format_list_numbered),
          label: Text(s.handRankings),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => open(const SettingsScreen()),
          icon: const Icon(Icons.settings),
          label: Text(s.settings),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: const [LanguageButton(), SizedBox(width: 8)],
      ),
      extendBodyBehindAppBar: true,
      body: SafeArea(
        child: LayoutBuilder(
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
        ),
      ),
    );
  }
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
