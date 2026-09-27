/// Plays WAV bytes on each platform (see the io and web versions).
library;

export 'sound_player_io.dart' if (dart.library.js_interop) 'sound_player_web.dart';
