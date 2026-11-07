/// Test doubles for the kit's jobs: a backend whose replies the test sends
/// by hand, and a clock whose timers the test fires.
library;

import 'dart:async';

import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/kit/jobs/jobs_core.dart';

/// A job running on [ManualBackend], waiting for the test to answer it.
class PendingJob {
  PendingJob(this.lane, this.request, this.token);

  final JobLane lane;
  final String request;
  final CancelToken token;
  final reply = Completer<String>();

  /// The job's name, read from the request.
  String get name => RegExp(r'"job":"([^"]+)"').firstMatch(request)![1]!;

  /// The cap sent with it, in ms (null: none).
  int? get cap => int.tryParse(RegExp(r'"cap":(\d+)').firstMatch(request)?[1] ?? '');
}

/// Runs nothing until told: [answer] runs a job for real (runJobRequest),
/// [fail] makes it throw, and a late answer can be sent after a cancel.
class ManualBackend implements JobBackend {
  ManualBackend(this.jobs, {this.platform = JobPlatform.test, this.background = true});

  final Map<String, GameJob<Object?, Object?>> jobs;

  @override
  final JobPlatform platform;

  @override
  final bool background;

  /// Every job the backend was given, in order (answered ones too).
  final started = <PendingJob>[];
  var disposed = false;

  /// The jobs running now (not answered, not cancelled).
  List<PendingJob> get running => [
        for (final job in started)
          if (!job.reply.isCompleted && !job.token.isCancelled) job,
      ];

  /// The running job on [lane], if any.
  PendingJob? on(JobLane lane) => running.where((job) => job.lane == lane).firstOrNull;

  @override
  Future<String> run(JobLane lane, String request, CancelToken token) {
    final job = PendingJob(lane, request, token);
    started.add(job);
    return job.reply.future;
  }

  /// Runs [job] for real and sends its reply (even if it was cancelled: a
  /// late reply).
  void answer(PendingJob job) {
    if (!job.reply.isCompleted) job.reply.complete(runJobRequest(job.request, jobs));
  }

  void fail(PendingJob job, [Object error = 'broken']) {
    if (!job.reply.isCompleted) job.reply.completeError(JobFailed('$error'));
  }

  @override
  void dispose() => disposed = true;
}

/// Timers that fire only when the test says so.
class FakeClock {
  final timers = <FakeTimer>[];

  Timer call(Duration duration, void Function() callback) {
    final timer = FakeTimer(duration, callback);
    timers.add(timer);
    return timer;
  }

  /// The timers not yet fired or cancelled.
  List<FakeTimer> get pending => [for (final t in timers) if (t.isActive) t];
}

class FakeTimer implements Timer {
  FakeTimer(this.duration, this._callback);

  final Duration duration;
  final void Function() _callback;
  var _active = true;

  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

/// Lets every pending future and microtask run.
Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
