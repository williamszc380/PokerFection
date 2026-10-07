import 'dart:async';
import 'dart:io';

import '../online/protocol.dart';
import '../online/timing.dart';
import 'room_registry.dart';
import 'web_files.dart';
import 'websocket_link.dart';

/// The game server: plain HTTP with two addresses, and the web version.
/// - `/health`: answers 200, with the protocol version.
/// - `/ws`: a WebSocket to play (see protocol.dart).
/// - anything else: the web version of the app, when there is one ([web]),
///   so friends can play in a browser.
///
/// It runs inside the app of whoever creates a room (see host_here_io.dart),
/// or on its own (bin/server.dart). Rooms live in memory.
class PokerServer {
  PokerServer({RoomRegistry? registry, this.web, void Function(String message)? log})
    : _log = log ?? ((_) {}),
      registry = registry ?? RoomRegistry(log: log);

  /// The port a server listens on unless told otherwise (or, when it is
  /// taken, one of the next few).
  static const defaultPort = gamePort;

  final RoomRegistry registry;
  final WebFiles? web;
  final void Function(String message) _log;
  HttpServer? _http;

  /// Starts listening on [port] (0: any free port), on every network of
  /// this device unless [address] says otherwise; if [port] is taken, on
  /// one of the next [tries] - 1. Returns the port.
  Future<int> start({int port = defaultPort, Object? address, int tries = 1}) async {
    for (var i = 0; ; i++) {
      try {
        final http = _http = await HttpServer.bind(address ?? InternetAddress.anyIPv4, port == 0 ? 0 : port + i);
        http.listen((request) => unawaited(_handle(request)));
        return http.port;
      } on SocketException {
        if (port == 0 || i + 1 >= tries) rethrow;
      }
    }
  }

  /// The port it listens on, once started.
  int? get port => _http?.port;

  Future<void> _handle(HttpRequest request) async {
    try {
      switch (request.uri.path) {
        case '/health':
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.text
            ..write('PokerFection server, protocol $protocolVersion, ${registry.roomCount} rooms');
          await request.response.close();
        case '/ws' when WebSocketTransformer.isUpgradeRequest(request):
          final address = request.connectionInfo?.remoteAddress.address ?? 'unknown';
          final socket = await WebSocketTransformer.upgrade(request);
          // Notices a connection that went away without closing.
          socket.pingInterval = OnlineTiming.ping + const Duration(seconds: 5);
          registry.accept(WebSocketLink(socket, address));
        default:
          if (await web?.serve(request) ?? false) return;
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
      }
    } catch (e) {
      _log('Request failed: $e');
    }
  }

  /// Ends every room (telling the players why: by default, the server
  /// restarts) and stops.
  Future<void> close({CloseReason reason = CloseReason.serverRestart}) async {
    registry.shutdown(reason);
    // A moment for the goodbyes to go out.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _http?.close(force: true);
  }
}
