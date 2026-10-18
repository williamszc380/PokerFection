/// How far a room hosted on this device is with letting friends in over
/// the internet (see PeerHost). Kept apart from peer_host.dart, which needs
/// the server's code, so the lobby and the strings can show it anywhere.
library;

/// How far a host is with letting friends in over the internet.
enum PeerPhase {
  /// Taking the room's name at the meeting service: at first, or again
  /// after the connection to it dropped.
  starting,

  /// Friends anywhere can come in with the room's code.
  ready,

  /// They can't (see [PeerTrouble]); friends already in play on.
  unavailable,
}

/// Why friends on the internet can't come in.
enum PeerTrouble {
  /// The meeting service can't be reached (no internet, or it is down). The
  /// host keeps trying in the background.
  unreachable,

  /// Someone else holds the room's name at the meeting service: the room
  /// must be made again, with a new code.
  codeTaken,

  /// This version of the app can't make direct connections.
  unsupported,
}

/// [PeerHost.status]: the phase, and for [PeerPhase.unavailable], why.
class PeerStatus {
  const PeerStatus._(this.phase, [this.trouble]);

  static const starting = PeerStatus._(PeerPhase.starting);
  static const ready = PeerStatus._(PeerPhase.ready);
  const PeerStatus.unavailable(PeerTrouble trouble) : this._(PeerPhase.unavailable, trouble);

  final PeerPhase phase;
  final PeerTrouble? trouble;

  @override
  bool operator ==(Object other) => other is PeerStatus && other.phase == phase && other.trouble == trouble;

  @override
  int get hashCode => Object.hash(phase, trouble);

  @override
  String toString() => 'PeerStatus(${phase.name}${trouble == null ? '' : ', ${trouble!.name}'})';
}
