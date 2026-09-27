import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Reads and writes the settings file, `settings.json` in the app's own
/// folder: %APPDATA%\PokerFection on Windows, the app's private files on
/// phones (asked from the host app, see MainActivity / AppDelegate).
class SettingsStore {
  static const _channel = MethodChannel('pokerfection/platform');

  Future<File?> _file() async {
    String? folder;
    final env = Platform.environment;
    if (Platform.isWindows) {
      final appData = env['APPDATA'];
      if (appData != null) folder = '$appData\\PokerFection';
    } else if (Platform.isMacOS) {
      final home = env['HOME'];
      if (home != null) folder = '$home/Library/Application Support/PokerFection';
    } else if (Platform.isLinux) {
      final home = env['HOME'];
      if (home != null) folder = '${env['XDG_CONFIG_HOME'] ?? '$home/.config'}/pokerfection';
    } else {
      try {
        folder = await _channel.invokeMethod<String>('dataFolder');
      } on Exception {
        folder = null;
      }
    }
    return folder == null ? null : File('$folder${Platform.pathSeparator}settings.json');
  }

  /// The saved settings, or an empty map if there are none (or they can't be read).
  Future<Map<String, Object?>> read() async {
    try {
      final file = await _file();
      if (file == null || !file.existsSync()) return {};
      final data = jsonDecode(await file.readAsString());
      return data is Map<String, Object?> ? data : {};
    } on Exception {
      return {};
    }
  }

  Future<void> write(Map<String, Object?> settings) async {
    try {
      final file = await _file();
      if (file == null) return;
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(settings));
    } on Exception {
      // Settings just won't be remembered.
    }
  }
}
