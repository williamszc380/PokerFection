import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/online/clock.dart';
import 'package:pokerfection/src/online/connect.dart';
import 'package:pokerfection/src/online/in_process_host.dart';
import 'package:pokerfection/src/online/invite.dart';
import 'package:pokerfection/src/online/memory_link.dart';
import 'package:pokerfection/src/online/online_client.dart';
import 'package:pokerfection/src/online/peer_config.dart';
import 'package:pokerfection/src/online/peer_host.dart';
import 'package:pokerfection/src/online/peer_socket.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/ui/online/online_screen.dart';
import 'package:pokerfection/src/ui/online/room_panel.dart';
import 'package:pokerfection/src/ui/online/room_scope.dart';

import '../widget_test.dart' show setScreen;
import 'fake_peer.dart';
import 'fake_room_host.dart';
import 'room_app.dart';

/// Hosting and joining from the web version: a browser hosts the room in
/// the page (InProcessHost), with everyone coming in through the meeting
/// service; and a guest on the website (https) goes there too, skipping the
/// ws:// addresses the browser would refuse. On the fakes of fake_peer.dart:
/// no real network.

final _en = S.forLanguage(AppLanguage.english);

/// The website, where the web version is published.
final _site = Uri.parse('https://williamszc380.github.io/PokerFection/');

/// A PeerHost on [broker] and [rtc] that takes [code] (or tries a few
/// random ones when it is someone else's).
GuestDoor _door(FakeBroker broker, FakeRtc rtc, Clock clock, {String? code}) =>
    (accept) => PeerHost(
      accept: accept,
      rtc: rtc,
      connectSignaling: broker.connect,
      clock: clock,
      random: Random(4),
      pickCode: code == null ? null : () => code,
    );

/// The app's room in the test running now.
RoomService? _rooms;

/// Play Online in the app, for a player called [name], in a window wide
/// enough for the room to be docked beside it.
Widget _app(WidgetTester tester, Widget screen, {String name = 'Ann'}) {
  setScreen(tester, const Size(1280, 800));
  final rooms = _rooms = RoomService(settings: AppSettings()..nickname = name);
  return roomApp(screen, rooms: rooms);
}

