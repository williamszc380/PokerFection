import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import '../online/online_client.dart' show RejoinRecord;
import '../ui/table_controller.dart' show PlaybackSpeed;
import 'settings_store.dart';
import 'sounds.dart';

enum AppLanguage {
  english('en', 'English'),
  spanish('es', 'Español'),
  chinese('zh', '中文');

  const AppLanguage(this.code, this.label);
  final String code;

  /// The language's own name for itself.
  final String label;

  Locale get locale => Locale(code);
}

/// Card backs, each a two-color gradient.
enum CardBackStyle {
  blue(Color(0xFF1565C0), Color(0xFF0D47A1)),
  red(Color(0xFFC62828), Color(0xFF8E0000)),
  green(Color(0xFF2E7D32), Color(0xFF1B5E20)),
  black(Color(0xFF37474F), Color(0xFF111111));

  const CardBackStyle(this.light, this.dark);
  final Color light;
  final Color dark;
}

/// How card faces show their suit (suits: 0 clubs, 1 diamonds, 2 hearts, 3 spades).
enum CardFaceStyle {
  /// White cards; hearts and diamonds red, spades and clubs black.
  twoColors,

  /// White cards; clubs green, diamonds blue, hearts red, spades black.
  fourColors,

  /// Each card filled with its suit's color, with white marks (spades purple).
  colored;

  static const _red = Color(0xFFD32F2F), _black = Color(0xFF1A1A1A);
  static const _green = Color(0xFF2E7D32), _blue = Color(0xFF1565C0), _purple = Color(0xFF7B1FA2);

  /// The card's color.
  Color face(int suit) => this == colored ? const [_green, _blue, _red, _purple][suit] : Colors.white;

  /// The color of the rank and suit marks.
  Color ink(int suit) => switch (this) {
        twoColors => suit == 1 || suit == 2 ? _red : _black,
        fourColors => const [_green, _blue, _red, _black][suit],
        colored => Colors.white,
      };
}

/// Table felt colors: center, middle and edge of the gradient.
enum FeltStyle {
  green(Color(0xFF2E8B57), Color(0xFF1E6B42), Color(0xFF12452B)),
  blue(Color(0xFF2F6FA8), Color(0xFF1F5282), Color(0xFF123456)),
  red(Color(0xFFA33B3B), Color(0xFF7E2828), Color(0xFF4F1616)),
  purple(Color(0xFF6A4A9C), Color(0xFF4F3578), Color(0xFF2E1E4A)),
  gray(Color(0xFF5B6770), Color(0xFF434D55), Color(0xFF262D33));

  const FeltStyle(this.center, this.middle, this.edge);
  final Color center;
  final Color middle;
  final Color edge;
}

/// The app's preferences (language, animations, sound, looks), kept
/// between runs. Widgets read them with [AppSettings.of], which rebuilds
/// them when a setting changes.
class AppSettings extends ChangeNotifier {
  AppSettings({this._store});

  final SettingsStore? _store;

  AppLanguage language = AppLanguage.english;
  PlaybackSpeed speed = PlaybackSpeed.normal;

  /// Sound effects volume, 0 (off) to 1.
  double volume = 0.7;
  CardBackStyle cardBack = CardBackStyle.blue;

  CardFaceStyle cardFaces = CardFaceStyle.twoColors;
  FeltStyle felt = FeltStyle.green;

  /// The name shown to the other players online.
  String nickname = '';

  /// The game server to play online on; empty for the app's own.
  String serverUrl = '';

  /// Hosting a room here: the router's public address, typed by hand (its
  /// port forwarded by hand) when it can't be opened automatically; empty
  /// if none. "203.0.113.7", or with the port outside: "203.0.113.7:47500".
  String publicAddress = '';

  /// The online room this player is in, to come back to it if the app
  /// closes (or the page reloads) during the game. Changing it (see
  /// [remember]) only tells those who listen to it.
  final ValueNotifier<RejoinRecord?> rejoin = ValueNotifier(null);

  /// A random key this app sends when it joins an online room (it says
  /// nothing else about the device), made and saved the first time: a room
  /// the host removed this player from won't let them in again.
  String get device {
    if (_device.isEmpty) {
      final random = Random.secure();
      _device = base64Url.encode([for (var i = 0; i < 16; i++) random.nextInt(256)]).replaceAll('=', '');
      _save();
    }
    return _device;
  }

  String _device = '';

  static AppSettings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppSettingsScope>()?.notifier ?? _fallback;

  /// For widgets used outside the app (tests): the defaults.
  static final _fallback = AppSettings();

  /// Reads the saved settings (the defaults stay for anything missing).
  Future<void> load() async {
    final saved = await _store?.read() ?? const {};
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.firstWhere((v) => v.name == name, orElse: () => fallback);
    language = pick(AppLanguage.values, saved['language'], language);
    speed = pick(PlaybackSpeed.values, saved['speed'], speed);
    cardBack = pick(CardBackStyle.values, saved['cardBack'], cardBack);
    felt = pick(FeltStyle.values, saved['felt'], felt);
    final savedVolume = saved['volume'];
    if (savedVolume is num) volume = savedVolume.toDouble().clamp(0, 1);
    cardFaces = pick(CardFaceStyle.values, saved['cardFaces'], cardFaces);
    if (saved['nickname'] case final String name) nickname = name;
    if (saved['serverUrl'] case final String url) serverUrl = url;
    if (saved['publicAddress'] case final String address) publicAddress = address;
    if (saved['device'] case final String key) _device = key;
    rejoin.value = RejoinRecord.fromJson(saved['rejoin']);
    // Settings saved before there were three styles.
    if (saved['fourColorDeck'] == true && saved['cardFaces'] == null) cardFaces = CardFaceStyle.fourColors;
    Sounds.instance.volume = volume;
    notifyListeners();
  }

  /// Changes settings, then tells everyone and saves them.
  void update(void Function(AppSettings settings) change) {
    change(this);
    Sounds.instance.volume = volume;
    notifyListeners();
    _save();
  }

  /// Keeps [record] (null: forgets it) to come back to an online room,
  /// and saves it.
  void remember(RejoinRecord? record) {
    // Not while screens are built or taken down (a table that closes forgets its room).
    scheduleMicrotask(() {
      if (record == null && rejoin.value == null) return;
      rejoin.value = record;
      _save();
    });
  }

  void _save() {
    _store?.write({
      'language': language.name,
      'speed': speed.name,
      'volume': volume,
      'cardBack': cardBack.name,
      'cardFaces': cardFaces.name,
      'felt': felt.name,
      'nickname': nickname,
      'serverUrl': serverUrl,
      'publicAddress': publicAddress,
      if (_device.isNotEmpty) 'device': _device,
      'rejoin': ?rejoin.value?.toJson(),
    });
  }
}

/// Makes the app's [AppSettings] available below it.
class AppSettingsScope extends InheritedNotifier<AppSettings> {
  const AppSettingsScope({super.key, required AppSettings settings, required super.child})
      : super(notifier: settings);
}
