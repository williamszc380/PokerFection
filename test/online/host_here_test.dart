import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/online/clock.dart';
import 'package:pokerfection/src/online/connect.dart';
import 'package:pokerfection/src/online/host_here.dart';
import 'package:pokerfection/src/online/invite.dart';
import 'package:pokerfection/src/online/online_client.dart';
import 'package:pokerfection/src/online/peer_config.dart';
import 'package:pokerfection/src/online/peer_host.dart';
import 'package:pokerfection/src/online/peer_socket.dart';
import 'package:pokerfection/src/online/protocol.dart';

import 'fake_peer.dart';

/// Hosting on this device for real (the game server inside the app), with
/// the internet faked: the meeting service and WebRTC are fake_peer.dart's.
/// The server listens on this computer only and the router is left alone,
/// so nothing is opened to the network.
void main() {
  test('Create Room on this device: the room gets the code taken at the meeting service, the host joins at its own '
      'server, a friend anywhere comes in through the meeting service, and stopping gives the code back', () async {
    final clock = SystemClock();
    final broker = FakeBroker(clock);
    final rtc = FakeRtc();
    final host = await hostHere(
      openRouter: false,
      loopbackOnly: true,
      peer: (accept) => PeerHost(
        accept: accept,
        rtc: rtc,
        connectSignaling: broker.connect,
        clock: clock,
        random: Random(4),
        pickCode: () => 'K7M2Q',
      ),
    );
    expect(host.internet, PeerStatus.ready);
    expect(host.peerCode, 'K7M2Q');
    expect(host.routerEndpoint, isNull, reason: 'the router was left alone');
    await host.routerSetup;

    final own = OnlineClient(host.ownServer, host: host);
    final welcome = await own.open(const CreateRoom(name: 'Ann'));
    expect(welcome.code, 'K7M2Q');
    expect(hostServers(host, 'K7M2Q'), [
      for (final address in host.localAddresses) 'ws://$address:${host.port}/ws',
      'peer:K7M2Q',
    ]);

    final guest = PeerConnector(rtc: rtc, connectSignaling: broker.connect, clock: clock, random: Random(20));
    final friend = OnlineClient('peer:K7M2Q', connect: (url) => connectAny(url, peer: guest));
    final seat = await friend.open(const JoinRoom(code: 'K7M2Q', name: 'Ben'));
    expect(seat.code, 'K7M2Q');

    // The host leaves: the room closes, the server stops, and the name is free again.
    await own.close();
    await host.stopped.timeout(const Duration(seconds: 5));
    expect(broker.holds(hostPeerId('K7M2Q')), isFalse);
    await friend.close(leave: false);
  });

  test("when someone else holds the code at the meeting service, the room gets another and invites don't name the "
      'meeting service (they would lead to the other room)', () async {
    final clock = SystemClock();
    final broker = FakeBroker(clock);
    await broker.connect('$peerBroker?id=${hostPeerId('K7M2Q')}&token=someoneelse');
    final host = await hostHere(
      openRouter: false,
      loopbackOnly: true,
      peer: (accept) => PeerHost(
        accept: accept,
        rtc: FakeRtc(),
        connectSignaling: broker.connect,
        clock: clock,
        random: Random(4),
        pickCode: () => 'K7M2Q',
      ),
    );
    expect(host.internet, const PeerStatus.unavailable(PeerTrouble.codeTaken));
    expect(host.peerCode, isNull);
    final own = OnlineClient(host.ownServer, host: host);
    final welcome = await own.open(const CreateRoom(name: 'Ann'));
    expect(welcome.code, isNot('K7M2Q'));
    expect(hostServers(host, welcome.code), isNot(contains(startsWith(peerScheme))));
    await own.close();
    await host.stopped.timeout(const Duration(seconds: 5));
  });

  test('stopping the host while its room is still open (the window closing while hosting) stops it once, with no '
      'error', () async {
    final clock = SystemClock();
    final broker = FakeBroker(clock);
    final host = await hostHere(
      openRouter: false,
      loopbackOnly: true,
      peer: (accept) => PeerHost(
        accept: accept,
        rtc: FakeRtc(),
        connectSignaling: broker.connect,
        clock: clock,
        random: Random(4),
        pickCode: () => 'K7M2Q',
      ),
    );
    final own = OnlineClient(host.ownServer, host: host);
    await own.open(const CreateRoom(name: 'Ann'));
    // As closing the app does: the room is open, and closing it calls stop again from inside.
    await expectLater(host.stop(), completes);
    await expectLater(host.stop(), completes);
    await host.stopped.timeout(const Duration(seconds: 5));
    expect(broker.holds(hostPeerId('K7M2Q')), isFalse, reason: 'the name was given back');
    await own.close(leave: false);
  });
}
