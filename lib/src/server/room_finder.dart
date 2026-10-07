/// Finding a room on the local network by its code alone: the joining
/// device asks everyone on its networks (a UDP broadcast, "PokerFection
/// find ABCDE") and a host with that room answers with its port. So on the
/// same Wi-Fi, reading out the code is enough; the invite (with the host's
/// addresses) works everywhere else.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _ask = 'PokerFection find ';
const _answer = 'PokerFection room ';

/// The host's side: answers for the rooms [hasRoom] knows, telling where
/// their server listens ([serverPort]).
class RoomBeacon {
  RoomBeacon._(this._socket, this._hasRoom, this._serverPort) {
    _socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = _socket.receive();
      if (datagram == null || datagram.data.length > 64) return;
      final text = ascii.decode(datagram.data, allowInvalid: true);
      if (!text.startsWith(_ask)) return;
      final code = text.substring(_ask.length).trim().toUpperCase();
      if (!_hasRoom(code)) return;
      try {
        _socket.send(ascii.encode('$_answer$code $_serverPort'), datagram.address, datagram.port);
      } on Object {
        // They ask again.
      }
    });
  }

  final RawDatagramSocket _socket;
  final bool Function(String code) _hasRoom;
  final int _serverPort;

  /// Starts answering on UDP [port]; null if it can't listen there.
  static Future<RoomBeacon?> start({
    required int port,
    required int serverPort,
    required bool Function(String code) hasRoom,
  }) async {
    try {
      // Shared: several hosts on one computer (test copies of the app) all hear.
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port, reuseAddress: true);
      return RoomBeacon._(socket, hasRoom, serverPort);
    } on Object {
      return null;
    }
  }

  void close() => _socket.close();
}

/// The joining side: the game servers (`ws://<address>:<port>/ws`) of the
/// hosts on this device's networks that have room [code], as they answer
/// within [wait]. Asks on UDP [port], from [localAddresses] (this device's:
/// each network's broadcast address is guessed as a /24).
Future<List<String>> findRoom(
  String code, {
  required int port,
  List<String> localAddresses = const [],
  Duration wait = const Duration(milliseconds: 1200),
}) async {
  final found = <String>[];
  RawDatagramSocket? socket;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket!.receive();
      if (datagram == null || datagram.data.length > 64) return;
      final parts = ascii.decode(datagram.data, allowInvalid: true).split(' ');
      if (parts.length != 4 || '${parts[0]} ${parts[1]} ' != _answer || parts[2] != code) return;
      final serverPort = int.tryParse(parts[3]);
      if (serverPort == null || serverPort <= 0 || serverPort > 65535) return;
      final url = 'ws://${datagram.address.address}:$serverPort/ws';
      if (!found.contains(url)) found.add(url);
    });
    final targets = {
      '255.255.255.255',
      '127.0.0.1',
      for (final a in localAddresses) '${a.substring(0, a.lastIndexOf('.'))}.255',
    };
    void ask() {
      for (final target in targets) {
        try {
          socket!.send(ascii.encode('$_ask$code'), InternetAddress(target), port);
        } on Object {
          // Not allowed that way (some phones): the others may work.
        }
      }
    }

    // Twice, as UDP may be lost.
    ask();
    await Future<void>.delayed(wait ~/ 2);
    ask();
    await Future<void>.delayed(wait ~/ 2);
  } on Object {
    // No network to ask on.
  } finally {
    socket?.close();
  }
  return found;
}
