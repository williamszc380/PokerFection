import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/doudizhu/cards.dart';
import 'package:pokerfection/src/games/doudizhu/game.dart';
import 'package:pokerfection/src/games/doudizhu/plays.dart';
import 'package:pokerfection/src/games/doudizhu/rules.dart';
import 'package:pokerfection/src/games/doudizhu/view.dart';

DdzMove play(String text) => DdzPlay(classifyPlay(parseRanks(text)).single);
const pass = DdzPass();
DdzMove bid(int n) => DdzBid(n);

/// A deal whose hands are easy to follow: seat 0 has the low cards.
DdzGame dealt({DdzRules rules = DdzRules.standard, int firstBidder = 0}) =>
    DdzGame.deal(rules: rules, random: Random(42), firstBidder: firstBidder);

void main() {
  group('the deal', () {
    test('17 cards each and a kitty of 3, all 54 different', () {
      final g = dealt();
      expect([for (var s = 0; s < 3; s++) g.handSize(s)], [17, 17, 17]);
      expect(g.kitty, hasLength(3));
      expect({...g.hands.expand((h) => h), ...g.kitty}, hasLength(54));
      expect(g.phase, DdzPhase.bidding);
      expect(g.toAct, 0);
    });

    test('the same seed deals the same cards', () {
      expect(dealt().hands, dealt().hands);
      expect(DdzGame.deal(random: Random(1), firstBidder: 0).hands, isNot(dealt().hands));
    });
  });

  group('points auction (Pagat)', () {
    test('a bid of 3 ends the auction at once; the landlord takes the kitty and leads', () {
      final g = dealt();
      final kitty = [...g.kitty];
      g.act(bid(3));
      expect(g.phase, DdzPhase.playing);
      expect(g.landlord, 0);
      expect(g.stake, 3);
      expect(g.handSize(0), 20);
      expect(g.hands[0], containsAll(kitty));
      expect(g.toAct, 0);
      expect(g.isLead, isTrue);
    });

    test('each bid must be higher; two passes in a row after a bid end it', () {
      final g = dealt();
      g.act(bid(1));
      expect(g.legalMoves(), [bid(0), bid(2), bid(3)]);
      expect(() => g.act(bid(1)), throwsStateError);
      g.act(bid(2));
      g.act(bid(0));
      expect(g.phase, DdzPhase.bidding, reason: 'one pass is not enough');
      g.act(bid(0));
      expect((g.landlord, g.stake), (1, 2));
    });

    test('a player who passed may bid later in the same auction', () {
      final g = dealt();
      g.act(bid(0));
      g.act(bid(1));
      g.act(bid(0));
      g.act(bid(2));
      g.act(bid(0));
      g.act(bid(0));
      expect((g.landlord, g.stake), (0, 2));
    });

    test('two opening passes still let the third player bid', () {
      final g = dealt(firstBidder: 1);
      g.act(bid(0));
      g.act(bid(0));
      expect(g.toAct, 0);
      g.act(bid(1));
      g.act(bid(0));
      g.act(bid(0));
      expect((g.landlord, g.stake), (0, 1));
    });

    test('everyone passing throws the hand in (redeal)', () {
      final g = dealt();
      for (var i = 0; i < 3; i++) {
        g.act(bid(0));
      }
      expect(g.phase, DdzPhase.thrownIn);
      expect(g.legalMoves(), isEmpty);
    });

    test('with the house rule, everyone passing makes the first bidder landlord at 1', () {
      final g = dealt(rules: const DdzRules(allPass: AllPassRule.firstBidderLandlord), firstBidder: 2);
      for (var i = 0; i < 3; i++) {
        g.act(bid(0));
      }
      expect((g.phase, g.landlord, g.stake), (DdzPhase.playing, 2, 1));
    });
  });

  group('call and rob auction', () {
    const rules = DdzRules(bidding: BiddingStyle.callRob);

    test('a call nobody robs: the caller is landlord at stake 1', () {
      final g = dealt(rules: rules);
      g.act(const DdzCall(true));
      expect(g.isRobbing, isTrue);
      g.act(const DdzRob(false));
      g.act(const DdzRob(false));
      expect((g.landlord, g.stake), (0, 1));
    });

    test('each rob doubles; the caller may rob back last', () {
      final g = dealt(rules: rules);
      g.act(const DdzCall(true));
      g.act(const DdzRob(true));
      g.act(const DdzRob(true));
      expect(g.toAct, 0, reason: 'the caller has the last word');
      g.act(const DdzRob(true));
      expect((g.landlord, g.stake), (0, 8));
    });

    test('the last robber wins when the caller declines to rob back', () {
      final g = dealt(rules: rules);
      g.act(const DdzCall(true));
      g.act(const DdzRob(false));
      g.act(const DdzRob(true));
      g.act(const DdzRob(false));
      expect((g.landlord, g.stake), (2, 2));
    });

    test('players who declined to call may not rob', () {
      final g = dealt(rules: rules);
      g.act(const DdzCall(false));
      g.act(const DdzCall(true));
      expect(g.toAct, 2);
      g.act(const DdzRob(false));
      expect((g.phase, g.landlord), (DdzPhase.playing, 1));
    });

    test('nobody calling is a redeal, in the app preset too; the house rule makes the first bidder landlord', () {
      for (final redeals in [rules, DdzRules.app]) {
        final a = dealt(rules: redeals);
        for (var i = 0; i < 3; i++) {
          a.act(const DdzCall(false));
        }
        expect(a.phase, DdzPhase.thrownIn, reason: 'the cited source: "如果都\'不叫\'，则重新发牌"');
      }
      final b = dealt(rules: const DdzRules(bidding: BiddingStyle.callRob, allPass: AllPassRule.firstBidderLandlord));
      for (var i = 0; i < 3; i++) {
        b.act(const DdzCall(false));
      }
      expect((b.landlord, b.stake), (0, 1));
    });
  });

  group('play', () {
    test('the landlord leads; others beat or pass; two passes give the lead back', () {
      final g = DdzGame.fromRanks(hands: ['345', '678', '9TJ'], kitty: 'QKA', landlord: 0);
      expect(g.legalMoves(), isNot(contains(pass)), reason: 'a leader may not pass');
      g.act(play('3'));
      expect(g.toAct, 1);
      expect(g.legalMoves().first, pass);
      g.act(play('6'));
      g.act(pass);
      g.act(pass);
      expect(g.toAct, 1);
      expect(g.isLead, isTrue, reason: 'two passes: the last player to play leads');
    });

    test('a pass does not stop a player from playing later in the trick', () {
      final g = DdzGame.fromRanks(hands: ['3A2', '45', '67'], kitty: '', landlord: 0);
      g.act(play('3'));
      g.act(pass);
      g.act(play('6'));
      g.act(play('A'));
      expect(g.toAct, 1);
      expect(g.legalMoves(), [pass]);
    });

    test('playing cards you do not hold, or a lower play, is refused', () {
      final g = DdzGame.fromRanks(hands: ['345', '678', '9TJ'], kitty: '', landlord: 0);
      expect(() => g.act(play('2')), throwsStateError);
      g.act(play('5'));
      expect(() => g.act(play('3')), throwsStateError);
      expect(g.isLegal(play('7')), isTrue);
    });

    test('the app can name the exact cards (suits) of a play', () {
      final g = DdzGame.fromCards(hands: [[0, 1, 2], [4, 5, 6], [8, 9, 10]], kitty: [12, 13, 14], landlord: 0);
      g.act(play('3'), cardIds: [2]);
      expect(g.hands[0], isNot(contains(2)));
      expect(g.history.last.cardIds, [2]);
      expect(() => g.act(play('4'), cardIds: [8]), throwsStateError, reason: 'not their card');
    });

    test('naming the same card twice is refused, and nothing is played', () {
      // A save or a peer's message could name one card for both 3s of a
      // pair: the hand would lose one card while the history showed two.
      final g = DdzGame.fromRanks(hands: ['33A9', '45', '56'], kitty: '', landlord: 0);
      final three = g.hands[0].firstWhere((id) => rankOfId(id) == 0);
      expect(() => g.act(play('33'), cardIds: [three, three]), throwsStateError);
      expect(g.handSize(0), 4);
      expect(g.history, isEmpty);
      expect(g.toAct, 0);
    });

    test('naming more or fewer cards than the play has is refused', () {
      final g = DdzGame.fromRanks(hands: ['33A9', '45', '56'], kitty: '', landlord: 0);
      final threes = g.hands[0].where((id) => rankOfId(id) == 0).toList();
      expect(() => g.act(play('3'), cardIds: threes), throwsStateError);
      expect(() => g.act(play('33'), cardIds: [threes.first]), throwsStateError);
      expect(g.handSize(0), 4);
    });

    test('a play whose rank does not match its cards is not legal', () {
      // Play == compares only the kind and the cards, so a 9 built in code
      // claiming the big joker's rank must be caught by its rank.
      final g = DdzGame.fromRanks(hands: ['33A', '49', '56'], kitty: '', landlord: 0);
      g.act(play('A'));
      final fake = DdzPlay(Play(PlayType.solo, Rank.bigJoker, 1, [parseRanks('9').single]));
      expect(g.isLegal(fake), isFalse);
      expect(() => g.act(fake), throwsStateError);
      final longFake = DdzPlay(Play(PlayType.solo, 6, 3, [6]));
      expect(g.isLegal(longFake), isFalse, reason: 'a solo has length 1');
      expect(g.isLegal(pass), isTrue);
    });

    test('moves encode and decode for online messages', () {
      for (final m in [bid(0), bid(3), const DdzCall(true), const DdzRob(false), pass, play('33344456')]) {
        expect(DdzMove.decode(m.encode()), m);
      }
    });

    test('a malformed move message throws instead of reading as "no"', () {
      for (final bad in ['c2', 'r7', 'cx', 'b4', 'b9', 'r', 'q1', 'x', 'xsolo:', '']) {
        expect(() => DdzMove.decode(bad), throwsFormatException, reason: bad);
      }
    });
  });

  group('scoring', () {
    test('peasants win as a team when either goes out', () {
      final g = DdzGame.fromRanks(hands: ['3 5', '4', '6 7'], kitty: '', landlord: 0, stake: 2);
      g.act(play('3'));
      g.act(play('4'));
      final r = g.result!;
      expect((r.winner, r.landlordWon), (1, false));
      expect(r.wonBy(2), isTrue);
      expect(r.antiSpring, isTrue, reason: 'the landlord played only once');
      expect(r.multiplier, 2);
      expect(r.points, [-8, 4, 4]);
    });

    test('a spring: the landlord wins before any peasant plays (doubles)', () {
      final g = DdzGame.fromRanks(hands: ['33 A', '4', '5'], kitty: '', landlord: 0, stake: 3);
      g.act(play('33'));
      g.act(pass);
      g.act(pass);
      g.act(play('A'));
      final r = g.result!;
      expect((r.landlordWon, r.spring, r.multiplier), (true, true, 2));
      expect(r.points, [12, -6, -6]);
    });

    test('each bomb or rocket doubles the stake', () {
      final g = DdzGame.fromRanks(hands: ['3 4', '5555 6', 'BR 7'], kitty: '', landlord: 0, stake: 1);
      g.act(play('3'));
      g.act(play('5555'));
      g.act(play('BR'));
      g.act(pass);
      g.act(pass);
      g.act(play('7'));
      final r = g.result!;
      expect(r.bombs, 2);
      expect(r.landlordWon, isFalse);
      expect(r.antiSpring, isTrue);
      expect(r.multiplier, 8);
      expect(r.points, [-16, 8, 8]);
    });

    test('a plain landlord win with no doubling', () {
      final g = DdzGame.fromRanks(hands: ['3 A', '4 9', '5 6'], kitty: '', landlord: 0, stake: 1);
      g.act(play('3'));
      g.act(play('4'));
      g.act(play('5'));
      g.act(play('A'));
      expect(g.phase, DdzPhase.finished, reason: 'the landlord went out with the A');
      final r = g.result!;
      expect((r.landlordWon, r.spring, r.multiplier), (true, false, 1));
      expect(r.points, [2, -1, -1]);
    });

    test('the multiplier cap and the switches that turn doubling off', () {
      expect(ddzMultiplier(DdzRules.standard, 3, true), 16);
      expect(ddzMultiplier(DdzRules.beginner, 3, true), 8);
      expect(ddzMultiplier(const DdzRules(bombsDouble: false), 3, true), 2);
      expect(ddzMultiplier(const DdzRules(springDoubles: false), 1, true), 2);
    });
  });

  group('views', () {
    test('a seat sees its own cards, every hand size and the shown kitty, never other hands', () {
      final g = dealt();
      g.act(bid(3));
      final v = g.viewFor(1);
      expect(v.hand, g.hands[1]);
      expect(v.handSizes, [20, 17, 17]);
      expect(v.kitty, g.kitty);
      expect(v.legalMoves, isEmpty, reason: 'not their turn');
      expect(g.viewFor(0).legalMoves, isNotEmpty);
    });

    test('a hidden kitty is seen by the landlord only', () {
      final g = dealt(rules: const DdzRules(kittyShown: false));
      g.act(bid(3));
      expect(g.viewFor(1).kitty, isNull);
      expect(g.viewFor(0).kitty, g.kitty);
    });

    test('the card counter tracks played cards and the kitty cards still with the landlord', () {
      final g = DdzGame.fromRanks(hands: ['3 4 5', '6 7 8', '9 T J'], kitty: '22B', landlord: 0);
      g.act(play('2'));
      final count = g.viewFor(1).cardCount;
      expect(count.played[Rank.two], 1);
      expect(count.playedBy[0][Rank.two], 1);
      expect(count.knownInHand[0][Rank.two], 1, reason: 'one kitty 2 is still in the landlord\'s hand');
      expect(count.knownInHand[0][Rank.littleJoker], 1);
      expect(count.unseen[Rank.two], 1, reason: 'this set-up deal leaves two 2s out');
      expect(count.unknown[Rank.two], 0, reason: 'the only unseen 2 is the kitty one');
      expect(count.handSizes, [5, 3, 3]);
    });

    test('copies are independent', () {
      final g = dealt();
      final c = g.copy();
      c.act(bid(3));
      expect(g.phase, DdzPhase.bidding);
      expect(g.handSize(0), 17);
    });

    test('a copy of a game in play gives the same views as the game', () {
      // The bots and the coach work on copies: cards already played, and
      // the kitty now in the landlord's hand, must not count as "left out
      // of the deal" on the copy.
      final g = DdzGame.deal(random: Random(3), firstBidder: 0);
      g.act(bid(3));
      g.act(g.legalMoves().first);
      final c = g.copy();
      expect(c.removed, g.removed);
      expect(c.removed, everyElement(0));
      for (var s = 0; s < 3; s++) {
        expect(jsonEncode(c.viewFor(s).toJson()), jsonEncode(g.viewFor(s).toJson()));
        expect(c.viewFor(s).cardCount.unseen, g.viewFor(s).cardCount.unseen);
      }
    });

    test('a copy of a set-up deal keeps the cards it left out', () {
      final g = DdzGame.fromRanks(hands: ['345', '678', '9TJ'], kitty: 'QKA', landlord: 0);
      g.act(play('3'));
      expect(g.copy().removed, g.removed);
      expect(g.removed.reduce((a, b) => a + b), 54 - 12);
    });
  });

  group('saving', () {
    /// Plays the first legal move until [moves] moves are made.
    DdzGame played(DdzGame g, int moves) {
      for (var i = 0; i < moves && g.legalMoves().isNotEmpty; i++) {
        g.act(g.legalMoves()[i % g.legalMoves().length]);
      }
      return g;
    }

    test('a game saved as JSON replays to the same state, mid-deal and finished', () {
      for (final moves in [0, 2, 9, 400]) {
        final g = played(DdzGame.deal(random: Random(moves), rules: DdzRules.app, firstBidder: 0), moves);
        final back = DdzGame.fromJson(jsonDecode(jsonEncode(g.toJson())) as Map<String, Object?>);
        expect(back.hands, g.hands);
        expect(back.phase, g.phase);
        expect(back.toAct, g.toAct);
        expect(back.history.map((a) => a.toString()), g.history.map((a) => a.toString()));
        expect(back.result?.points, g.result?.points);
      }
    });

    test('a deal that skipped the auction saves its landlord and stake', () {
      final g = played(DdzGame.deal(random: Random(3), firstBidder: 0), 0);
      final preset = DdzGame.fromCards(hands: g.hands, kitty: g.kitty, landlord: 2, stake: 3);
      final back = DdzGame.fromJson(preset.toJson());
      expect((back.landlord, back.stake, back.handSize(2)), (2, 3, 20));
    });

    test('a corrupt save throws instead of loading a wrong game', () {
      final json = DdzGame.deal(random: Random(1), firstBidder: 0).toJson()..['moves'] = [['xbomb:2222']];
      expect(() => DdzGame.fromJson(json), throwsA(anything));
    });

    test('a view survives JSON, for sending it to a worker', () {
      final g = played(DdzGame.deal(random: Random(5), firstBidder: 0), 12);
      final v = g.viewFor(g.toAct);
      final back = DdzView.fromJson(jsonDecode(jsonEncode(v.toJson())) as Map<String, Object?>);
      expect(jsonEncode(back.toJson()), jsonEncode(v.toJson()));
      expect(back.legalMoves, v.legalMoves);
      expect(back.cardCount.unseen, v.cardCount.unseen);
    });
  });

  group('the face-up card (Pagat: whoever draws it bids first; everyone sees it until it is played)', () {
    /// Plays random legal moves on [g] (the auction too), calling [each]
    /// before every move and once at the end.
    void playRandomly(DdzGame g, Random random, void Function(DdzGame g) each) {
      while (g.phase == DdzPhase.bidding || g.phase == DdzPhase.playing) {
        each(g);
        final legal = g.legalMoves();
        g.act(legal[random.nextInt(legal.length)]);
      }
      each(g);
    }

    test('every deal turns up one of the 51 cards dealt to the hands, never a kitty card, and its holder bids first',
        () {
      final openers = <int>{};
      for (var seed = 0; seed < 300; seed++) {
        final g = DdzGame.deal(random: Random(seed));
        final up = g.faceUp;
        expect(up, isNotNull);
        expect(g.hands[g.firstBidder], contains(up), reason: 'seed $seed');
        expect(g.kitty, isNot(contains(up)));
        expect(g.toAct, g.firstBidder, reason: 'its holder opens the auction');
        openers.add(g.firstBidder);
      }
      expect(openers, {0, 1, 2}, reason: 'the card decides, so every seat opens some deals');
    });

    test('the card is drawn after the shuffle: a seed deals the same hands as before, chosen opener or not', () {
      for (final seed in [1, 42, 77]) {
        final deck = shuffledDeck(Random(seed));
        final hands = [
          for (var s = 0; s < 3; s++) [...deck.sublist(17 * s, 17 * s + 17)]..sort(),
        ];
        expect(DdzGame.deal(random: Random(seed)).hands, hands);
        expect(DdzGame.deal(random: Random(seed), firstBidder: 2).hands, hands);
        expect(DdzGame.deal(random: Random(seed)).kitty, [...deck.sublist(51)]..sort());
      }
    });

    test("with a first bidder given, the face-up card is one of that seat's cards", () {
      for (var seed = 0; seed < 30; seed++) {
        for (var seat = 0; seat < 3; seat++) {
          final g = DdzGame.deal(random: Random(seed), firstBidder: seat);
          expect(g.firstBidder, seat);
          expect(g.hands[seat], contains(g.faceUp));
        }
      }
    });

    test("it is visible in its holder's hand until played, then no longer, and never in another hand", () {
      // Seeds until seat 0 can answer seat 1's lowest lead with it.
      var checked = 0;
      for (var seed = 0; seed < 60 && checked < 3; seed++) {
        final g = DdzGame.deal(random: Random(seed), firstBidder: 0);
        final up = g.faceUp!;
        expect(g.visibleIn(0), [up]);
        expect(g.visibleIn(1), isEmpty);
        expect(g.visibleIn(2), isEmpty);
        // Seat 1 takes the landlord: the face-up card stays with seat 0.
        g
          ..act(bid(0))
          ..act(bid(3));
        expect(g.visibleIn(0), [up]);
        final low = g.hands[1].first;
        g.act(DdzPlay(Play.decode('solo:${Rank.chars[rankOfId(low)]}')), cardIds: [low]);
        g.act(pass);
        final beat = DdzPlay(Play.decode('solo:${Rank.chars[rankOfId(up)]}'));
        if (!g.isLegal(beat)) continue;
        g.act(beat, cardIds: [up]);
        expect(g.visibleIn(0), isEmpty, reason: 'played: no longer in the hand');
        for (var v = 0; v < 3; v++) {
          expect(g.viewFor(v).visibleIn(0), isEmpty);
        }
        checked++;
      }
      expect(checked, 3);
    });

    test("the shown kitty is visible in the landlord's hand once taken, only when the rules show it", () {
      for (final shown in [true, false]) {
        final g = dealt(rules: DdzRules(kittyShown: shown), firstBidder: 1);
        final kitty = [...g.kitty];
        expect(g.visibleIn(2), isEmpty, reason: 'nobody has taken it yet');
        g
          ..act(bid(0))
          ..act(bid(3));
        expect(g.landlord, 2);
        expect(g.visibleIn(2), shown ? kitty : isEmpty, reason: 'kittyShown: $shown');
        expect(g.visibleIn(1), [g.faceUp], reason: 'the face-up card stays with its holder');
      }
    });

    test('the landlord who holds the face-up card shows it and the kitty, sorted', () {
      final g = dealt();
      g.act(bid(3));
      expect(g.visibleIn(0), [g.faceUp!, ...g.kitty]..sort());
    });

    test('saved: toJson and fromJson keep it, a copy keeps it, and a save without it replays with none', () {
      final g = dealt()..act(bid(2));
      final back = DdzGame.fromJson(jsonDecode(jsonEncode(g.toJson())) as Map<String, Object?>);
      expect(back.faceUp, g.faceUp);
      expect(back.visibleIn(0), g.visibleIn(0));
      expect(g.copy().faceUp, g.faceUp);
      final old = g.toJson()..remove('faceUp');
      final replayed = DdzGame.fromJson(old);
      expect(replayed.faceUp, isNull);
      expect(replayed.hands, g.hands);
      expect([for (var s = 0; s < 3; s++) ...replayed.visibleIn(s)], isEmpty);
    });

    test("a set-up deal refuses a face-up card its first bidder wasn't dealt", () {
      final g = dealt();
      expect(
        () => DdzGame.fromCards(hands: g.hands, kitty: g.kitty, firstBidder: 1, faceUp: g.hands[0].first),
        throwsArgumentError,
      );
      expect(
        () => DdzGame.fromCards(hands: g.hands, kitty: g.kitty, firstBidder: 1, faceUp: g.kitty.first),
        throwsArgumentError,
        reason: 'never a kitty card',
      );
      final ok = DdzGame.fromCards(hands: g.hands, kitty: g.kitty, firstBidder: 1, faceUp: g.hands[1].last);
      expect(ok.visibleIn(1), [g.hands[1].last]);
    });

    test('a deal thrown in (everyone passed) has its own card; the next deal turns up a new one', () {
      final random = Random(6);
      final g = DdzGame.deal(random: random)
        ..act(bid(0))
        ..act(bid(0))
        ..act(bid(0));
      expect(g.phase, DdzPhase.thrownIn);
      final next = DdzGame.deal(random: random);
      expect(next.hands[next.firstBidder], contains(next.faceUp));
      expect(next.hands, isNot(g.hands));
    });

    test("every seat's view says the same as the game, step by step, through JSON", () {
      final random = Random(12);
      var steps = 0;
      for (var deal = 0; deal < 40; deal++) {
        final rules = deal.isEven ? DdzRules.standard : DdzRules.app.copyWith(kittyShown: deal % 4 != 1);
        playRandomly(DdzGame.deal(rules: rules, random: random), random, (g) {
          steps++;
          for (var v = 0; v < 3; v++) {
            final view = DdzView.fromJson(jsonDecode(jsonEncode(g.viewFor(v).toJson())) as Map<String, Object?>);
            expect(view.faceUp, g.faceUp);
            for (var s = 0; s < 3; s++) {
              expect(view.visibleIn(s), g.visibleIn(s), reason: 'deal $deal, seat $v sees seat $s');
            }
          }
        });
      }
      expect(steps, greaterThan(1000));
    });

    test('the card counter knows the visible cards other seats hold, by id, the face-up card in the auction too', () {
      final g = dealt();
      final up = g.faceUp!;
      final count = g.viewFor(1).cardCount;
      final known = List<int>.filled(Rank.count, 0)..[rankOfId(up)] = 1;
      expect(count.knownInHand[0], known, reason: "the face-up card in seat 0's hand");
      expect(count.knownInHand[1], everyElement(0), reason: "never the viewer's own");
      expect(count.unknown[rankOfId(up)], count.unseen[rankOfId(up)] - 1);
      expect(g.viewFor(0).cardCount.knownInHand[0], everyElement(0));
    });

    test('a kitty card stays known after the landlord played another card of its rank', () {
      // The landlord (seat 0) holds 7♣ and takes 7♦ in the kitty; it plays
      // the 7♣. By rank the old count said "no 7 left"; by id the kitty's
      // 7♦ is still in the hand, and everyone saw it go in.
      const sevenClubs = 4 * 4, sevenDiamonds = 4 * 4 + 1;
      final g = DdzGame.fromCards(
        hands: [
          [sevenClubs, 0, 1],
          [8, 9, 10],
          [12, 13, 14],
        ],
        kitty: [sevenDiamonds, 52, 53],
        landlord: 0,
      );
      g.act(DdzPlay(Play.decode('solo:7')), cardIds: [sevenClubs]);
      final count = g.viewFor(1).cardCount;
      expect(count.knownInHand[0][rankOfId(sevenDiamonds)], 1);
      expect(count.knownInHand[0][Rank.littleJoker], 1);
      expect(count.knownInHand[0][Rank.bigJoker], 1);
      expect(g.viewFor(1).visibleIn(0), [sevenDiamonds, 52, 53]);
    });
  });
}
