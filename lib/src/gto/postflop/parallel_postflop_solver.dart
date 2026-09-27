import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../message_queue.dart';
import 'postflop_solver.dart';
import 'postflop_tree.dart';

/// How a street's tree is split between threads: the coordinator keeps the
/// top ("trunk") decisions, each "frontier" decision starts a branch that
/// one worker solves in full.
class PostflopWorkPlan {
  PostflopWorkPlan(PostflopTree tree, int workers, {required int runouts}) {
    final work = <int, double>{};
    double measure(PostflopNode node) => switch (node) {
          // Showdowns sweep every runout for both players; folds are cheap.
          PostflopTerminal() => node.foldedBy >= 0 ? 1.0 : 2.0 * runouts,
          PostflopDecision() => work[node.id] =
              node.actions.length + node.children.fold(0.0, (sum, c) => sum + measure(c)),
        };
    measure(tree.root);

    // The coordinator keeps only the decisions made before anyone bets (so
    // at most the check-check showdown is evaluated there); every decision
    // facing a bet starts a worker branch. That spreads the costly showdowns
    // evenly over the workers.
    void split(PostflopNode node) {
      if (node is! PostflopDecision) return;
      final facingBet = node.actions.any((a) => a.move == PostflopMove.fold);
      if (facingBet) {
        frontier.add(node.id);
        return;
      }
      trunk.add(node.id);
      node.children.forEach(split);
    }

    split(tree.root);
    final order = [for (var i = 0; i < frontier.length; i++) i]
      ..sort((a, b) => work[frontier[b]]!.compareTo(work[frontier[a]]!));
    final load = List.filled(workers, 0.0);
    assignments = List.generate(workers, (_) => <int>[]);
    for (final slot in order) {
      var w = 0;
      for (var k = 1; k < workers; k++) {
        if (load[k] < load[w]) w = k;
      }
      assignments[w].add(slot);
      load[w] += work[frontier[slot]]!;
    }
    assignments.removeWhere((a) => a.isEmpty);
  }

  final List<int> trunk = [];
  final List<int> frontier = [];
  late final List<List<int>> assignments;
}

/// Solves one street using several threads; same result as
/// [PostflopSolver.solve] on one thread.
Future<PostflopSolution> solvePostflopInParallel(
  PostflopSpec spec,
  List<Float64List> ranges, {
  required int iterations,
  required int threads,
}) async {
  if (threads < 2) return PostflopSolver(spec, ranges).solve(iterations: iterations);
  final plan = PostflopWorkPlan(
    PostflopTree(spec, hands: 1),
    threads,
    runouts: switch (spec.board.length) { 5 => 1, 4 => 48, _ => 40 },
  );
  if (plan.frontier.isEmpty) return PostflopSolver(spec, ranges).solve(iterations: iterations);
  final coordinator = PostflopSolver.part(spec, ranges, owned: plan.trunk, frontier: plan.frontier);
  // Start every worker at once (each builds its own copy of the tree).
  final workers = await Future.wait([
    for (final slots in plan.assignments)
      _Worker.start(spec, ranges, [for (final s in slots) plan.frontier[s]], slots),
  ]);
  final n = coordinator.hands.length;

  Future<void> round(int t, {required bool last}) async {
    coordinator.collectFrontier();
    await Future.wait([for (final w in workers) w.run(coordinator, t, last: last, hands: n)]);
    coordinator.finishFromFrontier();
  }

  try {
    for (var t = 1; t <= iterations; t++) {
      coordinator.beginIteration(t);
      await round(t, last: false);
    }
    coordinator.beginFinalPass();
    await round(iterations + 1, last: true);

    final tree = coordinator.tree;
    final strategy = Float32List(tree.storageSize);
    final values = Float32List(tree.storageSize)..fillRange(0, tree.storageSize, double.nan);
    void copy(Int32List offsets, Float64List average, Float64List vals) {
      for (final node in tree.decisions) {
        final from = offsets[node.id];
        if (from < 0) continue;
        final size = node.actions.length * n;
        strategy.setRange(node.offset, node.offset + size, average, from);
        values.setRange(node.offset, node.offset + size, vals, from);
      }
    }

    copy(coordinator.offsets, coordinator.ownedAverage, coordinator.ownedValues);
    for (final w in workers) {
      final (offsets, average, vals) = await w.export();
      copy(offsets, average, vals);
    }
    return PostflopSolution(tree, coordinator.hands, strategy, values);
  } finally {
    for (final w in workers) {
      w.stop();
    }
  }
}

