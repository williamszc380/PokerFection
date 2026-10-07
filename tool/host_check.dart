// Checks hosting on this computer, the way Create Room does it: starts the
// game server inside this process, says which addresses it has and how the
// router setup went, creates a room from 127.0.0.1, then joins it as
// friends would: at 127.0.0.1, at each local network address of the invite,
// by the room code alone (found on the network), and at the public address
// when the router opened the port. Then deals a hand to everyone, checks the
// browser version is served, and closes the room as the host.
//
//   dart run tool/host_check.dart [--no-router]
//
// --no-router leaves the router alone (no port opened with UPnP): the
// public address is then checked as if typed by hand, in the invite only.
// The first run may make Windows Firewall ask about dart.exe (connections
// from this computer to itself work either way).
import 'dart:async';
import 'dart:io';

import 'package:pokerfection/src/online/host_here.dart';
import 'package:pokerfection/src/online/invite.dart';
import 'package:pokerfection/src/online/online_client.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/online/room_host.dart';

var _failed = false;

void _report(bool ok, String what) {
  if (!ok) _failed = true;
  stdout.writeln('${ok ? 'OK  ' : 'FAIL'} $what');
}

/// A player's connection, keeping every message it gets.
class _Player {
  _Player(this.name, this.client) {
    client.attach(seen.add);
  }

  final String name;
  final OnlineClient client;
  final List<ServerMessage> seen = [];

