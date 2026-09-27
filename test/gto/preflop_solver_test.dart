import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/engine/actions.dart';
import 'package:pokerfection/src/engine/cards.dart';
import 'package:pokerfection/src/engine/events.dart';
import 'package:pokerfection/src/engine/poker_hand.dart';
import 'package:pokerfection/src/engine/positions.dart';
import 'package:pokerfection/src/engine/rules.dart';
import 'package:pokerfection/src/gto/hand_classes.dart';
import 'package:pokerfection/src/gto/preflop/preflop_equity.dart';
import 'package:pokerfection/src/gto/preflop/preflop_solver.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tree.dart';

final equity =
    PreflopEquity.fromBytes(ByteData.sublistView(File('assets/preflop_equity.bin').readAsBytesSync()));

int cls(String cards) {
  final c = parseCards(cards);
  return handClassOf(c[0], c[1]);
}

/// Seat of preflop player [k] when the button is on seat 0.
int seatOf(int n, int k) => (bigBlindSeat(n, 0) + 1 + k) % n;

/// Share of all starting hands that take one of [moves] at [node].
double share(PreflopSolution s, PreflopDecision node, Set<PreflopMove> moves) {
  var total = 0.0;
  for (var h = 0; h < handClassCount; h++) {
    for (var i = 0; i < node.actions.length; i++) {
      if (moves.contains(node.actions[i].move)) {
        total += s.frequency(node, i, h) * handClassCombos(h) / 1326;
      }
    }
  }
  return total;
}

double freq(PreflopSolution s, PreflopDecision node, Set<PreflopMove> moves, int hand) {
  var total = 0.0;
  for (var i = 0; i < node.actions.length; i++) {
    if (moves.contains(node.actions[i].move)) total += s.frequency(node, i, hand);
  }
  return total;
}

PreflopDecision child(PreflopDecision node, PreflopMove move) =>
    node.children[node.actions.indexWhere((a) => a.move == move)] as PreflopDecision;

/// Plays one path of the tree in the real game engine and checks each step.
void replay(PreflopSpec spec, List<(PreflopDecision, int)> path, PreflopTerminal end) {
  final n = spec.players;
  final stacks = List.filled(n, 0);
  for (var k = 0; k < n; k++) {
    stacks[seatOf(n, k)] = spec.stacks[k];
  }
  final hand = PokerHand(
    stacks: stacks,
    buttonSeat: 0,
    smallBlind: spec.smallBlind,
    bigBlind: spec.bigBlind,
    ante: spec.ante,
    raiseRule: spec.raiseRule,
    random: Random(1),
  );
  for (final (node, i) in path) {
    expect(hand.toAct, seatOf(n, node.player));
    final legal = hand.legalActions();
    final action = node.actions[i];
    switch (action.move) {
      case PreflopMove.fold:
        expect(legal.canFold, isTrue);
        hand.act(const PlayerAction.fold());
      case PreflopMove.check:
        expect(legal.canCheck, isTrue);
        hand.act(const PlayerAction.check());
      case PreflopMove.call:
        expect(legal.canCall, isTrue);
        hand.act(const PlayerAction.call());
      case PreflopMove.raise:
        expect(legal.canRaise, isTrue);
        expect(action.raiseTo, inInclusiveRange(legal.minRaiseTo, legal.maxRaiseTo - 1));
        hand.act(PlayerAction.raiseTo(action.raiseTo));
      case PreflopMove.allIn:
        expect(legal.canRaise, isTrue);
        expect(action.raiseTo, legal.maxRaiseTo);
        hand.act(PlayerAction.raiseTo(action.raiseTo));
    }
  }
  expect(hand.isOver || hand.street != Street.preflop, isTrue, reason: 'betting should be over');
  expect(hand.potTotal, end.contributions.reduce((a, b) => a + b));
}

int replayAll(PreflopSpec spec) {
  final tree = PreflopTree(spec);
  var paths = 0;
  void walk(PreflopNode node, List<(PreflopDecision, int)> path) {
    switch (node) {
      case PreflopTerminal():
        replay(spec, path, node);
        paths++;
      case PreflopDecision():
        for (var i = 0; i < node.actions.length; i++) {
          walk(node.children[i], [...path, (node, i)]);
        }
    }
  }

  walk(tree.root, []);
  return paths;
}

