// Compares greedy ways of answering multiway spots with the heads-up
// postflop solver, against an exact three-player solve of small river spots.
//
// Each spot: a random river; three players' ranges from the preflop game
// (CO opens, BTN and BB call), 25 hands each; one bet size, all-in for 0.75
// pot; fold or call facing it, no raises. The three-player game is solved
// with CFR+. Then, for each seat as the user, each greedy approach gives the
// user a strategy, which plays against the three-player solution's
// opponents: its loss is how much less it wins than the best response to
// them (in BB per hand).
//
// Run from the project root (compiled, it is much faster):
//   dart compile exe tool/multiway_bench.dart -o build/multiway_bench.exe
//   build/multiway_bench.exe [spots] [seed]
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pokerfection/src/engine/cards.dart';
import 'package:pokerfection/src/engine/hand_evaluator.dart';
import 'package:pokerfection/src/gto/combos.dart';
import 'package:pokerfection/src/gto/hand_classes.dart';
import 'package:pokerfection/src/gto/postflop/postflop_solver.dart';
import 'package:pokerfection/src/gto/postflop/postflop_tree.dart';
import 'package:pokerfection/src/gto/preflop/preflop_equity.dart';
import 'package:pokerfection/src/gto/preflop/preflop_solver.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tree.dart';

const pot = 2000;
const bet = 1500; // all-in, 0.75 pot
const perPlayer = 25;
const cfrIterations = 1500;
const huIterations = 600;

Future<void> main(List<String> args) async {
  final spots = args.isNotEmpty ? int.parse(args[0]) : 16;
  final seed = args.length > 1 ? int.parse(args[1]) : 1;
  final equity =
      PreflopEquity.fromBytes(ByteData.sublistView(File('assets/preflop_equity.bin').readAsBytesSync()));
  final classRanges = _threeWayRanges(equity);
  final rng = Random(seed);

  const approaches = ['A ignore others', 'B others check along', 'B2 others fold to bets', 'C mixed field',
      'D strongest of field', 'F average per opponent'];
  final lossVsBest = {for (final a in [...approaches, 'three-player solution']) a: <double>[]};
  final bySeat = {for (final a in approaches) a: List.generate(3, (_) => <double>[])};

  for (var s = 0; s < spots; s++) {
    final spot = _Spot.random(classRanges, rng);
    final game = _Game(spot)..solve();
    for (var hero = 0; hero < 3; hero++) {
      final best = game.heroEv(hero, null, bestResponse: true);
      lossVsBest['three-player solution']!.add((best - game.heroEv(hero, null)) / 100);
      for (final (k, name) in approaches.indexed) {
        final policy = _greedy(k, spot, hero);
        final loss = (best - game.heroEv(hero, policy)) / 100;
        lossVsBest[name]!.add(loss);
        bySeat[name]![hero].add(loss);
      }
    }
    stdout.writeln('spot ${s + 1}/$spots: ${spot.boardText}');
  }

  double mean(List<double> x) => x.reduce((a, b) => a + b) / x.length;
  stdout.writeln('\nLoss against the best response to the three-player solution (BB per hand, lower is better):');
  stdout.writeln('${'approach'.padRight(26)}  all     first   middle  last');
  for (final entry in lossVsBest.entries) {
    final seats = bySeat[entry.key];
    stdout.writeln('${entry.key.padRight(26)}  ${mean(entry.value).toStringAsFixed(3).padLeft(6)}'
        '${seats == null ? '' : '  ${[for (final x in seats) mean(x).toStringAsFixed(3).padLeft(6)].join('  ')}'}');
  }
}

/// Class weights (169) for BB, CO and BTN after CO opens, BTN and BB call
/// (6-max, 100 BB), in that order: the order they act after the flop.
List<Float64List> _threeWayRanges(PreflopEquity equity) {
  final tree = PreflopTree(PreflopSpec(stacks: List.filled(6, 10000)));
  final solution = PreflopSolver(tree, equity).solve(iterations: 200);
  final reach = List.generate(6, (_) => Float64List(handClassCount)..fillRange(0, handClassCount, 1));
  var node = tree.root as PreflopDecision;
  for (final move in [
    PreflopMove.fold, // UTG
    PreflopMove.fold, // HJ
    PreflopMove.raise, // CO
    PreflopMove.call, // BTN
    PreflopMove.fold, // SB
    PreflopMove.call, // BB
  ]) {
    final a = node.actions.indexWhere((x) => x.move == move);
    for (var h = 0; h < handClassCount; h++) {
      reach[node.player][h] *= solution.frequency(node, a, h);
    }
    final next = node.children[a];
    if (next is! PreflopDecision) break;
    node = next;
  }
  return [reach[5], reach[2], reach[3]];
}

