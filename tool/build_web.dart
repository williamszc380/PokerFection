// Builds the web version: the app, plus its two Web Workers, which
// `flutter build web` leaves out, each in WebAssembly and in JavaScript:
// the poker solvers' (lib/solver_worker.dart) and the other games' coaches
// and bots (lib/game_worker.dart). Without them the site still works, but
// solves and coaches freeze the page.
//
// Run from the project root, adding any `flutter build web` options:
//   dart run tool/build_web.dart [--base-href /PokerFection/]
//     the website, in build/web
//   dart run tool/build_web.dart --host
//     the copy a host's app serves to friends who play in a browser, in
//     build/web_host: with the engine's files (nothing from the internet)
//     and served at the root. The Windows build ships it as data/web next to
//     the app; this also copies it into the Windows builds there are now.
import 'dart:io';

import 'build_label.dart';

Future<void> main(List<String> args) async {
  final host = args.contains('--host');
  final output = host ? 'build/web_host' : 'build/web';
  final options = [for (final a in args) if (a != '--host') a];
  // Makes the page ask for this build's worker script, not a cached one.
  final build = DateTime.now().millisecondsSinceEpoch;
  await _run('flutter', [
    'build',
    'web',
    '--release',
    '--wasm',
    '--dart-define=SOLVER_WORKER_BUILD=$build',
    // The main menu's corner shows which code this is.
    ...buildLabelOptions(await buildLabel()),
    if (host) ...['--no-web-resources-cdn', '--output', Directory(output).absolute.path],
    ...options,
  ]);
  await buildSolverWorker(output);
  await buildGameWorker(output);
  if (host) {
    for (final mode in ['Debug', 'Profile', 'Release']) {
      final data = Directory('build/windows/x64/runner/$mode/data');
      if (!data.existsSync()) continue;
      final web = Directory('${data.path}/web');
      if (web.existsSync()) web.deleteSync(recursive: true);
      _copy(Directory(output), web);
      stdout.writeln('Copied into ${web.path}');
    }
  }
}

/// Compiles lib/solver_worker.dart into [output] twice: to WebAssembly
/// (solver_worker.wasm and .mjs, started by solver_worker_wasm.js), which
/// solves faster, and to JavaScript (solver_worker.js) for browsers that
/// can't run that. The page tries them in that order (web_workers.dart).
Future<void> buildSolverWorker(String output) => _buildWorker(output, 'solver_worker', "the solvers'");

/// Compiles lib/game_worker.dart the same way: game_worker.wasm and .mjs
/// (started by game_worker_wasm.js), and game_worker.js. The page tries
/// them in that order (lib/src/kit/jobs/backend_web.dart).
Future<void> buildGameWorker(String output) => _buildWorker(output, 'game_worker', "the games'");

/// Compiles lib/[name].dart ([whose] Web Worker) into [output], to
/// WebAssembly and to JavaScript.
Future<void> _buildWorker(String output, String name, String whose) async {
  for (final target in ['wasm', 'js']) {
    await _run(Platform.resolvedExecutable, [
      'compile',
      target,
      '-O4',
      '--no-source-maps',
      '-o',
      '$output/$name.$target',
      'lib/$name.dart',
    ]);
  }
  // The compiler's test for whether a browser can run the WebAssembly goes
  // in the script that starts it; its list of source files isn't part of the site.
  final support = File('$output/$name.support.js');
  File('$output/${name}_wasm.js').writeAsStringSync(_wasmStarter(support.readAsStringSync().trim(), name, whose));
  support.deleteSync();
  File('$output/$name.js.deps').deleteSync();
}

/// The worker script (a module) that runs [name].wasm. Where the browser
/// can't, it fails at once, and the page uses [name].js. The files it
/// loads carry its build number, so they come from one build.
String _wasmStarter(String support, String name, String whose) =>
    '''
// Starts $whose Web Worker compiled to WebAssembly (tool/build_web.dart).
if (!$support) throw new Error('This browser cannot run $name.wasm');
const build = new URL(import.meta.url).search;
const {compileStreaming} = await import(`./$name.mjs\${build}`);
const app = await compileStreaming(fetch(new URL(`$name.wasm\${build}`, import.meta.url)));
(await app.instantiate({})).invokeMain();
''';

void _copy(Directory from, Directory to) {
  to.createSync(recursive: true);
  for (final entity in from.listSync()) {
    final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (entity is Directory) {
      _copy(entity, Directory('${to.path}/$name'));
    } else if (entity is File) {
      entity.copySync('${to.path}/$name');
    }
  }
}

Future<void> _run(String executable, List<String> arguments) async {
  final process = await Process.start(
    executable,
    arguments,
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
  );
  final code = await process.exitCode;
  if (code != 0) exit(code);
}
