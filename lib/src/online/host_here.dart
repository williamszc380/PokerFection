/// Hosting a room on this device, and finding one on the local network:
/// dart:io's sockets on Windows, Android and iOS. The web version can't
/// listen for players, nor ask the network around it ([canHostHere] is
/// false there): it only joins.
library;

export 'host_here_io.dart' if (dart.library.js_interop) 'host_here_web.dart';
