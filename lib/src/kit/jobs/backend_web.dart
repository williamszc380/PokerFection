import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'backend_inline.dart';
import 'backend_workers.dart';
import 'job_registry.dart';
import 'jobs.dart';
import 'jobs_core.dart';

/// Browsers' jobs: in the games' Web Workers (see WorkerBackend), or on
/// the page when no worker can start.
Jobs createPlatformJobs() => Jobs.using(webWorkerBackend());

/// The games' worker scripts, built by tool/build_web.dart next to the app:
/// lib/game_worker.dart compiled to WebAssembly (a module script starts it)
/// and to JavaScript, for browsers that can't run that. Poker's solver has
/// its own (web_workers.dart); nothing is shared with it.
enum _Script {
  wasm('game_worker_wasm.js', 'module'),
  js('game_worker.js', 'classic');

  const _Script(this.file, this.type);

  final String file;
  final String type;

  /// With the build number, so browsers don't use a copy cached from an
  /// older build (the same number the solver's worker gets).
  String get url {
    const build = String.fromEnvironment('SOLVER_WORKER_BUILD');
    return build.isEmpty ? file : '$file?build=$build';
  }
}

/// The scripts this page still tries, fastest first, shared by every game
/// screen (like the solver's): one that fails is dropped for the rest of
/// the page's life. `flutter run` builds no workers, a browser without
/// WasmGC can't run the first, and an older cached page may get a script
/// from another build.
final _scripts = [
  WorkerScript(platform: JobPlatform.webWasm, start: () => _WebWorker.start(_Script.wasm)),
  WorkerScript(platform: JobPlatform.webJs, start: () => _WebWorker.start(_Script.js)),
];

/// What the page itself was compiled to.
const _pagePlatform = bool.fromEnvironment('dart.tool.dart2wasm') ? JobPlatform.webWasm : JobPlatform.webJs;

/// Each lane's jobs in its own Web Worker (a page has no isolates), kept
/// while the game screen lives; with no worker at all, on the page itself
/// with its short caps (see capFor), after one paint so the "thinking"
/// state shows.
WorkerBackend webWorkerBackend({Map<String, GameJob<Object?, Object?>>? jobs}) => WorkerBackend(
      scripts: _scripts,
      page: InlineBackend(jobs: jobs ?? kitJobs, platform: _pagePlatform, background: false, paintFirst: true),
      pagePlatform: _pagePlatform,
    );

/// A game worker in a Web Worker. Its start is copied from SolverWorker's
/// (web_workers.dart), not shared, so poker's worker code stays as it is.
class _WebWorker extends JobWorker {
  _WebWorker._(this._worker, {required super.wasm});

  final web.Worker _worker;

  /// A ready worker from [script], or null when it can't start. Waits at
  /// most [_startLimit] for its ready message.
  static Future<JobWorker?> start(_Script script) async {
    final web.Worker worker;
    try {
      worker = web.Worker(script.url.toJS, web.WorkerOptions(type: script.type));
    } on Object {
      return null;
    }
    final game = _WebWorker._(worker, wasm: script == _Script.wasm);
    final ready = Completer<bool>();
    worker.onmessage = ((web.MessageEvent event) => game._message(event, ready)).toJS;
    worker.onerror = ((web.Event event) {
      final message = event.isA<web.ErrorEvent>() ? (event as web.ErrorEvent).message : 'not started';
      // Fails first: this script can't run here.
      if (!ready.isCompleted) ready.complete(false);
      game.died(message);
    }).toJS;
    final ok = await ready.future.timeout(_startLimit, onTimeout: () => false);
    if (!ok) {
      game.stop();
      return null;
    }
    return game;
  }

  static const _startLimit = Duration(seconds: 20);

  void _message(web.MessageEvent event, Completer<bool> ready) {
    final data = event.data;
    final text = data.isA<JSString>() ? (data as JSString).toDart : null;
    if (!ready.isCompleted) {
      // The first message says it is ready, with its jobs.
      try {
        final message = jsonDecode(text!) as Map<String, Object?>;
        jobs = {for (final name in message['jobs'] as List) name as String};
        ready.complete(message['ready'] == 1);
      } on Object {
        ready.complete(false);
      }
      return;
    }
    replied(text);
  }

  @override
  void post(String request) => _worker.postMessage(request.toJS);

  @override
  void terminate() => _worker.terminate();
}
