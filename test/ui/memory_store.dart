import 'package:pokerfection/src/app/settings_store.dart';

/// A settings store that keeps what it is given in memory, to see what the
/// app saves (and to hand it saved settings) without touching the disk.
class MemoryStore implements SettingsStore {
  MemoryStore([Map<String, Object?>? saved, this.name = 'settings']) : saved = saved ?? {};

  /// What was saved last.
  Map<String, Object?> saved;

  /// How many times it was written.
  int writes = 0;

  @override
  final String name;

  @override
  int? get profile => null;

  @override
  Future<Map<String, Object?>> read() async => Map.of(saved);

  @override
  Future<void> write(Map<String, Object?> settings) async {
    writes++;
    saved = Map.of(settings);
  }
}
