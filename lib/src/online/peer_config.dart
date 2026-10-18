/// Playing over the internet with no server of our own: each guest's app
/// connects straight to the host's (WebRTC). To find each other, both use
/// a free public meeting service (PeerJS's server, [peerBroker]), which
/// only passes on the few short messages that set the connection up; and
/// public STUN servers, which tell each device the address the internet
/// sees it at. The game itself never goes through either.
///
/// This file holds what both ends must agree on: the names they use at the
/// meeting service, how an invite names such a room ([peerEntry]), and the
/// helpers' addresses.
library;

import 'dart:math';

/// The meeting service (signaling): PeerJS's free public server. Its `key`
/// is ignored and its names are shared by everyone who uses it, so ours
/// all start with [peerIdPrefix].
const peerBroker = 'wss://0.peerjs.com/peerjs';

/// The start of every name this app takes at the meeting service: the app,
/// and the version of what it sends there (a later, different format gets
/// v2, and the two never meet by mistake).
const peerIdPrefix = 'pokerfection-v1-';

/// A room code as typed or read from a link, the way the room has it:
/// without spaces, in capitals. Names at the meeting service are
/// case-sensitive, so `k7m2q` and `K7M2Q` must end up the same.
String normalizeCode(String code) => code.trim().toUpperCase();

/// The host's name at the meeting service for room [code]: guests find the
/// room by its code alone.
String hostPeerId(String code) => '$peerIdPrefix${normalizeCode(code)}';

/// A guest's name at the meeting service: random, so nobody can guess it,
/// and new for each app session (or when, rarely, it is taken).
String guestPeerId([Random? random]) => '${peerIdPrefix}guest-${randomLetters(16, random)}';

/// The secret that goes with a name at the meeting service for one app
/// session: coming back after a dropped connection with the same name and
/// token takes the name back; anyone else asking for it is refused.
String sessionToken([Random? random]) => randomLetters(16, random);

/// [length] random lowercase letters and digits.
String randomLetters(int length, [Random? random]) {
  const letters = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final r = random ?? Random.secure();
  return String.fromCharCodes([for (var i = 0; i < length; i++) letters.codeUnitAt(r.nextInt(letters.length))]);
}

/// How an invite (or the list of servers to try) names a room reached
/// through the meeting service: `peer:K7M2Q`. Old apps can't read it and
/// skip it, keeping the other entries.
///
/// `peer:K7M2Q@<service>` is kept free for a different meeting service
/// later; today only the bare form is read.
String peerEntry(String code) => '$peerScheme${normalizeCode(code)}';

/// The start of a [peerEntry].
const peerScheme = 'peer:';

/// Whether [server] is a [peerEntry] (written any case), rather than a
/// game server's address. Says nothing about whether the code in it is
/// right: see [parsePeerEntry].
bool isPeerEntry(String server) => server.trim().toLowerCase().startsWith(peerScheme);

/// The room code in a [peerEntry] (in capitals), or null if [server] isn't
/// one, or its code isn't a room code.
String? parsePeerEntry(String server) {
  if (!isPeerEntry(server)) return null;
  final code = normalizeCode(server.trim().substring(peerScheme.length));
  return roomCodePattern.hasMatch(code) ? code : null;
}

/// A room code: 5 of the server's letters and digits (no I, L, O, 0 or 1),
/// as the server makes them (RoomRegistry.codeLetters).
final roomCodePattern = RegExp(r'^[A-HJKMNP-Z2-9]{5}$');

/// A STUN or TURN server, as a peer connection is given it.
class IceServer {
  const IceServer(this.urls, {this.username, this.credential});

  /// `stun:host:port` or `turn:host:port`; several for the same server.
  final List<String> urls;

  /// For a TURN relay, which needs an account.
  final String? username;
  final String? credential;

  @override
  String toString() => 'IceServer($urls)';
}

/// The public STUN servers: Google's, then Cloudflare's. A STUN server only
/// tells a device the address and port the internet sees it at, so the two
/// ends can try to reach each other there; no game data goes through it.
///
/// They are given to WebRTC as written, names and all: it looks them up
/// itself (also over IPv6, as some phone networks need), asks each one, and
/// does without one it can't reach. Each URL counts toward the 8 that the
/// apps' WebRTC takes in all (FlutterRtc.maxServerUrls).
const stunServers = [
  IceServer(['stun:stun.l.google.com:19302']),
  IceServer(['stun:stun.cloudflare.com:3478']),
];

/// Relays (TURN) for players whose networks won't let the two devices reach
/// each other directly (some phone networks, strict firewalls): none for
/// now, so those players are told they can't connect from where they are.
///
/// A relay is added here with its account ([IceServer.username] and
/// [IceServer.credential]) and any of `turn:host:port` (UDP, or TCP with
/// `?transport=tcp`) and `turns:host:443?transport=tcp` (TLS, which gets
/// through the strictest firewalls); WebRTC uses whichever works. Keep the
/// STUN and TURN URLs to 8 in all (see [stunServers]). PeerJS's old free
/// relays are gone: never list them.
const turnServers = <IceServer>[];

/// Everything a peer connection is given: [stunServers], then [turnServers].
const iceServers = [...stunServers, ...turnServers];