/// One river spot: the board, and each player's hands (combination indices).
class _Spot {
  _Spot(this.board, this.hands) {
    for (var p = 0; p < 3; p++) {
      strength.add([
        for (final c in hands[p]) evaluateIndices([comboLow[c], comboHigh[c], ...board]),
      ]);
    }
  }

  factory _Spot.random(List<Float64List> classRanges, Random rng) {
    final deck = [for (var c = 0; c < 52; c++) c]..shuffle(rng);
    final board = deck.sublist(0, 5);
    final hands = <List<int>>[];
    for (final range in classRanges) {
      final weights = [
        for (var c = 0; c < comboCount; c++)
          board.contains(comboLow[c]) || board.contains(comboHigh[c]) ? 0.0 : range[comboClass[c]],
      ];
      final picked = <int>[];
      for (var k = 0; k < perPlayer; k++) {
        var roll = rng.nextDouble() * weights.fold(0.0, (a, b) => a + b);
        var c = 0;
        while (roll > weights[c] || weights[c] == 0) {
          roll -= weights[c];
          c++;
        }
        picked.add(c);
        weights[c] = 0;
      }
      hands.add(picked);
    }
    return _Spot(board, hands);
  }

  final List<int> board;
  final List<List<int>> hands;
  final List<List<int>> strength = [];

  String get boardText => [for (final c in board) PlayingCard(c).toString()].join(' ');

  /// A player's hands as weights over all 1326 combinations.
  Float64List range(int p) {
    final r = Float64List(comboCount);
    for (final c in hands[p]) {
      r[c] = 1;
    }
    return r;
  }
}

/// The user's strategy from a greedy approach: how often each of their
/// hands bets when nobody has, and calls facing a bet.
typedef _Policy = ({List<double> bet, List<double> call});

_Policy _greedy(int approach, _Spot spot, int hero) {
  final opponents = [for (var p = 0; p < 3; p++) if (p != hero) p];
  // The main opponent: the one acting last.
  final main = opponents.last, third = opponents.first;
  switch (approach) {
    case 0: // A: heads-up against the main opponent; the third ignored.
      return _headsUp(spot, hero, main, spot.range(main));
    case 1: // B: the third checks along to showdown.
      return _headsUp(spot, hero, main, spot.range(main), others: [spot.range(third)]);
    case 2: // B2: the third checks along, but folds to any bet.
      return _headsUp(spot, hero, main, spot.range(main), others: [spot.range(third)], othersFoldToBets: true);
    case 3: // C: one opponent holding either range.
      final mixed = Float64List(comboCount);
      for (final o in opponents) {
        final r = spot.range(o);
        for (var c = 0; c < comboCount; c++) {
          mixed[c] += r[c];
        }
      }
      return _headsUp(spot, hero, hero == 2 ? 0 : 2, mixed);
    case 4: // D: one opponent holding the field's best hand.
      return _headsUp(spot, hero, hero == 2 ? 0 : 2, _strongestOfField(spot, opponents));
    default: // F: heads-up against each opponent, the answers averaged.
      final answers = [for (final o in opponents) _headsUp(spot, hero, o, spot.range(o))];
      final n = spot.hands[hero].length;
      return (
        bet: [for (var i = 0; i < n; i++) answers.map((a) => a.bet[i]).reduce((a, b) => a + b) / answers.length],
        call: [for (var i = 0; i < n; i++) answers.map((a) => a.call[i]).reduce((a, b) => a + b) / answers.length],
      );
  }
}

/// Each opponent's hands, weighted by how often that hand is the best of
/// all the opponents' (against the others' ranges, ties counting half).
Float64List _strongestOfField(_Spot spot, List<int> opponents) {
  final out = Float64List(comboCount);
  for (final o in opponents) {
    for (final (i, c) in spot.hands[o].indexed) {
      var weight = 1.0;
      for (final other in opponents) {
        if (other == o) continue;
        var beaten = 0.0, possible = 0;
        for (final (j, d) in spot.hands[other].indexed) {
          if (_overlap(c, d)) continue;
          possible++;
          final a = spot.strength[o][i], b = spot.strength[other][j];
          beaten += a > b ? 1 : (a == b ? 0.5 : 0);
        }
        weight *= possible == 0 ? 1 : beaten / possible;
      }
      out[c] += weight;
    }
  }
  return out;
}

bool _overlap(int c, int d) =>
    comboLow[c] == comboLow[d] || comboLow[c] == comboHigh[d] || comboHigh[c] == comboLow[d] || comboHigh[c] == comboHigh[d];

