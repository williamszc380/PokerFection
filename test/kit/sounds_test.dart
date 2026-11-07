import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/sound_synth.dart';
import 'package:pokerfection/src/ui/kit/game_sounds.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

void main() {
  test('every sound effect is audible and under a second long, the new games\' included', () {
    expect(
      SoundEffect.values.map((e) => e.name),
      containsAll(['stone', 'cardsDown', 'pass', 'bomb', 'lose']),
    );
    for (final effect in SoundEffect.values) {
      final samples = synthesize(effect);
      expect(samples.length / soundSampleRate, lessThan(1.0), reason: effect.name);
      expect(samples.map((s) => s.abs()).reduce(max), greaterThan(0.05), reason: '${effect.name} is not silent');
      expect(samples.every((s) => s.abs() <= 1), isTrue, reason: '${effect.name} does not clip');
    }
  });

  test('game sounds are silent at Instant speed', () {
    final played = <SoundEffect>[];
    final before = GameSounds.output;
    GameSounds.output = played.add;
    addTearDown(() => GameSounds.output = before);
    GameSounds.play(SoundEffect.stone, speed: PlaybackSpeed.normal);
    GameSounds.play(SoundEffect.bomb, speed: PlaybackSpeed.instant);
    GameSounds.play(SoundEffect.lose, speed: PlaybackSpeed.fast);
    expect(played, [SoundEffect.stone, SoundEffect.lose]);
  });
}
