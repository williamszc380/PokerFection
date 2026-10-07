import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'src/app/app_settings.dart';
import 'src/app/drills.dart';
import 'src/app/settings_store.dart';
import 'src/online/invite.dart';
import 'src/ui/main_menu.dart';
import 'src/ui/online/online_screen.dart';

/// `--profile=N` keeps a separate set of settings (another name online), to
/// play several copies of the app against each other on one computer. An
/// invite link (pokerfection://join?code=...) opens Play Online with it; so
/// does the web version opened at a room (a host's app serves it at
/// `http://<host>:<port>/?code=...`).
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Phones and tablets are played sideways: the table on the left, the
  // decisions on the right.
  if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  }
  final profile = [for (final a in args) ?RegExp(r'^--profile=(\d+)$').firstMatch(a)?.group(1)].firstOrNull;
  final profileNumber = profile == null ? null : int.parse(profile);
  final settings = AppSettings(store: SettingsStore(profile: profileNumber));
  final drills = Drills(store: SettingsStore(profile: profileNumber, name: 'drills'));
  await (settings.load(), drills.load()).wait;
  if (!kIsWeb) unawaited(registerInviteLinks());
  // On Windows a clicked invite link arrives as an argument; in a browser,
  // the room is in the page's address.
  final invite = kIsWeb
      ? inviteFromPage(Uri.base)
      : [for (final a in args) if (a.startsWith('$inviteScheme:')) ?parseInvite(a)].firstOrNull;
  runApp(PokerFectionApp(settings: settings, drills: drills, invite: invite));
}

class PokerFectionApp extends StatelessWidget {
  /// Without [drills], mistakes are kept only while the app runs.
  PokerFectionApp({super.key, required this.settings, Drills? drills, this.invite}) : drills = drills ?? Drills();

  final AppSettings settings;

  /// The mistake drills, saved in training (see Drills).
  final Drills drills;

  /// The invite link the app was opened with, if any.
  final Invite? invite;

  static final theme = _theme();

  /// Dark green theme. Everything clickable lights up clearly under the
  /// mouse (the stock highlight is hard to see on the dark background).
  static ThemeData _theme() {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF2E8B57), brightness: Brightness.dark);
    WidgetStateProperty<Color?> highlight(Color color) => WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) return color.withValues(alpha: 0.26);
          if (states.contains(WidgetState.hovered)) return color.withValues(alpha: 0.18);
          if (states.contains(WidgetState.focused)) return color.withValues(alpha: 0.12);
          return null;
        });
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF0B0F12),
      hoverColor: Colors.white.withValues(alpha: 0.12),
      filledButtonTheme: FilledButtonThemeData(style: ButtonStyle(overlayColor: highlight(scheme.onPrimary))),
      outlinedButtonTheme: OutlinedButtonThemeData(style: ButtonStyle(overlayColor: highlight(scheme.primary))),
      textButtonTheme: TextButtonThemeData(style: ButtonStyle(overlayColor: highlight(scheme.primary))),
      iconButtonTheme: IconButtonThemeData(style: ButtonStyle(overlayColor: highlight(scheme.onSurface))),
      segmentedButtonTheme: SegmentedButtonThemeData(style: ButtonStyle(overlayColor: highlight(scheme.onSurface))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppSettingsScope(
      settings: settings,
      child: DrillsScope(
        drills: drills,
        child: ListenableBuilder(
          listenable: settings,
          builder: (context, _) => MaterialApp(
            title: 'PokerFection',
            debugShowCheckedModeBanner: false,
            theme: theme,
            locale: settings.language.locale,
            supportedLocales: [for (final language in AppLanguage.values) language.locale],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            // No hover texts anywhere (also none of Flutter's own, like "Back").
            builder: (context, child) => TooltipVisibility(visible: false, child: child!),
            // The main menu; opened with an invite link, Play Online with its code
            // on top (on Android and iOS the link arrives as the first route,
            // "/?code=...").
            onGenerateInitialRoutes: (route) => [
              MaterialPageRoute<void>(builder: (_) => const MainMenu()),
              if (invite ?? inviteFromUri(Uri.tryParse(route)) case final found?)
                MaterialPageRoute<void>(builder: (_) => OnlineScreen(invite: found)),
            ],
            // ... or a link opened while the app runs.
            onGenerateRoute: (route) => switch (inviteFromUri(Uri.tryParse(route.name ?? ''))) {
              final found? => MaterialPageRoute<void>(builder: (_) => OnlineScreen(invite: found)),
              null => route.name == '/' ? MaterialPageRoute<void>(builder: (_) => const MainMenu()) : null,
            },
          ),
        ),
      ),
    );
  }
}
