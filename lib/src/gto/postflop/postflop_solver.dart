import 'dart:math';
import 'dart:typed_data';

import '../branches.dart';
import '../combos.dart';
import 'postflop_tree.dart';
import 'showdown.dart';

/// The hands possible on a board: every two-card combination that doesn't
/// use a board card, numbered 0..length-1 ("compact" indices).
class PostflopHands {
  factory PostflopHands(List<int> board) {
    final used = List<bool>.filled(52, false);
    for (final c in board) {
      used[c] = true;
    }
    final full = <int>[];
    final compact = Int32List(comboCount)..fillRange(0, comboCount, -1);
    for (var i = 0; i < comboCount; i++) {
      if (used[comboLow[i]] || used[comboHigh[i]]) continue;
      compact[i] = full.length;
      full.add(i);
    }
    final fullList = Int32List.fromList(full);
    return PostflopHands._(
      Int32List.fromList([for (final i in full) comboLow[i]]),
      Int32List.fromList([for (final i in full) comboHigh[i]]),
      fullList,
      compact,
    );
  }

  PostflopHands._(this.cardA, this.cardB, this.full, this.compact);

  final Int32List cardA;
  final Int32List cardB;

  /// Compact index -> combination index (0-1325).
  final Int32List full;

  /// Combination index -> compact index, or -1 if it uses a board card.
  final Int32List compact;

  int get length => full.length;
}

/// Strategies and action values for one street.
class PostflopSolution {
  PostflopSolution(this.tree, this.hands, this.strategy, this.values);

  final PostflopTree tree;
  final PostflopHands hands;

  /// `[node.offset + action * hands.length + hand]`: how often the hand takes the action.
  final Float32List strategy;

  /// Same layout: chips the player expects to win on this street by taking
  /// the action (minus what they bet on it); NaN where it can't happen.
  final Float32List values;

  double frequency(PostflopDecision node, int action, int combo) =>
      strategy[node.offset + action * hands.length + hands.compact[combo]];

  double value(PostflopDecision node, int action, int combo) =>
      values[node.offset + action * hands.length + hands.compact[combo]];
}

/// Solves one street of heads-up betting with Discounted CFR.
///
/// On the river, hands are compared at showdown. On the flop and turn the
/// betting of later streets isn't modeled: when the street's betting ends,
/// each hand gets its equity share of the pot over the cards still to come
/// (all rivers on the turn; a sample of turn/river pairs on the flop).
/// The next street is solved again when it is reached.
class PostflopSolver implements BranchSolver {
  /// [ranges]: each player's weight on every combination (0-1325), in the
  /// order of [PostflopSpec.stacks] (first to act first).
  factory PostflopSolver(PostflopSpec spec, List<Float64List> ranges, {int flopRunouts = 40}) =>
      PostflopSolver.part(spec, ranges, flopRunouts: flopRunouts);

  /// Solves only the decisions in [owned] (all when null), for splitting the
  /// work across threads; decisions in [frontier] are handled by workers
  /// (see `solvePostflopInParallel`, and the preflop solver for details).
  factory PostflopSolver.part(
    PostflopSpec spec,
    List<Float64List> ranges, {
    Iterable<int>? owned,
    List<int> frontier = const [],
    int flopRunouts = 40,
  }) {
    final hands = PostflopHands(spec.board);
    final tree = PostflopTree(spec, hands: hands.length);
    final n = hands.length;
    final width = tree.decisions.fold(1, (m, d) => max(m, d.actions.length)) * n;
    final count = tree.decisions.length;
    final offsets = Int32List(count)..fillRange(0, count, -1);
    var storage = 0;
    if (owned == null) {
      for (final node in tree.decisions) {
        offsets[node.id] = node.offset;
      }
      storage = tree.storageSize;
    } else {
      for (final id in owned.toList()..sort()) {
        offsets[id] = storage;
        storage += tree.decisions[id].actions.length * n;
      }
    }
    final slots = Int32List(count)..fillRange(0, count, -1);
    for (var i = 0; i < frontier.length; i++) {
      slots[frontier[i]] = i;
    }
    return PostflopSolver._(spec, tree, hands, ranges, flopRunouts, n, width, _depthOf(tree.root) + 2,
        offsets, storage, slots, frontier.length);
  }