  Future<bool> waitFor(bool Function(ServerMessage m) test, {Duration within = const Duration(seconds: 5)}) async {
    final end = DateTime.now().add(within);
    while (DateTime.now().isBefore(end)) {
      if (seen.any(test)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return false;
  }
}

Future<_Player?> _join(String name, String code, List<String> servers) async {
  final client = OnlineClient(servers.first, alsoTry: servers.skip(1).toList());
  try {
    final welcome = await client.open(JoinRoom(code: code, name: name));
    _report(true, '$name joined at ${client.url} (seat ${welcome.seat})');
    return _Player(name, client);
  } on OnlineFailure catch (e) {
    _report(false, '$name could not join at ${servers.join(', ')}: $e');
    return null;
  }
}

Future<void> main(List<String> args) async {
  final openRouter = !args.contains('--no-router');
  final RoomHost host;
  try {
    host = await hostHere(log: (m) => stderr.writeln('server: $m'), openRouter: openRouter);
  } on Object catch (e) {
    _report(false, "Can't start the server: $e");
    exit(1);
  }
  _report(true, 'Server listening on port ${host.port}');
  stdout.writeln('     Local addresses: ${host.localAddresses.isEmpty ? 'none' : host.localAddresses.join(', ')}');
  stdout.writeln('     Web version served: ${host.servesWeb}');

  // The router setup runs in the background: a few seconds.
  final setupEnd = DateTime.now().add(const Duration(seconds: 15));
  while (host.internet == InternetAccess.checking && DateTime.now().isBefore(setupEnd)) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  stdout.writeln('     Router setup: ${openRouter ? host.internet.name : 'left alone (--no-router)'}'
      '${host.publicEndpoint == null ? '' : ' (public ${host.publicEndpoint!.address}:${host.publicEndpoint!.port})'}');

  final hostClient = OnlineClient(host.ownServer, host: host);
  final Welcome welcome;
  try {
    welcome = await hostClient.open(const CreateRoom(name: 'Host'));
  } on OnlineFailure catch (e) {
    _report(false, 'Creating the room failed: $e');
    await host.stop();
    exit(1);
  }
  final code = welcome.code;
  final hostPlayer = _Player('Host', hostClient);
  _report(welcome.isHost, 'Room $code created at ${host.ownServer}');

  final servers = hostServers(host);
  final link = inviteLink(code, servers);
  stdout.writeln('     Invite link: $link');
  final invite = parseInvite(link)!;
  _report(invite.servers.join(',') == servers.join(','), 'The invite reads back with ${invite.servers.length} addresses');

  final players = <_Player>[hostPlayer];
  if (await _join('Local', code, ['ws://127.0.0.1:${host.port}/ws']) case final p?) players.add(p);
  for (final (i, address) in host.localAddresses.indexed) {
    if (await _join('Lan${i + 1}', code, ['ws://$address:${host.port}/ws']) case final p?) players.add(p);
  }
  // As Join Room does with the invite: every address in order.
  if (await _join('Invited', code, invite.servers) case final p?) players.add(p);
  final nearby = await findRoomNearby(code);
  _report(nearby.isNotEmpty, 'The code alone finds the room on the network: ${nearby.join(', ')}');
  if (nearby.isNotEmpty) {
    if (await _join('ByCode', code, nearby) case final p?) players.add(p);
  }
  if (host.publicEndpoint case final public?) {
    // Many routers don't lead their own public address back inside (no
    // "hairpin"): failing here doesn't mean friends outside can't come in.
    final client = OnlineClient('ws://${public.address}:${public.port}/ws');
    try {
      await client.open(JoinRoom(code: code, name: 'Public'));
      stdout.writeln('OK   Joined at the public address too');
      players.add(_Player('Public', client));
    } on OnlineFailure {
      stdout.writeln('     The public address does not lead back from inside (common; ask a friend to try)');
    }
  }

  // Without the router opened, a public address typed by hand goes last in the invite (nothing can check it).
  if (host.internet != InternetAccess.ready) {
    host.byHand = parsePublicAddress('203.0.113.7', port: host.port);
    final typed = parseInvite(inviteLink(code, hostServers(host)))!.servers;
    _report(
      typed.length == servers.length + 1 && typed.last == 'ws://203.0.113.7:${host.port}/ws',
      'A public address set by hand ends the invite: ${typed.last}',
    );
    host.byHand = null;
  }

  // A wrong code is refused; a full table too.
  final wrong = OnlineClient(host.ownServer);
  try {
    await wrong.open(const JoinRoom(code: 'ZZZZZ', name: 'Nobody'));
    _report(false, 'A wrong room code was let in');
  } on OnlineFailure catch (e) {
    _report(e.error == JoinError.roomNotFound, 'A wrong room code is refused (${e.error?.name})');
  }

  if (host.servesWeb) {
    final address = host.localAddresses.firstOrNull ?? '127.0.0.1';
    final http = HttpClient();
    try {
      final page = await (await http.getUrl(Uri.parse(browserLink(code, address, host.port)))).close();
      final text = await page.transform(const SystemEncoding().decoder).join();
      _report(
        page.statusCode == 200 && text.contains('<base href="/">') && text.contains('flutter_bootstrap.js'),
        'The browser version is served at ${browserLink(code, address, host.port)} (${page.headers.contentType})',
      );
      for (final file in [
        'flutter_bootstrap.js',
        'main.dart.wasm',
        'main.dart.js',
        'solver_worker_wasm.js',
        'solver_worker.mjs',
        'solver_worker.wasm',
        'solver_worker.js',
      ]) {
        final response = await (await http.headUrl(Uri.parse('http://$address:${host.port}/$file'))).close();
        await response.drain<void>();
        _report(response.statusCode == 200, '  /$file: ${response.statusCode} ${response.headers.contentType}');
      }
    } on Object catch (e) {
      _report(false, 'The browser version could not be fetched: $e');
    } finally {
      http.close(force: true);
    }
  }

  // Everyone sees the others; the host deals a hand to all.
  final seated = players.length;
  _report(
    await hostPlayer.waitFor((m) => m is RoomState && m.taken == seated),
    'The host sees all $seated players seated',
  );
  hostClient.send(const StartGame());
  for (final p in players) {
    _report(await p.waitFor((m) => m is HandDealt, within: const Duration(seconds: 20)), '${p.name} was dealt a hand');
  }

  // The host leaves: the room closes for everyone and the server stops.
  await hostClient.close();
  for (final p in players.skip(1)) {
    _report(
      await p.waitFor((m) => m is Closing && m.reason == CloseReason.roomClosed),
      '${p.name} was told the host closed the room',
    );
  }
  await host.stopped.timeout(const Duration(seconds: 5));
  try {
    final socket = await Socket.connect('127.0.0.1', host.port, timeout: const Duration(seconds: 2));
    socket.destroy();
    _report(false, 'The server still listens after the room closed');
  } on SocketException {
    _report(true, 'The server stopped with the room');
  }
  for (final p in players.skip(1)) {
    await p.client.close(leave: false);
  }
  stdout.writeln(_failed ? 'Some checks failed.' : 'All checks passed.');
  exit(_failed ? 1 : 0);
}
