import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/bots/bot.dart';
import 'package:pokerfection/src/engine/actions.dart';
import 'package:pokerfection/src/engine/events.dart';
import 'package:pokerfection/src/game/table_session.dart';
import 'package:pokerfection/src/engine/cards.dart';
import 'package:pokerfection/src/gto/combos.dart';
import 'package:pokerfection/src/gto/gto_solutions.dart';
import 'package:pokerfection/src/gto/postflop/postflop_solver.dart';
import 'package:pokerfection/src/gto/preflop/preflop_equity.dart';

void main() {
  final equity =
      PreflopEquity.fromBytes(ByteData.sublistView(File('assets/preflop_equity.bin').readAsBytesSync()));

  test('heads-up against a GTO bot: every decision after the flop gets an answer', () async {
    final solutions = GtoSolutions(
      iterations: 40,
      postflopIterations: 8,
      inBackground: false,
      loadEquity: () async => equity,
    );
    final rng = Random(2);
    final session = TableSession(
      TableConfig.quick(playerCount: 2, stackBb: 30, opponentStyle: BotStyle.gto, guessGto: true),
      random: rng,
      solvePostflop: solutions.solvePostflop,
      solveSubgame: solutions.solveSubgame,
    );
    var asked = 0, answered = 0;
    final streets = <Street>{};
    for (var i = 0; i < 15; i++) {
      session.advisor = await solutions.solve(session.upcomingSpec);
      final hand = session.startHand();
      await session.afterAction();
      while (!hand.isOver) {
        // The user's subgame (their answer, and the bot's replies to it) and
        // the street, as the table waits for them.
        await session.preflopReady;
        await session.postflop?.ready;
        final PlayerAction action;
        // Both ranges are known while everyone follows GTO, and each adds up to 100%.
        for (final seat in [0, 1]) {
          if (hand.isFolded(seat)) continue;
          final range = session.rangeOf(seat);
          expect(range, isNotNull, reason: 'hand $i, ${hand.street}, seat $seat');
          var total = 0.0;
          for (var h = 0; h < 169; h++) {
            total += range!.shareOf(h);
          }
          expect(total, closeTo(1, 1e-9));
        }
        // The user's range as shown counts a raise at any size, so it holds
        // at least the hands GTO raises this exact size with.
        if (hand.street == Street.preflop) {
          final exact = session.preflop!.rangeOf(hand, TableSession.heroSeat);
          final shown = session.rangeOf(TableSession.heroSeat);
          if (exact != null && shown != null) {
            for (var h = 0; h < 169; h++) {
              expect(shown.frequency[h], greaterThanOrEqualTo(exact[h] - 1e-9));
            }
          }
        }
        if (session.isHeroTurn) {
          final spot = session.heroSpot();
          expect(spot, isNotNull, reason: 'hand $i, ${hand.street}');
          expect(spot!.frequencies.reduce((a, b) => a + b), closeTo(1, 1e-6));
          if (hand.street != Street.preflop) {
            asked++;
            streets.add(hand.street);
            answered++;
          }
          // Follow GTO's own mix.
          var roll = rng.nextDouble(), pick = spot.actions.length - 1;
          for (var k = 0; k < spot.actions.length; k++) {
            roll -= spot.frequencies[k];
            if (roll < 0) {
              pick = k;
              break;
            }
          }
          action = spot.actions[pick].action;
        } else {
          action = session.botDecision();
        }
        hand.act(action);
        await session.afterAction();
      }
      session.finishHand();
    }
    // ignore: avoid_print
    print('Postflop decisions answered: $answered of $asked, on ${streets.map((s) => s.name).join(', ')}');
    expect(asked, greaterThan(0));
    expect(answered, asked);
  });

  test('pots with three players after the flop get an approximate answer', () async {
    final solutions = GtoSolutions(
      iterations: 30,
      postflopIterations: 4,
      inBackground: false,
      loadEquity: () async => equity,
    );
    final session = TableSession(
      TableConfig.quick(playerCount: 3, stackBb: 100, guessGto: true),
      random: Random(5),
      solvePostflop: solutions.solvePostflop,
      solveSubgame: solutions.solveSubgame,
    );
    session.advisor = await solutions.solve(session.upcomingSpec);
    final hand = session.startHand();
    // A line the preflop game has: the first player opens to 2.5 BB, both
    // others call, and three see the flop.
    while (hand.street == Street.preflop) {
      final opened = hand.log.any((e) => e is ActionTaken && (e.kind == ActionKind.raise || e.kind == ActionKind.bet));
      hand.act(opened ? const PlayerAction.call() : const PlayerAction.raiseTo(250));
      await session.afterAction();
    }
    expect([for (var s = 0; s < 3; s++) hand.isFolded(s)], [false, false, false]);
    // The user against the field.
    expect(session.postflop!.unavailable, isNull);
    expect(session.postflop!.approximate, isTrue);
    // Play it out: every decision of the user's while the field is followed
    // gets an answer, and everyone's range can be shown.
    var answered = 0;
    while (!hand.isOver) {
      await session.postflop!.ready;
      final PlayerAction action;
      if (session.isHeroTurn) {
        final spot = session.heroSpot();
        if (session.postflop!.unavailable == null) {
          expect(spot, isNotNull, reason: '${hand.street}');
          for (var seat = 0; seat < 3; seat++) {
            if (!hand.isFolded(seat)) expect(session.rangeOf(seat), isNotNull, reason: 'seat $seat');
          }
        }
        if (spot != null) answered++;
        // Check or call, to see more streets.
        action = hand.legalActions().canCheck ? const PlayerAction.check() : const PlayerAction.call();
      } else {
        action = session.botDecision();
      }
      hand.act(action);
      await session.afterAction();
    }
    expect(answered, greaterThan(0));
  });

  test('multiway hands play through, with well-formed answers against the field', () async {
    final solutions = GtoSolutions(
      iterations: 30,
      postflopIterations: 4,
      inBackground: false,
      loadEquity: () async => equity,
    );
    final rng = Random(8);
    final session = TableSession(
      TableConfig.quick(playerCount: 4, stackBb: 50, guessGto: true, opponentStyle: BotStyle.station),
      random: rng,
      solvePostflop: solutions.solvePostflop,
      solveSubgame: solutions.solveSubgame,
    );
    var answered = 0;
    for (var i = 0; i < 8; i++) {
      session.advisor = await solutions.solve(session.upcomingSpec);
      final hand = session.startHand();
      await session.afterAction();
      while (!hand.isOver) {
        await session.preflopReady;
        await session.postflop?.ready;
        final PlayerAction action;
        if (session.isHeroTurn) {
          final spot = session.heroSpot();
          final legal = hand.legalActions();
          if (spot != null && hand.street != Street.preflop) {
            answered++;
            expect(spot.frequencies.reduce((a, b) => a + b), closeTo(1, 1e-6));
            action = spot.actions[spot.frequencies.indexOf(spot.frequencies.reduce(max))].action;
          } else if (spot != null && hand.street != Street.preflop) {
            action = spot.actions[spot.frequencies.indexOf(spot.frequencies.reduce(max))].action;
          } else {
            // Before the flop, just call: many-way pots.
            action = legal.canCheck ? const PlayerAction.check() : const PlayerAction.call();
          }
        } else {
          action = session.botDecision();
        }
        hand.act(action);
        await session.afterAction();
      }
      session.finishHand();
    }
    expect(answered, greaterThan(0), reason: 'decisions answered against the field');
  });

  test('the field is the opponents\' hands, weighted by how often each is the best', () {
    final board = [for (final c in parseCards('Kh 9d 4c 2s 7h')) c.index];
    Float64List only(String a, String b) {
      final r = Float64List(comboCount);
      r[comboIndex(PlayingCard.parse(a).index, PlayingCard.parse(b).index)] = 1;
      return r;
    }

    // Kings (a set) against nines (a pair): the kings are always the best.
    final kings = comboIndex(PlayingCard.parse('Ks').index, PlayingCard.parse('Kd').index);
    final nines = comboIndex(PlayingCard.parse('9s').index, PlayingCard.parse('9h').index);
    final field = strongestOfField(board, [only('Ks', 'Kd'), only('9s', '9h')]);
    expect(field[kings], closeTo(1, 1e-9));
    expect(field[nines], closeTo(0, 1e-9));
  });
}
