import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/engine/actions.dart';
import 'package:pokerfection/src/engine/events.dart';
import 'package:pokerfection/src/online/channel_link.dart';
import 'package:pokerfection/src/online/clock.dart';
import 'package:pokerfection/src/online/connect.dart';
import 'package:pokerfection/src/online/memory_link.dart';
import 'package:pokerfection/src/online/online_client.dart';
import 'package:pokerfection/src/online/online_socket.dart';
import 'package:pokerfection/src/online/peer_config.dart';
import 'package:pokerfection/src/online/peer_host.dart';
import 'package:pokerfection/src/online/peer_socket.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/server/room_registry.dart';

import 'fake_peer.dart';

/// A device at the table, as simple as can be: it checks or calls whenever
/// it is its turn, and is ready for each next hand.
class _Player {
  _Player(this.client) {
    client.attach(_on);
  }

  final OnlineClient client;
  final List<ServerMessage> seen = [];
  int handsEnded = 0;
  int? _you;

  void _on(ServerMessage m) {
    seen.add(m);
    switch (m) {
      case NextHand():
        _you = m.you;
        client.send(Ready(m.hand));
      case HandDealt(:final hand, :final turn, :final batch) || HandEvents(:final hand, :final turn, :final batch):
        handsEnded += batch.whereType<HandEnded>().length;
        _act(hand, turn);
      case Snapshot(:final hand, :final next):
        // Back after the connection dropped: on with the hand where it is.
        if (next != null) {
          _you = next.you;
          client.send(Ready(next.hand));
        }
        if (hand != null) {
          _you = hand.lineup.you;
          _act(hand.hand, hand.turn);
        }
      default:
        break;
    }
  }

  void _act(int hand, Turn? turn) {
    if (turn == null || turn.seat != _you) return;
    final move = turn.toCall == 0 ? const PlayerAction.check() : const PlayerAction.call();
    client.send(Act(hand: hand, turnId: turn.turnId, action: move));
  }
}

/// A room hosted with direct connections, on fakes: the meeting service,
/// WebRTC, and a clock the test moves (no real sockets, no real time).
class _Game {
  _Game(this.tester) {
    registry = RoomRegistry(clock: clock, random: Random(3), maxRooms: 1, nextCode: () => peer.code);
    peer = PeerHost(
      accept: (link) {
        links.add(link as ChannelLink);
        registry.accept(link);
      },
      rtc: rtc,
      connectSignaling: broker.connect,
      clock: clock,
      random: Random(4),
    );
  }

  final WidgetTester tester;
  final clock = ManualClock();
  late final broker = FakeBroker(clock);
  final rtc = FakeRtc();
  late final RoomRegistry registry;
  late final PeerHost peer;

  /// The guests' connections, as the room got them.
  final List<ChannelLink> links = [];
  final List<OnlineClient> clients = [];
  late String code;
  late _Player host;

  Future<void> wait([Duration time = const Duration(milliseconds: 100)]) async {
    clock.advance(time);
    await tester.pump(time);
  }

  /// [future]'s value, letting time pass until it comes.
  Future<T> settle<T>(Future<T> future) async {
    var done = false;
    unawaited(future.then((_) => done = true, onError: (Object _) => done = true));
    for (var i = 0; !done; i++) {
      expect(i, lessThan(400), reason: 'never settled');
      await wait();
    }
    return future;
  }

  /// Takes the room's name, then the host's app creates the room (its own
  /// connection is in memory, as in the app).
  Future<void> open() async {
    code = await settle(peer.start());
    expect(peer.status, PeerStatus.ready);
    final client = OnlineClient(
      'memory:host',
      clock: clock,
      random: Random(1),
      connect: (_) async {
        final (server, device) = MemoryLink.pair(address: 'host');
        registry.accept(server);
        return device;
      },
    );
    clients.add(client);
    final welcome = await settle(
      client.open(
        const CreateRoom(
          name: 'Ann',
          game: holdemKey,
          // Stacks reset every hand: nobody runs out of chips here.
          settings: RoomSettings(seats: 3, stackBb: 20, resetStacks: true),
        ),
      ),
    );
    expect(welcome.code, code, reason: 'the room has the code the host took at the meeting service');
    client.send(const TakeSeat());
    host = _Player(client);
  }

