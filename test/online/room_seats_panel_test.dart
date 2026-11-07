import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/online/online_client.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/ui/online/room_lobby_screen.dart';
import 'package:pokerfection/src/ui/online/room_seats_panel.dart';
import 'package:pokerfection/src/ui/online/room_shell.dart' show roomPanelColor;

import '../kit/shots.dart';

/// What moved from the lobby to the room's table (rooms v2.1): the seats
/// and the host's controls (RoomSeatsPanel: the Game tab before the game,
/// the Seats sheet during it), and the felt with the seats to take
/// (RoomSeatsTable): who may do what, what is greyed out, and that nothing
/// overflows at any size or in any language.

const _ann = 1, _ben = 2;

/// A room as [you] sees it: Ann hosts; Ben, Cy and Dee are in it.
RoomState _room({
  int you = _ann,
  GameChoice? game = GameChoice.holdem,
  List<SeatInfo> seats = _seats,
  RoomPhase phase = RoomPhase.lobby,
  Map<int, int> seated = const {_ben: 0, 3: 2},
  bool paused = false,
}) => RoomState(
  code: 'K7M2Q',
  phase: phase,
  paused: paused,
  host: _ann,
  you: you,
  cap: 16,
  games: const {holdemKey: holdemGv},
  game: game,
  settings: game?.key == holdemKey ? RoomSettings(seats: seats.length) : null,
  members: [
    for (final (id, name) in [(1, 'Ann'), (2, 'Ben'), (3, 'Cy'), (4, 'Dee Longname-Example')])
      RoomMember(id: id, name: name, seat: seated[id], status: id == 4 ? SeatStatus.away : SeatStatus.connected),
  ],
  seats: seats,
);

/// Hold'em's four seats: Ben, a GTO bot, Cy, and one empty.
const _seats = [
  SeatInfo(seat: 0, kind: SeatKind.human, name: 'Ben', member: _ben, chips: 2000),
  SeatInfo(seat: 1, kind: SeatKind.bot, name: 'Charlie', style: 'gto', chips: 2000),
  SeatInfo(seat: 2, kind: SeatKind.human, name: 'Cy', member: 3, chips: 2000),
  SeatInfo(seat: 3, kind: SeatKind.empty),
];

/// Eight seats, half of them empty, one waited for.
final _eight = [
  ..._seats,
  const SeatInfo(seat: 4, kind: SeatKind.bot, name: 'Bartholomew-Longname', style: 'nit', chips: 2000),
  const SeatInfo(seat: 5, kind: SeatKind.empty, joining: 'Dee Longname-Example'),
  const SeatInfo(seat: 6, kind: SeatKind.empty),
  const SeatInfo(seat: 7, kind: SeatKind.empty),
];

/// [room]'s connection as its member sees it (not connected anywhere),
/// keeping what it sends in [sent].
OnlineClient _client(RoomState room) => _Recording('memory')
  ..welcome = Welcome(code: room.code, token: 't', id: room.you!, isHost: room.you == room.host)
  ..status = OnlineStatus.open
  ..room = room;

class _Recording extends OnlineClient {
  _Recording(super.url);

  final sent = <ClientMessage>[];

  @override
  void send(ClientMessage message) => sent.add(message);
}

List<ClientMessage> _sent(OnlineClient client) => (client as _Recording).sent;

Future<void> _panel(WidgetTester tester, OnlineClient client, {Size size = const Size(320, 800), AppLanguage language = AppLanguage.english, bool inSheet = false}) async {
  await pumpShot(
    tester,
    Material(color: roomPanelColor, child: RoomSeatsPanel(client: client, inSheet: inSheet)),
    size: size,
    language: language,
  );
  await tester.pump();
}

Future<void> _table(WidgetTester tester, OnlineClient client, {Size size = const Size(420, 400), AppLanguage language = AppLanguage.english}) async {
  await pumpShot(
    tester,
    Material(color: const Color(0xFF0B0F12), child: RoomSeatsTable(client: client, room: client.room!)),
    size: size,
    language: language,
  );
  await tester.pump();
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The mouse cursor over [finder] ([mouse]: one per test).
Future<MouseCursor?> _cursorOn(WidgetTester tester, TestGesture mouse, Finder finder) async {
  await mouse.moveTo(tester.getCenter(finder));
  await tester.pump();
  return RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);
}

