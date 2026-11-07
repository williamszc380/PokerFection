import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/blackjack/app/blackjack_analysis_codec.dart';
import 'package:pokerfection/src/games/blackjack/app/blackjack_record.dart';
import 'package:pokerfection/src/games/blackjack/blackjack.dart';
import 'package:pokerfection/src/games/blackjack/online/blackjack_runner.dart';
import 'package:pokerfection/src/games/blackjack/online/blackjack_view_codec.dart';
import 'package:pokerfection/src/online/games/game_runner.dart';
import 'package:pokerfection/src/online/games/online_games.dart';
import 'package:pokerfection/src/online/protocol.dart';

import 'runner_harness.dart';

/// Blackjack in a room, through the runner harness: 1 to 7 seats each
/// playing its own hands against the dealer (played inside the runner),
/// one deal per round, the shoe shuffled from the room's secure Random and
/// kept from round to round, every player's cards face up, the hole card
/// hidden from every seat (and from the spectators unless the host's
/// switch shows them the bots' cards, the dealer's included).

const _game = BlackjackOnline();

Map<String, Object?> _rules(BlackjackRules rules) => rules.toJson();

/// A quick player for the harness: usually the Medium bot's play, worked
/// out from the engine's view rebuilt from the seat's own view (so every
/// pick also checks that path), sometimes any legal decision.
String _pick(Map<String, Object?> seatView, int seat, Random random) {
  expect(seatView['you'], seat);
  final legal = wireLegalMoves(seatView);
  expect(legal, isNotEmpty, reason: 'seat $seat picks at its turn');
  if (random.nextInt(4) == 0) return legal[random.nextInt(legal.length)];
  final view = blackjackViewFromWire(seatView);
  final move = handMove(view.turn!.hand, BlackjackBot(BotLevel.medium).chooseAction(view));
  expect(legal, contains(move));
  return move;
}

/// The cards nobody may see in [r]'s round, as JSON strings: those still
/// in the shoe and (with [hole]) the face-down hole card, less any card of
/// the same face and suit that shows on the table (a shoe of several decks
/// has copies). With one deck every card is the only one of its kind.
Set<String> _undealt(GameRunner r, {bool hole = true}) {
  final runner = r as BlackjackRunner;
  final round = runner.round, shoe = runner.shoe;
  if (round == null || shoe == null) return const {};
  final shown = {
    for (final seat in round.seats)
      for (final hand in seat.hands)
        for (final c in hand.cards) '$c',
    for (final c in round.dealerVisible) '$c',
  };
  return {
    for (final c in [...shoe.cardsToCome, if (hole && round.holeCardHidden) round.dealerCards[1]])
      if (!shown.contains('$c')) '"$c"',
  };
}

RunnerHarness _harness({int seed = 1, bool spectatorsSeeHole = false}) => RunnerHarness(
  _game,
  pick: _pick,
  secrets: (view, seat) => const {},
  seatViewFrom: blackjackSeatViewFrom,
  undealt: (r) => _undealt(r, hole: !spectatorsSeeHole),
  seed: seed,
);

/// Opens a room at [rules] with Ben seated, [bots] bots and Cy watching,
/// and starts the game.
Future<(HarnessDevice host, HarnessDevice ben, HarnessDevice cy)> _table(
  RunnerHarness h, {
  BlackjackRules rules = const BlackjackRules(),
  int seats = 7,
  int bots = 2,
  bool seeBots = false,
}) async {
  final host = await h.open();
  await h.choose(rules: _rules(rules), seats: seats);
  if (seeBots) host.send(const HostSettings(seeBots: true));
  final ben = await h.join('Ben', seated: true);
  final cy = await h.join('Cy');
  await h.addBots(bots, level: 'medium');
  await h.start();
  return (host, ben, cy);
}

/// A round dealt from a shoe of [decks] decks shuffled by [seed], to
/// [seats] seats (for the codec's own checks).
BlackjackRound _deal(BlackjackRules rules, int seed, int seats) =>
    BlackjackRound.deal(rules, Shoe.forRules(rules, random: Random(seed)), List.filled(seats, 1));

