/// Running jobs on worker threads that are kept from one job to the next
/// (browsers' Web Workers), in plain Dart so tests can drive it with fake
/// workers: backend_web.dart only adds the Web Worker itself.
library;

import 'dart:async';
import 'dart:convert';

import 'jobs.dart';
import 'jobs_core.dart';

/// One worker thread: ready with the names of its jobs, then running one
/// job at a time. A subclass sends requests to the thread ([post]), ends
/// it ([terminate]), and passes on what the thread says ([replied],
/// [died]).
abstract class JobWorker {
  JobWorker({required this.wasm});

  /// Started from WebAssembly: when it dies mid-job, the job is tried
  /// again in JavaScript.
  final bool wasm;

  /// The jobs it has (from its ready message).
  Set<String> jobs = const {};

  /// It died or was stopped: never used again.
  bool get dead => _dead;
  var _dead = false;

  /// A job was given to it and has had no reply. Jobs runs one job per
  /// lane, so a busy worker's job was cancelled (or timed out) and its
  /// stop may still be on the way: it is never given another job.
  bool get busy => _reply != null;

  Completer<String>? _reply;

  /// Sends [request] to the thread.
  void post(String request);

  /// Ends the thread at once (a search can't be stopped any other way).
  void terminate();

  /// Runs [request]; when [token] is cancelled first, terminates the
  /// thread and fails with JobCancelled.
  Future<String> run(String request, CancelToken token) {
    assert(!busy && !dead, 'a worker runs one job, once free');
    final reply = Completer<String>();
    _reply = reply;
    unawaited(token.whenCancelled.then((_) {
      if (reply.isCompleted) return;
      // Its thread goes only if this is still its job (it always is: a
      // busy worker never gets another).
      if (identical(_reply, reply)) stop();
      reply.completeError(const JobCancelled());
    }));
    post(request);
    return reply.future;
  }

  /// The thread's reply to the running job ([text] null: not text).
  void replied(String? text) {
    final reply = _reply;
    _reply = null;
    if (reply == null || reply.isCompleted) return;
    if (text == null) {
      reply.completeError(JobFailed('a reply that is not text'));
    } else {
      reply.complete(text);
    }
  }

  /// The thread died (an uncaught error: a WebAssembly trap, say).
  void died(String message) {
    _dead = true;
    terminate();
    final reply = _reply;
    _reply = null;
    if (reply != null && !reply.isCompleted) reply.completeError(WorkerDied(message));
  }

  void stop() {
    _dead = true;
    _reply = null;
    terminate();
  }
}

/// A worker died mid-job.
class WorkerDied implements Exception {
  WorkerDied(this.message);
  final String message;

  @override
  String toString() => 'WorkerDied: $message';
}

/// A way to start workers (a script), tried in order.
class WorkerScript {
  const WorkerScript({required this.platform, required this.start});

  /// What its workers run as (webWasm or webJs).
  final JobPlatform platform;

  /// A ready worker, or null when the script is missing or can't run here.
  final Future<JobWorker?> Function() start;

  bool get wasm => platform == JobPlatform.webWasm;
}

/// Runs each lane's jobs on its own worker, started on first use and kept
/// for the next job.
///
/// - **Cancel:** the worker is terminated, and the lane's next job starts
///   a new one. That next job often starts in the same step as the cancel
///   (the review's slider, Think longer, New game), before the old job's
///   stop has run: a worker still busy is therefore never reused.
/// - **Which script:** the first of [scripts] that gives a worker with the
///   job. A script with none (missing, unable to run, or from another
///   build: its ready message lacks the job) is dropped from [scripts],
///   which callers may share for a whole page. So is WebAssembly when its
///   worker dies mid-job: the job is tried again on the next script.
/// - **No script left:** jobs run on [page] with the page's short caps.
class WorkerBackend implements JobBackend {
  WorkerBackend({required this.scripts, required this._page, required this._pagePlatform});

  /// The scripts still tried, first first.
  final List<WorkerScript> scripts;
  final JobBackend _page;
  final JobPlatform _pagePlatform;

  final _lanes = <JobLane, JobWorker>{};
  var _disposed = false;

  @override
  JobPlatform get platform => scripts.isEmpty ? _pagePlatform : scripts.first.platform;

  /// False once no script is left: jobs then run on the page.
  @override
  bool get background => scripts.isNotEmpty;

  /// The lane's worker now, if any (for tests).
  JobWorker? workerOn(JobLane lane) => _lanes[lane];

  @override
  Future<String> run(JobLane lane, String request, CancelToken token) async {
    final name = (jsonDecode(request) as Map<String, Object?>)['job'] as String;
    while (true) {
      if (token.isCancelled || _disposed) throw const JobCancelled();
      var worker = _lanes[lane];
      if (worker == null || worker.dead || worker.busy || !worker.jobs.contains(name)) {
        worker?.stop();
        _lanes.remove(lane);
        worker = await _start(name);
        // Cancelled while the worker started: the lane's next job may
        // already have its own, so this one never takes the lane.
        if (_disposed || token.isCancelled) {
          worker?.stop();
          throw const JobCancelled();
        }
        if (worker == null) return _page.run(lane, pageCaps(request), token);
        // Never two workers on a lane: one left here could only be a
        // cancelled job's, and would be lost to dispose().
        final other = _lanes[lane];
        if (other != null && other != worker) other.stop();
        _lanes[lane] = worker;
      }
      try {
        return await worker.run(request, token);
      } on WorkerDied catch (died) {
        if (_lanes[lane] == worker) _lanes.remove(lane);
        if (!worker.wasm) throw JobFailed('the worker stopped: ${died.message}');
        // WebAssembly broke where JavaScript may not: JavaScript from now on.
        scripts.removeWhere((script) => script.wasm);
      } on JobCancelled {
        // Its worker was terminated: the lane's next job starts a new one.
        if (_lanes[lane] == worker) _lanes.remove(lane);
        rethrow;
      }
    }
  }

  /// A worker that has [job], from the first script that can give one.
  Future<JobWorker?> _start(String job) async {
    while (scripts.isNotEmpty) {
      final script = scripts.first;
      final worker = await script.start();
      if (worker != null && worker.jobs.contains(job)) return worker;
      // Missing, unable to run here, or from another build.
      worker?.stop();
      scripts.remove(script);
    }
    return null;
  }

  /// [request] with the page's caps: it was made for a worker's (Jobs asks
  /// [background] before the first worker has been tried).
  static String pageCaps(String request) {
    final message = jsonDecode(request) as Map<String, Object?>;
    final cap = message['cap'] as int?;
    // Every kind but guide (5000 everywhere) gets 300 ms on the page.
    if (cap != null && cap < 5000) message['cap'] = cap < 300 ? cap : 300;
    return jsonEncode(message);
  }

  @override
  void dispose() {
    _disposed = true;
    for (final worker in _lanes.values) {
      worker.stop();
    }
    _lanes.clear();
  }
}
