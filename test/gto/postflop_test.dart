import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/engine/actions.dart';
import 'package:pokerfection/src/engine/cards.dart';
import 'package:pokerfection/src/engine/events.dart';
import 'package:pokerfection/src/engine/hand_evaluator.dart';
import 'package:pokerfection/src/engine/poker_hand.dart';
import 'package:pokerfection/src/engine/rules.dart';
import 'package:pokerfection/src/gto/combos.dart';
import 'package:pokerfection/src/gto/postflop/parallel_postflop_solver.dart';
import 'package:pokerfection/src/gto/postflop/postflop_solver.dart';
import 'package:pokerfection/src/gto/postflop/postflop_tree.dart';
import 'package:pokerfection/src/gto/postflop/showdown.dart';

List<int> cards(String text) => [for (final c in parseCards(text)) c.index];

/// Weight 1 on every combination of the listed hands, e.g. "77 65".
Float64List rangeOf(Map<String, double> classes, List<int> board) {
  final range = Float64List(comboCount);
  for (var i = 0; i < comboCount; i++) {
    final a = comboLow[i], b = comboHigh[i];
    if (board.contains(a) || board.contains(b)) continue;
    final ranks = [PlayingCard(a).rankLabel, PlayingCard(b).rankLabel]..sort();
    for (final entry in classes.entries) {
      final want = entry.key.split('').map((r) => r == 'T' ? '10' : r).toList()..sort();
      if (ranks[0] == want[0] && ranks[1] == want[1]) range[i] = entry.value;
    }
  }
  return range;
}