  PostflopSolver._(
    this.spec,
    this.tree,
    this.hands,
    List<Float64List> ranges,
    int flopRunouts,
    int n,
    int width,
    int depth,
    this.offsets,
    int storage,
    this._slots,
    int frontierCount,
  )   : _n = n,
        _width = width,
        _regrets = Float64List(storage),
        _strategySum = Float64List(storage),
        _average = Float64List(storage),
        _values = Float64List(storage),
        frontierReach = Float64List(frontierCount * 2 * n),
        frontierMass = Float64List(frontierCount * 2),
        frontierActive = Uint8List(frontierCount),
        frontierValues = Float64List(frontierCount * 2 * n),
        _out = Float64List(depth * 2 * n),
        _mass = Float64List(depth * 2),
        _reach = Float64List((2 + depth) * n),
        _reachAt = Int32List(depth * 2),
        _actionValues = Float64List(depth * width),
        _strategy = Float64List(depth * width),
        _acc = Float64List(n),
        _valid = Float64List(n),
        _weights = Float64List(n),
        _rootReach = Float64List(2 * n),
        _lastValues = Float64List(storage),
        _tremble = Float64List(storage),
        _trembleFrom = Int32List(tree.decisions.length)..fillRange(0, tree.decisions.length, -1),
        _haveValues = Uint8List(tree.decisions.length) {
    for (var p = 0; p < 2; p++) {
      for (var c = 0; c < n; c++) {
        _rootReach[p * n + c] = ranges[p][hands.full[c]];
      }
    }
    _setUpRunouts(flopRunouts);
  }

  final PostflopSpec spec;
  final PostflopTree tree;
  final PostflopHands hands;
  final int _n;
  final int _width;

  /// Where each decision's numbers start in this solver's arrays (-1 if not owned).
  @override
  final Int32List offsets;
  final Int32List _slots;

  /// For each frontier decision: both players' reach (2 x hands), their
  /// masses, whether it was reached, and the values workers computed.
  final Float64List frontierReach;
  final Float64List frontierMass;
  final Uint8List frontierActive;
  final Float64List frontierValues;
  bool _collecting = false;
  final Float64List _regrets;
  final Float64List _strategySum;
  final Float64List _average;
  final Float64List _values;
  final Float64List _out;
  final Float64List _mass;
  final Float64List _reach;
  final Int32List _reachAt;
  final Float64List _actionValues;
  final Float64List _strategy;
  final Float64List _acc;
  final Float64List _valid;
  final Float64List _weights;
  final Float64List _rootReach;
  final Float64List _cardSum = Float64List(52);
  final Float64List _below = Float64List(52);
  final Float64List _group = Float64List(52);
  final List<RunoutRanking> _runouts = [];

  /// How many runouts each pair of hands shares (to turn sums into averages).
  double _runoutsPerPair = 1;

  bool _finalPass = false;
  double _positiveDiscount = 0;
  double _strategyKeep = 0;
  int _iteration = 0;

  /// At the user's decisions, every action also gets a tiny weight from
  /// the hands that come closest to choosing it (see [_fillTremble]): the
  /// action values from the last iteration (same layout as [_regrets]),
  /// the extra weights, when they were last worked out, and whether a
  /// decision has values yet.
  final Float64List _lastValues;
  final Float64List _tremble;
  final Int32List _trembleFrom;
  final Uint8List _haveValues;

  /// Share of the user's hands (by weight) that tremble into each action,
  /// their weight, and how often (in iterations) the choice is refreshed.
  static const _trembleShare = 0.1;
  static const _trembleWeight = 1e-3;
  static const _trembleRefresh = 8;

  static int _depthOf(PostflopNode node) => switch (node) {
        PostflopTerminal() => 0,
        PostflopDecision() => 1 + node.children.map(_depthOf).reduce(max),
      };

  void _setUpRunouts(int flopRunouts) {
    final board = spec.board;
    final used = List<bool>.filled(52, false);
    for (final c in board) {
      used[c] = true;
    }
    final free = [for (var c = 0; c < 52; c++) if (!used[c]) c];
    switch (board.length) {
      case 5:
        _runouts.add(RunoutRanking(board, hands.cardA, hands.cardB));
        _runoutsPerPair = 1;
      case 4:
        for (final river in free) {
          _runouts.add(RunoutRanking([...board, river], hands.cardA, hands.cardB));
        }
        _runoutsPerPair = (free.length - 4).toDouble(); // rivers left once both hands are out
      default:
        final pairs = [
          for (var i = 0; i < free.length; i++)
            for (var j = i + 1; j < free.length; j++) (free[i], free[j]),
        ]..shuffle(Random(board.fold<int>(17, (h, c) => h * 31 + c)));
        final chosen = pairs.take(flopRunouts).toList();
        for (final (turn, river) in chosen) {
          _runouts.add(RunoutRanking([...board, turn, river], hands.cardA, hands.cardB));
        }
        // Of all turn/river pairs, the share that avoids four more cards.
        final all = pairs.length, open = (free.length - 4) * (free.length - 5) / 2;
        _runoutsPerPair = chosen.length * open / all;
    }
  }

