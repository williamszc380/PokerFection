import 'dart:convert';

import 'package:web/web.dart' as web;

/// Reads and writes the settings in the browser's local storage.
class SettingsStore {
  static const _key = 'pokerfection.settings';

  Future<Map<String, Object?>> read() async {
    try {
      final text = web.window.localStorage.getItem(_key);
      if (text == null) return {};
      final data = jsonDecode(text);
      return data is Map<String, Object?> ? data : {};
    } on Object {
      return {};
    }
  }

  Future<void> write(Map<String, Object?> settings) async {
    try {
      web.window.localStorage.setItem(_key, jsonEncode(settings));
    } on Object {
      // Settings just won't be remembered.
    }
  }
}
