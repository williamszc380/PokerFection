import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/games/big_two/online/big_two_runner.dart';
import 'package:pokerfection/src/games/big_two/online/big_two_view_codec.dart';
import 'package:pokerfection/src/kit/match.dart';
import 'package:pokerfection/src/online/games/game_envelope.dart';
import 'package:pokerfection/src/online/games/game_runner.dart';
import 'package:pokerfection/src/online/protocol.dart';

import 'runner_harness.dart';

/// Big Two's runner in a real room (see runner_harness.dart): its seats
/// and rules, whole deals with people, bots and spectators, nothing hidden
/// leaking (the other hands, the undealt cards of a two-player deal), the
/// views rebuilt for the coach, the match carried from deal to deal.

final game = BigTwoOnline();

/// A legal move for the seat seeing [view], at random (a play more often
/// than a pass, so deals end).
String pick(Map<String, Object?> view, int seat, Random random) {
  final legal = bigTwoEngineView(view).legalMoves();
  final plays = legal.where((p) => !p.isPass).toList();
  final choice = plays.isNotEmpty && (random.nextInt(3) > 0 || !legal.contains(Play.pass))
      ? plays[random.nextInt(plays.length)]
      : Play.pass;
  return bigTwoMove(seat, choice);
}

/// The seat's hand (each card as it appears in the JSON, in quotes) while
/// the deal goes on, but what everyone knows of it: the cards everyone has
/// seen (the face-up card of a three-player deal, and the starting card,
/// whose holder leads with it, two players included). A hand of only such
/// cards is still hidden as a whole (the marker, which no message holds,
/// says so).
Set<String> secrets(Map<String, Object?> view, int seat) {
  if ((view['winner']! as int) >= 0) return const {};
  final public = {view['extra'], if ((view['startSeat']! as int) >= 0) view['start']};
  return {
    '<the hand of seat $seat>',
    for (final card in view['hand']! as List)
      if (!public.contains(card)) '"$card"',
  };
}

/// The cards no seat was dealt (a two-player deal), in quotes.
Set<String> undealt(GameRunner runner) => {for (final card in (runner as BigTwoRunner).undealt) '"${card.short}"'};

RunnerHarness harness({int seed = 1}) =>
    RunnerHarness(game, pick: pick, secrets: secrets, seatViewFrom: bigTwoSeatViewFrom, undealt: undealt, seed: seed);

/// Plays until the host's device has seen [count] more deals end, as
/// [RunnerHarness.playRounds] does, but with the host's device answering
/// its bots' turns one at a time, a tenth of a second apart (on the app a
/// bot waits at least 0.6 s): three bots passing round a table would
/// otherwise send more at one instant than the room takes from a device.
Future<void> playRounds(RunnerHarness h, int count) async {
  final host = h.host;
  host.autoBots = false;
  final random = Random(count);
  final target = host.roundsOver + count;
  final answered = <(int, int)>{};
  for (var tick = 0; host.roundsOver < target; tick++) {
    expect(tick, lessThan(40000), reason: 'never: $count deals');
    await h.settle();
    final r = host.botRequests.lastOrNull;
    final answer = r != null && answered.add((r.round, r.turnId));
    if (answer) {
      host.botMovesSent++;
      host.sendGame(
        EnvelopeBotMove(round: r.round, turnId: r.turnId, seat: r.seat, move: pick(r.view, r.seat, random)),
      );
    }
    for (final d in h.devices) {
      d.send(const Ping(0));
    }
    await h.settle();
    // After a bot's move a tenth of a second; else on to the room's next timer.
    answer ? h.clock.advance(const Duration(milliseconds: 100)) : h.clock.fireNext();
  }
  await h.settle();
}

/// The room's rules with [rules] (the standard ones by default), [cards2]
/// cards each at two players and [match] as the target.
Map<String, Object?> roomRules({BigTwoRules? rules, int cards2 = 17, MatchTarget? match}) => BigTwoRoomRules(
  rules: rules ?? BigTwoRules.standard(),
  cards2: cards2,
  match: match ?? BigTwoRoomRules.defaultMatch,
).toJson();

/// A Random that gives [values] in turn (then 0s): a deal chosen card by card.
class ScriptedRandom implements Random {
  ScriptedRandom(this.values);
  final List<int> values;
  var _next = 0;

  @override
  int nextInt(int max) {
    final v = _next < values.length ? values[_next] : 0;
    _next++;
    return v % max;
  }

  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
}

