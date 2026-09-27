// Builds the web version into build/web: the app, plus the solvers' Web
// Worker (lib/solver_worker.dart), which `flutter build web` leaves out.
// Without the worker the site still works, but solves freeze the page.
//
// Run from the project root, adding any `flutter build web` options:
//   dart run tool/build_web.dart [--base-href /PokerFection/]
import 'dart:io';

Future<void> main(List<String> args) async {
  // Makes the page ask for this build's worker script, not a cached one.
  final build = DateTime.now().millisecondsSinceEpoch;
  await _run('flutter', ['build', 'web', '--release', '--wasm', '--dart-define=SOLVER_WORKER_BUILD=$build', ...args]);
  await _run(Platform.resolvedExecutable, [
    'compile',
    'js',
    '-O4',
    '--no-source-maps',
    '-o',
    'build/web/solver_worker.js',
    'lib/solver_worker.dart',
  ]);
  // The compiler's list of source files isn't part of the site.
  File('build/web/solver_worker.js.deps').deleteSync();
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
