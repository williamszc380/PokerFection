/// A room server inside a widget test (RoomRegistry on a clock the test
/// moves, connections in memory), the app clients that join it, and guests
/// that play by themselves: for the room service, panel and table tests.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/engine/actions.dart';
import 'package:pokerfection/src/online/clock.dart';
import 'package:pokerfection/src/online/games/game_runner.dart';
import 'package:pokerfection/src/online/memory_link.dart';
import 'package:pokerfection/src/online/online_client.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/server/room_registry.dart';

/// The server, on [clock] ([games]: the games other than Hold'em it runs).
class TestServer {
  TestServer({
    int seed = 3,
    int roomCap = RoomRegistry.largeRoomCap,
    Duration? roomIdle,
    Map<String, OnlineGame>? games,
  }) : clock = ManualClock() {
    registry = RoomRegistry(clock: clock, random: Random(seed), roomCap: roomCap, roomIdle: roomIdle, games: games);
  }

  final ManualClock clock;
  late final RoomRegistry registry;

  /// Every app connection's device end, in order.
  final List<MemoryLink> links = [];

  /// A new memory connection to the server (a device's end).
  MemoryLink connect({bool record = false}) {
    final (server, device) = MemoryLink.pair(record: record);
    registry.accept(server);
    links.add(device);
    return device;
  }

  /// An app's connection, not opened yet.
  OnlineClient client({void Function(RejoinRecord? record)? onRecord, bool record = false}) => OnlineClient(
    'memory',
    clock: clock,
    onRecord: onRecord,
    connect: (_) async => connect(record: record),
  );

  /// Lets [time] pass, for the widgets and the server.
  Future<void> wait(WidgetTester tester, [Duration time = const Duration(milliseconds: 100)]) async {
    for (var left = time; left > Duration.zero; left -= const Duration(milliseconds: 100)) {
      clock.advance(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Lets time pass until [done].
  Future<void> until(WidgetTester tester, bool Function() done, String what, {int limit = 1200}) async {
    for (var i = 0; !done(); i++) {
      expect(i, lessThan(limit), reason: 'never: $what');
      await wait(tester);
    }
  }

  /// Opens [client] with [opening] (a create, a join), letting time pass.
  Future<Welcome> open(WidgetTester tester, OnlineClient client, ClientMessage opening) async {
    Welcome? welcome;
    Object? failed;
    unawaited(client.open(opening).then((w) => welcome = w, onError: (Object e) => failed = e));
    await until(tester, () => welcome != null || failed != null, 'opened');
    if (failed != null) throw failed!;
    // Its RoomState.
    await until(tester, () => client.room != null, 'the room');
    return welcome!;
  }
}

/// A guest who plays by themselves on a raw connection: joins as [name],
/// is Ready for every hand, and checks or calls at their turns (folding
/// never). [seen] is everything the server sent them.
class AutoGuest {
  AutoGuest(this.server, this.name, {this.think = Duration.zero});

  final TestServer server;
  final String name;

  /// How long they take to act (on the server's clock).
  final Duration think;
  late final MemoryLink link = server.connect();
  final List<ServerMessage> seen = [];
  int _handSeat = -1;
  bool _listening = false;

  /// The latest RoomState.
  RoomState? get room => seen.whereType<RoomState>().lastOrNull;

  void join(String code) {
    _listen();
    link.send(JoinRoom(code: code, name: name).encode());
  }

  void send(ClientMessage message) => link.send(message.encode());

  void _listen() {
    if (_listening) return;
    _listening = true;
    link.messages.listen((text) {
      final ServerMessage m;
      try {
        m = ServerMessage.decode(text);
      } on ProtocolError {
        return;
      }
      seen.add(m);
      switch (m) {
        case NextHand():
          _handSeat = m.you ?? -1;
          if (m.you != null) link.send(Ready(m.hand).encode());
        case HandDealt(:final hand, :final turn) || HandEvents(:final hand, :final turn):
          if (turn != null && turn.seat == _handSeat) {
            final move = turn.toCall == 0 ? const PlayerAction.check() : const PlayerAction.call();
            void act() => link.send(Act(hand: hand, turnId: turn.turnId, action: move).encode());
            if (think == Duration.zero) {
              act();
            } else {
              server.clock.schedule(think, act);
            }
          }
        default:
          break;
      }
    });
  }
}
