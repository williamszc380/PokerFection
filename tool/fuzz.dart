// Fuzzer for the game engine and the solvers: random hands, trees and
// solves, checked against the rules of the game and simple invariants.
//
// Every case gets its own seed, printed with any failure so it can be
// replayed. Runs for the given number of minutes (0 = one round).
//
// Run from the project root:
//   dart run tool/fuzz.dart [minutes] [first seed] [case name filter]
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pokerfection/src/engine/actions.dart';
import 'package:pokerfection/src/engine/events.dart';
import 'package:pokerfection/src/engine/hand_evaluator.dart';
import 'package:pokerfection/src/engine/poker_hand.dart';
import 'package:pokerfection/src/engine/positions.dart';
import 'package:pokerfection/src/engine/rules.dart';
import 'package:pokerfection/src/gto/combos.dart';
import 'package:pokerfection/src/gto/hand_classes.dart';
import 'package:pokerfection/src/gto/postflop/parallel_postflop_solver.dart';
import 'package:pokerfection/src/gto/postflop/postflop_solver.dart';
import 'package:pokerfection/src/gto/postflop/postflop_tree.dart';
import 'package:pokerfection/src/gto/postflop/showdown.dart';
import 'package:pokerfection/src/gto/preflop/parallel_preflop_solver.dart';
import 'package:pokerfection/src/gto/preflop/preflop_equity.dart';
import 'package:pokerfection/src/gto/preflop/preflop_solver.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tree.dart';

final equity =
    PreflopEquity.fromBytes(ByteData.sublistView(File('assets/preflop_equity.bin').readAsBytesSync()));