/// The user's strategy from a heads-up solve against [opponentRange], sitting
/// where [opponent] sits (for who acts first).
_Policy _headsUp(_Spot spot, int hero, int opponent, Float64List opponentRange,
    {List<Float64List> others = const [], bool othersFoldToBets = false}) {
  final heroFirst = hero < opponent;
  final heroRange = spot.range(hero);
  final spec = PostflopSpec(
    board: spot.board,
    pot: pot,
    stacks: const [bet, bet],
    bigBlind: 100,
    botBetSizes: const [],
    botRaiseSizes: const [],
  );
  final ranges = heroFirst ? [heroRange, opponentRange] : [opponentRange, heroRange];
  final solution =
      PostflopSolver(spec, [...ranges, ...others], othersFoldToBets: othersFoldToBets).solve(iterations: huIterations);
  bool aggressive(PostflopMove m) => m == PostflopMove.bet || m == PostflopMove.raise || m == PostflopMove.allIn;
  PostflopDecision child(PostflopDecision n, bool Function(PostflopMove) f) =>
      n.children[n.actions.indexWhere((a) => f(a.move))] as PostflopDecision;
  final root = solution.tree.root as PostflopDecision;
  final PostflopDecision open, facing;
  if (heroFirst) {
    open = root;
    facing = child(child(root, (m) => m == PostflopMove.check), aggressive);
  } else {
    open = child(root, (m) => m == PostflopMove.check);
    facing = child(root, aggressive);
  }
  final call = facing.actions.indexWhere((a) => a.move == PostflopMove.call);
  return (
    bet: [
      for (final c in spot.hands[hero])
        [for (var a = 0; a < open.actions.length; a++) if (aggressive(open.actions[a].move)) solution.frequency(open, a, c)]
            .fold(0.0, (x, y) => x + y),
    ],
    call: [for (final c in spot.hands[hero]) solution.frequency(facing, call, c)],
  );
}

/// The three-player river game.
class _Node {
  _Node.decision(this.player, this.facing) : invested = const [], folded = const [];
  _Node.terminal(this.invested, this.folded)
      : player = -1,
        facing = false;

  final int player;

  /// Facing a bet: fold or call (otherwise check or bet).
  final bool facing;
  final List<_Node> children = [];
  final List<int> invested;
  final List<bool> folded;
  late final int id;
}

class _Game {
  _Game(this.spot) {
    root = _build(const [0, 0, 0], const [false, false, false], -1, const [0, 1, 2]);
    final n = [for (final h in spot.hands) h.length];
    for (var i = 0; i < n[0]; i++) {
      for (var j = 0; j < n[1]; j++) {
        if (_overlap(spot.hands[0][i], spot.hands[1][j])) continue;
        for (var k = 0; k < n[2]; k++) {
          if (_overlap(spot.hands[0][i], spot.hands[2][k]) || _overlap(spot.hands[1][j], spot.hands[2][k])) continue;
          _triples.addAll([i, j, k]);
        }
      }
    }
  }

  final _Spot spot;
  late final _Node root;
  final List<_Node> _decisions = [];
  final List<int> _triples = [];
  final List<Float64List> _regrets = [], _sums = [];

  int get _k => perPlayer;

  _Node _build(List<int> invested, List<bool> folded, int bettor, List<int> queue) {
    if (queue.isEmpty) return _Node.terminal(invested, folded);
    final p = queue.first, rest = queue.sublist(1);
    final node = _Node.decision(p, bettor >= 0)..id = _decisions.length;
    _decisions.add(node);
    _regrets.add(Float64List(2 * _k));
    _sums.add(Float64List(2 * _k));
    if (bettor < 0) {
      node.children.add(_build(invested, folded, -1, rest)); // check
      node.children.add(_build([...invested]..[p] = bet, folded, p, [(p + 1) % 3, (p + 2) % 3])); // bet
    } else {
      node.children.add(_build(invested, [...folded]..[p] = true, bettor, rest)); // fold
      node.children.add(_build([...invested]..[p] = bet, folded, bettor, rest)); // call
    }
    return node;
  }

  /// Each player's result for one deal of hands (chips, from the river on).
  void _payoffs(_Node t, int i, int j, int k, Float64List out) {
    final s = [spot.strength[0][i], spot.strength[1][j], spot.strength[2][k]];
    final total = pot + t.invested[0] + t.invested[1] + t.invested[2];
    var best = -1, winners = 0;
    for (var p = 0; p < 3; p++) {
      if (t.folded[p]) continue;
      if (s[p] > best) {
        best = s[p];
        winners = 1;
      } else if (s[p] == best) {
        winners++;
      }
    }
    for (var p = 0; p < 3; p++) {
      final wins = !t.folded[p] && s[p] == best;
      out[p] = (wins ? total / winners : 0.0) - t.invested[p];
    }
  }

  Float64List _strategy(int id) {
    final r = _regrets[id], out = Float64List(2 * _k);
    for (var c = 0; c < _k; c++) {
      final a = max(0.0, r[c]), b = max(0.0, r[_k + c]);
      final sum = a + b;
      out[c] = sum > 0 ? a / sum : 0.5;
      out[_k + c] = sum > 0 ? b / sum : 0.5;
    }
    return out;
  }