  PostflopSolution solve({required int iterations, void Function(int done, int total)? onProgress}) {
    for (var t = 1; t <= iterations; t++) {
      beginIteration(t);
      _walkFromRoot();
      onProgress?.call(t, iterations);
    }
    beginFinalPass();
    _walkFromRoot();
    return PostflopSolution(tree, hands, Float32List.fromList(_average), Float32List.fromList(_values));
  }

  /// Sets the discounting for iteration [t] (counting from 1).
  @override
  void beginIteration(int t) {
    _iteration = t;
    _positiveDiscount = pow(t, 1.5) / (pow(t, 1.5) + 1);
    _strategyKeep = pow(t / (t + 1), 2).toDouble();
  }

  /// Computes the average strategies; later walks use them and record values.
  @override
  void beginFinalPass() {
    final n = _n;
    for (final node in tree.decisions) {
      final offset = offsets[node.id];
      if (offset < 0) continue;
      final a = node.actions.length;
      for (var c = 0; c < n; c++) {
        var total = 0.0;
        for (var i = 0; i < a; i++) {
          total += _strategySum[offset + i * n + c];
        }
        for (var i = 0; i < a; i++) {
          final index = offset + i * n + c;
          _average[index] = total > 0 ? _strategySum[index] / total : 1 / a;
        }
      }
    }
    _values.fillRange(0, _values.length, double.nan);
    _finalPass = true;
  }

  /// Average strategies and values of the owned decisions (see [offsets]).
  @override
  Float64List get ownedAverage => _average;
  @override
  Float64List get ownedValues => _values;

  /// Coordinator, step 1: records each frontier decision's reach.
  void collectFrontier() {
    frontierActive.fillRange(0, frontierActive.length, 0);
    _collecting = true;
    _walkFromRoot();
    _collecting = false;
  }

  /// Coordinator, step 2: with [frontierValues] filled in, finishes the walk.
  void finishFromFrontier() => _walkFromRoot();

  /// Worker: walks the branch starting at decision [nodeId], given both
  /// players' reach and mass there, and writes both players' values into [out].
  @override
  void walkBranch(
    int nodeId,
    Float64List reach,
    int reachAt,
    Float64List mass,
    int massAt,
    Float64List out,
    int outAt,
  ) {
    final n = _n;
    for (var p = 0; p < 2; p++) {
      _mass[p] = mass[massAt + p];
      _reachAt[p] = p * n;
      _reach.setRange(p * n, (p + 1) * n, reach, reachAt + p * n);
    }
    _walk(tree.decisions[nodeId], 0);
    out.setRange(outAt, outAt + 2 * n, _out);
  }

  void _walkFromRoot() {
    final n = _n;
    for (var p = 0; p < 2; p++) {
      _reach.setRange(p * n, (p + 1) * n, _rootReach, p * n);
      _reachAt[p] = p * n;
      var m = 0.0;
      for (var c = 0; c < n; c++) {
        m += _rootReach[p * n + c];
      }
      _mass[p] = m;
    }
    _walk(tree.root, 0);
  }

  void _walk(PostflopNode node, int depth) {
    switch (node) {
      case PostflopTerminal():
        if (!_collecting) _terminal(node, depth);
      case PostflopDecision():
        final slot = _slots[node.id];
        if (slot >= 0) {
          _atFrontier(slot, depth);
        } else {
          _decision(node, depth);
        }
    }
  }

  void _atFrontier(int slot, int depth) {
    final n = _n;
    final block = slot * 2 * n;
    if (_collecting) {
      frontierActive[slot] = 1;
      for (var p = 0; p < 2; p++) {
        frontierMass[slot * 2 + p] = _mass[depth * 2 + p];
        frontierReach.setRange(block + p * n, block + (p + 1) * n, _reach, _reachAt[depth * 2 + p]);
      }
      return;
    }
    _out.setRange(depth * 2 * n, (depth + 1) * 2 * n, frontierValues, block);
  }