  /// A guest joins with the room's code only, through the meeting service.
  Future<_Player> join(String name, int seed) async {
    final connector = PeerConnector(rtc: rtc, connectSignaling: broker.connect, clock: clock, random: Random(seed));
    final client = OnlineClient(
      peerEntry(code),
      clock: clock,
      random: Random(seed),
      connect: (url) => connectAny(url, peer: connector),
    );
    clients.add(client);
    await settle(client.open(JoinRoom(code: code, name: name)));
    client.send(const TakeSeat());
    await playUntil(() => client.mySeat != null, '$name seated');
    return _Player(client);
  }

  /// Plays on until [done].
  Future<void> playUntil(bool Function() done, String what) async {
    for (var step = 0; !done(); step++) {
      expect(step, lessThan(5000), reason: 'never: $what');
      await wait();
    }
  }

  /// Everyone goes, and the room closes; time passes until all is done.
  Future<void> end() async {
    final closing = Future.wait([for (final client in clients) client.close(leave: false)]);
    registry.shutdown();
    final stopping = peer.stop();
    await settle(Future.wait([closing, stopping]));
    await wait(const Duration(seconds: 30));
  }
}

void main() {
  testWidgets('a host and two guests play full hands over direct connections; each guest comes in at its own '
      'address', (tester) async {
    final game = _Game(tester);
    await game.open();
    final ben = await game.join('Ben', 20), cat = await game.join('Cat', 30);
    expect(game.links.map((l) => l.address).toSet(), hasLength(2));
    expect(game.links.map((l) => l.address), everyElement(startsWith('peer:pokerfection-v1-guest-')));
    game.host.client.send(const StartGame());
    final players = [game.host, ben, cat];
    await game.playUntil(() => players.every((p) => p.handsEnded >= 4), 'four hands');
    expect([for (final p in players) p.client.status], everyElement(OnlineStatus.open));
    expect(game.broker.closed, isEmpty, reason: 'every message to the meeting service was well shaped');
    // The guests gave their names back once connected; the host keeps the room's.
    expect(game.broker.holds(hostPeerId(game.code)), isTrue);
    expect(game.broker.connects.where((c) => c.id.contains('guest')), hasLength(2));
    await game.end();
  });

  testWidgets("a guest's channel drops: the app gets the seat back over a new connection, and catches up "
      'with a snapshot', (tester) async {
    final game = _Game(tester);
    await game.open();
    final ben = await game.join('Ben', 20);
    game.host.client.send(const StartGame());
    await game.playUntil(() => ben.handsEnded >= 1, 'a first hand');
    final before = ben.seen.length;
    await (game.links.single.peer as FakeRtcPeer).dropChannel();
    await game.wait();
    expect(ben.client.status, OnlineStatus.reconnecting);
    await game.playUntil(() => ben.client.status == OnlineStatus.open, 'back');
    await game.playUntil(() => ben.seen.skip(before).any((m) => m is Snapshot), 'a snapshot');
    expect(game.links, hasLength(2), reason: 'a new direct connection');
    final again = (game.links.last.peer as FakeRtcPeer).other!.channelEnd!;
    expect(again.sent.first, contains('"t":"rejoin"'));
    final hands = ben.handsEnded;
    await game.playUntil(() => ben.handsEnded >= hands + 2, 'hands after coming back');
    await game.end();
  });

  testWidgets("the host's app vanishes: the guests keep trying, and only after 45 s of finding the room "
      'missing do they say the host closed it', (tester) async {
    final game = _Game(tester);
    await game.open();
    final ben = await game.join('Ben', 20);
    game.host.client.send(const StartGame());
    await game.playUntil(() => ben.handsEnded >= 1, 'a first hand');
    // Gone without a word: its name at the meeting service is free, and nothing more comes through the channel.
    await game.peer.stop();
    (game.links.single.peer as FakeRtcPeer).goSilent();
    final goneAt = game.clock.nowMs;
    await game.playUntil(() => ben.client.status == OnlineStatus.reconnecting, 'noticed');
    expect(game.clock.nowMs - goneAt, lessThanOrEqualTo(8000), reason: 'silent for 6 s (checked every 2 s)');
    await game.playUntil(() => game.broker.expires.isNotEmpty, 'found missing');
    final missingAt = game.clock.nowMs;
    await game.playUntil(() => game.clock.nowMs - missingAt >= 40000, '40 s');
    expect(ben.client.status, OnlineStatus.reconnecting);
    expect(game.broker.expires.length, greaterThanOrEqualTo(3));
    await game.playUntil(() => ben.client.status == OnlineStatus.closed, 'given up');
    expect(game.clock.nowMs - missingAt, inInclusiveRange(45000, 60000));
    expect(ben.client.closeReason, CloseReason.roomClosed);
    expect(ben.client.failure, isNull);
    expect(game.broker.closed, isEmpty);
    await game.end();
  });

  testWidgets('a connection that comes after its time is closed; a direct one is given 20 s (and a moment for its '
      'own verdict), a nearby one 3 s, any other 6 s', (tester) async {
    expect(connectTimeout('peer:K7M2Q'), PeerConnector.timeout + const Duration(seconds: 2));
    expect(PeerConnector.timeout, const Duration(seconds: 20));
    expect(connectTimeout('ws://192.168.1.20:47474/ws'), const Duration(seconds: 3));
    expect(connectTimeout('ws://203.0.113.7:47474/ws'), const Duration(seconds: 6));
    final clock = ManualClock();
    final registry = RoomRegistry(clock: clock, random: Random(1));
    final made = <MemoryLink>[];
    Future<MemoryLink> slow(Duration delay) async {
      await Future<void>.delayed(delay);
      final (server, device) = MemoryLink.pair();
      registry.accept(server);
      made.add(device);
      return device;
    }

    final slowClient = OnlineClient(
      'ws://203.0.113.7:47474/ws',
      alsoTry: ['ws://192.168.1.20:47474/ws'],
      clock: clock,
      connect: (_) => slow(const Duration(seconds: 7)),
    );
    Object? error;
    unawaited(slowClient.open(JoinRoom(code: 'K7M2Q', name: 'Ben')).then((_) {}, onError: (Object e) => error = e));
    await tester.pump(const Duration(seconds: 5));
    expect(error, isNull);
    await tester.pump(const Duration(seconds: 2));
    expect(made.single.isClosed, isTrue, reason: 'came at 7 s, after the 6 s it had');
    await tester.pump(const Duration(seconds: 3));
    expect(error, isA<OnlineFailure>(), reason: 'the nearby address had 3 s');
    await tester.pump(const Duration(seconds: 5));
    expect(made, hasLength(2));
    expect(made.last.isClosed, isTrue);

    // A room reached directly may take its time.
    final direct = OnlineClient('peer:K7M2Q', clock: clock, connect: (_) => slow(const Duration(seconds: 15)));
    final opening = direct.open(const CreateRoom(name: 'Ann', settings: RoomSettings(seats: 2)));
    await tester.pump(const Duration(seconds: 16));
    expect((await opening).isHost, isTrue);
    await direct.close();
    await tester.pump(const Duration(seconds: 15));
  });
  testWidgets('a way in that fails at once (a browser on the https site refuses a ws:// address) is skipped like '
      'one that fails later: the next is tried, and getting the connection back keeps trying', (tester) async {
    final clock = ManualClock();
    final registry = RoomRegistry(clock: clock, random: Random(1));
    var refuseAll = false;
    late MemoryLink link;
    Future<OnlineSocket> connect(String url) {
      // As the browser's WebSocket constructor does: before there is any Future to fail.
      if (refuseAll || url.startsWith('ws://')) throw StateError('SecurityError: insecure WebSocket');
      final (server, device) = MemoryLink.pair();
      registry.accept(server);
      return Future.value(link = device);
    }

    final client = OnlineClient('ws://192.168.1.20:47474/ws', alsoTry: ['peer:K7M2Q'], clock: clock, connect: connect);
    Future<void> wait(Duration time) async {
      for (var left = time; left > Duration.zero; left -= const Duration(milliseconds: 100)) {
        clock.advance(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    final opening = client.open(const CreateRoom(name: 'Ann', settings: RoomSettings(seats: 2)));
    await wait(const Duration(seconds: 1));
    expect((await opening).isHost, isTrue);
    expect(client.url, 'peer:K7M2Q');
    expect(client.status, OnlineStatus.open);

    refuseAll = true;
    await link.close();
    await wait(const Duration(seconds: 5));
    expect(client.status, OnlineStatus.reconnecting);
    refuseAll = false;
    await wait(const Duration(seconds: 10));
    expect(client.status, OnlineStatus.open, reason: 'tried again, and back');
    await client.close();
    await wait(const Duration(seconds: 15));
  });
}
