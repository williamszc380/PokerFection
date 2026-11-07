import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/engine/actions.dart';
import 'package:pokerfection/src/online/games/game_envelope.dart';
import 'package:pokerfection/src/online/games/game_runner.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/online/timing.dart';

import 'fake_runner.dart';
import 'runner_harness.dart';

/// A harness with High card ([seats]: its seat range).
RunnerHarness _harness({
  SeatRange seats = const SeatRange(2, 3, hostPicks: true, start: 2),
  int seed = 1,
  int openingMs = 0,
}) =>
    RunnerHarness(
      HighCardGame(seats: seats, openingMs: openingMs),
      pick: highCardPick,
      secrets: highCardSecrets,
      seatViewFrom: highCardSeatViewFrom,
      seed: seed,
    );

void main() {
  test('a game picked from a room with no game comes with its own empty seats, as many as its range starts with '
      '(2 of 2–3 here, as Big Two will); the host picks another count', () async {
    final h = _harness();
    final host = await h.open();
    expect(host.room.game, isNull);
    host.send(const ChooseGame(game: 'gomoku'));
    await h.settle();
    final room = host.room;
    expect((room.game!.key, room.game!.gv, room.settings), ('gomoku', 1, null));
    expect(room.game!.setup, {'seats': 2, 'turnLimit': 0, 'rules': <String, Object?>{}});
    expect(room.seats.map((s) => s.kind), [SeatKind.empty, SeatKind.empty]);
    expect(room.members.single.seat, isNull, reason: 'everyone still watches');
    await h.choose(seats: 3, turnLimit: 30);
    expect(host.room.seats, hasLength(3));
    expect(host.room.game!.setup!['turnLimit'], 30);
    expect(OnlineSetup.defaultFor(HighCardGame()).seats, 2);
    expect(OnlineSetup.defaultFor(HighCardGame(seats: const SeatRange(2, 4, hostPicks: true))).seats, 4);
    expect(OnlineSetup.defaultFor(HighCardGame(seats: const SeatRange(3, 3, start: 2))).seats, 3);
  });

  test('switching from a runner game to Hold\'em and back clears the seats each time', () async {
    final h = _harness();
    final host = await h.open();
    await h.choose();
    final ben = await h.join('Ben', seated: true);
    await h.addBots(1);
    expect(host.room.seats.map((s) => s.kind), [SeatKind.human, SeatKind.bot]);
    host.send(const ChooseGame(game: holdemKey));
    await h.settle();
    expect(ben.room.game!.key, holdemKey);
    expect(ben.room.settings, isNotNull);
    expect(ben.room.seats.map((s) => s.kind), everyElement(SeatKind.empty));
    expect(ben.room.members.map((m) => m.seat), [null, null]);
    ben.send(const TakeSeat());
    host.send(const AddBot(style: 'tag'));
    await h.settle();
    expect(ben.room.taken, 2);
    await h.choose();
    expect(ben.room.game!.key, 'gomoku');
    expect(ben.room.settings, isNull);
    expect(ben.room.seats.map((s) => s.kind), [SeatKind.empty, SeatKind.empty]);
    expect(ben.room.members.map((m) => m.seat), [null, null]);
    h.expectClean();
  });

  test('whole rounds with a person and a bot the host\'s device plays while it watches: every move legal, scores '
      'kept on the seats, nothing hidden leaks, every message small', () async {
    final h = _harness();
    final host = await h.open();
    await h.choose(seats: 3);
    final ben = await h.join('Ben', seated: true);
    final cy = await h.join('Cy');
    await h.addBots(2);
    await h.start();
    await h.playRounds(40);
    h.expectClean();
    expect(host.botMovesSent, greaterThan(20));
    expect(ben.movesSent, greaterThan(20));
    final runner = h.runners.single;
    expect(runner.moves.length, greaterThanOrEqualTo(120));
    // The room played nothing itself: every move was a device's.
    for (final s in host.states) {
      if (s.last case final last?) expect(last.cause, EnvelopeCause.act);
    }
    // Scores on the seats add up to nothing (each point won is another's lost).
    final scores = [for (final s in cy.room.seats) s.score ?? 0];
    expect(scores.fold<num>(0, (a, b) => a + b), 0);
    expect(cy.room.seats.any((s) => s.score != null && s.score != 0), isTrue);
    // The lineup goes with every view; the bots' turns go to the host's device only.
    expect(cy.state!.seats, [0, 1, 2]);
    expect(ben.botRequests, isEmpty);
    expect(cy.botRequests, isEmpty);
  });

  test('200 random rounds with every mix of people and bots, the switch on and off: no leaks, the acting seat\'s '
      'view rebuilt from the spectators\' view, every message under 12 KB', () async {
    for (final seed in [1, 2, 3, 4]) {
      final h = _harness(seed: seed);
      final host = await h.open();
      await h.choose(seats: 3);
      if (seed.isEven) host.send(const HostSettings(seeBots: true));
      await h.join('Ben', seated: true);
      if (seed > 2) await h.join('Cy', seated: true);
      await h.addBots(seed > 2 ? 1 : 2);
      await h.join('Dee');
      await h.start();
      await h.playRounds(50);
      h.expectClean();
      expect(h.largest, lessThan(2048));
    }
  });

  test('every deal draws from the room\'s Random, never from a seed; the longest move goes through the envelope', () {
    final game = HighCardGame();
    expectDealsFromRandom(game, OnlineSetup.defaultFor(game), [false, true]);
    expectMoveRoundTrips(game, '2:raise', seat: 2);
    expectMoveRoundTrips(game, '0:${'x' * (maxMoveLength - 2)}');
  });

  test('the harness finds a view too big, and a view that shows a hidden card', () async {
    final big = _harness();
    await big.open();
    await big.choose(rules: {'pad': 13000});
    await big.join('Ben', seated: true);
    await big.addBots(1);
    await big.start();
    await big.playRounds(1);
    expect(big.problems, isNotEmpty);
    expect(big.largest, greaterThan(12 * 1024));

    final leaky = RunnerHarness(
      HighCardGame(),
      pick: highCardPick,
      // A codec that "forgets" the switch: rebuilding a bot's view always.
      secrets: highCardSecrets,
      seatViewFrom: (view, seat) => {...?highCardSeatViewFrom(view, seat), 'you': seat},
    );
    await leaky.open();
    await leaky.choose();
    await leaky.join('Ben', seated: true);
    await leaky.addBots(1);
    await leaky.start();
    await leaky.playRounds(2);
    expect(leaky.problems, isNotEmpty);
  });

  test('the spectators\' copy is one string for them all, with a coach seed; a seat\'s copy has none; seq counts '
      'each round\'s messages', () async {
    final h = _harness();
    final host = await h.open();
    await h.choose();
    final ben = await h.join('Ben', seated: true);
    final cy = await h.join('Cy'), dee = await h.join('Dee');
    await h.addBots(1);
    await h.start();
    await h.playRounds(6);
    List<String> gameTexts(HarnessDevice d) => [
      for (final t in d.texts)
        if (t.startsWith('{"t":"g"')) t,
    ];
    final watched = gameTexts(cy);
    expect(watched, isNotEmpty);
    expect(gameTexts(dee), watched);
    // The host watches too: its copy is the spectators' (plus the bots' turns).
    expect([
      for (final t in gameTexts(host))
        if (!t.contains('"k":"bot"')) t,
    ], watched);
    for (final s in cy.states) {
      expect(s.you, isNull);
      expect(s.coachSeed, isNotNull);
    }
    for (final s in ben.states) {
      expect(s.you, 0);
      expect(s.coachSeed, isNull);
    }
    for (final d in [ben, cy]) {
      var round = 0, seq = 0;
      for (final s in d.states) {
        if (s.round != round) {
          expect(s.round, round + 1);
          expect(s.seq, 1);
        } else {
          expect(s.seq, seq + 1);
        }
        (round, seq) = (s.round, s.seq);
      }
    }
    h.expectClean();
  });

  test('stale, duplicate and out-of-turn moves are refused; after 3 refused moves at a turn more are ignored, until '
      'a fresh copy', () async {
    final h = _harness();
    final host = await h.open();
    await h.choose();
    final ben = await h.join('Ben', seated: true);
    final cy = await h.join('Cy', seated: true);
    ben.autoPlay = cy.autoPlay = false;
    await h.start();
    await h.until(() => ben.state != null, 'round 1');
    final s = ben.state!;
    expect(s.turn!.seat, 0, reason: 'Ben has hand seat 0 and acts first in round 1');
    Rejected last(HarnessDevice d) => d.all<Rejected>().last;

    cy.play('1:raise');
    await h.settle();
    expect((last(cy).reason, last(cy).turnId), (Rejection.notYourTurn, s.turn!.turnId));
    ben.sendGame(EnvelopeMove(round: s.round, turnId: s.turn!.turnId + 1, move: '0:raise'));
    await h.settle();
    expect(last(ben).reason, Rejection.stale);
    ben.sendGame(EnvelopeMove(round: s.round + 1, turnId: s.turn!.turnId, move: '0:raise'));
    await h.settle();
    expect(last(ben).reason, Rejection.stale);
    ben.send(
      GameMessage(
        game: 'big_two',
        gv: 1,
        body: EnvelopeMove(round: 1, turnId: s.turn!.turnId, move: '0:raise'),
      ),
    );
    ben.send(
      GameMessage(
        game: 'gomoku',
        gv: 2,
        body: EnvelopeMove(round: 1, turnId: s.turn!.turnId, move: '0:raise'),
      ),
    );
    await h.settle();
    expect(ben.all<Rejected>().reversed.take(2).map((r) => r.reason), [Rejection.stale, Rejection.stale]);
    host.sendGame(EnvelopeBotMove(round: 1, turnId: s.turn!.turnId, seat: 0, move: '0:raise'));
    await h.settle();
    expect(last(host).reason, Rejection.notYourTurn, reason: 'seat 0 is no bot');

    for (var i = 0; i < 3; i++) {
      ben.play('0:check');
    }
    ben.play('0:raise');
    await h.settle();
    expect(ben.all<Rejected>().reversed.take(4).map((r) => r.reason), [
      Rejection.rateLimited,
      Rejection.illegal,
      Rejection.illegal,
      Rejection.illegal,
    ]);
    expect(h.runners.single.moves, isEmpty);
    ben.send(const Resync());
    await h.settle();
    ben.play('0:raise');
    await h.settle();
    expect(h.runners.single.moves, [(0, '0:raise')]);
    ben.sendGame(EnvelopeMove(round: s.round, turnId: s.turn!.turnId, move: '0:raise'));
    await h.settle();
    expect(last(ben).reason, Rejection.stale, reason: 'a duplicate: that turn is gone');
    // Poker's moves are for a hand that isn't there.
    ben.send(const Act(hand: 1, turnId: 1, action: PlayerAction.fold()));
    ben.send(const Rebuy());
    await h.settle();
    expect(ben.all<Rejected>().reversed.take(2).map((r) => r.reason), [Rejection.illegal, Rejection.stale]);
    expect(h.problems, isEmpty);
  });

  /// Ben (hand seat 0, first to act in round 1) and a bot (seat 1), the host watching; [ben] doesn't play.
  Future<(RunnerHarness, HarnessDevice, HarnessDevice, HarnessDevice)> benAndBot() async {
    final h = _harness();
    final host = await h.open();
    await h.choose();
    final ben = await h.join('Ben', seated: true);
    final cy = await h.join('Cy');
    await h.addBots(1);
    ben.autoPlay = false;
    await h.start();
    await h.until(() => ben.state?.turn?.seat == 0, "Ben's turn");
    return (h, host, ben, cy);
  }

  test('a player away at their turn is played for after a few seconds', () async {
    final (h, _, ben, cy) = await benAndBot();
    await h.drop(ben);
    await h.pass(OnlineTiming.awayLimit - const Duration(milliseconds: 500));
    expect(h.runners.single.moves, isEmpty);
    await h.pass(const Duration(seconds: 1));
    expect(h.runners.single.moves.first, (0, '0:fold'));
    expect(cy.states.firstWhere((s) => s.last != null).last!.cause, EnvelopeCause.away);
    h.expectClean();
  });

  test("a player who left mid-round is played for at once, and their seat is free at the round's end", () async {
    final (h, _, ben, cy) = await benAndBot();
    ben.send(const Leave());
    await h.settle();
    await h.until(() => h.runners.single.moves.isNotEmpty, 'a move');
    expect(h.clock.nowMs, lessThan(1000));
    expect(cy.states.firstWhere((s) => s.last != null).last!.cause, EnvelopeCause.left);
    await h.until(() => cy.state!.over != null, 'round over');
    expect(cy.room.seats[0].kind, SeatKind.empty);
    expect(cy.room.members.map((m) => m.name), isNot(contains('Ben')));
    expect(cy.room.paused, isTrue, reason: 'every seat must play');
  });

  test("the bot moves after a moment while the host is away; the host back in a bot's turn is asked again", () async {
    final (h, host, ben, cy) = await benAndBot();
    host.autoBots = false;
    ben.play('0:raise');
    await h.until(() => host.botRequests.isNotEmpty, "the bot's turn");
    final asked = host.botRequests.single;
    expect((asked.seat, asked.level), (1, 'easy'));
    expect(asked.view['card'], isA<String>(), reason: "the bot's own view");
    final token = host.welcome.token, code = host.welcome.code;
    await h.drop(host);
    final back = await h.rejoin('Ann', code, token, host: true);
    expect(back.welcome.isHost, isTrue);
    final again = back.botRequests.single;
    expect((again.turnId, again.seat), (asked.turnId, 1), reason: 'the same turn, asked again');
    // Answered now: the bot's move is the host's device's.
    back.sendGame(EnvelopeBotMove(round: again.round, turnId: again.turnId, seat: 1, move: '1:fold'));
    await h.settle();
    expect(cy.state!.last, isA<EnvelopeLast>().having((l) => (l.seat, l.cause), 'last', (1, EnvelopeCause.act)));

    // Round 2 (the bot first): the host goes away and stays away; the room plays the bot after a moment.
    back.autoBots = false;
    await h.until(() => cy.state!.round == 2, 'round 2');
    expect(cy.state!.turn!.seat, 1);
    await h.drop(back);
    final at = h.clock.nowMs;
    await h.until(() => cy.state!.last != null, 'the bot played for');
    expect(cy.state!.last!.cause, EnvelopeCause.hostAway);
    expect(h.clock.nowMs - at, lessThanOrEqualTo(OnlineTiming.hostAwayBotLimit.inMilliseconds + 400));
  });

  test('between rounds a seat taken or given up counts at once (the next round deals to it); during a round it '
      'waits for the round\'s end, and a bot gives its seat to a person', () async {
    final h = _harness();
    final host = await h.open();
    await h.choose(seats: 3);
    final ben = await h.join('Ben', seated: true);
    await h.addBots(2);
    final cy = await h.join('Cy');
    final dee = await h.join('Dee');
    ben.autoPlay = false;
    await h.start();
    await h.until(() => cy.state != null, 'round 1');
    // Mid-round: Cy asks for a seat: every seat is taken, so a bot's (the highest) gives way at the round's end.
    cy.send(const TakeSeat());
    await h.settle();
    expect(cy.room.me!.waiting, isTrue);
    expect(cy.room.seats[2].leaving, isTrue);
    expect(cy.room.seats[2].joining, 'Cy');
    ben.autoPlay = true;
    ben.actNow();
    await h.until(() => cy.state!.over != null, 'round 1 over');
    expect(cy.room.seats[2].member, cy.id);
    expect(cy.room.me!.waiting, isFalse);
    // Between rounds: Ben gives his seat up and Dee takes it, at once; round 2 deals to Dee.
    ben.send(const LeaveSeat());
    await h.settle();
    expect(ben.room.me!.seat, isNull);
    dee.autoPlay = false;
    dee.send(const TakeSeat(0));
    await h.settle();
    expect(dee.room.seats[0].member, dee.id);
    await h.until(() => dee.state!.round == 2, 'round 2');
    expect(dee.state!.you, 0);
    expect(cy.state!.you, 2);
    expect(ben.state!.you, isNull);
    expect(host.room.seats.map((s) => s.kind), [SeatKind.human, SeatKind.bot, SeatKind.human]);
    // Mid-round: Dee gives the seat up: she plays the round out (leaving), and watches from its end.
    dee.send(const LeaveSeat());
    await h.settle();
    expect(dee.room.seats[0].leaving, isTrue);
    await h.until(() => dee.state!.turn?.seat == 0, "Dee's turn");
    expect(dee.state!.you, 0, reason: 'she still plays the round');
    dee.actNow();
    await h.until(() => dee.state!.over != null, 'round 2 over');
    expect(dee.room.me!.seat, isNull);
    h.expectClean();
  });

  test('a game every seat must play waits for players when one leaves, and goes on when the seat is taken; the '
      'host ends the game between rounds at once, during a round at its end', () async {
    final h = _harness(seats: const SeatRange(2, 2));
    final host = await h.open();
    await h.choose();
    expect(host.room.seats, hasLength(2));
    final ben = await h.join('Ben', seated: true);
    host.send(const StartGame());
    await h.settle();
    expect(host.lastRejection, Rejection.illegal, reason: 'every seat must be taken');
    host.rejected.clear();
    final cy = await h.join('Cy', seated: true);
    await h.start();
    await h.playRounds(2);
    await h.until(() => cy.state!.over != null, 'between rounds');
    cy.send(const LeaveSeat());
    await h.settle();
    expect(host.room.paused, isTrue);
    final dee = await h.join('Dee', seated: true);
    await h.until(() => dee.state != null && dee.state!.you != null, 'Dee dealt in');
    expect(host.room.paused, isFalse);

    // During a round: the game ends at its end.
    ben.autoPlay = dee.autoPlay = false;
    await h.until(() => dee.state!.over == null, 'a round');
    host.send(const EndGame());
    await h.settle();
    expect(host.room.phase, RoomPhase.playing);
    ben.autoPlay = dee.autoPlay = true;
    ben.actNow();
    dee.actNow();
    await h.until(() => host.room.phase == RoomPhase.lobby, 'the lobby');
    expect(host.room.seats.map((s) => s.score), [null, null], reason: 'scores go with the game');
    expect(host.room.seats.map((s) => s.member), [ben.id, dee.id], reason: 'the seats stay');
    // Between rounds: at once.
    await h.start();
    await h.until(() => host.state!.over != null && host.room.phase == RoomPhase.playing, 'a round over');
    host.send(const EndGame());
    await h.settle();
    expect(host.room.phase, RoomPhase.lobby);
    h.expectClean();
  });

  test('round 2 is dealt once every seated person is ready, or at the game\'s latest; a spectator joining '
      'mid-game gets the round as spectators see it', () async {
    final h = _harness();
    final host = await h.open();
    await h.choose();
    final ben = await h.join('Ben', seated: true);
    await h.addBots(1);
    ben.autoReady = false;
    await h.start();
    await h.until(() => ben.state?.over != null, 'round 1 over');
    final overAt = h.clock.nowMs;
    await h.until(() => ben.state!.round == 2, 'round 2');
    expect(h.clock.nowMs - overAt, greaterThanOrEqualTo(6000), reason: 'dealt at the latest: Ben never said Ready');
    ben.autoReady = true;
    await h.until(() => ben.state!.round == 2 && ben.state!.over != null, 'round 2 over');
    final again = h.clock.nowMs;
    await h.until(() => ben.state!.round == 3, 'round 3');
    expect(h.clock.nowMs - again, lessThan(6000));
    final eve = await h.join('Eve');
    expect(eve.state, isNotNull);
    expect(eve.state!.you, isNull);
    expect(eve.state!.view['hands'], isA<Map<Object?, Object?>>());
    expect(host.state!.round, eve.state!.round);
    h.expectClean();
  });

  test('the host removes a player mid-round: they play the round out, then go (barred); a spectator at once', () async {
    final h = _harness(seats: const SeatRange(1, 3, hostPicks: true, everySeat: false));
    final host = await h.open();
    await h.choose(seats: 3);
    final ben = await h.join('Ben', seated: true);
    final cy = await h.join('Cy', seated: true);
    final dee = await h.join('Dee');
    ben.autoPlay = false;
    await h.start();
    await h.until(() => ben.state?.turn?.seat == 0, "Ben's turn");
    host.send(RemoveMember(id: ben.id, name: 'Ben'));
    host.send(RemoveMember(id: dee.id, name: 'Dee'));
    await h.settle();
    expect(dee.all<Closing>().single.reason, CloseReason.removed);
    expect(host.room.members.map((m) => m.name), ['Ann', 'Ben', 'Cy']);
    expect(host.room.seats[0].leaving, isTrue);
    expect(ben.all<Closing>(), isEmpty, reason: 'he plays the round out');
    ben.actNow();
    await h.until(() => cy.state!.over != null, 'round over');
    await h.settle();
    expect(ben.all<Closing>().single.reason, CloseReason.removed);
    expect(host.room.members.map((m) => m.name), ['Ann', 'Cy']);
    expect(host.room.seats[0].kind, SeatKind.empty);
    await h.until(() => cy.state!.round == 2, 'round 2, dealt to the seats taken');
    expect(cy.state!.seats, [1]);
    expect(h.problems, isEmpty);
  });

  test('the poker table and the runner table answer each other\'s messages as for a round that isn\'t there', () async {
    final h = _harness();
    final host = await h.open();
    await h.choose();
    host.send(const ChangeSettings(settings: RoomSettings()));
    host.send(const AddBot(style: 'tag'));
    await h.settle();
    expect(host.all<Rejected>().map((r) => r.reason), [Rejection.illegal, Rejection.illegal]);
    host.send(const AddBot(style: 'hard'));
    await h.settle();
    expect(host.room.seats[0].style, 'hard');
    host.send(const ChangeSettings(botStyles: {0: 'medium'}));
    await h.settle();
    expect(host.room.seats[0].style, 'medium');
    expect(jsonEncode(host.room.seats[0].toJson()), contains('Ana'), reason: 'bots have the kit\'s names');
  });

  /// The fake runner inside the harness's spy.
  HighCardRunner inner(RunnerHarness h) => h.runners.single.inner as HighCardRunner;

  test("the room's move for a seat says whether anyone is there: not for a person at the table whose clock ran out; "
      'yes for one away and for a bot while the host is away', () async {
    final h = _harness();
    final host = await h.open();
    await h.choose(turnLimit: 15);
    final ben = await h.join('Ben', seated: true);
    await h.addBots(1);
    ben.autoPlay = false;
    await h.start();
    await h.until(() => ben.state?.turn?.seat == 0, "Ben's turn");
    await h.pass(const Duration(seconds: 15));
    expect(inner(h).autoMoves, isEmpty, reason: 'the limit and the grace');
    await h.pass(const Duration(seconds: 2));
    expect(inner(h).autoMoves, [(0, false)], reason: 'Ben is at the table');
    expect(ben.states.firstWhere((s) => s.last != null).last!.cause, EnvelopeCause.timeout);
    // The bot moves; round 2 opens with the bot (hand seat 1); the host goes away.
    await h.until(() => ben.state?.over != null, 'round 1 over');
    host.autoBots = false;
    await h.until(() => ben.state?.round == 2 && ben.state?.turn?.seat == 1, 'round 2, the bot first');
    await h.drop(host);
    await h.until(() => inner(h).autoMoves.length == 2, 'the bot played for');
    expect(inner(h).autoMoves.last, (1, true), reason: 'nobody plays the bot while the host is away');
    // Ben's turn in round 2: away now.
    await h.until(() => ben.state?.turn?.seat == 0, "Ben's turn again");
    await h.drop(ben);
    await h.until(() => inner(h).autoMoves.length == 3, 'Ben played for');
    expect(inner(h).autoMoves.last, (0, true), reason: 'away');
  });

  test("a game whose deals open with a who-goes-first step: the round's first clock and its first bot wait for it, "
      "so the starter's time isn't spent watching", () async {
    final h = _harness(openingMs: 2000);
    final host = await h.open();
    await h.choose(turnLimit: 15);
    await h.addBots(1);
    final ben = await h.join('Ben', seated: true);
    host.autoBots = false;
    ben.autoPlay = false;
    await h.start();
    await h.until(() => ben.state != null, 'round 1 dealt');
    // Round 1: the bot (hand seat 0) opens.
    expect(ben.state!.turn!.seat, 0);
    expect(ben.state!.turn!.waitMs, 2000, reason: 'the clock starts after the step');
    expect(host.botRequests, isEmpty, reason: 'asked once the step is over');
    await h.pass(const Duration(milliseconds: 1750));
    expect(host.botRequests, isEmpty);
    await h.pass(const Duration(milliseconds: 500));
    expect(host.botRequests.single.seat, 0);
    host.sendGame(EnvelopeBotMove(round: 1, turnId: host.botRequests.single.turnId, seat: 0, move: '0:fold'));
    await h.settle();
    // Ben's turn later in the round has no opening wait.
    expect(ben.state!.turn!.seat, 1);
    expect(ben.state!.turn!.waitMs, lessThan(2000));
    ben.play('1:fold');
    await h.settle();

    // Round 2: Ben opens; his limit runs from the step's end.
    await h.until(() => ben.state?.round == 2, 'round 2');
    expect((ben.state!.turn!.seat, ben.state!.turn!.waitMs), (1, 2000));
    await h.pass(const Duration(seconds: 2 + 15));
    expect(ben.state!.last, isNull, reason: "Ben's 15 s (and the grace) start after the step");
    await h.pass(const Duration(seconds: 2));
    expect(ben.state!.last!.cause, EnvelopeCause.timeout);
  });
}
