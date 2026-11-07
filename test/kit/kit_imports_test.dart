/// The games' engines and the kit's pure parts run in Web Workers, isolates
/// and (later) on the online host, so they must not reach Flutter or the
/// platform's libraries; and the app must not carry the worker's entrypoint.
/// (The helper is a copy of test/online/import_guard_test.dart's.)
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _directive = RegExp(
  r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]((?:\s+if\s*\([^)]*\)\s*['"][^'"]+['"])*)''',
  multiLine: true,
);
final _conditional = RegExp(r'''if\s*\(([^)]*)\)\s*['"]([^'"]+)['"]''');

/// Everything [file] imports, exports or includes (every choice of a
/// conditional import): project files as paths from the package root, the
/// rest ('dart:io', 'package:flutter/...') as is.
List<String> _uses(String file) {
  final uses = <String>[];
  for (final m in _directive.allMatches(File(file).readAsStringSync())) {
    for (final uri in [m[1]!, for (final c in _conditional.allMatches(m[2] ?? '')) c[2]!]) {
      if (uri.startsWith('package:pokerfection/')) {
        uses.add('lib/${uri.substring('package:pokerfection/'.length)}');
      } else if (uri.startsWith('dart:') || uri.startsWith('package:')) {
        uses.add(uri);
      } else {
        uses.add(Uri.parse(file).resolve(uri).path);
      }
    }
  }
  return uses;
}

/// [roots] and everything they reach, not walking past files [stop] says.
Set<String> _closure(Iterable<String> roots, {bool Function(String file)? stop}) {
  final seen = <String>{};
  final queue = [...roots];
  while (queue.isNotEmpty) {
    final next = queue.removeLast();
    if (!seen.add(next) || !next.endsWith('.dart') || next.contains(':')) continue;
    if (!File(next).existsSync() || (stop?.call(next) ?? false)) continue;
    queue.addAll(_uses(next));
  }
  return seen;
}

List<String> _dartFiles(String folder) => [
      if (Directory(folder).existsSync())
        for (final f in Directory(folder).listSync(recursive: true))
          if (f is File && f.path.endsWith('.dart')) f.path.replaceAll(r'\', '/'),
    ];

bool _isBackend(String file) => RegExp(r'^lib/src/kit/jobs/backend[^/]*\.dart$').hasMatch(file);

void main() {
  test("the games' worker reaches no Flutter, platform, app, UI, server or solver code", () {
    const roots = ['lib/game_worker.dart'];
    expect(File(roots.single).existsSync(), isTrue);
    const allowed = {'lib/src/gto/message_queue.dart', 'lib/src/gto/spot_strategy.dart', 'lib/src/engine/actions.dart'};
    final bad = [
      for (final f in _closure(roots))
        if (!allowed.contains(f) &&
            (f.startsWith('package:flutter') ||
                f == 'dart:ui' ||
                f == 'dart:io' ||
                f.startsWith('lib/src/ui/') ||
                f.startsWith('lib/src/app/') ||
                f.startsWith('lib/src/server/') ||
                f.startsWith('lib/src/gto/')))
          f,
    ];
    expect(bad, isEmpty);
  });

  test('the engines and the kit\'s pure files reach no Flutter, dart:io, isolates or package:web', () {
    final roots = [..._dartFiles('lib/src/games'), ..._dartFiles('lib/src/kit')].where((f) => !_isBackend(f));
    for (final root in roots) {
      final bad = [
        for (final f in _closure([root], stop: _isBackend))
          if (f.startsWith('package:flutter') ||
              f == 'dart:ui' ||
              f == 'dart:io' ||
              f == 'dart:isolate' ||
              f.startsWith('package:web/') ||
              f.startsWith('lib/src/ui/') ||
              f.startsWith('lib/src/app/'))
            f,
      ];
      expect(bad, isEmpty, reason: root);
    }
  });

  test("the app doesn't carry the worker's entrypoint", () {
    expect(_closure(['lib/main.dart']), isNot(contains('lib/game_worker.dart')));
  });

  test("the job model doesn't reach the app's side of the jobs", () {
    final reached = _closure(['lib/src/kit/jobs/jobs_core.dart']);
    expect(reached.where((f) => f.endsWith('/jobs.dart') || _isBackend(f)), isEmpty);
    expect(reached, {'lib/src/kit/jobs/jobs_core.dart', 'dart:convert'});
  });
}
