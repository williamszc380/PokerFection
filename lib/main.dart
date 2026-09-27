import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'src/app/app_settings.dart';
import 'src/app/settings_store.dart';
import 'src/ui/main_menu.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Phones and tablets are played sideways: the table on the left, the
  // decisions on the right.
  if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  }
  final settings = AppSettings(store: SettingsStore());
  await settings.load();
  runApp(PokerFectionApp(settings: settings));
}

class PokerFectionApp extends StatelessWidget {
  const PokerFectionApp({super.key, required this.settings});

  final AppSettings settings;

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
          home: const MainMenu(),
        ),
      ),
    );
  }
}