/// Lets time pass (the widgets' and the fakes') until [done].
Future<void> _until(WidgetTester tester, FakeInternet net, bool Function() done, String what) async {
  for (var i = 0; !done(); i++) {
    expect(i, lessThan(600), reason: 'never: $what');
    net.clock.advance(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Leaves the room (it closes, if hosted here) and Play Online, and lets
/// everything finish.
Future<void> _leave(WidgetTester tester, FakeInternet net) async {
  final rooms = _rooms;
  _rooms = null;
  if (rooms != null) unawaited(rooms.leave());
  for (var i = 0; i < 10; i++) {
    net.clock.advance(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpWidget(const SizedBox());
  for (var i = 0; i < 50; i++) {
    net.clock.advance(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

bool _inLobby() => find.byType(RoomPanel).evaluate().isNotEmpty;

void main() {
  group('a room hosted in a browser tab', () {
    test("takes its code at the meeting service; the host's own app joins it in memory, with no server to connect "
        "to; the invite names only the room through the meeting service; a friend anywhere joins; and closing "
        'the tab tells the friend at once and gives the code back', () async {
      final clock = SystemClock();
      final broker = FakeBroker(clock);
      final rtc = FakeRtc();
      final host = await InProcessHost.start(door: _door(broker, rtc, clock, code: 'K7M2Q'), clock: clock);
      expect(host.internet, PeerStatus.ready);
      expect(host.peerCode, 'K7M2Q');
      expect(host.inBrowser, isTrue);
      expect(host.localAddresses, isEmpty, reason: 'a page listens on no network');
      expect(host.routerEndpoint, isNull);

      // No connect function at all: the host's own connection never leaves the page.
      final own = OnlineClient(host.ownServer, host: host);
      final welcome = await own.open(const CreateRoom(name: 'Ann'));
      expect(welcome.code, 'K7M2Q');
      expect(welcome.isHost, isTrue);
      expect(hostServers(host, 'K7M2Q'), ['peer:K7M2Q']);

      final guest = PeerConnector(rtc: rtc, connectSignaling: broker.connect, clock: clock, random: Random(20));
      final friend = OnlineClient('peer:K7M2Q', connect: (url) => connectAny(url, peer: guest));
      expect((await friend.open(const JoinRoom(code: 'K7M2Q', name: 'Ben'))).code, 'K7M2Q');

      // The tab goes (host_here_web.dart stops the host when the page hides): the friend hears at once.
      await host.stop();
      await host.stopped.timeout(const Duration(seconds: 5));
      for (var i = 0; i < 50 && friend.status != OnlineStatus.closed; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(friend.status, OnlineStatus.closed);
      expect(friend.closeReason, CloseReason.roomClosed);
      expect(broker.holds(hostPeerId('K7M2Q')), isFalse, reason: 'the code is free again');
      // Stopping again (the host's app closing its connection) is the same stop.
      await host.stop();
      await own.close();
    });

    test("the host's own connection keeps nothing of what goes through it: a room hosted for hours doesn't fill the "
        "tab's memory", () async {
      final clock = SystemClock();
      final host = await InProcessHost.start(door: _door(FakeBroker(clock), FakeRtc(), clock, code: 'K7M2Q'), clock: clock);
      final own = host.connectOwn() as MemoryLink;
      own.send(const CreateRoom(name: 'Ann').encode());
      for (var n = 1; n <= 100; n++) {
        own.send(Ping(n).encode());
      }
      final heard = await own.messages.take(101).length;
      expect(heard, 101, reason: 'the welcome and a pong for each ping');
      expect(own.sent, isEmpty);
      await host.stop();
    });

    test("when someone else holds the code at the meeting service, the room gets another and the invite doesn't "
        'name the meeting service (it would lead to the other room)', () async {
      final clock = SystemClock();
      final broker = FakeBroker(clock);
      await broker.connect('$peerBroker?id=${hostPeerId('K7M2Q')}&token=someoneelse');
      final host = await InProcessHost.start(door: _door(broker, FakeRtc(), clock, code: 'K7M2Q'), clock: clock);
      expect(host.internet, const PeerStatus.unavailable(PeerTrouble.codeTaken));
      expect(host.peerCode, isNull);
      final own = OnlineClient(host.ownServer, host: host);
      final welcome = await own.open(const CreateRoom(name: 'Ann'));
      expect(welcome.code, isNot('K7M2Q'));
      expect(hostServers(host, welcome.code), isEmpty);
      await own.close();
      await host.stopped.timeout(const Duration(seconds: 5));
    });

    test('where there are no direct connections, the room still opens for its host, and says the internet is not '
        'available on this device', () async {
      // The real PeerHost: under flutter test there is no WebRTC, as in a browser without it.
      final host = await InProcessHost.start();
      expect(host.internet, const PeerStatus.unavailable(PeerTrouble.unsupported));
      final own = OnlineClient(host.ownServer, host: host);
      final welcome = await own.open(const CreateRoom(name: 'Ann'));
      expect(welcome.code, matches(roomCodePattern));
      expect(hostServers(host, welcome.code), isEmpty);
      await own.close();
      await host.stopped.timeout(const Duration(seconds: 5));
    });
  });

  testWidgets('Create Room in a browser: the lobby greys out the same Wi-Fi line ("app only"), says to keep the tab '
      'open behind the "?", and the invite names the room through the meeting service', (tester) async {
    final net = FakeInternet();
    InProcessHost? host;
    await tester.pumpWidget(
      _app(
        tester,
        OnlineScreen(
          page: _site,
          startHost: () async => host = await InProcessHost.start(
            door: _door(net.broker, net.rtc, net.clock, code: 'K7M2Q'),
            clock: net.clock,
            random: Random(3),
          ),
          connect: (url) => throw StateError('The host joins in memory, not at $url'),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('online go')));
    await _until(tester, net, _inLobby, 'the lobby');
    await tester.pump();
    expect(find.text('K7M2Q'), findsOneWidget);
    expect(find.text('Internet: ready'), findsOneWidget);
    // No way in on the same Wi-Fi of its own: greyed out, not hidden; the tab advice is behind the "?".
    expect(find.text(_en.sameWifiAppOnly), findsOneWidget);
    expect(find.textContaining('Keep this tab open'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('internet help')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Friends anywhere can join with the code or the invite.'), findsOneWidget);
    expect(find.textContaining('Keep this tab open while you host'), findsOneWidget);
    expect(find.textContaining('Same Wi-Fi always works'), findsNothing, reason: 'not without the app');
    expect(find.textContaining('works only when the room is hosted in the app'), findsOneWidget);
    expect(find.textContaining('Windows Firewall'), findsNothing);
    Navigator.of(tester.element(find.byType(AlertDialog))).pop();
    await tester.pumpAndSettle();

    expect(siteInviteLink('K7M2Q', hostServers(host!, 'K7M2Q')), endsWith('join.html?code=K7M2Q&server=peer%3AK7M2Q'));

    // A friend anywhere joins the tab's room.
    final friend = OnlineClient('peer:K7M2Q', connect: (url) => connectAny(url, peer: net.guest(30)));
    Welcome? welcome;
    unawaited(friend.open(const JoinRoom(code: 'K7M2Q', name: 'Ben')).then((w) => welcome = w));
    await _until(tester, net, () => welcome != null, 'the friend in');
    // The room starts with no game: the host picks Hold'em before anyone sits (as Home's Hold'em, Play, Open
    // Table does), and is taken to its table, where Ben's seat shows; Back to the room beside the screen.
    _rooms!.hostPick(holdemKey);
    await _until(tester, net, () => _rooms!.room?.game?.key == holdemKey && _rooms!.gameOnScreen, "Hold'em picked");
    friend.send(const TakeSeat());
    await _until(tester, net, () => find.text('Ben').evaluate().isNotEmpty, "Ben seated at the room's table");
    await tester.binding.handlePopRoute();
    await _until(tester, net, () => !_rooms!.gameOnScreen, 'back beside the room');

    // Leaving closes the room, and gives its name at the meeting service back.
    await _leave(tester, net);
    expect(net.broker.holds(hostPeerId('K7M2Q')), isFalse);
    expect(friend.closeReason, CloseReason.roomClosed);
  });

  group('a guest on the website (https)', () {
    testWidgets("joins an invite through the meeting service, skipping the host's ws:// addresses at once (the "
        'browser would refuse them)', (tester) async {
      final net = FakeInternet();
      final room = await _roomElsewhere(tester, net);
      final tried = <String>[];
      await tester.pumpWidget(
        _app(
          tester,
          OnlineScreen(
            page: Uri.parse('https://williamszc380.github.io/PokerFection/?code=K7M2Q&server=peer%3AK7M2Q'),
            invite: (code: 'K7M2Q', servers: const ['ws://192.168.1.20:47474/ws', 'peer:K7M2Q', 'wss://pf.example/ws']),
            connect: (url) {
              tried.add(url);
              return room.connector(nearby: false)(url);
            },
          ),
          name: 'Ben',
        ),
      );
      await tester.tap(find.byKey(const ValueKey('online go')));
      await _until(tester, net, _inLobby, 'the lobby');
      expect(tried, ['peer:K7M2Q']);
      unawaited(room.stop());
      await _leave(tester, net);
    });

    testWidgets('joins a bare code through the meeting service, and tries nothing on this computer', (tester) async {
      final net = FakeInternet();
      final room = await _roomElsewhere(tester, net);
      final tried = <String>[];
      await tester.pumpWidget(
        _app(
          tester,
          OnlineScreen(
            page: _site,
            findNearby: (code) async => const [],
            connect: (url) {
              tried.add(url);
              return room.connector(nearby: false)(url);
            },
          ),
          name: 'Ben',
        ),
      );
      await tester.enterText(find.byKey(const ValueKey('online code')), 'K7M2Q');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('online go')));
      await _until(tester, net, _inLobby, 'the lobby');
      expect(tried, ['peer:K7M2Q']);
      unawaited(room.stop());
      await _leave(tester, net);
    });

    testWidgets("a room whose host this network can't reach directly: told what to try instead", (tester) async {
      final net = FakeInternet();
      final room = await _roomElsewhere(tester, net);
      net.rtc.failIce = true;
      await tester.pumpWidget(
        _app(
          tester,
          OnlineScreen(page: _site, findNearby: (code) async => const [], connect: room.connector(nearby: false)),
          name: 'Ben',
        ),
      );
      await tester.enterText(find.byKey(const ValueKey('online code')), 'K7M2Q');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('online go')));
      await _until(tester, net, () => find.text(_en.noDirectRoute).evaluate().isNotEmpty, 'the message');
      unawaited(room.stop());
      await _leave(tester, net);
    });
  });
}

/// Room K7M2Q, hosted on another device with its host's app in it.
Future<TestRoomHost> _roomElsewhere(WidgetTester tester, FakeInternet net) async {
  TestRoomHost? started;
  unawaited(TestRoomHost.start(net, code: 'K7M2Q').then((h) => started = h));
  await _until(tester, net, () => started != null, 'the code taken');
  final host = started!;
  final own = OnlineClient(host.ownServer, host: host, connect: host.connector());
  var opened = false;
  unawaited(own.open(const CreateRoom(name: 'Ann')).then((_) => opened = true));
  await _until(tester, net, () => opened, 'the room created');
  return host;
}