  void _decision(PostflopDecision node, int depth) {
    final n = _n;
    final p = node.player, q = 1 - p;
    final actions = node.actions.length;
    final out = _out, reach = _reach, strategy = _strategy, actionValues = _actionValues;
    final outBase = depth * 2 * n;
    final childOutBase = outBase + 2 * n;
    final sBase = depth * _width;
    _fillStrategy(node, sBase);
    out.fillRange(outBase, childOutBase, 0);

    final myReach = _reachAt[depth * 2 + p];
    final childReach = (2 + depth) * n;
    _reachAt[(depth + 1) * 2 + p] = childReach;
    _reachAt[(depth + 1) * 2 + q] = _reachAt[depth * 2 + q];
    final opponentMass = _mass[depth * 2 + q];
    final offset = offsets[node.id];
    final hero = p == spec.hero;
    final trembling = hero && !_finalPass && _haveValues[node.id] == 1;
    if (trembling) {
      final from = _trembleFrom[node.id];
      if (from < 0 || (_iteration % _trembleRefresh == 0 && from != _iteration)) {
        _fillTremble(node, myReach);
        _trembleFrom[node.id] = _iteration;
      }
    }
    final tremble = _tremble;

    for (var i = 0; i < actions; i++) {
      final base = sBase + i * n;
      final tBase = offset + i * n;
      var reachSum = 0.0;
      for (var c = 0; c < n; c++) {
        final r = reach[myReach + c] * (trembling ? strategy[base + c] + tremble[tBase + c] : strategy[base + c]);
        reach[childReach + c] = r;
        reachSum += r;
      }
      _mass[(depth + 1) * 2 + p] = reachSum;
      _mass[(depth + 1) * 2 + q] = opponentMass;
      if (opponentMass == 0 && reachSum == 0) {
        actionValues.fillRange(base, base + n, 0);
        continue;
      }
      _walk(node.children[i], depth + 1);
      if (_collecting) continue;

      final mine = childOutBase + p * n, myOut = outBase + p * n;
      for (var c = 0; c < n; c++) {
        final v = out[mine + c];
        actionValues[base + c] = v;
        out[myOut + c] += strategy[base + c] * v;
      }
      if (reachSum == 0) continue;
      final src = childOutBase + q * n, dst = outBase + q * n;
      for (var c = 0; c < n; c++) {
        out[dst + c] += out[src + c];
      }
    }

    if (_collecting) return;
    if (hero) {
      _lastValues.setRange(offset, offset + actions * n, actionValues, sBase);
      _haveValues[node.id] = 1;
    }
    if (_finalPass) {
      _recordValues(node, depth, sBase);
    } else {
      _update(node, myReach, sBase, outBase + p * n);
    }
  }

  /// Picks, for each action at one of the user's decisions, the hands that
  /// come closest to choosing it (by last values) until they make up
  /// [_trembleShare] of the user's weight, and gives them a tiny extra
  /// weight on it. The bot's answers to every choice then get trained
  /// against a sensible range, so the value of a size GTO never uses is
  /// still meaningful. The user's own strategy and regrets are unaffected.
  void _fillTremble(PostflopDecision node, int myReach) {
    final n = _n;
    final actions = node.actions.length;
    final offset = offsets[node.id];
    // _acc is free here: it is only used while scoring endings.
    final values = _lastValues, tremble = _tremble, reach = _reach, gap = _acc;
    tremble.fillRange(offset, offset + actions * n, 0);
    var total = 0.0;
    for (var c = 0; c < n; c++) {
      total += reach[myReach + c];
    }
    if (total <= 0) return;
    for (var i = 0; i < actions; i++) {
      // How far each hand is from preferring this action (0 when it does).
      var lowest = 0.0;
      for (var c = 0; c < n; c++) {
        var best = double.negativeInfinity;
        for (var j = 0; j < actions; j++) {
          final v = values[offset + j * n + c];
          if (v > best) best = v;
        }
        final g = values[offset + i * n + c] - best;
        gap[c] = g;
        if (g < lowest) lowest = g;
      }
      // Bisect for the cut-off that keeps the closest hands' weight at the share.
      var low = lowest, high = 0.0;
      for (var step = 0; step < 12; step++) {
        final middle = (low + high) / 2;
        var weight = 0.0;
        for (var c = 0; c < n; c++) {
          if (gap[c] >= middle) weight += reach[myReach + c];
        }
        if (weight >= _trembleShare * total) {
          low = middle;
        } else {
          high = middle;
        }
      }
      for (var c = 0; c < n; c++) {
        if (gap[c] >= low && reach[myReach + c] > 0) tremble[offset + i * n + c] = _trembleWeight;
      }
    }
  }

