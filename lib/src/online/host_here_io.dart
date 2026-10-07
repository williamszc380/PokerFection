import 'dart:async';
import 'dart:io';

import '../server/poker_server.dart';
import '../server/room_finder.dart';
import '../server/room_registry.dart';
import '../server/upnp.dart';
import '../server/web_files.dart';
import 'protocol.dart' show CloseReason;
import 'room_host.dart';

/// Windows, Android and iOS can host a room.
const canHostHere = true;

/// Starts the game server on this device, for one room (the one the host's
/// app creates next): on [PokerServer.defaultPort], or one of the next few
/// when it is taken. Then, in the background, asks the router to open the
/// port for friends on the internet (not on iOS, see [InternetAccess.byHand]).
/// With [openRouter] false it leaves the router alone, as if there were none
/// (tool/host_check.dart --no-router).
/// Throws a [SocketException] if it can't listen at all.
Future<RoomHost> hostHere({void Function(String message)? log, bool openRouter = true}) =>
    _LocalHost._start(log, openRouter: openRouter);

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
  _LocalHost._(this._server, this.port, this._addresses, this.servesWeb);

  static Future<_LocalHost> _start(void Function(String message)? log, {required bool openRouter}) async {
    late final _LocalHost host;
    // One room: the host's. Once it closes, the server stops.
    final registry = RoomRegistry(maxRooms: 1, log: log, onRoomClosed: (_) => unawaited(host.stop()));
    final web = _webFiles();
    final server = PokerServer(registry: registry, web: web, log: log);
    final port = await server.start(tries: 10);
    host = _LocalHost._(server, port, await localNetworkAddresses(), web != null);
    // A bare room code then finds this room on the same network.
    host._beacon = await RoomBeacon.start(
      port: PokerServer.defaultPort,
      serverPort: port,
      hasRoom: (code) => registry.room(code) != null,
    );
    if (openRouter) {
      unawaited(host._openRouter());
    } else {
      host.internet = InternetAccess.noRouter;
    }
    return host;
  }

  final PokerServer _server;
  RoomBeacon? _beacon;
  OpenPort? _openPort;

  @override
  final int port;

  @override
  final bool servesWeb;

  List<String> _addresses;

  @override
  List<String> get localAddresses => _addresses;

  @override
  String get ownServer => 'ws://127.0.0.1:$port/ws';

  @override
  InternetAccess internet = InternetAccess.checking;

  @override
  ({String address, int port})? get publicEndpoint {
    final open = _openPort;
    return open == null ? byHand : (address: open.externalAddress, port: open.externalPort);
  }

  ({String address, int port})? _byHand;

  @override
  ({String address, int port})? get byHand => _byHand;

  @override
  set byHand(({String address, int port})? value) {
    if (value == _byHand) return;
    _byHand = value;
    if (!_changes.isClosed) _changes.add(null);
  }

  final StreamController<void> _changes = StreamController.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  Future<void>? _stopping;
  final Completer<void> _stopped = Completer();

  @override
  Future<void> get stopped => _stopped.future;

  /// Asks the router to open the port (iPhones and iPads may not search the
  /// network for it without Apple's permission: by hand there).
  Future<void> _openRouter() async {
    if (Platform.isIOS) {
      _setInternet(InternetAccess.byHand);
      return;
    }
    final (open, setup) = await OpenPort.open(port, fromAddresses: _addresses);
    if (_stopping != null) {
      await open?.close();
      return;
    }
    _openPort = open;
    if (open != null) {
      // The address the router leads to goes first.
      _addresses = {open.gateway.localAddress, ..._addresses}.toList();
      // A router that won't renew the port gets another: the invites change.
      open.onMoved = () => _setInternet(InternetAccess.ready);
    }
    _setInternet(switch (setup) {
      RouterSetup.ready => InternetAccess.ready,
      RouterSetup.noRouter => InternetAccess.noRouter,
      RouterSetup.refused => InternetAccess.refused,
      RouterSetup.notPublic => InternetAccess.notPublic,
    });
  }

  void _setInternet(InternetAccess value) {
    internet = value;
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Future<void> stop() => _stopping ??= _stop();

  Future<void> _stop() async {
    _beacon?.close();
    await Future.wait([_server.close(reason: CloseReason.roomClosed), ?_openPort?.close()]);
    await _changes.close();
    _stopped.complete();
  }
}
