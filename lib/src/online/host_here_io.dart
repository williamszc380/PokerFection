import 'dart:async';
import 'dart:io';

import '../server/client_link.dart';
import '../server/poker_server.dart';
import '../server/room_finder.dart';
import '../server/room_registry.dart';
import '../server/upnp.dart';
import '../server/web_files.dart';
import 'online_socket.dart';
import 'peer_host.dart';
import 'protocol.dart' show CloseReason;
import 'room_host.dart';

/// Windows, Android and iOS can host a room.
const canHostHere = true;

/// Makes the PeerHost that lets friends anywhere in, given where it hands
/// each guest's connection (tests give one on fakes).
typedef PeerHostMaker = PeerHost Function(void Function(ClientLink link) accept);

/// Starts the game server on this device, for one room (the one the host's
/// app creates next): on [PokerServer.defaultPort], or one of the next few
/// when it is taken. Alongside it, [PeerHost] takes the room's code at the
/// meeting service, so friends anywhere can come in with it (made by [peer]
/// when given); the room gets that code. Then, in the background and
/// silently, asks the router to open the port too, as a second way in (not
/// on iOS, which needs a permission from Apple for it). With [openRouter]
/// false it leaves the router alone (tests, and tool/host_check.dart
/// --no-router). With [loopbackOnly] it listens on this device only and
/// answers no searches from the network: for tests, which must not open
/// the computer to its networks.
/// Throws a [SocketException] if it can't listen at all.
Future<RoomHost> hostHere({
  void Function(String message)? log,
  bool openRouter = true,
  PeerHostMaker? peer,
  bool loopbackOnly = false,
}) => _LocalHost._start(log, openRouter: openRouter, peer: peer, loopbackOnly: loopbackOnly);

/// The game servers of hosts on this device's networks that have room
/// [code] (by asking around, see room_finder.dart).
Future<List<String>> findRoomNearby(String code) async =>
    findRoom(code, port: PokerServer.defaultPort, localAddresses: await localNetworkAddresses());

/// This device's addresses on its local networks (10/8, 172.16/12,
/// 192.168/16), best first: Wi-Fi and wired ones before virtual machines'
/// networks; mobile data's left out (nobody can come in that way).
Future<List<String>> localNetworkAddresses() async {
  final List<NetworkInterface> interfaces;
  try {
    interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
  } on Object {
    return const [];
  }
  final virtual = RegExp(r'vEthernet|VirtualBox|VMware|Hyper-V|WSL|Docker|vbox|vmnet|virbr|veth|^br-', caseSensitive: false);
  final mobile = RegExp(r'^(rmnet|ccmni|pdp_ip|wwan)', caseSensitive: false);
  final found = <({int rank, String address})>[];
  for (final interface in interfaces) {
    if (mobile.hasMatch(interface.name)) continue;
    for (final a in interface.addresses) {
      if (!isPrivateAddress(a.address)) continue;
      final kind = a.address.startsWith('192.168.') ? 0 : (a.address.startsWith('10.') ? 1 : 2);
      found.add((rank: (virtual.hasMatch(interface.name) ? 10 : 0) + kind, address: a.address));
    }
  }
  found.sort((a, b) => a.rank - b.rank);
  return {for (final f in found) f.address}.take(3).toList();
}

/// The web version next to the app (data/web, where the Windows build puts
/// it), or while developing the one tool/build_web.dart --host made.
WebFiles? _webFiles() {
  final sep = Platform.pathSeparator;
  for (final path in [
    '${File(Platform.resolvedExecutable).parent.path}${sep}data${sep}web',
    'build${sep}web_host',
  ]) {
    final files = WebFiles(Directory(path));
    if (files.available) return files;
  }
  return null;
}

class _LocalHost implements RoomHost {
  _LocalHost._(this._server, this._peer, this.port, this._addresses, this.servesWeb);

