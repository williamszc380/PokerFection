import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/bots/bot.dart';
import 'package:pokerfection/src/engine/actions.dart';
import 'package:pokerfection/src/engine/events.dart';
import 'package:pokerfection/src/engine/poker_hand.dart';
import 'package:pokerfection/src/game/table_session.dart';
import 'package:pokerfection/src/gto/gto_solutions.dart';
import 'package:pokerfection/src/gto/spot_strategy.dart';
import 'package:pokerfection/src/online/mirror.dart';
import 'package:pokerfection/src/online/redact.dart';

import '../helpers.dart';
import '../widget_test.dart' show testSolutions;

/// A hand as the server deals it to [n] players with [stacks] (the button
/// at [button]), handing out its batches: the deal first, then one per
/// action.
class _Server {
  _Server(int n, {required int button, required int handNumber, required List<int> stacks, required Random rng})
    : hand = PokerHand(
        stacks: stacks,
        buttonSeat: button,
        smallBlind: TableConfig.smallBlind,
        bigBlind: TableConfig.bigBlind,
        handNumber: handNumber,
        random: rng,
      ) {
    deal = hand.drainEvents();
  }

  final PokerHand hand;
  late final List<GameEvent> deal;

  List<GameEvent> act(PlayerAction action) {
    hand.act(action);
    return hand.drainEvents();
  }
}

/// A spectator's session at an [n]-handed table: nobody at it is the user,
/// every seat is played elsewhere (a person, or a bot on the host's
/// device), and the coach is on.
TableSession _spectator(int n, GtoSolutions solutions, Random rng) {
  final session = TableSession(
    TableConfig(players: [for (var s = 0; s < n; s++) PlayerInfo(name: 'P$s', stackBb: 30, remote: true)]),
    random: rng,
    solvePostflop: solutions.solvePostflop,
    solveSubgame: solutions.solveSubgame,
  )..coaching = true;
  return session;
}

/// Deals [server]'s hand to [session] as a spectator who may see [visible]
/// (the server's deal for spectators: see redact.dart), once its whole
/// preflop game is solved, as the online table does.
Future<PokerHand> _follow(TableSession session, _Server server, Set<int> visible, GtoSolutions solutions,
    {Map<int, List<dynamic>> extra = const {}}) async {
  final deal = RemoteDeal.fromBatch(
    redactBatchFor(server.deal, SpectatorViewer(visible)),
    extraKnown: {for (final s in extra.keys) s: server.hand.holeCards(s)},
  );
  session.announced = (stacks: deal.stacks, button: deal.buttonSeat);
  session.advisor = await solutions.solve(session.upcomingSpec);
  final h = session.startHand(deal);
  await session.afterAction();
  return h;
}

/// The next action as the spectator sees it: on its copy of the hand, then
/// its trackers (and the street's solve) are waited for, as the table does.
Future<void> _step(TableSession session, List<GameEvent> batch, Set<int> visible) async {
  applyBatch(session.hand!, redactBatchFor(batch, SpectatorViewer(visible)));
  await session.afterAction();
  await session.postflop?.ready;
}

/// Whether [a] is a legal move where [l] holds.
bool _allowed(LegalActions l, PlayerAction a) => switch (a.type) {
  ActionType.fold => l.canFold,
  ActionType.check => l.canCheck,
  ActionType.call => l.canCall,
  ActionType.raise => l.canRaise && a.amount >= l.minRaiseTo && a.amount <= l.maxRaiseTo,
};

