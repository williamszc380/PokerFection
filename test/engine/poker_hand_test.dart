import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/engine/actions.dart';
import 'package:pokerfection/src/engine/cards.dart';
import 'package:pokerfection/src/engine/events.dart';
import 'package:pokerfection/src/engine/poker_hand.dart';
import 'package:pokerfection/src/engine/positions.dart';
import 'package:pokerfection/src/engine/rules.dart';

const fold = PlayerAction.fold();
const check = PlayerAction.check();
const call = PlayerAction.call();
PlayerAction raise(int to) => PlayerAction.raiseTo(to);

/// Blinds are 50/100. Seat 0 has the button unless [button] says otherwise.
PokerHand hand({
  required List<int> stacks,
  int button = 0,
  int ante = 0,
  Map<int, String> cards = const {},
  String board = '',
}) =>
    PokerHand(
      stacks: stacks,
      buttonSeat: button,
      smallBlind: 50,
      bigBlind: 100,
      ante: ante,
      random: Random(1),
      holeCards: cards.map((seat, c) => MapEntry(seat, parseCards(c))),
      board: parseCards(board),
    );

void main() {
  test('six players: blinds, positions and first to act', () {
    final h = hand(stacks: List.filled(6, 10000));
    expect(h.streetBetOf(1), 50);
    expect(h.streetBetOf(2), 100);
    expect(h.toAct, 3);
    expect(h.positionOf(3), Position.utg);
    expect(h.positionOf(0), Position.btn);
    final legal = h.legalActions();
    expect(legal.toCall, 100);
    expect(legal.minRaiseTo, 200);
    expect(legal.maxRaiseTo, 10000);
    expect(legal.pot, 150);
  });

  test('heads-up: button posts the small blind, acts first preflop and last after', () {
    final h = hand(stacks: [10000, 10000]);
    expect(h.streetBetOf(0), 50);
    expect(h.streetBetOf(1), 100);
    expect(h.toAct, 0);
    h.act(call);
    expect(h.toAct, 1, reason: 'big blind gets the option');
    expect(h.legalActions().canRaise, isTrue);
    h.act(check);
    expect(h.street, Street.flop);
    expect(h.board, hasLength(3));
    expect(h.toAct, 1);
  });

  test('everyone folds to the big blind', () {
    final h = hand(stacks: List.filled(4, 10000));
    h
      ..act(fold) // UTG
      ..act(fold) // BTN
      ..act(fold); // SB
    expect(h.isOver, isTrue);
    expect(h.stackOf(1), 9950);
    expect(h.stackOf(2), 10050);
    expect(h.log.whereType<UncalledBetReturned>().single.amount, 50);
    expect(h.log.whereType<HandsRevealed>(), isEmpty);
  });

  test('the minimum raise follows the last full raise', () {
    final h = hand(stacks: List.filled(6, 10000));
    h.act(raise(300));
    expect(h.legalActions().minRaiseTo, 500);
    h.act(raise(900));
    expect(h.legalActions().minRaiseTo, 1500);
    expect(() => h.act(raise(1400)), throwsArgumentError);
    expect(() => h.act(check), throwsArgumentError);
  });

  test('a short all-in raise does not reopen the betting', () {
    final h = hand(stacks: [10000, 400, 10000]);
    h.act(raise(300)); // BTN opens
    h.act(raise(400)); // SB all-in: only 100 more, less than a full raise
    expect(h.isAllIn(1), isTrue);
    expect(h.toAct, 2);
    expect(h.legalActions().canRaise, isTrue, reason: 'big blind has not acted yet');
    h.act(call);
    expect(h.toAct, 0);
    final legal = h.legalActions();
    expect(legal.toCall, 100);
    expect(legal.canRaise, isFalse);
  });

  test('a full raise reopens the betting for someone who already acted', () {
    final h = hand(stacks: List.filled(3, 10000));
    h.act(raise(300)); // BTN
    h.act(raise(900)); // SB
    h.act(fold); // BB
    expect(h.toAct, 0);
    expect(h.legalActions().canRaise, isTrue);
  });

  test('side pots are paid to the right players', () {
    final h = hand(
      stacks: [5000, 1000, 3000],
      cards: {0: '7c 2d', 1: 'As Ah', 2: 'Ks Kh'},
      board: '3c 8d 9h Js 4s',
    );
    h.act(raise(5000)); // BTN all-in
    h.act(call); // SB all-in for 1000
    h.act(call); // BB all-in for 3000
    expect(h.isOver, isTrue);
    expect(h.stackOf(1), 3000, reason: 'aces win the main pot');
    expect(h.stackOf(2), 4000, reason: 'kings win the side pot');
    expect(h.stackOf(0), 2000, reason: 'the uncalled 2000 comes back');
    final awards = h.log.whereType<PotAwarded>().toList();
    expect(awards.map((a) => a.amount), [4000, 3000], reason: 'side pot is paid first');
    expect(awards.first.winningHand!.describe(), 'Pair of Kings');
  });

  test('split pot: the odd chip goes to the first winner left of the button', () {
    final h = hand(
      stacks: List.filled(3, 10000),
      ante: 5,
      cards: {0: '2c 3d', 1: '4c 5d', 2: '6c 7d'},
      board: 'As Ks Qs Js Ts',
    );
    h
      ..act(fold) // BTN
      ..act(call) // SB completes
      ..act(check); // BB
    for (var street = 0; street < 3; street++) {
      h
        ..act(check)
        ..act(check);
    }
    expect(h.isOver, isTrue);
    final award = h.log.whereType<PotAwarded>().single;
    expect(award.amount, 215);
    expect(award.shares, {1: 108, 2: 107});
    expect(award.winningHand!.describe(), 'Royal Flush');
  });

  test('an uncalled bet goes back to the bettor', () {
    final h = hand(stacks: [10000, 10000]);
    h
      ..act(call)
      ..act(check)
      ..act(raise(200)) // BB bets the flop
      ..act(fold);
    expect(h.isOver, isTrue);
    expect(h.stackOf(0), 9900);
    expect(h.stackOf(1), 10100);
    expect(h.log.whereType<UncalledBetReturned>().single.amount, 200);
  });

  test('all-in before the flop: cards go face up, then the board is dealt', () {
    final h = hand(stacks: [2000, 2000]);
    h
      ..act(raise(2000))
      ..act(call);
    expect(h.isOver, isTrue);
    final types = h.log.map((e) => e.runtimeType).toList();
    expect(types.indexOf(HandsRevealed), lessThan(types.indexOf(BoardDealt)));
    expect(h.log.whereType<BoardDealt>().map((e) => e.street),
        [Street.flop, Street.turn, Street.river]);
    expect(h.stackOf(0) + h.stackOf(1), 4000);
  });

  test('a big blind all-in for less still sets the price', () {
    final h = hand(stacks: [10000, 60]);
    expect(h.isAllIn(1), isTrue);
    expect(h.toAct, 0);
    final legal = h.legalActions();
    expect(legal.toCall, 50);
    expect(legal.canRaise, isFalse, reason: 'nobody left who could call a raise');
    h.act(call);
    expect(h.isOver, isTrue);
    expect(h.log.whereType<UncalledBetReturned>().single.amount, 40);
    expect(h.stackOf(0) + h.stackOf(1), 10060);
  });

  test('home-game rule: any raise of at least 1 bb', () {
    final standard = hand(stacks: List.filled(3, 10000));
    standard.act(raise(1000));
    expect(standard.legalActions().minRaiseTo, 1900, reason: 'standard: raise by at least 9 bb more');

    final home = PokerHand(
      stacks: List.filled(3, 10000),
      buttonSeat: 0,
      smallBlind: 50,
      bigBlind: 100,
      raiseRule: RaiseRule.bigBlind,
      random: Random(1),
    );
    home.act(raise(1000));
    expect(home.legalActions().minRaiseTo, 1100);
    home.act(raise(1100)); // SB raises by just 1 bb
    expect(home.toAct, 2);
    expect(home.legalActions().minRaiseTo, 1200);
  });

  test('rejects the same card dealt twice', () {
    expect(() => hand(stacks: [1000, 1000], cards: {0: 'As Kd', 1: 'As Qd'}),
        throwsArgumentError);
  });

  test('positions for every table size', () {
    expect(positionsBySeat(6, 0), {
      3: Position.utg,
      4: Position.hj,
      5: Position.co,
      0: Position.btn,
      1: Position.sb,
      2: Position.bb,
    });
    expect(positionsBySeat(2, 0), {0: Position.btn, 1: Position.bb});
    for (var n = 2; n <= 8; n++) {
      expect(positionsForTable(n), hasLength(n));
      for (final position in positionsForTable(n)) {
        for (var seat = 0; seat < n; seat++) {
          final button = buttonSeatFor(n, seat, position);
          expect(positionsBySeat(n, button)[seat], position);
        }
      }
    }
  });
}
