import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/games/doudizhu/online/doudizhu_runner.dart';
import 'package:pokerfection/src/games/doudizhu/online/doudizhu_view_codec.dart';
import 'package:pokerfection/src/online/games/game_envelope.dart';
import 'package:pokerfection/src/online/games/game_runner.dart';
import 'package:pokerfection/src/online/games/online_games.dart';
import 'package:pokerfection/src/online/protocol.dart';

import 'runner_harness.dart';

/// Fight the Landlord in a room, through the runner harness: three seats,
/// the auction and the kitty, deals thrown in and dealt again inside the
/// round, every view checked for cards its reader may not see.

final _game = DoudizhuOnline();

/// The lowest-suited cards of [hand] that make [play].
List<int> _cardsFor(List<int> hand, Play play) {
  final left = [...hand]..sort();
  return [for (final r in play.ranks) left.removeAt(left.indexWhere((id) => rankOfId(id) == r))];
}

/// A legal move for [seat] seeing [view]: the view is replayed on the
/// device's side and the engine lists the moves. Picked at random, but in
/// play more often the move with the most cards: the harness answers the
/// bots' turns at the same instant, and the host's device may send only so
/// many messages at once (60), so the deals are kept to a lifelike length.
String _pick(Map<String, Object?> view, int seat, Random random) {
  final game = DdzWireView.read(view).replay()!;
  final legal = game.legalMoves();
  int cards(DdzMove m) => m is DdzPlay ? m.play.size : 0;
  final move = game.phase == DdzPhase.playing && random.nextDouble() < 0.6
      ? legal.reduce((a, b) => cards(b) > cards(a) ? b : a)
      : legal[random.nextInt(legal.length)];
  return ddzOnlineMoveText(seat, move, move is DdzPlay ? _cardsFor(game.hands[seat], move.play) : const []);
}

/// What only a seat sees while the deal goes on (nothing once it is over):
/// its hand's cards, but for the ones everyone has seen (the face-up card,
/// and the kitty's in the landlord's hand when the rules show the kitty to
/// everyone); and its hand as a whole (`"you":` is in a seat's own view
/// alone), so a bot whose last cards are all shown kitty cards still counts
/// as hidden from spectators without the switch.
Set<String> _secrets(Map<String, Object?> view, int seat) {
  if (view['left'] != null) return const {};
  final shownKitty = (view['rules']! as Map)['kittyShown'] == true ? view['kitty'] as List? ?? const [] : const [];
  return {
    '"you":$seat',
    for (final code in view['hand']! as List)
      if (!shownKitty.contains(code) && code != view['faceUp']) '"$code"',
  };
}

/// The kitty until the landlord takes it.
Set<String> _undealt(GameRunner runner) {
  final game = (runner as DoudizhuRunner).game;
  return game.phase == DdzPhase.bidding ? {for (final id in game.kitty) '"${ddzCardCode(id)}"'} : const {};
}

RunnerHarness _harness({int seed = 1}) =>
    RunnerHarness(_game, pick: _pick, secrets: _secrets, seatViewFrom: ddzSeatViewFrom, undealt: _undealt, seed: seed);

/// A deal played to its end by random legal moves, every view checked on
/// the way by [each].
DdzGame _playOut(Random random, {DdzRules rules = DdzRules.standard, void Function(DdzGame game)? each}) {
  final game = DdzGame.deal(rules: rules, random: random);
  while (game.phase == DdzPhase.bidding || game.phase == DdzPhase.playing) {
    each?.call(game);
    final legal = game.legalMoves();
    game.act(legal[random.nextInt(legal.length)]);
  }
  each?.call(game);
  return game;
}

