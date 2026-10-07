/// One player's connection, as the server sees it: text messages (JSON)
/// both ways. A WebSocket, or in tests a MemoryLink.
abstract interface class ClientLink {
  /// Where the connection comes from, for the limits per address.
  String get address;

  /// Messages from the player's device, in order; done once the
  /// connection closes.
  Stream<String> get messages;

  /// Sends [message] to the device; does nothing once closed.
  void send(String message);

  /// Closes the connection.
  Future<void> close();
}
