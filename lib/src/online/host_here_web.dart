import 'room_host.dart';

/// A browser can't host a room (no server sockets): it only joins.
const canHostHere = false;

Future<RoomHost> hostHere({void Function(String message)? log, bool openRouter = true}) =>
    throw UnsupportedError('The web version cannot host a room');

/// A browser can't ask the network around it.
Future<List<String>> findRoomNearby(String code) async => const [];