void main() {
  test('one-pass showdown sums match comparing every pair of hands', () {
    final rng = Random(4);
    final board = cards('Kh Qd 7c 4s 2h');
    final hands = PostflopHands(board);
    final ranking = RunoutRanking(board, hands.cardA, hands.cardB);
    final weights = Float64List.fromList([for (var c = 0; c < hands.length; c++) rng.nextDouble()]);
    final fast = Float64List(hands.length);
    addShowdownWins(ranking, weights, fast, hands.cardA, hands.cardB, Float64List(52), Float64List(52));

    int strength(int c) => evaluateIndices([hands.cardA[c], hands.cardB[c], ...board]);
    for (var c = 0; c < hands.length; c += 7) {
      var expected = 0.0;
      for (var o = 0; o < hands.length; o++) {
        final shared = {hands.cardA[c], hands.cardB[c]}.intersection({hands.cardA[o], hands.cardB[o]});
        if (shared.isNotEmpty) continue;
        final diff = strength(c).compareTo(strength(o));
        expected += weights[o] * (diff > 0 ? 1 : (diff == 0 ? 0.5 : 0));
      }
      expect(fast[c], closeTo(expected, 1e-9), reason: 'hand $c');
    }
  });

  group('every postflop tree path is legal in the game engine', () {
    for (final (stacks, rule) in const [
      ((10000, 10000), RaiseRule.standard),
      ((10000, 2600), RaiseRule.standard),
      ((1500, 9000), RaiseRule.standard),
      ((10000, 10000), RaiseRule.bigBlind),
    ]) {
      test('stacks $stacks, ${rule.name} raises', () {
        // Heads-up, button (seat 0) limps, big blind (seat 1) checks: 200 in the pot.
        PokerHand start() {
          final hand = PokerHand(
            stacks: [stacks.$1, stacks.$2],
            buttonSeat: 0,
            smallBlind: 50,
            bigBlind: 100,
            random: Random(1),
            raiseRule: rule,
            board: parseCards('Kh Qd 7c 4s 2h'),
          );
          hand
            ..act(const PlayerAction.call())
            ..act(const PlayerAction.check());
          return hand;
        }

        final probe = start();
        expect(probe.street, Street.flop);
        final spec = PostflopSpec(
          board: [for (final c in probe.board) c.index],
          pot: probe.potTotal,
          stacks: [probe.stackOf(1), probe.stackOf(0)], // big blind acts first after the flop
          bigBlind: 100,
          raiseRule: rule,
        );
        final tree = PostflopTree(spec, hands: 1);
        var paths = 0;
        void walk(PostflopNode node, List<(PostflopDecision, int)> path) {
          switch (node) {
            case PostflopDecision():
              for (var i = 0; i < node.actions.length; i++) {
                walk(node.children[i], [...path, (node, i)]);
              }
            case PostflopTerminal():
              paths++;
              final hand = start();
              for (final (decision, i) in path) {
                expect(hand.toAct, decision.player == 0 ? 1 : 0);
                final legal = hand.legalActions();
                final a = decision.actions[i];
                switch (a.move) {
                  case PostflopMove.fold:
                    expect(legal.canFold, isTrue);
                    hand.act(const PlayerAction.fold());
                  case PostflopMove.check:
                    expect(legal.canCheck, isTrue);
                    hand.act(const PlayerAction.check());
                  case PostflopMove.call:
                    expect(legal.canCall, isTrue);
                    hand.act(const PlayerAction.call());
                  case PostflopMove.bet || PostflopMove.raise:
                    expect(legal.canRaise, isTrue);
                    expect(a.to, inInclusiveRange(legal.minRaiseTo, legal.maxRaiseTo - 1));
                    hand.act(PlayerAction.raiseTo(a.to));
                  case PostflopMove.allIn:
                    expect(legal.canRaise, isTrue);
                    expect(a.to, legal.maxRaiseTo);
                    hand.act(PlayerAction.raiseTo(a.to));
                }
              }
              expect(hand.isOver || hand.street != Street.flop, isTrue);
              expect(hand.potTotal, spec.pot + node.bets[0] + node.bets[1]);
          }
        }

        walk(tree.root, []);
        expect(paths, greaterThan(10));
      });
    }
  });

  test('river: polarized bettor vs bluff-catcher matches the textbook answer', () {
    // Out of position: sets (77) or air (65), equally likely. In position:
    // only AQ, which beats the air and loses to the sets. The only bet is
    // all-in for the size of the pot. Known answer: bet every set, bluff half
    // the air; the bluff-catcher calls half the time.
    final board = cards('Kh Qd 7c 4s 2h');
    // Bots only, with no sized bets: the only bet is all-in.
    final spec = PostflopSpec(board: board, pot: 1000, stacks: [1000, 1000], bigBlind: 100, botBetSizes: const []);
    final oop = rangeOf({'77': 1 / 3, '65': 1 / 16}, board);
    final ip = rangeOf({'AQ': 1 / 12}, board);
    final solution = PostflopSolver(spec, [oop, ip]).solve(iterations: 2000);

    final root = solution.tree.root as PostflopDecision;
    final bet = root.actions.indexWhere((a) => a.move == PostflopMove.allIn);
    final sets = comboIndex(PlayingCard.parse('7s').index, PlayingCard.parse('7h').index);
    final air = comboIndex(PlayingCard.parse('6s').index, PlayingCard.parse('5h').index);
    final catcher = comboIndex(PlayingCard.parse('As').index, PlayingCard.parse('Qh').index);
    expect(solution.frequency(root, bet, sets), greaterThan(0.95));
    expect(solution.frequency(root, bet, air), closeTo(0.5, 0.06));

    final facing = root.children[bet] as PostflopDecision;
    final call = facing.actions.indexWhere((a) => a.move == PostflopMove.call);
    expect(solution.frequency(facing, call, catcher), closeTo(0.5, 0.06));
    // At equilibrium, calling and folding are worth the same to the bluff-catcher.
    expect(solution.value(facing, call, catcher), closeTo(solution.value(facing, 0, catcher), 30));
  });

  for (final board in ['Kh Qd 7c 4s 2h', 'Kh Qd 7c 4s', 'Kh Qd 7c']) {
    test('several threads give exactly the same answer as one ($board)', () async {
      final b = cards(board);
      final spec = PostflopSpec(board: b, pot: 600, stacks: [5000, 7000], bigBlind: 100);
      final rng = Random(8);
      final ranges = [
        for (var p = 0; p < 2; p++) Float64List.fromList([for (var c = 0; c < comboCount; c++) rng.nextDouble()]),
      ];
      final serial = PostflopSolver(spec, ranges).solve(iterations: 12);
      final parallel = await solvePostflopInParallel(spec, ranges, iterations: 12, threads: 4);
      expect(parallel.strategy, serial.strategy);
      for (var i = 0; i < serial.values.length; i++) {
        final x = serial.values[i], y = parallel.values[i];
        expect(x.isNaN ? y.isNaN : x == y, isTrue, reason: 'value $i');
      }
    });
  }

  test('players checking along take their share at showdown', () {
    final board = cards('Kh Qd 7c 4s 2h');
    final spec = PostflopSpec(board: board, pot: 1000, stacks: [1000, 1000], bigBlind: 100, botBetSizes: const []);
    final oop = rangeOf({'77': 1 / 3, '65': 1 / 16}, board);
    final ip = rangeOf({'AQ': 1 / 12}, board);
    final sets = comboIndex(PlayingCard.parse('7s').index, PlayingCard.parse('7h').index);
    double checkValue(List<Float64List> others) {
      final solution = PostflopSolver(spec, [oop, ip, ...others]).solve(iterations: 300);
      final root = solution.tree.root as PostflopDecision;
      return solution.value(root, root.actions.indexWhere((a) => a.move == PostflopMove.check), sets);
    }

    final alone = checkValue(const []);
    // A third player with kings: a set of sevens never wins.
    expect(checkValue([rangeOf({'KK': 1 / 3}, board)]), lessThan(alone * 0.05));
    // A third player with air: a set of sevens always beats them.
    expect(checkValue([rangeOf({'65': 1 / 16}, board)]), closeTo(alone, alone * 0.05));
  });

  test('solve times for a typical spot', () {
    // Wide ranges: every hand with weight 0.5.
    final wide = Float64List(comboCount)..fillRange(0, comboCount, 0.5);
    for (final (name, board) in [
      ('river', cards('Kh Qd 7c 4s 2h')),
      ('turn', cards('Kh Qd 7c 4s')),
      ('flop', cards('Kh Qd 7c')),
    ]) {
      final spec = PostflopSpec(board: board, pot: 600, stacks: [9700, 9700], bigBlind: 100);
      final watch = Stopwatch()..start();
      final solver = PostflopSolver(spec, [wide, wide]);
      final setup = watch.elapsedMilliseconds;
      solver.solve(iterations: 100);
      // ignore: avoid_print
      print('$name: ${solver.tree.decisions.length} decisions, ${solver.tree.terminals.length} endings, '
          'setup $setup ms, 100 iterations ${watch.elapsedMilliseconds - setup} ms');
    }
  });
}
