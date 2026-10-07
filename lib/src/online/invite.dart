import 'addresses.dart';
import 'room_host.dart';

export 'invite_links_io.dart' if (dart.library.js_interop) 'invite_links_web.dart';

/// An invitation to a room: its code, and the game servers to try for it,
/// in order (the host's addresses: same network first, then the internet).
typedef Invite = ({String code, List<String> servers});

/// The app's own link type: `pokerfection://join?code=ABCDE&server=...`
/// opens the installed app at Play Online with the code filled in.
const inviteScheme = 'pokerfection';

/// A link that opens the app at Play Online with [code], to try [servers]
/// in order (each a repeated `server`; `ws://<address>:<port>/ws` written as
/// just `<address>:<port>`).
String inviteLink(String code, List<String> servers) => Uri(
  scheme: inviteScheme,
  host: 'join',
  queryParameters: {
    'code': code,
    if (servers.isNotEmpty) 'server': [for (final s in servers) _shortServer(s)],
  },
).toString();

/// The address that opens the web version at a room, on a host that
/// serves it: `http://<address>:<port>/?code=ABCDE`.
String browserLink(String code, String address, int port) => 'http://$address:$port/?code=$code';

/// The game servers an invite to a room hosted on [host] names, in the
/// order to try: its local addresses (same network), then the public one
/// (the router's when open, else the one the host set by hand).
List<String> hostServers(RoomHost host) => [
  for (final address in host.localAddresses) 'ws://$address:${host.port}/ws',
  if (host.publicEndpoint case final public?) 'ws://${public.address}:${public.port}/ws',
];

/// The public address a host typed by hand (the router's, from its app or
/// status page): `203.0.113.7`, or `203.0.113.7:47500` when the router
/// leads another port outside to this device's [port]; a name (dynamic
/// DNS) works too. Null if it isn't one: a local network's address, say.
({String address, int port})? parsePublicAddress(String text, {required int port}) {
  final value = text.trim();
  final uri = Uri.tryParse(value.contains('://') ? value : 'ws://$value');
  if (uri == null || (uri.hasPort && (uri.port < 1 || uri.port > 65535))) return null;
  final address = uri.host.toLowerCase();
  final ip = RegExp(r'^[\d.]+$').hasMatch(address);
  if (ip ? !isPublicAddress(address) : !_hostName.hasMatch(address)) return null;
  return (address: address, port: uri.hasPort ? uri.port : port);
}

/// The invite in [text]: an app link anywhere in it (a whole invite
/// message pasted, say), else a browser link to a room, else just a room
/// code; null if there is none.
Invite? parseInvite(String text) {
  final link = RegExp('$inviteScheme://\\S+').firstMatch(text)?.group(0);
  if (link != null) return inviteFromUri(Uri.tryParse(link));
  final page = RegExp(r'https?://\S+').firstMatch(text)?.group(0);
  if (page != null) {
    if (inviteFromPage(Uri.tryParse(page)) case final invite?) return invite;
  }
  final code = text.trim().toUpperCase();
  return _code.hasMatch(code) ? (code: code, servers: const <String>[]) : null;
}

/// The invite in an app link or route ("/?code=ABCDE&server=...", as
/// Android and iOS hand an opened link to the app); null if it has no code.
Invite? inviteFromUri(Uri? uri) {
  final code = uri?.queryParameters['code']?.trim().toUpperCase();
  if (code == null || !_code.hasMatch(code)) return null;
  return (code: code, servers: [for (final s in uri!.queryParametersAll['server'] ?? const <String>[]) ?_server(s)]);
}

/// The invite in the address of a web page (the web version, opened at
/// `http://<host>:<port>/?code=ABCDE`): the room, on that host's server.
Invite? inviteFromPage(Uri? page) {
  final code = page?.queryParameters['code']?.trim().toUpperCase();
  if (code == null || !_code.hasMatch(code)) return null;
  return (code: code, servers: [?pageServer(page!)]);
}

/// The game server of the host that served [page] (the web version, over
/// plain http from a host's app); null for any other page.
String? pageServer(Uri page) =>
    page.scheme == 'http' && page.host.isNotEmpty ? 'ws://${page.host}:${page.port}/ws' : null;

/// Whether [serverUrl] is a server on this computer, which nobody else can
/// reach.
bool isThisComputer(String serverUrl) =>
    const {'localhost', '127.0.0.1', '::1'}.contains(Uri.tryParse(serverUrl)?.host);

/// A game server as written in a link: `ws://<address>:<port>/ws` as just
/// `<address>:<port>`, anything else whole.
String _shortServer(String url) {
  final uri = Uri.tryParse(url);
  return uri != null && uri.scheme == 'ws' && uri.path == '/ws' && uri.hasPort && !uri.hasQuery
      ? '${uri.host}:${uri.port}'
      : url;
}

/// A game server from a link (see [_shortServer]); null if it isn't one.
String? _server(String text) {
  final value = text.trim();
  final url = value.contains('://') ? value : 'ws://$value/ws';
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty || (uri.scheme != 'ws' && uri.scheme != 'wss')) return null;
  return url;
}

/// A room code: 5 of the server's letters and digits (no I, L, O, 0 or 1).
final _code = RegExp(r'^[A-HJKMNP-Z2-9]{5}$');

/// A host name with at least one dot and a letter (`myhome.duckdns.org`).
final _hostName = RegExp(r'^(?=.*[a-z])[a-z0-9-]+(\.[a-z0-9-]+)+$');
