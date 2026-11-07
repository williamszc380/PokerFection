import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/online/online_client.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/ui/online/room_panel.dart';
import 'package:pokerfection/src/ui/online/room_shell.dart' show roomPanelColor;

import '../kit/shots.dart';

/// The room's lobby (RoomPanel, rooms v2.1) as it shows docked, over the
/// screen and in the game's Room tab: only the room's code (Invite, Close
/// Room or Leave Room), the game it plays in one line, the people and the
/// chat. No game picker, no seats, no Start: the host picks games on Home,
/// and the seats are on the room's table. 256 to 420 px wide, short to
/// tall, in every language.

const _widths = [256.0, 280.0, 360.0, 420.0];
const _heights = [276.0, 320.0, 600.0, 800.0];

const _ann = 1, _ben = 2;

/// A room as [you] sees it: Ann hosts; Ben, Cy and Dee are in it; [seats]
/// when a game is picked.
RoomState _room({
  int you = _ann,
  GameChoice? game,
  List<SeatInfo> seats = const [],
  RoomPhase phase = RoomPhase.lobby,
  Map<int, int> seated = const {},
}) => RoomState(
  code: 'K7M2Q',
  phase: phase,
  host: _ann,
  you: you,
  cap: 16,
  games: const {holdemKey: holdemGv},
  game: game,
  settings: game?.key == holdemKey ? const RoomSettings(seats: 4) : null,
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

/// [room]'s connection as its member sees it (not connected anywhere).
OnlineClient _client(RoomState room) => OnlineClient('memory')
  ..welcome = Welcome(code: room.code, token: 't', id: room.you!, isHost: room.you == room.host)
  ..status = OnlineStatus.open
  ..room = room
  ..chat.addAll(const [
    ChatLine(n: 1, name: 'Cy', text: 'gl everyone'),
    ChatLine(n: 2, name: 'Ann', text: 'GG!', you: true),
  ]);

Future<void> _pump(
  WidgetTester tester,
  OnlineClient client, {
  Size size = const Size(280, 800),
  AppLanguage language = AppLanguage.english,
  RoomPanelMode mode = RoomPanelMode.docked,
}) async {
  await pumpShot(
    tester,
    Material(color: roomPanelColor, child: RoomPanel(mode: mode, client: client)),
    size: size,
    language: language,
  );
  await tester.pump();
}

/// Lets animations run (the waiting spinners never settle).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Nothing of the game's seats or the host's game controls is in the lobby.
void _noGameControls() {
  for (final key in [
    'start',
    'end game',
    'join game',
    'leave seat',
    'add bot',
    'see bots',
    'rules',
    'seat 0',
    'seat 3',
    'game holdem',
    'game gomoku',
  ]) {
    expect(find.byKey(ValueKey(key)), findsNothing, reason: key);
  }
  expect(find.byType(ChoiceChip), findsNothing, reason: 'no game picker');
  expect(find.byType(Switch), findsNothing, reason: 'no switch');
}

void main() {
  setUpAll(loadShotFonts);

  final scenes = <String, RoomState Function()>{
    'host, no game': () => _room(),
    'guest, no game': () => _room(you: _ben),
    "host, Hold'em": () => _room(game: GameChoice.holdem, seats: _seats, seated: {_ben: 0, 3: 2}),
    'guest waiting for a seat, playing': () => _room(
      you: 4,
      game: GameChoice.holdem,
      phase: RoomPhase.playing,
      seats: [..._seats.take(3), const SeatInfo(seat: 3, kind: SeatKind.empty, joining: 'Dee Longname-Example')],
      seated: {_ben: 0, 3: 2},
    ),
  };

  for (final language in AppLanguage.values) {
    testWidgets('nothing overflows at any width (256-420) or height (276-800), docked, over the screen or as a tab, '
        'and there is nothing of a game picker or seats (${language.code})', (tester) async {
      for (final MapEntry(key: scene, value: room) in scenes.entries) {
        for (final width in _widths) {
          for (final height in _heights) {
            for (final mode in RoomPanelMode.values) {
              await _pump(tester, _client(room()), size: Size(width, height), language: language, mode: mode);
              expect(
                tester.takeException(),
                isNull,
                reason: '$scene at ${width.toInt()}x${height.toInt()} ${mode.name} (${language.code})',
              );
              _noGameControls();
            }
          }
        }
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('no game yet: the host is told to pick one on Home, a guest waits; everyone is a spectator; the chat '
      'is there', (tester) async {
    final s = S.forLanguage(AppLanguage.english);
    await _pump(tester, _client(_room()));
    expect(find.text(s.pickGameOnHome), findsOneWidget);
    expect(find.text(s.people), findsOneWidget);
    expect(find.text(s.spectators), findsOneWidget);
    expect(find.text(s.playingNow), findsNothing, reason: 'nobody plays without a game');
    for (final id in [1, 2, 3, 4]) {
      expect(find.byKey(ValueKey('member $id')), findsOneWidget);
    }
    expect(find.text(s.chat), findsOneWidget);
    expect(find.textContaining('gl everyone'), findsOneWidget);
    _noGameControls();

    await _pump(tester, _client(_room(you: _ben)));
    expect(find.text(s.waitingForGame), findsOneWidget);
    expect(find.byKey(const ValueKey('leave room')), findsOneWidget);
    expect(find.byKey(const ValueKey('close room')), findsNothing);
    expect(find.byKey(const ValueKey('invite')), findsOneWidget);
  });

  testWidgets("with a game: its name in one line, and the people: who plays (bots marked, in seat order), then who "
      'watches; the host has its badge', (tester) async {
    final s = S.forLanguage(AppLanguage.english);
    await _pump(tester, _client(_room(you: _ben, game: GameChoice.holdem, seats: _seats, seated: {_ben: 0, 3: 2})));
    expect(find.byKey(const ValueKey('room game')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('room game')), matching: find.text(s.holdem)), findsOneWidget);
    expect(find.text(s.playingNow), findsOneWidget);
    // Playing: Ben (seat 0), the bot (seat 1), Cy (seat 2); then watching: Ann (the host) and Dee.
    final order = ['member 2', 'person bot 1', 'member 3', 'member 1', 'member 4'];
    final ys = [for (final key in order) tester.getTopLeft(find.byKey(ValueKey(key))).dy];
    for (var i = 1; i < ys.length; i++) {
      expect(ys[i], greaterThan(ys[i - 1]), reason: '${order[i]} after ${order[i - 1]}');
    }
    expect(find.descendant(of: find.byKey(const ValueKey('person bot 1')), matching: find.text(s.botBadge)), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('person bot 1')), matching: find.byIcon(Icons.smart_toy_outlined)), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('member 1')), matching: find.text(s.host)), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const ValueKey('people watching')), matching: find.text(s.spectators)),
      findsOneWidget,
    );
    // No Watch without the app's room (a table shown alone, in tests).
    expect(find.byKey(const ValueKey('watch')), findsNothing);
    _noGameControls();
  });

  testWidgets('the host taps another person in the people to remove them (asked first); not a guest', (tester) async {
    final s = S.forLanguage(AppLanguage.english);
    await _pump(tester, _client(_room(game: GameChoice.holdem, seats: _seats, seated: {_ben: 0, 3: 2})));
    expect(tester.widget<ListTile>(find.byKey(const ValueKey('member 1'))).onTap, isNull, reason: 'the host itself');
    expect(tester.widget<ListTile>(find.byKey(const ValueKey('person bot 1'))).onTap, isNull, reason: 'bots are on the table');
    await tester.tap(find.byKey(const ValueKey('member 2')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('remove player')), findsOneWidget);
    expect(find.text(s.removePlayer), findsOneWidget);

    await _pump(tester, _client(_room(you: _ben, game: GameChoice.holdem, seats: _seats, seated: {_ben: 0, 3: 2})));
    expect(tester.widget<ListTile>(find.byKey(const ValueKey('member 3'))).onTap, isNull, reason: 'a guest');
  });

  testWidgets('Close Room (the host) and Leave Room (a guest) ask first; Cancel keeps the room', (tester) async {
    final s = S.forLanguage(AppLanguage.english);
    final host = _client(_room());
    await _pump(tester, host);
    await tester.tap(find.byKey(const ValueKey('close room')));
    await _settle(tester);
    expect(find.text(s.closeRoomQuestion), findsOneWidget);
    expect(find.text(s.leaveWarning(host: true)), findsOneWidget);
    await tester.tap(find.text(s.cancel));
    await _settle(tester);
    expect(host.status, OnlineStatus.open);

    final guest = _client(_room(you: _ben, game: GameChoice.holdem, seats: _seats, seated: {_ben: 0, 3: 2}));
    await _pump(tester, guest);
    await tester.tap(find.byKey(const ValueKey('leave room')));
    await _settle(tester);
    expect(find.text(s.leaveRoomQuestion), findsOneWidget);
    expect(find.text(s.leaveWarning(host: false)), findsOneWidget, reason: 'seated: the seat is given up');
    await tester.tap(find.text(s.cancel));
    await _settle(tester);
    expect(guest.status, OnlineStatus.open);
  });
}
