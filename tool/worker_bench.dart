// Times the web version's solver worker compiled to JavaScript and to
// WebAssembly (see tool/build_web.dart) on the same preflop and postflop
// solves, in a headless Edge or Chrome on this computer. Each solve runs the
// way the app asks for it: one worker, which starts more for the threads.
//
// Run from the project root:
//   dart run tool/worker_bench.dart [--runs 3] [--browser <path to msedge or chrome>]
// It compiles both workers from the current code into a temporary folder,
// serves them on 127.0.0.1 only, and stops the browser and the server after.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pokerfection/src/engine/cards.dart';
import 'package:pokerfection/src/gto/combos.dart';
import 'package:pokerfection/src/gto/postflop/postflop_tree.dart';
import 'package:pokerfection/src/gto/preflop/preflop_equity.dart';
import 'package:pokerfection/src/gto/preflop/preflop_solver.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tree.dart';
import 'package:pokerfection/src/server/web_files.dart';

import 'build_web.dart' show buildSolverWorker;

Future<void> main(List<String> args) async {
  String? option(String name) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final runs = int.parse(option('--runs') ?? '3');
  final browser = option('--browser') ?? _findBrowser();
  if (browser == null) {
    stderr.writeln('No Edge or Chrome found: pass --browser <path>');
    exit(1);
  }
  final folder = Directory.systemTemp.createTempSync('worker_bench');
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  Process? process;
  try {
    await buildSolverWorker(folder.path);
    final cases = jsonEncode({'runs': runs, 'cases': _cases()});
    final files = WebFiles(folder);
    final done = Completer<List<Object?>>();
    server.listen((request) async {
      switch (request.uri.path) {
        case '/':
          request.response.headers.contentType = ContentType.html;
          request.response.write(_page);
        case '/cases.json':
          request.response.headers.contentType = ContentType.json;
          request.response.write(cases);
        case '/log':
          stdout.writeln(await utf8.decoder.bind(request).join());
        case '/done':
          final results = jsonDecode(await utf8.decoder.bind(request).join()) as List<Object?>;
          if (!done.isCompleted) done.complete(results);
        default:
          if (await files.serve(request)) return;
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    stdout.writeln('Browser: $browser');
    process = await Process.start(browser, [
      '--headless=new',
      '--no-first-run',
      '--no-default-browser-check',
      '--disable-extensions',
      '--user-data-dir=${folder.path}${Platform.pathSeparator}profile',
      'http://127.0.0.1:${server.port}/',
    ]);
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    _report(await done.future.timeout(const Duration(minutes: 30)));
  } finally {
    if (process != null) await _stopBrowser(process, folder.path);
    await server.close(force: true);
    // The browser may hold its profile for a moment after it stops.
    for (var attempt = 0; folder.existsSync(); attempt++) {
      try {
        folder.deleteSync(recursive: true);
      } on FileSystemException {
        if (attempt == 10) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
  }
}

/// Stops every process of the browser: on Windows, each one that uses this
/// run's own profile [folder] (Edge starts itself again, so the process
/// started here may be gone already, and the browser runs several).
Future<void> _stopBrowser(Process process, String folder) async {
  if (Platform.isWindows) {
    await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      r'Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like '
          "'*$folder*' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force -ErrorAction SilentlyContinue }",
    ]);
  } else {
    process.kill();
  }
  await process.exitCode.timeout(const Duration(seconds: 10), onTimeout: () => -1);
}

String? _findBrowser() {
  for (final path in [
    r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
    r'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
    r'C:\Program Files\Google\Chrome\Application\chrome.exe',
    '/usr/bin/google-chrome',
    '/usr/bin/chromium',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  ]) {
    if (File(path).existsSync()) return path;
  }
  return null;
}

/// The solves the app asks for most: whole preflop games (200 iterations)
/// and the streets after the button opens and the big blind calls, with the
/// user in the big blind (120 iterations, 300 on the river).
List<Map<String, Object?>> _cases() {
  final equity = PreflopEquity.fromBytes(ByteData.sublistView(File('assets/preflop_equity.bin').readAsBytesSync()));
  Map<String, Object?> preflop(int players, List<int> threads) => {
        'name': 'Preflop, $players players',
        'threads': threads,
        'request': {
          'kind': 'preflop',
          'spec': jsonEncode(PreflopSpec(stacks: List.filled(players, 10000)).toJson()),
          'iterations': 200,
          'equity': equity.values,
          'ranges': <Object>[],
        },
      };

  // As tool/postflop_bench.dart: UTG, HJ and CO fold, the button raises,
  // the small blind folds, the big blind calls.
  final tree = PreflopTree(PreflopSpec(stacks: List.filled(6, 10000)));
  final solution = PreflopSolver(tree, equity).solve(iterations: 200);
  var node = tree.root as PreflopDecision;
  final path = <(PreflopDecision, int)>[];
  for (final move in [PreflopMove.fold, PreflopMove.fold, PreflopMove.fold, PreflopMove.raise, PreflopMove.fold]) {
    final i = node.actions.indexWhere((a) => a.move == move);
    path.add((node, i));
    node = node.children[i] as PreflopDecision;
  }
  path.add((node, node.actions.indexWhere((a) => a.move == PreflopMove.call)));
  List<double> range(int player) {
    final classes = List.filled(169, 1.0);
    for (final (n, a) in path) {
      if (n.player != player) continue;
      for (var h = 0; h < 169; h++) {
        classes[h] *= solution.frequency(n, a, h);
      }
    }
    return [for (var c = 0; c < comboCount; c++) classes[comboClass[c]]];
  }

  Map<String, Object?> postflop(String street, String board, int iterations) => {
        'name': '$street, BB vs button',
        'threads': [1, 0],
        'request': {
          'kind': 'postflop',
          'spec': jsonEncode(PostflopSpec(
            board: [for (final c in parseCards(board)) c.index],
            pot: 550,
            stacks: [9750, 9750],
            bigBlind: 100,
            hero: 0,
          ).toJson()),
          'iterations': iterations,
          'ranges': [range(5), range(3)],
        },
      };

  // Threads: 0 is what the app uses (every core but one, at most 12).
  return [
    preflop(2, [0]),
    preflop(6, [1, 0]),
    preflop(8, [0]),
    postflop('Flop', 'Kh 9d 4c', 120),
    postflop('Turn', 'Kh 9d 4c 2s', 120),
    postflop('River', 'Kh 9d 4c 2s 7h', 300),
  ];
}

void _report(List<Object?> results) {
  stdout.writeln('\nMedian (fastest) of each, in ms, from starting the worker to the answer:');
  stdout.writeln('${'Solve'.padRight(26)}${'Threads'.padLeft(8)}${'JavaScript'.padLeft(18)}'
      '${'WebAssembly'.padLeft(18)}${'Speed-up'.padLeft(10)}  Same answer');
  String time(List<num> ms) {
    final sorted = [...ms]..sort();
    return '${sorted[sorted.length ~/ 2].round()} (${sorted.first.round()})';
  }

  double median(List<num> ms) => ([...ms]..sort())[ms.length ~/ 2].toDouble();
  for (final r in results.cast<Map<String, Object?>>()) {
    final js = (r['js'] as List).cast<num>(), wasm = (r['wasm'] as List).cast<num>();
    final difference = r['difference'] as num;
    stdout.writeln('${(r['name'] as String).padRight(26)}${'${r['threads']}'.padLeft(8)}'
        '${time(js).padLeft(18)}${time(wasm).padLeft(18)}'
        '${'${(median(js) / median(wasm)).toStringAsFixed(2)}x'.padLeft(10)}'
        '  ${switch (difference) { 0 => 'yes', < 0 => 'no: other sizes', _ => 'largest difference $difference' }}');
  }
}

/// Runs every case with both workers, taking turns at going first.
const _page = r'''<!doctype html>
<meta charset="utf-8">
<title>Worker bench</title>
<script type="module">
const log = (text) => fetch('log', {method: 'POST', body: text});
const {runs, cases} = await (await fetch('cases.json')).json();
const scripts = {js: ['solver_worker.js', 'classic'], wasm: ['solver_worker_wasm.js', 'module']};
const appThreads = Math.min(Math.max(navigator.hardwareConcurrency - 1, 1), 12);
await log(`${navigator.userAgent}\n${navigator.hardwareConcurrency} cores: the app uses ${appThreads} threads`);

function solve(kind, request) {
  return new Promise((resolve, reject) => {
    const start = performance.now();
    const [url, type] = scripts[kind];
    const worker = new Worker(url, {type});
    worker.onerror = (e) => reject(new Error(`${kind} worker: ${e.message ?? 'did not start'}`));
    worker.onmessage = ({data}) => {
      if (data.kind === 'ready') {
        worker.postMessage(request);
      } else if (data.kind === 'solved') {
        worker.terminate();
        resolve({ms: performance.now() - start, strategy: data.strategy});
      } else if (data.kind === 'failed') {
        worker.terminate();
        reject(new Error(data.error));
      }
    };
  });
}

const results = [];
try {
  for (const c of cases) {
    const r = c.request;
    for (const t of c.threads) {
      const threads = t || appThreads;
      const request = {...r, threads, equity: new Float64Array(r.equity ?? []), ranges: r.ranges.map((x) => new Float64Array(x))};
      const times = {js: [], wasm: []}, answers = {};
      for (let run = 0; run < runs; run++) {
        for (const kind of run % 2 ? ['wasm', 'js'] : ['js', 'wasm']) {
          const {ms, strategy} = await solve(kind, request);
          times[kind].push(ms);
          answers[kind] ??= strategy;
          await log(`${c.name}, ${threads} thread${threads > 1 ? 's' : ''}, ${kind}: ${Math.round(ms)} ms`);
        }
      }
      let difference = 0;
      for (let i = 0; i < answers.js.length; i++) difference = Math.max(difference, Math.abs(answers.js[i] - answers.wasm[i]));
      if (answers.js.length !== answers.wasm.length) difference = -1;
      results.push({name: c.name, threads, ...times, difference});
    }
  }
} catch (e) {
  await log(`Failed: ${e.stack ?? e}`);
}
await fetch('done', {method: 'POST', body: JSON.stringify(results)});
</script>
''';
