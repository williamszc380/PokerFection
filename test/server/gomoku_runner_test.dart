import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/gomoku/gomoku.dart';
import 'package:pokerfection/src/games/gomoku/online/gomoku_runner.dart';
import 'package:pokerfection/src/games/gomoku/online/gomoku_view_codec.dart';
import 'package:pokerfection/src/online/games/game_runner.dart';
import 'package:pokerfection/src/online/games/online_games.dart';
import 'package:pokerfection/src/online/protocol.dart';

import 'runner_harness.dart';

/// Gomoku in a room, through the runner harness: two seats (Black and
/// White, as the host's rules say), one game per round, nothing hidden,
/// every move checked, the views rebuilt from the spectators' one.

/// The rules as JSON.
Map<String, Object?> _rules({
  GomokuRules rules = GomokuRules.freestyle,
  GomokuBlackRule black = GomokuBlackRule.turns,
}) => GomokuOnlineRules(rules: rules, black: black).toJson();

/// A quick player for the harness: mostly the point that makes its own
/// longest line (so games end in a few dozen moves), sometimes a random
/// point next to a stone; always legal (Renju's forbidden points too).
String _pick(Map<String, Object?> seatView, int seat, Random random) {
  final view = GomokuOnlineView.fromJson(seatView);
  final game = view.game;
  if (game.mustPass) return 'pass';
  final size = game.rules.size;
  final me = game.toMove;
  final near = <GomokuMove>{};
  for (final m in game.moves.where((m) => !m.isPass)) {
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        final p = GomokuMove(m.x + dx, m.y + dy);
        if (game.isLegal(p)) near.add(p);
      }
    }
  }
  if (near.isEmpty) {
    final centre = GomokuMove(size ~/ 2, size ~/ 2);
    return (game.isLegal(centre) ? centre : game.legalMoves()[random.nextInt(game.legalMoves().length)]).notation;
  }
  final points = near.toList();
  if (random.nextInt(5) == 0) return points[random.nextInt(points.length)].notation;
  int run(GomokuMove p) {
    var best = 0;
    for (final (dx, dy) in const [(1, 0), (0, 1), (1, 1), (1, -1)]) {
      var n = 1;
      for (final sign in const [1, -1]) {
        var x = p.x + dx * sign, y = p.y + dy * sign;
        while (x >= 0 && y >= 0 && x < size && y < size && game.stoneAt(x, y) == me) {
          n++;
          x += dx * sign;
          y += dy * sign;
        }
      }
      best = max(best, n);
    }
    return best;
  }

  points.shuffle(random);
  points.sort((a, b) => run(b) - run(a));
  return points.first.notation;
}

RunnerHarness _harness({int seed = 1}) =>
    RunnerHarness(GomokuOnline(), pick: _pick, seatViewFrom: gomokuSeatViewFrom, seed: seed);

/// A whole 15×15 board with no five anywhere, Black and White taking
/// turns: a draw. A point is Black when (x / 2 + y) is even (runs of two at
/// most, every way), 113 Black points and 112 White.
List<String> _drawnGame() {
  final black = <String>[], white = <String>[];
  for (var y = 0; y < 15; y++) {
    for (var x = 0; x < 15; x++) {
      ((x ~/ 2 + y).isEven ? black : white).add(GomokuMove(x, y).notation);
    }
  }
  return [
    for (var i = 0; i < black.length; i++) ...[black[i], if (i < white.length) white[i]],
  ];
}

GomokuRunner _runner([Map<String, Object?>? rules, Random? random]) =>
    GomokuOnline().newRunner(OnlineSetup(rules: rules ?? _rules(), seats: 2), random ?? Random(1)) as GomokuRunner;

