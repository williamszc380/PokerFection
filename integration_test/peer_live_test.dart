// The whole way friends play over the internet, for real, inside one app:
// a room hosted here takes its code as its name at the PUBLIC meeting
// service (wss://0.peerjs.com), and guests join it with the code alone,
// each over its own direct connection (flutter_webrtc on both ends), with
// the public STUN servers. Host and guests are on this one device, so the
// connection finds its way without going through the router; that it works
// between two networks is for a test on two devices.
//
// It goes on the internet, so it runs only when asked:
//
//   flutter test integration_test/peer_live_test.dart -d windows --dart-define=PEER_LIVE=1
//
// Everyone enters the room as a spectator: the host and two guests take a
// seat (Join game), and three more guests watch a hand.
//
// Each run takes a new random room code (and so a new name at the service),
// and sends it a few dozen short messages: run it now and then, not in a
// loop. If the service is down or changes its rules, this fails at the
// first step, saying so.
//
// Lines starting with "PEER:" are measurements, for the record.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pokerfection/src/engine/events.dart';
import 'package:pokerfection/src/online/channel_link.dart';
import 'package:pokerfection/src/online/connect.dart';
import 'package:pokerfection/src/online/memory_link.dart';
import 'package:pokerfection/src/online/online_client.dart';
import 'package:pokerfection/src/online/online_socket.dart';
import 'package:pokerfection/src/online/peer_config.dart';
import 'package:pokerfection/src/online/peer_host.dart';
import 'package:pokerfection/src/online/peer_socket.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/online/rtc.dart';
import 'package:pokerfection/src/server/room_registry.dart';

