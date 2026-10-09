/// Talking to the solvers' Web Workers (lib/solver_worker.dart), from the
/// page or from a worker starting more of them: browsers have no isolates.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'branch_jobs.dart';
import 'message_queue.dart';
import 'postflop/postflop_tree.dart';
import 'preflop/preflop_solver.dart';
import 'preflop/preflop_tree.dart';

/// Whether this code was compiled to WebAssembly (else to JavaScript).
const _wasm = bool.fromEnvironment('dart.tool.dart2wasm');

/// The worker's scripts: lib/solver_worker.dart compiled next to the app by
/// tool/build_web.dart, to WebAssembly (a module script starts it) and to
/// JavaScript for browsers that can't run that.
enum _Script {
  wasm('solver_worker_wasm.js', 'module'),
  js('solver_worker.js', 'classic');

  const _Script(this.file, this.type);

  final String file;
  final String type;

  /// With the build number, so browsers don't use a copy cached from an older build.
  String get url {
    const build = String.fromEnvironment('SOLVER_WORKER_BUILD');
    return build.isEmpty ? file : '$file?build=$build';
  }
}

extension SolverArray on JSFloat64Array {
  /// [toDart] for numbers a solver reads over and over. In WebAssembly,
  /// [toDart] leaves the array in JavaScript, where every read is a call
  /// out of WebAssembly (preflop solves took 1.4 times as long), so it is
  /// copied in. In JavaScript nothing changes.
  Float64List get toSolver {
    final list = toDart;
    return _wasm ? (Float64List(list.length)..setAll(0, list)) : list;
  }
}

extension on JSTypedArray {
  external JSArrayBuffer get buffer;
}

/// What to hand over with a message holding [arrays] (made by `toJS`):
/// their memory, instead of copying it. Each must be a fresh array, or one
/// the sender no longer uses (in JavaScript `toJS` is the Dart list itself).
List<JSObject> transferOf(List<JSTypedArray> arrays) => [for (final a in arrays) a.buffer];

/// A message to a solver worker. [kind] says which fields it has:
/// - `preflop`: solve a whole game ([spec], [iterations], [threads],
///   [equity], the players' starting [ranges] if any, and for a warm start
///   the game it starts from, [warmSpec], and that game's strategies,
///   [warm]), replying with `progress` and then `solved`;
/// - `postflop`: solve a street ([spec], [iterations], [threads], both
///   players' [ranges]), replying `solved`;
/// - `preflopBranches`, `postflopBranches`: become a worker thread of such
///   a solve (a [BranchJob]: [spec], [equity] or [ranges], [roots], and
///   [warm] for a warm start), then
///   answer `walk` ([t], [last], [active], [reach], [mass]) with `walked`
///   and `export` with `exported`.
extension type SolverRequest._(JSObject _) implements JSObject {
  external factory SolverRequest({
    required String kind,
    String spec,
    int iterations,
    int threads,
    JSFloat64Array equity,
    JSArray<JSFloat64Array> ranges,
    JSInt32Array roots,
    int t,
    bool last,
    JSUint8Array active,
    JSFloat64Array reach,
    JSFloat64Array mass,
    String warmSpec,
    JSFloat32Array warm,
  });

  factory SolverRequest.preflop(
    PreflopSpec spec,
    Float64List equity, {
    required int iterations,
    required int threads,
    Float64List? ranges,
    PreflopSolution? warmFrom,
  }) =>
      SolverRequest(
        kind: 'preflop',
        spec: jsonEncode(spec.toJson()),
        iterations: iterations,
        threads: threads,
        equity: equity.toJS,
        ranges: [if (ranges != null) ranges.toJS].toJS,
        warmSpec: warmFrom == null ? '' : jsonEncode(warmFrom.tree.spec.toJson()),
        warm: (warmFrom?.strategy ?? Float32List(0)).toJS,
      );

  factory SolverRequest.postflop(
    PostflopSpec spec,
    List<Float64List> ranges, {
    required int iterations,
    required int threads,
  }) =>
      SolverRequest(
        kind: 'postflop',
        spec: jsonEncode(spec.toJson()),
        iterations: iterations,
        threads: threads,
        ranges: [for (final r in ranges) r.toJS].toJS,
      );

  factory SolverRequest.branches(BranchJob job) => switch (job) {
        PreflopBranchJob() => SolverRequest(
            kind: 'preflopBranches',
            spec: jsonEncode(job.spec.toJson()),
            equity: job.equity.toJS,
            roots: Int32List.fromList(job.roots).toJS,
            warm: (job.warm ?? Float32List(0)).toJS,
          ),
        PostflopBranchJob() => SolverRequest(
            kind: 'postflopBranches',
            spec: jsonEncode(job.spec.toJson()),
            ranges: [for (final r in job.ranges) r.toJS].toJS,
            roots: Int32List.fromList(job.roots).toJS,
          ),
      };

  external String get kind;
  external String get spec;
  external int get iterations;
  external int get threads;
  external JSFloat64Array get equity;
  external JSArray<JSFloat64Array> get ranges;
  external JSInt32Array get roots;
  external int get t;
  external bool get last;
  external JSUint8Array get active;
  external JSFloat64Array get reach;
  external JSFloat64Array get mass;
  external String? get warmSpec;
  external JSFloat32Array? get warm;

