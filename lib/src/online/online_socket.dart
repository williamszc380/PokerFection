/// A connection to the game server, as the app sees it: text messages
/// (JSON) both ways. A WebSocket, or in tests a MemoryLink.
abstract interface class OnlineSocket {
  /// Messages from the server, in order; done once the connection closes.
  Stream<String> get messages;

  /// Sends [message] to the server; does nothing once closed.
  void send(String message);

  /// Closes the connection.
  Future<void> close();
}

/// Nothing listens at the server's address any more (the device is there,
/// but the app that served the room has stopped). Only apps can tell; in a
/// browser a refused connection looks like any other failure.
class ConnectionRefused implements Exception {
  const ConnectionRefused();

  @override
  String toString() => 'ConnectionRefused';
}
