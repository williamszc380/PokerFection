import 'dart:async';
import 'dart:math';

import '../server/client_link.dart';
import '../server/room_registry.dart';
import 'clock.dart';
import 'memory_link.dart';
import 'online_socket.dart';
import 'peer_host.dart';
import 'protocol.dart' show CloseReason;
import 'room_host.dart';

/// Makes the PeerHost that lets friends in, given where it hands each
/// guest's connection (tests give one on fakes).
typedef GuestDoor = PeerHost Function(void Function(ClientLink link) accept);

/// A room hosted inside the app itself, with no server sockets: how a
/// browser hosts (a web page can't listen for connections). The room
/// (RoomRegistry, plain Dart) runs in the page; every friend comes in over
/// a direct connection through the meeting service ([PeerHost]), even one
/// on the same Wi-Fi; and the host's own app joins it in memory
/// ([connectOwn]), not over any network.
///
/// It lives as long as the page: closing the tab closes the room (see
/// host_here_web.dart, which warns first and tells everyone).
class InProcessHost implements RoomHost {
  InProcessHost._();

  /// Starts it: takes the room's code at the meeting service (PeerHost made
  /// by [door] when given, else the real one), as Create Room does. The room
  /// opens anyway when the service is slow or out of reach: [internet] says
  /// how it is going.
  static Future<InProcessHost> start({
    GuestDoor? door,
    Clock? clock,
    Random? random,
    void Function(String message)? log,
  }) async {
    final host = InProcessHost._();
    // One room: the host's, with the code taken at the meeting service. Once it closes, hosting stops.
    host.registry = RoomRegistry(
      clock: clock,
      random: random,
      maxRooms: 1,
      // A browser also runs the room and the bots, on top of the game: fewer members.
      roomCap: RoomRegistry.smallRoomCap,
      // The room lives as long as this page does (until the host closes it): it never idles out.
      roomIdle: null,
      log: log,
      nextCode: () => host.peerCode,
      atMeetingService: (code) => host.peerCode == code,
      onRoomClosed: (_) => unawaited(host.stop()),
    );
    host._peer =
        door?.call(host.registry.accept) ??
        PeerHost(accept: host.registry.accept, seatTokens: () => host.registry.seatTokens);
    // At most PeerHost.startWait: a slow meeting service doesn't hold the room up.
    await host._peer.start();
    host._statuses = host._peer.statuses.listen((_) => host._changed());
    return host;
  }

  /// The rooms (one), as the server keeps them, but in this page.
  late final RoomRegistry registry;
  late final PeerHost _peer;
  StreamSubscription<PeerStatus>? _statuses;

  /// Listens on no port: nobody connects to it but through the meeting
  /// service.
  @override
  int get port => 0;

  /// Not a network address: the host's own app joins with [connectOwn].
  @override
  String get ownServer => 'memory:host';

  /// The host's own app's connection to the room, in memory.
  @override
  OnlineSocket connectOwn() {
    // Keeps nothing of what goes through it: the room may be hosted for hours.
    final (server, device) = MemoryLink.pair(address: 'host');
    registry.accept(server);
    return device;
  }

  /// None: friends on the same Wi-Fi come in through the meeting service
  /// too.
  @override
  List<String> get localAddresses => const [];

  @override
  bool get inBrowser => true;

  @override
  PeerStatus get internet => _peer.status;

  @override
  String? get peerCode => switch (_peer.status.trouble) {
    PeerTrouble.codeTaken || PeerTrouble.unsupported => null,
    _ => _peer.code,
  };

  /// A page can't ask a router for anything.
  @override
  ({String address, int port})? get routerEndpoint => null;

  @override
  bool get servesWeb => false;

  final StreamController<void> _changes = StreamController.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  void _changed() {
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  void checkInternet() => _peer.checkSignaling();

  @override
  Future<void> get routerSetup async {}

  final Completer<void> _stopped = Completer();

  @override
  Future<void> get stopped => _stopped.future;

  Future<void>? _stopping;

  /// Closes the room for everyone (each hears it at once, over their own
  /// connection) and gives the room's name back. The room closing calls
  /// this again (onRoomClosed): that call gets the same stop.
  @override
  Future<void> stop() {
    if (_stopping case final stopping?) return stopping;
    final done = Completer<void>();
    _stopping = done.future;
    done.complete(_stop());
    return done.future;
  }

  Future<void> _stop() async {
    registry.shutdown(CloseReason.roomClosed);
    await _peer.stop();
    await _statuses?.cancel();
    await _changes.close();
    _stopped.complete();
  }
}
