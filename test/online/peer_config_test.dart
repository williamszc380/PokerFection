import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/online/clock.dart';
import 'package:pokerfection/src/online/invite.dart';
import 'package:pokerfection/src/online/memory_link.dart';
import 'package:pokerfection/src/online/peer_config.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/server/room_registry.dart';

/// [invite] is room [code], with [servers] in that order.
void expectInvite(Invite? invite, String code, List<String> servers) {
  expect(invite?.code, code);
  expect(invite?.servers, servers);
}

void main() {
  test("a room's name at the meeting service is its code, in capitals; a guest's is random", () {
    expect(hostPeerId(' k7m2q '), 'pokerfection-v1-K7M2Q');
    expect(guestPeerId(Random(1)), matches(RegExp(r'^pokerfection-v1-guest-[a-z0-9]{16}$')));
    expect(guestPeerId(Random(1)), isNot(guestPeerId(Random(2))));
    expect(sessionToken(Random(1)), matches(RegExp(r'^[a-z0-9]{16}$')));
    // Every name passes the official PeerJS client's own check.
    final official = RegExp(r'^[A-Za-z0-9]+(?:[ _-][A-Za-z0-9]+)*$');
    expect([hostPeerId('K7M2Q'), guestPeerId()], everyElement(matches(official)));
  });

  test('a peer: entry names a room by its code; anything else is not one', () {
    expect(peerEntry(' k7m2q'), 'peer:K7M2Q');
    expect(parsePeerEntry('peer:K7M2Q'), 'K7M2Q');
    expect(parsePeerEntry(' PEER:k7m2q '), 'K7M2Q');
    expect(isPeerEntry('Peer:K7M2Q'), isTrue);
    for (final wrong in ['peer:', 'peer:K7M2', 'peer:K7M2QQ', 'peer:K7M20', 'peer:K7M2Q@elsewhere', 'ws://peer:1/ws']) {
      expect(parsePeerEntry(wrong), isNull, reason: wrong);
    }
    expect(isPeerEntry('ws://192.168.1.20:47474/ws'), isFalse);
    // The same letters as the server's codes.
    final random = Random(5);
    for (var i = 0; i < 200; i++) {
      expect(roomCodePattern.hasMatch(RoomRegistry.randomCode(random)), isTrue);
    }
  });

  test("the helpers: Google's and Cloudflare's STUN, no relay (and never PeerJS's dead ones)", () {
    expect(peerBroker, 'wss://0.peerjs.com/peerjs');
    expect(stunServers.map((s) => s.urls.single), ['stun:stun.l.google.com:19302', 'stun:stun.cloudflare.com:3478']);
    expect(turnServers, isEmpty);
    expect(iceServers.expand((s) => s.urls), everyElement(isNot(contains('peerjs.com'))));
    // The apps' WebRTC takes 8 server URLs at most (FlutterRtc.maxServerUrls).
    expect(iceServers.expand((s) => s.urls).length, lessThanOrEqualTo(8));
  });

  test('invites keep peer: entries whole and in their place; links read back the same', () {
    const local = 'ws://192.168.1.20:47474/ws';
    final link = inviteLink('K7M2Q', [local, 'peer:K7M2Q']);
    expect(link, 'pokerfection://join?code=K7M2Q&server=192.168.1.20%3A47474&server=peer%3AK7M2Q');
    expectInvite(parseInvite('Come play: $link'), 'K7M2Q', [local, 'peer:K7M2Q']);
    final site = siteInviteLink('K7M2Q', ['peer:K7M2Q', local]);
    expect(site, endsWith('join.html?code=K7M2Q&server=peer%3AK7M2Q&server=192.168.1.20%3A47474'));
    expectInvite(parseInvite(site), 'K7M2Q', ['peer:K7M2Q', local]);
    // As the web version reads its own address: in capitals, and a broken entry is dropped.
    expectInvite(
      inviteFromPage(Uri.parse('https://williamszc380.github.io/PokerFection/?code=k7m2q&server=peer%3Ak7m2q')),
      'K7M2Q',
      ['peer:K7M2Q'],
    );
    expectInvite(inviteFromUri(Uri.parse('/?code=K7M2Q&server=peer:nope&server=10.0.0.5:47474')), 'K7M2Q', [
      'ws://10.0.0.5:47474/ws',
    ]);
    expect(isThisComputer('peer:K7M2Q'), isFalse);
  });

  test('a host that took its code at the meeting service gets a room with that code; otherwise codes are random '
      'as before', () async {
    Future<String> create(RoomRegistry registry) async {
      final (server, device) = MemoryLink.pair();
      registry.accept(server);
      final welcome = device.messages.map(ServerMessage.decode).firstWhere((m) => m is Welcome);
      device.send(const CreateRoom(name: 'Ann', settings: RoomSettings(seats: 2)).encode());
      return ((await welcome) as Welcome).code;
    }

    String? wanted = 'K7M2Q';
    final hosted = RoomRegistry(clock: ManualClock(), random: Random(7), maxRooms: 2, nextCode: () => wanted);
    expect(await create(hosted), 'K7M2Q');
    // A code a room has already, or none: a random one.
    final second = await create(hosted);
    expect(second, isNot('K7M2Q'));
    expect(roomCodePattern.hasMatch(second), isTrue);
    wanted = null;
    final plain = RoomRegistry(clock: ManualClock(), random: Random(7));
    final hook = RoomRegistry(clock: ManualClock(), random: Random(7), nextCode: () => wanted);
    expect(await create(hook), await create(plain), reason: 'the same codes from the same dice');
  });
}
