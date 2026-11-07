/// The app's side of the background jobs: [Jobs] queues them on two lanes
/// and hands back a [JobHandle] for each. Where they run is a [JobBackend]'s
/// business (isolates, Web Workers, or the same thread), so this file uses
/// only dart:async.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'backend_inline.dart';
import 'job_registry.dart';
import 'jobs_core.dart';

/// Two lanes, so a slow analysis never delays a bot move (and vice versa).
enum JobLane { coach, bot }

/// Tells a backend that a running job is no longer wanted.
class CancelToken {
  final _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  /// Completes when [cancel] is called.
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

/// Runs job requests somewhere: one at a time per lane (Jobs makes sure).
abstract interface class JobBackend {
  JobPlatform get platform;

  /// False when jobs run on the page itself (no worker): caps are short
  /// and "Think longer" is greyed out.
  bool get background;

  /// Runs [request] (see encodeRequest) and gives its reply string. When
  /// [token] is cancelled it stops the job (kills its thread) and may
  /// complete with [JobCancelled], or never.
  Future<String> run(JobLane lane, String request, CancelToken token);

  /// Stops every thread it started.
  void dispose();
}

/// Starts background jobs: first in, first out per lane, one running job
/// per lane. One [Jobs] per game screen, disposed of with it, so leaving a
/// game stops its threads.
class Jobs {
  /// [timer] makes the safety timers (tests pass a fake clock).
  Jobs.using(this._backend, {Timer Function(Duration duration, void Function() callback)? timer})
      : _timer = timer ?? Timer.new;

  /// Jobs on the same thread with no time cap (tests, and widget tests
  /// pumping one screen): kitJobs plus [extra].
  factory Jobs.inline({Map<String, GameJob<Object?, Object?>> extra = const {}}) =>
      Jobs.using(InlineBackend(jobs: {...kitJobs, ...extra}, platform: JobPlatform.test, background: true));

  final JobBackend _backend;
  final Timer Function(Duration duration, void Function() callback) _timer;
  final _queues = {for (final lane in JobLane.values) lane: Queue<_Entry>()};
  final Map<JobLane, _Entry?> _running = {};
  var _nextId = 1;
  var _disposed = false;

  bool get background => _backend.background;
  JobPlatform get platform => _backend.platform;

  /// Queues [job] on [lane]. Without a [cap], the cap is capFor([kind]):
  /// none in tests. The handle's result fails with [JobCancelled] when it
  /// is cancelled, or with [JobFailed] when the job throws or runs 2 s
  /// past its cap.
  JobHandle<O> start<I, O>(
    GameJob<I, O> job,
    I input, {
    JobLane lane = JobLane.coach,
    JobKind kind = JobKind.coach,
    Duration? cap,
  }) {
    final limit = cap ?? capFor(kind, platform, background: background);
    final entry = _Entry(this, lane, limit, (Object? json) => job.decodeOutput(json));
    final handle = JobHandle<O>._(entry, job.name);
    if (_disposed) {
      entry.finish(error: const JobCancelled());
      return handle;
    }
    try {
      entry.request = encodeRequest(_nextId++, job, input, cap: limit, platform: platform);
    } on Object catch (error) {
      entry.finish(error: JobFailed('bad input: $error'));
      return handle;
    }
    _queues[lane]!.add(entry);
    _pump(lane);
    return handle;
  }

  /// Cancels every job and stops the backend's threads.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final lane in JobLane.values) {
      for (final entry in [..._queues[lane]!, ?_running[lane]]) {
        entry.cancel();
      }
    }
    _backend.dispose();
  }

  void _pump(JobLane lane) {
    if (_disposed || _running[lane] != null) return;
    final queue = _queues[lane]!;
    if (queue.isEmpty) return;
    final entry = queue.removeFirst();
    _running[lane] = entry;
    entry.running = true;
    // The safety timer starts when the job starts running, not while it waits.
    if (entry.cap case final cap?) {
      entry.timer = _timer(cap + const Duration(seconds: 2), () => entry.finish(error: JobFailed('timeout')));
    }
    _backend.run(lane, entry.request, entry.token).then(entry.reply, onError: (Object error) {
      entry.finish(error: error is JobCancelled || error is JobFailed ? error : JobFailed('$error'));
    });
  }

  /// [entry] is done: frees its lane and starts the next job there.
  void _done(_Entry entry) {
    _queues[entry.lane]!.remove(entry);
    if (_running[entry.lane] == entry) {
      _running[entry.lane] = null;
      _pump(entry.lane);
    }
  }
}

/// One job's place in [Jobs]: queued, running, then done (exactly once:
/// whatever arrives after that, a late reply included, is dropped).
class _Entry {
  _Entry(this._jobs, this.lane, this.cap, this._decode) {
    // Nobody may be waiting on a cancelled job: that's not an error to report.
    _result.future.ignore();
  }

  final Jobs _jobs;
  final JobLane lane;
  final Duration? cap;
  final Object? Function(Object? json) _decode;
  final token = CancelToken();
  final _result = Completer<Object?>();
  String request = '';
  bool running = false;
  Timer? timer;

  bool get isDone => _result.isCompleted;

  void reply(String reply) {
    if (isDone) return;
    try {
      final message = jsonDecode(reply) as Map<String, Object?>;
      if (message['err'] case final String error) {
        finish(error: JobFailed(error));
      } else {
        finish(value: _decode(message['out']));
      }
    } on Object catch (error) {
      finish(error: JobFailed('bad reply: $error'));
    }
  }

  void cancel() => finish(error: const JobCancelled());

  void finish({Object? value, Object? error}) {
    if (isDone) return;
    timer?.cancel();
    if (error != null) {
      // A job stopped early: its thread goes (the backend kills it).
      token.cancel();
      _result.completeError(error);
    } else {
      _result.complete(value);
    }
    running = false;
    _jobs._done(this);
  }
}

/// A started job: its result, and a way to cancel it.
class JobHandle<O> {
  JobHandle._(this._entry, this.name);

  final _Entry _entry;

  /// The job's name (`gomoku.coach`).
  final String name;

  /// The output, or [JobCancelled] / [JobFailed].
  late final Future<O> result = _entry._result.future.then((value) => value as O);

  bool get isDone => _entry.isDone;
  bool get isRunning => _entry.running;

  /// Cancels the job, queued or running; nothing happens if it is done.
  void cancel() => _entry.cancel();
}