  void _fillStrategy(PostflopDecision node, int sBase) {
    final n = _n;
    final a = node.actions.length;
    final offset = offsets[node.id];
    final strategy = _strategy;
    if (_finalPass) {
      final average = _average;
      for (var k = 0; k < a * n; k++) {
        strategy[sBase + k] = average[offset + k];
      }
      return;
    }
    final regrets = _regrets;
    for (var c = 0; c < n; c++) {
      var total = 0.0;
      for (var i = 0; i < a; i++) {
        final r = regrets[offset + i * n + c];
        if (r > 0) total += r;
      }
      for (var i = 0; i < a; i++) {
        final r = regrets[offset + i * n + c];
        strategy[sBase + i * n + c] = total > 0 ? (r > 0 ? r / total : 0) : 1 / a;
      }
    }
  }

  void _update(PostflopDecision node, int myReach, int sBase, int nodeValue) {
    const negativeDiscount = 0.5;
    final n = _n;
    final regrets = _regrets, sums = _strategySum, reach = _reach, out = _out;
    final strategy = _strategy, actionValues = _actionValues;
    final positiveDiscount = _positiveDiscount, keep = _strategyKeep;
    final offset = offsets[node.id];
    for (var i = 0; i < node.actions.length; i++) {
      final base = i * n;
      for (var c = 0; c < n; c++) {
        final index = offset + base + c;
        final r = regrets[index];
        regrets[index] = r * (r > 0 ? positiveDiscount : negativeDiscount) +
            actionValues[sBase + base + c] -
            out[nodeValue + c];
        sums[index] = sums[index] * keep + reach[myReach + c] * strategy[sBase + base + c];
      }
    }
  }

  /// Turns counterfactual values into chips, given that the opponent's
  /// cards (not clashing with the hand) and actions led here.
  void _recordValues(PostflopDecision node, int depth, int sBase) {
    final n = _n;
    final q = 1 - node.player;
    _disjointWeight(_reachAt[depth * 2 + q]);
    final values = _values, actionValues = _actionValues, valid = _valid;
    for (var i = 0; i < node.actions.length; i++) {
      for (var c = 0; c < n; c++) {
        final v = valid[c];
        if (v > 0) values[offsets[node.id] + i * n + c] = actionValues[sBase + i * n + c] / v;
      }
    }
  }

  /// `_valid[c]`: the opponent's weight on hands sharing no card with c.
  void _disjointWeight(int weightsAt) {
    final n = _n;
    final reach = _reach, cardSum = _cardSum, valid = _valid;
    final a = hands.cardA, b = hands.cardB;
    cardSum.fillRange(0, 52, 0);
    var total = 0.0;
    for (var c = 0; c < n; c++) {
      final w = reach[weightsAt + c];
      total += w;
      cardSum[a[c]] += w;
      cardSum[b[c]] += w;
    }
    for (var c = 0; c < n; c++) {
      valid[c] = total - cardSum[a[c]] - cardSum[b[c]] + reach[weightsAt + c];
    }
  }

  void _terminal(PostflopTerminal t, int depth) {
    final n = _n;
    final out = _out;
    final potEnd = spec.pot + t.bets[0] + t.bets[1];
    for (var p = 0; p < 2; p++) {
      final q = 1 - p;
      final outBase = (depth * 2 + p) * n;
      if (_mass[depth * 2 + q] == 0) {
        out.fillRange(outBase, outBase + n, 0);
        continue;
      }
      final weightsAt = _reachAt[depth * 2 + q];
      _disjointWeight(weightsAt);
      final valid = _valid;
      if (t.foldedBy >= 0) {
        final u = (t.foldedBy == p ? -t.bets[p] : potEnd - t.bets[p]).toDouble();
        for (var c = 0; c < n; c++) {
          out[outBase + c] = u * valid[c];
        }
        continue;
      }
      final acc = _acc, weights = _weights;
      acc.fillRange(0, n, 0);
      weights.setRange(0, n, _reach, weightsAt);
      for (final runout in _runouts) {
        addShowdownWins(runout, weights, acc, hands.cardA, hands.cardB, _below, _group);
      }
      final scale = potEnd / _runoutsPerPair;
      final bet = t.bets[p].toDouble();
      for (var c = 0; c < n; c++) {
        out[outBase + c] = scale * acc[c] - bet * valid[c];
      }
    }
  }
}
