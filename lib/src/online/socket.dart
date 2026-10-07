/// Connecting to the game server with a WebSocket, without plugins:
/// dart:io's on Windows, Android and iOS, the browser's on the web.
library;

export 'socket_io.dart' if (dart.library.js_interop) 'socket_web.dart';
