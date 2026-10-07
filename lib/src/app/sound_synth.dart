import 'dart:math';
import 'dart:typed_data';

/// The table's sound effects.
enum SoundEffect { deal, chips, fold, check, yourTurn, win }

/// Samples per second of every sound.
const soundSampleRate = 22050;

/// The samples of [effect] at full volume (-1 to 1), mono at [soundSampleRate].
///
/// Every sound is made of soft tones (no noise, which sounds like static):
/// each note starts gently, slides a little in pitch and fades out, and the
/// whole sound is smoothed and fades to silence at its ends, so nothing
/// clicks.
Float64List synthesize(SoundEffect effect) {
  const rate = soundSampleRate;
  Float64List buffer(double seconds) => Float64List((seconds * rate).round());

  /// Adds a note sliding from [hz] to [toHz] (a sine with a touch of its
  /// octave), rising over [attack] seconds and fading out over [length].
  void note(Float64List out, double start, double hz, double length, double level,
      {double? toHz, double attack = 0.004, double octave = 0.15}) {
    final from = (start * rate).round();
    final end = toHz ?? hz;
    var phase = 0.0;
    for (var i = 0; i < length * rate && from + i < out.length; i++) {
      final t = i / rate;
      phase += 2 * pi * hz * pow(end / hz, t / length) / rate;
      final fade = exp(-t / (length / 4)) * min(1.0, t / attack);
      out[from + i] += level * fade * (sin(phase) + octave * sin(2 * phase));
    }
  }

  final samples = switch (effect) {
    // A card sliding onto the felt: a quick, low flick.
    SoundEffect.deal => buffer(0.08)..apply((b) => note(b, 0, 520, 0.06, 0.22, toHz: 340, octave: 0)),
    // Chips set down: three soft clay tocks.
    SoundEffect.chips => buffer(0.18)
      ..apply((b) {
        note(b, 0, 1150, 0.035, 0.2, toHz: 950);
        note(b, 0.045, 1000, 0.035, 0.15, toHz: 840);
        note(b, 0.09, 1250, 0.035, 0.11, toHz: 1020);
      }),
    // Cards tossed away: a gentle falling tone.
    SoundEffect.fold => buffer(0.18)..apply((b) => note(b, 0, 420, 0.16, 0.16, toHz: 260, attack: 0.015, octave: 0)),
    // Two knocks on the table.
    SoundEffect.check => buffer(0.22)
      ..apply((b) {
        note(b, 0, 230, 0.07, 0.4, toHz: 180);
        note(b, 0.1, 230, 0.07, 0.4, toHz: 180);
      }),
    // A soft two-note chime.
    SoundEffect.yourTurn => buffer(0.55)
      ..apply((b) {
        note(b, 0, 784, 0.4, 0.2, attack: 0.008, octave: 0.05);
        note(b, 0.14, 1047, 0.4, 0.2, attack: 0.008, octave: 0.05);
      }),
    // A rising major chord, one note after another.
    SoundEffect.win => buffer(0.75)
      ..apply((b) {
        note(b, 0, 523, 0.45, 0.18, attack: 0.008, octave: 0.1);
        note(b, 0.1, 659, 0.45, 0.18, attack: 0.008, octave: 0.1);
        note(b, 0.2, 784, 0.5, 0.18, attack: 0.008, octave: 0.1);
      }),
  };
  return _smooth(samples);
}

/// Takes the edge off [samples]: a gentle low-pass (nothing harsh above
/// about 5 kHz) and a few milliseconds of fade at both ends.
Float64List _smooth(Float64List samples) {
  const fade = soundSampleRate * 0.004;
  final keep = exp(-2 * pi * 5000 / soundSampleRate);
  var last = 0.0;
  for (var i = 0; i < samples.length; i++) {
    last = (1 - keep) * samples[i] + keep * last;
    final edge = min(1.0, min(i, samples.length - 1 - i) / fade);
    samples[i] = last * edge;
  }
  return samples;
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
