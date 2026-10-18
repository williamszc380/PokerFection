// Builds the web version: the app, plus the solvers' Web Worker
// (lib/solver_worker.dart, in WebAssembly and in JavaScript), which
// `flutter build web` leaves out. Without the worker the site still works,
// but solves freeze the page.
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
Future<void> buildSolverWorker(String output) async {
  for (final target in ['wasm', 'js']) {
    await _run(Platform.resolvedExecutable, [
      'compile',
      target,
      '-O4',
      '--no-source-maps',
      '-o',
      '$output/solver_worker.$target',
      'lib/solver_worker.dart',
    ]);
  }
  // The compiler's test for whether a browser can run the WebAssembly goes
  // in the script that starts it; its list of source files isn't part of the site.
  final support = File('$output/solver_worker.support.js');
  File('$output/solver_worker_wasm.js').writeAsStringSync(_wasmStarter(support.readAsStringSync().trim()));
  support.deleteSync();
  File('$output/solver_worker.js.deps').deleteSync();
}

/// The worker script (a module) that runs solver_worker.wasm. Where the
/// browser can't, it fails at once, and the page uses solver_worker.js.
/// The files it loads carry its build number, so they come from one build.
String _wasmStarter(String support) => '''
// Starts the solvers' Web Worker compiled to WebAssembly (tool/build_web.dart).
if (!$support) throw new Error('This browser cannot run solver_worker.wasm');
const build = new URL(import.meta.url).search;
const {compileStreaming} = await import(`./solver_worker.mjs\${build}`);
const app = await compileStreaming(fetch(new URL(`solver_worker.wasm\${build}`, import.meta.url)));
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
