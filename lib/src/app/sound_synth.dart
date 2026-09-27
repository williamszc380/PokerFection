import 'dart:math';
import 'dart:typed_data';

/// The table's sound effects.
enum SoundEffect { deal, chips, fold, check, yourTurn, win }

/// Samples per second of every sound.
const soundSampleRate = 22050;

/// The samples of [effect] at full volume (-1 to 1), mono at [soundSampleRate].
Float64List synthesize(SoundEffect effect) {
  const rate = soundSampleRate;
  final random = Random(effect.index + 1);
  Float64List buffer(double seconds) => Float64List((seconds * rate).round());

  /// Adds a note: a sine (with a touch of its octave) that fades out.
  void tone(Float64List out, double start, double hz, double length, double level) {
    final from = (start * rate).round();
    for (var i = 0; i < length * rate && from + i < out.length; i++) {
      final t = i / rate;
      final fade = exp(-t / (length / 4)) * min(1.0, t / 0.003);
      out[from + i] += level * fade * (sin(2 * pi * hz * t) + 0.25 * sin(4 * pi * hz * t));
    }
  }

  /// Adds a burst of noise, smoothed (lower [bright] is duller) and faded.
  void noise(Float64List out, double start, double length, double level, double bright) {
    final from = (start * rate).round();
    var smooth = 0.0;
    for (var i = 0; i < length * rate && from + i < out.length; i++) {
      final t = i / rate;
      smooth += bright * (random.nextDouble() * 2 - 1 - smooth);
      out[from + i] += level * smooth * sin(pi * t / length);
    }
  }

  /// Adds a clack: a very short, bright ring (chips hitting chips).
  void click(Float64List out, double start, double hz, double level) {
    final from = (start * rate).round();
    for (var i = 0; i < 0.03 * rate && from + i < out.length; i++) {
      final t = i / rate;
      out[from + i] += level * exp(-t / 0.004) * (sin(2 * pi * hz * t) + 0.6 * (random.nextDouble() * 2 - 1));
    }
  }

  switch (effect) {
    case SoundEffect.deal:
      return buffer(0.07)..apply((b) => noise(b, 0, 0.06, 0.5, 0.6));
    case SoundEffect.chips:
      return buffer(0.12)
        ..apply((b) {
          click(b, 0, 3400, 0.45);
          click(b, 0.035, 2900, 0.35);
          click(b, 0.07, 3700, 0.25);
        });
    case SoundEffect.fold:
      return buffer(0.14)..apply((b) => noise(b, 0, 0.13, 0.35, 0.2));
    case SoundEffect.check:
      return buffer(0.2)
        ..apply((b) {
          tone(b, 0, 170, 0.06, 0.6);
          tone(b, 0.1, 170, 0.06, 0.6);
        });
    case SoundEffect.yourTurn:
      return buffer(0.45)
        ..apply((b) {
          tone(b, 0, 988, 0.3, 0.3);
          tone(b, 0.13, 1319, 0.3, 0.3);
        });
    case SoundEffect.win:
      return buffer(0.6)
        ..apply((b) {
          tone(b, 0, 1047, 0.3, 0.25);
          tone(b, 0.09, 1319, 0.3, 0.25);
          tone(b, 0.18, 1568, 0.4, 0.25);
        });
  }
}

extension on Float64List {
  void apply(void Function(Float64List samples) fill) => fill(this);
}

/// A WAV file of [samples] (-1 to 1, clipped) at [volume].
Uint8List wav(Float64List samples, {double volume = 1, int sampleRate = soundSampleRate}) {
  final bytes = ByteData(44 + samples.length * 2);
  void text(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  bytes.setUint32(4, 36 + samples.length * 2, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  bytes
    ..setUint32(16, 16, Endian.little) // format chunk size
    ..setUint16(20, 1, Endian.little) // PCM
    ..setUint16(22, 1, Endian.little) // mono
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * 2, Endian.little) // bytes per second
    ..setUint16(32, 2, Endian.little) // bytes per sample
    ..setUint16(34, 16, Endian.little); // bits per sample
  text(36, 'data');
  bytes.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    bytes.setInt16(44 + i * 2, (samples[i] * volume).clamp(-1.0, 1.0) * 32767 ~/ 1, Endian.little);
  }
  return bytes.buffer.asUint8List();
}
