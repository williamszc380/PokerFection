import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'src/app/app_settings.dart';
import 'src/app/last_games.dart';
import 'src/app/settings_store.dart';
import 'src/kit/jobs/backend.dart';
import 'src/kit/jobs/jobs.dart';
import 'src/online/invite.dart';
import 'src/ui/home_screen.dart';
import 'src/ui/kit/kit_scope.dart';
import 'src/ui/online/online_screen.dart';
import 'src/ui/online/room_scope.dart';
import 'src/ui/online/room_shell.dart';

// Drills are off for now: uncomment to bring them back.
// import 'src/app/drills.dart';

/// `--profile=N` keeps a separate set of settings (another name online), to
/// play several copies of the app against each other on one computer. An
/// invite link (pokerfection://join?code=...) opens Play Online with it; so
/// does the web version opened at a room: the website from an invite's join
/// page (`?code=K7M2Q&server=peer:K7M2Q`, the room through the meeting
/// service), or a host's app serving it at `http://<host>:<port>/?code=...`.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Phones and tablets are played sideways: the table on the left, the
  // decisions on the right.
  if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  }
  final profile = [for (final a in args) ?RegExp(r'^--profile=(\d+)$').firstMatch(a)?.group(1)].firstOrNull;
  final profileNumber = profile == null ? null : int.parse(profile);
  SettingsStore open(String name) => SettingsStore(profile: profileNumber, name: name);
  final settings = await loadSaved(open);
  // Drills are off for now: uncomment to bring them back (and the runApp line below).
  // final drills = Drills(store: open('drills'));
  // await drills.load();
  if (!kIsWeb) unawaited(registerInviteLinks());
  // On Windows a clicked invite link arrives as an argument; in a browser,
  // the room is in the page's address.
  final invite = kIsWeb
      ? inviteFromPage(Uri.base)
      : [for (final a in args) if (a.startsWith('$inviteScheme:')) ?parseInvite(a)].firstOrNull;
  runApp(PokerFectionApp(settings: settings, invite: invite, lastGames: LastGames(open: open)));
  // Drills are off for now: uncomment to bring them back (in place of the line above).
  // runApp(PokerFectionApp(settings: settings, drills: drills, invite: invite));
}

/// Reads what the app keeps between runs, from the stores [open] gives by
/// name (on disk: `settings.json`, see SettingsStore): the settings. Each
/// new game's most recent game (`last_<key>.json`, see LastGames) is read
/// when its menu or setup opens. The drills (`drills.json`, loaded in main)
/// are neither read nor written while they are off.
Future<AppSettings> loadSaved(SettingsStore Function(String name) open) async {
  final settings = AppSettings(store: open('settings'));
  await settings.load();
  return settings;
}

class PokerFectionApp extends StatelessWidget {
  PokerFectionApp({
    super.key,
    required this.settings,
    this.invite,
    LastGames? lastGames,
    this.newJobs = platformJobs,
    RoomService? rooms,
  })  : lastGames = lastGames ?? LastGames(),
        rooms = rooms ?? RoomService(settings: settings);
  // Drills are off for now: uncomment to bring them back (in place of the constructor above).
  // /// Without [drills], mistakes are kept only while the app runs.
  // PokerFectionApp({super.key, required this.settings, Drills? drills, this.invite}) : drills = drills ?? Drills();

  final AppSettings settings;

  // Drills are off for now: uncomment to bring them back.
  // /// The mistake drills, saved in training (see Drills).
  // final Drills drills;

  /// The invite link the app was opened with, if any.
  final Invite? invite;

  /// Each new game's most recent game; without one given, kept only while
  /// the app runs (tests).
  final LastGames lastGames;

  /// Makes the background jobs of one game screen: isolates in the apps,
  /// Web Workers in a browser. Tests that open a game pass
  /// `() => Jobs.inline()`, so they never start a thread.
  final Jobs Function() newJobs;

  /// The online room the app is in, for every screen (none at first): it
  /// stays beside them until it is left (see RoomService, RoomShell).
  final RoomService rooms;

  static final theme = _theme();

