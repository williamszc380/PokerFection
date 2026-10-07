import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/engine/actions.dart';
import 'package:pokerfection/src/engine/cards.dart';
import 'package:pokerfection/src/engine/events.dart';
import 'package:pokerfection/src/engine/poker_hand.dart';
import 'package:pokerfection/src/engine/rules.dart';
import 'package:pokerfection/src/online/event_codec.dart';
import 'package:pokerfection/src/online/mirror.dart';
import 'package:pokerfection/src/online/redact.dart';
import 'package:pokerfection/src/online/seat_map.dart';

import '../helpers.dart';

/// One hand as the server plays it: its batches of events (the deal, then
/// one per action) and who was to act, with what choices, before each action.
class _Played {
  _Played(this.hand);
  final PokerHand hand;
  final List<List<GameEvent>> batches = [];
  final List<(int, LegalActions)> turns = [];
}

_Played _play(Random rng, int n) {
  // Deep, short and tiny stacks: all-ins from the blinds (or the ante) too.
  int stack() => switch (rng.nextInt(10)) {
        0 => 1 + rng.nextInt(150),
        1 || 2 => 200 + rng.nextInt(1500),
        _ => 2000 + rng.nextInt(30000),
      };
  final played = _Played(PokerHand(
    stacks: [for (var i = 0; i < n; i++) stack()],
    buttonSeat: rng.nextInt(n),
    smallBlind: 50,
    bigBlind: 100,
    ante: const [0, 0, 10, 100][rng.nextInt(4)],
    handNumber: 1 + rng.nextInt(50),
    raiseRule: RaiseRule.values[rng.nextInt(RaiseRule.values.length)],
    random: rng,
  ));
  final hand = played.hand;
  played.batches.add(hand.drainEvents());
  while (!hand.isOver) {
    final legal = hand.legalActions();
    played.turns.add((hand.toAct!, legal));
    hand.act(randomAction(legal, rng));
    played.batches.add(hand.drainEvents());
  }
  return played;
}

/// What a device receives: redacted for its seat, sent as JSON text, and
/// turned to its own seats.
List<GameEvent> _receive(List<GameEvent> batch, int viewer, SeatMap seats) {
  final wire = jsonEncode(encodeEvents(redactBatch(batch, viewer)));
  return seats.eventsToLocal(decodeEvents(jsonDecode(wire)));
}

void _expectSameLegal(LegalActions mine, LegalActions server) {
  expect(
    [mine.toCall, mine.canRaise, mine.minRaiseTo, mine.maxRaiseTo, mine.currentBet, mine.streetBet, mine.stack, mine.pot],
    [server.toCall, server.canRaise, server.minRaiseTo, server.maxRaiseTo, server.currentBet, server.streetBet, server.stack,
      server.pot],
  );
}

void main() {
  test('every device mirrors the server\'s hand from what it is sent', () {
    final rng = Random(11);
    for (var n = 2; n <= 8; n++) {
      for (var i = 0; i < 300; i++) {
        final played = _play(rng, n);
        final server = played.hand;
        // Every player's view, and the host's (seat 0 here) knowing the bots' cards.
        final bots = [for (var s = 1; s < n; s++) if (rng.nextBool()) s];
        for (var viewer = 0; viewer <= n; viewer++) {
          final host = viewer == n;
          final me = host ? 0 : viewer;
          final seats = SeatMap(n, me);
          final botCards = host ? seats.mapToLocal(botCardsFor(server, bots)) : const <int, List<PlayingCard>>{};
          final mirror = RemoteDeal.fromBatch(_receive(played.batches[0], me, seats), extraKnown: botCards).build(
            smallBlind: 50,
            bigBlind: 100,
            ante: server.ante,
            raiseRule: server.raiseRule,
          );
          for (final local in [0, ...botCards.keys]) {
            expect(mirror.holeCards(local), server.holeCards(seats.toServer(local)));
          }
          for (var b = 1; b < played.batches.length; b++) {
            final (toAct, legal) = played.turns[b - 1];
            expect(mirror.toAct, seats.toLocal(toAct));
            _expectSameLegal(mirror.legalActions(), legal);
            applyBatch(mirror, _receive(played.batches[b], me, seats));
          }
          expect(mirror.isOver, isTrue);
          expect([for (var s = 0; s < n; s++) mirror.stackOf(s)],
              seats.listToLocal([for (var s = 0; s < n; s++) server.stackOf(s)]));
        }
      }
    }
  });

  test('a mirror refuses moves that don\'t fit', () {
    final rng = Random(3);
    late _Played played;
    do {
      played = _play(rng, 3);
    } while (played.batches.length < 2);
    final seats = SeatMap(3, 1);
    final mirror = RemoteDeal.fromBatch(_receive(played.batches[0], 1, seats))
        .build(smallBlind: 50, bigBlind: 100, ante: played.hand.ante, raiseRule: played.hand.raiseRule);
    final toAct = mirror.toAct!;
    ActionTaken raise(int seat, int to) => ActionTaken(
        seat: seat, kind: ActionKind.raise, chipsAdded: 0, streetBet: to, isAllIn: false, street: Street.preflop);
    // Out of turn, and more chips than the player has.
    expect(() => applyBatch(mirror, [raise((toAct + 1) % 3, 300)]), throwsA(isA<MirrorMismatch>()));
    expect(() => applyBatch(mirror, [raise(toAct, mirror.legalActions().maxRaiseTo + 1)]),
        throwsA(isA<MirrorMismatch>()));
  });
}