  /// The warm start's strategies ([warm]), if any.
  Float32List? get warmStrategies {
    final w = warm?.toDart;
    return w == null || w.isEmpty ? null : w;
  }

  /// The solution a `preflop` solve starts from, if any (only its strategies
  /// are sent).
  PreflopSolution? get warmFrom {
    final s = warmSpec, w = warmStrategies;
    if (s == null || s.isEmpty || w == null) return null;
    return PreflopSolution(PreflopTree(PreflopSpec.fromJson(jsonDecode(s) as Map<String, Object?>)), w, Float32List(0));
  }

  PreflopSpec get preflopSpec => PreflopSpec.fromJson(jsonDecode(spec) as Map<String, Object?>);
  PostflopSpec get postflopSpec => PostflopSpec.fromJson(jsonDecode(spec) as Map<String, Object?>);

  BranchJob get branchJob => switch (kind) {
        'preflopBranches' => PreflopBranchJob(preflopSpec, equity.toSolver, roots.toDart, warm: warmStrategies),
        _ => PostflopBranchJob(postflopSpec, [for (final r in ranges.toDart) r.toSolver], roots.toDart),
      };
}

/// A message from a solver worker: `ready` once it runs, `progress`,
/// `solved` ([strategy], [values]), `walked` ([walked]), `exported`
/// ([offsets], [average], [ownedValues]) or `failed` ([error]).
extension type SolverReply._(JSObject _) implements JSObject {
  external factory SolverReply({
    required String kind,
    double progress,
    JSFloat32Array strategy,
    JSFloat32Array values,
    JSFloat64Array walked,
    JSInt32Array offsets,
    JSFloat64Array average,
    JSFloat64Array ownedValues,
    String error,
  });

  external String get kind;
  external double get progress;
  external JSFloat32Array get strategy;
  external JSFloat32Array get values;
  external JSFloat64Array get walked;
  external JSInt32Array get offsets;
  external JSFloat64Array get average;
  external JSFloat64Array get ownedValues;
  external String get error;
}

/// A Web Worker running lib/solver_worker.dart.
class SolverWorker {
  SolverWorker._(this._worker, this._events, {required this.wasm});

  final web.Worker _worker;
  final MessageQueue _events;

  /// Whether it runs the WebAssembly build.
  final bool wasm;

  /// The scripts a page still tries, fastest first. One is dropped once
  /// it couldn't be used: the page doesn't have it (`flutter run` doesn't
  /// build the worker) or can't run it (no WasmGC).
  static final _scripts = [_Script.wasm, _Script.js];

  static void disable() => _scripts.clear();

  /// Uses the JavaScript build from now on.
  static void disableWasm() => _scripts.remove(_Script.wasm);

  /// Starts a worker, or returns null when there is none to use.
  static Future<SolverWorker?> start() async {
    // In a worker: its own script, so the workers it starts run the same build.
    if (!globalContext.has('window')) {
      final self = (globalContext as web.WorkerGlobalScope).location.href;
      return _start(self, _wasm ? _Script.wasm : _Script.js);
    }
    while (_scripts.isNotEmpty) {
      final script = _scripts.first;
      final worker = await _start(script.url, script);
      if (worker != null) return worker;
      _scripts.remove(script);
    }
    return null;
  }

  static Future<SolverWorker?> _start(String url, _Script script) async {
    final web.Worker worker;
    try {
      worker = web.Worker(url.toJS, web.WorkerOptions(type: script.type));
    } on Object {
      return null;
    }
    final events = StreamController<_Event>();
    worker.onmessage = ((web.MessageEvent event) => events.add(_Reply(event.data as SolverReply))).toJS;
    worker.onerror = ((web.Event event) {
      events.add(_Failure(event.isA<web.ErrorEvent>() ? (event as web.ErrorEvent).message : 'not started'));
    }).toJS;
    final queue = MessageQueue(events.stream);
    // It says it's ready as soon as it runs: failing first means it can't.
    if (await queue.next is! _Reply) {
      worker.terminate();
      return null;
    }
    return SolverWorker._(worker, queue, wasm: script == _Script.wasm);
  }

  /// [transfer]: buffers handed over instead of copied.
  void send(SolverRequest request, [List<JSObject> transfer = const []]) =>
      _worker.postMessage(request, transfer.toJS);

  /// The next reply, in order. Throws if the worker failed.
  Future<SolverReply> next() async {
    switch (await _events.next as _Event) {
      case _Reply(:final reply) when reply.kind != 'failed':
        return reply;
      case _Reply(:final reply):
        throw StateError('Solver worker failed: ${reply.error}');
      case _Failure(:final error):
        throw StateError('Solver worker failed: $error');
    }
  }

  void stop() {
    _worker.terminate();
    _events.cancel();
  }
}

sealed class _Event {}

final class _Reply extends _Event {
  _Reply(this.reply);
  final SolverReply reply;
}

final class _Failure extends _Event {
  _Failure(this.error);
  final String error;
}
