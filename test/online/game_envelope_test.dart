import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/online/games/game_envelope.dart';
import 'package:pokerfection/src/online/games/game_runner.dart';
import 'package:pokerfection/src/online/games/online_games.dart';
import 'package:pokerfection/src/online/protocol.dart';

/// A game with rules `{"players": 2..4}` (its seats) for reading setups.
class _Cards implements OnlineGame {
  @override
  String get key => 'big_two';
  @override
  int get gv => 3;
  @override
  Map<String, Object?> get defaultRules => const {'players': 4};
  @override
  Map<String, Object?> readRules(Object? json) => switch (json) {
    {'players': final int n} when n >= 2 && n <= 4 && json.length == 1 => {'players': n},
    _ => throw const FormatException('Not the rules'),
  };
  @override
  SeatRange seatsFor(Map<String, Object?> rules) => SeatRange(rules['players']! as int, rules['players']! as int);
  @override
  List<String> get botLevels => botLevelNames;
  @override
  Duration get betweenRounds => const Duration(seconds: 4);
  @override
  Duration get maxBetweenRounds => const Duration(seconds: 15);
  @override
  GameRunner newRunner(OnlineSetup setup, Random random) => throw UnimplementedError();
}

void main() {
  test('the game envelope goes both ways and is read strictly: known games, versions, seats, moves up to 256 '
      'characters', () {
    final move = ClientMessage.decode(
      const GameMessage(
        game: 'doudizhu',
        gv: 2,
        body: EnvelopeMove(round: 3, turnId: 18, move: '1:xpair:7,7|20,23'),
      ).encode(),
    );
    expect(move, isA<GameMessage>().having((m) => (m.game, m.gv), 'game', ('doudizhu', 2)));
    expect(((move as GameMessage).body as EnvelopeMove).move, '1:xpair:7,7|20,23');
    final bot = ClientMessage.decode(
      const GameMessage(
        game: 'big_two',
        gv: 1,
        body: EnvelopeBotMove(round: 1, turnId: 2, seat: 3, move: '1:pass'),
      ).encode(),
    );
    expect(((bot as GameMessage).body as EnvelopeBotMove).seat, 3);
    expect(
      ((ClientMessage.decode(
                const GameMessage(game: 'gomoku', gv: 1, body: EnvelopeReady(4)).encode(),
              ) as GameMessage).body
              as EnvelopeReady)
          .round,
      4,
    );

    final longest = '0:${'x' * (maxMoveLength - 2)}';
    expect(longest.length, maxMoveLength);
    String g(Map<String, Object?> m, {Object game = 'gomoku', Object gv = 1}) =>
        jsonEncode({'t': 'g', 'game': game, 'gv': gv, 'm': m});
    expect(ClientMessage.decode(g({'k': 'move', 'r': 1, 'turnId': 1, 'mv': longest})), isA<GameMessage>());
    for (final bad in [
      g({'k': 'move', 'r': 1, 'turnId': 1, 'mv': '${longest}y'}),
      g({'k': 'move', 'r': 0, 'turnId': 1, 'mv': 'h8'}),
      g({'k': 'move', 'r': 1, 'turnId': 0, 'mv': 'h8'}),
      g({'k': 'move', 'r': 1, 'turnId': 1}),
      g({'k': 'botMove', 'r': 1, 'turnId': 1, 's': 8, 'mv': 'h8'}),
      g({'k': 'state', 'r': 1, 'seq': 0, 'view': <String, Object?>{}}),
      g({'k': 'jump', 'r': 1}),
      g({'k': 'ready', 'r': 1}, game: 'holdem'),
      g({'k': 'ready', 'r': 1}, game: 'chess'),
      g({'k': 'ready', 'r': 1}, gv: 0),
      g({'k': 'ready', 'r': 1}, gv: maxGameVersion + 1),
      jsonEncode({'t': 'g', 'game': 'gomoku', 'gv': 1, 'm': 'ready'}),
    ]) {
      expect(() => ClientMessage.decode(bad), throwsA(isA<ProtocolError>()), reason: bad);
    }

    // To a device: a full view each time, the spectators' with a coach seed; on the host's device a bot's turn.
    const state = EnvelopeState(
      round: 3,
      seq: 41,
      you: null,
      turn: EnvelopeTurn(seat: 1, turnId: 18, ms: null, waitMs: 400),
      last: EnvelopeLast(seat: 0, move: '0:3d 3c', cause: EnvelopeCause.redeal),
      view: {
        'hands': {'1': '3d 4c'},
      },
      over: EnvelopeOver(result: {'winner': 0}, scores: [2, -1, -1, 0]),
      coachSeed: 123456789,
    );
    final read = ServerMessage.decode(const ServerGameMessage(game: 'big_two', gv: 1, body: state).encode());
    final body = (read as ServerGameMessage).body as EnvelopeState;
    expect(jsonEncode(body.toJson()), jsonEncode(state.toJson()));
    const request = EnvelopeBotRequest(round: 3, turnId: 18, seat: 1, level: 'hard', view: {'hand': '3d'});
    final asked = ServerMessage.decode(const ServerGameMessage(game: 'big_two', gv: 1, body: request).encode());
    expect(((asked as ServerGameMessage).body as EnvelopeBotRequest).level, 'hard');
    expect(
      () => ServerMessage.decode(
        jsonEncode({
          't': 'g',
          'game': 'big_two',
          'gv': 1,
          'm': {...request.toJson(), 'level': 'gto'},
        }),
      ),
      throwsA(isA<ProtocolError>()),
    );
    expect(
      () => ServerMessage.decode(
        jsonEncode({
          't': 'g',
          'game': 'big_two',
          'gv': 1,
          'm': {'k': 'move', 'r': 1, 'turnId': 1, 'mv': 'h8'},
        }),
      ),
      throwsA(isA<ProtocolError>()),
      reason: 'a move goes to the room, never to a device',
    );
  });

  test("a game's setup is read strictly by its rules: seats the rules allow, a known time limit, nothing else", () {
    final game = _Cards();
    final setup = OnlineSetup.fromJson({
      'seats': 3,
      'turnLimit': 30,
      'rules': {'players': 3},
    }, game);
    expect(setup.toJson(), {
      'seats': 3,
      'turnLimit': 30,
      'rules': {'players': 3},
    });
    expect(OnlineSetup.defaultFor(game).toJson(), {
      'seats': 4,
      'turnLimit': 0,
      'rules': {'players': 4},
    });
    for (final bad in <Object?>[
      {
        'seats': 4,
        'rules': {'players': 3},
      },
      {
        'seats': 3,
        'turnLimit': 7,
        'rules': {'players': 3},
      },
      {
        'seats': 3,
        'rules': {'players': 5},
      },
      {
        'seats': 3,
        'rules': {'players': 3},
        'shuffle': 'seed',
      },
      {'seats': 3},
      'seats',
    ]) {
      expect(() => OnlineSetup.fromJson(bad, game), throwsFormatException, reason: '$bad');
    }
    const range = SeatRange(1, 7, hostPicks: true);
    expect([for (var n = 0; n <= 8; n++) range.allows(n)], [false, true, true, true, true, true, true, true, false]);
    expect(const SeatRange(3, 3).allows(2), isFalse);
  });

  test('v8 members: ids from 1, the seat in RoomState.members, the other games\' bot levels accepted', () {
    const room = RoomState(
      code: 'K7M2Q',
      phase: RoomPhase.lobby,
      host: 1,
      you: 2,
      cap: 8,
      seeBots: true,
      games: {holdemKey: holdemGv, 'gomoku': 1},
      game: GameChoice('gomoku', gv: 1, setup: {'seats': 2}),
      settings: RoomSettings(),
      members: [
        RoomMember(id: 1, name: 'Ann'),
        RoomMember(id: 2, name: 'Ben', seat: 1, waiting: true, status: SeatStatus.away),
      ],
      seats: [
        SeatInfo(seat: 0, kind: SeatKind.bot, name: 'Heidi', style: 'hard', score: 2.5),
        SeatInfo(seat: 1, kind: SeatKind.human, name: 'Ben', member: 2),
      ],
    );
    final read = ServerMessage.decode(room.encode()) as RoomState;
    expect(read.encode(), room.encode());
    expect((read.yourSeat, read.me!.waiting, read.me!.spectator), (1, true, true));
    expect(read.seats.first.score, 2.5);
    expect(
      ServerMessage.decode(const Welcome(code: 'K7M2Q', token: 't', id: 3, isHost: false).encode()),
      isA<Welcome>().having((w) => w.id, 'id', 3),
    );
    expect(ServerMessage.decode('{"t":"removed","id":3,"name":"Cy"}'), isA<PlayerRemoved>());
    for (final bad in [
      '{"t":"welcome","code":"K7M2Q","token":"t","id":0,"isHost":false}',
      '{"t":"removeMember","id":0,"name":"Cy"}',
      '{"t":"peek","hand":1,"s":1}',
      '{"t":"removePlayer","s":1,"name":"Cy"}',
    ]) {
      expect(
        () => bad.contains('"welcome"') ? ServerMessage.decode(bad) : ClientMessage.decode(bad),
        throwsA(isA<ProtocolError>()),
        reason: bad,
      );
    }
    expect((ClientMessage.decode('{"t":"addBot","style":"easy"}') as AddBot).style, 'easy');
    // A room is created for Hold'em: its bots have poker's styles only.
    expect(
      () => ClientMessage.decode(const CreateRoom(name: 'Ann', game: holdemKey, bots: {1: 'easy'}).encode()),
      throwsA(isA<ProtocolError>()),
    );
    expect(
      (ClientMessage.decode(const CreateRoom(name: 'Ann', game: holdemKey, bots: {1: 'gto'}).encode()) as CreateRoom)
          .bots,
      {1: 'gto'},
    );
    expect(ClientMessage.decode('{"t":"takeSeat"}'), isA<TakeSeat>().having((m) => m.seat, 'seat', isNull));
    expect(ClientMessage.decode('{"t":"takeSeat","s":3}'), isA<TakeSeat>().having((m) => m.seat, 'seat', 3));
    expect(ClientMessage.decode('{"t":"hostSettings","seeBots":true}'), isA<HostSettings>());
    expect(ClientMessage.decode('{"t":"leaveSeat"}'), isA<LeaveSeat>());
    expect(ClientMessage.decode('{"t":"endGame"}'), isA<EndGame>());
    expect(protocolVersion, 8);
    // Each game's runner registers under its own key.
    expect(onlineGames.entries.every((e) => e.key == e.value.key), isTrue);
  });
}
