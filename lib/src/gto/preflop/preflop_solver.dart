import 'dart:math';
import 'dart:typed_data';

import '../branches.dart';
import '../hand_classes.dart';
import 'preflop_equity.dart';
import 'preflop_tree.dart';

const _h = handClassCount;

/// Strategies and action values found by [PreflopSolver].
class PreflopSolution {
  PreflopSolution(this.tree, this.strategy, this.values);

  final PreflopTree tree;

  /// `strategy[node.offset + action * 169 + hand]`: how often the starting
  /// hand takes the action at that decision (0-1).
  final Float32List strategy;

  /// Same layout: the chips the player expects to win or lose over the whole
  /// hand (antes and blinds included) by taking the action. NaN where the
  /// spot can't be reached with the final strategies.
  final Float32List values;

  double frequency(PreflopDecision node, int action, int hand) =>
      strategy[node.offset + action * _h + hand];

  double value(PreflopDecision node, int action, int hand) =>
      values[node.offset + action * _h + hand];
}

/// Finds near-equilibrium preflop strategies with Discounted CFR.
///
/// All players are solved at once, one vector of 169 starting hands per
/// player. When the betting ends, a player's share of each pot comes from
/// the all-in equity table:
/// - two players: exact matchup equities, plus a small edge for the player
///   acting last after the flop when there is still betting to come;
/// - three or more: the chance of beating each opponent multiplied
///   together, then scaled so the shares add up to the whole pot.
/// Card removal between players is ignored.
///
/// For speed, every buffer is one flat array indexed by offsets (compiled
/// Dart is much slower with lists of arrays in hot loops).
class PreflopSolver implements BranchSolver {
  /// Solves the whole tree on this thread. [ranges] gives every player's
  /// weight (0-1) on each starting hand when the tree starts, player after
  /// player (players x 169); null means every hand is possible.
  factory PreflopSolver(PreflopTree tree, PreflopEquity equity, {Float64List? ranges}) =>
      PreflopSolver.part(tree, equity, ranges: ranges);

