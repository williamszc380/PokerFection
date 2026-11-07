import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/kit/jobs/backend_inline.dart';
import 'package:pokerfection/src/kit/jobs/backend_workers.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/kit/jobs/jobs_core.dart';

import 'fakes.dart' show FakeClock, settle;
import 'nim_jobs.dart';

/// A worker the test answers by hand: it keeps what it was sent.
class _FakeWorker extends JobWorker {
  _FakeWorker({required super.wasm, required Set<String> jobs}) {
    this.jobs = jobs;
  }

  final posted = <String>[];
  var terminated = false;

  @override
  void post(String request) => posted.add(request);

  @override
  void terminate() => terminated = true;

  /// Answers the request it was sent last, as the real worker would.
  void answer() => replied(runJobRequest(posted.last, nimJobs));
}

/// A script whose starts the test may hold back, finish, or fail.
class _FakeScript {
  _FakeScript({this.wasm = true, this.missing = false, this.manual = false});

  final bool wasm;
  final bool missing;

  /// Starts wait for [finishStart].
  final bool manual;

  final workers = <_FakeWorker>[];
  final _waiting = <Completer<JobWorker?>>[];

  late final script = WorkerScript(platform: wasm ? JobPlatform.webWasm : JobPlatform.webJs, start: _start);

  Future<JobWorker?> _start() {
    if (missing) return Future.value(null);
    final worker = _FakeWorker(wasm: wasm, jobs: nimJobs.keys.toSet());
    workers.add(worker);
    if (!manual) return Future.value(worker);
    final waiting = Completer<JobWorker?>();
    _waiting.add(waiting);
    return waiting.future;
  }

  /// Finishes start number [i] (from 0).
  void finishStart(int i) => _waiting[i].complete(workers[i]);
}

/// A take from Nim's pile of 7, as the coach is asked for it.
final _input = {
  'record': {'rules': {'pile': 7, 'take': 3}, 'moves': <String>[]},
  'seat': 0,
};

void main() {
  late FakeClock clock;
  late WorkerBackend backend;
  late Jobs jobs;

  void using(List<_FakeScript> scripts) {
    clock = FakeClock();
    backend = WorkerBackend(
      scripts: [for (final s in scripts) s.script],
      page: InlineBackend(jobs: nimJobs, platform: JobPlatform.webJs, background: false),
      pagePlatform: JobPlatform.webJs,
    );
    jobs = Jobs.using(backend, timer: clock.call);
  }

  JobHandle<Object?> coach() => jobs.start(const NimCoachJob(), _input, kind: JobKind.coachDeep);

  test('a worker is started on first use and kept for the next job', () async {
    final wasm = _FakeScript();
    using([wasm]);
    final first = coach();
    await settle();
    wasm.workers.single.answer();
    await first.result;
    final second = coach();
    await settle();
    expect(wasm.workers, hasLength(1));
    expect(wasm.workers.single.posted, hasLength(2));
    wasm.workers.single.answer();
    expect(await second.result, isNotNull);
    expect(backend.platform, JobPlatform.webWasm);
  });

  test(
      'a job cancelled and the next one started in the same step (the review slider, Think longer): '
      'the next runs on a new worker and gets its answer', () async {
    final wasm = _FakeScript();
    using([wasm]);
    final long = coach();
    await settle();
    final old = wasm.workers.single;
    long.cancel();
    final next = coach();
    await settle();
    expect(old.terminated, isTrue, reason: 'the cancelled job stopped its worker');
    expect(old.posted, hasLength(1), reason: 'the next job never went to the worker being stopped');
    expect(wasm.workers, hasLength(2));
    final fresh = wasm.workers.last;
    expect(fresh.posted, hasLength(1));
    fresh.answer();
    expect(await next.result.timeout(const Duration(seconds: 1)), isNotNull);
    expect(clock.pending, isEmpty, reason: 'not failed by its safety timer');
  });

  test('a job that timed out: its worker is never given the next job', () async {
    final wasm = _FakeScript();
    using([wasm]);
    final slow = coach();
    await settle();
    clock.pending.single.fire();
    await expectLater(slow.result, throwsA(isA<JobFailed>()));
    final next = coach();
    await settle();
    expect(wasm.workers.first.terminated, isTrue);
    expect(wasm.workers.first.posted, hasLength(1));
    wasm.workers.last.answer();
    expect(await next.result, isNotNull);
  });

  test(
      'a job cancelled while its worker starts: that worker is stopped and never takes the lane '
      "from the next job's", () async {
    final wasm = _FakeScript(manual: true);
    using([wasm]);
    final first = coach();
    await settle();
    first.cancel();
    final second = coach();
    await settle();
    expect(wasm.workers, hasLength(2), reason: 'each job started a worker');
    // The second job's worker is ready first, then the cancelled job's.
    wasm.finishStart(1);
    await settle();
    wasm.finishStart(0);
    await settle();
    final (lost, kept) = (wasm.workers[0], wasm.workers[1]);
    expect(lost.terminated, isTrue);
    expect(lost.posted, isEmpty);
    expect(backend.workerOn(JobLane.coach), same(kept));
    kept.answer();
    expect(await second.result, isNotNull);
    jobs.dispose();
    expect(kept.terminated, isTrue, reason: 'leaving the screen stops every worker');
  });

  test('a missing script is dropped and the next one is used; with none left, the page runs jobs with short caps',
      () async {
    final wasm = _FakeScript(missing: true), js = _FakeScript(wasm: false);
    using([wasm, js]);
    final first = coach();
    await settle();
    expect(backend.platform, JobPlatform.webJs);
    js.workers.single.answer();
    expect(await first.result, isNotNull);

    final none = _FakeScript(missing: true);
    using([none]);
    expect(backend.background, isTrue, reason: 'not known before the first try');
    final onPage = coach();
    await settle();
    expect(await onPage.result, isNotNull);
    expect(backend.background, isFalse);
    expect(WorkerBackend.pageCaps(encodeRequest(1, const NimCoachJob(), _input, cap: const Duration(seconds: 3), platform: JobPlatform.webJs)),
        contains('"cap":300'));
  });

  test('a WebAssembly worker that dies mid-job: the job is tried again in JavaScript, which the page keeps',
      () async {
    final wasm = _FakeScript(), js = _FakeScript(wasm: false);
    using([wasm, js]);
    final job = coach();
    await settle();
    wasm.workers.single.died('unreachable');
    await settle();
    expect(js.workers.single.posted, hasLength(1));
    expect(jsonDecode(js.workers.single.posted.single), containsPair('job', 'nim.coach'));
    js.workers.single.answer();
    expect(await job.result, isNotNull);
    expect(backend.platform, JobPlatform.webJs);
  });

  test('a JavaScript worker that dies mid-job fails the job; the next job gets a new worker', () async {
    final js = _FakeScript(wasm: false);
    using([js]);
    final job = coach();
    await settle();
    js.workers.single.died('out of memory');
    await expectLater(job.result, throwsA(isA<JobFailed>()));
    final next = coach();
    await settle();
    expect(js.workers, hasLength(2));
    js.workers.last.answer();
    expect(await next.result, isNotNull);
  });
}
