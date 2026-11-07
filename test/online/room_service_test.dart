import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/main.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/app/sounds.dart';
import 'package:pokerfection/src/gto/gto_solutions.dart';
import 'package:pokerfection/src/gto/preflop/preflop_equity.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/online/clock.dart';
import 'package:pokerfection/src/online/connect.dart';
import 'package:pokerfection/src/online/in_process_host.dart';
import 'package:pokerfection/src/online/memory_link.dart';
import 'package:pokerfection/src/online/online_client.dart';
import 'package:pokerfection/src/online/online_socket.dart';
import 'package:pokerfection/src/online/peer_host.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/online/room_host.dart';
import 'package:pokerfection/src/online/timing.dart';
import 'package:pokerfection/src/ui/game_menu.dart';
import 'package:pokerfection/src/ui/games.dart';
import 'package:pokerfection/src/ui/glossary.dart';
import 'package:pokerfection/src/ui/hand_rankings_screen.dart';
import 'package:pokerfection/src/ui/home_screen.dart';
import 'package:pokerfection/src/ui/online/online_screen.dart';
import 'package:pokerfection/src/ui/online/room_lobby_screen.dart';
import 'package:pokerfection/src/ui/online/room_panel.dart';
import 'package:pokerfection/src/ui/online/room_scope.dart';
import 'package:pokerfection/src/ui/online/room_shell.dart';
import 'package:pokerfection/src/ui/settings_screen.dart';
import 'package:pokerfection/src/ui/table_controller.dart';
import 'package:pokerfection/src/ui/table_screen.dart';

import '../widget_test.dart' show setScreen, testSolutions;
import 'fake_room_host.dart';
import 'room_kit.dart';

/// The app's room (RoomService): it outlives every screen, takes everyone
/// to the room's table when the host opens or starts a game (v2.1: guests
/// follow the host), shows the seats there again after the game, and keeps
/// the game going off screen.

final _en = S.forLanguage(AppLanguage.english);

/// The app at [size] for a player called [name], with its room [rooms].
Future<RoomService> _app(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
  String name = 'Ben',
  RoomService? rooms,
  GtoSolutions? solutions,
}) async {
  setScreen(tester, size);
  final settings = rooms?.settings ?? (AppSettings()
    ..nickname = name
    ..speed = PlaybackSpeed.instant);
  rooms ??= RoomService(settings: settings, solutions: solutions ?? testSolutions());
  await tester.pumpWidget(PokerFectionApp(settings: settings, rooms: rooms, newJobs: () => Jobs.inline()));
  await tester.pump();
  return rooms;
}

/// A Hold'em room on [server] (with no game: [game] false), hosted by an
/// app not on screen (its client).
Future<OnlineClient> _hostRoom(
  WidgetTester tester,
  TestServer server, {
  int seats = 4,
  Map<int, String> bots = const {},
  bool game = true,
}) async {
  final host = server.client();
  await server.open(
    tester,
    host,
    game
        ? CreateRoom(
            name: 'Ann',
            game: holdemKey,
            settings: RoomSettings(seats: seats, stackBb: 20, resetStacks: true),
            bots: bots,
          )
        : const CreateRoom(name: 'Ann'),
  );
  return host;
}

/// [name]'s client in room [code], handed to [rooms] as Play Online does.
Future<OnlineClient> _enter(WidgetTester tester, TestServer server, RoomService rooms, String code, {String name = 'Ben'}) async {
  final client = server.client();
  await server.open(tester, client, JoinRoom(code: code, name: name));
  rooms.enter(client);
  await tester.pump();
  return client;
}

/// Guests who play by themselves, seated.
Future<List<AutoGuest>> _players(WidgetTester tester, TestServer server, String code, List<String> names, {Duration think = Duration.zero}) async {
  final guests = [for (final name in names) AutoGuest(server, name, think: think)];
  for (final guest in guests) {
    guest.join(code);
    await server.until(tester, () => guest.room != null, '${guest.name} in');
    guest.send(const TakeSeat());
    await server.until(tester, () => guest.room?.me?.seat != null, '${guest.name} seated');
  }
  return guests;
}

