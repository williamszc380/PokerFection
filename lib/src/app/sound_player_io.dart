import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

/// Plays short WAV files: through Windows' own PlaySound on Windows, and
/// through the host app on phones (see MainActivity / AppDelegate).
/// Silent elsewhere, and in tests.
class SoundPlayer {
  SoundPlayer() : _windows = !_inTests && Platform.isWindows ? _WindowsSound.open() : null;

  static final _inTests = Platform.environment.containsKey('FLUTTER_TEST');
  static const _channel = MethodChannel('pokerfection/sound');

  final _WindowsSound? _windows;

  bool get available => !_inTests && (_windows != null || Platform.isAndroid || Platform.isIOS);

  void play(Uint8List wav) {
    if (!available) return;
    final windows = _windows;
    if (windows != null) {
      windows.play(wav);
    } else {
      _channel.invokeMethod<void>('play', wav).catchError((_) {});
    }
  }

  /// Forgets prepared sounds (they are made again at the new volume).
  void clear() => _windows?.clear();
}

/// winmm's PlaySound, playing from memory without waiting. The memory must
/// stay valid while a sound plays, so each sound is copied once and kept.
class _WindowsSound {
  _WindowsSound._(this._playSound);

  static _WindowsSound? open() {
    try {
      final winmm = DynamicLibrary.open('winmm.dll');
      return _WindowsSound._(winmm.lookupFunction<Int32 Function(Pointer<Uint8>, IntPtr, Uint32),
          int Function(Pointer<Uint8>, int, int)>('PlaySoundW'));
    } on Object {
      return null;
    }
  }

  static const _async = 0x0001, _noDefault = 0x0002, _memory = 0x0004;

  final int Function(Pointer<Uint8> sound, int module, int flags) _playSound;
  final Map<Uint8List, Pointer<Uint8>> _copies = Map.identity();

  void play(Uint8List wav) {
    final copy = _copies.putIfAbsent(wav, () {
      final memory = calloc<Uint8>(wav.length);
      memory.asTypedList(wav.length).setAll(0, wav);
      return memory;
    });
    _playSound(copy, 0, _async | _memory | _noDefault);
  }

  void clear() {
    // Stop whatever plays before its memory goes.
    _playSound(nullptr, 0, 0);
    for (final memory in _copies.values) {
      calloc.free(memory);
    }
    _copies.clear();
  }
}
