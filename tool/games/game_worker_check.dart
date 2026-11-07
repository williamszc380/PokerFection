// Checks that every game job gives the same answer in the browser as in
// the apps: each registered job's checkInputs() run natively, in the games'
// Web Worker compiled to JavaScript, and compiled to WebAssembly, both
// under Node (with a few lines standing in for the worker's global scope).
// The outputs, after the job's normalize(), must be equal: there is no list
// of accepted differences. A difference goes back to that game's agent.
//
//   dart run tool/games/game_worker_check.dart [--only=nim,gomoku] [--platform=desktop] [--keep]
//
// Each game is built on its own (its job list behind the worker's own
// serveJobs, the code lib/game_worker.dart runs), so a game whose jobs
// don't compile yet is reported and doesn't stop the others. "nim" is the
// kit's test game (test/kit/nim_jobs.dart), which proves the whole path
// whatever the games have registered. Then lib/game_worker.dart itself is
// compiled both ways, and its ready message must list exactly the jobs
// checked: a registered job that was never compared (one with no
// checkInputs(), or of a game missing from _targets) fails the run.
//
// --platform: what the requests say they run on (it sets each job's work
// budget); every run gets the same requests, with no time cap, so the
// work is the same everywhere. Needs Node 22 or later (WasmGC).
// Takes minutes (the coaches run at full budget): run it alone. Each run
// has its own work folder, so the game agents' runs can overlap.
import 'dart:convert';
import 'dart:io';

/// The checked games: key, the file of its jobs, its list's name.
const _targets = [
  (key: 'nim', import: 'test/kit/nim_jobs.dart', list: 'nimJobs.values'),
  (key: 'gomoku', import: 'lib/src/games/gomoku/app/gomoku_jobs.dart', list: 'gomokuJobs'),
  (key: 'big_two', import: 'lib/src/games/big_two/app/big_two_jobs.dart', list: 'bigTwoJobs'),
  (key: 'doudizhu', import: 'lib/src/games/doudizhu/app/doudizhu_jobs.dart', list: 'doudizhuJobs'),
  (key: 'blackjack', import: 'lib/src/games/blackjack/app/blackjack_jobs.dart', list: 'blackjackJobs'),
];

