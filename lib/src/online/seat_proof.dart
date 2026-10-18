/// Proving a seat over a direct connection without giving its token away.
///
/// A room's name at the meeting service is just its code, and while the
/// host's connection to the service is being made again, anyone who knows
/// the code could take the name and so receive the guests who come back
/// through it. A guest's seat token is the only proof of who sits where, so
/// it must never reach whoever happens to answer. Over a direct connection
/// the guest sends a proof instead ([seatProof]): a keyed hash of the
/// token, tied to that one connection ([connectionBinding]: both ends'
/// certificate fingerprints, which WebRTC checks). Only the real host,
/// which knows every token, can check it; and a proof made for a
/// connection to someone else is no good on any other connection.
///
/// The same keyed hash lets a guest coming back skip the line when the host
/// is flooded with made-up offers ([seatPass]).
///
/// Pure Dart: the room runs in the standalone server, the apps and browsers.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// A connection that knows which two devices it joins: a direct connection,
/// by both ends' certificates ([connectionBinding]). Proofs of a seat are
/// tied to it.
abstract interface class BoundConnection {
  /// What a seat proof made on this connection is tied to; null when the
  /// connection can't say (then no proof made on it can be checked).
  String? get binding;
}

/// What ties a proof to one direct connection: the certificate fingerprints
/// in its offer (the guest's) and its answer (the host's), which both ends
/// see alike, and only on that connection: someone in the middle would have
/// to show their own certificates. Null when either has none.
String? connectionBinding(String offerSdp, String answerSdp) {
  final offer = _fingerprints(offerSdp), answer = _fingerprints(answerSdp);
  if (offer.isEmpty || answer.isEmpty) return null;
  return '${offer.join(',')}|${answer.join(',')}';
}

/// The `a=fingerprint:<hash> <value>` lines of [sdp], written one way.
List<String> _fingerprints(String sdp) => {
  for (final m in RegExp(r'^a=fingerprint:(\S+)[ \t]+(\S+)', multiLine: true).allMatches(sdp))
    '${m[1]!.toLowerCase()} ${m[2]!.toUpperCase()}',
}.toList()..sort();

/// The proof that the holder of [token] is coming back to their seat, on
/// the connection [binding] says.
String seatProof(String token, String binding) => _mac(token, 'rejoin|$binding');

/// The pass that goes with a guest's offer when it comes back to a seat: the
/// holder of [token], at the meeting service as [guest], offering connection
/// [connectionId]. Seen only by whoever holds the room's name, and good for
/// that one offer only.
String seatPass(String token, String guest, String connectionId) => _mac(token, 'offer|$guest|$connectionId');

/// Whether proofs [a] and [b] are the same, taking as long whatever they
/// are (so timing tells nothing about how close a guess was).
bool sameProof(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

String _mac(String key, String message) =>
    base64Url.encode(Hmac(sha256, utf8.encode(key)).convert(utf8.encode(message)).bytes).replaceAll('=', '');
