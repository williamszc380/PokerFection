import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/online/connect.dart';
import 'package:pokerfection/src/online/invite.dart';
import 'package:pokerfection/src/online/online_client.dart';
import 'package:pokerfection/src/online/peer_config.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/ui/online/online_screen.dart';
import 'package:pokerfection/src/ui/online/room_panel.dart';
import 'package:pokerfection/src/ui/online/room_scope.dart';

import '../widget_test.dart' show setScreen;
import 'fake_room_host.dart';
import 'room_app.dart';

/// Play Online, hosting and joining rooms through the meeting service (on
/// the fakes of fake_peer.dart: no real network, router or sockets).

final _en = S.forLanguage(AppLanguage.english);

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

/// Lets [time] pass, for the widgets and the fakes.
Future<void> _wait(WidgetTester tester, FakeInternet net, Duration time) async {
  for (var left = time; left > Duration.zero; left -= const Duration(milliseconds: 100)) {
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
  await _wait(tester, net, const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox());
  await _wait(tester, net, const Duration(seconds: 4));
}

bool _inLobby() => find.byType(RoomPanel).evaluate().isNotEmpty;

/// The invite link the Invite dialog shows, read back.
Invite? _shownInvite(WidgetTester tester) {
  final texts = tester.widgetList<SelectableText>(find.byType(SelectableText));
  return parseInvite(texts.map((t) => t.data ?? '').firstWhere((t) => t.contains('join.html')));
}

/// Closes the dialog on top.
Future<void> _closeDialog(WidgetTester tester) async {
  Navigator.of(tester.element(find.byType(AlertDialog))).pop();
  await tester.pumpAndSettle();
}

/// A room hosted on another device, K7M2Q, with its host's app in it (as
/// Create Room leaves it).
Future<(TestRoomHost, OnlineClient)> _hostElsewhere(WidgetTester tester, FakeInternet net) async {
  TestRoomHost? started;
  // Under the widgets' clock, as everything else: it takes the code at the meeting service as time passes.
  unawaited(TestRoomHost.start(net, code: 'K7M2Q').then((h) => started = h));
  await _until(tester, net, () => started != null, 'the code taken');
  final host = started!;
  final own = OnlineClient(host.ownServer, host: host, connect: host.connector());
  var opened = false;
  unawaited(own.open(const CreateRoom(name: 'Ann')).then((_) => opened = true));
  await _until(tester, net, () => opened, 'the room created');
  return (host, own);
}

/// Types [code] on Play Online and presses Join Room.
Future<void> _join(WidgetTester tester, String code) async {
  await tester.enterText(find.byKey(const ValueKey('online code')), code);
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('online go')));
  await tester.pump();
}

