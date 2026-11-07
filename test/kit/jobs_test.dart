import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/kit/jobs/jobs_core.dart';

import 'fakes.dart';

/// Doubles a number; throws on a negative one.
class DoubleJob extends GameJob<int, int> {
  const DoubleJob();

  @override
  String get name => 'fake.double';
  @override
  Object? encodeInput(int input) => input;
  @override
  int decodeInput(Object? json) => json! as int;
  @override
  Object? encodeOutput(int output) => {'out': output, 'micros': 12};
  @override
  int decodeOutput(Object? json) => (json! as Map)['out'] as int;

  @override
  int run(int input, JobContext context) {
    if (input < 0) throw ArgumentError('negative');
    return input * 2;
  }
}

final _jobs = <String, GameJob<Object?, Object?>>{'fake.double': const DoubleJob()};

void main() {
  group('the request and the reply', () {
    test('a request carries the job, its input, the cap and the platform', () {
      final request = jsonDecode(encodeRequest(17, const DoubleJob(), 21,
          cap: const Duration(seconds: 1), platform: JobPlatform.webJs)) as Map;
      expect(request, {'id': 17, 'job': 'fake.double', 'in': 21, 'cap': 1000, 'p': 'webJs'});
      final none = jsonDecode(encodeRequest(1, const DoubleJob(), 2, platform: JobPlatform.test)) as Map;
      expect(none.containsKey('cap'), isFalse, reason: 'no cap: none sent');
    });

    test('running a request gives the output, or the error, and never throws', () {
      String run(Object? input, [String job = 'fake.double']) =>
          runJobRequest(jsonEncode({'id': 3, 'job': job, 'in': input, 'p': 'test'}), _jobs);
      expect(jsonDecode(run(21)), {
        'id': 3,
        'out': {'out': 42, 'micros': 12},
      });
      expect((jsonDecode(run(-1)) as Map)['err'], startsWith('Invalid argument(s): negative'));
      expect((jsonDecode(run(1, 'fake.none')) as Map)['err'], 'unknown job fake.none');
      expect((jsonDecode(runJobRequest('not json', _jobs)) as Map)['err'], isNotEmpty);
    });

    test('a job knows what is left of its cap, and has none in tests', () {
      expect(JobContext(platform: JobPlatform.test).remaining, isNull);
      final capped = JobContext(timeCap: const Duration(seconds: 5), platform: JobPlatform.desktop).remaining!;
      expect(capped, lessThanOrEqualTo(const Duration(seconds: 5)));
      expect(capped, greaterThan(Duration.zero));
    });

    test('caps: short on the page itself, none in tests', () {
      int? ms(JobKind kind, {bool background = true, JobPlatform platform = JobPlatform.desktop}) =>
          capFor(kind, platform, background: background)?.inMilliseconds;
      expect(
        [ms(JobKind.coach), ms(JobKind.coachDeep), ms(JobKind.bot), ms(JobKind.guide), ms(JobKind.range)],
        [1000, 3000, 800, 5000, 1000],
      );
      expect(
        [for (final kind in JobKind.values) ms(kind, background: false, platform: JobPlatform.webJs)],
        [300, 300, 300, 5000, 300],
      );
      expect([for (final kind in JobKind.values) ms(kind, platform: JobPlatform.test)], everyElement(isNull));
    });
  });

  group('Jobs', () {
    late ManualBackend backend;
    late FakeClock clock;
    late Jobs jobs;

    setUp(() {
      backend = ManualBackend(_jobs, platform: JobPlatform.desktop);
      clock = FakeClock();
      jobs = Jobs.using(backend, timer: clock.call);
    });

    test('runs one job per lane, first in first out; the two lanes run side by side', () async {
      final a = jobs.start(const DoubleJob(), 1);
      final b = jobs.start(const DoubleJob(), 2);
      final bot = jobs.start(const DoubleJob(), 3, lane: JobLane.bot, kind: JobKind.bot);
      expect(backend.running.map((j) => j.lane), [JobLane.coach, JobLane.bot]);
      expect([a.isRunning, b.isRunning, bot.isRunning], [true, false, true]);
      expect(backend.on(JobLane.coach)!.cap, 1000);
      expect(backend.on(JobLane.bot)!.cap, 800);

      backend.answer(backend.on(JobLane.coach)!);
      expect(await a.result, 2);
      expect(b.isRunning, isTrue, reason: 'the next one starts when the lane is free');
      backend.answer(backend.on(JobLane.coach)!);
      backend.answer(backend.on(JobLane.bot)!);
      expect([await b.result, await bot.result], [4, 6]);
      expect([a.isDone, b.isDone, bot.isDone], [true, true, true]);
    });

    test('cancelling a queued job takes it out of the queue', () async {
      jobs.start(const DoubleJob(), 1);
      final queued = jobs.start(const DoubleJob(), 2);
      final next = jobs.start(const DoubleJob(), 3);
      queued.cancel();
      await expectLater(queued.result, throwsA(isA<JobCancelled>()));
      backend.answer(backend.on(JobLane.coach)!);
      await settle();
      expect(backend.on(JobLane.coach)!.request, contains('"in":3'), reason: 'the cancelled job never ran');
      backend.answer(backend.on(JobLane.coach)!);
      expect(await next.result, 6);
    });

    test('cancelling a running job stops it at once and frees its lane', () async {
      final running = jobs.start(const DoubleJob(), 1);
      final next = jobs.start(const DoubleJob(), 2);
      final job = backend.on(JobLane.coach)!;
      running.cancel();
      expect(job.token.isCancelled, isTrue, reason: 'the backend kills its thread');
      await expectLater(running.result, throwsA(isA<JobCancelled>()));
      expect(next.isRunning, isTrue);
      backend.answer(backend.on(JobLane.coach)!);
      expect(await next.result, 4);
    });

    test('a reply that arrives after a cancel is dropped', () async {
      final handle = jobs.start(const DoubleJob(), 1);
      final job = backend.on(JobLane.coach)!;
      handle.cancel();
      backend.answer(job);
      await settle();
      await expectLater(handle.result, throwsA(isA<JobCancelled>()));
    });

    test('the safety timer starts when the job starts running, and fails it at cap + 2 s', () async {
      final first = jobs.start(const DoubleJob(), 1);
      final second = jobs.start(const DoubleJob(), 2);
      expect(clock.pending, hasLength(1), reason: 'the queued job has no timer yet');
      expect(clock.pending.single.duration, const Duration(milliseconds: 3000));
      backend.answer(backend.on(JobLane.coach)!);
      await first.result;
      expect(clock.pending, hasLength(1), reason: "the first job's timer is gone; the second's started");
      final job = backend.on(JobLane.coach)!;
      clock.pending.single.fire();
      await expectLater(second.result, throwsA(isA<JobFailed>().having((e) => e.message, 'message', 'timeout')));
      expect(job.token.isCancelled, isTrue);
      backend.answer(job);
      await settle();
    });

    test('there is no timer without a cap', () {
      Jobs.using(ManualBackend(_jobs), timer: clock.call).start(const DoubleJob(), 1);
      expect(clock.timers, isEmpty);
    });

    test('a job that throws fails with its message', () async {
      final handle = jobs.start(const DoubleJob(), -1);
      backend.answer(backend.on(JobLane.coach)!);
      await expectLater(handle.result, throwsA(isA<JobFailed>().having((e) => e.message, 'message', contains('negative'))));
    });

    test('dispose cancels everything and stops the backend; later jobs are cancelled at once', () async {
      final running = jobs.start(const DoubleJob(), 1);
      final queued = jobs.start(const DoubleJob(), 2);
      jobs.dispose();
      expect(backend.disposed, isTrue);
      await expectLater(running.result, throwsA(isA<JobCancelled>()));
      await expectLater(queued.result, throwsA(isA<JobCancelled>()));
      await expectLater(jobs.start(const DoubleJob(), 3).result, throwsA(isA<JobCancelled>()));
    });

    test('inline jobs run on the same thread, with the JSON round trip and no cap', () async {
      final inline = Jobs.inline(extra: _jobs);
      expect([inline.platform, inline.background], [JobPlatform.test, true]);
      expect(await inline.start(const DoubleJob(), 21).result, 42);
      final cancelled = inline.start(const DoubleJob(), 1)..cancel();
      await expectLater(cancelled.result, throwsA(isA<JobCancelled>()));
    });
  });
}