  static Future<_LocalHost> _start(
    void Function(String message)? log, {
    required bool openRouter,
    required PeerHostMaker? peer,
    required bool loopbackOnly,
  }) async {
    late final _LocalHost host;
    // One room: the host's, with the code taken at the meeting service. Once it closes, the server stops.
    final registry = RoomRegistry(
      maxRooms: 1,
      // A phone also runs the room and the bots, on top of the game: fewer members.
      roomCap: Platform.isAndroid || Platform.isIOS ? RoomRegistry.smallRoomCap : RoomRegistry.largeRoomCap,
      // The room lives as long as this app does (until the host closes it): it never idles out.
      roomIdle: null,
      log: log,
      nextCode: () => host.peerCode,
      // Guests may come back through the meeting service while this device holds the room's name there.
      atMeetingService: (code) => host.peerCode == code,
      onRoomClosed: (_) => unawaited(host.stop()),
    );
    final peerHost =
        peer?.call(registry.accept) ?? PeerHost(accept: registry.accept, seatTokens: () => registry.seatTokens);
    final web = _webFiles();
    final server = PokerServer(registry: registry, web: web, log: log);
    final port = await server.start(tries: 10, address: loopbackOnly ? InternetAddress.loopbackIPv4 : null);
    try {
      // At most PeerHost.startWait: a slow meeting service doesn't hold the room up.
      await peerHost.start();
    } on Object {
      await server.close();
      rethrow;
    }
    host = _LocalHost._(server, peerHost, port, await localNetworkAddresses(), web != null);
    host._watchPeer();
    // A bare room code then finds this room on the same network.
    if (!loopbackOnly) {
      host._beacon = await RoomBeacon.start(
        port: PokerServer.defaultPort,
        serverPort: port,
        hasRoom: (code) => registry.room(code) != null,
      );
    }
    if (openRouter && !Platform.isIOS) {
      unawaited(host._openRouter().whenComplete(host._routerSetDone));
    } else {
      host._routerSetDone();
    }
    return host;
  }

  final PokerServer _server;
  final PeerHost _peer;
  RoomBeacon? _beacon;
  OpenPort? _openPort;
  StreamSubscription<PeerStatus>? _peerStatuses;

  @override
  final int port;

  @override
  final bool servesWeb;

  List<String> _addresses;

  @override
  List<String> get localAddresses => _addresses;

  @override
  String get ownServer => 'ws://127.0.0.1:$port/ws';

  /// The host's own app connects to the server's port, as everyone does.
  @override
  OnlineSocket? connectOwn() => null;

  @override
  bool get inBrowser => false;

  @override
  PeerStatus get internet => _peer.status;

  @override
  String? get peerCode => switch (_peer.status.trouble) {
    PeerTrouble.codeTaken || PeerTrouble.unsupported => null,
    _ => _peer.code,
  };

  @override
  ({String address, int port})? get routerEndpoint {
    final open = _openPort;
    return open == null ? null : (address: open.externalAddress, port: open.externalPort);
  }

  final StreamController<void> _changes = StreamController.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  @override
  void checkInternet() => _peer.checkSignaling();

  final Completer<void> _routerSetup = Completer();

  @override
  Future<void> get routerSetup => _routerSetup.future;

  void _routerSetDone() {
    if (!_routerSetup.isCompleted) _routerSetup.complete();
  }

  Future<void>? _stopping;
  final Completer<void> _stopped = Completer();

  @override
  Future<void> get stopped => _stopped.future;

  /// The lobby follows the meeting service's status as it changes.
  void _watchPeer() => _peerStatuses = _peer.statuses.listen((_) => _changed());

  /// Asks the router to open the port, silently: when it does, invites
  /// carry its public address too (after the direct way in).
  Future<void> _openRouter() async {
    final (open, _) = await OpenPort.open(port, fromAddresses: _addresses);
    if (_stopping != null) {
      await open?.close();
      return;
    }
    _openPort = open;
    if (open == null) return;
    // The address the router leads to goes first.
    _addresses = {open.gateway.localAddress, ..._addresses}.toList();
    // A router that won't renew the port gets another: the invites change.
    open.onMoved = _changed;
    _changed();
  }

  void _changed() {
    if (!_changes.isClosed) _changes.add(null);
  }

  /// Closes the room for everyone, gives the room's name back and closes
  /// the router's port. The room closing calls this again from inside
  /// (onRoomClosed, while the server closes it): that call gets the same
  /// stop, so it is done once.
  @override
  Future<void> stop() {
    if (_stopping case final stopping?) return stopping;
    final done = Completer<void>();
    _stopping = done.future;
    done.complete(_stop());
    return done.future;
  }

  Future<void> _stop() async {
    _beacon?.close();
    await Future.wait([_server.close(reason: CloseReason.roomClosed), _peer.stop(), ?_openPort?.close()]);
    await _peerStatuses?.cancel();
    await _changes.close();
    _routerSetDone();
    _stopped.complete();
  }
}
