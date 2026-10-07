import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Reads and writes the settings file, `settings.json` in the app's own
/// folder: %APPDATA%\PokerFection on Windows, the app's private files on
/// phones (asked from the host app, see MainActivity / AppDelegate). Another
/// [name] keeps something else there the same way (the drills: `drills.json`).
///
/// With a [profile] (the app started with --profile=N): `settings-N.json`
/// instead, so several copies of the app on one computer can play online
/// as different players.
class SettingsStore {
  SettingsStore({this.profile, this.name = 'settings'});

  final int? profile;
  final String name;

  static const _channel = MethodChannel('pokerfection/platform');

  /// The last write: the next one waits for it, so they land in order.
  Future<void> _writing = Future.value();

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
    final file = profile == null ? '$name.json' : '$name-$profile.json';
    return folder == null ? null : File('$folder${Platform.pathSeparator}$file');
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

  Future<void> write(Map<String, Object?> settings) => _writing = _writing.then((_) => _write(jsonEncode(settings)));

  /// Writes a copy first, then puts it in place: a write cut short leaves
  /// the last one whole.
  Future<void> _write(String text) async {
    try {
      final file = await _file();
      if (file == null) return;
      await file.parent.create(recursive: true);
      final copy = File('${file.path}.tmp');
      await copy.writeAsString(text, flush: true);
      await copy.rename(file.path);
    } on Exception {
      // Settings just won't be remembered.
    }
  }
}