/// Lets the screens' animations run (spinners never settle), and the
/// [server]'s time with them.
Future<void> _settle(WidgetTester tester, [TestServer? server]) async {
  for (var i = 0; i < 8; i++) {
    server?.clock.advance(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

NavigatorState _nav(RoomService rooms) => rooms.navigatorKey.currentState!;

void _push(RoomService rooms, Widget screen) =>
    unawaited(_nav(rooms).push(MaterialPageRoute<void>(builder: (_) => screen)));

/// Scrolls [finder] into view (in the room's panel) and taps it.
Future<void> _tapInPanel(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

bool _atTable() => find.byType(TableScreen).evaluate().isNotEmpty;

/// The room's table shows the game's seats (no game running).
bool _atSeats() => find.byType(RoomLobbyScreen).evaluate().isNotEmpty;

/// The table is the top screen.
bool _tableOnTop(RoomService rooms) => rooms.gameOnScreen;

/// Leaves every room, takes the app away and lets everything finish.
Future<void> _end(WidgetTester tester, TestServer server, List<RoomService> rooms) async {
  for (final r in rooms) {
    unawaited(r.leave());
  }
  await server.wait(tester, const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox());
  await server.wait(tester, const Duration(seconds: 6));
}

/// A room host whose own connection the test can cut and keep cut (the
/// app suspended in the background), around [inner].
class _PausableHost implements RoomHost {
  _PausableHost(this.inner);

  final InProcessHost inner;
  bool away = false;
  MemoryLink? link;

  @override
  OnlineSocket? connectOwn() {
    if (away) return null;
    return link = inner.connectOwn() as MemoryLink;
  }

  /// When the own connection can't be had (away): nothing listens.
  Future<OnlineSocket> connect(String url) async => throw StateError('away');

  @override
  int get port => inner.port;
  @override
  String get ownServer => inner.ownServer;
  @override
  bool get inBrowser => inner.inBrowser;
  @override
  List<String> get localAddresses => inner.localAddresses;
  @override
  PeerStatus get internet => inner.internet;
  @override
  String? get peerCode => inner.peerCode;
  @override
  ({String address, int port})? get routerEndpoint => inner.routerEndpoint;
  @override
  bool get servesWeb => inner.servesWeb;
  @override
  Stream<void> get changes => inner.changes;
  @override
  void checkInternet() => inner.checkInternet();
  @override
  Future<void> get routerSetup => inner.routerSetup;
  @override
  Future<void> get stopped => inner.stopped;
  @override
  Future<void> stop() => inner.stop();
}

void main() {
  tearDown(() => OnlineTableController.debugOnSound = null);

  testWidgets('Create Room on Play Online: it closes, and Home has the room beside it, a rail on a phone held '
      'sideways (the app gets the rest) and the whole room docked on a PC', (tester) async {
    final net = FakeInternet();
    final rooms = await _app(tester, name: 'Ann');
    TestRoomHost? host;
    unawaited(_nav(rooms).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(arguments: RoomRoute.online),
        builder: (_) => OnlineScreen(
          startHost: () async => host = await TestRoomHost.start(net, code: 'K7M2Q'),
          connect: (url) => host!.connector()(url),
        ),
      ),
    ));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('online go')));
    for (var i = 0; !(rooms.inRoom && find.byType(OnlineScreen).evaluate().isEmpty); i++) {
      expect(i, lessThan(300));
      net.clock.advance(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await _settle(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(RoomPanel), findsOneWidget);
    expect(tester.getSize(find.byType(HomeScreen)).width, closeTo(1280 - RoomShell.dockWidth(1280), 0.01));

    setScreen(tester, const Size(568, 320));
    await _settle(tester);
    expect(find.byType(RoomRail), findsOneWidget);
    expect(find.byType(RoomPanel), findsNothing);
    expect(tester.getSize(find.byType(HomeScreen)).width, 568 - RoomShell.railWidth);
    expect(find.text('K7M2Q'), findsOneWidget, reason: "the rail's code");
    // Home's Multiplayer button is the room's now.
    expect(find.text(_en.room('K7M2Q')), findsOneWidget);

    setScreen(tester, const Size(1280, 800));
    await _settle(tester);
    expect(find.byType(RoomRail), findsNothing);
    expect(find.byType(RoomPanel), findsOneWidget);

    unawaited(rooms.leave());
    for (var i = 0; i < 60; i++) {
      net.clock.advance(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(host!.registry.roomCount, 0);
    expect(find.byType(RoomPanel), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("going to Settings, a game's menu and a guide and back never takes anyone out: the host's connection "
      'stays open, its room keeps running, and a guest still hears it', (tester) async {
    final net = FakeInternet();
    TestRoomHost? started;
    unawaited(TestRoomHost.start(net, code: 'K7M2Q').then((h) => started = h));
    for (var i = 0; started == null; i++) {
      expect(i, lessThan(300));
      net.clock.advance(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }
    final host = started!;
    var stopped = false;
    unawaited(host.stopped.then((_) => stopped = true));
    Future<void> wait([int steps = 5]) async {
      for (var i = 0; i < steps; i++) {
        net.clock.advance(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    final own = OnlineClient(host.ownServer, host: host, connect: host.connector());
    var opened = false;
    unawaited(own.open(const CreateRoom(name: 'Ann')).then((_) => opened = true));
    while (!opened) {
      await wait(1);
    }
    final guest = OnlineClient('ws://192.168.1.20:47474/ws', connect: host.connector());
    var joined = false;
    unawaited(guest.open(const JoinRoom(code: 'K7M2Q', name: 'Ben')).then((_) => joined = true));
    while (!joined) {
      await wait(1);
    }
    final rooms = RoomService(settings: AppSettings()..nickname = 'Ann');
    rooms.enter(own);
    await _app(tester, rooms: rooms);
    await wait();

    for (final screen in <Widget>[const SettingsScreen(), GameMenu(game: games[1]), const HandRankingsScreen()]) {
      _push(rooms, screen);
      await wait();
      expect(find.byType(RoomPanel), findsOneWidget, reason: 'the room stays beside ${screen.runtimeType}');
      _nav(rooms).pop();
      await wait();
      expect(own.status, OnlineStatus.open);
      expect(stopped, isFalse);
      expect(rooms.stage, RoomStage.open);
    }

    // The docked room has no game picker: the host picks Hold'em the usual way (Home, Hold'em, Play, then the
    // setup's Open Table), and the guest hears it.
    expect(find.descendant(of: find.byType(RoomPanel), matching: find.byType(ChoiceChip)), findsNothing);
    expect(find.text(_en.pickGameOnHome), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('game holdem')));
    await wait();
    await tester.tap(find.text(_en.play));
    await wait();
    expect(find.byKey(const ValueKey('room setup')), findsOneWidget, reason: "the setup is the room's while hosting");
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('open table')),
      200,
      scrollable: find.descendant(of: find.byKey(const ValueKey('room setup')), matching: find.byType(Scrollable)),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('open table')));
    for (var i = 0; guest.room?.game?.key != holdemKey; i++) {
      expect(i, lessThan(100));
      await wait(1);
    }
    await wait();
    expect(guest.room!.seats, hasLength(8));
    expect(_atSeats(), isTrue, reason: "the host is at the room's table");
    expect(rooms.gameOnScreen, isTrue);

    unawaited(rooms.leave());
    await wait(30);
    expect(host.registry.roomCount, 0, reason: 'Close Room ends the room on this device');
    expect(guest.closeReason, CloseReason.roomClosed);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("a guest's Leave Room takes only them out; the host and the others stay", (tester) async {
    final server = TestServer();
    final host = await _hostRoom(tester, server, game: false);
    final code = host.room!.code;
    final cy = AutoGuest(server, 'Cy')..join(code);
    await server.until(tester, () => cy.room != null, 'Cy in');
    final rooms = await _app(tester);
    final ben = await _enter(tester, server, rooms, code);
    await server.wait(tester);
    expect(host.room!.members.map((m) => m.name), containsAll(['Ann', 'Ben', 'Cy']));

    await tester.tap(find.byKey(const ValueKey('leave room')));
    await _settle(tester, server);
    expect(find.text(_en.leaveRoomQuestion), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('leave room sure')));
    await server.until(tester, () => !host.room!.members.any((m) => m.name == 'Ben'), 'Ben gone');
    await _settle(tester, server);
    expect(rooms.stage, RoomStage.none, reason: 'out on purpose: no ended card');
    expect(find.byKey(const ValueKey('room ended')), findsNothing);
    expect(find.byType(RoomPanel), findsNothing);
    expect(ben.status, OnlineStatus.closed);
    expect(host.status, OnlineStatus.open);
    expect(host.room!.members.map((m) => m.name), ['Ann', 'Cy']);
    expect(cy.room!.members.map((m) => m.name), ['Ann', 'Cy']);
    await _end(tester, server, [rooms]);
  });

  testWidgets("the host's Close Room, asked first, ends the room for everyone: a guest's room says why, and OK "
      'takes them out of it', (tester) async {
    final server = TestServer();
    final hostRooms = await _app(tester, name: 'Ann');
    final own = server.client();
    await server.open(tester, own, const CreateRoom(name: 'Ann'));
    hostRooms.enter(own);
    await tester.pump();
    final code = own.room!.code;
    final cy = AutoGuest(server, 'Cy')..join(code);
    final benRooms = RoomService(settings: AppSettings()..nickname = 'Ben');
    final ben = server.client();
    await server.open(tester, ben, JoinRoom(code: code, name: 'Ben'));
    benRooms.enter(ben);
    await server.wait(tester);

    await tester.tap(find.byKey(const ValueKey('close room')));
    await _settle(tester, server);
    expect(find.text(_en.closeRoomQuestion), findsOneWidget);
    expect(find.text(_en.leaveWarning(host: true)), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('close room sure')));
    await server.until(tester, () => ben.status == OnlineStatus.closed, "Ben hears it's closed");
    expect(ben.closeReason, CloseReason.roomClosed);
    expect(cy.seen.whereType<Closing>().single.reason, CloseReason.roomClosed);
    expect(hostRooms.stage, RoomStage.none);
    expect(benRooms.stage, RoomStage.ended);

    // Ben's app: the room says why it ended; OK and it's gone.
    await _app(tester, rooms: benRooms);
    expect(find.byKey(const ValueKey('room ended')), findsOneWidget);
    expect(find.text(_en.closed(CloseReason.roomClosed)), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('room ok')));
    await tester.pump();
    await tester.pump();
    expect(benRooms.stage, RoomStage.none);
    expect(find.byType(RoomPanel), findsNothing);
    await _end(tester, server, [hostRooms, benRooms]);
  });

  testWidgets('when the game starts, a seated guest is taken to the table over whatever is open (a game menu)', (tester) async {
    final server = TestServer();
    final host = await _hostRoom(tester, server);
    final code = host.room!.code;
    await _players(tester, server, code, ['Cy', 'Di']);
    final rooms = await _app(tester);
    final ben = await _enter(tester, server, rooms, code);
    await _settle(tester, server);
    expect(_atSeats(), isTrue, reason: "the room plays Hold'em: its table opens on entering");
    ben.send(const TakeSeat());
    await server.until(tester, () => ben.mySeat != null, 'Ben seated');
    // Off the table before the game (nobody waits), to a game menu.
    await tester.binding.handlePopRoute();
    await _settle(tester, server);
    expect(_atSeats(), isFalse);
    _push(rooms, GameMenu(game: games[1]));
    await server.wait(tester);
    host.send(const StartGame());
    await server.until(tester, _atTable, 'at the table');
    await _settle(tester, server);
    expect(_tableOnTop(rooms), isTrue);
    expect(find.byType(GameMenu, skipOffstage: false), findsOneWidget, reason: 'the menu is still under it');
    expect(find.byType(RoomPanel, skipOffstage: false), findsOneWidget, reason: 'the Room tab');
    expect(find.byType(RoomShell), findsOneWidget);
    expect(find.byKey(const ValueKey('room rail')), findsNothing);
    await _end(tester, server, [rooms]);
  });

  testWidgets('a spectator follows the host: at the table when the game starts, from Home and from a game menu '
      'alike; Back leaves it (the game goes on), and Watch shows the hand being played now', (tester) async {
    final server = TestServer();
    final host = await _hostRoom(tester, server);
    final code = host.room!.code;
    final players = await _players(tester, server, code, ['Cy', 'Di']);

    // From Home (where entering the room left them after Back): to the table.
    final rooms = await _app(tester);
    await _enter(tester, server, rooms, code);
    await _settle(tester, server);
    await tester.binding.handlePopRoute();
    await _settle(tester, server);
    expect(find.byType(HomeScreen), findsOneWidget);
    host.send(const StartGame());
    await server.until(tester, _atTable, 'at the table from Home');
    await _settle(tester, server);
    expect(rooms.table!.spectating, isTrue);
    host.send(const EndGame());
    await server.until(tester, () => !rooms.gameRunning, 'game over');
    await server.wait(tester, const Duration(seconds: 1));
    expect(_atTable(), isFalse);
    expect(_atSeats(), isTrue, reason: "the room's table shows the seats again");

    // From a game menu: taken too (the menu stays under the table).
    await tester.binding.handlePopRoute();
    await _settle(tester, server);
    _push(rooms, GameMenu(game: games[1]));
    await server.wait(tester);
    final watch = find.byKey(const ValueKey('watch'));
    expect(watch, findsOneWidget, reason: "the room's table is a tap away");
    host.send(const StartGame());
    await server.until(tester, () => rooms.gameRunning, 'the game on');
    await _settle(tester, server);
    expect(_atTable(), isTrue);
    expect(_tableOnTop(rooms), isTrue);
    expect(find.byType(GameMenu, skipOffstage: false), findsOneWidget);

    // Back: off the table at once (a spectator), the game goes on.
    await tester.binding.handlePopRoute();
    await _settle(tester, server);
    expect(_atTable(), isFalse);
    expect(find.byType(GameMenu), findsOneWidget);
    final controller = rooms.table!;
    final before = players.first.seen.whereType<HandDealt>().length;
    await server.until(tester, () => players.first.seen.whereType<HandDealt>().length >= before + 2, 'hands go on');
    expect(rooms.table, same(controller), reason: 'the game keeps running off screen');

    await _tapInPanel(tester, watch);
    await _settle(tester, server);
    expect(_atTable(), isTrue);
    await server.wait(tester, const Duration(seconds: 1));
    final latest = players.first.seen.whereType<HandDealt>().last.hand;
    expect(controller.handNumber, latest);
    await _end(tester, server, [rooms]);
  });

  testWidgets("after the game, its banner shows 4 s, then the room's table shows the seats again and the game's "
      "controller goes; the connection stays, and the next game's first hand turns it into a new table", (tester) async {
    final server = TestServer();
    final host = await _hostRoom(tester, server);
    final code = host.room!.code;
    await _players(tester, server, code, ['Cy', 'Di']);
    final rooms = await _app(tester);
    final ben = await _enter(tester, server, rooms, code);
    host.send(const StartGame());
    await server.until(tester, _atTable, 'at the table');
    final first = rooms.table!;
    host.send(const EndGame());
    await server.until(tester, () => first.gameOver != null, 'game over');
    await server.wait(tester, const Duration(seconds: 3));
    expect(_atTable(), isTrue, reason: 'the banner shows');
    await server.wait(tester, const Duration(seconds: 2));
    await _settle(tester, server);
    expect(_atTable(), isFalse);
    expect(_atSeats(), isTrue);
    expect(rooms.gameOnScreen, isTrue, reason: "still at the room's table");
    expect(rooms.table, isNull);
    expect(() => first.addListener(() {}), throwsFlutterError, reason: 'disposed');
    expect(ben.status, OnlineStatus.open);
    expect(rooms.stage, RoomStage.open);

    host.send(const StartGame());
    await server.until(tester, _atTable, 'the next game at the table');
    expect(rooms.table, isNot(same(first)));
    expect(rooms.gameOpen, isTrue);
    await _end(tester, server, [rooms]);
  });

  testWidgets("the host spectating with a GTO bot, on Home the whole hand: the deal waits for the host's solve, the "
      'bot plays from the host, and the table makes no sound off screen', (tester) async {
    final server = TestServer();
    final sounds = <SoundEffect>[];
    OnlineTableController.debugOnSound = sounds.add;
    // Solves that take 2 s.
    final slow = GtoSolutions(
      iterations: 30,
      postflopIterations: 5,
      inBackground: false,
      loadEquity: () async {
        await Future<void>.delayed(const Duration(seconds: 2));
        return PreflopEquity.fromBytes(ByteData.sublistView(File('assets/preflop_equity.bin').readAsBytesSync()));
      },
    );
    final rooms = await _app(tester, name: 'Ann', solutions: slow);
    final own = server.client(record: true);
    await server.open(
      tester,
      own,
      const CreateRoom(
        name: 'Ann',
        game: holdemKey,
        settings: RoomSettings(seats: 3, stackBb: 20, resetStacks: true),
        bots: {0: 'gto'},
      ),
    );
    rooms.enter(own);
    await tester.pump();
    final players = await _players(tester, server, own.room!.code, ['Cy']);
    own.send(const StartGame());
    // From the first hand's line-up to its deal.
    final cy = players.single;
    final link = server.links.first;
    int? readyAt, dealtAt;
    void note() {
      readyAt ??= link.sent.any((m) => m.contains('"t":"ready"')) ? server.clock.nowMs : null;
      dealtAt ??= cy.seen.whereType<HandDealt>().isNotEmpty ? server.clock.nowMs : null;
    }

    await server.until(tester, () => cy.seen.whereType<NextHand>().isNotEmpty, 'the line-up');
    final announced = server.clock.nowMs;
    await server.until(tester, () => rooms.gameRunning, 'the game on');
    note();
    // Spectators on Home go to the table: the host goes back to Home at once.
    await _settle(tester, server);
    if (_atTable()) {
      await tester.binding.handlePopRoute();
      await _settle(tester, server);
    }
    expect(_atTable(), isFalse);
    expect(find.byType(HomeScreen), findsOneWidget);
    sounds.clear();
    await server.until(tester, () {
      note();
      return dealtAt != null;
    }, 'the deal');
    // The first hand has no wait of its own: it was dealt once the host's app had solved and said Ready.
    expect(readyAt, isNotNull);
    expect(readyAt! - announced, greaterThanOrEqualTo(1500), reason: 'the solve took its time');
    expect(dealtAt!, greaterThanOrEqualTo(readyAt!), reason: "the deal waited for the host's Ready");
    expect(dealtAt! - announced, lessThan(OnlineTiming.readyWaitWithHelp.inMilliseconds), reason: 'not for the longest wait');
    await server.until(tester, () => link.sent.any((m) => m.contains('"t":"botAct"')), 'the bot plays from the host');
    await server.until(tester, () => players.single.seen.whereType<HandDealt>().length >= 2, 'another hand');
    expect(_atTable(), isFalse);
    expect(sounds, isEmpty, reason: 'no sound off screen');

    // Back at the table: its sounds again.
    await _tapInPanel(tester, find.byKey(const ValueKey('watch')));
    await _settle(tester, server);
    await server.until(tester, () => sounds.isNotEmpty, 'a sound on screen');
    await _end(tester, server, [rooms]);
  });

  testWidgets('the app restarts during a hand: Play Online rejoins the room with the record kept, and a seated '
      'player is at the table at once', (tester) async {
    final server = TestServer();
    final host = await _hostRoom(tester, server);
    final code = host.room!.code;
    await _players(tester, server, code, ['Cy', 'Di'], think: const Duration(seconds: 1));
    RejoinRecord? record;
    final before = server.client(onRecord: (r) => record = r ?? record);
    await server.open(tester, before, JoinRoom(code: code, name: 'Ben'));
    before.send(const TakeSeat());
    await server.until(tester, () => before.mySeat != null, 'Ben seated');
    host.send(const StartGame());
    await server.wait(tester, const Duration(seconds: 6));
    // The app is gone (no Leave).
    unawaited(before.close(leave: false));
    await server.wait(tester);

    final settings = AppSettings()
      ..nickname = 'Ben'
      ..speed = PlaybackSpeed.instant;
    settings.remember(record);
    final rooms = RoomService(settings: settings, solutions: testSolutions());
    await _app(tester, rooms: rooms);
    unawaited(_nav(rooms).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(arguments: RoomRoute.online),
        builder: (_) => OnlineScreen(connect: (url) async => server.connect()),
      ),
    ));
    await _settle(tester, server);
    await tester.tap(find.byKey(const ValueKey('rejoin')));
    await server.until(tester, _atTable, 'back at the table');
    await _settle(tester, server);
    expect(find.byType(OnlineScreen), findsNothing);
    expect(rooms.client!.mySeat, isNotNull);
    expect(rooms.table!.spectating, isFalse);
    await _end(tester, server, [rooms]);
  });

  testWidgets("during the game, a spectator at the table opens Seats (the table's bar) and taps an empty seat: "
      'queued for the next hand; off the table, they are taken back when they are seated', (tester) async {
    final server = TestServer();
    final host = await _hostRoom(tester, server);
    final code = host.room!.code;
    await _players(tester, server, code, ['Cy', 'Di'], think: const Duration(seconds: 2));
    final rooms = await _app(tester);
    final ben = await _enter(tester, server, rooms, code);
    host.send(const StartGame());
    await server.until(tester, () => rooms.gameRunning && !rooms.table!.handOver, 'a hand on');
    await _settle(tester, server);
    expect(_atTable(), isTrue);
    expect(find.byKey(const ValueKey('end game')), findsNothing, reason: "the host's, not a guest's");
    await tester.tap(find.byKey(const ValueKey('seats button')));
    await _settle(tester, server);
    expect(find.byKey(const ValueKey('seats sheet')), findsOneWidget);
    final empty = ben.room!.seats.firstWhere((s) => s.isEmpty).seat;
    await _tapInPanel(tester, find.byKey(ValueKey('seat $empty')));
    await _settle(tester, server);
    expect(ben.queuedSeat, empty, reason: 'seated from the next hand');
    await tester.tap(find.byKey(const ValueKey('close seats')));
    await _settle(tester, server);

    // Off the table (still a spectator): to a game menu, until seated.
    await tester.binding.handlePopRoute();
    await _settle(tester, server);
    expect(_atTable(), isFalse);
    _push(rooms, GameMenu(game: games[1]));
    await server.until(tester, () => ben.mySeat == empty, 'seated');
    await _settle(tester, server);
    expect(_atTable(), isTrue, reason: 'seated: to the table');
    expect(find.byType(GameMenu, skipOffstage: false), findsOneWidget);
    await _end(tester, server, [rooms]);
  });

  testWidgets("the host's Start is in the Game tab of the room's table (not in the docked room); the table turns into "
      "the game, and the host's End game is on the table's bar", (tester) async {
    final server = TestServer();
    final rooms = await _app(tester, name: 'Ann');
    final own = server.client();
    await server.open(tester, own, const CreateRoom(name: 'Ann', game: holdemKey, settings: RoomSettings(seats: 3)));
    rooms.enter(own);
    await tester.pump();
    await _players(tester, server, own.room!.code, ['Cy', 'Di']);
    await _settle(tester, server);
    expect(_atSeats(), isTrue);
    expect(find.descendant(of: find.byType(RoomPanel, skipOffstage: false), matching: find.byKey(const ValueKey('start'))),
        findsNothing);
    await _tapInPanel(tester, find.byKey(const ValueKey('start')));
    await server.until(tester, _atTable, 'at the table');
    await _settle(tester, server);
    expect(_tableOnTop(rooms), isTrue);
    expect(rooms.table!.spectating, isTrue);
    await tester.tap(find.byKey(const ValueKey('end game')));
    await server.until(tester, () => own.room!.phase == RoomPhase.lobby, 'the game ended');
    await _end(tester, server, [rooms]);
  });

  testWidgets('Watch with the glossary open over the table goes back to that table (not a second one); the routes '
      'the room opens have no names (the address bar stays put)', (tester) async {
    final server = TestServer();
    final host = await _hostRoom(tester, server);
    final code = host.room!.code;
    await _players(tester, server, code, ['Cy', 'Di']);
    final rooms = await _app(tester);
    await _enter(tester, server, rooms, code);
    host.send(const StartGame());
    await server.until(tester, _atTable, 'at the table');
    await _settle(tester, server);
    final table = ModalRoute.of(tester.element(find.byType(TableScreen)))!;
    expect(table.settings.name, isNull);
    expect(table.settings.arguments, RoomRoute.game);

    await tester.tap(find.byIcon(Icons.menu));
    await _settle(tester, server);
    await tester.tap(find.text(_en.glossary));
    await _settle(tester, server);
    expect(find.byType(GlossaryScreen), findsOneWidget);
    expect(rooms.gameOnScreen, isFalse);
    await _tapInPanel(tester, find.byKey(const ValueKey('watch')));
    await _settle(tester, server);
    expect(find.byType(GlossaryScreen), findsNothing);
    expect(find.byType(TableScreen, skipOffstage: false), findsOneWidget);
    expect(rooms.gameOnScreen, isTrue);
    await _end(tester, server, [rooms]);
  });

  testWidgets("the rail opens the room once (a second tap adds nothing); closing it closes a glossary dialog opened "
      'over it too', (tester) async {
    final server = TestServer();
    final host = await _hostRoom(tester, server, game: false);
    final rooms = await _app(tester, size: const Size(568, 320));
    await _enter(tester, server, rooms, host.room!.code);
    await tester.tap(find.byKey(const ValueKey('open room')));
    await _settle(tester, server);
    expect(find.byType(RoomPanel), findsOneWidget);
    expect(rooms.panelOpen, isTrue);
    final sheet = ModalRoute.of(tester.element(find.byType(RoomPanel)))!;
    expect(sheet.settings.name, isNull);
    rooms.openPanel();
    await tester.tap(find.byKey(const ValueKey('open room')), warnIfMissed: false);
    await _settle(tester, server);
    expect(find.byType(RoomPanel), findsOneWidget);

    await tester.tap(find.byType(HelpButton).first);
    await _settle(tester, server);
    expect(find.byType(AlertDialog), findsOneWidget);
    rooms.watch();
    await _settle(tester, server);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(RoomPanel), findsNothing);
    expect(rooms.panelOpen, isFalse);

    // Back closes it too.
    await tester.tap(find.byKey(const ValueKey('open room')));
    await _settle(tester, server);
    await tester.binding.handlePopRoute();
    await _settle(tester, server);
    expect(find.byType(RoomPanel), findsNothing);
    await _end(tester, server, [rooms]);
  });

  testWidgets('a guest the host removes: their room says so, and OK takes them out', (tester) async {
    final server = TestServer();
    final host = await _hostRoom(tester, server, game: false);
    final rooms = await _app(tester);
    final ben = await _enter(tester, server, rooms, host.room!.code);
    await server.wait(tester);
    host.send(RemoveMember(id: ben.room!.you!, name: 'Ben'));
    await server.until(tester, () => rooms.stage == RoomStage.ended, 'ended');
    await tester.pump();
    expect(find.text(_en.closed(CloseReason.removed)), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('room ok')));
    await tester.pump();
    expect(rooms.stage, RoomStage.none);
    await _end(tester, server, [rooms]);
  });

  testWidgets("an invite to another room while in one: Play Online says which room you're in, greys the rest, and "
      'after Leave Room the invite is still there to join', (tester) async {
    final server = TestServer();
    final host = await _hostRoom(tester, server, game: false);
    final code = host.room!.code;
    final rooms = await _app(tester);
    await _enter(tester, server, rooms, code);
    unawaited(_nav(rooms).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(arguments: RoomRoute.online),
        builder: (_) => OnlineScreen(
          invite: (code: 'ZZZZZ', servers: const ['ws://192.168.1.50:47474/ws']),
          connect: (url) async => server.connect(),
        ),
      ),
    ));
    await _settle(tester, server);
    expect(find.byType(OnlineScreen), findsOneWidget);
    expect(find.text(_en.inRoom(code)), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('online go'))).onPressed, isNull);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('online code'))).enabled, isFalse);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('online code'))).controller!.text, 'ZZZZZ');

    await tester.tap(find.descendant(of: find.byType(OnlineScreen), matching: find.byKey(const ValueKey('leave room'))));
    await _settle(tester, server);
    await tester.tap(find.byKey(const ValueKey('leave room sure')));
    await server.wait(tester);
    await _settle(tester, server);
    expect(rooms.stage, RoomStage.none);
    expect(find.text(_en.inRoom(code)), findsNothing);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('online code'))).enabled, isTrue);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('online code'))).controller!.text, 'ZZZZZ');
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('online go'))).onPressed, isNotNull);
    await _end(tester, server, [rooms]);
  });

  testWidgets("a room on this device stays while its host's app is away (suspended for 10 min): it still answers "
      "a guest's chat, and the host's app comes back to it as host", (tester) async {
    final net = FakeInternet();
    InProcessHost? started;
    unawaited(InProcessHost.start(
      door: (accept) => PeerHost(
        accept: accept,
        rtc: net.rtc,
        connectSignaling: net.broker.connect,
        clock: net.clock,
        random: Random(4),
        pickCode: () => 'K7M2Q',
      ),
      clock: net.clock,
      random: Random(3),
    ).then((h) => started = h));
    Future<void> wait(int steps, {Duration step = const Duration(milliseconds: 100)}) async {
      for (var i = 0; i < steps; i++) {
        net.clock.advance(step);
        await tester.pump(step);
      }
    }

    while (started == null) {
      await wait(1);
    }
    final host = _PausableHost(started!);
    // The host's app has its own time: suspended, its timers don't run.
    final hostClock = ManualClock();
    final own = OnlineClient(host.ownServer, host: host, connect: host.connect, clock: hostClock);
    var opened = false;
    unawaited(own.open(const CreateRoom(name: 'Ann')).then((_) => opened = true));
    while (!opened) {
      await wait(1);
    }
    final rooms = RoomService(settings: AppSettings()..nickname = 'Ann');
    rooms.enter(own);
    final guest = OnlineClient('peer:K7M2Q', clock: net.clock, connect: (url) => connectAny(url, peer: net.guest(30)));
    var joined = false;
    unawaited(guest.open(const JoinRoom(code: 'K7M2Q', name: 'Ben')).then((_) => joined = true));
    while (!joined) {
      await wait(1);
    }

    // Away: the connection drops and can't come back for 10 minutes.
    host.away = true;
    await host.link!.close();
    await wait(10);
    expect(own.status, OnlineStatus.reconnecting);
    await wait(600, step: const Duration(seconds: 1));
    guest.say('still here?');
    await wait(10);
    expect(guest.status, OnlineStatus.open);
    expect(guest.chat.map((l) => l.text), contains('still here?'), reason: 'the room answers');
    expect(guest.room!.members.map((m) => m.name), contains('Ann'), reason: 'the host is still a member');

    // Back: the host's app reconnects, as host.
    host.away = false;
    own.reconnectNow();
    hostClock.advance(const Duration(seconds: 2));
    await wait(10);
    expect(own.status, OnlineStatus.open);
    expect(own.isHost, isTrue);
    expect(rooms.stage, RoomStage.open);

    unawaited(guest.close());
    unawaited(rooms.leave());
    hostClock.advance(const Duration(seconds: 3));
    await wait(30);
    await tester.pumpWidget(const SizedBox());
  });
}
