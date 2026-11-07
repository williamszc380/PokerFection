import 'dart:async';
import 'dart:convert';

import '../kit/game_record.dart';
import 'settings_store.dart';

/// Each game's most recent game, one record per game: `last_<key>.json`
/// next to the settings (`last_<key>-N.json` with --profile=N), or the
/// `pokerfection.last_<key>` key in a browser's local storage. Nothing else
/// about past games is kept.
///
/// Saving is cheap to call after every move: writes wait up to 300 ms and
/// then save only the newest record of each game, in order.
class LastGames {
  /// Without [open], records stay in memory (tests, and screens pumped
  /// outside the app).
  LastGames({this._open});

  final SettingsStore Function(String name)? _open;
  final _stores = <String, SettingsStore>{};
  final _memory = <String, Object?>{};
  final _pending = <String, GameRecord>{};

  /// Records handed to their store and not yet written: a load meanwhile
  /// (the game menu, right after the game's screen closed) sees them.
  final _inFlight = <String, GameRecord>{};
  Timer? _timer;
  Future<void> _writing = Future.value();

  /// [game]'s most recent record, or null if there is none, it is broken,
  /// of another [version], or [validate] (which may replay its moves) says
  /// no or throws. A record that fails is left as it is until the next
  /// save: it is never deleted.
  Future<GameRecord?> load(String game, {required int version, bool Function(GameRecord record)? validate}) async {
    try {
      final Object? json = switch (_pending[game] ?? _inFlight[game]) {
        final waiting? => _roundTrip(waiting),
        null when _open == null => _memory[game],
        null => await _store(game).read(),
      };
      final record = GameRecord.fromJson(json, game: game, version: version);
      if (record == null || (validate != null && !validate(record))) return null;
      return record;
    } on Object {
      return null;
    }
  }

  /// Keeps [record] as its game's most recent one (written within 300 ms).
  /// Every value in it must be plain JSON (checked in debug builds, where
  /// the save is made, rather than lost later on the way to disk).
  void save(GameRecord record) {
    assert(() {
      jsonEncode(record.toJson());
      return true;
    }());
    _pending[record.game] = record;
    _timer ??= Timer(const Duration(milliseconds: 300), _write);
  }

  /// Writes what is waiting now, and completes when every write is done.
  /// It never fails: a write that fails loses only that record.
  Future<void> flush() {
    _write();
    return _writing;
  }

  void _write() {
    _timer?.cancel();
    _timer = null;
    final waiting = Map.of(_pending);
    _pending.clear();
    for (final MapEntry(key: game, value: record) in waiting.entries) {
      if (_open == null) {
        try {
          _memory[game] = _roundTrip(record);
        } on Object {
          // Not JSON: like a failed write, only this record is lost.
        }
      } else {
        final store = _store(game);
        _inFlight[game] = record;
        // Each write on its own: one that fails (a full disk, a value that
        // isn't JSON) must not stop the writes after it, for any game.
        _writing = _writing
            .then((_) => store.write(record.toJson()))
            .catchError((Object _) {})
            .whenComplete(() {
              if (identical(_inFlight[game], record)) _inFlight.remove(game);
            });
      }
    }
  }

  SettingsStore _store(String game) => _stores[game] ??= _open!('last_$game');

  /// The record as it comes back from disk (so memory behaves the same).
  static Object? _roundTrip(GameRecord record) => jsonDecode(jsonEncode(record.toJson()));
}
