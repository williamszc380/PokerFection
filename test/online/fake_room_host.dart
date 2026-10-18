/// A room hosted "on this device" for widget tests: the room's registry and
/// its PeerHost on the fakes of fake_peer.dart, with no sockets, no router
/// and no real network. It does what hostHere does in the app: the room gets
/// the code the PeerHost took at the meeting service, and stopping it gives
/// that code back.
library;

import 'dart:async';
import 'dart:math';

import 'package:pokerfection/src/online/clock.dart';
import 'package:pokerfection/src/online/connect.dart';
import 'package:pokerfection/src/online/memory_link.dart';
import 'package:pokerfection/src/online/online_socket.dart';
import 'package:pokerfection/src/online/peer_config.dart';
import 'package:pokerfection/src/online/peer_host.dart';
import 'package:pokerfection/src/online/peer_socket.dart';
import 'package:pokerfection/src/online/protocol.dart' show CloseReason;
import 'package:pokerfection/src/online/room_host.dart';
import 'package:pokerfection/src/server/room_registry.dart';

import 'fake_peer.dart';

/// The internet as the tests see it: the meeting service, WebRTC, and the
/// clock that drives both (moved by the test, with the widgets' time).
class FakeInternet {
  FakeInternet() : clock = ManualClock() {
    broker = FakeBroker(clock);
  }

  final ManualClock clock;
  late final FakeBroker broker;
  final FakeRtc rtc = FakeRtc();

  /// A guest's way to rooms through the meeting service, on these fakes.
  PeerConnector guest([int seed = 20]) =>
      PeerConnector(rtc: rtc, connectSignaling: broker.connect, clock: clock, random: Random(seed));
}

/// A room hosted here, on [FakeInternet]'s fakes. Its own app connects to
/// [ownServer] through [connectOwn]; a friend on the same Wi-Fi reaches it
/// at [localAddresses] through [connectNearby].
class TestRoomHost implements RoomHost {
  TestRoomHost._(this.net, this.localAddresses, this.routerEndpoint);

  /// Starts it: takes [code] (or a random one) at the meeting service, as
  /// Create Room does.
  static Future<TestRoomHost> start(
    FakeInternet net, {
    String? code,
    List<String> localAddresses = const ['192.168.1.20'],
    ({String address, int port})? routerEndpoint,
  }) async {
    final host = TestRoomHost._(net, localAddresses, routerEndpoint);
    host.registry = RoomRegistry(
      clock: net.clock,
      random: Random(3),
      maxRooms: 1,
      nextCode: () => host.peerCode,
      atMeetingService: (code) => host.peerCode == code,
      onRoomClosed: (_) => unawaited(host.stop()),
    );
    host.peer = PeerHost(
      accept: host.registry.accept,
      seatTokens: () => host.registry.seatTokens,
      rtc: net.rtc,
      connectSignaling: net.broker.connect,
      clock: net.clock,
      random: Random(4),
      pickCode: code == null ? null : () => code,
    );
    await host.peer.start();
    host._statuses = host.peer.statuses.listen((_) => host._changed());
    return host;
  }

  final FakeInternet net;
  late final RoomRegistry registry;
  late final PeerHost peer;
  StreamSubscription<PeerStatus>? _statuses;

  @override
  final List<String> localAddresses;

  @override
  ({String address, int port})? routerEndpoint;

  @override
  int get port => 47474;

  @override
  String get ownServer => 'memory:host';

  /// The host's own app's connection to the room.
  @override
  OnlineSocket connectOwn() {
    final (server, device) = MemoryLink.pair(address: 'host');
    registry.accept(server);
    return device;
  }

  /// Whether friends on the same Wi-Fi reach it now ([connector]'s
  /// nearby): a test turns it off for a phone that left the Wi-Fi.
  bool wifi = true;

  /// A friend's connection over the same Wi-Fi.
  OnlineSocket connectNearby() {
    final (server, device) = MemoryLink.pair(address: '192.168.1.30');
    registry.accept(server);
    return device;
  }

  /// How the apps in a test connect: the host's own app in memory, the
  /// same Wi-Fi in memory when [nearby], a room through the meeting service
  /// on the fakes (as [guest]), and nothing else (no such server).
  Future<OnlineSocket> Function(String url) connector({bool nearby = true, PeerConnector? guest}) {
    final through = guest ?? net.guest();
    return (url) async {
      if (url == ownServer) return connectOwn();
      if (nearby && wifi && localAddresses.any((a) => url == 'ws://$a:$port/ws')) return connectNearby();
      if (isPeerEntry(url)) return connectAny(url, peer: through);
      throw StateError('Nothing listens at $url');
    };
  }

  @override
  PeerStatus get internet => peer.status;

  @override
  String? get peerCode => switch (peer.status.trouble) {
    PeerTrouble.codeTaken || PeerTrouble.unsupported => null,
    _ => peer.code,
  };

  @override
  bool get servesWeb => false;

  @override
  bool get inBrowser => false;

  final StreamController<void> _changes = StreamController.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  void _changed() {
    if (!_changes.isClosed) _changes.add(null);
  }

  /// How many times the app asked it to check the meeting service.
  int checks = 0;

  @override
  void checkInternet() {
    checks++;
    peer.checkSignaling();
  }

  @override
  Future<void> get routerSetup async {}

  final Completer<void> _stopped = Completer();

  @override
  Future<void> get stopped => _stopped.future;

  Future<void>? _stopping;

  /// The room closing calls this again (onRoomClosed): that call gets the
  /// same stop.
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
    await peer.stop();
    await _statuses?.cancel();
    await _changes.close();
    _stopped.complete();
  }
}
