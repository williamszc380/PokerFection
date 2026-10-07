import 'dart:async';

import '../server/client_link.dart';
import 'online_socket.dart';

/// One end of a connection inside one process, for tests that run the
/// server and the devices together: what one end sends, the other gets,
/// in order and a moment later, as over a socket. Either end can be the
/// server's side ([ClientLink]) or a device's ([OnlineSocket]).
class MemoryLink implements ClientLink, OnlineSocket {
  MemoryLink._(this.address);

  /// Two connected ends: the server's and the device's.
  static (MemoryLink server, MemoryLink device) pair({String address = 'memory'}) {
    final server = MemoryLink._(address), device = MemoryLink._(address);
    server._other = device;
    device._other = server;
    return (server, device);
  }

  @override
  final String address;

  late final MemoryLink _other;
  final StreamController<String> _incoming = StreamController();
  bool _closed = false;

  /// Everything this end has sent, for tests to look at.
  final List<String> sent = [];

  bool get isClosed => _closed;

  @override
  Stream<String> get messages => _incoming.stream;

  @override
  void send(String message) {
    if (_closed) return;
    sent.add(message);
    _other._incoming.add(message);
  }

  /// Closes both ends (like a dropped connection, from either side).
  /// Messages already sent are still delivered first.
  @override
  Future<void> close() async {
    if (_closed) return;
    for (final end in [this, _other]) {
      end._closed = true;
      // Completes only once someone has read to the end: don't wait.
      unawaited(end._incoming.close());
    }
  }
}