/// Whether to go on the internet: `--dart-define=PEER_LIVE=1`.
const _live = String.fromEnvironment('PEER_LIVE') == '1';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group(
    'through the public meeting service and public STUN',
    skip: _live ? false : 'goes on the internet: run with --dart-define=PEER_LIVE=1',
    () {
      final room = _LiveRoom();
      setUpAll(room.open);
      tearDownAll(room.end);

      test('the room takes its code as its name at the meeting service', () {
        expect(room.peer.status, PeerStatus.ready);
        expect(room.code, matches(roomCodePattern));
        expect(room.host.client.welcome!.code, room.code);
      });

      test('a guest joins with the code alone: welcomed as a spectator, then seated by Join game', () async {
        final ben = room.ben = await room.join('Ben');
        expect(ben.client.status, OnlineStatus.open);
        expect(ben.client.isHost, isFalse);
        expect(ben.client.url, peerEntry(room.code), reason: 'in through the meeting service, not a server');
        await room.until(() => ben.client.room != null, 'the room, after the welcome');
        expect(ben.client.isSpectator, isTrue);
        await room.sit(ben);
        expect(_names(ben.client.room!), ['Ann', 'Ben']);
        await room.until(() => _names(room.host.client.room!).contains('Ben'), 'the host seeing Ben');
        expect(room.links.single.address, startsWith('peer:pokerfection-v1-guest-'));
        // A public STUN server answered the guest: it found the address the
        // internet sees it at (srflx), besides its own (host), before
        // offering. The host's connection, made with the guest's addresses
        // in hand, may open on this one device before its STUN answer comes
        // (WebRTC then stops looking): the test with only STUN's addresses,
        // below, shows the host's side.
        _log('candidates: guest ${room.guestRtc.types}, host ${room.hostRtc.types}');
        expect(room.guestRtc.types, containsAll(['host', 'srflx']), reason: 'the STUN request had no answer');
        expect(room.hostRtc.types, contains('host'));
      });

      test('chat in any language arrives, both ways', () async {
        final ben = room.ben!;
        const fromBen = '¡Hola! Grüße, 你好, Привет, नमस्ते 🂡';
        const fromAnn = 'こんにちは, مرحبا, Ελλάδα ♠♥♦♣';
        final annHeard = room.host.client.said.firstWhere((l) => l.text == fromBen);
        expect(ben.client.say(fromBen), isTrue);
        expect((await annHeard.timeout(_wait)).name, 'Ben');
        final benHeard = ben.client.said.firstWhere((l) => l.text == fromAnn);
        expect(room.host.client.say(fromAnn), isTrue);
        expect((await benHeard.timeout(_wait)).name, 'Ann');
      });

      test('a message of 16 KB arrives whole and is played; one longer ends the connection, and the guest '
          'gets its seat back over a new one', () async {
        final ben = room.ben!;
        // A chat message padded with a field the room ignores, up to the
        // longest a guest may send (in characters, as over a WebSocket):
        // many more bytes than that on the wire.
        const text = 'Padded to 16 KB: ñ 你好';
        final big = _padded({'t': 'say', 'text': text}, ChannelLink.maxMessage);
        expect(big.length, ChannelLink.maxMessage);
        final heard = room.host.client.said.firstWhere((l) => l.text == text);
        ben.socket.send(big);
        expect((await heard.timeout(_wait)).name, 'Ben');
        expect(room.links.single.isClosed, isFalse);

        final seat = ben.client.mySeat;
        final dropped = Stopwatch()..start();
        ben.socket.send(_padded({'t': 'say', 'text': 'too long'}, ChannelLink.maxMessage + 1));
        await room.until(() => room.links.first.isClosed, 'the host ending the connection');
        await room.until(() => ben.client.status == OnlineStatus.reconnecting, 'the guest noticing');
        _log('guest noticed the dropped connection after ${dropped.elapsedMilliseconds} ms');
        await room.until(() => ben.client.status == OnlineStatus.open, 'the guest back in', within: _join);
        _log('guest back in its seat ${dropped.elapsedMilliseconds} ms after the drop');
        expect(room.links, hasLength(2), reason: 'back over a new direct connection');
        expect(room.links.last.isClosed, isFalse);
        expect(ben.client.mySeat, seat);
      });

      test('the guest leaves: the host sees the seat free at once', () async {
        final ben = room.ben!;
        final link = room.links.last;
        final left = Stopwatch()..start();
        await ben.client.close();
        await room.until(() => !_names(room.host.client.room!).contains('Ben'), 'the host seeing Ben gone');
        _log('host saw the guest leave after ${left.elapsedMilliseconds} ms');
        expect(link.isClosed, isTrue, reason: 'the guest said bye: no waiting for the silence');
        expect(left.elapsed, lessThan(ChannelSocket.silence));
      });

      test('a second guest joins', () async {
        final cat = room.cat = await room.join('Cat');
        await room.until(() => cat.client.room != null, 'the room, after the welcome');
        await room.sit(cat);
        expect(_names(cat.client.room!), ['Ann', 'Cat']);
        expect(room.links.last.address, isNot(room.links.first.address), reason: 'each guest at its own address');
      });

      test("three more guests watch a hand, each over its own connection: every person's cards, not the bot's",
          () async {
        final names = ['Dan', 'Eve', 'Fay'];
        final watchers = [for (final name in names) await room.join(name)];
        final seen = [for (final _ in watchers) <ServerMessage>[]];
        for (final (i, watcher) in watchers.indexed) {
          watcher.client.attach(seen[i].add);
        }
        room.host.client.send(const AddBot(style: 'tag'));
        await room.until(() => room.host.client.room!.taken == 3, 'the bot seated');
        await room.until(() => room.host.client.room!.members.length == 6, 'the host seeing everyone');
        room.host.client.send(const StartGame());
        final watched = Stopwatch()..start();
        for (final (i, watcher) in watchers.indexed) {
          await room.until(() => seen[i].any((m) => m is HandDealt), '${names[i]} watching a hand', within: _join);
          final dealt = seen[i].whereType<HandDealt>().first;
          final lineup = seen[i].whereType<NextHand>().lastWhere((next) => next.hand == dealt.hand);
          expect(lineup.you, isNull, reason: 'a spectator has no seat in the hand');
          expect(dealt.batch.whereType<HoleCardsDealt>().single.cards.keys, [
            for (final (s, info) in lineup.seats.indexed)
              if (info.kind == SeatKind.human) s,
          ]);
          expect(watcher.client.isSpectator, isTrue);
        }
        _log('3 spectators saw the first hand ${watched.elapsedMilliseconds} ms after Start');
        expect(room.links.map((l) => l.address).toSet(), hasLength(room.links.length));
      });

      test('with only the addresses STUN found (as between two networks), the public addresses cross the meeting '
          "service both ways; the guest connects if this network's router loops them back, else hears there is no "
          'direct route', () async {
        // Each end ignores the other's own addresses (host candidates), so
        // the only way between them is the one STUN found: out to the
        // router's public address and back in. Many home routers don't loop
        // such traffic back (hairpinning): between two networks there is no
        // need to, so either outcome is right here, but nothing else.
        room.hostRtc.onlyStun = room.guestRtc.onlyStun = true;
        room.hostRtc.received.clear();
        room.guestRtc.received.clear();
        final trying = Stopwatch()..start();
        Object outcome;
        try {
          final socket = await connectPeer(room.code, via: PeerConnector(rtc: room.guestRtc));
          outcome = 'connected';
          await socket.close();
        } on Object catch (e) {
          outcome = e;
        } finally {
          room.hostRtc.onlyStun = room.guestRtc.onlyStun = false;
        }
        _log(
          'only STUN addresses: $outcome after ${trying.elapsedMilliseconds} ms; received: '
          'guest ${room.guestRtc.received}, host ${room.hostRtc.received}',
        );
        expect(room.hostRtc.types, contains('srflx'), reason: "the host's STUN request had no answer");
        expect(room.guestRtc.received['srflx'], greaterThan(0), reason: "the host's public address never arrived");
        expect(room.hostRtc.received['srflx'], greaterThan(0), reason: "the guest's public address never arrived");
        expect(outcome, anyOf('connected', isA<NoDirectRoute>()));
      });

      test('the host closes the room: the guest hears at once, and the name is given back', () async {
        final cat = room.cat!;
        final closed = Stopwatch()..start();
        await room.host.client.close();
        await room.until(() => cat.client.status == OnlineStatus.closed, 'the guest hearing the room closed');
        _log('guest heard the room closed after ${closed.elapsedMilliseconds} ms');
        expect(cat.client.closeReason, CloseReason.roomClosed);
        await room.peer.stop();
        // Nobody holds the room's name now: a guest trying the code hears
        // so from the meeting service, without waiting for a timeout.
        final asked = Stopwatch()..start();
        await expectLater(
          connectPeer(room.code, via: PeerConnector(rtc: room.guestRtc)),
          throwsA(isA<ConnectionRefused>()),
        );
        _log('a guest trying the closed room was refused after ${asked.elapsedMilliseconds} ms');
      });
    },
  );

  group(
    'a host that vanishes, through the public meeting service',
    skip: _live ? false : 'goes on the internet: run with --dart-define=PEER_LIVE=1',
    () {
      final room = _LiveRoom();
      setUpAll(room.open);
      tearDownAll(room.end);

      test('is known to be gone once it has been missing at the meeting service for '
          '${OnlineClient.peerRefusalSpan.inSeconds} s', () async {
        final ben = room.ben = await room.join('Ben');
        // The host's app stops at once, with no word to anyone: its
        // connections end without a bye, its name at the service goes.
        final vanished = Stopwatch()..start();
        for (final link in room.links) {
          await link.peer.close();
        }
        await room.peer.stop();
        await room.until(() => ben.client.status == OnlineStatus.reconnecting, 'the guest noticing');
        _log('guest noticed the host gone after ${vanished.elapsedMilliseconds} ms');
        await room.until(
          () => ben.client.status == OnlineStatus.closed,
          'the guest giving up',
          within: OnlineClient.peerRefusalSpan + const Duration(seconds: 40),
        );
        _log('guest knew the room closed after ${vanished.elapsedMilliseconds} ms');
        expect(ben.client.closeReason, CloseReason.roomClosed);
        expect(vanished.elapsed, greaterThanOrEqualTo(OnlineClient.peerRefusalSpan));
        expect(room.links, hasLength(1), reason: 'no new connection was ever made to the vanished room');
      }, timeout: const Timeout(Duration(minutes: 3)));
    },
  );
}

