import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/engine/cards.dart';
import 'package:pokerfection/src/engine/events.dart';
import 'package:pokerfection/src/engine/poker_hand.dart';

import '../helpers.dart';

/// Rebuilds the stacks from the event log alone, the way the table UI does.
List<int> replayStacks(List<GameEvent> events) {
  var stacks = <int>[];
  for (final e in events) {
    switch (e) {
      case HandStarted():
        stacks = List.of(e.stacks);
      case AntesPosted():
        e.amounts.forEach((seat, amount) => stacks[seat] -= amount);
      case BlindPosted():
        stacks[e.seat] -= e.amount;
      case ActionTaken():
        stacks[e.seat] -= e.chipsAdded;
      case UncalledBetReturned():
        stacks[e.seat] += e.amount;
      case PotAwarded():
        e.shares.forEach((seat, amount) => stacks[seat] += amount);
      default:
        break;
    }
  }
  return stacks;
}

void main() {
  test('random play keeps every chip and a consistent event log', () {
    for (var seed = 0; seed < 1000; seed++) {
      final rng = Random(seed);
      final n = 2 + rng.nextInt(7);
      final stacks = [
        for (var i = 0; i < n; i++) rng.nextBool() ? 1 + rng.nextInt(1500) : 1 + rng.nextInt(20000),
      ];
      final h = PokerHand(
        stacks: stacks,
        buttonSeat: rng.nextInt(n),
        smallBlind: 50,
        bigBlind: 100,
        ante: rng.nextBool() ? 0 : 10,
        handNumber: seed,
        random: rng,
      );

      var steps = 0;
      while (!h.isOver) {
        expect(++steps, lessThan(500), reason: 'seed $seed never finished');
        h.act(randomAction(h.legalActions(), rng));
      }

      final finalStacks = [for (var i = 0; i < n; i++) h.stackOf(i)];
      expect(finalStacks.reduce((a, b) => a + b), stacks.reduce((a, b) => a + b),
          reason: 'seed $seed');
      expect(finalStacks.every((s) => s >= 0), isTrue, reason: 'seed $seed');
      expect(replayStacks(h.log), finalStacks, reason: 'seed $seed');
      expect(h.log.last, isA<HandEnded>());

      final seen = <PlayingCard>{...h.board};
      for (var i = 0; i < n; i++) {
        for (final c in h.holeCards(i)) {
          expect(seen.add(c), isTrue, reason: 'seed $seed dealt $c twice');
        }
      }
      if (h.log.any((e) => e is HandsRevealed)) expect(h.board, hasLength(5));
    }
  });
}
