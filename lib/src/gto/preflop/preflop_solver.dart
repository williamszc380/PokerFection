import 'dart:math';
import 'dart:typed_data';

import '../branches.dart';
import '../hand_classes.dart';
import '../vectors.dart';
import 'preflop_equity.dart';
import 'preflop_tree.dart';
import 'range_equity.dart';

const _h = handClassCount;

/// Numbers per hand vector in the solver's own arrays: the 169 hands
/// rounded up to whole SIMD lanes (the 3 extra are never reached).
const _s = (_h + 3) & ~3;

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

/// Starting strategies for [tree] from [from], the answer to a similar game
/// (other stacks, or the whole game a subgame is part of), for a warm start
/// (see [PreflopSolver]). Same layout as [PreflopSolution.strategy]: each
/// decision reached by the same kinds of moves in [from] (raises matched to
/// the nearest size) gets its strategy there; the others are NaN.
Float32List warmStrategies(PreflopTree tree, PreflopSolution from) {
  final warm = Float32List(tree.storageSize)..fillRange(0, tree.storageSize, double.nan);
  PreflopNode at = from.tree.root;
  for (final a in tree.spec.history) {
    final i = at is PreflopDecision ? _closest(at.actions, a, const {}) : -1;
    if (i < 0) return warm;
    at = (at as PreflopDecision).children[i];
  }
  void match(PreflopNode mine, PreflopNode theirs) {
    if (mine is! PreflopDecision || theirs is! PreflopDecision || mine.player != theirs.player) return;
    final pairs = List.filled(mine.actions.length, -1);
    for (var j = 0; j < theirs.actions.length; j++) {
      final i = _closest(mine.actions, theirs.actions[j], {for (final p in pairs) if (p >= 0) p});
      if (i >= 0) pairs[i] = j;
    }
    final offset = mine.offset;
    warm.fillRange(offset, offset + mine.actions.length * _h, 0);
    for (var h = 0; h < _h; h++) {
      var total = 0.0;
      for (var i = 0; i < pairs.length; i++) {
        if (pairs[i] >= 0) total += from.frequency(theirs, pairs[i], h);
      }
      if (total <= 0) continue;
      for (var i = 0; i < pairs.length; i++) {
        if (pairs[i] >= 0) warm[offset + i * _h + h] = from.frequency(theirs, pairs[i], h) / total;
      }
    }
    for (var i = 0; i < pairs.length; i++) {
      if (pairs[i] >= 0) match(mine.children[i], theirs.children[pairs[i]]);
    }
  }

  match(tree.root, at);
  return warm;
}

/// [warm] (see [warmStrategies]) for just the decisions [ids], in order: what
/// a solver owning them takes (see [PreflopSolver.part]).
Float32List? warmFor(PreflopTree tree, Float32List? warm, List<int> ids) {
  if (warm == null) return null;
  final size = ids.fold(0, (sum, id) => sum + tree.decisions[id].actions.length * _h);
  final part = Float32List(size);
  var at = 0;
  for (final id in ids) {
    final node = tree.decisions[id], length = node.actions.length * _h;
    part.setRange(at, at + length, warm, node.offset);
    at += length;
  }
  return part;
}