void main() {
  setUpAll(loadShotFonts);

  final scenes = <String, RoomState Function()>{
    "host, Hold'em, 4 seats": () => _room(),
    'host, 8 seats': () => _room(seats: _eight),
    'guest, 8 seats': () => _room(you: 4, seats: _eight),
    'host, playing, paused': () => _room(phase: RoomPhase.playing, paused: true),
    'guest waiting for a seat, playing': () => _room(you: 4, phase: RoomPhase.playing, seats: _eight),
  };

  for (final language in AppLanguage.values) {
    testWidgets("the seats panel (256-420 wide) and the table's seats (small to large) never overflow "
        '(${language.code})', (tester) async {
      for (final MapEntry(key: scene, value: room) in scenes.entries) {
        for (final width in const [256.0, 280.0, 360.0, 420.0]) {
          for (final height in const [240.0, 400.0, 800.0]) {
            await _panel(tester, _client(room()), size: Size(width, height), language: language);
            expect(tester.takeException(), isNull, reason: '$scene panel ${width.toInt()}x${height.toInt()}');
          }
        }
        // The felt beside the tabs: a sideways phone (288x276), an upright phone (390x394), a PC (845x756).
        for (final size in const [Size(232, 220), Size(288, 276), Size(390, 394), Size(640, 316), Size(845, 756)]) {
          await _table(tester, _client(room()), size: size, language: language);
          expect(tester.takeException(), isNull, reason: '$scene table $size');
          // No two seats overlap.
          final boxes = [
            for (var i = 0; i < room().seats.length; i++) tester.getRect(find.byKey(ValueKey('table seat $i'))),
          ];
          for (var i = 0; i < boxes.length; i++) {
            for (var j = i + 1; j < boxes.length; j++) {
              expect(boxes[i].overlaps(boxes[j].deflate(0.5)), isFalse, reason: '$scene $size: seats $i and $j');
            }
          }
        }
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets("Start is greyed out until 2 seats are taken (with why); Join game until a seat is free or a bot can "
      "give its seat; the switch and the bots only for the host", (tester) async {
    final s = S.forLanguage(AppLanguage.english);
    final one = [
      const SeatInfo(seat: 0, kind: SeatKind.human, name: 'Ben', member: _ben),
      for (var i = 1; i < 4; i++) SeatInfo(seat: i, kind: SeatKind.empty),
    ];
    await _panel(tester, _client(_room(seats: one, seated: {_ben: 0})));
    expect(find.text(s.needPlayers), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('start'))).onPressed, isNull);
    final host = _client(_room());
    await _panel(tester, host);
    expect(find.text(s.needPlayers), findsNothing);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('start'))).onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('start')));
    expect(_sent(host).whereType<StartGame>(), hasLength(1));
    await _show(tester, find.byKey(const ValueKey('see bots')));
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('see bots'))).onChanged, isNotNull);
    await tester.tap(find.byKey(const ValueKey('see bots')));
    expect(_sent(host).whereType<HostSettings>().single.seeBots, isTrue);
    await _show(tester, find.byKey(const ValueKey('add bot')));
    expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('add bot'))).onPressed, isNotNull);

    // Every seat a person's: Join game greyed out (for Dee, a spectator).
    final people = [
      for (final (i, (id, name)) in [(1, 'Ann'), (2, 'Ben'), (3, 'Cy'), (5, 'Eve')].indexed)
        SeatInfo(seat: i, kind: SeatKind.human, name: name, member: id),
    ];
    await _panel(tester, _client(_room(you: 4, seats: people, seated: {1: 0, 2: 1, 3: 2})));
    await _show(tester, find.byKey(const ValueKey('join game')));
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('join game'))).onPressed, isNull);
    await _show(tester, find.byKey(const ValueKey('see bots')));
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('see bots'))).onChanged, isNull, reason: 'not the host');
    // A bot's seat: it gives way.
    final dee = _client(_room(you: 4, seats: _seats.take(3).toList()));
    await _panel(tester, dee);
    await _show(tester, find.byKey(const ValueKey('join game')));
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('join game'))).onPressed, isNotNull);
    expect(find.byKey(const ValueKey('start')), findsNothing, reason: 'not the host');
    expect(find.text(s.waitingForHost), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('join game')));
    expect(_sent(dee).whereType<TakeSeat>(), hasLength(1));
  });

  testWidgets("during the game: the host's End game (not in the Seats sheet, where the table's bar has it); an empty "
      'seat taken from the sheet is queued for the next hand', (tester) async {
    final s = S.forLanguage(AppLanguage.english);
    final host = _client(_room(phase: RoomPhase.playing));
    await _panel(tester, host);
    expect(find.byKey(const ValueKey('end game')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('end game')));
    expect(_sent(host).whereType<EndGame>(), hasLength(1));
    await _panel(tester, _client(_room(phase: RoomPhase.playing)), inSheet: true);
    expect(find.byKey(const ValueKey('end game')), findsNothing);

    final dee = _client(_room(you: 4, phase: RoomPhase.playing));
    await _panel(tester, dee, inSheet: true);
    await _show(tester, find.byKey(const ValueKey('seat 3')));
    await tester.tap(find.byKey(const ValueKey('seat 3')));
    expect(_sent(dee).whereType<TakeSeat>().single.seat, 3);
    // Waiting for it (queued during the hand): says so.
    final waiting = _room(you: 4, phase: RoomPhase.playing, seats: [
      ..._seats.take(3),
      const SeatInfo(seat: 3, kind: SeatKind.empty, joining: 'Dee Longname-Example'),
    ]);
    await _panel(
      tester,
      _client(RoomState(
        code: waiting.code,
        phase: waiting.phase,
        host: waiting.host,
        you: waiting.you,
        cap: waiting.cap,
        games: waiting.games,
        game: waiting.game,
        settings: waiting.settings,
        members: [
          for (final m in waiting.members)
            m.id == 4 ? RoomMember(id: 4, name: m.name, seat: 3, waiting: true) : m,
        ],
        seats: waiting.seats,
      )),
      inSheet: true,
    );
    expect(find.text(s.joinNextHand), findsOneWidget);
  });

  testWidgets('an empty seat in the list lights up under the mouse with the hand, and a tap takes it; a taken one '
      'does not', (tester) async {
    await _panel(tester, _client(_room(you: 4)), size: const Size(420, 800));
    final empty = find.byKey(const ValueKey('seat 3'));
    await _show(tester, empty);
    expect(tester.widget<ListTile>(empty).onTap, isNotNull);
    expect(tester.widget<ListTile>(empty).hoverColor, isNotNull);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    expect(await _cursorOn(tester, mouse, empty), SystemMouseCursors.click);
    expect(tester.widget<ListTile>(find.byKey(const ValueKey('seat 0'))).onTap, isNull, reason: "Ben's, for a guest");
  });

  testWidgets("the felt: an empty seat says Sit to a spectator (a tap takes it), with the hand under the mouse; the "
      "host's empty seat offers Sit or a bot, and a bot's seat has the host's ×; the user's own seat reads Player", (
    tester,
  ) async {
    final s = S.forLanguage(AppLanguage.english);
    final dee = _client(_room(you: 4));
    await _table(tester, dee);
    final sit = find.byKey(const ValueKey('table seat 3'));
    expect(find.descendant(of: sit, matching: find.text(s.sit)), findsOneWidget);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    expect(await _cursorOn(tester, mouse, sit), SystemMouseCursors.click);
    await tester.tap(sit);
    expect(_sent(dee).whereType<TakeSeat>().single.seat, 3);
    expect(find.byKey(const ValueKey('table remove bot 1')), findsNothing, reason: 'not the host');

    // Ben (seated): his own seat reads Player; no Sit for him.
    await _table(tester, _client(_room(you: _ben)));
    expect(find.descendant(of: find.byKey(const ValueKey('table seat 0')), matching: find.text(s.you)), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('table seat 3')), matching: find.text(s.sit)), findsNothing);

    // The host: Sit or a bot on an empty seat; × on a bot.
    final ann = _client(_room());
    await _table(tester, ann);
    await tester.tap(find.byKey(const ValueKey('table seat 3')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('table sit 3')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('table bot 3')));
    await _settle(tester);
    expect(_sent(ann).whereType<AddBot>().single.seat, 3);
    await tester.tap(find.byKey(const ValueKey('table remove bot 1')));
    expect(_sent(ann).whereType<RemoveBot>().single.seat, 1);
    // The host taps another person's seat: Remove, asked first.
    await tester.tap(find.byKey(const ValueKey('table seat 0')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('remove player')), findsOneWidget);
  });
}
