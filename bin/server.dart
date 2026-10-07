// The online game server on its own, for your own computer. The app
// doesn't need it: Create Room runs the same server inside the app. Run it
// with
//   dart run bin/server.dart
// PORT sets the port (47474 by default). WEB names a folder with the web
// version to serve to browser players (made by
// `dart run tool/build_web.dart --host`, in build/web_host).
// Players then enter ws://<this computer's address>:<port>/ws as the
// Server in Play Online (see lib/src/online/protocol.dart). The guide to
// hosting, with this server too, is docs/online_server.md.
import 'dart:async';
import 'dart:io';

import 'package:pokerfection/src/server/poker_server.dart';
import 'package:pokerfection/src/server/web_files.dart';

Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? PokerServer.defaultPort;
  final webFolder = Platform.environment['WEB'];
  void log(String message) => stderr.writeln('${DateTime.now().toUtc().toIso8601String()} $message');
  await runZonedGuarded(() async {
    final server = PokerServer(log: log, web: webFolder == null ? null : WebFiles(Directory(webFolder)));
    final bound = await server.start(port: port);
    log('PokerFection server listening on port $bound');
    if (server.web case final web? when !web.available) log('No web version in $webFolder');
    var stopping = false;
    Future<void> stop(ProcessSignal signal) async {
      if (stopping) return;
      stopping = true;
      log('Stopping ($signal)');
      await server.close();
      exit(0);
    }

    ProcessSignal.sigint.watch().listen(stop);
    // Windows has no SIGTERM.
    if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(stop);
  }, (error, stack) => log('Unhandled error: $error\n$stack'));
}