/// The action in [actions] like [a] (the same move, the nearest size), not
/// in [taken]; -1 if none.
int _closest(List<PreflopAction> actions, PreflopAction a, Set<int> taken) {
  var best = -1;
  for (var i = 0; i < actions.length; i++) {
    if (actions[i].move != a.move || taken.contains(i)) continue;
    if (best < 0 || (actions[i].raiseTo - a.raiseTo).abs() < (actions[best].raiseTo - a.raiseTo).abs()) best = i;
  }
  return best;
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
/// With a warm start, it starts from the strategies of a similar game
/// (see [warmStrategies]) instead of from scratch, and needs fewer
/// iterations.
///
/// For speed, every buffer is one flat array of 32-bit numbers indexed by
/// offsets (compiled Dart is much slower with lists of arrays in hot
/// loops), each hand vector padded to whole SIMD lanes, and the vector
/// arithmetic is in vectors.dart (four hands at a time in native builds).
class PreflopSolver implements BranchSolver {
  /// Solves the whole tree on this thread. [ranges] gives every player's
  /// weight (0-1) on each starting hand when the tree starts, player after
  /// player (players x 169); null means every hand is possible. [warm]:
  /// see [warmStrategies].
  factory PreflopSolver(PreflopTree tree, PreflopEquity equity, {Float64List? ranges, Float32List? warm}) =>
      PreflopSolver.part(tree, equity, ranges: ranges, warm: warm);

  /// Solves only the decisions in [owned] (all of them when null), for
  /// splitting the work across threads (see `solvePreflopInParallel`).
  ///
  /// Decisions in [frontier] are never walked: the coordinator records how
  /// likely each hand is to get there ([collectFrontier]) and takes their
  /// values from [frontierValues], filled in by the workers. [warm]: the
  /// owned decisions' part of [warmStrategies] (see [warmFor]).
  factory PreflopSolver.part(
    PreflopTree tree,
    PreflopEquity equity, {
    Iterable<int>? owned,
    List<int> frontier = const [],
    Float64List? ranges,
    Float32List? warm,
  }) {
    final depth = _depth(tree.root) + 2;
    final width = tree.decisions.fold(1, (m, d) => max(m, d.actions.length)) * _s;
    final count = tree.decisions.length;
    final offsets = Int32List(count)..fillRange(0, count, -1);
    var storage = 0;
    for (final id in owned == null ? [for (final d in tree.decisions) d.id] : (owned.toList()..sort())) {
      offsets[id] = storage;
      storage += tree.decisions[id].actions.length * _s;
    }
    final slots = Int32List(count)..fillRange(0, count, -1);
    for (var i = 0; i < frontier.length; i++) {
      slots[frontier[i]] = i;
    }
    final n = tree.spec.players;
    if (ranges != null && ranges.length != n * _h) throw ArgumentError('Need 169 weights per player');
    return PreflopSolver._(tree, equity, n, depth, width, offsets, storage, slots, frontier.length, ranges, warm);
  }

  PreflopSolver._(
    this.tree,
    this.equity,
    int n,
    int depth,
    int width,
    this._offsets,
    int storage,
    this._slots,
    int frontierCount,
    Float64List? ranges,
    Float32List? warm,
  )   : _n = n,
        _width = width,
        _rangeEquity = RangeEquity(equity),
        _regrets = Vec(storage),
        _strategySum = Vec(storage),
        _out = Vec(depth * n * _s),
        _mass = Float64List(depth * n),
        _reach = Vec((n + depth) * _s),
        _reachAt = Int32List(depth * n),
        _actionValues = Vec(depth * width),
        _strategy = Vec(depth * width),
        _slotStamp = Int32List(n + depth),
        _cacheStamp = Int32List(n + depth)..fillRange(0, n + depth, -1),
        _cacheCloseness = Uint8List(n + depth),
        _vsRange = Vec((n + depth) * _s),
        _closeVsRange = Vec((n + depth) * _s),
        _equityAt = Int32List(n),
        _product = Vec(n * _s),
        _rootReach = _rootReachOf(n, ranges),
        _values = Vec(storage),
        _average = Vec(storage),
        _walked = Uint8List(tree.decisions.length),
        _trembleAt = _trembleNode(tree),
        _lastRootValues = Vec(width),
        _recentRootValues = Vec(width),
        _tremble = Vec(width),
        frontierReach = Float64List(frontierCount * n * _h),
        frontierMass = Float64List(frontierCount * n),
        frontierActive = Uint8List(frontierCount),
        frontierValues = Float64List(frontierCount * n * _h),
        _warm = _warmOf(tree, _offsets, storage, warm) {
    // The first iteration plays the warm strategies (any positive regrets
    // in proportion will do; see [_settleWarmStart]).
    final w = _warm;
    if (w != null) vScale(_regrets, 0, w, 0, storage, 1e-20);
  }

  static Vec _rootReachOf(int n, Float64List? ranges) {
    final reach = Vec(n * _s);
    for (var p = 0; p < n; p++) {
      for (var h = 0; h < _h; h++) {
        reach.f[p * _s + h] = handClassCombos(h) / 1326 * (ranges == null ? 1 : ranges[p * _h + h]);
      }
    }
    return reach;
  }

  /// The decision whose choices all get trained (see [_fillTremble]): the
  /// user's decision at the start of a subgame. -1 for none.
  static int _trembleNode(PreflopTree tree) {
    final root = tree.root;
    return root is PreflopDecision && root.player == tree.spec.hero ? root.id : -1;
  }

  final PreflopTree tree;
  final PreflopEquity equity;
  final RangeEquity _rangeEquity;
  final int _n;
  final int _width;

  /// Where each decision's numbers start in this solver's arrays (-1 if not
  /// owned): actions one after the other, [_s] numbers each.
  final Int32List _offsets;
  final Int32List _slots;
  final Vec _regrets;
  final Vec _strategySum;

  /// For each frontier decision: every player's reach vector (n x 169),
  /// their masses (n), whether it was reached at all, and the values the
  /// workers computed for it (n x 169).
  final Float64List frontierReach;
  final Float64List frontierMass;
  final Uint8List frontierActive;
  final Float64List frontierValues;
  bool _collecting = false;

  /// Counterfactual values: `[(depth * n + player) * _s + hand]`.
  final Vec _out;

  /// How likely each player is to reach the current node: `[depth * n + player]`.
  final Float64List _mass;

  /// Reach vectors: the root vectors (one per player), then one slot per
  /// depth for the acting player's child reach.
  final Vec _reach;

  /// Where each player's reach vector starts in [_reach]: `[depth * n + player]`.
  final Int32List _reachAt;
  final Vec _actionValues;
  final Vec _strategy;

  /// Each reach vector in [_reach] is a "slot" (its start / [_s]). A slot's
  /// stamp changes whenever it is rewritten, so the equity against it only
  /// has to be recomputed then: many endings share their players' ranges.
  final Int32List _slotStamp;
  final Int32List _cacheStamp;
  final Uint8List _cacheCloseness;
  int _stamp = 0;

  /// Unnormalized equity (and closeness) of each hand vs the range in a
  /// slot: `[slot * _s + hand]`.
  final Vec _vsRange;
  final Vec _closeVsRange;

  /// For the ending being scored: where each player's row starts in [_vsRange].
  final Int32List _equityAt;
  final Vec _product;

  /// Every player's reach vector when the tree starts (players x [_s]):
  /// the chance of being dealt each hand, times their range.
  final Vec _rootReach;
  final Vec _values;
  final Vec _average;

  /// Pruning: an action that no hand getting to it takes (by this
  /// iteration's strategy) changes nobody else's values, so its branch is
  /// skipped, and the player's own values for it (needed for regrets) are
  /// the ones from the last time it was walked. While training, [_values]
  /// keeps every decision's action values from its last visit, and
  /// [_walked] whether it has been visited. Every branch is walked again
  /// whenever the floor is added (see [_floorEvery]).
  final Uint8List _walked;

  /// The user's decision at the start of a subgame (see [_fillTremble]),
  /// its action values from the last iteration, and the extra weight each
  /// hand gets on each action this iteration.
  final int _trembleAt;
  final Vec _lastRootValues;
  final Vec _tremble;
  bool _haveRootValues = false;

  /// The same values smoothed over the last iterations: what the
  /// opponents' recent strategies (rather than their averages) give each
  /// action. See [_recordValues].
  final Vec _recentRootValues;

  bool _finalPass = false;
  double _positiveDiscount = 0;
  double _strategyKeep = 0;

  /// A warm start's strategies (see [warmStrategies]), same layout as
  /// [_regrets]: all zero for a hand and decision that has none.
  final Vec? _warm;

  /// A warm strategy counts as this many iterations of training (the
  /// discounting goes on from there), and its regrets hold it with this
  /// many iterations' worth of what the first iteration shows. Measured
  /// against long solves, 64 iterations from a warm start come closer than
  /// 200 from scratch (whole games; subgames of 6 or more players).
  static const _warmCounts = 16;
  static const _warmTrust = 16.0;

  /// Iterations already counted by the warm start.
  int _clock = 0;

  static Vec? _warmOf(PreflopTree tree, Int32List offsets, int storage, Float32List? warm) {
    if (warm == null) return null;
    final vec = Vec(storage);
    var at = 0;
    for (final node in tree.decisions) {
      final offset = offsets[node.id];
      if (offset < 0) continue;
      final a = node.actions.length;
      if (!warm[at].isNaN) {
        for (var i = 0; i < a; i++) {
          vec.f.setRange(offset + i * _s, offset + i * _s + _h, warm, at + i * _h);
        }
      }
      at += a * _h;
    }
    return vec;
  }

  /// After the first iteration, which played the warm strategies: they
  /// keep being played, held by regrets worth [_warmTrust] iterations of
  /// what that iteration showed (plus its own regrets), and their strategy
  /// sums count as [_warmCounts] iterations.
  void _settleWarmStart() {
    final warm = _warm!.f, regrets = _regrets.f, sums = _strategySum.f;
    // After T iterations, iteration t's strategy weighs ((t + 1) / (T + 1))
    // squared in the sums (see [beginIteration]); the first one alone weighs 1 now.
    var weight = 0.0;
    for (var t = 1; t <= _warmCounts; t++) {
      weight += (t + 1) * (t + 1);
    }
    final scale = weight / ((_warmCounts + 1) * (_warmCounts + 1));
    for (final node in tree.decisions) {
      final offset = _offsets[node.id];
      if (offset < 0) continue;
      final a = node.actions.length;
      for (var h = 0; h < _h; h++) {
        var spread = 0.0, start = 0.0;
        for (var i = 0; i < a; i++) {
          spread += regrets[offset + i * _s + h].abs();
          start += warm[offset + i * _s + h];
        }
        if (start <= 0) continue; // starting from scratch here
        for (var i = 0; i < a; i++) {
          final k = offset + i * _s + h;
          regrets[k] = warm[k] * _warmTrust * spread + regrets[k];
          sums[k] *= scale;
        }
      }
    }
    _clock = _warmCounts - 1;
  }

  PreflopSolution solve({int iterations = 200, void Function(int done, int total)? onProgress}) {
    for (var t = 1; t <= iterations; t++) {
      beginIteration(t);
      _walkFromRoot();
      onProgress?.call(t, iterations);
    }
    // One more pass with the final strategies to measure each action's value.
    beginFinalPass();
    _walkFromRoot();
    final strategy = Float32List(tree.storageSize), values = Float32List(tree.storageSize);
    for (final node in tree.decisions) {
      _copyOut(node, _average, strategy, node.offset);
      _copyOut(node, _values, values, node.offset);
    }
    return PreflopSolution(tree, strategy, values);
  }

  /// Copies [node]'s numbers from [from] (this solver's layout) to [to] at
  /// [at], 169 per action.
  void _copyOut(PreflopDecision node, Vec from, List<double> to, int at) {
    final offset = _offsets[node.id];
    for (var i = 0; i < node.actions.length; i++) {
      to.setRange(at + i * _h, at + (i + 1) * _h, from.f, offset + i * _s);
    }
  }

  /// Sets the discounting for iteration [t] (counting from 1).
  @override
  void beginIteration(int t) {
    if (t == 2 && _warm != null) _settleWarmStart();
    final c = t + _clock;
    _positiveDiscount = pow(c, 1.5) / (pow(c, 1.5) + 1);
    _strategyKeep = pow(c / (c + 1), 2).toDouble();
    _floorNow = t % _floorEvery == 0 ? _floor * _floorEvery : 0;
  }

  /// Computes the average strategies; later walks use them and record values.
  @override
  void beginFinalPass() {
    for (final node in tree.decisions) {
      final offset = _offsets[node.id];
      if (offset >= 0) vNormalize(_strategySum, offset, _average, offset, node.actions.length, _s);
    }
    _values.f.fillRange(0, _values.length, double.nan);
    _finalPass = true;
    _floorNow = 0;
  }

  /// Where each owned decision's numbers start in [ownedAverage] and
  /// [ownedValues] (169 per action), or -1.
  @override
  late final Int32List offsets = () {
    final at = Int32List(_offsets.length)..fillRange(0, _offsets.length, -1);
    var size = 0;
    for (final node in tree.decisions) {
      if (_offsets[node.id] < 0) continue;
      at[node.id] = size;
      size += node.actions.length * _h;
    }
    return at;
  }();

  /// Average strategies and values of the owned decisions (see [offsets]).
  @override
  Float64List get ownedAverage => _owned(_average);
  @override
  Float64List get ownedValues => _owned(_values);

  Float64List _owned(Vec from) {
    var size = 0;
    for (final node in tree.decisions) {
      if (_offsets[node.id] >= 0) size += node.actions.length * _h;
    }
    final owned = Float64List(size);
    for (final node in tree.decisions) {
      if (_offsets[node.id] >= 0) _copyOut(node, from, owned, offsets[node.id]);
    }
    return owned;
  }

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
      _reachAt[q] = q * _s;
      _reach.f.setRange(q * _s, q * _s + _h, reach, reachAt + q * _h);
      _slotStamp[q] = ++_stamp;
    }
    _walk(tree.decisions[nodeId], 0);
    for (var q = 0; q < n; q++) {
      out.setRange(outAt + q * _h, outAt + (q + 1) * _h, _out.f, q * _s);
    }
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
    final root = _rootReach.f;
    for (var p = 0; p < _n; p++) {
      var mass = 0.0;
      for (var h = 0; h < _h; h++) {
        mass += root[p * _s + h];
      }
      _mass[p] = mass;
      _reachAt[p] = p * _s;
      _reach.f.setRange(p * _s, (p + 1) * _s, root, p * _s);
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
        frontierReach.setRange(block + q * _h, block + (q + 1) * _h, _reach.f, from);
      }
      return;
    }
    for (var q = 0; q < n; q++) {
      final at = (depth * n + q) * _s;
      _out.f.setRange(at, at + _h, frontierValues, block + q * _h);
    }
  }

  void _decision(PreflopDecision node, int depth) {
    final n = _n;
    final p = node.player;
    final actions = node.actions.length;
    final out = _out, mass = _mass, reach = _reach, reachAt = _reachAt;
    final actionValues = _actionValues, strategy = _strategy;
    final outBase = depth * n * _s;
    final childOutBase = outBase + n * _s;
    final sBase = depth * _width;
    _fillStrategy(node, sBase);
    vFill(out, outBase, n * _s, 0);

    // The child sees the same reach vectors, except the acting player's.
    final myReach = reachAt[depth * n + p];
    final childReach = (n + depth) * _s;
    for (var q = 0; q < n; q++) {
      reachAt[(depth + 1) * n + q] = q == p ? childReach : reachAt[depth * n + q];
    }
    final trembling = node.id == _trembleAt && !_finalPass && _haveRootValues;
    if (trembling) _fillTremble(node, myReach);
    final myOut = outBase + p * _s, mine = childOutBase + p * _s;

    for (var i = 0; i < actions; i++) {
      final base = sBase + i * _s;
      final reachSum = trembling
          ? vChildReach(reach, myReach, strategy, base, 0, _tremble, i * _s, reach, childReach, _s)
          : vChildReach(reach, myReach, strategy, base, _floorNow, null, 0, reach, childReach, _s);
      _slotStamp[n + depth] = ++_stamp;
      var zeros = 0;
      for (var q = 0; q < n; q++) {
        final m = q == p ? reachSum : mass[depth * n + q];
        mass[(depth + 1) * n + q] = m;
        if (m == 0) zeros++;
      }
      if (zeros >= 2) {
        // Two players never get here: every value in this branch is zero.
        vFill(actionValues, base, _s, 0);
        continue;
      }
      if (reachSum == 0 && _floorNow == 0 && !_finalPass && _walked[node.id] == 1) {
        // Pruned (see [_walked]): this action's values from the last walk.
        vTakeAction(_values, _offsets[node.id] + i * _s, actionValues, base, out, myOut, strategy, base, _s);
        continue;
      }
      _walk(node.children[i], depth + 1);
      if (_collecting) continue;

      vTakeAction(out, mine, actionValues, base, out, myOut, strategy, base, _s);
      // If this player never takes the action, the others' values from it are zero.
      if (reachSum == 0) continue;
      for (var q = 0; q < n; q++) {
        if (q != p) vAdd(out, outBase + q * _s, out, childOutBase + q * _s, _s);
      }
    }

    if (_collecting) return;
    if (node.id == _trembleAt && !_finalPass) {
      final recent = _recentRootValues.f, values = actionValues.f;
      for (var k = 0; k < actions * _s; k++) {
        final v = values[sBase + k];
        recent[k] = _haveRootValues ? 0.9 * recent[k] + 0.1 * v : v;
      }
      _lastRootValues.f.setRange(0, actions * _s, values, sBase);
      _haveRootValues = true;
    }
    if (_finalPass) {
      _recordValues(node, depth, sBase);
    } else {
      final offset = _offsets[node.id];
      _values.f.setRange(offset, offset + actions * _s, actionValues.f, sBase);
      _walked[node.id] = 1;
      vUpdate(_regrets, _strategySum, offset, actionValues, sBase, out, myOut, reach, myReach, strategy, sBase,
          actions, _s,
          positive: _positiveDiscount, negative: 0.5, keep: _strategyKeep);
    }
  }

  /// While training, every action everywhere else also gets this tiny
  /// weight, so the answers to a line nobody takes still get trained.
  /// Otherwise they can stay untrained (say, the blinds jamming 80% against
  /// a 3-bet nobody makes), which in turn keeps anyone from making it.
  static const _floor = 1e-3;

  /// The floor is only added every few iterations (and weighs that much
  /// more then): walking every line nobody takes is slow.
  static const _floorEvery = 8;
  double _floorNow = 0;

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
    final values = _lastRootValues.f, tremble = _tremble.f, reach = _reach.f;
    tremble.fillRange(0, actions * _s, 0);
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
          final v = values[j * _s + h];
          if (v > best) best = v;
        }
        gap[h] = values[i * _s + h] - best;
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
        tremble[i * _s + h] = _trembleWeight;
        taken += reach[myReach + h];
      }
    }
  }

  void _fillStrategy(PreflopDecision node, int sBase) {
    final a = node.actions.length;
    final offset = _offsets[node.id];
    if (_finalPass) {
      _strategy.f.setRange(sBase, sBase + a * _s, _average.f, offset);
    } else {
      // Regret matching: play each action in proportion to its positive regret.
      vRegretMatch(_regrets, offset, _strategy, sBase, a, _s);
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
    final offset = _offsets[node.id], size = node.actions.length * _s;
    vScale(_values, offset, _actionValues, sBase, size, 1 / opponents);
    if (node.id != _trembleAt || !_haveRootValues) return;
    // A choice the user's hand (almost) never makes is only answered by
    // the opponents' tiny "tremble" training, whose average can drift into
    // something that choice would exploit, though their recent strategies
    // don't allow it. Its value is the lower of the two.
    final strategy = _strategy.f, recent = _recentRootValues.f, values = _values.f;
    for (var k = 0; k < size; k++) {
      if (strategy[sBase + k] < 0.01) values[offset + k] = min(values[offset + k], recent[k] / opponents);
    }
  }

  void _terminal(PreflopTerminal t, int depth) {
    final n = _n;
    final c = t.contributions;
    final out = _out, mass = _mass;
    final outBase = depth * n * _s, massBase = depth * n;
    double othersMass(int q) {
      var m = 1.0;
      for (var j = 0; j < n; j++) {
        if (j != q) m *= mass[massBase + j];
      }
      return m;
    }

    // Everyone pays what they put in; pot shares are added below.
    for (var q = 0; q < n; q++) {
      vFill(out, outBase + q * _s, _s, -c[q] * othersMass(q));
    }
    if (t.uncontested) {
      final winner = t.live.single;
      vAddScalar(out, outBase + winner * _s, _s, t.pots.single.amount * othersMass(winner));
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

    final equityAt = _equityAt;
    for (final pot in t.pots) {
      final e = pot.eligible;
      var outside = foldedMass;
      for (final k in t.live) {
        if (!e.contains(k)) outside *= mass[massBase + k];
      }
      final amount = pot.amount * outside;
      if (amount == 0) continue;

      if (e.length == 1) {
        vAddScalar(out, outBase + e.single * _s, _s, amount);
      } else if (e.length == 2) {
        final i = e[0], j = e[1];
        final vi = outBase + i * _s, vj = outBase + j * _s;
        vAddScaled(out, vi, _vsRange, equityAt[j], _s, amount);
        vAddScaled(out, vj, _vsRange, equityAt[i], _s, amount);
        if (withEdge) {
          final edge = t.inPosition == i ? t.positionEdge : -t.positionEdge;
          vAddScaled(out, vi, _closeVsRange, equityAt[j], _s, amount * edge);
          vAddScaled(out, vj, _closeVsRange, equityAt[i], _s, -amount * edge);
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
    final massBase = depth * n, outBase = depth * n * _s;
    final mass = _mass, product = _product;
    for (final k in e) {
      if (mass[massBase + k] <= 0) return;
    }
    var norm = 0.0;
    for (final i in e) {
      final pBase = i * _s;
      vFill(product, pBase, _s, 1);
      for (final k in e) {
        if (k != i) vMultiplyScaled(product, pBase, _vsRange, _equityAt[k], _s, 1 / mass[massBase + k]);
      }
      norm += vDot(_reach, _reachAt[massBase + i], product, pBase, _s) / mass[massBase + i];
    }
    if (norm <= 0) return;
    for (final i in e) {
      var others = 1.0;
      for (final k in e) {
        if (k != i) others *= mass[massBase + k];
      }
      vAddScaled(_out, outBase + i * _s, product, i * _s, _s, amount * others / norm);
    }
  }

  /// Equity (and closeness) of each hand against the range whose reach
  /// vector starts at [reachStart] (unnormalized). Returns where the numbers
  /// start in [_vsRange] and [_closeVsRange]; they are only recomputed when
  /// the range changed.
  int _vsRangeOf(int reachStart, bool withCloseness) {
    final slot = reachStart ~/ _s;
    final outBase = slot * _s;
    if (_cacheStamp[slot] == _slotStamp[slot] && (!withCloseness || _cacheCloseness[slot] == 1)) {
      return outBase;
    }
    _cacheStamp[slot] = _slotStamp[slot];
    _cacheCloseness[slot] = withCloseness ? 1 : 0;
    _rangeEquity.against(_reach, reachStart, _vsRange, withCloseness ? _closeVsRange : null, outBase);
    return outBase;
  }
}