class _Worker {
  _Worker._(this._isolate, this._send, this._replies, this._slots);

  static Future<_Worker> start(
    PostflopSpec spec,
    List<Float64List> ranges,
    List<int> roots,
    List<int> slots,
  ) async {
    final replies = ReceivePort();
    final isolate = await Isolate.spawn(
      _workerMain,
      (replies.sendPort, spec, ranges, roots),
      onError: replies.sendPort,
    );
    final queue = MessageQueue(replies);
    final send = await queue.next as SendPort;
    return _Worker._(isolate, send, queue, slots);
  }

  final Isolate _isolate;
  final SendPort _send;
  final MessageQueue _replies;
  final List<int> _slots;

  Future<void> run(PostflopSolver coordinator, int t, {required bool last, required int hands}) async {
    final block = 2 * hands;
    final reach = Float64List(_slots.length * block);
    final mass = Float64List(_slots.length * 2);
    final active = Uint8List(_slots.length);
    for (var k = 0; k < _slots.length; k++) {
      final slot = _slots[k];
      active[k] = coordinator.frontierActive[slot];
      if (active[k] == 0) continue;
      reach.setRange(k * block, (k + 1) * block, coordinator.frontierReach, slot * block);
      mass.setRange(k * 2, (k + 1) * 2, coordinator.frontierMass, slot * 2);
    }
    _send.send((t, last, active, reach, mass));
    final values = await _replies.next as Float64List;
    for (var k = 0; k < _slots.length; k++) {
      coordinator.frontierValues.setRange(_slots[k] * block, (_slots[k] + 1) * block, values, k * block);
    }
  }

  Future<(Int32List, Float64List, Float64List)> export() async {
    _send.send('export');
    return await _replies.next as (Int32List, Float64List, Float64List);
  }

  void stop() {
    _send.send('stop');
    _isolate.kill(priority: Isolate.beforeNextEvent);
    _replies.cancel();
  }
}

void _workerMain((SendPort, PostflopSpec, List<Float64List>, List<int>) setup) {
  final (reply, spec, ranges, roots) = setup;
  final tree = PostflopTree(spec, hands: 1);
  final owned = <int>[];
  void collect(PostflopNode node) {
    if (node is PostflopDecision) {
      owned.add(node.id);
      node.children.forEach(collect);
    }
  }

  for (final id in roots) {
    collect(tree.decisions[id]);
  }
  final solver = PostflopSolver.part(spec, ranges, owned: owned);
  final block = 2 * solver.hands.length;
  var finalPass = false;

  final inbox = ReceivePort();
  reply.send(inbox.sendPort);
  inbox.listen((message) {
    if (message == 'stop') {
      inbox.close();
    } else if (message == 'export') {
      reply.send((solver.offsets, solver.ownedAverage, solver.ownedValues));
    } else {
      final (t, last, active, reach, mass) = message as (int, bool, Uint8List, Float64List, Float64List);
      if (last && !finalPass) {
        solver.beginFinalPass();
        finalPass = true;
      } else if (!last) {
        solver.beginIteration(t);
      }
      final values = Float64List(roots.length * block);
      for (var k = 0; k < roots.length; k++) {
        if (active[k] == 0) continue;
        solver.walkBranch(roots[k], reach, k * block, mass, k * 2, values, k * block);
      }
      reply.send(values);
    }
  });
}
