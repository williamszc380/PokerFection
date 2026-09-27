import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../hand_classes.dart';
import '../message_queue.dart';
import 'preflop_equity.dart';
import 'preflop_solver.dart';
import 'preflop_tree.dart';

const _h = handClassCount;

/// How the tree is split between threads: the coordinator keeps the top
/// ("trunk") decisions; each "frontier" decision starts a branch that one
/// worker solves in full.
class PreflopWorkPlan {
  PreflopWorkPlan(this.tree, int workers) {
    final work = <int, double>{};
    double measure(PreflopNode node) => switch (node) {
          PreflopTerminal() => node.uncontested ? 0.5 : 3.0 * node.live.length,
          PreflopDecision() => work[node.id] =
              node.actions.length + node.children.fold(0.0, (sum, c) => sum + measure(c)),
        };
    final total = measure(tree.root);
    final chunk = total / (workers * 4);

    void split(PreflopNode node) {
      if (node is! PreflopDecision) return;
      if (node != tree.root && work[node.id]! <= chunk) {
        frontier.add(node.id);
        return;
      }
      trunk.add(node.id);
      node.children.forEach(split);
    }

    split(tree.root);

    // Biggest branches first, each to the least busy worker.
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

  final PreflopTree tree;
  final List<int> trunk = [];

  /// Decision ids where worker branches start (their index is the "slot").
  final List<int> frontier = [];

  /// Slots per worker.
  late final List<List<int>> assignments;
}

/// Solves a preflop game using several threads. Gives exactly the same
/// result as [PreflopSolver.solve] on one thread. [ranges]: see [PreflopSolver].
Future<PreflopSolution> solvePreflopInParallel(
  PreflopSpec spec,
  PreflopEquity equity, {
  int iterations = 200,
  required int threads,
  Float64List? ranges,
  void Function(int done, int total)? onProgress,
}) async {
  final tree = PreflopTree(spec);
  // Small games are over before the threads would pay for themselves.
  if (threads < 2 || tree.decisions.length < 250) {
    return PreflopSolver(tree, equity, ranges: ranges).solve(iterations: iterations, onProgress: onProgress);
  }
  final plan = PreflopWorkPlan(tree, threads);
  // Only the coordinator starts from the root, so only it needs the ranges.
  final coordinator =
      PreflopSolver.part(tree, equity, owned: plan.trunk, frontier: plan.frontier, ranges: ranges);
  // Start every worker at once (each builds its own copy of the tree).
  final workers = await Future.wait([
    for (final slots in plan.assignments)
      _Worker.start(spec, equity, [for (final s in slots) plan.frontier[s]], slots),
  ]);
  final n = spec.players;

  Future<void> round(int t, {required bool last}) async {
    coordinator.collectFrontier();
    await Future.wait([
      for (final w in workers) w.run(coordinator, t, last: last, players: n),
    ]);
    coordinator.finishFromFrontier();
  }

  try {
    for (var t = 1; t <= iterations; t++) {
      coordinator.beginIteration(t);
      await round(t, last: false);
      onProgress?.call(t, iterations);
    }
    coordinator.beginFinalPass();
    await round(iterations + 1, last: true);

    // Put every thread's part of the answer together.
    final strategy = Float32List(tree.storageSize);
    final values = Float32List(tree.storageSize)..fillRange(0, tree.storageSize, double.nan);
    void copy(Int32List offsets, Float64List average, Float64List vals) {
      for (final node in tree.decisions) {
        final from = offsets[node.id];
        if (from < 0) continue;
        final size = node.actions.length * _h;
        strategy.setRange(node.offset, node.offset + size, average, from);
        values.setRange(node.offset, node.offset + size, vals, from);
      }
    }

    copy(coordinator.offsets, coordinator.ownedAverage, coordinator.ownedValues);
    for (final w in workers) {
      final (offsets, average, vals) = await w.export();
      copy(offsets, average, vals);
    }
    return PreflopSolution(tree, strategy, values);
  } finally {
    for (final w in workers) {
      w.stop();
    }
  }
}

/// One worker thread, solving the branches that start at [roots].
class _Worker {
  _Worker._(this._isolate, this._send, this._replies, this._slots);

  static Future<_Worker> start(PreflopSpec spec, PreflopEquity equity, List<int> roots, List<int> slots) async {
    final replies = ReceivePort();
    // Errors arrive on the same port, so a failing worker makes the solve fail
    // instead of waiting forever.
    final isolate = await Isolate.spawn(
      _workerMain,
      (replies.sendPort, spec, equity.values, roots),
      onError: replies.sendPort,
    );
    final queue = MessageQueue(replies);
    final send = await queue.next as SendPort;
    return _Worker._(isolate, send, queue, slots);
  }

  final Isolate _isolate;
  final SendPort _send;
  final MessageQueue _replies;

  /// The coordinator's frontier slots this worker handles, in order.
  final List<int> _slots;

  /// Sends the reach data for this worker's branches and copies back their values.
  Future<void> run(PreflopSolver coordinator, int t, {required bool last, required int players}) async {
    final block = players * _h;
    final reach = Float64List(_slots.length * block);
    final mass = Float64List(_slots.length * players);
    final active = Uint8List(_slots.length);
    for (var k = 0; k < _slots.length; k++) {
      final slot = _slots[k];
      active[k] = coordinator.frontierActive[slot];
      if (active[k] == 0) continue;
      reach.setRange(k * block, (k + 1) * block, coordinator.frontierReach, slot * block);
      mass.setRange(k * players, (k + 1) * players, coordinator.frontierMass, slot * players);
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

typedef _Setup = (SendPort, PreflopSpec, Float64List, List<int>);

void _workerMain(_Setup setup) {
  final (reply, spec, equityValues, roots) = setup;
  final tree = PreflopTree(spec);
  final owned = <int>[];
  void collect(PreflopNode node) {
    if (node is PreflopDecision) {
      owned.add(node.id);
      node.children.forEach(collect);
    }
  }

  for (final id in roots) {
    collect(tree.decisions[id]);
  }
  final solver = PreflopSolver.part(tree, PreflopEquity(equityValues), owned: owned);
  final n = spec.players;
  final block = n * _h;
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
        solver.walkBranch(roots[k], reach, k * block, mass, k * n, values, k * block);
      }
      reply.send(values);
    }
  });
}

