import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/bots/bot.dart';
import 'package:pokerfection/src/engine/actions.dart';
import 'package:pokerfection/src/engine/events.dart';
import 'package:pokerfection/src/game/table_session.dart';
import 'package:pokerfection/src/gto/gto_solutions.dart';
import 'package:pokerfection/src/gto/preflop/preflop_equity.dart';
import 'package:pokerfection/src/gto/spot_strategy.dart';

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

  test('pots with three players after the flop say there is no answer', () async {
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
    // Everyone just calls or checks to see a three-way flop.
    while (hand.street == Street.preflop) {
      hand.act(hand.legalActions().canCheck ? const PlayerAction.check() : const PlayerAction.call());
      await session.afterAction();
    }
    expect(session.postflop!.unavailable, NoAnswer.multiway);
  });
}
