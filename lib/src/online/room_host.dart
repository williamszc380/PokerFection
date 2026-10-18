/// Hosting a room on this device: Create Room starts the game server inside
/// the app (see host_here.dart), and the host's own app joins it like
/// everyone else. Friends on the same network come in at this device's
/// local address; friends anywhere else connect straight to this device
/// through the meeting service (PeerHost, see peer_config.dart), with the
/// room's code as its name there. A browser hosts the room inside the page
/// (InProcessHost): everyone comes in through the meeting service there.
library;

import 'online_socket.dart';
import 'peer_status.dart';

export 'peer_status.dart';

/// A room's game server running on this device.
abstract interface class RoomHost {
  /// The port it listens on, on every network of this device.
  int get port;

  /// Where this device's own app connects.
  String get ownServer;

  /// The host's own app's connection to the room when it is made inside
  /// the app (a room hosted in a browser has no server to connect to); null
  /// when the app connects to [ownServer] like anyone else.
  OnlineSocket? connectOwn();

  /// Whether the room runs in a browser tab: no game server, so no way in
  /// on the same Wi-Fi of its own (friends there come in through the
  /// meeting service too), and it closes with the tab.
  bool get inBrowser;

  /// This device's addresses on its local networks, best first.
  List<String> get localAddresses;

  /// Whether friends on the internet can come in (through the meeting
  /// service), and if not, why.
  PeerStatus get internet;

  /// The code this device holds the room's name for at the meeting service:
  /// the room's own code (the room is made with it). Null when it holds none
  /// (someone else had it, or this build can't make direct connections):
  /// invites then name no room there, or they would lead to someone else's.
  String? get peerCode;

  /// The router's public address and port, when the router opened the port
  /// by itself (UPnP): a second way in from the internet, for guests whose
  /// network can't connect directly. Null otherwise; nobody is ever asked
  /// to set up a router.
  ({String address, int port})? get routerEndpoint;

  /// Whether it serves the web version to browsers (when the app has one).
  bool get servesWeb;

  /// Fires whenever [internet], [peerCode] or [routerEndpoint] changes.
  Stream<void> get changes;

  /// Checks the way in from the internet now (the app is back on screen:
  /// the connection to the meeting service may have died meanwhile), and
  /// makes it again if needed.
  void checkInternet();

  /// Completes once the automatic router setup has finished, whether or not
  /// it opened the port (tool/host_check.dart waits for it).
  Future<void> get routerSetup;

  /// Completes once it has stopped.
  Future<void> get stopped;

  /// Stops serving (the room closes for everyone, if still open), gives the
  /// room's name at the meeting service back, and closes the router's port
  /// again.
  Future<void> stop();
}
