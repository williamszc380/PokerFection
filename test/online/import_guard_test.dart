/// The server runs without Flutter, so the code it uses must not reach the
/// app's Flutter, solver or bot code; and the app carries the server only to
/// host a room (never in the web version, which can't).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files the server is built from (those that exist yet).
const _serverRoots = [
  'bin/server.dart',
  'lib/src/server',
  'lib/src/engine',
  'lib/src/game/table_rules.dart',
  'lib/src/online/protocol.dart',
  'lib/src/online/event_codec.dart',
  'lib/src/online/redact.dart',
  'lib/src/online/timing.dart',
  'lib/src/online/clock.dart',
];

/// Never reachable from the server.
const _notOnServer = [
  'lib/src/gto/',
  'lib/src/bots/',
  'lib/src/ui/',
  'lib/src/app/',
  'lib/src/l10n/',
  'lib/src/game/table_session.dart',
  'lib/src/game/history.dart',
];

final _directive = RegExp(
    r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]((?:\s+if\s*\([^)]*\)\s*['"][^'"]+['"])*)''',
    multiLine: true);
final _conditional = RegExp(r'''if\s*\(([^)]*)\)\s*['"]([^'"]+)['"]''');

/// Everything [file] imports, exports or includes: project files as paths
/// from the package root, the rest ('dart:io', 'package:flutter/...') as is.
/// Of a conditional import, every choice; or with [web], the one the web
/// version (true) or the apps (false) get.
List<String> _uses(String file, {bool? web}) {
  final uses = <String>[];
  for (final m in _directive.allMatches(File(file).readAsStringSync())) {
    final choices = [for (final c in _conditional.allMatches(m[2] ?? '')) (when: c[1]!, uri: c[2]!)];
    final webChoice = choices.where((c) => c.when.contains('dart.library.js')).firstOrNull?.uri;
    final appChoice = choices.where((c) => c.when.contains('dart.library.io')).firstOrNull?.uri;
    final picked = switch (web) {
      null => [m[1]!, for (final c in choices) c.uri],
      true => [webChoice ?? m[1]!],
      false => [appChoice ?? m[1]!],
    };
    for (final uri in picked) {
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

/// [roots] and everything they reach (see [_uses] for [web]).
Set<String> _closure(Iterable<String> roots, {bool? web}) {
  final seen = <String>{};
  final queue = [...roots];
  while (queue.isNotEmpty) {
    final next = queue.removeLast();
    if (!seen.add(next) || !next.endsWith('.dart') || next.contains(':')) continue;
    if (!File(next).existsSync()) continue;
    queue.addAll(_uses(next, web: web));
  }
  return seen;
}

List<String> _expand(List<String> roots) {
  final files = <String>[];
  for (final root in roots) {
    if (FileSystemEntity.isDirectorySync(root)) {
      for (final f in Directory(root).listSync(recursive: true)) {
        if (f is File && f.path.endsWith('.dart')) files.add(f.path.replaceAll(r'\', '/'));
      }
    } else if (File(root).existsSync()) {
      files.add(root);
    }
  }
  return files;
}

void main() {
  test('the server reaches no Flutter, solver, bot or app code', () {
    final reached = _closure(_expand(_serverRoots));
    final bad = [
      for (final f in reached)
        if (f == 'dart:ui' ||
            f.startsWith('dart:js') ||
            f == 'dart:html' ||
            (f.startsWith('package:') && !f.startsWith('package:pokerfection/')) ||
            _notOnServer.any(f.startsWith))
          f,
    ];
    expect(bad, isEmpty);
  });

  test('the web version carries no server code; the apps reach it only to host a room', () {
    final web = _closure(['lib/main.dart', 'lib/solver_worker.dart'], web: true);
    expect(web.where((f) => f.startsWith('lib/src/server/') || f == 'dart:io'), isEmpty);
    final apps = _closure(['lib/main.dart'], web: false);
    final users = {
      for (final f in apps)
        if (f.startsWith('lib/') && !f.startsWith('lib/src/server/') && _uses(f).any((u) => u.startsWith('lib/src/server/')))
          f,
    };
    expect(users, {'lib/src/online/host_here_io.dart'});
    // Sanity check: the walk does reach the app's code.
    expect(apps, contains('lib/src/game/table_session.dart'));
  });
}