void main() {
  test('the room offers it: three seats, Easy to Hard bots, the solo rules read strictly', () {
    expect(onlineGames['doudizhu'], isA<DoudizhuOnline>());
    expect(_game.seatsFor(_game.defaultRules).allows(3), isTrue);
    expect(_game.seatsFor(_game.defaultRules).allows(2), isFalse);
    expect(_game.botLevels, ['easy', 'medium', 'hard']);
    expect(_game.readRules(_game.defaultRules), DdzRules.standard.toJson());
    expect(
      _game.readRules({'bidding': 'callRob', 'maxMultiplier': 16}),
      DdzRules.standard.copyWith(bidding: BiddingStyle.callRob, maxMultiplier: 16).toJson(),
    );
    for (final bad in [
      null,
      'standard',
      {'bidding': 'auction'},
      {'kittyShown': 'yes'},
      {'maxMultiplier': 7},
      {'deck': 'four'},
    ]) {
      expect(() => _game.readRules(bad), throwsFormatException, reason: '$bad');
    }
  });

  test('a seat\'s view replays to the real game: its hand, whose turn, the play to beat and its legal moves; the '
      'other hands are only stand-ins of the right size', () {
    final random = Random(4);
    for (var deal = 0; deal < 40; deal++) {
      final rules = deal.isEven ? DdzRules.standard : DdzRules.app.copyWith(kittyShown: false);
      _playOut(
        random,
        rules: rules,
        each: (game) {
          for (var seat = 0; seat < 3; seat++) {
            final view = jsonDecode(jsonEncode(ddzSeatView(game, seat, redeals: 0))) as Map<String, Object?>;
            final replayed = DdzWireView.read(view).replay();
            expect(replayed, isNotNull, reason: jsonEncode(view));
            expect(replayed!.hands[seat], game.hands[seat]);
            expect([for (final h in replayed.hands) h.length], [for (final h in game.hands) h.length]);
            expect(
              (replayed.phase, replayed.landlord, replayed.stake, replayed.multiplier, replayed.current),
              (game.phase, game.landlord, game.stake, game.multiplier, game.current),
            );
            if (game.phase == DdzPhase.finished) {
              expect(replayed.hands, game.hands, reason: 'every card is shown at the end');
              expect(replayed.result.toString(), game.result.toString());
            } else if (game.toAct == seat) {
              expect(replayed.toAct, seat);
              expect(replayed.legalMoves(), game.legalMoves());
              expect(
                jsonEncode(replayed.viewFor(seat).toJson()),
                jsonEncode(game.viewFor(seat).toJson()),
                reason: 'the bot and the coach see exactly the engine\'s own view',
              );
            }
          }
        },
      );
    }
  });

  test('the kitty: nobody sees it in the auction; once taken, everyone when the rules show it, else only the '
      'landlord (and spectators who see the landlord\'s hand)', () {
    final random = Random(9);
    for (final shown in [true, false]) {
      final rules = DdzRules.standard.copyWith(kittyShown: shown);
      var checked = 0;
      _playOut(
        random,
        rules: rules,
        each: (game) {
          final kitty = [for (final id in game.kitty) '"${ddzCardCode(id)}"'];
          final lord = game.landlord;
          for (var seat = 0; seat < 3; seat++) {
            final view = ddzSeatView(game, seat, redeals: 0);
            if (lord == null) {
              final text = jsonEncode(view);
              expect(kitty.where(text.contains), isEmpty, reason: 'seat $seat in the auction');
            } else if (game.phase == DdzPhase.playing) {
              expect(view.containsKey('kitty'), shown || seat == lord, reason: 'seat $seat, shown: $shown');
              checked++;
            }
          }
          if (lord != null && game.phase == DdzPhase.playing) {
            final others = {0, 1, 2}..remove(lord);
            expect(ddzSpectatorView(game, shown: others, redeals: 0).containsKey('kitty'), shown);
            expect(ddzSpectatorView(game, shown: {lord}, redeals: 0).containsKey('kitty'), isTrue);
          }
        },
      );
      expect(checked, greaterThan(0));
    }
  });

  test('the table turns so the player sits at the bottom: seats move back, the order of play stays', () {
    final game = _playOut(Random(2));
    final view = DdzWireView.read(ddzSeatView(game, 2, redeals: 0));
    final turned = view.rotated(2);
    expect(turned.you, 0);
    expect(turned.lord, (game.landlord! - 2) % 3);
    final replayed = turned.replay()!;
    expect(replayed.result!.winner, (game.result!.winner - 2) % 3);
    expect(replayed.hands[0], game.hands[2]);
  });

  test('moves: the record\'s notation, read strictly; junk is a reason, never an exception', () {
    final runner = _game.newRunner(OnlineSetup.defaultFor(_game), Random(3)) as DoudizhuRunner;
    runner.startRound(1, [false, false, false]);
    final seat = runner.seatToAct!;
    expect(runner.check(seat, '$seat:b1'), isNull);
    expect(runner.check(seat, '$seat:b0'), isNull);
    expect(runner.check((seat + 1) % 3, '${(seat + 1) % 3}:b1'), isNotNull, reason: 'not their turn');
    expect(runner.check(seat, '${(seat + 1) % 3}:b1'), isNotNull, reason: "another seat's move");
    expect(runner.check(seat, '$seat:p'), isNotNull, reason: 'no passing in the auction');
    expect(runner.check(seat, '$seat:b4'), isNotNull);
    for (final junk in ['', ':', '0:', '9:b1', '$seat:x', '$seat:xsolo:3|999', '$seat:b1|1', 'x' * 256, '{"a":1}']) {
      expect(runner.check(seat, junk), isNotNull, reason: junk);
    }
    // Bid 3: the bidder is the landlord and leads.
    runner.act(seat, '$seat:b3');
    expect(runner.seatToAct, seat);
    final hand = runner.game.hands[seat];
    final low = hand.first;
    final code = Rank.chars[rankOfId(low)];
    expect(runner.check(seat, '$seat:xsolo:$code|$low'), isNull);
    expect(runner.check(seat, '$seat:xsolo:$code'), isNull, reason: 'the cards may be left to the room');
    final other = hand.firstWhere((id) => rankOfId(id) != rankOfId(low));
    expect(runner.check(seat, '$seat:xsolo:$code|$other'), isNotNull, reason: 'the cards must be the play');
    final notHeld = runner.game.hands[(seat + 1) % 3].firstWhere(
      (id) => rankOfId(id) == rankOfId(low),
      orElse: () => -1,
    );
    if (notHeld >= 0) expect(runner.check(seat, '$seat:xsolo:$code|$notHeld'), isNotNull);
    expect(runner.check(seat, '$seat:xpair:$code$code|$low,$low'), isNotNull, reason: 'one card twice');
    expect(() => runner.act(seat, '$seat:p'), throwsArgumentError);
    // The auto move is legal and cheap: the lowest single card on a lead.
    expect(runner.autoMove(seat), '$seat:xsolo:$code|$low');
    expect(runner.check(seat, runner.autoMove(seat)), isNull);
  });

  test('everyone passes: the cards are dealt again inside the round from the same Random, with a new face-up card '
      'whose holder opens; the move says so', () {
    final random = RecordingRandom(Random(5));
    final runner = _game.newRunner(OnlineSetup.defaultFor(_game), random) as DoudizhuRunner;
    runner.startRound(2, [false, true, false]);
    final first = runner.game;
    expect(first.hands[first.firstBidder], contains(first.faceUp));
    final before = (random.draws, runner.game.kitty);
    for (var i = 0; i < 2; i++) {
      final s = runner.seatToAct!;
      runner.act(s, '$s:b0');
      expect(runner.redealt, isFalse);
    }
    final s = runner.seatToAct!;
    runner.act(s, '$s:b0');
    expect(runner.redealt, isTrue);
    expect(runner.redeals, 1);
    expect(random.draws, greaterThan(before.$1), reason: 'the new deal is shuffled from the room\'s Random');
    final again = runner.game;
    expect(again, isNot(same(first)));
    expect(again.faceUp, isNotNull);
    expect(again.hands[again.firstBidder], contains(again.faceUp), reason: 'the new face-up card decides');
    expect(runner.seatView(0)['faceUp'], ddzCardCode(again.faceUp!), reason: 'the deal thrown in is gone');
    expect(runner.game.history, isEmpty);
    expect(runner.roundOver, isFalse);
    expect(runner.seatView(0)['redeals'], 1);
    final shown = runner.playbackMs('$s:b0');
    // The next move is an ordinary one, shown for less time.
    final t = runner.seatToAct!;
    runner.act(t, '$t:b1');
    expect(runner.redealt, isFalse);
    expect(runner.playbackMs('$t:b1'), lessThan(shown));
  });

  test("the auto move declines in the auction, but for the auction's last chance under the redeal rule when nobody "
      'plays the seat: there it takes the landlord at the lowest stake, so a table of absent players never redeals '
      'forever', () {
    for (final bidding in BiddingStyle.values) {
      for (final allPass in AllPassRule.values) {
        final rules = DdzRules(bidding: bidding, allPass: allPass);
        final runner = _game.newRunner(OnlineSetup(rules: rules.toJson(), seats: 3), Random(4)) as DoudizhuRunner;
        runner.startRound(1, [false, false, false]);
        final decline = bidding == BiddingStyle.points ? 'b0' : 'c0';
        for (var i = 0; i < 2; i++) {
          final s = runner.seatToAct!;
          expect(runner.game.isLastChance, isFalse);
          expect(runner.autoMove(s, absent: true), '$s:$decline',
              reason: '${rules.toJson()}: someone else may still take it');
          runner.act(s, runner.autoMove(s, absent: true));
        }
        final last = runner.seatToAct!;
        expect(runner.game.isLastChance, isTrue);
        final take = bidding == BiddingStyle.points ? 'b1' : 'c1';
        expect(
          runner.autoMove(last, absent: true),
          allPass == AllPassRule.redeal ? '$last:$take' : '$last:$decline',
          reason: '${rules.toJson()}: under the other rule declining ends the auction anyway',
        );
        // The others may still outbid a bid of 1; away, they decline.
        while (runner.game.phase == DdzPhase.bidding) {
          final s = runner.seatToAct!;
          runner.act(s, runner.autoMove(s, absent: true));
        }
        expect(runner.redeals, 0);
        expect(runner.game.phase, DdzPhase.playing);
        expect(runner.game.landlord, allPass == AllPassRule.redeal ? last : runner.game.firstBidder);
        expect(runner.game.stake, 1);
      }
    }
  });

  test("a player at the table whose clock runs out at the auction's last chance declines, and the deal is thrown in "
      '(Pagat); only once a deal was thrown in with nobody acting does the next one take the landlord at stake 1', () {
    for (final bidding in BiddingStyle.values) {
      final rules = DdzRules(bidding: bidding);
      final decline = bidding == BiddingStyle.points ? 'b0' : 'c0';
      final take = bidding == BiddingStyle.points ? 'b1' : 'c1';
      final runner = _game.newRunner(OnlineSetup(rules: rules.toJson(), seats: 3), Random(9)) as DoudizhuRunner;
      runner.startRound(1, [false, false, false]);

      // Deal 1: the first seat declines by hand, the others time out.
      var s = runner.seatToAct!;
      runner.act(s, '$s:$decline');
      s = runner.seatToAct!;
      runner.act(s, runner.autoMove(s));
      s = runner.seatToAct!;
      expect(runner.game.isLastChance, isTrue);
      expect(runner.autoMove(s), '$s:$decline', reason: '$bidding: someone at the table who did nothing');
      runner.act(s, runner.autoMove(s));
      expect(runner.redealt, isTrue);
      expect(runner.redeals, 1);

      // Deal 2: someone acted in deal 1, so a timeout still declines. Now
      // all three time out.
      for (var i = 0; i < 3; i++) {
        s = runner.seatToAct!;
        expect(runner.autoMove(s), '$s:$decline', reason: '$bidding, deal 2, turn $i');
        runner.act(s, runner.autoMove(s));
      }
      expect(runner.redeals, 2);

      // Deal 3: the deal before was thrown in with nobody acting: the
      // table is idle, and its last chance takes.
      for (var i = 0; i < 2; i++) {
        s = runner.seatToAct!;
        runner.act(s, runner.autoMove(s));
      }
      s = runner.seatToAct!;
      expect(runner.autoMove(s), '$s:$take', reason: '$bidding: an idle table');
      while (runner.game.phase == DdzPhase.bidding) {
        final t = runner.seatToAct!;
        runner.act(t, runner.autoMove(t));
      }
      expect(runner.redeals, 2);
      expect(runner.game.landlord, s);
      expect(runner.game.stake, 1);

      // A new round starts afresh: a timeout declines again.
      runner.startRound(2, [false, false, false]);
      for (var i = 0; i < 2; i++) {
        s = runner.seatToAct!;
        runner.act(s, runner.autoMove(s));
      }
      s = runner.seatToAct!;
      expect(runner.autoMove(s), '$s:$decline', reason: '$bidding: round 2');
    }
  });

  test("every round's deal opens with the who-bids-first step: the room waits that long before the first clock", () {
    final runner = _game.newRunner(OnlineSetup(rules: _game.defaultRules, seats: 3), Random(2));
    runner.startRound(1, [false, true, true]);
    expect(runner.openingMs, DoudizhuRunner.redealMs, reason: 'the who-bids-first step at Normal, and a little more');
  });

  test('whole games with a person, a spectator and two bots the host\'s device plays: every move legal, the deal '
      'thrown in dealt again, scores kept on the seats, nothing hidden leaks, every message small', () async {
    final h = _harness();
    final host = await h.open();
    await h.choose();
    final ben = await h.join('Ben', seated: true);
    final cy = await h.join('Cy');
    await h.addBots(2);
    await h.start();
    await h.playRounds(30);
    h.expectClean();
    expect(host.botMovesSent, greaterThan(60));
    expect(ben.movesSent, greaterThan(30));
    // Random bids throw deals in now and then: they are dealt again, and said to be.
    expect(cy.states.where((s) => s.last?.cause == EnvelopeCause.redeal), isNotEmpty);
    // The landlord's points are the two peasants' together: the scores add up to nothing.
    final scores = [for (final s in cy.room.seats) s.score ?? 0];
    expect(scores.fold<num>(0, (a, b) => a + b), 0);
    expect(scores.any((s) => s != 0), isTrue);
    expect(ben.botRequests, isEmpty);
    expect(cy.botRequests, isEmpty);
    expect(h.largest, lessThan(4096));
  });

  test('every mix of people and bots, the host\'s switch on and off, both auctions, the kitty hidden or shown: no '
      'leaks, no undealt kitty, the acting seat\'s view rebuilt from the spectators\' view', () async {
    for (final seed in [1, 2, 3, 4]) {
      final h = _harness(seed: seed);
      final host = await h.open();
      final rules = DdzRules.standard.copyWith(
        bidding: seed > 2 ? BiddingStyle.callRob : BiddingStyle.points,
        kittyShown: seed.isOdd,
      );
      await h.choose(rules: rules.toJson());
      if (seed.isEven) host.send(const HostSettings(seeBots: true));
      await h.join('Ben', seated: true);
      if (seed > 2) await h.join('Cy', seated: true);
      await h.addBots(seed > 2 ? 1 : 2);
      await h.join('Dee');
      await h.start();
      await h.playRounds(25);
      h.expectClean();
    }
  });

  test("an absent player's turns are played by the room's auto move when time runs out (legal every time)", () async {
    final h = _harness(seed: 7);
    await h.open();
    // 15 s a move: the harness lets the clock jump to the next timer, and
    // the room's 25 s silence check must not come first.
    await h.choose(turnLimit: 15);
    final ben = await h.join('Ben', seated: true);
    ben.autoPlay = false;
    await h.addBots(2);
    await h.start();
    await h.playRounds(2);
    h.expectClean();
    final seat = ben.state!.seats.indexOf(ben.seat!);
    expect(h.runners.single.moves.where((m) => m.$1 == seat), isNotEmpty);
    expect(ben.movesSent, 0);
  });

  test("junk at a seat's turns is refused, one move at a time, and never closes the room", () async {
    final h = _harness(seed: 3);
    await h.open();
    // A time limit: Ben's next turn may open while the harness has him wait
    // (the bots pass straight back to him); the clock then plays it.
    await h.choose(turnLimit: 15);
    final ben = await h.join('Ben', seated: true);
    await h.join('Cy');
    await h.addBots(2);
    await h.start();
    await h.expectJunkRefused(ben);
    await h.playRounds(1);
    h.expectClean();
  });

  test('every deal draws from the room\'s Random, never from a seed; the longest move goes through the envelope', () {
    expectDealsFromRandom(_game, OnlineSetup.defaultFor(_game), [false, true, false]);
    // The longest play: an airplane of five trios with five wings, all twenty cards named.
    final longest = ddzOnlineMoveText(
      2,
      DdzPlay(Play.decode('airplaneSolos:33344455566677789TJQ')),
      idsForRanks(parseRanks('33344455566677789TJQ')),
    );
    expect(longest.length, lessThan(maxMoveLength));
    expectMoveRoundTrips(_game, longest, seat: 2);
  });

  group('the face-up card online (Pagat: whoever draws it bids first; everyone sees it until it is played)', () {
    test("every seat's view and the spectators' carry it, the bots' seats included, with the switch off and on", () {
      final runner = _game.newRunner(OnlineSetup.defaultFor(_game), Random(8)) as DoudizhuRunner;
      final openers = <int>{};
      for (var round = 1; round <= 12; round++) {
        runner.startRound(round, [false, true, true]);
        final code = ddzCardCode(runner.game.faceUp!);
        for (var seat = 0; seat < 3; seat++) {
          expect(runner.seatView(seat)['faceUp'], code, reason: 'round $round, seat $seat');
        }
        for (final seesBots in [false, true]) {
          final view = runner.spectatorView(seesBots: seesBots);
          expect(view['faceUp'], code, reason: 'spectators, seesBots: $seesBots');
          expect(view['first'], runner.game.firstBidder);
        }
        expect(runner.seatToAct, runner.game.firstBidder, reason: 'its holder opens the auction');
        openers.add(runner.game.firstBidder);
      }
      expect(openers, {0, 1, 2}, reason: 'no rotation: the card decides');
    });

    test("a view replays with the face-up card in the first bidder's hand, stand-ins around it: the replay, its "
        "views and their card counters see the same visible cards as the game, turned or not", () {
      final random = Random(14);
      var checked = 0;
      for (var deal = 0; deal < 30; deal++) {
        final rules = deal.isEven ? DdzRules.standard : DdzRules.app.copyWith(kittyShown: deal % 4 == 1);
        _playOut(
          random,
          rules: rules,
          each: (game) {
            if (game.phase == DdzPhase.finished) return;
            final views = [
              for (var seat = 0; seat < 3; seat++) ddzSeatView(game, seat, redeals: 0),
              for (final shown in const [<int>{}, {0}, {1, 2}, {0, 1, 2}])
                ddzSpectatorView(game, shown: shown, redeals: 0),
            ];
            for (final json in views) {
              final wire = DdzWireView.read(jsonDecode(jsonEncode(json)) as Map<String, Object?>);
              final replayed = wire.replay();
              expect(replayed, isNotNull, reason: jsonEncode(json));
              expect(replayed!.faceUp, game.faceUp);
              for (var s = 0; s < 3; s++) {
                expect(replayed.visibleIn(s), game.visibleIn(s), reason: '${jsonEncode(json)} seat $s');
              }
              final you = wire.you;
              if (you != null) {
                final mine = replayed.viewFor(you), real = game.viewFor(you);
                for (var s = 0; s < 3; s++) {
                  expect(mine.visibleIn(s), real.visibleIn(s));
                }
                expect(mine.cardCount.knownInHand, real.cardCount.knownInHand);
                expect(mine.cardCount.unknown, real.cardCount.unknown);
              }
              for (final base in [1, 2]) {
                final turned = wire.rotated(base).replay()!;
                for (var s = 0; s < 3; s++) {
                  expect(turned.visibleIn((s - base) % 3), game.visibleIn(s), reason: 'turned by $base');
                }
              }
              checked++;
            }
          },
        );
      }
      expect(checked, greaterThan(2000));
    });

    test('a view without the key (an older device) still reads, with no face-up card; junk there is refused', () {
      final game = _playOut(Random(3), each: (_) {});
      final view = ddzSeatView(game, 0, redeals: 0)..remove('faceUp');
      expect(DdzWireView.read(view).faceUp, isNull);
      expect(() => DdzWireView.read({...ddzSeatView(game, 0, redeals: 0), 'faceUp': 'Zz'}), throwsFormatException);
      expect(_game.gv, 2, reason: 'the views changed: version 2');
    });
  });

  group('the step that opens every deal (who bids first) online', () {
    test('it needs nothing the views did not carry already: every seat and the spectators, the table turned or not, '
        'deal the same order from them, the face-up card at the same moment, each own hand in the same order', () {
      final runner = _game.newRunner(OnlineSetup.defaultFor(_game), Random(21)) as DoudizhuRunner;
      for (var round = 1; round <= 10; round++) {
        runner.startRound(round, [false, round.isEven, true]);
        final real = DdzDealOrder.of(runner.game);
        final views = <(Map<String, Object?>, int)>[
          for (var seat = 0; seat < 3; seat++) (runner.seatView(seat), seat),
          for (final seesBots in [false, true]) (runner.spectatorView(seesBots: seesBots), 0),
        ];
        for (final (json, base) in views) {
          // The keys the views had before the step: nothing added for it.
          expect(json.keys.toSet().difference(const {'rules', 'first', 'faceUp', 'redeals', 'you', 'hand', 'hands', 'moves'}),
              isEmpty, reason: 'round $round: ${json.keys}');
          final wire = DdzWireView.read(jsonDecode(jsonEncode(json)) as Map<String, Object?>);
          // As the device draws it: its own seat (or the first) at the bottom.
          final shown = wire.rotated(base).replay()!;
          final order = DdzDealOrder.of(shown, firstSeat: (3 - base) % 3);
          expect(order.faceUpAt, real.faceUpAt, reason: 'round $round, base $base');
          expect([for (final c in order.cards) (c.seat + base) % 3], [for (final c in real.cards) c.seat]);
          for (final hand in wire.hands.keys) {
            expect(order.dealtTo((hand - base) % 3, 51), real.dealtTo(hand, 51),
                reason: 'round $round: hand $hand, seen from $base, is dealt in the same order');
          }
          expect(order.cards[order.faceUpAt!].id, runner.game.faceUp);
        }
      }
    });

    test('a deal thrown in is shown long enough for its step (about two seconds at Normal) before the next clock',
        () {
      final runner = _game.newRunner(OnlineSetup.defaultFor(_game), Random(5)) as DoudizhuRunner;
      runner.startRound(1, [false, false, false]);
      for (var i = 0; i < 3; i++) {
        final s = runner.seatToAct!;
        runner.act(s, '$s:b0');
      }
      expect(runner.redealt, isTrue);
      expect(runner.playbackMs('0:b0'), DoudizhuRunner.redealMs);
      expect(DoudizhuRunner.redealMs, inInclusiveRange(2000, 4000), reason: "within the room's longest watch (4 s)");
    });
  });
}
