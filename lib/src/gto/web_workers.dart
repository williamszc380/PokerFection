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
import 'preflop/preflop_tree.dart';

/// The worker's script. On the page: lib/solver_worker.dart compiled next
/// to the app by tool/build_web.dart, with the build number so browsers
/// don't use a copy cached from an older build. In a worker: its own
/// script, so the workers it starts run the same build.
String get _scriptUrl {
  if (!globalContext.has('window')) return (globalContext as web.WorkerGlobalScope).location.href;
  const build = String.fromEnvironment('SOLVER_WORKER_BUILD');
  return build.isEmpty ? 'solver_worker.js' : 'solver_worker.js?build=$build';
}

/// A message to a solver worker. [kind] says which fields it has:
/// - `preflop`: solve a whole game ([spec], [iterations], [threads],
///   [equity], and the players' starting [ranges] if any), replying with
///   `progress` and then `solved`;
/// - `postflop`: solve a street ([spec], [iterations], [threads], both
///   players' [ranges]), replying `solved`;
/// - `preflopBranches`, `postflopBranches`: become a worker thread of such
///   a solve (a [BranchJob]: [spec], [equity] or [ranges], [roots]), then
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
  });

  factory SolverRequest.preflop(
    PreflopSpec spec,
    Float64List equity, {
    required int iterations,
    required int threads,
    Float64List? ranges,
  }) =>
      SolverRequest(
        kind: 'preflop',
        spec: jsonEncode(spec.toJson()),
        iterations: iterations,
        threads: threads,
        equity: equity.toJS,
        ranges: [if (ranges != null) ranges.toJS].toJS,
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

  PreflopSpec get preflopSpec => PreflopSpec.fromJson(jsonDecode(spec) as Map<String, Object?>);
  PostflopSpec get postflopSpec => PostflopSpec.fromJson(jsonDecode(spec) as Map<String, Object?>);

  BranchJob get branchJob => switch (kind) {
        'preflopBranches' => PreflopBranchJob(preflopSpec, equity.toDart, roots.toDart),
        _ => PostflopBranchJob(postflopSpec, [for (final r in ranges.toDart) r.toDart], roots.toDart),
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
  SolverWorker._(this._worker, this._events);

  final web.Worker _worker;
  final MessageQueue _events;

  /// Cleared once a worker couldn't be used: the page has no worker
  /// script (`flutter run` doesn't build it) or can't run it.
  static bool _available = true;

  static void disable() => _available = false;

  /// Starts a worker, or returns null when there is none to use.
  static Future<SolverWorker?> start() async {
    if (!_available) return null;
    final web.Worker worker;
    try {
      worker = web.Worker(_scriptUrl.toJS);
    } on Object {
      _available = false;
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
      _available = false;
      return null;
    }
    return SolverWorker._(worker, queue);
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