class FuzzFailure implements Exception {
  FuzzFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

void check(bool ok, String Function() message) {
  if (!ok) throw FuzzFailure(message());
}

typedef FuzzCase = FutureOr<void> Function(Random rng);

Future<void> main(List<String> args) async {
  final minutes = args.isNotEmpty ? double.parse(args[0]) : 30;
  var seed = args.length > 1 ? int.parse(args[1]) : DateTime.now().millisecondsSinceEpoch % 100000000;
  final filter = args.length > 2 ? args[2] : '';
  final cases = <String, (FuzzCase, int)>{
    // name: (case, run it every n rounds)
    'engine-hand': (engineHand, 1),
    'preflop-tree': (preflopTree, 1),
    'postflop-tree': (postflopTree, 1),
    'showdown-sums': (showdownSums, 2),
    'preflop-solve': (preflopSolve, 2),
    'postflop-solve': (postflopSolve, 3),
    'parallel-preflop': (parallelPreflop, 15),
    'parallel-postflop': (parallelPostflop, 15),
    'preflop-ev': (preflopEv, 10),
    'postflop-ev': (postflopEv, 10),
  }..removeWhere((name, _) => !name.contains(filter));

  final end = DateTime.now().add(Duration(milliseconds: (minutes * 60000).round()));
  final runs = {for (final name in cases.keys) name: 0};
  final failures = {for (final name in cases.keys) name: 0};
  final watch = Stopwatch()..start();
  var lastReport = 0;
  stdout.writeln('Fuzzing ${cases.keys.join(', ')} from seed $seed for $minutes minutes');
  for (var round = 0;; round++) {
    for (final MapEntry(key: name, value: (run, every)) in cases.entries) {
      if (round % every != 0) continue;
      final s = seed++;
      try {
        await run(Random(s));
        runs[name] = runs[name]! + 1;
      } catch (e, stack) {
        failures[name] = failures[name]! + 1;
        final where = e is FuzzFailure ? '' : '\n${stack.toString().split('\n').take(6).join('\n')}';
        stdout.writeln('FAIL $name seed $s: $e$where');
      }
    }
    if (watch.elapsedMilliseconds - lastReport > 60000) {
      lastReport = watch.elapsedMilliseconds;
      stdout.writeln('${(lastReport / 60000).round()} min: ${_summary(runs, failures)}');
    }
    if (!DateTime.now().isBefore(end)) break;
  }
  stdout.writeln('Done after ${(watch.elapsedMilliseconds / 1000).round()} s: ${_summary(runs, failures)}');
  exit(failures.values.any((f) => f > 0) ? 1 : 0);
}

String _summary(Map<String, int> runs, Map<String, int> failures) =>
    [for (final name in runs.keys) '$name ${runs[name]} ok/${failures[name]} failed'].join(', ');

// -----------------------------------------------------------------------------
// Random inputs
// -----------------------------------------------------------------------------

/// Chips: mostly normal stacks, sometimes very short or very deep.
int randomStack(Random rng) => switch (rng.nextInt(10)) {
      0 => 1 + rng.nextInt(150),
      1 || 2 => 150 + rng.nextInt(1500),
      3 => 10000 + rng.nextInt(20000),
      _ => 1500 + rng.nextInt(12000),
    };

int randomAnte(Random rng) => [0, 0, 10, 25, rng.nextInt(60)][rng.nextInt(5)];

RaiseRule randomRule(Random rng) => RaiseRule.values[rng.nextInt(RaiseRule.values.length)];

/// A random legal action, including odd raise sizes and all-ins.
PlayerAction randomAction(LegalActions legal, Random rng) {
  final roll = rng.nextDouble();
  if (legal.canRaise && roll < 0.3) {
    if (roll < 0.05) return PlayerAction.raiseTo(legal.maxRaiseTo);
    final span = legal.maxRaiseTo - legal.minRaiseTo;
    return PlayerAction.raiseTo(legal.minRaiseTo + (span == 0 ? 0 : rng.nextInt(span + 1)));
  }
  if (legal.canCheck) return const PlayerAction.check();
  return roll < 0.75 ? const PlayerAction.call() : const PlayerAction.fold();
}

/// 1 to 5 raise sizes (multiples of the bet faced, or shares of the pot).
List<double> randomSizes(Random rng, List<double> choices) {
  final sizes = {for (var k = 1 + rng.nextInt(5); k > 0; k--) choices[rng.nextInt(choices.length)]};
  return sizes.toList()..sort();
}

// -----------------------------------------------------------------------------
// Engine
// -----------------------------------------------------------------------------

/// Random play keeps every chip, never gets stuck, and the event log
/// rebuilds the final stacks.
void engineHand(Random rng) {
  final n = 2 + rng.nextInt(7);
  final stacks = [for (var i = 0; i < n; i++) randomStack(rng)];
  final hand = PokerHand(
    stacks: stacks,
    buttonSeat: rng.nextInt(n),
    smallBlind: 50,
    bigBlind: 100,
    ante: randomAnte(rng),
    raiseRule: randomRule(rng),
    random: rng,
  );
  var steps = 0;
  while (!hand.isOver) {
    check(++steps < 1000, () => 'the hand never finished');
    final legal = hand.legalActions();
    check(legal.toCall >= 0 && legal.toCall <= legal.stack, () => 'bad amount to call: ${legal.toCall}');
    check(legal.maxRaiseTo == legal.streetBet + legal.stack, () => 'all-in amount is off');
    if (legal.canRaise) {
      check(legal.minRaiseTo > legal.currentBet && legal.minRaiseTo <= legal.maxRaiseTo,
          () => 'bad raise range ${legal.minRaiseTo}-${legal.maxRaiseTo} over ${legal.currentBet}');
    }
    hand.act(randomAction(legal, rng));
  }
  final after = [for (var i = 0; i < n; i++) hand.stackOf(i)];
  check(after.every((s) => s >= 0), () => 'negative stack: $after');
  check(after.reduce((a, b) => a + b) == stacks.reduce((a, b) => a + b), () => 'chips were created or lost');
  check(_replayStacks(hand.log).join(',') == after.join(','), () => 'the event log disagrees with the stacks');
}

/// Rebuilds the stacks from the event log alone, the way the table UI does.
List<int> _replayStacks(List<GameEvent> events) {
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

// -----------------------------------------------------------------------------
// Preflop trees
// -----------------------------------------------------------------------------

/// A random preflop situation: the game, and the actions taken so far
/// (random legal ones, as a user or a bot might play) up to someone's turn.
class _PreflopCase {
  _PreflopCase(Random rng, {int maxPlayers = 8, bool deep = true}) {
    n = 2 + rng.nextInt(maxPlayers - 1);
    stacks = [for (var k = 0; k < n; k++) deep ? randomStack(rng) : 100 + rng.nextInt(3000)];
    ante = randomAnte(rng);
    rule = randomRule(rng);
    seed = rng.nextInt(1 << 30);
    multiples = randomSizes(rng, const [1.5, 2, 2.2, 2.5, 3, 3.5, 4, 5, 6]);
    // Walk into the hand with random actions; stop at a random point.
    final hand = start();
    final stop = rng.nextInt(2 * n);
    for (var k = 0; k < stop && !hand.isOver && hand.street == Street.preflop; k++) {
      final legal = hand.legalActions();
      final action = randomAction(legal, rng);
      history.add(_asTreeAction(action, legal));
      hand.act(action);
    }
    if (!hand.isOver && hand.street == Street.preflop) hero = _order(hand.toAct!);
  }

  late final int n;

  /// In preflop order (first to act first).
  late final List<int> stacks;
  late final int ante;
  late final RaiseRule rule;
  late final int seed;
  late final List<double> multiples;
  final history = <PreflopAction>[];

  /// Preflop order of the player to act after [history], or -1 if the
  /// preflop betting is over.
  int hero = -1;

  /// Seat of preflop player [k], with the button on seat 0.
  int seatOf(int k) => (bigBlindSeat(n, 0) + 1 + k) % n;
  int _order(int seat) => (seat - bigBlindSeat(n, 0) - 1 + 2 * n) % n;

  PokerHand start() {
    final bySeat = List.filled(n, 0);
    for (var k = 0; k < n; k++) {
      bySeat[seatOf(k)] = stacks[k];
    }
    return PokerHand(
      stacks: bySeat,
      buttonSeat: 0,
      smallBlind: 50,
      bigBlind: 100,
      ante: ante,
      raiseRule: rule,
      random: Random(seed),
    );
  }

  PreflopSpec spec({required bool subgame}) => PreflopSpec(
        stacks: stacks,
        ante: ante,
        raiseRule: rule,
        raiseMultiples: multiples,
        history: subgame ? history : const [],
        hero: subgame ? hero : -1,
      );

  static PreflopAction _asTreeAction(PlayerAction action, LegalActions legal) => switch (action.type) {
        ActionType.fold => const PreflopAction(PreflopMove.fold),
        ActionType.check => const PreflopAction(PreflopMove.check),
        ActionType.call => const PreflopAction(PreflopMove.call),
        ActionType.raise => action.amount == legal.maxRaiseTo
            ? PreflopAction(PreflopMove.allIn, action.amount)
            : PreflopAction(PreflopMove.raise, action.amount),
      };
}

/// Every sampled path of a preflop tree (the whole game, or the user's
/// subgame after random actions) is legal in the engine, the user's menu is
/// complete, and the chips add up.
void preflopTree(Random rng) {
  final c = _PreflopCase(rng);
  final subgame = c.hero >= 0 && rng.nextInt(3) > 0;
  final spec = c.spec(subgame: subgame);
  final tree = PreflopTree(spec);
  if (subgame) _checkFullMenu(c, tree);
  for (var walk = 0; walk < 40; walk++) {
    final path = <(PreflopDecision, int)>[];
    PreflopNode node = tree.root;
    while (node is PreflopDecision) {
      final i = rng.nextInt(node.actions.length);
      path.add((node, i));
      node = node.children[i];
    }
    _replayPreflop(c, spec, path, node as PreflopTerminal);
  }
}

/// At the root of the user's subgame: fold only when facing a bet, check or
/// call, raise sizes within the legal range (and short of all-in), all-in
/// whenever raising is possible.
void _checkFullMenu(_PreflopCase c, PreflopTree tree) {
  final hand = c.start();
  for (final a in c.history) {
    hand.act(_engineAction(a));
  }
  final legal = hand.legalActions();
  final root = tree.root as PreflopDecision;
  check(root.player == c.hero, () => 'the subgame starts with player ${root.player}, not ${c.hero}');
  final moves = [for (final a in root.actions) a.move];
  check(moves.contains(PreflopMove.fold) == legal.canFold, () => 'fold offered wrongly: $moves');
  check(moves.contains(legal.canCheck ? PreflopMove.check : PreflopMove.call), () => 'no check/call: $moves');
  check(moves.contains(PreflopMove.allIn) == legal.canRaise, () => 'all-in offered wrongly: $moves');
  for (final a in root.actions.where((a) => a.move == PreflopMove.raise)) {
    check(a.raiseTo >= legal.minRaiseTo && a.raiseTo < legal.maxRaiseTo * 0.9,
        () => 'raise to ${a.raiseTo} outside ${legal.minRaiseTo}-${legal.maxRaiseTo}');
  }
  if (legal.canRaise) {
    // Every size of the menu that is allowed must be there.
    for (final m in c.multiples) {
      final to = PreflopTree.raiseSize(legal.currentBet, m);
      if (to >= legal.minRaiseTo && to < legal.maxRaiseTo * 0.9) {
        check(root.actions.any((a) => a.move == PreflopMove.raise && a.raiseTo == to),
            () => 'size ${m}x (to $to) is allowed but missing');
      }
    }
  }
}

PlayerAction _engineAction(PreflopAction a) => switch (a.move) {
      PreflopMove.fold => const PlayerAction.fold(),
      PreflopMove.check => const PlayerAction.check(),
      PreflopMove.call => const PlayerAction.call(),
      PreflopMove.raise || PreflopMove.allIn => PlayerAction.raiseTo(a.raiseTo),
    };

void _replayPreflop(_PreflopCase c, PreflopSpec spec, List<(PreflopDecision, int)> path, PreflopTerminal end) {
  final hand = c.start();
  for (final a in spec.history) {
    hand.act(_engineAction(a));
  }
  for (final (node, i) in path) {
    check(hand.toAct == c.seatOf(node.player), () => 'player ${node.player} acts in the tree, not in the game');
    final legal = hand.legalActions();
    final a = node.actions[i];
    switch (a.move) {
      case PreflopMove.fold:
        check(legal.canFold, () => 'fold is not legal');
      case PreflopMove.check:
        check(legal.canCheck, () => 'check is not legal');
      case PreflopMove.call:
        check(legal.canCall, () => 'call is not legal');
      case PreflopMove.raise:
        check(legal.canRaise && a.raiseTo >= legal.minRaiseTo && a.raiseTo < legal.maxRaiseTo,
            () => 'raise to ${a.raiseTo} is not legal (${legal.minRaiseTo}-${legal.maxRaiseTo})');
      case PreflopMove.allIn:
        check(legal.canRaise && a.raiseTo == legal.maxRaiseTo, () => 'all-in to ${a.raiseTo} is off');
    }
    hand.act(_engineAction(a));
  }
  final total = end.contributions.reduce((a, b) => a + b);
  if (hand.isOver || hand.street != Street.preflop) {
    check(hand.potTotal == total, () => 'the pot is ${hand.potTotal} in the game, $total in the tree');
  } else {
    // The subgame ended early because the user folded: nobody may have
    // more in the tree than in the game.
    check(spec.hero >= 0 && end.live.every((p) => p != spec.hero), () => 'the tree ended the betting early');
    check(total <= hand.potTotal, () => 'the tree has more chips in the pot than the game');
  }
}

// -----------------------------------------------------------------------------
// Postflop trees
// -----------------------------------------------------------------------------

/// A random heads-up hand that reaches the flop, turn or river with both
/// players still able to bet.
class _PostflopCase {
  _PostflopCase(Random rng) {
    seed = rng.nextInt(1 << 30);
    stacks = [300 + rng.nextInt(20000), 300 + rng.nextInt(20000)];
    rule = randomRule(rng);
    preflopTo = rng.nextBool() ? 100 : 200 + rng.nextInt(400);
    street = [Street.flop, Street.turn, Street.river][rng.nextInt(3)];
    hero = rng.nextInt(3) - 1;
    sizes = randomSizes(rng, const [0.2, 0.25, 0.33, 0.5, 0.66, 0.75, 1, 1.25, 1.5, 2, 3]);
  }

  late final int seed;
  late final List<int> stacks;
  late final RaiseRule rule;
  late final int preflopTo;
  late final Street street;
  late final int hero;
  late final List<double> sizes;

  /// The hand at the start of [street], or null if someone is all-in by then.
  PokerHand? start() {
    final hand = PokerHand(
      stacks: stacks,
      buttonSeat: 0,
      smallBlind: 50,
      bigBlind: 100,
      raiseRule: rule,
      random: Random(seed),
    );
    final legal = hand.legalActions();
    hand.act(preflopTo > 100 && legal.canRaise
        ? PlayerAction.raiseTo(min(preflopTo, legal.maxRaiseTo))
        : const PlayerAction.call());
    if (!hand.isOver && hand.street == Street.preflop) {
      hand.act(hand.legalActions().canCheck ? const PlayerAction.check() : const PlayerAction.call());
    }
    while (!hand.isOver && hand.street != street) {
      hand.act(const PlayerAction.check());
    }
    if (hand.isOver || hand.toAct == null) return null;
    return hand;
  }

  PostflopSpec? spec() {
    final hand = start();
    if (hand == null) return null;
    final first = hand.toAct!;
    return PostflopSpec(
      board: [for (final c in hand.board) c.index],
      pot: hand.potTotal,
      stacks: [hand.stackOf(first), hand.stackOf(1 - first)],
      bigBlind: 100,
      raiseRule: rule,
      hero: hero,
      heroSizes: sizes,
    );
  }
}

/// Every sampled path of a postflop tree is legal in the engine, the user's
/// menu is complete at every one of their decisions, and the chips add up.
void postflopTree(Random rng) {
  final c = _PostflopCase(rng);
  final spec = c.spec();
  if (spec == null) return;
  final tree = PostflopTree(spec, hands: 1);
  for (var walk = 0; walk < 40; walk++) {
    final hand = c.start()!;
    final first = hand.toAct!;
    PostflopNode node = tree.root;
    while (node is PostflopDecision) {
      final d = node;
      check(hand.toAct == (d.player == 0 ? first : 1 - first), () => 'wrong player to act');
      final legal = hand.legalActions();
      if (d.player == spec.hero) _checkPostflopMenu(spec, d, legal);
      final a = d.actions[rng.nextInt(d.actions.length)];
      switch (a.move) {
        case PostflopMove.fold:
          check(legal.canFold, () => 'fold is not legal');
          hand.act(const PlayerAction.fold());
        case PostflopMove.check:
          check(legal.canCheck, () => 'check is not legal');
          hand.act(const PlayerAction.check());
        case PostflopMove.call:
          check(legal.canCall, () => 'call is not legal');
          hand.act(const PlayerAction.call());
        case PostflopMove.bet || PostflopMove.raise:
          check(legal.canRaise && a.to >= legal.minRaiseTo && a.to < legal.maxRaiseTo,
              () => '${a.move.name} to ${a.to} is not legal (${legal.minRaiseTo}-${legal.maxRaiseTo})');
          hand.act(PlayerAction.raiseTo(a.to));
        case PostflopMove.allIn:
          check(legal.canRaise && a.to == legal.maxRaiseTo, () => 'all-in to ${a.to} is off');
          hand.act(PlayerAction.raiseTo(a.to));
      }
      node = d.children[d.actions.indexOf(a)];
    }
    final end = node as PostflopTerminal;
    check(hand.isOver || hand.street != c.street, () => 'the tree ended the street early');
    check(hand.potTotal == spec.pot + end.bets[0] + end.bets[1],
        () => 'the pot is ${hand.potTotal} in the game, ${spec.pot + end.bets[0] + end.bets[1]} in the tree');
  }
}

void _checkPostflopMenu(PostflopSpec spec, PostflopDecision d, LegalActions legal) {
  final moves = [for (final a in d.actions) a.move];
  check(moves.contains(PostflopMove.fold) == legal.canFold, () => 'fold offered wrongly: $moves');
  check(moves.contains(PostflopMove.allIn) == legal.canRaise, () => 'all-in offered wrongly: $moves');
  if (!legal.canRaise) return;
  final pot = spec.pot + d.bets[0] + d.bets[1];
  for (final share in spec.heroSizes) {
    final to = PostflopTree.sizeTo(legal.currentBet, legal.streetBet, pot, share, spec.bigBlind);
    final allowed = to >= legal.minRaiseTo && to < legal.maxRaiseTo * PostflopSpec.nearlyAllIn;
    final present = d.actions.any((a) => a.to == to && a.move != PostflopMove.allIn);
    // A size can be missing when a smaller share gives the same amount.
    final duplicate = spec.heroSizes.any((s) =>
        s < share && PostflopTree.sizeTo(legal.currentBet, legal.streetBet, pot, s, spec.bigBlind) == to);
    check(present || !allowed || duplicate, () => 'size $share (to $to) is allowed but missing');
  }
}

// -----------------------------------------------------------------------------
// Showdown
// -----------------------------------------------------------------------------

/// The one-pass showdown sums match comparing every pair of hands.
void showdownSums(Random rng) {
  final deck = [for (var i = 0; i < 52; i++) i]..shuffle(rng);
  final board = deck.sublist(0, 5);
  final hands = PostflopHands(board);
  final ranking = RunoutRanking(board, hands.cardA, hands.cardB);
  final weights = Float64List.fromList([
    for (var c = 0; c < hands.length; c++) rng.nextInt(3) == 0 ? 0 : rng.nextDouble(),
  ]);
  final fast = Float64List(hands.length);
  addShowdownWins(ranking, weights, fast, hands.cardA, hands.cardB, Float64List(52), Float64List(52));
  int strength(int c) => evaluateIndices([hands.cardA[c], hands.cardB[c], ...board]);
  for (var k = 0; k < 25; k++) {
    final c = rng.nextInt(hands.length);
    var expected = 0.0;
    for (var o = 0; o < hands.length; o++) {
      if ({hands.cardA[c], hands.cardB[c]}.intersection({hands.cardA[o], hands.cardB[o]}).isNotEmpty) continue;
      final diff = strength(c).compareTo(strength(o));
      expected += weights[o] * (diff > 0 ? 1 : (diff == 0 ? 0.5 : 0));
    }
    check((fast[c] - expected).abs() < 1e-9, () => 'hand $c: ${fast[c]} instead of $expected');
  }
}

// -----------------------------------------------------------------------------
// Solves
// -----------------------------------------------------------------------------

/// Small random preflop games (or subgames): strategies are probabilities,
/// values are finite where the spot can be reached and never more than the
/// chips on the table. Subgames sometimes start from random ranges.
void preflopSolve(Random rng) {
  final c = _PreflopCase(rng, maxPlayers: 4, deep: false);
  final subgame = c.hero >= 0 && rng.nextBool();
  final spec = c.spec(subgame: subgame);
  final ranges = subgame && rng.nextBool() ? randomPreflopRanges(rng, c.n) : null;
  final solution =
      PreflopSolver(PreflopTree(spec), equity, ranges: ranges).solve(iterations: 20 + rng.nextInt(40));
  final tree = solution.tree;
  final chips = spec.stacks.reduce((a, b) => a + b);
  for (final node in tree.decisions) {
    for (var h = 0; h < handClassCount; h++) {
      var total = 0.0;
      for (var a = 0; a < node.actions.length; a++) {
        final f = solution.frequency(node, a, h);
        check(f >= 0 && f <= 1 + 1e-6, () => 'frequency $f at decision ${node.id}');
        total += f;
        final v = solution.value(node, a, h);
        check(v.isNaN || v.abs() <= chips, () => 'value $v at decision ${node.id} is impossible');
      }
      check((total - 1).abs() < 1e-4, () => 'frequencies add up to $total at decision ${node.id}');
    }
  }
  final root = tree.root;
  if (root is PreflopDecision) {
    for (var a = 0; a < root.actions.length; a++) {
      for (var h = 0; h < handClassCount; h++) {
        check(solution.value(root, a, h).isFinite, () => 'no value for ${root.actions[a]} at the start');
      }
    }
  }
}

/// A random range: some hands at random weights, the rest left out.
Float64List randomRange(Random rng, List<int> board) {
  final dead = board.toSet();
  final keep = 0.1 + 0.9 * rng.nextDouble();
  return Float64List.fromList([
    for (var c = 0; c < comboCount; c++)
      dead.contains(comboLow[c]) || dead.contains(comboHigh[c]) || rng.nextDouble() > keep ? 0 : rng.nextDouble(),
  ]);
}

/// Small random postflop solves: the same invariants as before the flop.
void postflopSolve(Random rng) {
  final c = _PostflopCase(rng);
  final spec = c.spec();
  if (spec == null || spec.street == Street.flop) return; // flops are slow; the turn covers the same code
  final ranges = [randomRange(rng, spec.board), randomRange(rng, spec.board)];
  final solution = PostflopSolver(spec, ranges).solve(iterations: 10 + rng.nextInt(20));
  final n = solution.hands.length;
  final chips = spec.pot + spec.stacks[0] + spec.stacks[1];
  for (final node in solution.tree.decisions) {
    for (var h = 0; h < n; h++) {
      var total = 0.0;
      for (var a = 0; a < node.actions.length; a++) {
        final f = solution.strategy[node.offset + a * n + h];
        check(f >= 0 && f <= 1 + 1e-6, () => 'frequency $f at decision ${node.id}');
        total += f;
        final v = solution.values[node.offset + a * n + h];
        check(v.isNaN || v.abs() <= chips, () => 'value $v at decision ${node.id} is impossible');
      }
      check((total - 1).abs() < 1e-4, () => 'frequencies add up to $total at decision ${node.id}');
    }
  }
}

/// Splitting a solve across threads gives exactly the same answer.
Future<void> parallelPreflop(Random rng) async {
  final c = _PreflopCase(rng, maxPlayers: 5, deep: false);
  final spec = c.spec(subgame: c.hero >= 0 && rng.nextBool());
  final iterations = 10 + rng.nextInt(20);
  final serial = PreflopSolver(PreflopTree(spec), equity).solve(iterations: iterations);
  final parallel =
      await solvePreflopInParallel(spec, equity, iterations: iterations, threads: 2 + rng.nextInt(4));
  _sameArrays(serial.strategy, parallel.strategy, 'strategy');
  _sameArrays(serial.values, parallel.values, 'values');
}

Future<void> parallelPostflop(Random rng) async {
  final c = _PostflopCase(rng);
  final spec = c.spec();
  if (spec == null || spec.street == Street.flop) return;
  final ranges = [randomRange(rng, spec.board), randomRange(rng, spec.board)];
  final iterations = 5 + rng.nextInt(10);
  final serial = PostflopSolver(spec, ranges).solve(iterations: iterations);
  final parallel =
      await solvePostflopInParallel(spec, ranges, iterations: iterations, threads: 2 + rng.nextInt(4));
  _sameArrays(serial.strategy, parallel.strategy, 'strategy');
  _sameArrays(serial.values, parallel.values, 'values');
}

void _sameArrays(Float32List a, Float32List b, String what) {
  check(a.length == b.length, () => '$what sizes differ');
  for (var i = 0; i < a.length; i++) {
    final same = a[i] == b[i] || (a[i].isNaN && b[i].isNaN);
    check(same, () => '$what differs at $i: ${a[i]} vs ${b[i]}');
  }
}

/// Random starting ranges for a subgame (players x 169), never empty.
Float64List randomPreflopRanges(Random rng, int players) {
  final ranges = Float64List(players * handClassCount);
  for (var p = 0; p < players; p++) {
    final keep = 0.05 + 0.95 * rng.nextDouble();
    for (var h = 0; h < handClassCount; h++) {
      if (rng.nextDouble() < keep) ranges[p * handClassCount + h] = rng.nextDouble();
    }
    ranges[p * handClassCount + rng.nextInt(handClassCount)] = 1;
  }
  return ranges;
}

/// How much better the best choice a hand never makes (under 1%) looks than
/// the best one it does make; 0 if it doesn't look better.
double _unusedLooksBetterBy(List<(double, double)> frequencyAndValue) {
  var used = double.negativeInfinity, unused = double.negativeInfinity;
  for (final (f, v) in frequencyAndValue) {
    if (v.isNaN) continue;
    if (f >= 0.01) {
      used = max(used, v);
    } else {
      unused = max(unused, v);
    }
  }
  return used.isInfinite || unused.isInfinite ? 0 : max(0, unused - used);
}

/// At the user's decision in a subgame, no choice GTO never makes may look
/// clearly better than the ones it does (see the solvers' trembles).
void preflopEv(Random rng) {
  final c = _PreflopCase(rng, maxPlayers: 4, deep: false);
  if (c.hero < 0) return;
  final spec = c.spec(subgame: true);
  final solution = PreflopSolver(PreflopTree(spec), equity).solve(iterations: 300);
  final root = solution.tree.root as PreflopDecision;
  for (var h = 0; h < handClassCount; h++) {
    final gap = _unusedLooksBetterBy([
      for (var a = 0; a < root.actions.length; a++)
        (solution.frequency(root, a, h), solution.value(root, a, h) / spec.bigBlind),
    ]);
    check(
        gap <= 0.25,
        () => '${handClassName(h)}: an unused choice looks ${gap.toStringAsFixed(2)} BB better in ${spec.key}: ${[
              for (var a = 0; a < root.actions.length; a++)
                '${root.actions[a]} ${(solution.frequency(root, a, h) * 100).round()}% '
                    '${(solution.value(root, a, h) / spec.bigBlind).toStringAsFixed(2)}',
            ].join(' | ')}');
  }
}

/// The same after the flop, at the user's first decision of the street.
void postflopEv(Random rng) {
  final c = _PostflopCase(rng);
  final spec = c.spec();
  if (spec == null || spec.street == Street.flop || spec.hero < 0) return;
  final ranges = [randomRange(rng, spec.board), randomRange(rng, spec.board)];
  final solution = PostflopSolver(spec, ranges).solve(iterations: 150);
  var node = solution.tree.root as PostflopDecision;
  if (node.player != spec.hero) {
    final checks = node.actions.indexWhere((a) => a.move == PostflopMove.check);
    final next = node.children[checks];
    if (next is! PostflopDecision) return;
    node = next;
  }
  final n = solution.hands.length;
  final pot = spec.pot + node.bets[0] + node.bets[1];
  for (var h = 0; h < n; h++) {
    if (ranges[spec.hero][solution.hands.full[h]] == 0) continue;
    final gap = _unusedLooksBetterBy([
      for (var a = 0; a < node.actions.length; a++)
        (solution.strategy[node.offset + a * n + h].toDouble(), solution.values[node.offset + a * n + h] / pot),
    ]);
    check(
        gap <= 0.05,
        () => 'hand $h: an unused choice looks ${(gap * 100).toStringAsFixed(1)}% of the pot better at '
            '${node.actions.join(', ')}: ${[
              for (var a = 0; a < node.actions.length; a++)
                '${(solution.strategy[node.offset + a * n + h] * 100).round()}% '
                    '${(solution.values[node.offset + a * n + h] / pot).toStringAsFixed(3)}',
            ].join(' | ')}');
  }
}
