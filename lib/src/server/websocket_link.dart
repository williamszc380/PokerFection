import 'dart:async';
import 'dart:io';

import 'client_link.dart';

/// A player's WebSocket, as the server sees it. Only text messages count,
/// up to [maxMessage] characters; a longer one ends the connection.
class WebSocketLink implements ClientLink {
  WebSocketLink(this._socket, this.address) {
    _socket.listen(
      (data) {
        if (data is! String || _incoming.isClosed) return;
        if (data.length > maxMessage) {
          unawaited(close());
          return;
        }
        _incoming.add(data);
      },
      onDone: () => unawaited(_incoming.close()),
      onError: (Object _) => unawaited(close()),
      cancelOnError: true,
    );
  }

  static const maxMessage = 16 * 1024;

  final WebSocket _socket;
  final StreamController<String> _incoming = StreamController();
  bool _closed = false;

  @override
  final String address;

  @override
  Stream<String> get messages => _incoming.stream;

  @override
  void send(String message) {
    if (_closed || _socket.readyState != WebSocket.open) return;
    _socket.add(message);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    unawaited(_incoming.close());
    await _socket.close(WebSocketStatus.normalClosure);
  }
}