  /// Solves only the decisions in [owned] (all of them when null), for
  /// splitting the work across threads (see `solvePreflopInParallel`).
  ///
  /// Decisions in [frontier] are never walked: the coordinator records how
  /// likely each hand is to get there ([collectFrontier]) and takes their
  /// values from [frontierValues], filled in by the workers.
  factory PreflopSolver.part(
    PreflopTree tree,
    PreflopEquity equity, {
    Iterable<int>? owned,
    List<int> frontier = const [],
    Float64List? ranges,
  }) {
    final depth = _depth(tree.root) + 2;
    final width = tree.decisions.fold(1, (m, d) => max(m, d.actions.length)) * _h;
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
        storage += tree.decisions[id].actions.length * _h;
      }
    }
    final slots = Int32List(count)..fillRange(0, count, -1);
    for (var i = 0; i < frontier.length; i++) {
      slots[frontier[i]] = i;
    }
    final n = tree.spec.players;
    if (ranges != null && ranges.length != n * _h) throw ArgumentError('Need 169 weights per player');
    return PreflopSolver._(tree, equity, n, depth, width, offsets, storage, slots, frontier.length, ranges);
  }

  PreflopSolver._(
    this.tree,
    this.equity,
    int n,
    int depth,
    int width,
    this.offsets,
    int storage,
    this._slots,
    int frontierCount,
    Float64List? ranges,
  )   : _n = n,
        _width = width,
        _regrets = Float64List(storage),
        _strategySum = Float64List(storage),
        _out = Float64List(depth * n * _h),
        _mass = Float64List(depth * n),
        _reach = Float64List((n + depth) * _h),
        _reachAt = Int32List(depth * n),
        _actionValues = Float64List(depth * width),
        _strategy = Float64List(depth * width),
        _slotStamp = Int32List(n + depth),
        _cacheStamp = Int32List(n + depth)..fillRange(0, n + depth, -1),
        _cacheCloseness = Uint8List(n + depth),
        _vsRange = Float64List((n + depth) * _h),
        _closeVsRange = Float64List((n + depth) * _h),
        _equityAt = Int32List(n),
        _product = Float64List(n * _h),
        _rootReach = Float64List.fromList([
          for (var p = 0; p < n; p++)
            for (var h = 0; h < _h; h++) handClassCombos(h) / 1326 * (ranges == null ? 1 : ranges[p * _h + h]),
        ]),
        _values = Float64List(storage),
        _average = Float64List(storage),
        _trembleAt = _trembleNode(tree),
        _lastRootValues = Float64List(width),
        _recentRootValues = Float64List(width),
        _tremble = Float64List(width),
        frontierReach = Float64List(frontierCount * n * _h),
        frontierMass = Float64List(frontierCount * n),
        frontierActive = Uint8List(frontierCount),
        frontierValues = Float64List(frontierCount * n * _h);

  /// The decision whose choices all get trained (see [_fillTremble]): the
  /// user's decision at the start of a subgame. -1 for none.
  static int _trembleNode(PreflopTree tree) {
    final root = tree.root;
    return root is PreflopDecision && root.player == tree.spec.hero ? root.id : -1;
  }

  final PreflopTree tree;
  final PreflopEquity equity;
  final int _n;
  final int _width;

  /// Where each decision's numbers start in this solver's arrays (-1 if not owned).
  @override
  final Int32List offsets;
  final Int32List _slots;
  final Float64List _regrets;
  final Float64List _strategySum;

  /// For each frontier decision: every player's reach vector (n x 169),
  /// their masses (n), whether it was reached at all, and the values the
  /// workers computed for it (n x 169).
  final Float64List frontierReach;
  final Float64List frontierMass;
  final Uint8List frontierActive;
  final Float64List frontierValues;
  bool _collecting = false;

  /// Counterfactual values: `[(depth * n + player) * 169 + hand]`.
  final Float64List _out;

  /// How likely each player is to reach the current node: `[depth * n + player]`.
  final Float64List _mass;

  /// Reach vectors: the root vectors (one per player), then one slot per
  /// depth for the acting player's child reach.
  final Float64List _reach;

  /// Where each player's reach vector starts in [_reach]: `[depth * n + player]`.
  final Int32List _reachAt;
  final Float64List _actionValues;
  final Float64List _strategy;

  /// Each reach vector in [_reach] is a "slot" (its start / 169). A slot's
  /// stamp changes whenever it is rewritten, so the equity against it only
  /// has to be recomputed then: many endings share their players' ranges.
  final Int32List _slotStamp;
  final Int32List _cacheStamp;
  final Uint8List _cacheCloseness;
  int _stamp = 0;

  /// Unnormalized equity (and closeness) of each hand vs the range in a
  /// slot: `[slot * 169 + hand]`.
  final Float64List _vsRange;
  final Float64List _closeVsRange;

  /// For the ending being scored: where each player's row starts in [_vsRange].
  final Int32List _equityAt;
  final Float64List _product;

  /// Every player's reach vector when the tree starts (players x 169):
  /// the chance of being dealt each hand, times their range.
  final Float64List _rootReach;
  final Float64List _values;
  final Float64List _average;
  final Int32List _nonZeroIndex = Int32List(_h);
  final Float64List _nonZeroValue = Float64List(_h);

  /// The user's decision at the start of a subgame (see [_fillTremble]),
  /// its action values from the last iteration, and the extra weight each
  /// hand gets on each action this iteration.
  final int _trembleAt;
  final Float64List _lastRootValues;
  final Float64List _tremble;
  bool _haveRootValues = false;

  /// The same values smoothed over the last iterations: what the
  /// opponents' recent strategies (rather than their averages) give each
  /// action. See [_recordValues].
  final Float64List _recentRootValues;

  bool _finalPass = false;
  double _positiveDiscount = 0;
  double _strategyKeep = 0;

  PreflopSolution solve({int iterations = 200, void Function(int done, int total)? onProgress}) {
    for (var t = 1; t <= iterations; t++) {
      beginIteration(t);
      _walkFromRoot();
      onProgress?.call(t, iterations);
    }
    // One more pass with the final strategies to measure each action's value.
    beginFinalPass();
    _walkFromRoot();
    return PreflopSolution(tree, Float32List.fromList(_average), Float32List.fromList(_values));
  }

  /// Sets the discounting for iteration [t] (counting from 1).
  @override
  void beginIteration(int t) {
    _positiveDiscount = pow(t, 1.5) / (pow(t, 1.5) + 1);
    _strategyKeep = pow(t / (t + 1), 2).toDouble();
  }

  /// Computes the average strategies; later walks use them and record values.
  @override
  void beginFinalPass() {
    final sums = _strategySum, average = _average;
    for (final node in tree.decisions) {
      final offset = offsets[node.id];
      if (offset < 0) continue;
      final a = node.actions.length;
      for (var h = 0; h < _h; h++) {
        var total = 0.0;
        for (var i = 0; i < a; i++) {
          total += sums[offset + i * _h + h];
        }
        for (var i = 0; i < a; i++) {
          final index = offset + i * _h + h;
          average[index] = total > 0 ? sums[index] / total : 1 / a;
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

  /// Coordinator, step 1: walks the top of the tree and records, for each
  /// frontier decision, how likely each player's hands are to get there.
  void collectFrontier() {
    frontierActive.fillRange(0, frontierActive.length, 0);
    _collecting = true;
    _walkFromRoot();
    _collecting = false;
  }

  /// Coordinator, step 2: with [frontierValues] filled in, walks the top of
  /// the tree again, updating its regrets (or recording values in the final pass).
  void finishFromFrontier() => _walkFromRoot();

  /// Worker: walks the branch starting at decision [nodeId], given every
  /// player's reach vector and mass there, and writes every player's values
  /// (n x 169) into [out] at [outAt].
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
    _restartStampsIfNeeded();
    final n = _n;
    for (var q = 0; q < n; q++) {
      _mass[q] = mass[massAt + q];
      _reachAt[q] = q * _h;
      _reach.setRange(q * _h, (q + 1) * _h, reach, reachAt + q * _h);
      _slotStamp[q] = ++_stamp;
    }
    _walk(tree.decisions[nodeId], 0);
    out.setRange(outAt, outAt + n * _h, _out);
  }

  /// Stamps live in 32-bit arrays (web builds have no 64-bit ones): start
  /// over long before they could wrap around, forgetting every cached range.
  void _restartStampsIfNeeded() {
    if (_stamp < 1 << 30) return;
    _stamp = 0;
    _slotStamp.fillRange(0, _slotStamp.length, 0);
    _cacheStamp.fillRange(0, _cacheStamp.length, -1);
  }

  void _walkFromRoot() {
    _restartStampsIfNeeded();
    for (var p = 0; p < _n; p++) {
      var mass = 0.0;
      for (var h = 0; h < _h; h++) {
        mass += _rootReach[p * _h + h];
      }
      _mass[p] = mass;
      _reachAt[p] = p * _h;
      _reach.setRange(p * _h, (p + 1) * _h, _rootReach, p * _h);
      _slotStamp[p] = ++_stamp;
    }
    _walk(tree.root, 0);
  }

  static int _depth(PreflopNode node) => switch (node) {
        PreflopTerminal() => 0,
        PreflopDecision() => 1 + node.children.map(_depth).reduce(max),
      };

  /// Fills the values at [depth] for every player and starting hand.
  void _walk(PreflopNode node, int depth) {
    switch (node) {
      case PreflopTerminal():
        if (!_collecting) _terminal(node, depth);
      case PreflopDecision():
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
    final block = slot * n * _h;
    if (_collecting) {
      frontierActive[slot] = 1;
      for (var q = 0; q < n; q++) {
        frontierMass[slot * n + q] = _mass[depth * n + q];
        final from = _reachAt[depth * n + q];
        frontierReach.setRange(block + q * _h, block + (q + 1) * _h, _reach, from);
      }
      return;
    }
    _out.setRange(depth * n * _h, (depth + 1) * n * _h, frontierValues, block);
  }

  void _decision(PreflopDecision node, int depth) {
    final n = _n;
    final p = node.player;
    final actions = node.actions.length;
    final out = _out, mass = _mass, reach = _reach, reachAt = _reachAt;
    final actionValues = _actionValues, strategy = _strategy;
    final outBase = depth * n * _h;
    final childOutBase = outBase + n * _h;
    final sBase = depth * _width;
    _fillStrategy(node, sBase);
    out.fillRange(outBase, childOutBase, 0);

    // The child sees the same reach vectors, except the acting player's.
    final myReach = reachAt[depth * n + p];
    final childReach = (n + depth) * _h;
    for (var q = 0; q < n; q++) {
      reachAt[(depth + 1) * n + q] = q == p ? childReach : reachAt[depth * n + q];
    }
    final trembling = node.id == _trembleAt && !_finalPass && _haveRootValues;
    if (trembling) _fillTremble(node, myReach);
    final tremble = _tremble;

    for (var i = 0; i < actions; i++) {
      final base = sBase + i * _h;
      var reachSum = 0.0;
      for (var h = 0; h < _h; h++) {
        final r = reach[myReach + h] * (trembling ? strategy[base + h] + tremble[i * _h + h] : strategy[base + h]);
        reach[childReach + h] = r;
        reachSum += r;
      }
      _slotStamp[n + depth] = ++_stamp;
      var zeros = 0;
      for (var q = 0; q < n; q++) {
        final m = q == p ? reachSum : mass[depth * n + q];
        mass[(depth + 1) * n + q] = m;
        if (m == 0) zeros++;
      }
      if (zeros >= 2) {
        // Two players never get here: every value in this branch is zero.
        actionValues.fillRange(base, base + _h, 0);
        continue;
      }
      _walk(node.children[i], depth + 1);
      if (_collecting) continue;

      final mine = childOutBase + p * _h, myOut = outBase + p * _h;
      for (var h = 0; h < _h; h++) {
        final v = out[mine + h];
        actionValues[base + h] = v;
        out[myOut + h] += strategy[base + h] * v;
      }
      // If this player never takes the action, the others' values from it are zero.
      if (reachSum == 0) continue;
      for (var q = 0; q < n; q++) {
        if (q == p) continue;
        final src = childOutBase + q * _h, dst = outBase + q * _h;
        for (var h = 0; h < _h; h++) {
          out[dst + h] += out[src + h];
        }
      }
    }

    if (_collecting) return;
    if (node.id == _trembleAt && !_finalPass) {
      final recent = _recentRootValues;
      for (var k = 0; k < actions * _h; k++) {
        final v = actionValues[sBase + k];
        recent[k] = _haveRootValues ? 0.9 * recent[k] + 0.1 * v : v;
      }
      _lastRootValues.setRange(0, actions * _h, actionValues, sBase);
      _haveRootValues = true;
    }
    if (_finalPass) {
      _recordValues(node, depth, sBase);
    } else {
      _update(node, myReach, sBase, outBase + p * _h);
    }
  }

  /// Share of the user's hands that "tremble" into each action they don't
  /// otherwise take, and how much weight they get.
  static const _trembleShare = 0.1;
  static const _trembleWeight = 1e-3;

  /// At the user's decision in a subgame, every action also gets a tiny
  /// weight from the hands that come closest to choosing it (by last
  /// iteration's values), even when no hand really does. The opponents'
  /// answers to every choice then get trained against a sensible range, so
  /// the value of a choice GTO never makes is still meaningful. The user's
  /// own strategy and regrets are not affected.
  void _fillTremble(PreflopDecision node, int myReach) {
    final actions = node.actions.length;
    final values = _lastRootValues, tremble = _tremble, reach = _reach;
    tremble.fillRange(0, actions * _h, 0);
    var total = 0.0;
    for (var h = 0; h < _h; h++) {
      total += reach[myReach + h];
    }
    if (total <= 0) return;
    final order = List<int>.generate(_h, (h) => h);
    final gap = Float64List(_h);
    for (var i = 0; i < actions; i++) {
      // How far each hand is from preferring this action (0 when it does).
      for (var h = 0; h < _h; h++) {
        var best = double.negativeInfinity;
        for (var j = 0; j < actions; j++) {
          final v = values[j * _h + h];
          if (v > best) best = v;
        }
        gap[h] = values[i * _h + h] - best;
      }
      // Ties in hand order, so every platform's sort picks the same hands.
      order.sort((a, b) {
        final byGap = gap[b].compareTo(gap[a]);
        return byGap != 0 ? byGap : a - b;
      });
      var taken = 0.0;
      for (final h in order) {
        if (taken >= _trembleShare * total) break;
        if (reach[myReach + h] <= 0) continue;
        tremble[i * _h + h] = _trembleWeight;
        taken += reach[myReach + h];
      }
    }
  }

  void _fillStrategy(PreflopDecision node, int sBase) {
    final a = node.actions.length;
    final offset = offsets[node.id];
    final strategy = _strategy;
    if (_finalPass) {
      final average = _average;
      for (var k = 0; k < a * _h; k++) {
        strategy[sBase + k] = average[offset + k];
      }
      return;
    }
    // Regret matching: play each action in proportion to its positive regret.
    final regrets = _regrets;
    for (var h = 0; h < _h; h++) {
      var total = 0.0;
      for (var i = 0; i < a; i++) {
        final r = regrets[offset + i * _h + h];
        if (r > 0) total += r;
      }
      for (var i = 0; i < a; i++) {
        final r = regrets[offset + i * _h + h];
        strategy[sBase + i * _h + h] = total > 0 ? (r > 0 ? r / total : 0) : 1 / a;
      }
    }
  }

  void _update(PreflopDecision node, int myReach, int sBase, int nodeValue) {
    const negativeDiscount = 0.5;
    final regrets = _regrets, sums = _strategySum, reach = _reach, out = _out;
    final strategy = _strategy, actionValues = _actionValues;
    final positiveDiscount = _positiveDiscount, keep = _strategyKeep;
    final offset = offsets[node.id];
    for (var i = 0; i < node.actions.length; i++) {
      final base = i * _h;
      for (var h = 0; h < _h; h++) {
        final index = offset + base + h;
        final r = regrets[index];
        regrets[index] = r * (r > 0 ? positiveDiscount : negativeDiscount) +
            actionValues[sBase + base + h] -
            out[nodeValue + h];
        sums[index] = sums[index] * keep + reach[myReach + h] * strategy[sBase + base + h];
      }
    }
  }

  /// Turns counterfactual values into expected chips, given that the
  /// opponents' actions and cards led to this spot.
  void _recordValues(PreflopDecision node, int depth, int sBase) {
    var opponents = 1.0;
    for (var q = 0; q < _n; q++) {
      if (q != node.player) opponents *= _mass[depth * _n + q];
    }
    if (opponents <= 0) return;
    final values = _values, actionValues = _actionValues;
    final offset = offsets[node.id];
    for (var k = 0; k < node.actions.length * _h; k++) {
      values[offset + k] = actionValues[sBase + k] / opponents;
    }
    if (node.id != _trembleAt || !_haveRootValues) return;
    // A choice the user's hand (almost) never makes is only answered by
    // the opponents' tiny "tremble" training, whose average can drift into
    // something that choice would exploit, though their recent strategies
    // don't allow it. Its value is the lower of the two.
    final strategy = _strategy, recent = _recentRootValues;
    for (var k = 0; k < node.actions.length * _h; k++) {
      if (strategy[sBase + k] < 0.01) values[offset + k] = min(values[offset + k], recent[k] / opponents);
    }
  }

  void _terminal(PreflopTerminal t, int depth) {
    final n = _n;
    final c = t.contributions;
    final out = _out, mass = _mass;
    final outBase = depth * n * _h, massBase = depth * n;
    double othersMass(int q) {
      var m = 1.0;
      for (var j = 0; j < n; j++) {
        if (j != q) m *= mass[massBase + j];
      }
      return m;
    }

    // Everyone pays what they put in; pot shares are added below.
    for (var q = 0; q < n; q++) {
      out.fillRange(outBase + q * _h, outBase + (q + 1) * _h, -c[q] * othersMass(q));
    }
    if (t.uncontested) {
      final winner = t.live.single;
      final won = t.pots.single.amount * othersMass(winner);
      final v = outBase + winner * _h;
      for (var h = 0; h < _h; h++) {
        out[v + h] += won;
      }
      return;
    }

    final withEdge = t.positionEdge > 0;
    for (final k in t.live) {
      _equityAt[k] = _vsRangeOf(_reachAt[massBase + k], withEdge);
    }
    var foldedMass = 1.0;
    for (var q = 0; q < n; q++) {
      if (!t.live.contains(q)) foldedMass *= mass[massBase + q];
    }

    final vsRange = _vsRange, close = _closeVsRange, equityAt = _equityAt;
    for (final pot in t.pots) {
      final e = pot.eligible;
      var outside = foldedMass;
      for (final k in t.live) {
        if (!e.contains(k)) outside *= mass[massBase + k];
      }
      final amount = pot.amount * outside;
      if (amount == 0) continue;

      if (e.length == 1) {
        final v = outBase + e.single * _h;
        for (var h = 0; h < _h; h++) {
          out[v + h] += amount;
        }
      } else if (e.length == 2) {
        final i = e[0], j = e[1];
        final vi = outBase + i * _h, vj = outBase + j * _h;
        final eqJ = equityAt[j], eqI = equityAt[i];
        if (!withEdge) {
          for (var h = 0; h < _h; h++) {
            out[vi + h] += amount * vsRange[eqJ + h];
            out[vj + h] += amount * vsRange[eqI + h];
          }
        } else {
          final edge = t.inPosition == i ? t.positionEdge : -t.positionEdge;
          for (var h = 0; h < _h; h++) {
            out[vi + h] += amount * (vsRange[eqJ + h] + edge * close[eqJ + h]);
            out[vj + h] += amount * (vsRange[eqI + h] - edge * close[eqI + h]);
          }
        }
      } else {
        _multiwayShares(e, depth, amount);
      }
    }
  }

  /// Three or more players: approximate each hand's share of the pot by its
  /// chances against each opponent multiplied together, scaled so the
  /// expected shares add up to the whole pot.
  void _multiwayShares(List<int> e, int depth, double amount) {
    final n = _n;
    final massBase = depth * n, outBase = depth * n * _h;
    final mass = _mass, reach = _reach, vsRange = _vsRange, product = _product, out = _out;
    final equityAt = _equityAt;
    for (final k in e) {
      if (mass[massBase + k] <= 0) return;
    }
    var norm = 0.0;
    for (final i in e) {
      final pBase = i * _h;
      for (var h = 0; h < _h; h++) {
        var p = 1.0;
        for (final k in e) {
          if (k != i) p *= vsRange[equityAt[k] + h] / mass[massBase + k];
        }
        product[pBase + h] = p;
      }
      final r = _reachAt[massBase + i];
      var expected = 0.0;
      for (var h = 0; h < _h; h++) {
        expected += reach[r + h] * product[pBase + h];
      }
      norm += expected / mass[massBase + i];
    }
    if (norm <= 0) return;
    for (final i in e) {
      var others = 1.0;
      for (final k in e) {
        if (k != i) others *= mass[massBase + k];
      }
      final scale = amount * others / norm;
      final v = outBase + i * _h, pBase = i * _h;
      for (var h = 0; h < _h; h++) {
        out[v + h] += scale * product[pBase + h];
      }
    }
  }

  /// Equity (and closeness) of each hand against the range whose reach
  /// vector starts at [reachStart]: unnormalized, skipping hands with no
  /// weight in the range. Returns where the numbers start in [_vsRange] and
  /// [_closeVsRange]; they are only recomputed when the range changed.
  int _vsRangeOf(int reachStart, bool withCloseness) {
    final slot = reachStart ~/ _h;
    final outBase = slot * _h;
    if (_cacheStamp[slot] == _slotStamp[slot] && (!withCloseness || _cacheCloseness[slot] == 1)) {
      return outBase;
    }
    _cacheStamp[slot] = _slotStamp[slot];
    _cacheCloseness[slot] = withCloseness ? 1 : 0;
    final indices = _nonZeroIndex, weights = _nonZeroValue, reach = _reach;
    var count = 0;
    for (var o = 0; o < _h; o++) {
      final w = reach[reachStart + o];
      if (w > 0) {
        indices[count] = o;
        weights[count++] = w;
      }
    }
    final values = equity.values, closeness = equity.closeness;
    final vsRange = _vsRange, close = _closeVsRange;
    for (var h = 0; h < _h; h++) {
      final row = h * _h;
      var e = 0.0, cl = 0.0;
      if (!withCloseness) {
        for (var x = 0; x < count; x++) {
          e += values[row + indices[x]] * weights[x];
        }
      } else {
        for (var x = 0; x < count; x++) {
          final index = row + indices[x];
          final w = weights[x];
          e += values[index] * w;
          cl += closeness[index] * w;
        }
        close[outBase + h] = cl;
      }
      vsRange[outBase + h] = e;
    }
    return outBase;
  }
}
