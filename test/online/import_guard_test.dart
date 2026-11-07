/// The server runs without Flutter, so the code it uses must not reach the
/// app's Flutter, solver or bot code; the apps carry the server only to host
/// a room; and the web version carries only the room itself (a browser
/// hosts in the page, with no game server and no dart:io).
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
  'lib/src/online/games',
];

/// The only other packages the server may use: pure Dart, no Flutter
/// (HMAC-SHA256 for seat proofs, see seat_proof.dart).
const _serverPackages = ['package:crypto/'];

/// Never reachable from the server.
const _notOnServer = [
  'lib/src/gto/',
  'lib/src/bots/',
  'lib/src/ui/',
  'lib/src/app/',
  'lib/src/l10n/',
  'lib/src/game/table_session.dart',
  'lib/src/game/history.dart',
  'lib/src/kit/jobs/',
];

final _directive = RegExp(
  r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]((?:\s+if\s*\([^)]*\)\s*['"][^'"]+['"])*)''',
  multiLine: true,
);
final _conditional = RegExp(r'''if\s*\(([^)]*)\)\s*['"]([^'"]+)['"]''');

/// The `dart.library.*` a conditional import can test, as each kind of
/// build has them: the web version (`_web`), the apps (`_apps`: Flutter on
/// a device), and tools run with plain Dart (`_plainDart`, no Flutter).
const _web = {'js_interop', 'js_util', 'html', 'ui', 'ui_web'};
const _apps = {'io', 'ffi', 'isolate', 'ui'};
const _plainDart = {'io', 'ffi', 'isolate'};

/// Everything [file] imports, exports or includes: project files as paths
/// from the package root, the rest ('dart:io', 'package:flutter/...') as is.
/// Of a conditional import, every choice; or with [platform] (one of the
/// sets above), the one that build gets: the first whose library it has,
/// as Dart picks.
List<String> _uses(String file, {Set<String>? platform}) {
  final uses = <String>[];
  for (final m in _directive.allMatches(File(file).readAsStringSync())) {
    final choices = [for (final c in _conditional.allMatches(m[2] ?? '')) (when: c[1]!, uri: c[2]!)];
    final picked = platform == null
        ? [m[1]!, for (final c in choices) c.uri]
        : [choices.where((c) => platform.contains(_library(c.when))).firstOrNull?.uri ?? m[1]!];
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

/// The library a condition tests (`dart.library.ui` → `ui`).
String _library(String condition) {
  final library = RegExp(r'dart\.library\.(\w+)').firstMatch(condition)?.group(1);
  if (library == null) throw FormatException('A condition this test does not know', condition);
  return library;
}

/// [roots] and everything they reach (see [_uses] for [platform]).
Set<String> _closure(Iterable<String> roots, {Set<String>? platform}) {
  final seen = <String>{};
  final queue = [...roots];
  while (queue.isNotEmpty) {
    final next = queue.removeLast();
    if (!seen.add(next) || !next.endsWith('.dart') || next.contains(':')) continue;
    if (!File(next).existsSync()) continue;
    queue.addAll(_uses(next, platform: platform));
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
            (f.startsWith('package:') &&
                !f.startsWith('package:pokerfection/') &&
                !_serverPackages.any(f.startsWith)) ||
            _notOnServer.any(f.startsWith))
          f,
    ];
    expect(bad, isEmpty);
  });

  test('the web version carries only the pure-Dart room (to host in a browser), never dart:io; the apps reach the '
      'server only to host a room (and let guests in from anywhere)', () {
    final web = _closure(['lib/main.dart', 'lib/solver_worker.dart'], platform: _web);
    // A browser hosts the room in the page: the rooms, one room and its hands, and a connection's interface. No
    // game server, router or local network search (those need dart:io).
    expect(web.where((f) => f.startsWith('lib/src/server/')).toSet(), {
      'lib/src/server/room_registry.dart',
      'lib/src/server/room.dart',
      'lib/src/server/poker_table.dart',
      'lib/src/server/runner_table.dart',
      'lib/src/server/hand_runner.dart',
      'lib/src/server/client_link.dart',
    });
    // The games' online parts (pure Dart): the runner framework and each game's runner.
    expect(
      web,
      containsAll([
        'lib/src/online/games/game_runner.dart',
        'lib/src/online/games/online_games.dart',
        'lib/src/online/games/game_envelope.dart',
        for (final key in ['gomoku', 'big_two', 'doudizhu', 'blackjack'])
          'lib/src/games/$key/online/${key}_runner.dart',
      ]),
    );
    expect(web, isNot(contains('dart:io')));
    expect(web, containsAll(['lib/src/online/in_process_host.dart', 'lib/src/online/peer_host.dart']));
    final apps = _closure(['lib/main.dart'], platform: _apps);
    final users = {
      for (final f in apps)
        if (f.startsWith('lib/') &&
            !f.startsWith('lib/src/server/') &&
            _uses(f).any((u) => u.startsWith('lib/src/server/')))
          f,
    };
    // Hosting: the game server, and the direct connections' way into the room (PeerHost hands each guest's
    // channel to the room as a ChannelLink). Only host_here_io.dart reaches them.
    expect(users, {
      'lib/src/online/host_here_io.dart',
      'lib/src/online/peer_host.dart',
      'lib/src/online/channel_link.dart',
    });
    // The browser's own code stays out of the apps, and the browser's way of hosting with it.
    expect(apps.where((f) => f.startsWith('package:web')), isEmpty);
    expect(apps, isNot(contains('lib/src/online/in_process_host.dart')));
    // Sanity check: the walk does reach the app's code, and the direct
    // connections' (behind `dart.library.ui`) in both.
    expect(apps, contains('lib/src/game/table_session.dart'));
    expect(apps, containsAll(['lib/src/online/rtc_flutter.dart', 'lib/src/online/rtc_support_io.dart']));
    expect(web, containsAll(['lib/src/online/rtc_flutter.dart', 'lib/src/online/rtc_support_web.dart']));
    expect(web, contains('package:web/web.dart'));
  });

  test('the tools run with plain Dart (bin/server.dart, tool/host_check.dart) reach no Flutter: no direct '
      'connections there', () {
    for (final root in ['bin/server.dart', 'tool/host_check.dart']) {
      final tool = _closure([root], platform: _plainDart);
      expect(
        tool.where(
          (f) =>
              f == 'dart:ui' ||
              f.startsWith('package:flutter') ||
              f.startsWith('package:web') ||
              f.endsWith('rtc_flutter.dart'),
        ),
        isEmpty,
        reason: root,
      );
    }
    final hostCheck = _closure(['tool/host_check.dart'], platform: _plainDart);
    expect(hostCheck, contains('lib/src/online/online_client.dart'));
    expect(hostCheck, contains('lib/src/online/rtc_none.dart'));
  });
}