/// How long a step on the internet may take: a few messages through the
/// meeting service, or across a direct connection.
const _wait = Duration(seconds: 15);

/// How long joining may take: the most a direct connection is given, and
/// the welcome.
const _join = Duration(seconds: 30);

/// A room hosted on this device, open to guests on the internet, and its
/// guests: all real (the public meeting service, STUN, WebRTC), on the
/// real clock.
class _LiveRoom {
  /// The connections both ends make, with the candidates they find.
  final hostRtc = _RecordingRtc(platformRtc()), guestRtc = _RecordingRtc(platformRtc());

  late final RoomRegistry registry;
  late final PeerHost peer;
  late final String code;
  late final _Guest host;

  /// The guests' connections, as the room got them.
  final List<ChannelLink> links = [];

  /// Guests, as the tests let them in.
  _Guest? ben, cat;
  final List<_Guest> _guests = [];

  /// Takes a new room code's name at the meeting service, then the host's
  /// app creates the room (its own connection is in memory, as in the app).
  Future<void> open() async {
    registry = RoomRegistry(maxRooms: 1, nextCode: () => peer.code);
    peer = PeerHost(
      accept: (link) {
        links.add(link as ChannelLink);
        registry.accept(link);
      },
      rtc: hostRtc,
    );
    final took = Stopwatch()..start();
    code = await peer.start();
    if (peer.status != PeerStatus.ready) {
      await peer.statuses.firstWhere((s) => s != PeerStatus.starting).timeout(_wait, onTimeout: () => peer.status);
    }
    _log('room $code: name at the meeting service ${peer.status} after ${took.elapsedMilliseconds} ms');
    if (peer.status != PeerStatus.ready) {
      throw StateError('The meeting service at $peerBroker would not give us the room name: ${peer.status}');
    }
    final client = OnlineClient(
      'memory:host',
      connect: (_) async {
        final (server, device) = MemoryLink.pair(address: 'host');
        registry.accept(server);
        return device;
      },
    );
    host = _Guest(client);
    await client.open(const CreateRoom(name: 'Ann', game: holdemKey, settings: RoomSettings(seats: 4)));
    await until(() => client.room != null, 'the host seeing the room');
    // The host enters watching too, and takes a seat.
    await sit(host);
  }