final String _root = Directory.current.absolute.path.replaceAll(r'\', '/');
final String _packages = '$_root/.dart_tool/package_config.json';
late final Directory _work;

Future<void> main(List<String> args) async {
  String? option(String name) =>
      [for (final a in args) if (a.startsWith('--$name=')) a.substring(name.length + 3)].firstOrNull;
  final only = option('only')?.split(',').toSet();
  final platform = option('platform') ?? 'desktop';
  if (!File(_packages).existsSync()) {
    stderr.writeln('Run from the project root, after flutter pub get.');
    exit(2);
  }
  _work = workFolder();
  File('${_work.path}/run_worker.mjs').writeAsStringSync(_nodeShim);
  stdout.writeln('Work folder: ${_work.path}  (requests say "p":"$platform", no cap)\n');

  var failed = false;
  final checked = <String>{};
  final keys = <String>{};
  for (final target in _targets) {
    if (only != null && !only.contains(target.key)) continue;
    keys.add(target.key);
    final result = await _check(target, platform);
    failed |= !result.ok;
    checked.addAll(result.jobs);
  }

  // The real worker: it builds both ways and says it has every job checked
  // (the games' own; Nim is the tests' and isn't in it).
  stdout.writeln('lib/game_worker.dart');
  final real = '$_root/lib/game_worker.dart';
  for (final mode in ['js', 'wasm']) {
    final out = '${_work.path}/game_worker';
    if (!await _compile(mode, real, out)) {
      stdout.writeln('  $mode: DOES NOT COMPILE');
      failed = true;
      continue;
    }
    final run = await _node(mode, out, '[]', '${_work.path}/game_worker_$mode.json');
    final listed = {for (final name in (run?['ready'] as Map?)?['jobs'] as List? ?? const []) name as String};
    final missing = checked.where((name) => !name.startsWith('nim.') && !listed.contains(name)).toList();
    final unchecked = uncheckedJobs(
      listed: listed,
      checked: checked,
      checkedGames: keys,
      allGames: {for (final t in _targets) t.key},
    );
    final ok = run != null && missing.isEmpty && unchecked.isEmpty;
    failed |= !ok;
    final size = File('$out.$mode').lengthSync();
    stdout.writeln('  $mode: ${ok ? 'ready' : 'FAILED'}, ${listed.length} jobs, $size bytes'
        '${missing.isEmpty ? '' : ', missing ${missing.join(', ')}'}'
        '${unchecked.isEmpty ? '' : ', NOT COMPARED ${unchecked.join(', ')}'}');
  }

  if (!args.contains('--keep')) _work.deleteSync(recursive: true);
  stdout.writeln(failed ? '\nFAILED' : '\nAll the same.');
  exit(failed ? 1 : 0);
}

/// A new work folder for this run (printed): runs never share files.
Directory workFolder() => Directory.systemTemp.createTempSync('pf_game_worker_check_');

/// The jobs the real worker [listed] that this run should have compared and
/// didn't: those of the games checked ([checkedGames], by the `<game>.`
/// prefix of a job's name), and those of a game the check doesn't know
/// ([allGames]: it was never added to _targets). Nim is the tests' game and
/// isn't in the worker.
List<String> uncheckedJobs({
  required Set<String> listed,
  required Set<String> checked,
  required Set<String> checkedGames,
  required Set<String> allGames,
}) => [
  for (final name in listed.toList()..sort())
    if (!checked.contains(name))
      if (checkedGames.contains(_gameOf(name)) || !allGames.contains(_gameOf(name))) name,
];

String _gameOf(String job) => job.split('.').first;

/// Builds and runs one game's jobs three ways and compares the replies.
Future<({bool ok, List<String> jobs})> _check(
  ({String key, String import, String list}) target,
  String platform,
) async {
  final key = target.key;
  stdout.writeln(key);
  final dir = Directory('${_work.path}/$key')..createSync(recursive: true);
  // Files under lib/ by their package URI: by a file URI, the libraries
  // they import would load twice, as two different libraries.
  final jobsImport = target.import.startsWith('lib/')
      ? 'package:pokerfection/${target.import.substring(4)}'
      : 'file:///$_root/${target.import}';
  final native = '${dir.path}/native.dart';
  File(native).writeAsStringSync(_nativeSource(jobsImport, target.list));
  final worker = '${dir.path}/worker.dart';
  File(worker).writeAsStringSync(_workerSource(jobsImport, target.list));

  // Natively: the requests, and the replies to compare with.
  final clock = Stopwatch()..start();
  final run = await Process.run(Platform.resolvedExecutable, ['--packages=$_packages', native, 'run', platform, dir.path]);
  if (run.exitCode != 0) {
    stdout.writeln('  NOT CHECKED: its jobs do not run natively\n${_indent(run.stderr)}${_indent(run.stdout)}');
    return (ok: false, jobs: <String>[]);
  }
  final requests = File('${dir.path}/requests.json').readAsStringSync();
  final names = [for (final r in jsonDecode(requests) as List) (jsonDecode(r as String) as Map)['job'] as String];
  final registered = [
    for (final name in jsonDecode(File('${dir.path}/jobs.json').readAsStringSync()) as List) name as String,
  ];
  if (registered.isEmpty) {
    stdout.writeln('  no jobs registered yet\n');
    return (ok: true, jobs: <String>[]);
  }
  // Every job is compared: one with no inputs fails, it isn't skipped.
  final noInputs = [for (final name in registered) if (!names.contains(name)) name];
  if (noInputs.isNotEmpty) stdout.writeln('  NOT CHECKED (no checkInputs): ${noInputs.join(', ')}');
  if (names.isEmpty) return (ok: false, jobs: <String>[]);
  stdout.writeln('  native: ${names.length} requests in ${clock.elapsed.inMilliseconds} ms');

  var ok = true;
  for (final mode in ['js', 'wasm']) {
    final out = '${dir.path}/worker';
    clock.reset();
    if (!await _compile(mode, worker, out)) {
      stdout.writeln('  $mode: DOES NOT COMPILE');
      ok = false;
      continue;
    }
    final compiled = clock.elapsed.inMilliseconds;
    clock.reset();
    final replies = await _node(mode, out, requests, '${dir.path}/$mode.json');
    if (replies == null) {
      ok = false;
      continue;
    }
    stdout.writeln('  $mode: built in $compiled ms, ${File('$out.$mode').lengthSync()} bytes, '
        'ran in ${clock.elapsed.inMilliseconds} ms');
  }
  if (!ok) return (ok: false, jobs: names.toSet().toList());
  if (noInputs.isNotEmpty) ok = false;

  // The comparison, natively (normalize() is the job's own code).
  final compare = await Process.run(
    Platform.resolvedExecutable,
    ['--packages=$_packages', native, 'compare', platform, dir.path],
  );
  stdout.write(_indent(compare.stdout));
  if (compare.exitCode != 0) stdout.write(_indent(compare.stderr));
  stdout.writeln();
  return (ok: ok && compare.exitCode == 0, jobs: names.toSet().toList());
}

/// Compiles [entry] to `<out>.js`, or `<out>.wasm` and `<out>.mjs`, as
/// tool/build_web.dart builds the workers (-O4).
Future<bool> _compile(String mode, String entry, String out) async {
  final result = await Process.run(Platform.resolvedExecutable, [
    'compile',
    mode,
    '-O4',
    '--no-source-maps',
    '--packages=$_packages',
    '-o',
    '$out.$mode',
    entry,
  ]);
  if (result.exitCode != 0) stdout.write(_indent('${result.stdout}${result.stderr}'));
  return result.exitCode == 0;
}

/// Runs the compiled worker under Node with [requests] (a JSON list of
/// request strings); gives `{ready, replies, ms}`, or null if it failed.
Future<Map<String, Object?>?> _node(String mode, String out, String requests, String outFile) async {
  final input = File('$outFile.requests')..writeAsStringSync(requests);
  final result = await Process.run('node', ['${_work.path}/run_worker.mjs', mode, out, input.path, outFile])
      .timeout(const Duration(minutes: 30));
  if (result.exitCode != 0) {
    stdout.writeln('  $mode: THE WORKER FAILED\n${_indent(result.stderr)}');
    return null;
  }
  return jsonDecode(File(outFile).readAsStringSync()) as Map<String, Object?>;
}

String _indent(Object? text) => [
      for (final line in '$text'.trimRight().split('\n'))
        if (line.trim().isNotEmpty) '    $line\n',
    ].join();

/// Stands in for a dedicated worker's global scope: postMessage and
/// onmessage on the global object, one request at a time.
const _nodeShim = r'''
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
const [mode, base, requestsFile, outFile] = process.argv.slice(2);
const requests = JSON.parse(readFileSync(requestsFile, 'utf8'));
let ready = null;
const replies = [];
globalThis.self = globalThis;
globalThis.postMessage = (message) => {
  if (ready === null) ready = JSON.parse(message); else replies.push(message);
};
if (mode === 'js') {
  await import(pathToFileURL(base + '.js').href);
} else {
  const loader = await import(pathToFileURL(base + '.mjs').href);
  const app = await loader.compile(readFileSync(base + '.wasm'));
  (await app.instantiate({})).invokeMain();
}
for (let i = 0; ready === null && i < 200; i++) await new Promise((r) => setTimeout(r, 25));
if (ready === null) throw new Error('the worker never said it was ready');
const ms = [];
for (const request of requests) {
  const start = performance.now();
  globalThis.onmessage({data: request});
  ms.push(performance.now() - start);
  if (replies.length !== ms.length) throw new Error('no reply to ' + request.slice(0, 200));
}
writeFileSync(outFile, JSON.stringify({ready, replies, ms}));
''';

/// A worker for one game's jobs, through the worker's own serveJobs.
String _workerSource(String jobsImport, String list) => '''
import 'package:pokerfection/game_worker.dart' show serveJobs;
import 'package:pokerfection/src/kit/jobs/jobs_core.dart';
import '$jobsImport';

void main() => serveJobs(jobsByName($list));
''';

/// Natively: `run` writes the requests and the native replies; `compare`
/// compares them with the JavaScript and WebAssembly replies, job by job.
String _nativeSource(String jobsImport, String list) => '''
import 'dart:convert';
import 'dart:io';

import 'package:pokerfection/src/kit/jobs/jobs_core.dart';
import '$jobsImport';

void main(List<String> args) {
  final jobs = jobsByName($list);
  final platform = JobPlatform.values.byName(args[1]);
  final dir = args[2];
  if (args[0] == 'run') {
    var id = 0;
    final requests = [
      for (final job in jobs.values)
        for (final input in job.checkInputs()) encodeRequest(++id, job, input, platform: platform),
    ];
    final ms = <double>[];
    final replies = <String>[];
    for (final request in requests) {
      final clock = Stopwatch()..start();
      replies.add(runJobRequest(request, jobs));
      ms.add(clock.elapsedMicroseconds / 1000);
    }
    File('\$dir/requests.json').writeAsStringSync(jsonEncode(requests));
    File('\$dir/jobs.json').writeAsStringSync(jsonEncode(jobs.keys.toList()));
    File('\$dir/native.json').writeAsStringSync(jsonEncode({'replies': replies, 'ms': ms}));
    return;
  }
  final requests = [for (final r in jsonDecode(File('\$dir/requests.json').readAsStringSync()) as List) r as String];
  Map<String, Object?> read(String name) => jsonDecode(File('\$dir/\$name.json').readAsStringSync()) as Map<String, Object?>;
  final native = read('native'), js = read('js'), wasm = read('wasm');
  var failed = false;
  final rows = <String, List<String>>{};
  final ms = <String, List<double>>{};
  for (final (i, request) in requests.indexed) {
    final name = (jsonDecode(request) as Map)['job'] as String;
    final job = jobs[name]!;
    final row = rows.putIfAbsent(name, () => []);
    ms.putIfAbsent(name, () => [0, 0, 0]);
    final replies = [native, js, wasm];
    for (final (k, reply) in replies.indexed) {
      ms[name]![k] += ((reply['ms'] as List)[i] as num).toDouble();
    }
    final decoded = [for (final reply in replies) jsonDecode((reply['replies'] as List)[i] as String) as Map];
    final errors = [for (final d in decoded) d['err']];
    if (errors.any((e) => e != null)) {
      failed = true;
      row.add('input \$i: an error (native, js, wasm): \${[for (final e in errors) e?.toString().split('\\n').first]}');
      continue;
    }
    final outs = [for (final d in decoded) job.normalize(d['out'])];
    for (final (k, mode) in [(1, 'js'), (2, 'wasm')]) {
      final where = _difference(outs[0], outs[k], r'\$');
      if (where != null) {
        failed = true;
        row.add('input \$i: \$mode differs at \$where');
      }
    }
  }
  for (final MapEntry(key: name, value: problems) in rows.entries) {
    final count = requests.where((r) => (jsonDecode(r) as Map)['job'] == name).length;
    final t = [for (final v in ms[name]!) (v / count).toStringAsFixed(1)];
    print('\${problems.isEmpty ? 'same  ' : 'DIFFER'} \$name: \$count inputs, '
        'average ms native \${t[0]} / js \${t[1]} / wasm \${t[2]}');
    for (final p in problems.take(10)) {
      print('         \$p');
    }
  }
  exit(failed ? 1 : 0);
}

/// Where [a] and [b] differ (a JSON path), or null. Numbers compare by
/// value: JavaScript writes 1.0 as 1.
String? _difference(Object? a, Object? b, String path) {
  if (a is num && b is num) return a == b ? null : '\$path: \$a vs \$b';
  if (a is Map && b is Map) {
    for (final key in {...a.keys, ...b.keys}) {
      if (!a.containsKey(key) || !b.containsKey(key)) return '\$path.\$key: missing on one side';
      final d = _difference(a[key], b[key], '\$path.\$key');
      if (d != null) return d;
    }
    return null;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return '\$path: \${a.length} items vs \${b.length}';
    for (var i = 0; i < a.length; i++) {
      final d = _difference(a[i], b[i], '\$path[\$i]');
      if (d != null) return d;
    }
    return null;
  }
  return a == b ? null : '\$path: \$a vs \$b';
}
''';
