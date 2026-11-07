import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/engine/actions.dart';
import 'package:pokerfection/src/engine/cards.dart';
import 'package:pokerfection/src/engine/events.dart';
import 'package:pokerfection/src/engine/poker_hand.dart';
import 'package:pokerfection/src/online/connect.dart';
import 'package:pokerfection/src/online/mirror.dart';
import 'package:pokerfection/src/online/online_client.dart';
import 'package:pokerfection/src/online/protocol.dart';

import 'fake_room_host.dart';

/// A full room on a host's device: 15 friends come in through the meeting
/// service (on the fakes of fake_peer.dart), all as spectators; two sit;
/// 30 hands with 4 of the host's bots, and every spectator follows every
/// hand exactly. The 16th friend finds the room full.

/// One app in the room: it follows each hand on a mirror (as the table
/// does), plays its own seat (checking or calling) and, on the host's
/// device, the bots.
class _Follower {
  _Follower(this.name, this.client, {this.bots = false});

  final String name;
  final OnlineClient client;
  final bool bots;
  final List<Object> errors = [];
  PokerHand? mirror;
  int hand = 0;
  int? you;
  List<SeatInfo> lineup = const [];
  Map<int, List<PlayingCard>> botCards = const {};
  int followed = 0;

  /// The hands this app saw every card of a person in (a spectator's view).
  int sawPeople = 0;

  void start() => client.attach(_onMessage);

  void _onMessage(ServerMessage m) {
    try {
      switch (m) {
        case NextHand():
          you = m.you;
          lineup = m.seats;
          if (m.you != null) client.send(Ready(m.hand));
        case BotCards():
          botCards = m.cards;
        case HandDealt():
          hand = m.hand;
          final deal = RemoteDeal.fromBatch(m.batch, extraKnown: bots ? botCards : const {});
          mirror = deal.build(smallBlind: onlineSmallBlind, bigBlind: onlineBigBlind);
          botCards = const {};
          if (you == null) {
            final people = [for (final (i, s) in lineup.indexed) if (s.kind == SeatKind.human) i];
            if (people.every(deal.known.containsKey) && people.isNotEmpty) sawPeople++;
          }
          _ended(m.batch);
          _turn(m.hand, m.turn);
        case HandEvents():
          if (mirror == null) return;
          applyBatch(mirror!, m.batch);
          _ended(m.batch);
          _turn(m.hand, m.turn);
        default:
          break;
      }
    } on Object catch (e) {
      errors.add(e);
    }
  }

  void _ended(List<GameEvent> batch) {
    if (batch.any((e) => e is HandEnded)) followed++;
  }

  void _turn(int hand, Turn? turn) {
    if (turn == null || mirror == null) return;
    if (mirror!.toAct != turn.seat) throw StateError('$name: the mirror is at another turn');
    final legal = mirror!.legalActions();
    final move = legal.canCheck ? const PlayerAction.check() : const PlayerAction.call();
    if (turn.seat == you) {
      client.send(Act(hand: hand, turnId: turn.turnId, action: move));
    } else if (bots && turn.seat < lineup.length && lineup[turn.seat].kind == SeatKind.bot) {
      client.send(BotAct(hand: hand, turnId: turn.turnId, seat: turn.seat, action: move));
    }
  }
}

void main() {
  testWidgets('15 friends join a room hosted here as spectators through the meeting service; two sit; 30 hands '
      'with 4 bots, every spectator following each exactly; a 16th finds the room full', (tester) async {
    final net = FakeInternet();
    Future<void> wait([int steps = 1]) async {
      for (var i = 0; i < steps; i++) {
        net.clock.advance(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> until(bool Function() done, String what, {int limit = 6000}) async {
      for (var i = 0; !done(); i++) {
        expect(i, lessThan(limit), reason: 'never: $what');
        await wait();
      }
    }

    TestRoomHost? started;
    unawaited(TestRoomHost.start(net, code: 'K7M2Q').then((h) => started = h));
    await until(() => started != null, 'the code taken');
    final host = started!;
    final own = OnlineClient(host.ownServer, host: host, connect: host.connector(), clock: net.clock);
    var opened = false;
    unawaited(own.open(const CreateRoom(
      name: 'Ann',
      game: holdemKey,
      settings: RoomSettings(seats: 6, stackBb: 20, resetStacks: true),
      bots: {0: 'tag', 1: 'lag', 2: 'station', 3: 'nit'},
    )).then((_) => opened = true));
    await until(() => opened, 'the room');
    final ann = _Follower('Ann', own, bots: true)..start();

    final friends = <_Follower>[];
    for (var i = 0; i < 15; i++) {
      final client = OnlineClient(
        'peer:K7M2Q',
        clock: net.clock,
        connect: (url) => connectAny(url, peer: net.guest(100 + i)),
      );
      var joined = false;
      unawaited(client.open(JoinRoom(code: 'K7M2Q', name: 'Guest $i')).then((_) => joined = true));
      await until(() => joined, 'Guest $i in');
      friends.add(_Follower('Guest $i', client)..start());
    }
    await until(() => own.room!.members.length == 16, 'everyone in the room');
    expect(own.room!.members.every((m) => m.spectator), isTrue, reason: 'everyone enters as a spectator');

    // The 16th friend: the room is full (bots don't count, people do).
    final late = OnlineClient('peer:K7M2Q', clock: net.clock, connect: (url) => connectAny(url, peer: net.guest(200)));
    Object? refused;
    unawaited(late.open(const JoinRoom(code: 'K7M2Q', name: 'Late')).then((_) {}, onError: (Object e) => refused = e));
    await until(() => refused != null, 'the 16th answered');
    expect((refused! as OnlineFailure).error, JoinError.roomFull);

    // Two sit; the host starts.
    friends[0].client.send(const TakeSeat());
    friends[1].client.send(const TakeSeat());
    await until(() => own.room!.taken == 6, 'two seated');
    own.send(const StartGame());
    await until(() => ann.followed >= 30, '30 hands', limit: 20000);
    await wait(10);

    final watchers = friends.skip(2).toList();
    for (final f in [ann, ...friends]) {
      expect(f.errors, isEmpty, reason: '${f.name} follows every hand exactly');
    }
    for (final f in watchers) {
      expect(f.followed, greaterThanOrEqualTo(29), reason: '${f.name} followed the hands');
      expect(f.sawPeople, greaterThanOrEqualTo(29), reason: "${f.name} saw the people's cards");
      expect(f.client.status, OnlineStatus.open);
    }
    expect(friends[0].followed, greaterThanOrEqualTo(29));

    for (final f in friends) {
      unawaited(f.client.close());
    }
    unawaited(own.close());
    await wait(50);
    await tester.pumpWidget(const SizedBox());
  });
}
