import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/app/settings_store.dart';
import 'package:pokerfection/src/kit/game_record.dart';

/// Keeps what is written, in memory, and counts the writes.
class _Store implements SettingsStore {
  _Store(this.name);

  @override
  final String name;

  @override
  int? get profile => null;

  Map<String, Object?> saved = {};
  int writes = 0;

  @override
  Future<Map<String, Object?>> read() async => saved;

  @override
  Future<void> write(Map<String, Object?> settings) async {
    writes++;
    saved = settings;
  }
}

/// A store whose writes the test finishes by hand, and which can fail one.
class _SlowStore implements SettingsStore {
  _SlowStore(this.name);

  @override
  final String name;

  @override
  int? get profile => null;

  Map<String, Object?> saved = {};
  final pending = <Completer<void>>[];
  var failNext = false;

  @override
  Future<Map<String, Object?>> read() async => saved;

  @override
  Future<void> write(Map<String, Object?> settings) {
    if (failNext) {
      failNext = false;
      // What SettingsStore (io) lets escape: its catch takes Exceptions only.
      return Future.error(JsonUnsupportedObjectError(Object()));
    }
    final done = Completer<void>();
    pending.add(done);
    return done.future.then((_) => saved = settings);
  }

  void finishAll() {
    for (final c in pending) {
      if (!c.isCompleted) c.complete();
    }
  }
}

GameRecord _game(String game, List<String> moves) =>
    GameRecord(game: game, version: 1, seed: 5, rules: const {'size': 15}, moves: moves);

void main() {
  final stores = <String, _Store>{};
  late LastGames lastGames;

  setUp(() {
    stores.clear();
    lastGames = LastGames(open: (name) => stores.putIfAbsent(name, () => _Store(name)));
  });

  test("each game's most recent record goes to its own store, last_<key>", () async {
    lastGames.save(_game('gomoku', ['h8']));
    lastGames.save(_game('blackjack', ['d']));
    await lastGames.flush();
    expect(stores.keys, unorderedEquals(['last_gomoku', 'last_blackjack']));
    expect((await lastGames.load('gomoku', version: 1))?.moves, ['h8']);
    expect((await lastGames.load('blackjack', version: 1))?.moves, ['d']);
    expect(await lastGames.load('big_two', version: 1), isNull, reason: 'none yet');
  });

  test('saves within 300 ms are written once, the newest; a load in between sees the newest', () async {
    lastGames.save(_game('gomoku', ['h8']));
    lastGames.save(_game('gomoku', ['h8', 'h9']));
    expect((await lastGames.load('gomoku', version: 1))?.moves, ['h8', 'h9']);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(stores['last_gomoku']!.writes, 1);
    expect(stores['last_gomoku']!.saved['moves'], ['h8', 'h9']);
  });

  test('a broken record, one of another version, or one its game rejects is ignored and left in place', () async {
    stores['last_gomoku'] = _Store('last_gomoku')..saved = {'game': 'gomoku', 'version': 1, 'moves': 7};
    expect(await lastGames.load('gomoku', version: 1), isNull);
    expect(stores['last_gomoku']!.saved['moves'], 7, reason: 'never deleted');

    lastGames.save(_game('gomoku', ['h8']));
    await lastGames.flush();
    expect(await lastGames.load('gomoku', version: 2), isNull);
    expect(await lastGames.load('gomoku', version: 1, validate: (r) => r.moves.length > 1), isNull);
    expect(await lastGames.load('gomoku', version: 1, validate: (r) => throw StateError('replay failed')), isNull);
    expect(await lastGames.load('gomoku', version: 1, validate: (r) => true), isNotNull);
  });

  test('without stores, records stay in memory the same way', () async {
    final memory = LastGames();
    memory.save(_game('doudizhu', ['0:bid3']));
    await memory.flush();
    expect((await memory.load('doudizhu', version: 1))?.moves, ['0:bid3']);
  });

  test('a write that fails loses only that record: later saves are still written, and flush never fails', () async {
    final store = _SlowStore('last_gomoku');
    final slow = LastGames(open: (_) => store);
    store.failNext = true;
    slow.save(_game('gomoku', ['h8']));
    await slow.flush();
    slow.save(_game('gomoku', ['h8', 'h9']));
    final flushed = slow.flush();
    await Future<void>.delayed(Duration.zero);
    store.finishAll();
    await flushed;
    expect(store.saved['moves'], ['h8', 'h9']);
  });

  test('a load while the last write is still on its way sees that record, not the one before', () async {
    final store = _SlowStore('last_gomoku');
    final slow = LastGames(open: (_) => store);
    slow.save(_game('gomoku', ['h8']));
    final flushed = slow.flush(); // The screen closed: its record is on its way to disk.
    // The game menu checks "Last game" as soon as the game's route returns.
    expect((await slow.load('gomoku', version: 1))?.moves, ['h8']);
    await Future<void>.delayed(Duration.zero);
    store.finishAll();
    await flushed;
    expect((await slow.load('gomoku', version: 1))?.moves, ['h8'], reason: 'and from the store once written');
  });

  test('a record holding a value that is not JSON is caught where it is saved (debug builds)', () {
    final bad = _game('gomoku', ['h8']).withExtra('sort', DateTime(2026));
    expect(() => lastGames.save(bad), throwsA(isA<JsonUnsupportedObjectError>()));
  });
}