/// The draws that make the runner's Fisher–Yates shuffle lay the 52 cards
/// out as [order] (card ids).
List<int> drawsFor(List<int> order) {
  final deck = [for (var i = 0; i < 52; i++) i];
  final draws = <int>[];
  for (var i = 51; i > 0; i--) {
    final j = deck.indexOf(order[i]);
    draws.add(j);
    final t = deck[i];
    deck[i] = deck[j];
    deck[j] = t;
  }
  return draws;
}

void main() {
  test('Big Two is picked with 2 seats (its range starts there), the host picks 2 to 4; the room keeps its rules '
      'strictly: the engine\'s rules, the two-player deal size and the match\'s target', () async {
    expect(game.seatsFor(game.defaultRules), isA<SeatRange>());
    final range = game.seatsFor(game.defaultRules);
    expect((range.min, range.max, range.hostPicks, range.first), (2, 4, true, 2));
    expect(OnlineSetup.defaultFor(game).seats, 2);
    expect(game.botLevels, ['easy', 'medium', 'hard']);

    final h = harness();
    final host = await h.open();
    host.send(const ChooseGame(game: 'big_two'));
    await h.settle();
    expect(host.room.game!.setup!['seats'], 2);
    expect(host.room.seats.map((s) => s.kind), [SeatKind.empty, SeatKind.empty]);
    for (final n in [3, 4, 2]) {
      await h.choose(seats: n);
      expect(host.room.seats, hasLength(n));
    }

    // The defaults: the standard rules, 17 cards each at two players, to 100 scaled with the players.
    final rules = BigTwoRoomRules.read(game.defaultRules);
    expect(rules.rules, BigTwoRules.standard());
    expect((rules.cards2, rules.match), (17, const MatchTarget(points: 100, scale: true)));
    expect(rules.rulesFor(2).cardsEach, 17);
    expect(rules.rulesFor(3).cardsEach, 17);
    expect(rules.rulesFor(4).cardsEach, 13);
    expect(rules.targetFor(4), 100);
    expect(rules.targetFor(2), 60);
    // Read back as written, whatever player count the engine's JSON says.
    final hk = roomRules(rules: BigTwoRules.hongKong(players: 2, cardsEach: 21), cards2: 13);
    expect(game.readRules(hk), hk);
    expect(BigTwoRoomRules.read(hk).rulesFor(2), BigTwoRules.hongKong(players: 2, cardsEach: 13));
    expect(game.readRules(roomRules(match: const MatchTarget())), roomRules(match: const MatchTarget()));
    // Anything else is refused.
    final ok = game.defaultRules;
    for (final bad in <Object?>[
      null,
      <String, Object?>{},
      {...ok, 'extra': 1},
      {...ok, 'cards2': 15},
      {...ok, 'cards2': '17'},
      {
        ...ok,
        'match': {'points': -5, 'scale': false},
      },
      {
        ...ok,
        'match': {'points': 100},
      },
      {
        ...ok,
        'rules': {'players': 4},
      },
      {
        ...ok,
        'rules': {
          ...(ok['rules']! as Map),
          'straights': [0, 1],
        },
      },
      {
        ...ok,
        'rules': {
          ...(ok['rules']! as Map),
          'suits': ['clubs', 'clubs', 'hearts', 'spades'],
        },
      },
    ]) {
      expect(() => game.readRules(bad), throwsFormatException, reason: '$bad');
    }
  });

  test('whole deals with a person and bots the host\'s device plays while it watches, at 2, 3 and 4 seats: every '
      'move legal, the points on the seats add up to nothing, nothing hidden leaks, every message small', () async {
    for (final seats in [2, 3, 4]) {
      final h = harness(seed: seats);
      final host = await h.open();
      await h.choose(seats: seats);
      final ben = await h.join('Ben', seated: true);
      final cy = await h.join('Cy');
      await h.addBots(seats - 1);
      await h.start();
      await playRounds(h, 6);
      h.expectClean();
      expect(host.botMovesSent, greaterThan(10));
      expect(ben.movesSent, greaterThan(3));
      final scores = [for (final s in cy.room.seats) s.score ?? 0];
      expect(scores.fold<num>(0, (a, b) => a + b), 0, reason: 'penalty points: each point won is another\'s lost');
      expect(cy.room.seats.any((s) => (s.score ?? 0) != 0), isTrue);
      // The bots' turns go to the host's device only.
      expect(ben.botRequests, isEmpty);
      expect(cy.botRequests, isEmpty);
      // A seat's view holds its own hand, and the others only as counts.
      final view = ben.states.firstWhere((s) => s.over == null).view;
      expect((view['hand']! as List).length, BigTwoRoomRules.read(game.defaultRules).rulesFor(seats).cardsEach);
      expect(view.containsKey('hands'), isFalse);
    }
  });

  test(
    '200 random deals with every mix of people and bots, the switch on and off: no hand leaks, no undealt card '
    'anywhere, each seat\'s view rebuilt from the spectators\' view, every message under 12 KB',
    timeout: const Timeout(Duration(minutes: 3)),
    () async {
      for (final (i, (seats, people)) in [(2, 1), (2, 2), (3, 1), (3, 2), (4, 1), (4, 3), (2, 1), (4, 2)].indexed) {
        final h = harness(seed: 10 + i);
        final host = await h.open();
        await h.choose(seats: seats);
        if (i.isOdd) host.send(const HostSettings(seeBots: true));
        for (var p = 0; p < people; p++) {
          await h.join('P$p', seated: true);
        }
        await h.addBots(seats - people);
        await h.join('Dee');
        await h.start();
        await playRounds(h, 25);
        h.expectClean();
        expect(h.largest, lessThan(6 * 1024));
        expect(h.runners.single.moves.length, greaterThan(25 * seats * 3));
      }
    },
  );

  test('the spectators see every person\'s hand, the bots\' only with the host\'s switch, and every hand once the '
      'deal is over; a hidden bot\'s view is not rebuilt', () {
    final runner = game.newRunner(OnlineSetup(rules: game.defaultRules, seats: 3), Random(4)) as BigTwoRunner;
    runner.startRound(1, [false, true, false]);
    final off = runner.spectatorView(seesBots: false), on = runner.spectatorView(seesBots: true);
    expect((off['hands']! as Map).keys, ['0', '2']);
    expect((on['hands']! as Map).keys, ['0', '1', '2']);
    expect(bigTwoSeatViewFrom(off, 1), isNull);
    expect(jsonEncode(bigTwoSeatViewFrom(off, 2)), jsonEncode(runner.seatView(2)));
    expect(jsonEncode(bigTwoSeatViewFrom(on, 1)), jsonEncode(runner.seatView(1)));
    while (!runner.roundOver) {
      final seat = runner.seatToAct!;
      runner.act(seat, runner.autoMove(seat));
    }
    final over = runner.spectatorView(seesBots: false);
    expect((over['hands']! as Map).keys, ['0', '1', '2']);
    expect(jsonEncode(bigTwoSeatViewFrom(over, 1)), jsonEncode(runner.seatView(1)));
    expect(runner.seatView(0)['shown'], isA<Map<String, Object?>>());
  });

  test('every seat\'s view and the spectators\' carry the starting card and its holder from the deal, two players '
      'included, the bots\' seats too, with the switch off and on', () {
    for (final seats in [2, 3, 4]) {
      for (var round = 1; round <= 8; round++) {
        final runner =
            game.newRunner(OnlineSetup(rules: game.defaultRules, seats: seats), Random(round)) as BigTwoRunner;
        runner.startRound(round, [for (var s = 0; s < seats; s++) s > 0]);
        final state = runner.state;
        if (state.isOver) continue; // a dealt dragon
        final start = state.rules.cardOf(state.startCode).short;
        for (final view in [
          for (var s = 0; s < seats; s++) runner.seatView(s),
          runner.spectatorView(seesBots: false),
          runner.spectatorView(seesBots: true),
        ]) {
          expect((view['start'], view['startSeat']), (start, state.startSeat), reason: '$seats seats, deal $round');
          expect(BigTwoWireView.read(view).visible.first, (card: Card.parse(start), seat: state.startSeat));
        }
        // Played, it leaves the visible cards (the first play must hold it).
        runner.act(state.toMove, runner.autoMove(state.toMove));
        if (!runner.roundOver) {
          final wire = BigTwoWireView.read(runner.spectatorView(seesBots: false));
          expect(wire.visible.map((v) => v.card), isNot(contains(Card.parse(start))));
        }
      }
    }
  });

  test('with a chosen leader no seat shows a starting card: two players aren\'t told it, three and four only the '
      'deck\'s lowest card', () {
    for (final seats in [2, 3, 4]) {
      final rules = BigTwoRules.standard(players: seats);
      final state = BigTwoState.deal(rules, seed: 5, leader: 1);
      for (var s = 0; s < seats; s++) {
        final view = bigTwoSeatView(state, s, deal: 1, match: null);
        expect(view['startSeat'], -1);
        expect(view['start'], seats == 2 ? isNull : '3d');
        expect(BigTwoWireView.read(view).start, isNull);
        expect(bigTwoEngineView(view).visibleCards, state.viewFor(s).visibleCards);
      }
    }
  });

  test('the engine view made from a seat\'s view has the room\'s visible cards at every step, and plays as the '
      'room does', () {
    for (final (seats, must) in [(2, true), (3, true), (4, true), (4, false), (2, false)]) {
      final rules = roomRules(rules: BigTwoRules.standard().copyWith(mustPlayStartCard: must));
      final runner = game.newRunner(OnlineSetup(rules: rules, seats: seats), Random(seats * 3)) as BigTwoRunner;
      runner.startRound(1, [for (var s = 0; s < seats; s++) true]);
      for (var turn = 0; !runner.roundOver; turn++) {
        for (var s = 0; s < seats; s++) {
          final engine = bigTwoEngineView(jsonDecode(jsonEncode(runner.seatView(s))) as Map<String, Object?>);
          final real = runner.state.viewFor(s);
          expect(engine.visibleCards, real.visibleCards, reason: '$seats seats, turn $turn, seat $s');
          expect(engine.startSeat, real.startSeat);
          expect(engine.unknownCodes(), real.unknownCodes());
        }
        final s = runner.seatToAct!;
        runner.act(s, runner.autoMove(s));
      }
    }
  });

  test('every deal draws from the room\'s Random, never from a seed; the longest move goes through the envelope', () {
    for (final seats in [2, 3, 4]) {
      expectDealsFromRandom(game, OnlineSetup(rules: game.defaultRules, seats: seats), [
        for (var s = 0; s < seats; s++) s.isOdd,
      ]);
    }
    expectMoveRoundTrips(game, '3:Td Jd Qd Kd Ad', seat: 3);
    expectMoveRoundTrips(game, '1:pass', seat: 1);
  });

  test('junk at a person\'s turn is refused one move at a time and never closes the room', () async {
    final h = harness(seed: 5);
    await h.open();
    await h.choose(seats: 3);
    final ben = await h.join('Ben', seated: true);
    await h.join('Cy');
    await h.addBots(2);
    await h.start();
    await h.expectJunkRefused(ben);
    // His turn may have come round again before he played by himself again.
    ben.actNow();
    await playRounds(h, 1);
    h.expectClean();
  });

  test('check gives a reason for anything but a legal move written the usual way, and never throws; the '
      'auto-move is always legal', () {
    final runner = game.newRunner(OnlineSetup(rules: game.defaultRules, seats: 4), Random(9)) as BigTwoRunner;
    runner.startRound(1, [false, false, true, true]);
    final seat = runner.seatToAct!;
    final hand = runner.state.handOf(seat);
    final low = hand.first;
    for (final move in [
      '',
      ':',
      '$seat:',
      '$seat:pass',
      '$seat:zz',
      '$seat:${low.short} ${low.short}',
      '${(seat + 1) % 4}:${low.short}',
      '$seat:${hand.last.short}',
      '9:${low.short}',
      '-1:pass',
      '$seat:${hand.take(6).map((c) => c.short).join(' ')}',
      '$seat:${low.short.toUpperCase()}',
      ' $seat:${low.short}',
    ]) {
      expect(runner.check(seat, move), isNotNull, reason: move);
    }
    expect(runner.check((seat + 1) % 4, '${(seat + 1) % 4}:pass'), 'not their turn');
    // The 3♦ leads the four-player deal.
    expect(runner.check(seat, '$seat:3d'), isNull);
    for (var i = 0; !runner.roundOver; i++) {
      final s = runner.seatToAct!;
      final move = runner.autoMove(s);
      expect(runner.check(s, move), isNull, reason: move);
      runner.act(s, move);
    }
    expect(runner.check(0, '0:pass'), 'the deal is over');
    expect(() => runner.act(0, '0:pass'), throwsArgumentError);
  });

  test('the deals make a match: each deal\'s penalties added to the totals until one reaches the target, the lowest '
      'total winning; the next deal starts a new match', () {
    final setup = OnlineSetup(rules: roomRules(match: const MatchTarget(points: 50)), seats: 4);
    final runner = game.newRunner(setup, Random(2)) as BigTwoRunner;
    var deals = 0;
    Map<String, Object?>? result;
    for (var round = 1; round < 60; round++) {
      runner.startRound(round, [false, true, true, true]);
      expect(runner.seatView(0)['deal'], round);
      while (!runner.roundOver) {
        final s = runner.seatToAct!;
        runner.act(s, runner.autoMove(s));
      }
      deals++;
      result = runner.roundResult();
      expect(runner.roundScores.fold<num>(0, (a, b) => a + b), 0);
      expect(result['points'], runner.state.result.penalties);
      expect(result['totals'], runner.match!.totals);
      if (result.containsKey('matchWinners')) break;
    }
    expect(result!['target'], 50);
    final totals = (result['totals']! as List).cast<int>();
    expect(totals.reduce(max), greaterThanOrEqualTo(50));
    expect(result['matchWinners'], [
      for (var s = 0; s < 4; s++)
        if (totals[s] == totals.reduce(min)) s,
    ]);
    expect(runner.match!.deals, hasLength(deals));
    // The match shows in every view, and a new one starts with the next deal.
    expect(MatchScore.fromJson(runner.seatView(1)['match'])!.totals, totals);
    runner.startRound(deals + 1, [false, true, true, true]);
    expect(runner.match!.deals, isEmpty);
    expect(MatchScore.fromJson(runner.spectatorView(seesBots: false)['match'])!.target, 50);

    // No limit: no match at all, the deals just go on.
    final free = game.newRunner(OnlineSetup(rules: roomRules(match: const MatchTarget()), seats: 2), Random(3));
    free.startRound(1, [false, true]);
    expect(free.seatView(0)['match'], isNull);
  });

  test('a dealt dragon wins before anyone plays (Hong Kong rules, 13 cards each): the round is over at once, with '
      'its points', () {
    // Seat 0 gets one card of each rank; the rest in order.
    final dragon = [for (var r = 0; r < 13; r++) r * 4];
    final order = [
      ...dragon,
      for (var id = 0; id < 52; id++)
        if (!dragon.contains(id)) id,
    ];
    final setup = OnlineSetup(rules: roomRules(rules: BigTwoRules.hongKong()), seats: 4);
    final runner = game.newRunner(setup, ScriptedRandom(drawsFor(order))) as BigTwoRunner;
    runner.startRound(1, [false, true, true, true]);
    expect(runner.roundOver, isTrue);
    expect(runner.seatToAct, isNull);
    final result = runner.roundResult();
    expect((result['winner'], result['dragon']), (0, true));
    expect(runner.roundScores.first, greaterThan(0));
  });

  test('crafted worst cases stay under 12 KB: the longest deal (passing whenever allowed) late in a long match, '
      'every hand shown to the spectators', () {
    var largest = 0;
    for (final seats in [2, 3, 4]) {
      final setup = OnlineSetup(
        rules: roomRules(rules: BigTwoRules.pusoyDos(), cards2: 21, match: const MatchTarget(points: 20, scale: true)),
        seats: seats,
      );
      final runner = game.newRunner(setup, Random(seats)) as BigTwoRunner;
      final bots = [for (var s = 0; s < seats; s++) s > 0];
      for (var round = 1; round <= 200; round++) {
        runner.startRound(round, bots);
        while (!runner.roundOver) {
          final s = runner.seatToAct!;
          // The longest deal: pass whenever allowed, else the smallest play.
          runner.act(s, runner.autoMove(s));
          for (final text in [
            jsonEncode(runner.spectatorView(seesBots: true)),
            for (var v = 0; v < seats; v++) jsonEncode(runner.seatView(v)),
          ]) {
            largest = max(largest, utf8.encode(text).length);
          }
        }
        if (runner.roundResult().containsKey('matchWinners') && round > 30) break;
      }
    }
    // The envelope around it adds well under 1 KB.
    expect(largest, lessThan(10 * 1024));
  });

  test('the room\'s game envelope carries a Big Two state for every viewer', () {
    final runner = game.newRunner(OnlineSetup(rules: game.defaultRules, seats: 2), Random(1));
    runner.startRound(1, [false, true]);
    final state = EnvelopeState(
      round: 1,
      seq: 1,
      you: null,
      turn: null,
      last: null,
      view: runner.spectatorView(seesBots: false),
      seats: const [0, 1],
    );
    final text = ServerGameMessage(game: 'big_two', gv: game.gv, body: state).encode();
    final back = (ServerMessage.decode(text) as ServerGameMessage).body as EnvelopeState;
    expect(jsonEncode(back.view), jsonEncode(state.view));
  });
}
