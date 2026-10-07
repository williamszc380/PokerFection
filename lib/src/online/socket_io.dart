import 'dart:async';
import 'dart:io';

import 'online_socket.dart';

/// Opens a WebSocket to [url] (ws:// or wss://). Throws if the server
/// can't be reached within [timeout]: [ConnectionRefused] when nothing
/// listens there.
Future<OnlineSocket> connectSocket(String url, {Duration timeout = const Duration(seconds: 10)}) async {
  try {
    return _IoSocket(await WebSocket.connect(url).timeout(timeout));
  } on SocketException catch (e) {
    if (_refused.contains(e.osError?.errorCode)) throw const ConnectionRefused();
    rethrow;
  }
}

/// "Connection refused" on Linux and Android, on macOS and iOS, and on
/// Windows (from the socket layer, or as Windows reports it).
const _refused = {111, 61, 10061, 1225};

class _IoSocket implements OnlineSocket {
  _IoSocket(this._socket) {
    _socket.listen(
      (data) {
        if (data is String && !_incoming.isClosed) _incoming.add(data);
      },
      onDone: () => unawaited(_incoming.close()),
      onError: (Object _) => unawaited(close()),
      cancelOnError: true,
    );
  }

  final WebSocket _socket;
  final StreamController<String> _incoming = StreamController();
  bool _closed = false;

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
