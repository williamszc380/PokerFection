import '../server/client_link.dart';
import 'channel_socket.dart';

export 'channel_socket.dart';

/// A guest's connection over a direct connection's data channel, as the
/// host's room sees it (and, being a ChannelSocket, as the guest's app
/// would): see ChannelSocket for how it keeps track of the other end.
///
/// Like a player's WebSocket (WebSocketLink), it takes only messages up to
/// [maxMessage] characters; a longer one ends the connection.
///
/// The guest's app uses ChannelSocket itself: the app reaches the server's
/// code only to host a room.
class ChannelLink extends ChannelSocket implements ClientLink {
  ChannelLink(super.peer, super.channel, {required this.address, super.clock, super.binding})
    : super(maxIncoming: maxMessage);

  /// The guest's name at the meeting service (`peer:<name>`): the room's
  /// limits per address then count each guest on their own.
  @override
  final String address;

  /// Longest message from a guest: as over a WebSocket (WebSocketLink's,
  /// which this can't import: it needs dart:io, and browsers will host too).
  static const maxMessage = 16 * 1024;
}