void main() {
  test("Gomoku is registered for rooms: two seats, Black and White, both needed; three bot levels; 5 s to see the "
      "five before the next game, 15 s at most", () {
    final game = onlineGames['gomoku']!;
    expect(game, isA<GomokuOnline>());
    expect(game.gv, gomokuOnlineGv);
    expect(game.defaultRules, {'size': 15, 'win': 'freestyle', 'black': 'turns'});
    final seats = game.seatsFor(game.defaultRules);
    expect((seats.min, seats.max, seats.hostPicks, seats.everySeat), (2, 2, false, true));
    expect(OnlineSetup.defaultFor(game).seats, 2);
    expect(game.botLevels, botLevelNames);
    expect((game.betweenRounds, game.maxBetweenRounds), (const Duration(seconds: 5), const Duration(seconds: 15)));
  });

  test('the rules are read strictly: every rule, both boards and each way of picking Black; anything else, Renju on '
      '19×19 included, is refused with a FormatException', () {
    final game = GomokuOnline();
    for (final rules in GomokuRules.presets) {
      for (final black in GomokuBlackRule.values) {
        final json = _rules(rules: rules, black: black);
        expect(game.readRules(jsonDecode(jsonEncode(json))), json);
      }
    }
    for (final bad in <Object?>[
      null,
      {},
      'freestyle',
      {'size': 15, 'win': 'freestyle'},
      {'size': 15, 'win': 'freestyle', 'black': 'turns', 'extra': 1},
      {'size': 17, 'win': 'freestyle', 'black': 'turns'},
      {'size': 15.0, 'win': 'freestyle', 'black': 'turns'},
      {'size': '15', 'win': 'freestyle', 'black': 'turns'},
      {'size': 15, 'win': 'caro', 'black': 'turns'},
      {'size': 15, 'win': 'freestyle', 'black': 'host'},
      {'size': 19, 'win': 'renju', 'black': 'turns'},
    ]) {
      expect(() => game.readRules(bad), throwsFormatException, reason: '$bad');
    }
  });

  test('whole games with a person and a bot the host\'s device plays while a spectator watches: every move legal, '
      'the wins kept on the seats, the views rebuilt from the spectators\' one, every message small', () async {
    final h = _harness();
    final host = await h.open();
    await h.choose();
    final ben = await h.join('Ben', seated: true);
    final cy = await h.join('Cy');
    await h.addBots(1);
    await h.start();
    await h.playRounds(6);
    h.expectClean();
    expect(host.botMovesSent, greaterThan(10));
    expect(ben.movesSent, greaterThan(10));
    final runner = h.runners.single;
    // Every round was played to a five (the quick players never fill the board).
    final overs = [
      for (final s in cy.states)
        if (s.over != null) s.over!,
    ];
    expect(overs.length, greaterThanOrEqualTo(6));
    for (final over in overs) {
      expect(over.result.keys, ['winner']);
      expect([...over.scores]..sort(), [0, 1]);
    }
    // The seats' scores are the wins.
    final wins = [for (final s in cy.room.seats) s.score ?? 0];
    expect(wins.fold<num>(0, (a, b) => a + b), greaterThanOrEqualTo(6));
    // The spectators' view is the whole game, and each seat's is the same with its seat.
    final last = cy.state!;
    expect(last.view.keys.toSet(), {'rules', 'black', 'moves'});
    expect(ben.state!.view['you'], ben.state!.you);
    expect(runner.moves, isNotEmpty);
    expect(ben.botRequests, isEmpty);
    expect(cy.botRequests, isEmpty);
  });

  test('games under every rule and board, the switch on and off, people and bots in every mix: no problem found, '
      'every message under 2 KB', () async {
    final cases = [
      (GomokuRules.freestyle, GomokuBlackRule.turns),
      (GomokuRules.standard, GomokuBlackRule.random),
      (GomokuRules.renju, GomokuBlackRule.loser),
      (GomokuRules.freestyle19, GomokuBlackRule.loser),
      (GomokuRules.standard19, GomokuBlackRule.turns),
    ];
    for (final (i, (rules, black)) in cases.indexed) {
      final h = _harness(seed: i + 1);
      final host = await h.open();
      await h.choose(
        rules: _rules(rules: rules, black: black),
      );
      if (i.isEven) host.send(const HostSettings(seeBots: true));
      if (i < 3) await h.join('Ben', seated: true);
      if (i == 0) await h.join('Cy', seated: true);
      await h.addBots(i == 0 ? 0 : (i < 3 ? 1 : 2));
      await h.join('Dee');
      await h.start();
      await h.playRounds(4);
      h.expectClean();
      expect(h.largest, lessThan(2048), reason: rules.label);
    }
  });

  test('junk sent at a seat\'s turns is refused, one move at a time, and never closes the room', () async {
    final h = _harness(seed: 7);
    await h.open();
    await h.choose(rules: _rules(rules: GomokuRules.renju));
    final ben = await h.join('Ben', seated: true);
    await h.addBots(1);
    await h.start();
    await h.expectJunkRefused(ben);
    h.expectClean();
  });

  test('nothing is dealt, so nothing is drawn from the room\'s Random unless the rules pick Black at random; then '
      'every pick comes from it (never a seed); the longest moves go through the envelope', () {
    final game = GomokuOnline();
    expectDealsFromRandom(game, OnlineSetup(rules: _rules(black: GomokuBlackRule.random), seats: 2), [false, true]);
    for (final black in [GomokuBlackRule.turns, GomokuBlackRule.loser]) {
      final random = RecordingRandom(Random(3));
      final runner = game.newRunner(OnlineSetup(rules: _rules(black: black), seats: 2), random);
      for (var round = 1; round <= 5; round++) {
        runner.startRound(round, [false, true]);
      }
      expect(random.draws, 0, reason: black.name);
    }
    expectMoveRoundTrips(game, 'pass', seat: 1);
    expectMoveRoundTrips(game, 's19');
  });

  test('a move is checked, never thrown at: out of turn, taken, off the board, a pass not forced, Renju\'s '
      'forbidden points, other spellings and anything after the five are refused with a reason', () {
    final runner = _runner(_rules(rules: GomokuRules.renju));
    expect(runner.check(0, 'h8'), isNotNull, reason: 'before the first game');
    expect(runner.seatToAct, isNull);
    runner.startRound(1, [false, false]);
    expect((runner.black, runner.seatToAct), (0, 0));
    expect(runner.check(1, 'h8'), 'not their turn');
    for (final spelling in ['H8', 'h08', ' h8', 'h8 ', 'h-8', '8h', 'pass ', 'PASS', '', 'h', 'h8h9']) {
      expect(runner.check(0, spelling), 'not a point', reason: spelling);
    }
    expect(runner.check(0, 'p8'), 'off the board');
    expect(runner.check(0, 'a16'), 'off the board');
    expect(runner.check(0, 'pass'), isNotNull);
    expect(() => runner.act(0, 'pass'), throwsArgumentError);
    // Black builds a double three at i8 (forbidden in Renju).
    for (final (seat, move) in [
      (0, 'h8'),
      (1, 'a1'),
      (0, 'j8'),
      (1, 'a2'),
      (0, 'i9'),
      (1, 'a3'),
      (0, 'i10'),
      (1, 'a4'),
    ]) {
      expect(runner.check(seat, move), isNull, reason: move);
      runner.act(seat, move);
    }
    expect(runner.check(0, 'h8'), 'taken');
    expect(runner.check(0, 'i8'), 'forbidden');
    expect(runner.autoMove(0), isNot('i8'));
    expect(runner.check(0, runner.autoMove(0)), isNull);
    // White makes five.
    for (final (seat, move) in [(0, 'm13'), (1, 'a5')]) {
      runner.act(seat, move);
    }
    expect(runner.roundOver, isTrue);
    expect(runner.seatToAct, isNull);
    expect(runner.check(0, 'n14'), 'the game is over');
    expect(runner.roundResult(), {'winner': 1});
    expect(runner.roundScores, [0, 1]);
  });

  test('Black follows the host\'s rule: the seats take turns; at random each game; or the loser of the last game '
      'has it (after a draw it changes seats)', () {
    final turns = _runner(_rules());
    final blacks = <int>[];
    for (var round = 1; round <= 4; round++) {
      turns.startRound(round, [false, true]);
      blacks.add(turns.black);
      expect(turns.seatView(1)['black'], turns.black);
      expect(turns.seatToAct, turns.black, reason: 'Black moves first');
    }
    expect(blacks, [0, 1, 0, 1]);

    final random = _runner(_rules(black: GomokuBlackRule.random), Random(5));
    final picks = {
      for (var round = 1; round <= 30; round++) (random..startRound(round, [false, false])).black,
    };
    expect(picks, {0, 1});

    final loser = _runner(_rules(black: GomokuBlackRule.loser));
    loser.startRound(1, [false, false]);
    expect(loser.black, 0, reason: 'the first seat in the first game');
    // Seat 0 (Black) wins with five across.
    for (final move in 'a1 a2 b1 b2 c1 c2 d1 d2 e1'.split(' ')) {
      loser.act(loser.seatToAct!, move);
    }
    expect(loser.roundResult(), {'winner': 0});
    loser.startRound(2, [false, false]);
    expect(loser.black, 1, reason: 'the loser has Black');
    // A drawn game: the whole board, no five.
    for (final move in _drawnGame()) {
      loser.act(loser.seatToAct!, move);
    }
    expect(loser.roundOver, isTrue);
    expect(loser.roundResult(), {'draw': true});
    expect(loser.roundScores, [0, 0]);
    loser.startRound(3, [false, false]);
    expect(loser.black, 0, reason: 'after a draw Black changes seats');
  });

  test('a player away gets a legal move at once and with no search: the centre, then next to the last stone; a '
      'whole game of them takes no time', () {
    final runner = _runner(_rules(rules: GomokuRules.standard19));
    runner.startRound(1, [false, false]);
    expect(runner.autoMove(0), 'j10', reason: 'the centre of an empty board');
    runner.act(0, 'j10');
    final reply = GomokuMove.parse(runner.autoMove(1));
    expect(max((reply.x - 9).abs(), (reply.y - 9).abs()), 1, reason: 'next to the last stone');
    final clock = Stopwatch()..start();
    for (var i = 0; i < 300 && !runner.roundOver; i++) {
      final seat = runner.seatToAct!;
      runner.act(seat, runner.autoMove(seat));
    }
    expect(clock.elapsedMilliseconds, lessThan(3000), reason: 'well under 10 ms a move');
  });

  test('the views hold the whole game and nothing else: the rules, Black\'s seat and the moves (a seat\'s also its '
      'seat); the longest, a full 19×19 board, stays under 2 KB', () {
    final runner = _runner(_rules(rules: GomokuRules.freestyle19, black: GomokuBlackRule.loser));
    runner.startRound(1, [true, false]);
    for (final move in ['j10', 'k11']) {
      runner.act(runner.seatToAct!, move);
    }
    final spectators = runner.spectatorView(seesBots: false);
    expect(spectators, {
      'rules': {'size': 19, 'win': 'freestyle'},
      'black': 0,
      'moves': 'j10 k11',
    });
    expect(runner.spectatorView(seesBots: true), spectators, reason: 'the bots hide nothing');
    for (final seat in [0, 1]) {
      expect(runner.seatView(seat), {...spectators, 'you': seat});
      expect(gomokuSeatViewFrom(spectators, seat), runner.seatView(seat));
    }
    final read = GomokuOnlineView.fromJson(runner.seatView(1));
    expect((read.you, read.black, read.seatToAct, read.game.moves.length), (1, 0, 0, 2));
    // The longest view: every point of a 19×19 board named ("a10" and up are three characters).
    final full = {
      ...spectators,
      'moves': [for (var i = 0; i < 361; i++) 's19'].join(' '),
      'you': 1,
    };
    expect(utf8.encode(jsonEncode(full)).length, lessThan(2048));
    expect(() => GomokuOnlineView.fromJson({...spectators, 'moves': 'j10 j10'}), throwsFormatException);
    expect(() => GomokuOnlineView.fromJson({...spectators, 'black': 2}), throwsFormatException);
  });
}
