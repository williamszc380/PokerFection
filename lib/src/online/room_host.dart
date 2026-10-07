/// Hosting a room on this device: Create Room starts the game server inside
/// the app (see host_here.dart), and the host's own app joins it like
/// everyone else. Friends on the same network come in at this device's
/// local address; friends on the internet at the router's public address,
/// once the router has opened the port.
library;

/// Whether friends on the internet can come in through the router.
enum InternetAccess {
  /// Setting up the router (a few seconds).
  checking,

  /// The router opened the port, at a public address.
  ready,

  /// No router answered the automatic setup (UPnP).
  noRouter,

  /// The router refused to open the port.
  refused,

  /// The router has no public address of its own (the internet provider
  /// shares one, CGNAT; or a second router sits in front of it).
  notPublic,

  /// This device can't set up the router (iPhone and iPad need a
  /// permission from Apple for it): only by hand.
  byHand,
}

/// A room's game server running on this device.
abstract interface class RoomHost {
  /// The port it listens on, on every network of this device.
  int get port;

  /// Where this device's own app connects.
  String get ownServer;

  /// This device's addresses on its local networks, best first.
  List<String> get localAddresses;

  InternetAccess get internet;

  /// Where friends on the internet come in: the router's public address
  /// and port once [internet] is ready, else the one set by hand
  /// ([byHand]), if any.
  ({String address, int port})? get publicEndpoint;

  /// The router's public address and port as the host typed them, for a
  /// router that can't be opened automatically (its port forwarded to this
  /// device by hand). Nothing can check it works.
  ({String address, int port})? get byHand;
  set byHand(({String address, int port})? value);

  /// Whether it serves the web version to browsers (when the app has one).
  bool get servesWeb;

  /// Fires whenever [internet] or [publicEndpoint] changes.
  Stream<void> get changes;

  /// Completes once it has stopped.
  Future<void> get stopped;

  /// Stops serving (the room closes for everyone, if still open) and
  /// closes the router's port again.
  Future<void> stop();
}