void main() {
  test('Blackjack is registered for rooms: 1 to 7 seats picked by the host, dealt to the seats taken, '
      'three bot levels, the solo game\'s default table', () {
    expect(onlineGames['blackjack'], same(blackjackOnline));
    final seats = _game.seatsFor(_game.defaultRules);
    expect((seats.min, seats.max, seats.hostPicks, seats.everySeat), (1, 7, true, false));
    expect(seats.needed(7), 1, reason: 'one player is enough');
    expect(_game.botLevels, ['easy', 'medium', 'hard']);
    expect(BlackjackRules.fromJson(_game.defaultRules), const BlackjackRules());
    expect((_game.betweenRounds, _game.maxBetweenRounds), (const Duration(seconds: 3), const Duration(seconds: 10)));
  });

  test('the rules are read strictly and written in full: unknown keys, wrong types and numbers out of range '
      'are refused', () {
    final single = BlackjackRules.preset(BlackjackPreset.singleDeck);
    expect(_game.readRules(single.toJson()), single.toJson());
    expect(_game.readRules({'decks': 2}), const BlackjackRules(decks: 2).toJson(), reason: 'the rest default');
    for (final bad in <Object?>[
      null,
      'standard',
      [1],
      {'decks': 9},
      {'decks': '6'},
      {'payout': 'twoToOne'},
      {'penetration': 1.0},
      {'seed': 5},
      {'decks': 6, 'shoeOrder': 'As Kd'},
    ]) {
      expect(() => _game.readRules(bad), throwsFormatException, reason: '$bad');
    }
    expect(() => OnlineSetup.fromJson({'seats': 8, 'rules': _game.defaultRules}, _game), throwsFormatException);
    expect(OnlineSetup.fromJson({'seats': 1, 'rules': _game.defaultRules}, _game).seats, 1);
  });

  test('200 rounds with a seated guest, two bots and a spectator: no card still to come or face-down hole card '
      'in any view, each seat\'s view rebuilt from the spectators\', legal auto-moves, small messages', () async {
    for (final seed in [1, 2]) {
      final h = _harness(seed: seed);
      final (host, ben, cy) = await _table(h);
      await h.playRounds(200);
      h.expectClean();
      expect(h.largest, lessThan(4096));
      expect(ben.movesSent, greaterThan(100));
      expect(host.botMovesSent, greaterThan(100));
      // Spectators never saw the hole card while it was face down.
      expect(cy.states.where((s) => s.view.containsKey('hole')), isEmpty);
      // Every view is the solo game's notation and a whole round's.
      final runner = h.runners.last;
      expect(runner.moves.map((m) => m.$2), everyElement(matches(RegExp(r'^[0-3]:[HSDPRINK]$'))));
    }
  });

  test('a single deck (every card the only one of its kind): no view holds a card still in the shoe or the '
      'hole card, so a leak of either would show', () async {
    final h = _harness(seed: 3);
    await _table(h, rules: BlackjackRules.preset(BlackjackPreset.singleDeck), bots: 3);
    await h.playRounds(150);
    h.expectClean();
  });

  test('with the host\'s switch on, the spectators see the face-down hole card (it counts as the bots\'); no seat '
      'ever does, the bots\' included', () async {
    final h = _harness(seed: 4, spectatorsSeeHole: true);
    final (host, ben, cy) = await _table(h, rules: BlackjackRules.preset(BlackjackPreset.singleDeck), seeBots: true);
    await h.playRounds(60);
    h.expectClean();
    final seen = cy.states.where((s) => s.view['hole'] != null).toList();
    expect(seen, isNotEmpty, reason: 'the spectators saw the hole card');
    for (final s in seen) {
      expect(s.view['holeDown'], isTrue, reason: 'only while it lies face down');
    }
    for (final d in [host, ben]) {
      expect(d.states.where((s) => s.you != null && s.view.containsKey('hole')), isEmpty);
    }
    expect(host.botRequests.where((r) => r.view.containsKey('hole')), isEmpty);
    // And straight from the runner, at every turn of a few rounds: a seat's
    // view never holds the hole card's code (one deck: it is unique).
    final runner = BlackjackRunner(BlackjackPreset.singleDeck.rules, Random(9));
    for (var round = 1; round <= 30; round++) {
      runner.startRound(round, [false, true, true]);
      while (!runner.roundOver) {
        final r = runner.round!;
        if (r.holeCardHidden) {
          final hole = '"${r.dealerCards[1]}"';
          for (var s = 0; s < 3; s++) {
            expect(jsonEncode(runner.seatView(s)), isNot(contains(hole)));
          }
          expect(jsonEncode(runner.spectatorView(seesBots: false)), isNot(contains(hole)));
          expect(runner.spectatorView(seesBots: true)['hole'], hole.replaceAll('"', ''));
        }
        final seat = runner.seatToAct!;
        runner.act(seat, runner.autoMove(seat));
      }
    }
  });

  test('junk sent at a seated guest\'s turns is refused, one move at a time, and never closes the room', () async {
    final h = _harness(seed: 5);
    final (_, ben, _) = await _table(h, bots: 1);
    await h.expectJunkRefused(ben);
    // Ben may be to act again at once (after a Hit): the harness turns his
    // own play back on, but only plays the turns that come after.
    ben.actNow();
    for (final junk in ['0:X', '0:h', '4:H', ' 0:H', '0:H ', '00:H', 'H', '0:', ':H', '9:H', '0:HH']) {
      expect(h.runners.last.inner.check(0, junk), isNotNull, reason: junk);
    }
    await h.playRounds(5);
    h.expectClean();
  });

  test('every shoe is shuffled from the room\'s Random (no seed anywhere): the first deal draws from it, and so '
      'does every new shoe', () async {
    expectDealsFromRandom(_game, OnlineSetup(rules: _game.defaultRules, seats: 3), [false, true, true]);
    // A continuous shuffler shuffles before every round.
    final h = _harness(seed: 6);
    await _table(h, rules: const BlackjackRules(continuousShuffle: true), bots: 1);
    await h.playRounds(5);
    expect(h.runners.last.dealDraws.take(5), everyElement(greaterThan(0)));
    h.expectClean();
    // A shoe lasts until its cut card: a round mid-shoe draws nothing new.
    final shoe = BlackjackRunner(const BlackjackRules(), Random(1))..startRound(1, [false]);
    expect(shoe.shoe!.shuffles, 1);
  });

  test('the longest move goes through the game envelope unchanged', () {
    expectMoveRoundTrips(_game, '3:R', seat: 6);
    expectMoveRoundTrips(_game, '0:K');
  });

  test('each seat bets 1: a round\'s scores are its nets, a blackjack at 3:2 pays 1.5, insurance counted', () {
    final runner = BlackjackRunner(const BlackjackRules(), Random(2))..startRound(1, [false, true]);
    while (!runner.roundOver) {
      final seat = runner.seatToAct!;
      runner.act(seat, runner.autoMove(seat));
    }
    expect(runner.roundScores, [for (var s = 0; s < 2; s++) runner.round!.result(s).net]);
    expect(runner.roundResult(), {'nets': runner.roundScores});
    // The next deal: the player's ace and king against the dealer's 7 and 9.
    runner.shoe!.stack([Card.parse('Ah'), Card.parse('7c'), Card.parse('Kd'), Card.parse('9h')]);
    runner.startRound(2, [false]);
    expect(runner.roundOver, isTrue, reason: 'a blackjack ends the round at the deal');
    expect(runner.roundScores, [1.5]);
    expect(runner.seatView(0)['nets'], [1.5]);
    expect(runner.seatView(0)['seats'], [
      {
        'hands': [
          {
            'c': ['Ah', 'Kd'],
            'done': true,
            'out': 'blackjack',
            'net': 1.5,
          },
        ],
      },
    ]);
  });

  test('a bot or a seat away plays Stand, or turns an offer down: always legal', () {
    final runner = BlackjackRunner(const BlackjackRules(surrender: Surrender.early), Random(3));
    var offers = 0;
    for (var round = 1; round <= 300; round++) {
      runner.startRound(round, [true, true, false]);
      while (!runner.roundOver) {
        final seat = runner.seatToAct!;
        final move = runner.autoMove(seat);
        expect(runner.check(seat, move), isNull);
        if (runner.round!.phase != RoundPhase.playing) {
          offers++;
          expect(move, anyOf(endsWith(':N'), endsWith(':K')));
        } else {
          expect(move, endsWith(':S'));
        }
        runner.act(seat, move);
      }
    }
    expect(offers, greaterThan(10), reason: 'insurance and early surrender came up');
  });

  test('the engine\'s view rebuilt from a seat\'s view decides as the round\'s own: the same decisions, cards seen, '
      'count, and the coach\'s exact values', () {
    const coach = BlackjackCoach();
    final chart = BasicStrategyChart.forRules(const BlackjackRules());
    var checked = 0;
    final moves = Random(7);
    for (final rules in [const BlackjackRules(), BlackjackPreset.singleDeck.rules, BlackjackPreset.european.rules]) {
      final runner = BlackjackRunner(rules, Random(rules.decks));
      for (var round = 1; round <= 25; round++) {
        runner.startRound(round, [false, false, true]);
        while (!runner.roundOver) {
          final seat = runner.seatToAct!;
          final own = runner.round!.viewFor(seat);
          final rebuilt = blackjackViewFromWire(runner.seatView(seat));
          expect(rebuilt.legalActions, own.legalActions);
          expect((rebuilt.phase, rebuilt.turn, rebuilt.seat), (own.phase, own.turn, own.seat));
          expect(rebuilt.dealerVisible, own.dealerVisible);
          expect((rebuilt.holeCardHidden, rebuilt.dealerPeeked), (own.holeCardHidden, own.dealerPeeked));
          expect(rebuilt.unseenSeen, own.unseenSeen);
          expect(rebuilt.unseenFresh, own.unseenFresh);
          expect((rebuilt.count.running, rebuilt.count.unseenCards), (own.count.running, own.count.unseenCards));
          expect(rebuilt.seenMayRunOut, own.seenMayRunOut);
          expect(rebuilt.offersEvenMoney, own.offersEvenMoney);
          if (rules == const BlackjackRules() && checked < 60) {
            expect(
              analysisToJson(coach.analyze(rebuilt, chart: chart)),
              analysisToJson(coach.analyze(own, chart: chart)),
            );
          }
          checked++;
          final legal = wireLegalMoves(runner.seatView(seat));
          runner.act(seat, legal[moves.nextInt(legal.length)]);
        }
      }
    }
    expect(checked, greaterThan(100));
  });

  test('a seat\'s view rebuilt from the spectators\' is the seat\'s own; a view that isn\'t one is refused', () {
    final runner = BlackjackRunner(const BlackjackRules(), Random(4))..startRound(1, [false, true, false]);
    for (var s = 0; s < 3; s++) {
      expect(
        jsonEncode(blackjackSeatViewFrom(runner.spectatorView(seesBots: true), s)),
        jsonEncode(runner.seatView(s)),
      );
    }
    expect(blackjackSeatViewFrom(runner.spectatorView(seesBots: false), 3), isNull);
    expect(blackjackSeatViewFrom(const {}, 0), isNull);
    for (final junk in <Map<String, Object?>>[
      {},
      {...runner.seatView(0), 'you': 7},
      {...runner.seatView(0), 'phase': 'dancing'},
      {
        ...runner.seatView(0),
        'dealer': ['Zz'],
      },
      {...runner.seatView(0), 'seen': <int>[]},
      {...runner.seatView(0), 'rules': 'standard'},
    ]) {
      expect(() => blackjackViewFromWire(junk), throwsFormatException, reason: '$junk');
    }
  });

  test('the largest view (seven seats, every one split to four hands and drawing to 21) stays under 4 KB', () {
    const rules = BlackjackRules(decks: 8, resplitAces: true, maxHands: 4);
    // Eights and twos only: every pair splits, every hand draws many cards.
    final shoe = Shoe.forRules(rules, random: Random(5));
    shoe.stack([for (var i = 0; i < 32; i++) Card.of(8, i % 4), for (var i = 0; i < 32; i++) Card.of(2, i % 4)]);
    final round = BlackjackRound.deal(rules, shoe, List.filled(7, 1));
    while (!round.isOver) {
      final legal = round.legalActions();
      round.apply(
        legal.contains(BlackjackAction.split)
            ? BlackjackAction.split
            : legal.contains(BlackjackAction.hit)
            ? BlackjackAction.hit
            : legal.first,
      );
    }
    expect(round.seats.first.hands, hasLength(4));
    final size = utf8.encode(jsonEncode({...blackjackPublicView(round, roundNo: 99), 'you': 6})).length;
    expect(size, lessThan(4096), reason: '$size bytes');
  });

  test('a round dealt to seven seats from a fresh shoe: each seat\'s two cards and the dealer\'s upcard show, '
      'the rest of the shoe and the hole card don\'t', () {
    final round = _deal(const BlackjackRules(decks: 1), 7, 7);
    final view = blackjackPublicView(round, roundNo: 1);
    expect((view['seats']! as List).length, 7);
    expect(view['dealer'], ['${round.dealerUpcard}']);
    expect(view['holeDown'], isTrue);
    expect(view['left'], 52 - 16);
    expect(view['seen'], List.filled(10, 0), reason: 'nothing seen before the first round');
    final text = jsonEncode(view);
    for (final c in [...round.shoe.cardsToCome, round.dealerCards[1]]) {
      expect(text, isNot(contains('"$c"')));
    }
  });
}

extension on BlackjackPreset {
  BlackjackRules get rules => BlackjackRules.preset(this);
}
