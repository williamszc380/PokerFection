import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'online_socket.dart';

/// Opens a WebSocket to [url] (ws:// or wss://). Throws if the server
/// can't be reached within [timeout].
Future<OnlineSocket> connectSocket(String url, {Duration timeout = const Duration(seconds: 10)}) {
  final socket = _WebSocket(web.WebSocket(url));
  return socket._opened.future.timeout(
    timeout,
    onTimeout: () {
      unawaited(socket.close());
      throw TimeoutException('No answer from $url');
    },
  );
}

class _WebSocket implements OnlineSocket {
  _WebSocket(this._socket) {
    _socket.onopen = ((web.Event _) {
      if (!_opened.isCompleted) _opened.complete(this);
    }).toJS;
    _socket.onmessage = ((web.MessageEvent event) {
      final data = event.data;
      if (data.isA<JSString>() && !_incoming.isClosed) _incoming.add((data as JSString).toDart);
    }).toJS;
    _socket.onerror = ((web.Event _) {
      if (!_opened.isCompleted) _opened.completeError(StateError("Can't connect"));
    }).toJS;
    _socket.onclose = ((web.CloseEvent _) {
      if (!_opened.isCompleted) _opened.completeError(StateError("Can't connect"));
      _closed = true;
      unawaited(_incoming.close());
    }).toJS;
  }

  final web.WebSocket _socket;
  final Completer<OnlineSocket> _opened = Completer();
  final StreamController<String> _incoming = StreamController();
  bool _closed = false;

  @override
  Stream<String> get messages => _incoming.stream;

  @override
  void send(String message) {
    if (_closed || _socket.readyState != web.WebSocket.OPEN) return;
    _socket.send(message.toJS);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _socket.close(1000);
    unawaited(_incoming.close());
  }
}
