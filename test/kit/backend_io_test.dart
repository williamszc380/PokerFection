@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/kit/jobs/backend_io.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/kit/jobs/jobs_core.dart';

/// Loops for [input] ms (forever when negative): a search that never looks
/// at the clock.
class SpinJob extends GameJob<int, int> {
  const SpinJob();

  @override
  String get name => 'fake.spin';
  @override
  Object? encodeInput(int input) => input;
  @override
  int decodeInput(Object? json) => json! as int;
  @override
  Object? encodeOutput(int output) => output;
  @override
  int decodeOutput(Object? json) => json! as int;

  @override
  int run(int input, JobContext context) {
    final clock = Stopwatch()..start();
    var turns = 0;
    while (input < 0 || clock.elapsedMilliseconds < input) {
      turns++;
    }
    return turns > 0 ? input : 0;
  }
}

void main() {
  final jobs = <String, GameJob<Object?, Object?>>{'fake.spin': const SpinJob()};

  test('a job runs in its own isolate and gives its output; the isolate then goes', () async {
    final backend = IsolateBackend(jobs: jobs);
    final handle = Jobs.using(backend).start(const SpinJob(), 5);
    expect(await handle.result, 5);
    for (var i = 0; i < 100 && backend.live > 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(backend.live, 0);
  });

  test('cancelling a job that never ends kills its isolate, and the lane runs the next job', () async {
    final backend = IsolateBackend(jobs: jobs);
    final runner = Jobs.using(backend);
    final forever = runner.start(const SpinJob(), -1, cap: const Duration(days: 1));
    final next = runner.start(const SpinJob(), 1);
    for (var i = 0; i < 100 && backend.live == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(backend.live, 1, reason: 'one isolate per running job');
    forever.cancel();
    await expectLater(forever.result, throwsA(isA<JobCancelled>()));
    expect(await next.result, 1);
    for (var i = 0; i < 200 && backend.live > 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(backend.live, 0, reason: 'the looping isolate was killed');
    runner.dispose();
  });

  test('the apps run jobs as desktop on Windows, macOS and Linux', () {
    expect(IsolateBackend(jobs: jobs).platform, JobPlatform.desktop);
    expect(IsolateBackend(jobs: jobs).background, isTrue);
  });
}