void main() {
  testWidgets('Create Room: the room takes the code this device holds at the meeting service; the lobby shows both '
      'ways in, with a "?" that explains, and the invite names the same Wi-Fi first, then the room through the '
      'meeting service. No box for a public address', (tester) async {
    final net = FakeInternet();
    TestRoomHost? host;
    await tester.pumpWidget(
      _app(
        tester,
        OnlineScreen(
          startHost: () async => host = await TestRoomHost.start(net, code: 'K7M2Q'),
          connect: (url) => host!.connector()(url),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('online go')));
    await _until(tester, net, _inLobby, 'the lobby');
    await tester.pump();
    expect(find.text('K7M2Q'), findsOneWidget);
    expect(find.text(_en.sameWifi(true)), findsOneWidget);
    expect(find.text('Internet: ready'), findsOneWidget);
    expect(find.text(_en.shareCode), findsOneWidget);
    expect(find.byKey(const ValueKey('public address')), findsNothing);
    expect(find.textContaining('Public address'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('internet help')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Friends anywhere can join with the code or the invite.'), findsOneWidget);
    expect(find.textContaining('A free public meeting service introduces the devices.'), findsOneWidget);
    expect(find.textContaining('device to device, encrypted.'), findsOneWidget);
    expect(find.textContaining('(often mobile data)'), findsOneWidget);
    expect(find.textContaining('Same Wi-Fi always works'), findsOneWidget);
    expect(find.textContaining('router'), findsNothing, reason: 'nothing asks the host to set up a router');
    await _closeDialog(tester);

    await tester.tap(find.byKey(const ValueKey('invite')));
    await tester.pumpAndSettle();
    final invite = _shownInvite(tester)!;
    expect(invite.code, 'K7M2Q');
    expect(invite.servers, ['ws://192.168.1.20:47474/ws', 'peer:K7M2Q']);
    await _closeDialog(tester);

    // Leaving closes the room, and gives its name at the meeting service back.
    expect(net.broker.holds(hostPeerId('K7M2Q')), isTrue);
    await _leave(tester, net);
    expect(net.broker.holds(hostPeerId('K7M2Q')), isFalse);
    expect(host!.registry.roomCount, 0);
  });

  testWidgets('a friend anywhere joins the room created here with the invite; the lobby follows the meeting '
      "service's status as it changes", (tester) async {
    final net = FakeInternet();
    TestRoomHost? host;
    await tester.pumpWidget(
      _app(
        tester,
        OnlineScreen(
          startHost: () async => host = await TestRoomHost.start(net, code: 'K7M2Q'),
          connect: (url) => host!.connector()(url),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('online go')));
    await _until(tester, net, _inLobby, 'the lobby');

    // From elsewhere: the same Wi-Fi isn't reachable, the meeting service is.
    final invite = parseInvite(siteInviteLink('K7M2Q', hostServers(host!, 'K7M2Q')))!;
    final friend = OnlineClient(
      invite.servers.first,
      alsoTry: invite.servers.skip(1).toList(),
      connect: host!.connector(nearby: false, guest: net.guest(30)),
    );
    Welcome? welcome;
    unawaited(friend.open(JoinRoom(code: invite.code, name: 'Ben')).then((w) => welcome = w));
    await _until(tester, net, () => welcome != null, 'the friend in');
    expect(friend.url, 'peer:K7M2Q');
    // The room starts with no game: the host picks Hold'em before anyone sits (as Home's Hold'em, Play, Open
    // Table does), and is taken to its table, where Ben's seat shows; Back to the room beside the screen.
    _rooms!.hostPick(holdemKey);
    await _until(tester, net, () => _rooms!.room?.game?.key == holdemKey && _rooms!.gameOnScreen, "Hold'em picked");
    friend.send(const TakeSeat());
    await _until(tester, net, () => find.text('Ben').evaluate().isNotEmpty, "Ben seated at the room's table");
    await tester.binding.handlePopRoute();
    await _until(tester, net, () => !_rooms!.gameOnScreen, 'back beside the room');

    // The connection to the meeting service drops: connecting again, then ready again.
    net.broker.drop(hostPeerId('K7M2Q'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Internet: connecting…'), findsOneWidget);
    await _until(tester, net, () => find.text('Internet: ready').evaluate().isNotEmpty, 'ready again');

    unawaited(friend.close());
    await _leave(tester, net);
  });

  testWidgets('without internet, Create Room still works on the same Wi-Fi: the lobby says the internet is not '
      'available and why, and a friend nearby joins with the code', (tester) async {
    final net = FakeInternet();
    net.broker.reachable = false;
    TestRoomHost? host;
    await tester.pumpWidget(
      _app(
        tester,
        OnlineScreen(
          startHost: () async => host = await TestRoomHost.start(net),
          connect: (url) => host!.connector()(url),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('online go')));
    await _until(tester, net, _inLobby, 'the lobby');
    await tester.pump();
    expect(find.text(_en.sameWifi(true)), findsOneWidget);
    expect(find.text('Internet: not available (no connection)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('internet help')));
    await tester.pumpAndSettle();
    expect(find.textContaining("The meeting service can't be reached (no internet?)."), findsOneWidget);
    expect(find.textContaining('Same Wi-Fi always works, even without internet.'), findsOneWidget);
    await _closeDialog(tester);

    final code = host!.peer.code!;
    expect(host!.registry.room(code), isNotNull, reason: 'the room has the code, whatever the meeting service said');
    final friend = OnlineClient('ws://192.168.1.20:47474/ws', connect: host!.connector());
    Welcome? welcome;
    unawaited(friend.open(JoinRoom(code: code, name: 'Ben')).then((w) => welcome = w));
    await _until(tester, net, () => welcome != null, 'the friend in');
    expect(welcome!.code, code);
    unawaited(friend.close());
    await _leave(tester, net);
  });

  testWidgets('a bare room code tries the rooms found on the same Wi-Fi first, then the room through the meeting '
      'service, wherever its host is', (tester) async {
    final net = FakeInternet();
    final (host, own) = await _hostElsewhere(tester, net);
    final tried = <String>[];
    await tester.pumpWidget(
      _app(
        tester,
        OnlineScreen(
          // A room nearby with that code (it has gone since): tried first, and it fails.
          findNearby: (code) async => ['ws://192.168.1.99:47474/ws'],
          connect: (url) {
            tried.add(url);
            return host.connector(nearby: false)(url);
          },
        ),
        name: 'Ben',
      ),
    );
    await _join(tester, 'k7m2q');
    await _until(tester, net, _inLobby, 'the lobby');
    expect(tried, ['ws://192.168.1.99:47474/ws', 'peer:K7M2Q']);
    expect(host.registry.room('K7M2Q')!.connectedCount, 2);
    await _leave(tester, net);
    unawaited(own.close());
    await _wait(tester, net, const Duration(seconds: 3));
  });

  testWidgets("when the host answers but this network can't reach it directly, the player is told what to try "
      "instead, not just that the room can't be reached", (tester) async {
    final net = FakeInternet();
    final (host, own) = await _hostElsewhere(tester, net);
    net.rtc.failIce = true;
    final tried = <String>[];
    await tester.pumpWidget(
      _app(
        tester,
        OnlineScreen(
          findNearby: (code) async => const [],
          connect: (url) {
            tried.add(url);
            return host.connector(nearby: false)(url);
          },
        ),
        name: 'Ben',
      ),
    );
    await _join(tester, 'K7M2Q');
    await _until(tester, net, () => find.text(_en.noDirectRoute).evaluate().isNotEmpty, 'the message');
    expect(_en.noDirectRoute, allOf(contains('mobile data'), contains('same Wi-Fi')));
    // Everything was tried, the room on this computer last; the direct connection's failure says the most.
    expect(tried, ['peer:K7M2Q', 'ws://127.0.0.1:47474/ws']);
    expect(find.byType(RoomPanel), findsNothing);
    for (final language in AppLanguage.values) {
      expect(S.forLanguage(language).noDirectRoute, isNotEmpty);
    }
    await _leave(tester, net);
    unawaited(own.close());
    await _wait(tester, net, const Duration(seconds: 3));
  });

  testWidgets('a code nobody holds, nearby or at the meeting service: "Room not found"', (tester) async {
    final net = FakeInternet();
    final guest = net.guest();
    await tester.pumpWidget(
      _app(
        tester,
        OnlineScreen(
          findNearby: (code) async => const [],
          connect: (url) {
            if (isPeerEntry(url)) return connectAny(url, peer: guest);
            throw StateError('Nothing listens at $url');
          },
        ),
        name: 'Ben',
      ),
    );
    await _join(tester, 'ZZZZZ');
    await _until(tester, net, () => find.text('Room not found').evaluate().isNotEmpty, 'the error');
    expect(net.broker.expires, isNotEmpty, reason: 'the meeting service said nobody holds the name');
    await _leave(tester, net);
  });

  testWidgets("with a server set by hand, joining tries that server, not the meeting service (its rooms aren't "
      "there): when it is down, the player hears the server can't be reached, not \"Room not found\"", (tester) async {
    final net = FakeInternet();
    final tried = <String>[];
    await tester.pumpWidget(
      AppSettingsScope(
        settings: AppSettings()
          ..nickname = 'Ben'
          ..serverUrl = 'wss://poker.example.org/ws',
        child: MaterialApp(
          home: OnlineScreen(
            findNearby: (code) async => const [],
            connect: (url) {
              tried.add(url);
              if (isPeerEntry(url)) return connectAny(url, peer: net.guest());
              throw StateError('Nothing listens at $url');
            },
          ),
        ),
      ),
    );
    await _join(tester, 'K7M2Q');
    await _until(tester, net, () => find.text(_en.cantReachServer).evaluate().isNotEmpty, 'the error');
    expect(tried, ['wss://poker.example.org/ws', 'ws://127.0.0.1:47474/ws']);
    expect(find.text('Room not found'), findsNothing);
    await _leave(tester, net);
  });

  testWidgets("Create Room on a server set by hand that can't be reached says the server can't be reached",
      (tester) async {
    final net = FakeInternet();
    await tester.pumpWidget(
      AppSettingsScope(
        settings: AppSettings()
          ..nickname = 'Ann'
          ..serverUrl = 'ws://203.0.113.9:47474/ws',
        child: MaterialApp(home: OnlineScreen(connect: (url) => throw StateError('Nothing listens at $url'))),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('online go')));
    await _until(tester, net, () => find.text(_en.cantReachServer).evaluate().isNotEmpty, 'the error');
    expect(find.text(_en.joinError(null)), findsNothing);
    await _leave(tester, net);
  });

  testWidgets("on the website, a ws:// server set by hand can't be used (the browser refuses it on a secure page): "
      'the player is told so, rather than that the room is nowhere', (tester) async {
    final net = FakeInternet();
    final tried = <String>[];
    await tester.pumpWidget(
      AppSettingsScope(
        settings: AppSettings()
          ..nickname = 'Ben'
          ..serverUrl = 'ws://203.0.113.9:47474/ws',
        child: MaterialApp(
          home: OnlineScreen(
            page: Uri.parse('https://williamszc380.github.io/PokerFection/'),
            findNearby: (code) async => const [],
            connect: (url) {
              tried.add(url);
              throw StateError('The browser refuses $url');
            },
          ),
        ),
      ),
    );
    await _join(tester, 'K7M2Q');
    await _until(tester, net, () => find.text(_en.wsOnWebsite).evaluate().isNotEmpty, 'the error');
    expect(tried, isEmpty, reason: 'nothing this page could open');
    await _leave(tester, net);
  });

  testWidgets("an invite that leaves the meeting service out (its host holds no name there) isn't sent there: the "
      "name could be anyone's", (tester) async {
    final net = FakeInternet();
    final tried = <String>[];
    await tester.pumpWidget(
      _app(
        tester,
        OnlineScreen(
          invite: (code: 'K7M2Q', servers: const ['ws://192.168.1.20:47474/ws']),
          connect: (url) {
            tried.add(url);
            if (isPeerEntry(url)) return connectAny(url, peer: net.guest());
            throw StateError('Nothing listens at $url');
          },
        ),
        name: 'Ben',
      ),
    );
    await tester.tap(find.byKey(const ValueKey('online go')));
    await _until(tester, net, () => find.text(_en.joinError(null)).evaluate().isNotEmpty, 'the error');
    expect(tried, ['ws://192.168.1.20:47474/ws', 'ws://127.0.0.1:47474/ws']);
    await _leave(tester, net);
  });
}
