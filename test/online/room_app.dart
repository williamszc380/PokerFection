/// The app around a screen, with the app's room (RoomService) and its shell,
/// as PokerFectionApp builds them: for widget tests of screens that open,
/// show or leave a room.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pokerfection/main.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/ui/online/room_scope.dart';
import 'package:pokerfection/src/ui/online/room_shell.dart';

/// [home] as the app's first screen, with [rooms] (its settings are the
/// app's) and the room's shell beside the screens. [theme]: the app's by
/// default.
Widget roomApp(Widget home, {required RoomService rooms, ThemeData? theme}) => AppSettingsScope(
  settings: rooms.settings,
  child: RoomScope(
    notifier: rooms,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme ?? PokerFectionApp.theme,
      locale: rooms.settings.language.locale,
      supportedLocales: [for (final language in AppLanguage.values) language.locale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      navigatorKey: rooms.navigatorKey,
      scaffoldMessengerKey: rooms.messengerKey,
      navigatorObservers: [rooms.observer],
      builder: (context, child) => TooltipVisibility(visible: false, child: RoomShell(app: child!)),
      home: home,
    ),
  ),
);
