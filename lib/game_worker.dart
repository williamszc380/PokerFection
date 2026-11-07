/// The games' Web Worker, for the web version (browsers have no isolates):
/// it runs the coach, bot and guide jobs of every game (kitJobs), one at a
/// time, as JSON strings in and out (see jobs_core.dart).
///
/// Compiled on its own by tool/build_web.dart, next to the poker solver's
/// worker: to WebAssembly (build/web/game_worker.wasm and .mjs, started by
/// game_worker_wasm.js) and to JavaScript (game_worker.js) for browsers that
/// can't run that. The page keeps one worker per lane and terminates it to
/// cancel a job (see lib/src/kit/jobs/backend_web.dart).
library;

import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'src/kit/jobs/job_registry.dart';
import 'src/kit/jobs/jobs_core.dart';

void main() => serveJobs(kitJobs);

/// Answers every request this worker gets from [jobs], then says it is
/// ready with the names of the jobs it has: a page that wants a job this
/// list lacks is talking to a script from another build.
///
/// Public so tool/games/game_worker_check.dart can build a worker with the
/// kit's test-only jobs added, through this very code.
void serveJobs(Map<String, GameJob<Object?, Object?>> jobs) {
  final scope = globalContext as web.DedicatedWorkerGlobalScope;
  scope.onmessage = ((web.MessageEvent event) {
    // runJobRequest never throws: a broken job is an "err" reply, not a dead worker.
    scope.postMessage(runJobRequest((event.data as JSString).toDart, jobs).toJS);
  }).toJS;
  scope.postMessage(jsonEncode({'ready': 1, 'jobs': jobs.keys.toList()}).toJS);
}
