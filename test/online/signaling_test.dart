import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/online/clock.dart';
import 'package:pokerfection/src/online/online_socket.dart';
import 'package:pokerfection/src/online/peer_config.dart';
import 'package:pokerfection/src/online/protocol.dart' show protocolVersion;
import 'package:pokerfection/src/online/rtc.dart';
import 'package:pokerfection/src/online/signaling.dart';

import 'fake_peer.dart';

void main() {
  late ManualClock clock;
  late FakeBroker broker;
  late List<PeerSignaling> made;

  setUp(() {
    clock = ManualClock();
    broker = FakeBroker(clock);
    made = [];
  });

  tearDown(() async {
    for (final s in made) {
      await s.close();
    }
  });

  PeerSignaling signaling(String id, {String? token, bool watch = false, bool reconnect = true, int seed = 1}) {
    final s = PeerSignaling(
      id,
      token: token,
      connect: broker.connect,
      clock: clock,
      random: Random(seed),
      watch: watch,
      reconnect: reconnect,
    );
    made.add(s);
    return s;
  }

  /// Moves time on by [time], a little at a time, letting everything that
  /// happens meanwhile run.
  Future<void> pass(Duration time, {Duration step = const Duration(milliseconds: 100)}) async {
    var left = time;
    while (left > Duration.zero) {
      final now = left < step ? left : step;
      clock.advance(now);
      left -= now;
      await pumpEventQueue();
    }
  }

  /// Opens a raw connection to the broker, as some other client would.
  Future<(OnlineSocket, List<String>)> raw(String id, {String token = 'tok'}) async {
    final socket = await broker.connect('wss://broker/peerjs?key=peerjs&id=$id&token=$token');
    final got = <String>[];
    socket.messages.listen(got.add);
    await pumpEventQueue();
    // Only what comes after OPEN counts.
    got.remove('{"type":"OPEN"}');
    return (socket, got);
  }

  test("taking a name: the official client's address, then OPEN", () async {
    final s = signaling(hostPeerId(' k7m2q '), token: 'abcdefghijklmnop');
    expect(s.url, 'wss://0.peerjs.com/peerjs?key=peerjs&id=pokerfection-v1-K7M2Q&token=abcdefghijklmnop&version=1.5.5');
    final events = <SignalEvent>[];
    s.events.listen(events.add);
    await s.open();
    await pumpEventQueue();
    expect(s.isOpen, isTrue);
    expect(broker.holds('pokerfection-v1-K7M2Q'), isTrue);
    expect(events.single, isA<SignalOpen>().having((e) => e.reconnected, 'reconnected', false));
    // A guest's name and token: random letters and digits.
    expect(guestPeerId(Random(1)), matches(RegExp(r'^pokerfection-v1-guest-[a-z0-9]{16}$')));
    expect(sessionToken(Random(1)), matches(RegExp(r'^[a-z0-9]{16}$')));
  });

  test('a name someone else holds: ID-TAKEN, and that connection is closed; given back, it is free at once', () async {
    final first = signaling('pokerfection-v1-ABCDE', token: 'one');
    await first.open();
    final second = signaling('pokerfection-v1-ABCDE', token: 'two');
    await expectLater(second.open(), throwsA(isA<PeerIdTaken>()));
    expect(broker.closed, ['pokerfection-v1-ABCDE: ID-TAKEN']);
    expect(first.isOpen, isTrue, reason: 'the holder keeps it');
    await first.close();
    await pumpEventQueue();
    await second.open();
    expect(second.isOpen, isTrue);
  });

  test('no OPEN within 10 s counts as a failure', () async {
    broker.answers = false;
    final s = signaling('pokerfection-v1-ABCDE');
    Object? error;
    unawaited(s.open().catchError((Object e) => error = e));
    await pass(const Duration(seconds: 9));
    expect(error, isNull);
    await pass(const Duration(seconds: 2));
    expect(error, isA<SignalingUnavailable>());
    broker.reachable = false;
    await expectLater(signaling('pokerfection-v1-FGHJK').open(), throwsA(isA<SignalingUnavailable>()));
  });

  test('offers, answers and candidates go through in the official shapes, from the real sender', () async {
    final host = signaling(hostPeerId('ABCDE')), guest = signaling(guestPeerId(Random(2)));
    await host.open();
    await guest.open();
    final atHost = <SignalEvent>[], atGuest = <SignalEvent>[];
    host.events.listen(atHost.add);
    guest.events.listen(atGuest.add);
    expect(await guest.sendOffer(host.id, connectionId: 'dc_1', sdp: 'v=0\r\na=offer\r\n'), isTrue);
    expect(guest.sendCandidate(host.id, connectionId: 'dc_1', candidate: const RtcCandidate('candidate:1 typ host')), isTrue);
    await pumpEventQueue();
    final offer = atHost[0] as SignalOffer;
    expect([offer.from, offer.connectionId, offer.sdp], [guest.id, 'dc_1', 'v=0\r\na=offer\r\n']);
    expect(offer.metadata, {'app': 'pokerfection', 'v': 1, 'proto': protocolVersion});
    final candidate = atHost[1] as SignalCandidate;
    // A candidate without its media section goes with the data channel's: browsers need it.
    expect(candidate.candidate, const RtcCandidate('candidate:1 typ host', sdpMid: '0', sdpMLineIndex: 0));
    expect(host.sendAnswer(guest.id, connectionId: 'dc_1', sdp: 'v=0\r\na=answer\r\n'), isTrue);
    await pumpEventQueue();
    final answer = atGuest.single as SignalAnswer;
    expect([answer.from, answer.connectionId, answer.sdp], [host.id, 'dc_1', 'v=0\r\na=answer\r\n']);
    expect(broker.closed, isEmpty, reason: 'every message was well shaped');
    // Never anything over 16 KB (the server closes the sender over 20,000 bytes).
    expect(host.sendAnswer(guest.id, connectionId: 'dc_1', sdp: 'v=0\r\n${'a=x\r\n' * 4000}'), isFalse);
    await pumpEventQueue();
    expect(host.isOpen, isTrue);
  });

  test('the server closes anyone who sends anything but well-shaped messages, or over 20,000 bytes', () async {
    final (_, got) = await raw('target');
    final candidate = {
      'type': 'CANDIDATE',
      'dst': 'target',
      'payload': {
        'candidate': {'candidate': 'c', 'sdpMid': '0', 'sdpMLineIndex': 0},
        'type': 'data',
        'connectionId': 'x',
      },
    };
    final wrong = <String, Object>{
      'not JSON': 'hello',
      'an array': '[1]',
      'a LEAVE': '{"type":"LEAVE","dst":"target"}',
      'an EXPIRE': '{"type":"EXPIRE","dst":"target"}',
      'our own type': '{"type":"PING","dst":"target"}',
      'a candidate as a string': jsonEncode({
        ...candidate,
        'payload': {'candidate': 'c', 'type': 'data', 'connectionId': 'x'},
      }),
      'no connection id': jsonEncode({
        ...candidate,
        'payload': {
          'candidate': {'candidate': 'c'},
          'type': 'data',
        },
      }),
      'an offer without a label': jsonEncode({
        'type': 'OFFER',
        'dst': 'target',
        'payload': {
          'sdp': {'type': 'offer', 'sdp': 'v=0\r\n'},
          'type': 'data',
          'connectionId': 'x',
          'serialization': 'raw',
        },
      }),
      'an offer that is no SDP': jsonEncode({
        'type': 'OFFER',
        'dst': 'target',
        'payload': {
          'sdp': {'type': 'offer', 'sdp': 'hello'},
          'type': 'data',
          'connectionId': 'x',
          'label': 'x',
          'serialization': 'raw',
        },
      }),
      'over 20,000 bytes': jsonEncode({
        ...candidate,
        'pad': 'x' * (20001 - jsonEncode({...candidate, 'pad': ''}).length),
      }),
    };
    for (final MapEntry(key: why, value: text) in wrong.entries) {
      final (sender, _) = await raw('sender', token: why);
      sender.send(text as String);
      await pumpEventQueue();
      expect(broker.holds('sender'), isFalse, reason: why);
    }
    expect(got, isEmpty, reason: 'nothing was passed on');
    // Exactly 20,000 bytes still goes.
    final (sender, _) = await raw('sender', token: 'fine');
    final exact = jsonEncode({...candidate, 'pad': 'x' * (20000 - jsonEncode({...candidate, 'pad': ''}).length)});
    expect(utf8.encode(exact).length, 20000);
    sender.send(exact);
    await pumpEventQueue();
    expect(broker.holds('sender'), isTrue);
    expect(got, hasLength(1));
    expect(jsonDecode(got.single), containsPair('src', 'sender'));
  });

  test('a message to a name nobody holds comes back as EXPIRE at once, at most once each 3 s: '
      'an offer to it waits 3.5 s', () async {
    final guest = signaling(guestPeerId(Random(3)));
    await guest.open();
    final expired = <int>[];
    guest.events.listen((e) {
      if (e is SignalExpire && e.peer == hostPeerId('ABCDE')) expired.add(clock.nowMs);
    });
    await guest.sendOffer(hostPeerId('ABCDE'), connectionId: 'a', sdp: 'v=0\r\n');
    await pumpEventQueue();
    expect(expired, [0]);
    // Sent at once, a second message gets no EXPIRE (the server's rule)...
    guest.sendCandidate(hostPeerId('ABCDE'), connectionId: 'a', candidate: const RtcCandidate('c'));
    await pass(const Duration(seconds: 1));
    expect(expired, [0]);
    // ...so the next offer waits until 3.5 s after the last EXPIRE, and gets its own.
    final sent = guest.sendOffer(hostPeerId('ABCDE'), connectionId: 'b', sdp: 'v=0\r\n');
    await pass(const Duration(seconds: 3));
    expect(await sent, isTrue);
    expect(expired, [0, 3500]);
    expect(broker.closed, isEmpty);
  });

  test('a heartbeat every 20 s keeps the connection; one that says nothing is cut at 99 s', () async {
    final s = signaling(hostPeerId('ABCDE'));
    await s.open();
    final (_, _) = await raw('quiet');
    await pass(const Duration(seconds: 98));
    expect(broker.holds('quiet'), isTrue);
    await pass(const Duration(seconds: 2));
    expect(broker.holds('quiet'), isFalse);
    expect(broker.closed, ['quiet: idle']);
    await pass(const Duration(seconds: 200));
    expect(s.isOpen, isTrue);
    expect(broker.count(s.id, 'HEARTBEAT'), 15, reason: 'one each 20 s for 300 s');
  });

  test("the host checks its connection every 60 s with a candidate to itself; when it doesn't come back within "
      '8 s, it connects again with the same name and token, taking the name over', () async {
    final s = signaling(hostPeerId('ABCDE'), token: 'secret', watch: true);
    final events = <SignalEvent>[];
    s.events.listen(events.add);
    await s.open();
    await pass(const Duration(seconds: 121));
    expect(broker.count(s.id, 'CANDIDATE'), 2);
    expect(events.whereType<SignalClosed>(), isEmpty, reason: 'both checks came back');
    // The connection dies without anyone hearing of it: the next check gets no answer.
    broker.deafen(s.id);
    await pass(const Duration(seconds: 66));
    expect(events.whereType<SignalClosed>(), isEmpty);
    await pass(const Duration(seconds: 2));
    expect(events.whereType<SignalClosed>(), hasLength(1));
    // Back about a second later with the same token: the server gives a fresh OPEN and closes the dead one.
    await pass(const Duration(milliseconds: 1300));
    expect(events.last, isA<SignalOpen>().having((e) => e.reconnected, 'reconnected', true));
    expect(broker.closed, ['${s.id}: taken over']);
    expect(broker.connects.map((c) => c.id), [s.id, s.id]);
    // On demand too (the app is back on screen): answered, nothing happens.
    s.probe();
    await pass(const Duration(seconds: 9));
    expect(events.whereType<SignalClosed>(), hasLength(1));
  });

  test('a dropped connection comes back with the same name and token after 1, 2, 4, 8, 15, 15 s, '
      'give or take a fifth', () async {
    final s = signaling(hostPeerId('ABCDE'), token: 'secret', seed: 9);
    final events = <SignalEvent>[];
    s.events.listen(events.add);
    await s.open();
    broker.reachable = false;
    broker.drop(s.id);
    await pumpEventQueue();
    expect(events.last, isA<SignalClosed>().having((e) => e.reconnecting, 'reconnecting', true));
    final tries = <int>[];
    var at = clock.nowMs;
    for (final wait in [1, 2, 4, 8, 15, 15]) {
      final retried = events.whereType<SignalRetrying>().length;
      for (var i = 0; events.whereType<SignalRetrying>().length == retried; i++) {
        expect(i, lessThan(400));
        await pass(const Duration(milliseconds: 50), step: const Duration(milliseconds: 50));
      }
      final gap = clock.nowMs - at;
      at = clock.nowMs;
      tries.add(gap);
      expect(gap, inInclusiveRange(wait * 800, wait * 1200 + 50), reason: 'wait $wait s');
    }
    expect(tries.toSet(), hasLength(greaterThan(3)), reason: 'the waits vary a little');
    broker.reachable = true;
    await pass(const Duration(seconds: 20));
    expect(s.isOpen, isTrue);
    expect(events.last, isA<SignalOpen>().having((e) => e.reconnected, 'reconnected', true));
  });

  test('coming back, a name someone else took meanwhile is lost: no more tries', () async {
    final s = signaling(hostPeerId('ABCDE'), token: 'secret');
    final events = <SignalEvent>[];
    s.events.listen(events.add);
    await s.open();
    broker.drop(s.id);
    await pumpEventQueue();
    final (_, _) = await raw(hostPeerId('ABCDE'), token: 'someone else');
    await pass(const Duration(seconds: 2));
    expect(events.last, isA<SignalIdTaken>());
    expect(s.idTaken, isTrue);
    final tries = broker.connects.length;
    await pass(const Duration(seconds: 60));
    expect(broker.connects.length, tries);
  });

  test('a guest that needs no reconnecting just reports the drop', () async {
    final s = signaling(guestPeerId(Random(4)), reconnect: false);
    final events = <SignalEvent>[];
    s.events.listen(events.add);
    await s.open();
    broker.drop(s.id);
    await pass(const Duration(seconds: 30));
    expect(events.last, isA<SignalClosed>().having((e) => e.reconnecting, 'reconnecting', false));
    expect(broker.connects, hasLength(1));
  });
}
