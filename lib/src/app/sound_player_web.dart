import 'dart:convert';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Plays short WAV files in the browser.
class SoundPlayer {
  final Map<Uint8List, String> _urls = Map.identity();

  bool get available => true;

  void play(Uint8List wav) {
    final url = _urls.putIfAbsent(wav, () => 'data:audio/wav;base64,${base64Encode(wav)}');
    try {
      final audio = web.HTMLAudioElement()..src = url;
      audio.play();
    } on Object {
      // Browsers may refuse sound before the first tap: nothing to do.
    }
  }

  void clear() => _urls.clear();
}