  Float64List _average(int id) {
    final s = _sums[id], out = Float64List(2 * _k);
    for (var c = 0; c < _k; c++) {
      final sum = s[c] + s[_k + c];
      out[c] = sum > 0 ? s[c] / sum : 0.5;
      out[_k + c] = sum > 0 ? s[_k + c] / sum : 0.5;
    }
    return out;
  }

  /// CFR+: every player's counterfactual values at [node].
  List<Float64List> _walk(_Node node, List<Float64List> reach, int t) {
    if (node.player < 0) {
      final out = List.generate(3, (_) => Float64List(_k));
      final pay = Float64List(3);
      for (var x = 0; x < _triples.length; x += 3) {
        final i = _triples[x], j = _triples[x + 1], k = _triples[x + 2];
        _payoffs(node, i, j, k, pay);
        out[0][i] += reach[1][j] * reach[2][k] * pay[0];
        out[1][j] += reach[0][i] * reach[2][k] * pay[1];
        out[2][k] += reach[0][i] * reach[1][j] * pay[2];
      }
      return out;
    }
    final p = node.player, sigma = _strategy(node.id);
    final values = <List<Float64List>>[];
    for (var a = 0; a < 2; a++) {
      final r = [for (var q = 0; q < 3; q++) q == p ? Float64List(_k) : reach[q]];
      for (var c = 0; c < _k; c++) {
        r[p][c] = reach[p][c] * sigma[a * _k + c];
      }
      values.add(_walk(node.children[a], r, t));
    }
    final out = List.generate(3, (_) => Float64List(_k));
    final regrets = _regrets[node.id], sums = _sums[node.id];
    for (var c = 0; c < _k; c++) {
      final v = sigma[c] * values[0][p][c] + sigma[_k + c] * values[1][p][c];
      out[p][c] = v;
      for (var a = 0; a < 2; a++) {
        regrets[a * _k + c] = max(0.0, regrets[a * _k + c] + values[a][p][c] - v);
        sums[a * _k + c] += t * reach[p][c] * sigma[a * _k + c];
      }
    }
    for (var q = 0; q < 3; q++) {
      if (q == p) continue;
      for (var c = 0; c < _k; c++) {
        out[q][c] = values[0][q][c] + values[1][q][c];
      }
    }
    return out;
  }

  void solve() {
    for (var t = 1; t <= cfrIterations; t++) {
      _walk(root, List.generate(3, (_) => Float64List(_k)..fillRange(0, _k, 1)), t);
    }
  }

  /// The user's average result per deal (chips) at seat [hero], playing
  /// [policy] (or the three-player solution when null, or the best response
  /// to the others), against the others' three-player solution.
  double heroEv(int hero, _Policy? policy, {bool bestResponse = false}) {
    Float64List walk(_Node node, List<Float64List> reach) {
      if (node.player < 0) {
        final out = Float64List(_k), pay = Float64List(3);
        for (var x = 0; x < _triples.length; x += 3) {
          final idx = [_triples[x], _triples[x + 1], _triples[x + 2]];
          _payoffs(node, idx[0], idx[1], idx[2], pay);
          var w = 1.0;
          for (var q = 0; q < 3; q++) {
            if (q != hero) w *= reach[q][idx[q]];
          }
          out[idx[hero]] += w * pay[hero];
        }
        return out;
      }
      final p = node.player;
      if (p != hero) {
        final sigma = _average(node.id);
        final out = Float64List(_k);
        for (var a = 0; a < 2; a++) {
          final r = [for (var q = 0; q < 3; q++) q == p ? Float64List(_k) : reach[q]];
          for (var c = 0; c < _k; c++) {
            r[p][c] = reach[p][c] * sigma[a * _k + c];
          }
          final v = walk(node.children[a], r);
          for (var c = 0; c < _k; c++) {
            out[c] += v[c];
          }
        }
        return out;
      }
      final v0 = walk(node.children[0], reach), v1 = walk(node.children[1], reach);
      final out = Float64List(_k);
      final average = policy == null && !bestResponse ? _average(node.id) : null;
      for (var c = 0; c < _k; c++) {
        final double second; // how often the second action (bet or call)
        if (bestResponse) {
          out[c] = max(v0[c], v1[c]);
          continue;
        } else if (average != null) {
          second = average[_k + c];
        } else {
          second = node.facing ? policy!.call[c] : policy!.bet[c];
        }
        out[c] = (1 - second) * v0[c] + second * v1[c];
      }
      return out;
    }

    final values = walk(root, List.generate(3, (_) => Float64List(_k)..fillRange(0, _k, 1)));
    return values.fold(0.0, (a, b) => a + b) / (_triples.length / 3);
  }
}