  /// [guest] takes a seat (Join game), and waits until the room says so.
  Future<void> sit(_Guest guest) async {
    guest.client.send(const TakeSeat());
    await until(() => guest.client.mySeat != null, 'a seat taken');
  }

  /// A guest joins with the room's code alone, as a player who typed it
  /// does (the `peer:` entry, through connectAny), on its own device: its
  /// own name at the meeting service.
  Future<_Guest> join(String name) async {
    final connector = PeerConnector(rtc: guestRtc);
    late final _Guest guest;
    final client = OnlineClient(
      peerEntry(code),
      connect: (url) async {
        final socket = await connectAny(url, peer: connector);
        guest.socket = socket;
        return socket;
      },
    );
    guest = _Guest(client);
    _guests.add(guest);
    final joining = Stopwatch()..start();
    final welcome = await client.open(JoinRoom(code: code, name: name)).timeout(_join);
    _log('$name: join to welcome in ${joining.elapsedMilliseconds} ms');
    expect(welcome.code, code);
    return guest;
  }

  /// Waits until [done], at most [within].
  Future<void> until(bool Function() done, String what, {Duration within = _wait}) async {
    final waited = Stopwatch()..start();
    while (!done()) {
      if (waited.elapsed > within) fail('Never: $what (waited ${within.inSeconds} s)');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  /// Everyone goes, the room closes, and its name is given back.
  Future<void> end() async {
    for (final g in [..._guests, host]) {
      await g.client.close(leave: false);
    }
    registry.shutdown();
    await peer.stop();
    for (final link in links) {
      await link.close();
    }
    // The guests' names at the service are given back a moment after
    // their last try (PeerConnector.linger).
    await Future<void>.delayed(PeerConnector.linger + const Duration(seconds: 1));
  }
}

/// A device in the room, and the connection under its client (to send what
/// the client never would).
class _Guest {
  _Guest(this.client);

  final OnlineClient client;
  late OnlineSocket socket;
}

/// Makes the platform's connections, notes the kind of every candidate
/// they find (host, srflx, prflx, relay), and with [onlyStun] ignores the
/// other end's own addresses.
class _RecordingRtc implements RtcFactory {
  _RecordingRtc(this._inner);

  final RtcFactory _inner;

  /// The kinds of candidates this side's connections found.
  final Set<String> types = {};

  /// Whether new connections ignore the other end's host candidates (its
  /// addresses on its own networks), keeping only those STUN found.
  bool onlyStun = false;

  /// The other end's candidates that reached this side's connections
  /// (through the meeting service), by kind: ignored ones too.
  final Map<String, int> received = {};

  @override
  RtcPeer create({List<IceServer> servers = iceServers}) =>
      _RecordingPeer(this, _inner.create(servers: servers), onlyStun: onlyStun);
}

/// A connection that notes the kind of each candidate it finds, also those
/// found after whoever set it up stopped listening (the connection open).
class _RecordingPeer implements RtcPeer {
  _RecordingPeer(this._rtc, this._inner, {required this.onlyStun}) {
    _inner.onLocalCandidate.listen((c) {
      if (_type(c) case final type?) _rtc.types.add(type);
      if (!_candidates.isClosed) _candidates.add(c);
    }, onDone: _candidates.close);
  }

  final _RecordingRtc _rtc;
  final RtcPeer _inner;
  final bool onlyStun;

  /// Kept until someone listens, as the connection's own are.
  final StreamController<RtcCandidate> _candidates = StreamController();

  static String? _type(RtcCandidate c) => RegExp(r' typ (\w+)').firstMatch(c.candidate)?.group(1);

  @override
  Stream<RtcCandidate> get onLocalCandidate => _candidates.stream;

  @override
  void addRemoteCandidate(RtcCandidate candidate) {
    final type = _type(candidate) ?? '?';
    _rtc.received[type] = (_rtc.received[type] ?? 0) + 1;
    if (onlyStun && type == 'host') return;
    _inner.addRemoteCandidate(candidate);
  }

  @override
  Future<String> offer() => _inner.offer();
  @override
  Future<String> answer(String offerSdp) => _inner.answer(offerSdp);
  @override
  Future<void> acceptAnswer(String answerSdp) => _inner.acceptAnswer(answerSdp);
  @override
  Stream<RtcState> get onState => _inner.onState;
  @override
  RtcState get state => _inner.state;
  @override
  Future<RtcChannel> get channel => _inner.channel;
  @override
  Future<void> close() => _inner.close();
}

/// The players' names in [room], by seat.
List<String> _names(RoomState room) => [
  for (final s in room.seats)
    if (!s.isEmpty) s.name,
];

/// [message] as JSON, with a `pad` field that makes it [length] characters.
String _padded(Map<String, Object?> message, int length) {
  final bare = jsonEncode({...message, 'pad': ''});
  return jsonEncode({...message, 'pad': 'x' * (length - bare.length)});
}

void _log(String line) => debugPrint('PEER: $line');
