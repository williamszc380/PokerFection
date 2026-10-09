import 'dart:math';
import 'dart:typed_data';

import '../branches.dart';
import '../combos.dart';
import '../vectors.dart';
import 'postflop_tree.dart';
import 'same_rank_wins.dart';
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

/// The complete boards a street's showdowns are averaged over: the board
/// itself on the river, every river on the turn, and [flopRunouts] turn and
/// river pairs on the flop (the same ones every time for a board).
List<List<int>> runoutBoards(List<int> board, {int flopRunouts = 40}) {
  final free = [for (var c = 0; c < 52; c++) if (!board.contains(c)) c];
  switch (board.length) {
    case 5:
      return [board];
    case 4:
      return [for (final river in free) [...board, river]];
    default:
      final pairs = [
        for (var i = 0; i < free.length; i++)
          for (var j = i + 1; j < free.length; j++) (free[i], free[j]),
      ]..shuffle(Random(board.fold<int>(17, (h, c) => h * 31 + c)));
      return [for (final (turn, river) in pairs.take(flopRunouts)) [...board, turn, river]];
  }
}

/// On a turn [board]: the rivers that rank every hand alike, in groups of
/// one rank (2 to 4 rivers) whose suits can't give anyone a flush (see
/// [RunoutRanking.sameRank]). The solver shows each group down at once.
List<List<int>> sameRankRivers(List<int> board) {
  final byRank = <int, List<int>>{};
  for (var river = 0; river < 52; river++) {
    if (board.contains(river)) continue;
    // A river of a suit the board already has twice could make a flush.
    if (board.where((c) => c & 3 == river & 3).length < 2) (byRank[river >> 2] ??= []).add(river);
  }
  return [for (final rivers in byRank.values) if (rivers.length >= 2) rivers];
}

/// About how many passes over the hands a showdown on [board] takes (for
/// both players at once): one per runout or group of [sameRankRivers].
int showdownPasses(List<int> board, {int flopRunouts = 40}) => switch (board.length) {
      5 => 1,
      4 => sameRankRivers(board).fold(48, (passes, rivers) => passes - rivers.length + 1),
      _ => flopRunouts,
    };

