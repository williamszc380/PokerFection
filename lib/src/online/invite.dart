import 'peer_config.dart';
import 'room_host.dart';

export 'invite_links_io.dart' if (dart.library.js_interop) 'invite_links_web.dart';

/// An invitation to a room: its code, and the ways in to try for it, in
/// order (the host's addresses on the same network first, then the room
/// through the meeting service, see [hostServers]).
typedef Invite = ({String code, List<String> servers});

/// The app's own link type: `pokerfection://join?code=ABCDE&server=...`
/// opens the installed app at Play Online with the code filled in.
const inviteScheme = 'pokerfection';

/// Where the web version is published. Invites link to its join page
/// (web/join.html), which opens the app at the room, or this site at the
/// room to play in the browser (through the meeting service; an invite with
/// no room there, from an older app, the host's own web version instead).
const inviteSite = String.fromEnvironment('PF_SITE', defaultValue: 'https://williamszc380.github.io/PokerFection/');

/// A link that opens the app at Play Online with [code], to try [servers]
/// in order (each a repeated `server`; `ws://<address>:<port>/ws` written as
/// just `<address>:<port>`, a room reached through the meeting service as
/// `peer:<code>`, see peer_config.dart).
String inviteLink(String code, List<String> servers) =>
    Uri(scheme: inviteScheme, host: 'join', queryParameters: _inviteQuery(code, servers)).toString();

/// The link to send for room [code], for everyone, with the app or without:
/// the website's join page, with the same query as [inviteLink]. It offers
/// the app, and playing in the browser: on the website, and with [web] (the
/// host serves its own web version, RoomHost.servesWeb) also at the host's
/// addresses over http, which on the same Wi-Fi need no internet.
String siteInviteLink(String code, List<String> servers, {bool web = false}) => Uri.parse(
  inviteSite,
).resolve('join.html').replace(queryParameters: {..._inviteQuery(code, servers), if (web) 'web': '1'}).toString();

Map<String, Object> _inviteQuery(String code, List<String> servers) => {
  'code': code,
  if (servers.isNotEmpty) 'server': [for (final s in servers) _shortServer(s)],
};

/// The address that opens the web version at a room, on a host that
/// serves it: `http://<address>:<port>/?code=ABCDE`.
String browserLink(String code, String address, int port) => 'http://$address:$port/?code=$code';

/// The ways into room [code], hosted on [host], that an invite names, in
/// the order to try: its local addresses (same network: quickest, and no
/// internet needed), then the room through the meeting service (a direct
/// connection from anywhere, while this device holds the room's name
/// there), then the router's public address when the router opened the
/// port by itself (a second way in from the internet, for guests whose
/// network can't connect directly).
List<String> hostServers(RoomHost host, String code) => [
  for (final address in host.localAddresses) 'ws://$address:${host.port}/ws',
  if (host.peerCode == code) peerEntry(code),
  if (host.routerEndpoint case final public?) 'ws://${public.address}:${public.port}/ws',
];

/// The ways into room [code] that a guest's invite names: where this guest
/// reached it, then the room through the meeting service when the room can
/// be reached there ([peer]: its host said so, Welcome.peer), as friends
/// elsewhere may not reach that address. Never for a room on a server of
/// its own, or whose host holds no name there: the name could be anyone's.
List<String> guestServers(String url, String code, {required bool peer}) => [
  url,
  if (peer && !isPeerEntry(url)) peerEntry(code),
];

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

/// The invite in the address of a web page: the website's join page (the
/// servers it lists), or the web version opened at
/// `http://<host>:<port>/?code=ABCDE` (the room, on that host's server).
Invite? inviteFromPage(Uri? page) {
  final listed = inviteFromUri(page);
  if (listed == null || listed.servers.isNotEmpty) return listed;
  return (code: listed.code, servers: [?pageServer(page!)]);
}

/// The game server of the host that served [page] (the web version, over
/// plain http from a host's app); null for any other page.
String? pageServer(Uri page) =>
    page.scheme == 'http' && page.host.isNotEmpty ? 'ws://${page.host}:${page.port}/ws' : null;

/// Of [servers], those a page at [page] can try: a secure (https) page may
/// not open plain ws:// connections (the browser refuses them), so those
/// are left out there rather than tried and waited for; a room through the
/// meeting service and wss:// servers stay.
List<String> reachableFromPage(List<String> servers, Uri page) => page.scheme == 'https'
    ? [for (final s in servers) if (!s.startsWith('ws://')) s]
    : servers;

/// Whether [serverUrl] is a server on this computer, which nobody else can
/// reach.
bool isThisComputer(String serverUrl) =>
    const {'localhost', '127.0.0.1', '::1'}.contains(Uri.tryParse(serverUrl)?.host);

/// A game server as written in a link: `ws://<address>:<port>/ws` as just
/// `<address>:<port>`, anything else whole (a room reached through the
/// meeting service too: `peer:K7M2Q`).
String _shortServer(String url) {
  if (isPeerEntry(url)) return url;
  final uri = Uri.tryParse(url);
  return uri != null && uri.scheme == 'ws' && uri.path == '/ws' && uri.hasPort && !uri.hasQuery
      ? '${uri.host}:${uri.port}'
      : url;
}

/// A game server from a link (see [_shortServer]), or a room reached
/// through the meeting service (`peer:K7M2Q`, in capitals); null if it
/// isn't one.
String? _server(String text) {
  final value = text.trim();
  if (isPeerEntry(value)) {
    final code = parsePeerEntry(value);
    return code == null ? null : peerEntry(code);
  }
  final url = value.contains('://') ? value : 'ws://$value/ws';
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty || (uri.scheme != 'ws' && uri.scheme != 'wss')) return null;
  return url;
}

/// A room code: 5 of the server's letters and digits (no I, L, O, 0 or 1).
final _code = RegExp(r'^[A-HJKMNP-Z2-9]{5}$');
