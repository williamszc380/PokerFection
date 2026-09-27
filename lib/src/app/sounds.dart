import 'dart:typed_data';

import 'sound_player.dart';
import 'sound_synth.dart';

export 'sound_synth.dart' show SoundEffect;

/// Plays the sound effects at the chosen volume. The sounds are made in
/// code (short synthesized clicks, swishes and chimes), so there are no
/// audio files to ship.
class Sounds {
  Sounds._();

  static final instance = Sounds._();

  final _player = SoundPlayer();
  final Map<SoundEffect, Uint8List> _wavs = {};
  double _volume = 0.7;

  /// 0 (silent) to 1.
  double get volume => _volume;
  set volume(double value) {
    final v = value.clamp(0.0, 1.0);
    if (v == _volume) return;
    _volume = v;
    _wavs.clear();
    _player.clear();
  }

  void play(SoundEffect effect) {
    if (_volume <= 0 || !_player.available) return;
    _player.play(_wavs[effect] ??= wav(synthesize(effect), volume: _volume));
  }
}