void main() {
  group('every tree path is legal in the game engine', () {
    final specs = [
      PreflopSpec(stacks: [10000, 10000]),
      PreflopSpec(stacks: [2000, 2000, 2000]),
      PreflopSpec(stacks: [10000, 4000, 1500, 10000, 6000, 800], ante: 10),
      PreflopSpec(stacks: List.filled(6, 10000)),
      PreflopSpec(stacks: [10000, 4000, 1500, 10000], ante: 10, raiseRule: RaiseRule.bigBlind),
    ];
    for (final spec in specs) {
      test(spec.key, () {
        expect(replayAll(spec), greaterThan(0));
      });
    }
  });

  test('tree size stays small enough to solve quickly', () {
    for (final n in [2, 4, 6, 8]) {
      final tree = PreflopTree(PreflopSpec(stacks: List.filled(n, 10000)));
      // ignore: avoid_print
      print('$n players: ${tree.decisions.length} decisions, ${tree.terminals.length} endings');
      expect(tree.decisions.length, lessThan(20000));
    }
  });

  test('heads-up push/fold at 10 bb lands near the known equilibrium', () {
    final tree = PreflopTree(
      PreflopSpec(stacks: [1000, 1000]),
      settings: const PreflopSettings(pushFoldOnly: true),
    );
    final s = PreflopSolver(tree, equity).solve(iterations: 400);
    final root = tree.root as PreflopDecision;
    final bb = child(root, PreflopMove.allIn);
    // Known result: the button shoves about 58% of hands, the big blind calls about 37%.
    expect(share(s, root, {PreflopMove.allIn}), inInclusiveRange(0.50, 0.66));
    expect(share(s, bb, {PreflopMove.call}), inInclusiveRange(0.30, 0.45));
    expect(freq(s, root, {PreflopMove.allIn}, cls('As Ah')), greaterThan(0.99));
    expect(freq(s, root, {PreflopMove.allIn}, cls('3c 2d')), lessThan(0.01));
    expect(freq(s, bb, {PreflopMove.call}, cls('Ks Kh')), greaterThan(0.99));
    expect(freq(s, bb, {PreflopMove.call}, cls('7c 2d')), lessThan(0.01));
  });

  test('six players at 100 bb: sensible ranges', () {
    final tree = PreflopTree(PreflopSpec(stacks: List.filled(6, 10000)));
    final watch = Stopwatch()..start();
    final s = PreflopSolver(tree, equity).solve(iterations: 150);
    // ignore: avoid_print
    print('6 players, 150 iterations: ${watch.elapsedMilliseconds} ms');

    const opens = {PreflopMove.raise, PreflopMove.allIn};
    final utg = tree.root as PreflopDecision;
    var node = utg;
    for (var k = 0; k < 3; k++) {
      node = child(node, PreflopMove.fold);
    }
    final button = node;
    final utgOpen = share(s, utg, opens);
    final buttonOpen = share(s, button, opens);
    // ignore: avoid_print
    print('UTG opens ${(utgOpen * 100).toStringAsFixed(1)}%, BTN opens ${(buttonOpen * 100).toStringAsFixed(1)}%');
    expect(utgOpen, inInclusiveRange(0.06, 0.35));
    expect(buttonOpen, greaterThan(utgOpen));
    expect(freq(s, utg, opens, cls('As Ah')), greaterThan(0.95));
    expect(freq(s, utg, opens, cls('7c 2d')), lessThan(0.05));

    // The big blind defends wider against a button open than against UTG.
    PreflopDecision bigBlindFacing(PreflopDecision opener) {
      var n = child(opener, PreflopMove.raise);
      while (n.player != 5) {
        n = child(n, PreflopMove.fold);
      }
      return n;
    }

    const defend = {PreflopMove.call, PreflopMove.raise, PreflopMove.allIn};
    expect(share(s, bigBlindFacing(button), defend), greaterThan(share(s, bigBlindFacing(utg), defend)));
  });
}