/// "The field" for approximate answers when more than two players are in
/// the pot: all the opponents' hands in one range, each weighted by how
/// often it is the best of all of theirs (against the other opponents'
/// [ranges], over the runouts, ties counting half). The field plays like
/// whichever opponent holds the best hand.
Float64List strongestOfField(List<int> board, List<Float64List> ranges, {int flopRunouts = 20}) {
  final hands = PostflopHands(board);
  final n = hands.length, cardA = hands.cardA, cardB = hands.cardB;
  final best = List.generate(ranges.length, (_) => Float64List(n));
  final beats = List.generate(ranges.length, (_) => Float64List(n));
  final counted = Float64List(n);
  final weights = Float64List(n), wins = Float64List(n);
  final cardSum = Float64List(52), below = Float64List(52), group = Float64List(52);
  for (final complete in runoutBoards(board, flopRunouts: flopRunouts)) {
    final ranking = RunoutRanking(complete, cardA, cardB);
    // How often each hand beats each opponent's range here.
    for (var j = 0; j < ranges.length; j++) {
      weights.fillRange(0, n, 0);
      cardSum.fillRange(0, 52, 0);
      var total = 0.0;
      for (final c in ranking.order) {
        final w = ranges[j][hands.full[c]];
        weights[c] = w;
        total += w;
        cardSum[cardA[c]] += w;
        cardSum[cardB[c]] += w;
      }
      wins.fillRange(0, n, 0);
      addShowdownWins(ranking, weights, wins, cardA, cardB, below, group);
      for (final c in ranking.order) {
        // Their hands that share no card with this one.
        final possible = total - cardSum[cardA[c]] - cardSum[cardB[c]] + weights[c];
        beats[j][c] = possible > 0 ? wins[c] / possible : 1;
      }
    }
    // Held by opponent k, how often it beats all the others.
    for (final c in ranking.order) {
      counted[c]++;
      for (var k = 0; k < ranges.length; k++) {
        var product = 1.0;
        for (var j = 0; j < ranges.length; j++) {
          if (j != k) product *= beats[j][c];
        }
        best[k][c] += product;
      }
    }
  }
  final field = Float64List(comboCount);
  for (var c = 0; c < n; c++) {
    if (counted[c] == 0) continue;
    final combo = hands.full[c];
    for (var k = 0; k < ranges.length; k++) {
      field[combo] += ranges[k][combo] * best[k][c] / counted[c];
    }
  }
  return field;
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
/// The next street is solved again when it is reached. On the turn, rivers
/// that rank every hand alike are shown down together (see
/// [sameRankRivers]).
///
/// Strategies, regrets and values are kept in 32-bit numbers, each hand
/// vector padded to whole SIMD lanes, and the vector arithmetic is in
/// vectors.dart (four hands at a time in native builds). Showdown sums are
/// in 64-bit numbers.
///
/// More players in the pot (a greedy approximation): ranges after the first
/// two belong to players who only check along to showdown. A hand then wins
/// only as often as it also beats each of them, which takes value from both
/// solved players' hands, and a player whose opponent folds still has to
/// beat them at showdown.
class PostflopSolver implements BranchSolver {
  /// [ranges]: each player's weight on every combination (0-1325), in the
  /// order of [PostflopSpec.stacks] (first to act first), then the ranges
  /// of any other players checking along. With [othersFoldToBets], those
  /// players fold as soon as anyone bets, and only a checked-down pot has
  /// to beat them.
  factory PostflopSolver(PostflopSpec spec, List<Float64List> ranges,
          {int flopRunouts = 40, bool othersFoldToBets = false}) =>
      PostflopSolver.part(spec, ranges, flopRunouts: flopRunouts, othersFoldToBets: othersFoldToBets);

  /// Solves only the decisions in [owned] (all when null), for splitting the
  /// work across threads; the nodes in [frontier] are handled by workers
  /// (see `solvePostflopInParallel`, and the preflop solver for details):
  /// decisions by id, showdowns as `-1 - id` (see `PostflopWorkPlan`).
  factory PostflopSolver.part(
    PostflopSpec spec,
    List<Float64List> ranges, {
    Iterable<int>? owned,
    List<int> frontier = const [],
    int flopRunouts = 40,
    bool othersFoldToBets = false,
  }) {
    final hands = PostflopHands(spec.board);
    final tree = PostflopTree(spec, hands: hands.length);
    final n = hands.length, s = roundUpToLanes(n);
    final width = tree.decisions.fold(1, (m, d) => max(m, d.actions.length)) * s;
    final count = tree.decisions.length;
    final offsets = Int32List(count)..fillRange(0, count, -1);
    var storage = 0;
    for (final id in owned == null ? [for (final d in tree.decisions) d.id] : (owned.toList()..sort())) {
      offsets[id] = storage;
      storage += tree.decisions[id].actions.length * s;
    }
    final slots = Int32List(count)..fillRange(0, count, -1);
    final terminalSlots = Int32List(tree.terminals.length)..fillRange(0, tree.terminals.length, -1);
    for (var i = 0; i < frontier.length; i++) {
      if (frontier[i] >= 0) {
        slots[frontier[i]] = i;
      } else {
        terminalSlots[-1 - frontier[i]] = i;
      }
    }
    return PostflopSolver._(spec, tree, hands, ranges, flopRunouts, n, width, _depthOf(tree.root) + 2,
        offsets, storage, slots, terminalSlots, frontier.length, othersFoldToBets);
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
    this._offsets,
    int storage,
    this._slots,
    this._terminalSlots,
    int frontierCount,
    this._othersFoldToBets,
  )   : _n = n,
        _s = roundUpToLanes(n),
        _width = width,
        _regrets = Vec(storage),
        _strategySum = Vec(storage),
        _average = Vec(storage),
        _values = Vec(storage),
        frontierReach = Float64List(frontierCount * 2 * n),
        frontierMass = Float64List(frontierCount * 2),
        frontierActive = Uint8List(frontierCount),
        frontierValues = Float64List(frontierCount * 2 * n),
        _out = Vec(depth * 2 * roundUpToLanes(n)),
        _mass = Float64List(depth * 2),
        _reach = Vec((2 + depth) * roundUpToLanes(n)),
        _reachAt = Int32List(depth * 2),
        _actionValues = Vec(depth * width),
        _strategy = Vec(depth * width),
        _acc = Float64List(n),
        _accQ = Float64List(n),
        _valid = Float64List(n),
        _weights = Float64List(n),
        _weightsQ = Float64List(n),
        _sameRank = SameRankScratch(n),
        _rootReach = Vec(2 * roundUpToLanes(n)),
        _lastValues = Vec(storage),
        _tremble = Vec(storage),
        _trembleFrom = Int32List(tree.decisions.length)..fillRange(0, tree.decisions.length, -1),
        _haveValues = Uint8List(tree.decisions.length) {
    for (var p = 0; p < 2; p++) {
      for (var c = 0; c < n; c++) {
        _rootReach.f[p * _s + c] = ranges[p][hands.full[c]];
      }
    }
    // Players checking along beat each river differently: no groups then.
    _setUpRunouts(flopRunouts, groupRivers: ranges.length <= 2);
    if (ranges.length > 2) _setUpOthers(ranges.sublist(2));
  }

  /// With other players checking along: for each runout, how often each
  /// hand beats all of them (ties count half), and the average over runouts.
  final List<Float64List> _beatOthers = [];
  final bool _othersFoldToBets;
  Float64List? _beatOthersOnAverage;

  void _setUpOthers(List<Float64List> others) {
    final n = _n, cardA = hands.cardA, cardB = hands.cardB;
    final average = Float64List(n);
    final weights = Float64List(n), wins = Float64List(n), cardSum = Float64List(52);
    for (final runout in _runouts) {
      final beat = Float64List(n)..fillRange(0, n, 1);
      for (final range in others) {
        weights.fillRange(0, n, 0);
        cardSum.fillRange(0, 52, 0);
        var total = 0.0;
        for (final c in runout.order) {
          final w = range[hands.full[c]];
          weights[c] = w;
          total += w;
          cardSum[cardA[c]] += w;
          cardSum[cardB[c]] += w;
        }
        wins.fillRange(0, n, 0);
        addShowdownWins(runout, weights, wins, cardA, cardB, _below, _group);
        for (final c in runout.order) {
          // Their hands that share no card with this one.
          final possible = total - cardSum[cardA[c]] - cardSum[cardB[c]] + weights[c];
          beat[c] *= possible > 0 ? wins[c] / possible : 1;
        }
      }
      _beatOthers.add(beat);
      for (var c = 0; c < n; c++) {
        average[c] += beat[c] / _runouts.length;
      }
    }
    _beatOthersOnAverage = average;
  }

  final PostflopSpec spec;
  final PostflopTree tree;
  final PostflopHands hands;
  final int _n;

  /// Numbers per hand vector in this solver's arrays: the hands rounded up
  /// to whole SIMD lanes (the extra ones are never reached).
  final int _s;
  final int _width;

  /// Where each decision's numbers start in this solver's arrays (-1 if not
  /// owned): actions one after the other, [_s] numbers each.
  final Int32List _offsets;

  /// Each frontier node's slot (-1 when not on the frontier): decisions by
  /// id, and showdowns by [PostflopTerminal.id].
  final Int32List _slots;
  final Int32List _terminalSlots;

  /// For each frontier decision: both players' reach (2 x hands), their
  /// masses, whether it was reached, and the values workers computed.
  final Float64List frontierReach;
  final Float64List frontierMass;
  final Uint8List frontierActive;
  final Float64List frontierValues;
  bool _collecting = false;
  final Vec _regrets;
  final Vec _strategySum;
  final Vec _average;
  final Vec _values;
  final Vec _out;
  final Float64List _mass;
  final Vec _reach;
  final Int32List _reachAt;
  final Vec _actionValues;
  final Vec _strategy;
  final Float64List _acc;
  final Float64List _accQ;
  final Float64List _valid;
  final Float64List _weights;
  final Float64List _weightsQ;
  final SameRankScratch _sameRank;
  final _scratch = ShowdownScratch();
  final Vec _rootReach;
  final Float64List _cardSum = Float64List(52);
  final Float64List _below = Float64List(52);
  final Float64List _group = Float64List(52);
  final List<RunoutRanking> _runouts = [];

  /// On the turn, the groups of [sameRankRivers] (their rivers aren't in
  /// [_runouts]): each one's ranking, and for each hand how many of its
  /// rivers the hand holds and how many it can see.
  final List<RunoutRanking> _riverGroups = [];
  final List<Float64List> _held = [];
  final List<Float64List> _seen = [];

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
  final Vec _lastValues;
  final Vec _tremble;
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

  void _setUpRunouts(int flopRunouts, {required bool groupRivers}) {
    final board = spec.board;
    final boards = runoutBoards(board, flopRunouts: flopRunouts);
    final groups = board.length == 4 && groupRivers ? sameRankRivers(board) : const <List<int>>[];
    final grouped = {for (final rivers in groups) ...rivers};
    for (final complete in boards) {
      if (board.length == 4 && grouped.contains(complete[4])) continue;
      _runouts.add(RunoutRanking(complete, hands.cardA, hands.cardB));
    }
    for (final rivers in groups) {
      _riverGroups.add(RunoutRanking.sameRank(board, rivers, hands.cardA, hands.cardB));
      final held = Float64List(_n), seen = Float64List(_n);
      for (var c = 0; c < _n; c++) {
        held[c] = rivers.where((r) => r == hands.cardA[c] || r == hands.cardB[c]).length.toDouble();
        seen[c] = rivers.length - held[c];
      }
      _held.add(held);
      _seen.add(seen);
    }
    final free = 52 - board.length;
    _runoutsPerPair = switch (board.length) {
      5 => 1,
      4 => (free - 4).toDouble(), // rivers left once both hands are out
      // Of all turn/river pairs, the share that avoids four more cards.
      _ => boards.length * ((free - 4) * (free - 5) / 2) / (free * (free - 1) / 2),
    };
  }

  PostflopSolution solve({required int iterations, void Function(int done, int total)? onProgress}) {
    for (var t = 1; t <= iterations; t++) {
      beginIteration(t);
      _walkFromRoot();
      onProgress?.call(t, iterations);
    }
    beginFinalPass();
    _walkFromRoot();
    final strategy = Float32List(tree.storageSize), values = Float32List(tree.storageSize);
    for (final node in tree.decisions) {
      _copyOut(node, _average, strategy, node.offset);
      _copyOut(node, _values, values, node.offset);
    }
    return PostflopSolution(tree, hands, strategy, values);
  }

  /// Copies [node]'s numbers from [from] (this solver's layout) to [to] at
  /// [at], one per hand for each action.
  void _copyOut(PostflopDecision node, Vec from, List<double> to, int at) {
    final n = _n, offset = _offsets[node.id];
    for (var i = 0; i < node.actions.length; i++) {
      to.setRange(at + i * n, at + (i + 1) * n, from.f, offset + i * _s);
    }
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
    for (final node in tree.decisions) {
      final offset = _offsets[node.id];
      if (offset >= 0) vNormalize(_strategySum, offset, _average, offset, node.actions.length, _s);
    }
    _values.f.fillRange(0, _values.length, double.nan);
    _finalPass = true;
  }

  /// Where each owned decision's numbers start in [ownedAverage] and
  /// [ownedValues] (one per hand for each action), or -1.
  @override
  late final Int32List offsets = () {
    final at = Int32List(_offsets.length)..fillRange(0, _offsets.length, -1);
    var size = 0;
    for (final node in tree.decisions) {
      if (_offsets[node.id] < 0) continue;
      at[node.id] = size;
      size += node.actions.length * _n;
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
      if (_offsets[node.id] >= 0) size += node.actions.length * _n;
    }
    final owned = Float64List(size);
    for (final node in tree.decisions) {
      if (_offsets[node.id] >= 0) _copyOut(node, from, owned, offsets[node.id]);
    }
    return owned;
  }

  /// Coordinator, step 1: records each frontier decision's reach.
  void collectFrontier() {
    frontierActive.fillRange(0, frontierActive.length, 0);
    _collecting = true;
    _walkFromRoot();
    _collecting = false;
  }

  /// Coordinator, step 2: with [frontierValues] filled in, finishes the walk.
  void finishFromFrontier() => _walkFromRoot();

  /// Worker: walks the branch starting at decision [nodeId] (or the
  /// showdown `-1 - nodeId`), given both players' reach and mass there, and
  /// writes both players' values into [out].
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
      _reachAt[p] = p * _s;
      _reach.f.setRange(p * _s, p * _s + n, reach, reachAt + p * n);
    }
    _walk(nodeId >= 0 ? tree.decisions[nodeId] : tree.terminals[-1 - nodeId], 0);
    for (var p = 0; p < 2; p++) {
      out.setRange(outAt + p * n, outAt + (p + 1) * n, _out.f, p * _s);
    }
  }

  void _walkFromRoot() {
    final n = _n, root = _rootReach.f;
    for (var p = 0; p < 2; p++) {
      _reach.f.setRange(p * _s, (p + 1) * _s, root, p * _s);
      _reachAt[p] = p * _s;
      var m = 0.0;
      for (var c = 0; c < n; c++) {
        m += root[p * _s + c];
      }
      _mass[p] = m;
    }
    _walk(tree.root, 0);
  }

  void _walk(PostflopNode node, int depth) {
    switch (node) {
      case PostflopTerminal():
        final slot = _terminalSlots[node.id];
        if (slot >= 0) {
          _atFrontier(slot, depth);
        } else if (!_collecting) {
          _terminal(node, depth);
        }
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
        frontierReach.setRange(block + p * n, block + (p + 1) * n, _reach.f, _reachAt[depth * 2 + p]);
      }
      return;
    }
    for (var p = 0; p < 2; p++) {
      final at = (depth * 2 + p) * _s;
      _out.f.setRange(at, at + n, frontierValues, block + p * n);
    }
  }

  void _decision(PostflopDecision node, int depth) {
    final s = _s;
    final p = node.player, q = 1 - p;
    final actions = node.actions.length;
    final out = _out, reach = _reach, strategy = _strategy, actionValues = _actionValues;
    final outBase = depth * 2 * s;
    final childOutBase = outBase + 2 * s;
    final sBase = depth * _width;
    _fillStrategy(node, sBase);
    vFill(out, outBase, 2 * s, 0);

    final myReach = _reachAt[depth * 2 + p];
    final childReach = (2 + depth) * s;
    _reachAt[(depth + 1) * 2 + p] = childReach;
    _reachAt[(depth + 1) * 2 + q] = _reachAt[depth * 2 + q];
    final opponentMass = _mass[depth * 2 + q];
    final offset = _offsets[node.id];
    final hero = p == spec.hero;
    final trembling = hero && !_finalPass && _haveValues[node.id] == 1;
    if (trembling) {
      final from = _trembleFrom[node.id];
      if (from < 0 || (_iteration % _trembleRefresh == 0 && from != _iteration)) {
        _fillTremble(node, myReach);
        _trembleFrom[node.id] = _iteration;
      }
    }
    final myOut = outBase + p * s, mine = childOutBase + p * s;

    for (var i = 0; i < actions; i++) {
      final base = sBase + i * s;
      final reachSum = vChildReach(reach, myReach, strategy, base, 0, trembling ? _tremble : null, offset + i * s,
          reach, childReach, s);
      _mass[(depth + 1) * 2 + p] = reachSum;
      _mass[(depth + 1) * 2 + q] = opponentMass;
      if (opponentMass == 0 && reachSum == 0) {
        vFill(actionValues, base, s, 0);
        continue;
      }
      _walk(node.children[i], depth + 1);
      if (_collecting) continue;

      vTakeAction(out, mine, actionValues, base, out, myOut, strategy, base, s);
      if (reachSum != 0) vAdd(out, outBase + q * s, out, childOutBase + q * s, s);
    }

    if (_collecting) return;
    if (hero) {
      _lastValues.f.setRange(offset, offset + actions * s, actionValues.f, sBase);
      _haveValues[node.id] = 1;
    }
    if (_finalPass) {
      _recordValues(node, depth, sBase);
    } else {
      vUpdate(_regrets, _strategySum, offset, actionValues, sBase, out, myOut, reach, myReach, strategy, sBase,
          actions, s,
          positive: _positiveDiscount, negative: 0.5, keep: _strategyKeep);
    }
  }

  /// Picks, for each action at one of the user's decisions, the hands that
  /// come closest to choosing it (by last values) until they make up
  /// [_trembleShare] of the user's weight, and gives them a tiny extra
  /// weight on it. The bot's answers to every choice then get trained
  /// against a sensible range, so the value of a size GTO never uses is
  /// still meaningful. The user's own strategy and regrets are unaffected.
  void _fillTremble(PostflopDecision node, int myReach) {
    final n = _n, s = _s;
    final actions = node.actions.length;
    final offset = _offsets[node.id];
    // _acc is free here: it is only used while scoring endings.
    final values = _lastValues.f, tremble = _tremble.f, reach = _reach.f, gap = _acc;
    tremble.fillRange(offset, offset + actions * s, 0);
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
          final v = values[offset + j * s + c];
          if (v > best) best = v;
        }
        final g = values[offset + i * s + c] - best;
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
        if (gap[c] >= low && reach[myReach + c] > 0) tremble[offset + i * s + c] = _trembleWeight;
      }
    }
  }

  void _fillStrategy(PostflopDecision node, int sBase) {
    final a = node.actions.length;
    final offset = _offsets[node.id];
    if (_finalPass) {
      _strategy.f.setRange(sBase, sBase + a * _s, _average.f, offset);
    } else {
      vRegretMatch(_regrets, offset, _strategy, sBase, a, _s);
    }
  }

  /// Turns counterfactual values into chips, given that the opponent's
  /// cards (not clashing with the hand) and actions led here.
  void _recordValues(PostflopDecision node, int depth, int sBase) {
    final n = _n, s = _s;
    final q = 1 - node.player;
    _disjointWeight(_reachAt[depth * 2 + q]);
    final values = _values.f, actionValues = _actionValues.f, valid = _valid;
    final offset = _offsets[node.id];
    for (var i = 0; i < node.actions.length; i++) {
      for (var c = 0; c < n; c++) {
        final v = valid[c];
        if (v > 0) values[offset + i * s + c] = actionValues[sBase + i * s + c] / v;
      }
    }
  }

  /// `_valid[c]`: the opponent's weight on hands sharing no card with c.
  void _disjointWeight(int weightsAt) {
    final n = _n;
    final reach = _reach.f, cardSum = _cardSum, valid = _valid;
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
    final out = _out.f;
    final potEnd = spec.pot + t.bets[0] + t.bets[1];
    // With others folding to bets, only a checked-down pot has to beat them.
    final beatOthers = _othersFoldToBets && (t.bets[0] > 0 || t.bets[1] > 0) ? null : _beatOthersOnAverage;
    if (t.foldedBy < 0) {
      if (_mass[depth * 2] > 0 || _mass[depth * 2 + 1] > 0) {
        _showdown(t, depth, potEnd, beatOthers != null);
      } else {
        out.fillRange(depth * 2 * _s, (depth * 2 + 2) * _s, 0);
      }
      return;
    }
    for (var p = 0; p < 2; p++) {
      final q = 1 - p;
      final outBase = (depth * 2 + p) * _s;
      if (_mass[depth * 2 + q] == 0) {
        out.fillRange(outBase, outBase + n, 0);
        continue;
      }
      _disjointWeight(_reachAt[depth * 2 + q]);
      final valid = _valid;
      if (t.foldedBy == p || beatOthers == null) {
        final u = (t.foldedBy == p ? -t.bets[p] : potEnd - t.bets[p]).toDouble();
        for (var c = 0; c < n; c++) {
          out[outBase + c] = u * valid[c];
        }
      } else {
        // The pot, if this hand also beats the players checking along.
        for (var c = 0; c < n; c++) {
          out[outBase + c] = (potEnd * beatOthers[c] - t.bets[p]) * valid[c];
        }
      }
    }
  }

  /// A showdown: both players' values, with one pass over each runout for
  /// the two of them (a player whose opponent never gets here gets 0). With
  /// [beatOthers], a hand also has to beat the players checking along.
  void _showdown(PostflopTerminal t, int depth, int potEnd, bool beatOthers) {
    final n = _n;
    final out = _out.f;
    final weights0 = _weights, weights1 = _weightsQ, wins0 = _acc, wins1 = _accQ;
    weights0.setRange(0, n, _reach.f, _reachAt[depth * 2]);
    weights1.setRange(0, n, _reach.f, _reachAt[depth * 2 + 1]);
    wins0.fillRange(0, n, 0);
    wins1.fillRange(0, n, 0);
    for (var r = 0; r < _runouts.length; r++) {
      addShowdownWinsForBoth(_runouts[r], weights0, weights1, wins0, wins1, _scratch,
          scale: beatOthers ? _beatOthers[r] : null);
    }
    for (var g = 0; g < _riverGroups.length; g++) {
      addSameRankWins(_riverGroups[g], weights0, weights1, _held[g], _seen[g], wins0, wins1, _sameRank);
    }
    final scale = potEnd / _runoutsPerPair;
    for (var p = 0; p < 2; p++) {
      _disjointWeight(_reachAt[depth * 2 + 1 - p]);
      final valid = _valid, wins = p == 0 ? wins0 : wins1;
      final outBase = (depth * 2 + p) * _s;
      final bet = t.bets[p].toDouble();
      for (var c = 0; c < n; c++) {
        out[outBase + c] = scale * wins[c] - bet * valid[c];
      }
    }
  }
}
