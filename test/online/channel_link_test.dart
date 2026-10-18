import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/online/channel_link.dart';
import 'package:pokerfection/src/online/clock.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/online/rtc.dart';
import 'package:pokerfection/src/server/websocket_link.dart';

import 'fake_peer.dart';

void main() {
  late ManualClock clock;
  late FakeRtc rtc;

  setUp(() {
    clock = ManualClock();
    rtc = FakeRtc();
  });

  /// Moves time on by [time], a little at a time, letting everything that
  /// happens meanwhile run.
  Future<void> pass(Duration time) async {
    const step = Duration(milliseconds: 100);
    for (var left = time; left > Duration.zero; left -= step) {
      clock.advance(left < step ? left : step);
      await pumpEventQueue();
    }
  }

  /// A guest's end (the app's socket) and the host's (the room's link) of a
  /// new direct connection, open.
  Future<(ChannelSocket guest, ChannelLink host, List<String> atGuest, List<String> atHost)> connect() async {
    final guestPeer = rtc.create() as FakeRtcPeer, hostPeer = rtc.create() as FakeRtcPeer;
    final offer = await guestPeer.offer();
    await guestPeer.acceptAnswer(await hostPeer.answer(offer));
    guestPeer.onLocalCandidate.listen(hostPeer.addRemoteCandidate);
    hostPeer.onLocalCandidate.listen(guestPeer.addRemoteCandidate);
    await pumpEventQueue();
    expect(guestPeer.state, RtcState.connected);
    final guest = ChannelSocket(guestPeer, await guestPeer.channel, clock: clock);
    final host = ChannelLink(hostPeer, await hostPeer.channel, address: 'peer:pokerfection-v1-guest-x', clock: clock);
    final atGuest = <String>[], atHost = <String>[];
    guest.messages.listen(atGuest.add);
    host.messages.listen(atHost.add);
    return (guest, host, atGuest, atHost);
  }

  test("game messages go both ways; the connection's own (it is there, bye) never reach the game", () async {
    final (guest, host, atGuest, atHost) = await connect();
    guest.send('{"t":"ping","n":1}');
    host.send('{"t":"pong","n":1}');
    await pass(const Duration(seconds: 30));
    expect(atHost, ['{"t":"ping","n":1}']);
    expect(atGuest, ['{"t":"pong","n":1}']);
    expect(guest.isClosed || host.isClosed, isFalse, reason: 'each end says it is there every 2 s');
    final hostChannel = (host.peer as FakeRtcPeer).channelEnd!;
    expect(hostChannel.sent.where((m) => m == ChannelSocket.pingFrame).length, 15);
    expect(host.address, 'peer:pokerfection-v1-guest-x');
  });

  test("the connection's own messages can't be taken for the game's: no game message type starts with _", () {
    expect(() => ClientMessage.decode(ChannelSocket.pingFrame), throwsA(isA<ProtocolError>()));
    expect(() => ServerMessage.decode(ChannelSocket.byeFrame), throwsA(isA<ProtocolError>()));
    final source = File('lib/src/online/protocol.dart').readAsStringSync();
    final types = [
      for (final m in RegExp(r"'t': '([^']*)'").allMatches(source)) m[1]!,
      for (final m in RegExp(r"^\s*'([^']*)' =>", multiLine: true).allMatches(source)) m[1]!,
    ];
    expect(types, hasLength(greaterThan(40)), reason: 'the walk finds the message types');
    expect(types.where((t) => t.startsWith('_')), isEmpty);
  });

  test('a message from a guest over 16 KB ends the connection, as over a WebSocket', () async {
    expect(ChannelLink.maxMessage, WebSocketLink.maxMessage);
    final (guest, host, _, atHost) = await connect();
    guest.send('x' * ChannelLink.maxMessage);
    await pumpEventQueue();
    expect(atHost.single, hasLength(ChannelLink.maxMessage));
    expect(host.isClosed, isFalse);
    guest.send('x' * (ChannelLink.maxMessage + 1));
    await pumpEventQueue();
    expect(host.isClosed, isTrue);
    expect(atHost, hasLength(1));
    expect(guest.isClosed, isTrue, reason: 'the channel closed');
    // The guest's end takes whatever the host sends.
    final (guest2, host2, atGuest2, _) = await connect();
    host2.send('y' * 100000);
    await pumpEventQueue();
    expect(atGuest2.single, hasLength(100000));
    expect(guest2.isClosed, isFalse);
  });

  test('a connection silent for 6 s has ended, at both ends', () async {
    final (guest, host, _, _) = await connect();
    (guest.peer as FakeRtcPeer).goSilent();
    await pass(const Duration(seconds: 5));
    expect(guest.isClosed || host.isClosed, isFalse);
    await pass(const Duration(seconds: 2));
    expect(guest.isClosed && host.isClosed, isTrue);
    expect([guest.peer.state, host.peer.state], [RtcState.closed, RtcState.closed]);
  });

  test("leaving says bye: the other end ends at once, though it never hears of the channel's close", () async {
    rtc.quietCloses = true;
    final (guest, host, _, _) = await connect();
    await guest.close();
    await pumpEventQueue();
    expect(host.isClosed, isTrue);
    expect((guest.peer as FakeRtcPeer).channelEnd!.sent.last, ChannelSocket.byeFrame);
    // Without the bye, the other end only finds out from the silence.
    final (guest2, host2, _, _) = await connect();
    await (host2.peer as FakeRtcPeer).dropChannel();
    await pumpEventQueue();
    expect(host2.isClosed, isTrue);
    expect(guest2.isClosed, isFalse);
    await pass(const Duration(seconds: 7));
    expect(guest2.isClosed, isTrue);
  });

  test('the channel closing ends the connection at both ends', () async {
    final (guest, host, _, _) = await connect();
    await (guest.peer as FakeRtcPeer).dropChannel();
    await pumpEventQueue();
    expect(guest.isClosed && host.isClosed, isTrue);
  });

  test('a connection disconnected for 5 s has ended (back sooner, it goes on); one that failed ends at once', () async {
    final (guest, host, _, _) = await connect();
    final peer = host.peer as FakeRtcPeer;
    peer.becomes(RtcState.disconnected);
    await pass(const Duration(seconds: 4));
    peer.becomes(RtcState.connected);
    await pass(const Duration(seconds: 4));
    expect(host.isClosed, isFalse);
    peer.becomes(RtcState.disconnected);
    await pass(const Duration(milliseconds: 4900));
    expect(host.isClosed, isFalse);
    await pass(const Duration(milliseconds: 200));
    expect(host.isClosed, isTrue);
    expect(guest.isClosed, isTrue, reason: 'the channel closed with it');
    final (_, host2, _, _) = await connect();
    (host2.peer as FakeRtcPeer).becomes(RtcState.failed);
    await pumpEventQueue();
    expect(host2.isClosed, isTrue);
  });
  test("a peer connection whose states can't be watched (onState must be shared: a broadcast stream): the "
      'socket fails at once and leaves nothing behind that fails later', () async {
    final guestPeer = rtc.create() as FakeRtcPeer, hostPeer = rtc.create() as FakeRtcPeer;
    await guestPeer.acceptAnswer(await hostPeer.answer(await guestPeer.offer()));
    guestPeer.onLocalCandidate.listen(hostPeer.addRemoteCandidate);
    hostPeer.onLocalCandidate.listen(guestPeer.addRemoteCandidate);
    await pumpEventQueue();
    final channel = await guestPeer.channel;
    expect(() => ChannelSocket(_WatchedAlready(guestPeer), channel, clock: clock), throwsStateError);
    // The channel closes later (from the other end): nothing of the socket that wasn't made may run then.
    await hostPeer.close();
    await pass(const Duration(seconds: 10));
    expect(channel.isOpen, isFalse);
  });
}

/// A peer connection whose [onState] someone else already listens to, as a
/// single-subscription stream (which the interface doesn't allow).
class _WatchedAlready implements RtcPeer {
  _WatchedAlready(this._peer) {
    _states.stream.listen((_) {});
  }

  final RtcPeer _peer;
  final StreamController<RtcState> _states = StreamController();

  @override
  Stream<RtcState> get onState => _states.stream;

  @override
  RtcState get state => _peer.state;

  @override
  Future<String> offer() => _peer.offer();

  @override
  Future<String> answer(String offerSdp) => _peer.answer(offerSdp);

  @override
  Future<void> acceptAnswer(String answerSdp) => _peer.acceptAnswer(answerSdp);

  @override
  void addRemoteCandidate(RtcCandidate candidate) => _peer.addRemoteCandidate(candidate);

  @override
  Stream<RtcCandidate> get onLocalCandidate => _peer.onLocalCandidate;

  @override
  Future<RtcChannel> get channel => _peer.channel;

  @override
  Future<void> close() => _peer.close();
}
