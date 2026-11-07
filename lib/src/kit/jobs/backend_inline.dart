import 'jobs.dart';
import 'jobs_core.dart';

/// Runs jobs on the calling thread, with the same JSON round trip as a
/// worker: in tests (no cap), and in browsers that can't start a worker
/// (the page fallback: short caps, the screen pauses while a job runs).
///
/// A cancelled job can't be stopped halfway here; its reply is dropped.
class InlineBackend implements JobBackend {
  InlineBackend({required this.jobs, required this.platform, required this.background, this.paintFirst = false});

  final Map<String, GameJob<Object?, Object?>> jobs;

  @override
  final JobPlatform platform;

  @override
  final bool background;

  /// Waits one frame's turn before running, so a "thinking" state paints
  /// before the page is busy (the page fallback).
  final bool paintFirst;

  @override
  Future<String> run(JobLane lane, String request, CancelToken token) async {
    // Never inside start(): whoever started the job can still cancel it.
    if (paintFirst) {
      await Future<void>.delayed(Duration.zero);
    } else {
      await Future<void>.value();
    }
    if (token.isCancelled) throw const JobCancelled();
    return runJobRequest(request, jobs);
  }

  @override
  void dispose() {}
}
