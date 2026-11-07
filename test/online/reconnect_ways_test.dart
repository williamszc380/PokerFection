import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/online/channel_socket.dart';
import 'package:pokerfection/src/online/invite.dart';
import 'package:pokerfection/src/online/online_client.dart';
import 'package:pokerfection/src/online/online_socket.dart';
import 'package:pokerfection/src/online/peer_config.dart';
import 'package:pokerfection/src/online/peer_host.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/online/signaling.dart';
import 'package:pokerfection/src/server/client_link.dart';
import 'package:pokerfection/src/ui/online/room_scope.dart';

import '../widget_test.dart' show setScreen;
import 'fake_peer.dart';
import 'fake_room_host.dart';
import 'room_app.dart';

/// Getting a dropped connection back by every way to the room, and what
/// the player is told when none works; and why coming back through the
/// meeting service is safe even when someone else holds the room's name
/// there. On the fakes of fake_peer.dart: no real network.

final _en = S.forLanguage(AppLanguage.english);

/// Lets time pass (the widgets' and the fakes') until [done].
Future<void> _until(WidgetTester tester, FakeInternet net, bool Function() done, String what, {int limit = 600}) async {
  for (var i = 0; !done(); i++) {
    expect(i, lessThan(limit), reason: 'never: $what');
    net.clock.advance(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Lets [time] pass, for the widgets and the fakes.
Future<void> _wait(WidgetTester tester, FakeInternet net, Duration time) async {
  for (var left = time; left > Duration.zero; left -= const Duration(milliseconds: 100)) {
    net.clock.advance(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A room hosted on another device (as [code] when it can take it at the
/// meeting service), with its host's app in it.
Future<(TestRoomHost, OnlineClient, String)> _hostElsewhere(
  WidgetTester tester,
  FakeInternet net, {
  String code = 'K7M2Q',
}) async {
  TestRoomHost? started;
  unawaited(TestRoomHost.start(net, code: code).then((h) => started = h));
  await _until(tester, net, () => started != null, 'the code taken');
  final host = started!;
  final own = OnlineClient(host.ownServer, host: host, connect: host.connector(), clock: net.clock);
  Welcome? welcome;
  unawaited(own.open(const CreateRoom(name: 'Ann')).then((w) => welcome = w));
  await _until(tester, net, () => welcome != null, 'the room created');
  return (host, own, welcome!.code);
}

/// A friend's app, joining with [servers] in order; [latest] is its
/// connection now (to drop it).
class _Friend {
  _Friend(TestRoomHost host, FakeInternet net, List<String> servers, {bool nearby = true}) {
    final connect = host.connector(nearby: nearby, guest: net.guest(30));
    client = OnlineClient(
      servers.first,
      alsoTry: servers.skip(1).toList(),
      clock: net.clock,
      random: Random(2),
      onRecord: records.add,
      connect: (url) async {
        tried.add(url);
        return latest = await connect(url);
      },
    );
  }

  late final OnlineClient client;
  final List<String> tried = [];
  final List<RejoinRecord?> records = [];
  OnlineSocket? latest;

  /// The fake peer connection under [latest], a direct connection.
  FakeRtcPeer get peer => (latest! as ChannelSocket).peer as FakeRtcPeer;

  Future<Welcome> join(WidgetTester tester, FakeInternet net, String code) async {
    Welcome? welcome;
    unawaited(client.open(JoinRoom(code: code, name: 'Ben')).then((w) => welcome = w));
    await _until(tester, net, () => welcome != null, 'the friend in');
    return welcome!;
  }
}

/// Leaves everything, and lets it finish.
Future<void> _end(WidgetTester tester, FakeInternet net, List<OnlineClient> clients) async {
  await tester.pumpWidget(const SizedBox());
  for (final c in clients) {
    unawaited(c.close());
  }
  await _wait(tester, net, const Duration(seconds: 5));
}

void main() {
  testWidgets("a guest who came in on the host's Wi-Fi and then left it (mobile data now) gets the seat back through "
      'the meeting service, proving the seat without naming its token; the record to come back after a restart '
      'names that way too', (tester) async {
    final net = FakeInternet();
    final (host, own, code) = await _hostElsewhere(tester, net);
    final ben = _Friend(host, net, ['ws://192.168.1.20:47474/ws', 'peer:K7M2Q']);
    final welcome = await ben.join(tester, net, code);
    expect(welcome.peer, isTrue, reason: "the host holds the room's name at the meeting service");
    expect(ben.client.url, 'ws://192.168.1.20:47474/ws');
    expect(ben.records.last!.server, 'ws://192.168.1.20:47474/ws');
    expect(ben.records.last!.alsoTry, ['peer:K7M2Q']);
    expect(RejoinRecord.fromJson(ben.records.last!.toJson())!.alsoTry, ['peer:K7M2Q']);

    // The phone leaves the Wi-Fi: its connection drops, and the host's Wi-Fi address can't be reached any more.
    host.wifi = false;
    ben.tried.clear();
    await ben.latest!.close();
    await _until(tester, net, () => ben.client.status == OnlineStatus.reconnecting, 'the drop noticed');
    await _until(tester, net, () => ben.client.status == OnlineStatus.open, 'back in');
    expect(ben.client.url, 'peer:K7M2Q');
    expect(ben.tried, containsAllInOrder(['ws://192.168.1.20:47474/ws', 'peer:K7M2Q']));
    expect(host.registry.room(code)!.connectedCount, 2);
    final rejoin = ben.peer.channelEnd!.sent.firstWhere((m) => m.contains('"t":"rejoin"'));
    expect(rejoin, contains('"proof"'));
    expect(rejoin, isNot(contains(welcome.token)));
    await _end(tester, net, [ben.client, own]);
  });

  testWidgets("a guest of a room that can't be reached through the meeting service never goes there to come back, "
      "and its invite doesn't name it (the room's name there could be anyone's)", (tester) async {
    final net = FakeInternet();
    // Someone else holds K7M2Q: the room gets another code, and its host holds no name at the meeting service.
    await net.broker.connect('$peerBroker?id=${hostPeerId('K7M2Q')}&token=someoneelse');
    final (host, own, code) = await _hostElsewhere(tester, net);
    expect(code, isNot('K7M2Q'));
    final ben = _Friend(host, net, ['ws://192.168.1.20:47474/ws']);
    final welcome = await ben.join(tester, net, code);
    expect(welcome.peer, isFalse);
    expect(guestServers(ben.client.url, code, peer: ben.client.atMeetingService), ['ws://192.168.1.20:47474/ws']);

    host.wifi = false;
    ben.tried.clear();
    await ben.latest!.close();
    await _wait(tester, net, const Duration(seconds: 30));
    expect(ben.client.status, OnlineStatus.reconnecting);
    expect(ben.tried, isNotEmpty);
    expect(ben.tried, everyElement('ws://192.168.1.20:47474/ws'));
    await _end(tester, net, [ben.client, own]);
  });

  testWidgets("coming back from a network that can't reach the host directly ends with what to try instead, not "
      'just "Connection lost"', (tester) async {
    final net = FakeInternet();
    final (host, own, code) = await _hostElsewhere(tester, net);
    final ben = _Friend(host, net, ['peer:K7M2Q'], nearby: false);
    await ben.join(tester, net, code);
    // The room docked beside the screen (a wide window), with why it ended once it has.
    setScreen(tester, const Size(1280, 800));
    await tester.pumpWidget(roomApp(const SizedBox(), rooms: RoomService(settings: AppSettings())..enter(ben.client)));

    // The phone moves to a network where no way between the two devices is found.
    net.rtc.failIce = true;
    await ben.peer.dropChannel();
    await _until(tester, net, () => ben.client.status == OnlineStatus.lost, 'given up', limit: 2500);
    expect(ben.client.noDirectRoute, isTrue);
    await tester.pump();
    expect(find.text(_en.noDirectRoute), findsOneWidget);
    expect(find.text(_en.connectionLost), findsNothing);
    await _end(tester, net, [ben.client, own]);
  });

  testWidgets('a host flooded with made-up offers by someone who knows the code still lets a seated guest back in: '
      "the guest's offer carries a pass made with its seat's token (never the token itself)", (tester) async {
    final net = FakeInternet();
    final (host, own, code) = await _hostElsewhere(tester, net);
    // The app's own way through the meeting service (no test connect function), on the fakes.
    final ben = OnlineClient('peer:K7M2Q', peer: net.guest(31), clock: net.clock, random: Random(2));
    Welcome? welcome;
    unawaited(ben.open(JoinRoom(code: code, name: 'Ben')).then((w) => welcome = w));
    await _until(tester, net, () => welcome != null, 'Ben in');
    final bensConnection = net.rtc.peers.last;

    final flooders = <PeerSignaling>[];
    for (var g = 0; g < 8; g++) {
      final s = PeerSignaling(
        guestPeerId(Random(100 + g)),
        connect: net.broker.connect,
        clock: net.clock,
        reconnect: false,
      );
      flooders.add(s);
      await s.open();
      for (var i = 0; i < 4; i++) {
        await s.sendOffer(hostPeerId(code), connectionId: 'c$i', sdp: 'v=0\r\na=fake:99999\r\n');
      }
    }
    await tester.pump();
    expect(
      host.peer.pendingCount,
      PeerHost.offersPerMinute - 1,
      reason: "with Ben's first offer, new guests' budget is used up",
    );

    await bensConnection.dropChannel();
    await _until(tester, net, () => ben.status == OnlineStatus.reconnecting, 'the drop noticed');
    await _until(tester, net, () => ben.status == OnlineStatus.open, 'Ben back in');
    final passes = net.broker.received.where((m) => m.contains('"type":"OFFER"') && m.contains('"pass"'));
    expect(passes, isNotEmpty);
    expect(passes.where((m) => m.contains(welcome!.token)), isEmpty);
    expect(host.registry.room(code)!.connectedCount, 2);
    for (final s in flooders) {
      await s.close();
    }
    await _end(tester, net, [ben, own]);
  });

  testWidgets("someone who takes the room's name at the meeting service while the host's connection there is being "
      'made again learns no seat token: a guest coming back through it proves its seat for that connection only, '
      'which is no good at the real host. The host takes its name back once it is free, and the guest gets back in', (
    tester,
  ) async {
    final net = FakeInternet();
    final (host, own, code) = await _hostElsewhere(tester, net);
    final ben = _Friend(host, net, ['peer:K7M2Q'], nearby: false);
    final welcome = await ben.join(tester, net, code);

    // The host's connection to the meeting service drops, and someone who knows the code takes the name at once.
    final caught = <ClientLink>[];
    net.broker.drop(hostPeerId('K7M2Q'));
    final impostor = PeerHost(
      accept: caught.add,
      rtc: net.rtc,
      connectSignaling: net.broker.connect,
      clock: net.clock,
      random: Random(9),
      pickCode: () => 'K7M2Q',
    );
    String? taken;
    unawaited(impostor.start().then((c) => taken = c));
    await _until(tester, net, () => taken != null, 'the name taken');
    expect(impostor.status, PeerStatus.ready);
    await _until(
      tester,
      net,
      () => host.internet == const PeerStatus.unavailable(PeerTrouble.codeTaken),
      'the host finds its name taken',
    );

    // The guest's connection drops: coming back through the meeting service, it reaches the impostor.
    await ben.peer.dropChannel();
    await _until(tester, net, () => caught.isNotEmpty, 'the guest at the impostor');
    final heard = <String>[];
    caught.first.messages.listen(heard.add);
    await _until(tester, net, () => heard.any((m) => m.contains('"t":"rejoin"')), 'the rejoin');
    final rejoin = heard.firstWhere((m) => m.contains('"t":"rejoin"'));
    expect(rejoin, contains('"proof"'));
    expect(rejoin, isNot(contains(welcome.token)));

    // Replayed at the real host (over its Wi-Fi), that proof gets no seat.
    final replay = host.connectNearby();
    final answer = replay.messages.first;
    replay.send(rejoin);
    expect(ServerMessage.decode(await answer), isA<ServerError>().having((e) => e.code, 'code', JoinError.seatGone));

    // The impostor goes: the host takes its name back, and the guest gets back in, to the real room.
    await impostor.stop();
    await _until(tester, net, () => host.internet == PeerStatus.ready, 'the name back', limit: 400);
    await _until(tester, net, () => ben.client.status == OnlineStatus.open, 'the guest back in', limit: 1500);
    expect(host.registry.room(code)!.connectedCount, 2);
    await _end(tester, net, [ben.client, own]);
  });
}