void main() {
  test('nobody at the table is the user: the session follows hands it only partly sees, and never throws', () async {
    final solutions = testSolutions();
    final rng = Random(5);
    for (final n in [2, 3, 6]) {
      final session = _spectator(n, solutions, rng);
      expect(session.hero, -1);
      expect(session.needsSolver, isTrue, reason: 'the coach needs the solves');
      for (var i = 0; i < 6; i++) {
        final server = _Server(n, button: i % n, handNumber: i + 1, stacks: List.filled(n, 3000), rng: rng);
        // Some players' cards are hidden from the spectator (bots, with the host's switch off).
        final visible = {for (var s = 0; s < n; s++) if (rng.nextInt(3) > 0) s};
        final h = await _follow(session, server, visible, solutions);
        expect(session.heroSpot(), isNull);
        expect(session.isHeroTurn, isFalse);
        while (!server.hand.isOver) {
          final toAct = server.hand.toAct!;
          final spot = session.spotToAct(visible);
          if (!visible.contains(toAct)) expect(spot, isNull, reason: 'hidden cards get no answer');
          if (spot != null) expect(spot.frequencies.reduce((a, b) => a + b), closeTo(1, 1e-6));
          await _step(session, server.act(randomAction(server.hand.legalActions(), rng)), visible);
        }
        expect(h.isOver, isTrue);
      }
      // Only the user's hands are counted, and there is no user here.
      expect(session.history, isEmpty);
      expect(session.handsFinished, 0);
      expect(session.heroNet, 0);
    }
  });

  test("the coach answers for whoever acts and may be seen: the blueprint before the flop, the street's solve "
      'heads-up after it; nothing for hidden cards or in a pot of three', () async {
    final solutions = testSolutions();
    final rng = Random(8);
    // Heads-up, both seen, everyone just calls or checks: on the solved lines all the way.
    var session = _spectator(2, solutions, rng);
    var server = _Server(2, button: 0, handNumber: 1, stacks: [3000, 3000], rng: rng);
    await _follow(session, server, {0, 1}, solutions);
    final streets = <Street>{};
    while (!server.hand.isOver) {
      final spot = session.spotToAct({0, 1});
      expect(spot, isNotNull, reason: '${server.hand.street}, seat ${server.hand.toAct}');
      expect(spot!.handName, isNotEmpty);
      streets.add(server.hand.street);
      // Only the seats seen: the other player's turn has no answer.
      expect(session.spotToAct({1 - server.hand.toAct!}), isNull);
      final legal = server.hand.legalActions();
      await _step(session, server.act(legal.canCheck ? const PlayerAction.check() : const PlayerAction.call()), {0, 1});
    }
    expect(streets, containsAll([Street.preflop, Street.flop, Street.river]));

    // Three see the flop: no answer after it (multiway), but one before it.
    session = _spectator(3, solutions, rng);
    server = _Server(3, button: 0, handNumber: 1, stacks: [3000, 3000, 3000], rng: rng);
    await _follow(session, server, {0, 1, 2}, solutions);
    expect(session.spotToAct({0, 1, 2}), isNotNull, reason: 'the first to act preflop is on the blueprint');
    while (!server.hand.isOver) {
      if (server.hand.street != Street.preflop) {
        expect(session.spotToAct({0, 1, 2}), isNull);
        expect(session.postflop!.unavailable, NoAnswer.multiway);
      }
      final legal = server.hand.legalActions();
      await _step(session, server.act(legal.canCheck ? const PlayerAction.check() : const PlayerAction.call()), {0, 1, 2});
    }
  });

  test("the host's device, watching: a GTO bot in seat 0 plays by the solver from its own cards", () async {
    final solutions = testSolutions();
    final rng = Random(3);
    final session = TableSession(
      TableConfig(
        players: const [
          PlayerInfo(name: 'Heidi', stackBb: 30, style: BotStyle.gto, isBot: true),
          PlayerInfo(name: 'Ann', stackBb: 30, remote: true),
          PlayerInfo(name: 'Ben', stackBb: 30, remote: true),
        ],
      ),
      random: rng,
      solvePostflop: solutions.solvePostflop,
      solveSubgame: solutions.solveSubgame,
    );
    expect(session.hero, -1);
    expect(session.hasGtoBots, isTrue);
    expect(session.needsSolver, isTrue, reason: "the bot's solve, with the coach off");
    var sampled = 0;
    for (var i = 0; i < 8; i++) {
      // Seat 0 acts first preflop with the button on seat 0 of three (the big blind is seat 2).
      final server = _Server(3, button: 0, handNumber: i + 1, stacks: [3000, 3000, 3000], rng: rng);
      // The host's app knows its bot's cards, not the people's (the switch is off: nobody is visible).
      await _follow(session, server, const {}, solutions, extra: {0: const []});
      expect(server.hand.toAct, 0);
      expect(session.botPlaysGto, isTrue);
      final fromSolver = session.preflop!.sample(session.hand!, Random(i));
      expect(fromSolver, isNotNull, reason: 'the blueprint has a move for the bot');
      final move = session.botDecision();
      expect(_allowed(server.hand.legalActions(), move), isTrue);
      sampled++;
      // The coach sees nothing the host's app holds only for its bots.
      expect(session.spotToAct(const {}), isNull);
      while (!server.hand.isOver) {
        final batch = server.act(randomAction(server.hand.legalActions(), rng));
        await _step(session, batch, const {});
      }
    }
    expect(sampled, 8);
  });

  test('a line-up without the user is taken; the user is never anywhere but seat 0', () {
    final session = TableSession(TableConfig.quick(playerCount: 3));
    expect(session.hero, TableSession.heroSeat);
    session.changeLineup(const [
      PlayerInfo(name: 'Ann', stackBb: 100, remote: true),
      PlayerInfo(name: 'Ben', stackBb: 100, remote: true),
    ]);
    expect(session.hero, -1);
    expect(session.upcomingHeroSpec, isNull, reason: 'no user: no first decision to solve ahead');
    expect(
      () => session.changeLineup(const [
        PlayerInfo(name: 'Ann', stackBb: 100, remote: true),
        PlayerInfo(name: 'You', stackBb: 100, isHero: true),
      ]),
      throwsArgumentError,
    );
    session.changeLineup(const [
      PlayerInfo(name: 'You', stackBb: 100, isHero: true),
      PlayerInfo(name: 'Ben', stackBb: 100, remote: true),
    ]);
    expect(session.hero, 0);
  });
}
