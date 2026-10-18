import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/online/channel_socket.dart';
import 'package:pokerfection/src/online/clock.dart';
import 'package:pokerfection/src/online/connect.dart';
import 'package:pokerfection/src/online/online_socket.dart';
import 'package:pokerfection/src/online/peer_config.dart';
import 'package:pokerfection/src/online/peer_host.dart';
import 'package:pokerfection/src/online/peer_socket.dart';
import 'package:pokerfection/src/online/rtc.dart';
import 'package:pokerfection/src/online/signaling.dart';
import 'package:pokerfection/src/server/client_link.dart';

import 'fake_peer.dart';

void main() {
  late ManualClock clock;
  late FakeBroker broker;
  late FakeRtc rtc;
  late List<ClientLink> links;
  late List<PeerHost> hosts;
  late List<PeerSignaling> others;

  setUp(() {
    clock = ManualClock();
    broker = FakeBroker(clock);
    rtc = FakeRtc();
    links = [];
    hosts = [];
    others = [];
  });

  tearDown(() async {
    for (final h in hosts) {
      await h.stop();
    }
    for (final s in others) {
      await s.close();
    }
  });

  PeerHost host({List<String>? codes, FakeRtc? using}) {
    final h = PeerHost(
      accept: links.add,
      rtc: using ?? rtc,
      connectSignaling: broker.connect,
      clock: clock,
      random: Random(1),
      pickCode: codes == null ? null : () => codes.removeAt(0),
    );
    hosts.add(h);
    return h;
  }

  PeerConnector guest(int seed) =>
      PeerConnector(rtc: rtc, connectSignaling: broker.connect, clock: clock, random: Random(seed));

  /// Moves time on by [time], a little at a time, letting everything that
  /// happens meanwhile run.
  Future<void> pass(Duration time) async {
    const step = Duration(milliseconds: 100);
    for (var left = time; left > Duration.zero; left -= step) {
      clock.advance(left < step ? left : step);
      await pumpEventQueue();
    }
  }

  /// [future]'s value, letting time pass ([within] at most) until it comes.
  Future<T> soon<T>(Future<T> future, {Duration within = const Duration(seconds: 30)}) async {
    var done = false;
    Object? error;
    late T value;
    unawaited(
      future.then(
        (v) {
          value = v;
          done = true;
        },
        onError: (Object e) {
          error = e;
          done = true;
        },
      ),
    );
    for (var waited = Duration.zero; !done; waited += const Duration(milliseconds: 100)) {
      if (waited > within) fail('Still waiting after $within');
      await pass(const Duration(milliseconds: 100));
    }
    if (error != null) throw error!;
    return value;
  }

  /// Someone else, holding [id] at the meeting service.
  Future<void> takeName(String id) async {
    final s = PeerSignaling(id, token: 'someone else', connect: broker.connect, clock: clock, reconnect: false);
    others.add(s);
    await s.open();
  }

  test("a host takes its room's name and is ready; each guest that connects comes to the room at its own address, "
      'and gives its name at the meeting service back 5 s later', () async {
    final h = host();
    final statuses = <PeerStatus>[];
    h.statuses.listen(statuses.add);
    final code = await soon(h.start());
    expect(code, matches(roomCodePattern));
    expect(h.status, PeerStatus.ready);
    expect(broker.holds(hostPeerId(code)), isTrue);
    final ann = guest(2), ben = guest(3);
    final OnlineSocket a = await soon(ann.connect(code)), b = await soon(ben.connect(code.toLowerCase()));
    expect(links, hasLength(2));
    expect(links[0].address, matches(RegExp(r'^peer:pokerfection-v1-guest-[a-z0-9]{16}$')));
    expect(links[1].address, isNot(links[0].address));
    final got = <String>[];
    links[0].messages.listen(got.add);
    a.send('{"t":"ping","n":1}');
    await pumpEventQueue();
    expect(got, ['{"t":"ping","n":1}']);
    expect(h.pendingCount, 0);
    expect(ann.hasSignaling, isTrue);
    await pass(const Duration(seconds: 5));
    expect(ann.hasSignaling || ben.hasSignaling, isFalse);
    expect(broker.closed, isEmpty, reason: 'every message was well shaped');
    await a.close();
    await b.close();
    expect(statuses, [PeerStatus.ready]);
  });

  test("a code whose name someone else holds: the host tries the next, up to 5 codes", () async {
    await takeName(hostPeerId('AAAAA'));
    await takeName(hostPeerId('BBBBB'));
    final h = host(codes: ['AAAAA', 'BBBBB', 'CCCCC']);
    expect(await soon(h.start()), 'CCCCC');
    expect(h.code, 'CCCCC');
    expect(h.status, PeerStatus.ready);
    for (final code in ['DDDDD', 'EEEEE', 'FFFFF', 'GGGGG', 'HHHHH']) {
      await takeName(hostPeerId(code));
    }
    final unlucky = host(codes: ['DDDDD', 'EEEEE', 'FFFFF', 'GGGGG', 'HHHHH', 'JJJJJ']);
    expect(await soon(unlucky.start()), 'HHHHH');
    expect(unlucky.status, const PeerStatus.unavailable(PeerTrouble.codeTaken));
  });

  test("the meeting service can't be reached: unavailable, and the host keeps trying until it is ready", () async {
    broker.reachable = false;
    final h = host();
    final code = await soon(h.start());
    expect(h.status, const PeerStatus.unavailable(PeerTrouble.unreachable));
    await pass(const Duration(seconds: 10));
    expect(h.status, const PeerStatus.unavailable(PeerTrouble.unreachable));
    broker.reachable = true;
    await pass(const Duration(seconds: 20));
    expect(h.status, PeerStatus.ready);
    expect(broker.holds(hostPeerId(code)), isTrue);
  });

  test('a slow meeting service: the room opens after 3 s anyway, and keeps its code whatever happens', () async {
    broker.answers = false;
    final h = host();
    String? code;
    unawaited(h.start().then((c) => code = c));
    await pass(const Duration(milliseconds: 2900));
    expect(code, isNull);
    await pass(const Duration(milliseconds: 200));
    expect(code, matches(roomCodePattern));
    expect(h.status, PeerStatus.starting);
    // No OPEN in 10 s: unavailable for now; then the service answers again.
    await pass(const Duration(seconds: 7));
    expect(h.status, const PeerStatus.unavailable(PeerTrouble.unreachable));
    broker.answers = true;
    await pass(const Duration(seconds: 20));
    expect(h.status, PeerStatus.ready);
    expect(h.code, code);
    expect(broker.holds(hostPeerId(code!)), isTrue);
  });

  test("the host's connection to the meeting service drops: it comes back with the room's name, and the guests "
      'in play never notice; a name taken meanwhile is lost', () async {
    final h = host();
    final statuses = <PeerStatus>[];
    h.statuses.listen(statuses.add);
    final code = await soon(h.start());
    final socket = await soon(guest(2).connect(code));
    final got = <String>[];
    links.single.messages.listen(got.add);
    broker.drop(hostPeerId(code));
    await pass(const Duration(seconds: 2));
    expect(statuses, [PeerStatus.ready, PeerStatus.starting, PeerStatus.ready]);
    socket.send('still here');
    await pass(const Duration(seconds: 10));
    expect(got, ['still here']);
    // A guest connects as before.
    await soon(guest(3).connect(code));
    expect(links, hasLength(2));
    // Dropped again, and the name is someone else's by the time the host comes back.
    broker.drop(hostPeerId(code));
    await pumpEventQueue();
    await takeName(hostPeerId(code));
    await pass(const Duration(seconds: 2));
    expect(h.status, const PeerStatus.unavailable(PeerTrouble.codeTaken));
    await pass(const Duration(seconds: 10));
    expect(got, ['still here'], reason: 'the guest in play plays on');
  });

  test("this version of the app can't make direct connections: hosting says so, joining fails at once", () async {
    final h = PeerHost(accept: links.add, connectSignaling: broker.connect, clock: clock);
    hosts.add(h);
    await h.start();
    expect(h.status, const PeerStatus.unavailable(PeerTrouble.unsupported));
    expect(broker.connects, isEmpty);
    final g = PeerConnector(connectSignaling: broker.connect, clock: clock);
    await expectLater(soon(g.connect('K7M2Q')), throwsUnsupportedError);
    expect(broker.connects, isEmpty);
    await expectLater(connectAny('peer:K7M2'), throwsArgumentError);
  });

  test('no such room: refused at once (nobody holds its name)', () async {
    await expectLater(
      soon(guest(2).connect('K7M2Q'), within: const Duration(seconds: 1)),
      throwsA(isA<ConnectionRefused>()),
    );
  });

  test('no way between the two devices: the guest hears so, and the host drops its side', () async {
    final h = host();
    final code = await soon(h.start());
    rtc.failIce = true;
    await expectLater(soon(guest(2).connect(code)), throwsA(isA<NoDirectRoute>()));
    await pumpEventQueue();
    expect(h.pendingCount, 0);
    expect(rtc.peers.map((p) => p.state), everyElement(RtcState.closed));
    expect(links, isEmpty);
  });

  test('a connection that never opens is given up after 20 s, at both ends', () async {
    final h = host();
    final code = await soon(h.start());
    rtc.stuck = true;
    final trying = guest(2).connect(code);
    Object? error;
    unawaited(trying.then((_) {}, onError: (Object e) => error = e));
    await pass(const Duration(seconds: 19));
    expect(error, isNull);
    expect(h.pendingCount, 1);
    await pass(const Duration(seconds: 2));
    expect(error, isA<NoDirectRoute>());
    expect(h.pendingCount, 0);
    expect(rtc.peers.map((p) => p.state), everyElement(RtcState.closed));
  });

  test('offer floods are capped: 4 at once from a guest, 30 a minute in all, only from this app; '
      'those not open after 20 s are closed', () async {
    final hostRtc = FakeRtc();
    final h = host(using: hostRtc);
    final code = await soon(h.start());
    final hostId = hostPeerId(code);
    Future<PeerSignaling> flooder(int n) async {
      final s = PeerSignaling(guestPeerId(Random(n)), connect: broker.connect, clock: clock, reconnect: false);
      others.add(s);
      await s.open();
      return s;
    }

    // Another app's offer, well shaped: not answered.
    final stranger = await broker.connect('wss://x/peerjs?key=peerjs&id=stranger&token=t');
    stranger.send(
      jsonEncode({
        'type': 'OFFER',
        'dst': hostId,
        'payload': {
          'sdp': {'type': 'offer', 'sdp': 'v=0\r\n'},
          'type': 'data',
          'connectionId': 'x',
          'label': 'x',
          'serialization': 'raw',
          'metadata': {'app': 'something else'},
        },
      }),
    );
    await pumpEventQueue();
    expect(hostRtc.peers, isEmpty);

    final first = await flooder(100);
    for (var i = 0; i < 10; i++) {
      await first.sendOffer(hostId, connectionId: 'c$i', sdp: 'v=0\r\na=fake:999\r\n');
    }
    await pumpEventQueue();
    expect(hostRtc.peers, hasLength(4));
    for (var g = 0; g < 10; g++) {
      final s = await flooder(g);
      for (var i = 0; i < 4; i++) {
        await s.sendOffer(hostId, connectionId: 'c$i', sdp: 'v=0\r\na=fake:999\r\n');
      }
    }
    await pumpEventQueue();
    expect(hostRtc.peers, hasLength(30));
    expect(h.pendingCount, 30);
    await pass(const Duration(seconds: 20));
    expect(h.pendingCount, 0);
    expect(hostRtc.peers.map((p) => p.state), everyElement(RtcState.closed));
    // A minute on, offers are taken again.
    await pass(const Duration(seconds: 40));
    await first.sendOffer(hostId, connectionId: 'later', sdp: 'v=0\r\na=fake:999\r\n');
    await pumpEventQueue();
    expect(hostRtc.peers, hasLength(31));
    expect(broker.closed, isEmpty);
  });
  test("made-up offers from someone who knows the code can use up the budget for new guests, but can't keep out a "
      "player coming back to their seat: that offer carries a pass made with the seat's token, and has a budget "
      'of its own. A pass made with any other token is no pass', () async {
    final h = PeerHost(
      accept: links.add,
      rtc: rtc,
      connectSignaling: broker.connect,
      clock: clock,
      random: Random(1),
      seatTokens: () => ['the seat token'],
    );
    hosts.add(h);
    final code = await soon(h.start());
    for (var g = 0; g < 8; g++) {
      final s = PeerSignaling(guestPeerId(Random(100 + g)), connect: broker.connect, clock: clock, reconnect: false);
      others.add(s);
      await s.open();
      for (var i = 0; i < 4; i++) {
        await s.sendOffer(hostPeerId(code), connectionId: 'c$i', sdp: 'v=0\r\na=fake:99999\r\n');
      }
    }
    await pumpEventQueue();
    expect(h.pendingCount, PeerHost.offersPerMinute);

    await expectLater(soon(guest(40).connect(code)), throwsA(isA<TimeoutException>()));
    await expectLater(soon(guest(41).connect(code, seat: 'made up')), throwsA(isA<TimeoutException>()));
    final back = await soon(guest(42).connect(code, seat: 'the seat token'));
    expect(links, hasLength(1));
    expect(
      broker.received.where((m) => m.contains('"pass"')).every((m) => !m.contains('the seat token')),
      isTrue,
      reason: 'the pass never names the token',
    );
    await back.close();
  });

  test("the host's connection to the meeting service blips while a guest connects: once the host has answered, "
      'the room is known to be there, so the guest keeps going and the connection opens', () async {
    final h = host();
    final code = await soon(h.start());
    rtc.stuck = true;
    Object? error;
    OnlineSocket? socket;
    unawaited(guest(2).connect(code).then((s) => socket = s, onError: (Object e) => error = e));
    await pass(const Duration(seconds: 1));
    expect(h.pendingCount, 1, reason: 'answered; the two devices look for a way to each other');
    final guestPeer = rtc.peers.first;
    broker.drop(hostPeerId(code));
    await pumpEventQueue();
    // A late candidate goes to the host's name while nobody holds it: EXPIRE.
    guestPeer.gatherMore();
    await pass(const Duration(milliseconds: 300));
    expect(broker.expires, [contains('about ${hostPeerId(code)}')]);
    expect(error, isNull);
    // The host is back with the room's name; the next candidate gets through, and a way is found.
    await pass(const Duration(seconds: 2));
    expect(h.status, PeerStatus.ready);
    rtc.stuck = false;
    guestPeer.gatherMore();
    await pass(const Duration(milliseconds: 300));
    expect(error, isNull);
    expect(socket, isNotNull);
    expect(links, hasLength(1));
    await socket!.close();
  });

  test("a guest's connection to the meeting service drops after the host answered: the host keeps setting the "
      'connection up (it may still open) until its 20 s are up', () async {
    final h = host();
    final code = await soon(h.start());
    rtc.stuck = true;
    Object? error;
    OnlineSocket? socket;
    unawaited(guest(2).connect(code).then((s) => socket = s, onError: (Object e) => error = e));
    await pass(const Duration(seconds: 1));
    expect(h.pendingCount, 1);
    final guestPeer = rtc.peers[0], hostPeer = rtc.peers[1];
    final guestId = broker.connects.lastWhere((c) => c.id.contains('guest')).id;
    broker.drop(guestId);
    await pumpEventQueue();
    // The host's late candidate goes to the guest's name, held by nobody now: EXPIRE.
    hostPeer.gatherMore();
    await pass(const Duration(milliseconds: 300));
    expect(broker.expires, ['${hostPeerId(code)} about $guestId']);
    expect(h.pendingCount, 1);
    expect(hostPeer.state, RtcState.connecting);
    // The guest's checks reach the host anyway (WebRTC learns an address from them): it opens.
    rtc.stuck = false;
    hostPeer.addRemoteCandidate(
      const RtcCandidate('candidate:9 1 udp 1853824767 203.0.113.9 6000 typ prflx', sdpMid: '0', sdpMLineIndex: 0),
    );
    expect(guestPeer.remoteCandidates, isNotEmpty, reason: "the guest had the host's first candidate");
    await pass(const Duration(milliseconds: 300));
    expect(error, isNull);
    expect(socket, isNotNull);
    expect(links, hasLength(1));
    expect(h.pendingCount, 0);
    await socket!.close();
  });

  test('a connection given up on after a dropped guest is still closed after 20 s', () async {
    final h = host();
    final code = await soon(h.start());
    rtc.stuck = true;
    Object? error;
    unawaited(guest(2).connect(code).then((_) {}, onError: (Object e) => error = e));
    await pass(const Duration(seconds: 1));
    broker.drop(broker.connects.lastWhere((c) => c.id.contains('guest')).id);
    await pumpEventQueue();
    rtc.peers[1].gatherMore();
    await pass(const Duration(seconds: 20));
    expect(error, isA<NoDirectRoute>());
    expect(h.pendingCount, 0);
    expect(rtc.peers.map((p) => p.state), everyElement(RtcState.closed));
  });

  test('candidate floods are capped: a connection being set up that gets over 50 candidates is given up', () async {
    final hostRtc = FakeRtc();
    final h = host(using: hostRtc);
    final code = await soon(h.start());
    final hostId = hostPeerId(code);
    final s = PeerSignaling(guestPeerId(Random(7)), connect: broker.connect, clock: clock, reconnect: false);
    others.add(s);
    await s.open();
    await s.sendOffer(hostId, connectionId: 'c1', sdp: 'v=0\r\na=fake:999\r\n');
    await pumpEventQueue();
    final peer = hostRtc.peers.single;
    for (var i = 0; i < 1000; i++) {
      s.sendCandidate(
        hostId,
        connectionId: 'c1',
        candidate: RtcCandidate(
          'candidate:$i 1 udp 2122260223 198.51.100.${i % 250} ${1000 + i} typ host',
          sdpMid: '0',
          sdpMLineIndex: 0,
        ),
      );
    }
    await pumpEventQueue();
    expect(peer.remoteCandidates.length, lessThanOrEqualTo(50));
    expect(peer.state, RtcState.closed);
    expect(h.pendingCount, 0);
    expect(broker.closed, isEmpty);
  });

  test("a connection the room can't take is closed at both ends, not left open to nobody", () async {
    final h = PeerHost(
      accept: (_) => throw StateError('the room has no place'),
      rtc: rtc,
      connectSignaling: broker.connect,
      clock: clock,
      random: Random(1),
    );
    hosts.add(h);
    final code = await soon(h.start());
    OnlineSocket? socket;
    unawaited(guest(2).connect(code).then((s) => socket = s, onError: (Object _) {}));
    await pass(const Duration(seconds: 1));
    expect(h.pendingCount, 0);
    expect(rtc.peers, hasLength(2));
    expect(rtc.peers.map((p) => p.state), everyElement(RtcState.closed));
    expect(socket == null || (socket! as ChannelSocket).isClosed, isTrue);
  });
}
