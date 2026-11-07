/// The games' background work as named JSON jobs: what a job is, the
/// request and reply it travels in, and its time caps.
///
/// This file imports nothing from the app or the kit, so the web worker
/// (which reaches only this file and job_registry.dart) stays small and
/// free of Flutter.
library;

import 'dart:convert';

/// Where a job runs; a job picks its work budget by it.
enum JobPlatform { desktop, phone, webWasm, webJs, test }

/// What kind of work a job is (it sets the time cap, see [capFor]).
enum JobKind {
  /// The coach's answer for the panel, also used to grade the move.
  coach,

  /// Think longer, and the review's answers.
  coachDeep,

  /// A bot's move.
  bot,

  /// A guide's data (Blackjack's strategy chart).
  guide,

  /// An opponent's range (what they could hold), asked for by tapping
  /// their seat: on the coach lane, as long as a coach answer.
  range,
}

/// What a running job knows about where and how long it may run.
class JobContext {
  JobContext({this.timeCap, required this.platform}) : _clock = Stopwatch()..start();

  /// Wall-clock cap, or null: no cap (tests). Null means the job passes an
  /// explicit "no limit" to its engine (Gomoku: `maxTime: Duration(days: 1)`),
  /// never the engine's own default, so answers repeat exactly.
  final Duration? timeCap;
  final JobPlatform platform;
  final Stopwatch _clock;

  /// What is left of the cap (never negative), or null without a cap.
  Duration? get remaining {
    final cap = timeCap;
    if (cap == null) return null;
    final left = cap - _clock.elapsed;
    return left.isNegative ? Duration.zero : left;
  }
}

/// One kind of background work for one game. JSON in, JSON out, on every
/// platform: in a fresh isolate on the apps, in a Web Worker in browsers,
/// on the same thread in tests.
///
/// Rules (they hold everywhere):
/// - [run] is synchronous and uses no Flutter, dart:io, isolates, timers or
///   `Random()`; seeds come in the input.
/// - It respects `context.remaining`, and passes an explicit "no limit" to
///   the engine when there is no cap.
/// - It does not rely on static caches lasting from one job to the next
///   (every job may start in a fresh isolate or worker): expensive data that
///   can be reused is made by its own job and passed in as input.
/// - [encodeOutput] leaves out timing fields (`micros`, `elapsedMicros`,
///   `elapsed`), so the same input gives the same output.
abstract class GameJob<I, O> {
  const GameJob();

  /// `<key>.<what>`, e.g. `gomoku.coach` (the key from GameKeys).
  String get name;

  Object? encodeInput(I input);
  I decodeInput(Object? json);
  Object? encodeOutput(O output);
  O decodeOutput(Object? json);

  O run(I input, JobContext context);

  /// Small inputs (each under 50 ms cold) for the registry's round-trip test.
  List<I> examples() => const [];

  /// More inputs for the cross-platform check (game_worker_check); about 30.
  List<I> checkInputs() => examples();

  /// Strips anything volatile left in an encoded output (default: nothing).
  Object? normalize(Object? outputJson) => outputJson;
}

/// A job was cancelled before it finished (a new game, Think longer, the
/// screen closed).
class JobCancelled implements Exception {
  const JobCancelled();

  @override
  String toString() => 'JobCancelled';
}

/// A job failed: it threw, its reply could not be read, or it ran past its
/// cap ('timeout').
class JobFailed implements Exception {
  JobFailed(this.message);

  final String message;

  @override
  String toString() => 'JobFailed: $message';
}

/// The request for one job, a plain JSON string, the same everywhere:
/// `{"id":17,"job":"gomoku.coach","in":<json>,"cap":1000,"p":"webJs"}`
/// ("cap" in milliseconds, absent: no cap).
String encodeRequest(int id, GameJob job, Object? input, {Duration? cap, required JobPlatform platform}) =>
    jsonEncode({
      'id': id,
      'job': job.name,
      'in': job.encodeInput(input),
      'cap': ?cap?.inMilliseconds,
      'p': platform.name,
    });

/// [jobs] by name. Throws if two have the same name: in a plain map the
/// second would silently replace the first, and one game's job would vanish.
Map<String, GameJob<Object?, Object?>> jobsByName(Iterable<GameJob<Object?, Object?>> jobs) {
  final byName = <String, GameJob<Object?, Object?>>{};
  for (final job in jobs) {
    if (byName.containsKey(job.name)) throw StateError('Two jobs are named ${job.name}');
    byName[job.name] = job;
  }
  return byName;
}

/// Runs one request against [jobs] and gives the reply: `{"id":17,"out":<json>}`,
/// or `{"id":17,"err":"message\nstack"}`. Never throws, so a worker's loop
/// can't die on a bad job.
String runJobRequest(String request, Map<String, GameJob<Object?, Object?>> jobs) {
  Object? id;
  try {
    final message = jsonDecode(request) as Map<String, Object?>;
    id = message['id'];
    final name = message['job'] as String;
    final job = jobs[name];
    if (job == null) return jsonEncode({'id': id, 'err': 'unknown job $name'});
    final cap = message['cap'] as int?;
    final platform = JobPlatform.values.byName(message['p'] as String);
    final context = JobContext(timeCap: cap == null ? null : Duration(milliseconds: cap), platform: platform);
    final output = job.run(job.decodeInput(message['in']), context);
    return jsonEncode({'id': id, 'out': job.encodeOutput(output)});
  } on Object catch (error, stack) {
    return jsonEncode({'id': id, 'err': '$error\n$stack'});
  }
}

/// A job's time cap: the table below, in milliseconds; null (no cap) in tests.
///
/// | kind      | on another thread | on the page (no worker) |
/// |-----------|-------------------|-------------------------|
/// | coach     | 1000              | 300                     |
/// | coachDeep | 3000              | 300 (Think longer is greyed out there) |
/// | bot       | 800               | 300                     |
/// | guide     | 5000              | 5000, with a spinner    |
/// | range     | 1000              | 300                     |
///
/// [background] is false when jobs run on the page itself, which freezes
/// the screen while they run, hence the short caps.
Duration? capFor(JobKind kind, JobPlatform platform, {required bool background}) {
  if (platform == JobPlatform.test) return null;
  final ms = switch (kind) {
    JobKind.coach => background ? 1000 : 300,
    JobKind.coachDeep => background ? 3000 : 300,
    JobKind.bot => background ? 800 : 300,
    JobKind.guide => 5000,
    JobKind.range => background ? 1000 : 300,
  };
  return Duration(milliseconds: ms);
}