  /// Dark green theme. Everything clickable lights up clearly under the
  /// mouse (the stock highlight is hard to see on the dark background) and
  /// shows the hand: Flutter's own default is the hand in a browser only,
  /// the plain arrow on Windows (WidgetStateMouseCursor.adaptiveClickable).
  /// Disabled controls keep the arrow. Chips and InkWells have no theme for
  /// it: they set `mouseCursor: WidgetStateMouseCursor.clickable` themselves.
  static ThemeData _theme() {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF2E8B57), brightness: Brightness.dark);
    WidgetStateProperty<Color?> highlight(Color color) => WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) return color.withValues(alpha: 0.26);
          if (states.contains(WidgetState.hovered)) return color.withValues(alpha: 0.18);
          if (states.contains(WidgetState.focused)) return color.withValues(alpha: 0.12);
          return null;
        });
    const hand = WidgetStateMouseCursor.clickable;
    ButtonStyle button(Color overlay) => ButtonStyle(overlayColor: highlight(overlay), mouseCursor: hand);
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF0B0F12),
      hoverColor: Colors.white.withValues(alpha: 0.12),
      filledButtonTheme: FilledButtonThemeData(style: button(scheme.onPrimary)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: button(scheme.primary)),
      textButtonTheme: TextButtonThemeData(style: button(scheme.primary)),
      elevatedButtonTheme: ElevatedButtonThemeData(style: button(scheme.primary)),
      iconButtonTheme: IconButtonThemeData(style: button(scheme.onSurface)),
      segmentedButtonTheme: SegmentedButtonThemeData(style: button(scheme.onSurface)),
      menuButtonTheme: const MenuButtonThemeData(style: ButtonStyle(mouseCursor: hand)),
      popupMenuTheme: const PopupMenuThemeData(mouseCursor: hand),
      switchTheme: const SwitchThemeData(mouseCursor: hand),
      checkboxTheme: const CheckboxThemeData(mouseCursor: hand),
      radioTheme: const RadioThemeData(mouseCursor: hand),
      sliderTheme: const SliderThemeData(mouseCursor: hand),
      tabBarTheme: const TabBarThemeData(mouseCursor: hand),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(mouseCursor: hand),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppSettingsScope(
      settings: settings,
      // Drills are off for now: uncomment to bring them back.
      // child: DrillsScope(
      //   drills: drills,
      // The new games' jobs and saved games, for every screen (see KitScope).
      child: KitScope(
        newJobs: newJobs,
        lastGames: lastGames,
        child: RoomScope(
          notifier: rooms,
          child: ListenableBuilder(
          listenable: settings,
          builder: (context, _) => MaterialApp(
            title: 'PokerFection',
            debugShowCheckedModeBanner: false,
            theme: theme,
            navigatorKey: rooms.navigatorKey,
            scaffoldMessengerKey: rooms.messengerKey,
            navigatorObservers: [rooms.observer],
            locale: settings.language.locale,
            supportedLocales: [for (final language in AppLanguage.values) language.locale],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            // No hover texts anywhere (also none of Flutter's own, like "Back"). The room the
            // user is in stays beside every screen.
            builder: (context, child) => TooltipVisibility(visible: false, child: RoomShell(app: child!)),
            // Home; opened with an invite link, Play Online with its code on
            // top (on Android and iOS the link arrives as the first route,
            // "/?code=...").
            onGenerateInitialRoutes: (route) => [
              MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
              if (invite ?? inviteFromUri(Uri.tryParse(route)) case final found?)
                MaterialPageRoute<void>(
                  settings: const RouteSettings(arguments: RoomRoute.online),
                  builder: (_) => OnlineScreen(invite: found),
                ),
            ],
            // ... or a link opened while the app runs.
            onGenerateRoute: (route) => switch (inviteFromUri(Uri.tryParse(route.name ?? ''))) {
              final found? => MaterialPageRoute<void>(
                  settings: const RouteSettings(arguments: RoomRoute.online),
                  builder: (_) => OnlineScreen(invite: found),
                ),
              null => route.name == '/' ? MaterialPageRoute<void>(builder: (_) => const HomeScreen()) : null,
            },
          ),
        ),
        ),
      ),
      // Drills are off for now: uncomment to bring them back (DrillsScope's end).
      // ),
    );
  }
}
