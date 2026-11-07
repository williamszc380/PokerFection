import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'job_registry.dart';
import 'jobs.dart';
import 'jobs_core.dart';

/// The apps' jobs: one short-lived isolate per job (see [IsolateBackend]).
Jobs createPlatformJobs() => Jobs.using(IsolateBackend(jobs: kitJobs));

/// Runs each job in a fresh isolate, killed when the job is cancelled.
///
/// Why a fresh isolate per job: spawning one costs about 0.06 ms, killing
/// it frees the CPU at once (a search can't be interrupted any other way),
/// and nothing leaks from one game to the next. The price is that static
/// caches start empty every time, which is why jobs must not rely on them.
/// Jobs runs one job per lane, so at most two isolates work at once and
/// the screen keeps a core even on a 4-core phone.
class IsolateBackend implements JobBackend {
  IsolateBackend({required this.jobs, JobPlatform? platform})
      : platform = platform ?? (Platform.isAndroid || Platform.isIOS ? JobPlatform.phone : JobPlatform.desktop);

  /// The jobs an isolate may run; isolates of one group share code, so the
  /// map (and a test's fake jobs) goes to each one as it is.
  final Map<String, GameJob<Object?, Object?>> jobs;

  @override
  final JobPlatform platform;

  @override
  bool get background => true;

  /// Isolates started and not yet gone (for tests: a cancelled job's
  /// isolate goes).
  int get live => _live;
  var _live = 0;

  final _isolates = <Isolate>{};

  @override
  Future<String> run(JobLane lane, String request, CancelToken token) async {
    final reply = Completer<String>();
    final port = RawReceivePort();
    port.handler = (Object? message) {
      port.close();
      if (reply.isCompleted) return;
      if (message is String) {
        reply.complete(message);
      } else if (message is List) {
        // From onError: [error, stack].
        reply.completeError(JobFailed('${message.firstOrNull}'));
      } else {
        reply.completeError(JobFailed('the job stopped'));
      }
    };
    final exit = RawReceivePort();
    _live++;
    late final Isolate isolate;
    exit.handler = (Object? _) {
      exit.close();
      _live--;
      _isolates.remove(isolate);
      // Gone without a word (killed elsewhere): don't leave the job hanging.
      if (!reply.isCompleted) {
        port.close();
        reply.completeError(token.isCancelled ? const JobCancelled() : JobFailed('the job stopped'));
      }
    };
    try {
      isolate = await Isolate.spawn(
        _jobMain,
        (port.sendPort, request, jobs),
        onError: port.sendPort,
        onExit: exit.sendPort,
        debugName: 'job',
      );
    } on Object catch (error) {
      port.close();
      exit.close();
      _live--;
      throw JobFailed('no isolate: $error');
    }
    _isolates.add(isolate);
    unawaited(token.whenCancelled.then((_) {
      // The port first, so a reply already on its way is dropped.
      port.close();
      isolate.kill(priority: Isolate.immediate);
      if (!reply.isCompleted) reply.completeError(const JobCancelled());
    }));
    return reply.future;
  }

  @override
  void dispose() {
    for (final isolate in [..._isolates]) {
      isolate.kill(priority: Isolate.immediate);
    }
  }
}

void _jobMain((SendPort, String, Map<String, GameJob<Object?, Object?>>) message) {
  final (reply, request, jobs) = message;
  reply.send(runJobRequest(request, jobs));
}
