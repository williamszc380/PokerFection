import 'online_socket.dart';
import 'peer_config.dart';
import 'peer_socket.dart';
import 'socket.dart';

/// Connects to a room's server as an invite or the app names it: a
/// [peerEntry] (`peer:K7M2Q`) directly to the host of that room, wherever
/// it is ([connectPeer], through [peer] when given, with the [seat]'s
/// token of a player coming back); anything else is a game server's
/// WebSocket address ([connectSocket]).
Future<OnlineSocket> connectAny(String url, {PeerConnector? peer, String? seat}) {
  if (isPeerEntry(url)) {
    final code = parsePeerEntry(url);
    if (code == null) return Future.error(ArgumentError.value(url, 'url', 'not a room code'));
    return connectPeer(code, via: peer, seat: seat);
  }
  return connectSocket(url);
}

/// How long to wait for a connection to [url] before trying the next way
/// in: a server on the local network answers at once (3 s), one elsewhere
/// soon (6 s), while a direct connection takes a few exchanges through the
/// meeting service first (up to [PeerConnector.timeout], and a moment more,
/// so its own verdict comes first: no direct route, or no answer).
Duration connectTimeout(String url) {
  if (isPeerEntry(url)) return PeerConnector.timeout + const Duration(seconds: 2);
  return _local.hasMatch(url) ? const Duration(seconds: 3) : const Duration(seconds: 6);
}

/// A WebSocket address on a local network (10/8, 127/8, 192.168/16,
/// 172.16/12).
final _local = RegExp(r'^wss?://(10|127|192\.168|172\.(1[6-9]|2\d|3[01]))\.');
