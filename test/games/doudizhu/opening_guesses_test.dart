// A probe of what the step that opens every deal (who bids first) tells
// the guessers. Everyone sees the face-up card land in its holder's seat,
// and nothing else: it is one of the 51 cards dealt to the hands, at
// random, so it says nothing about any other card. So every guess of the
// hidden cards, wherever it is made, must keep two rules:
// - the face-up card is known and fixed to its holder: never the kitty,
//   never the other seat;
// - nothing more follows: the rest is shared out as if the card had never
//   been seen (no seat is thought to hold more or fewer of anything).
//
// It samples many guesses at the moment the step leaves the table (the
// auction's first turn, for every seat, after a deal and after a deal
// thrown in and dealt again), from the solo game's views, a room's seat
// views as a device rebuilds them, the online jobs' views and the
// spectators' views rebuilt for a seat, under both auctions, and checks
// both rules on every guess, in the coach's weighed guesses and in the
// range job's tallies too.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_online_jobs.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_range.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/games/doudizhu/online/doudizhu_runner.dart';
import 'package:pokerfection/src/games/doudizhu/online/doudizhu_view_codec.dart';
import 'package:pokerfection/src/games/doudizhu/policy.dart';
import 'package:pokerfection/src/games/doudizhu/sampler.dart';

/// Checks one guess ([hands]: three seats' rank counts, and in the auction
/// the kitty's) of [viewer]'s hidden cards in [game] against both rules.
void expectBothRules(DdzGame game, int viewer, List<List<int>> hands, String reason) {
  final up = game.faceUp!, holder = game.firstBidder, rank = rankOfId(up);
  final mine = countsOfIds(game.hands[viewer]);
  final copies = deckCountOf(rank);
  // The face-up card stays with its holder.
  if (holder != viewer) {
    expect(hands[holder][rank], greaterThanOrEqualTo(1), reason: '$reason: the holder keeps the face-up card');
    for (var s = 0; s < hands.length; s++) {
      if (s == viewer || s == holder) continue;
      expect(
        hands[s][rank],
        lessThanOrEqualTo(copies - mine[rank] - 1),
        reason: '$reason: ${s == 3 ? 'the kitty' : 'seat $s'} never gets the face-up card',
      );
    }
  }
  // Every card the viewer can't see is placed once (the coach's weighed
  // guesses leave the kitty out: then at most once), and each hand has
  // its size.
  final unseen = game.viewFor(viewer).cardCount.unseen;
  final whole = hands.length == 4 || game.landlord != null;
  for (var r = 0; r < Rank.count; r++) {
    final placed = [
      for (var s = 0; s < hands.length; s++)
        if (s != viewer) hands[s][r],
    ].fold(0, (a, b) => a + b);
    expect(
      placed,
      whole ? unseen[r] : lessThanOrEqualTo(unseen[r]),
      reason: '$reason: every unseen ${Rank.label(r)} placed once',
    );
  }
  for (var s = 0; s < 3; s++) {
    expect(hands[s].fold(0, (a, b) => a + b), game.handSize(s), reason: '$reason: seat $s has its cards');
  }
}

/// The deals as the step leaves them: the auction's first turn, under
/// each auction and both kitty rules.
List<DdzGame> openings(int n) => [
  for (var i = 0; i < n; i++)
    DdzGame.deal(
      rules: DdzRules.standard.copyWith(
        bidding: i.isEven ? BiddingStyle.points : BiddingStyle.callRob,
        kittyShown: i % 3 != 2,
      ),
      random: Random(1000 + i),
    ),
];

void main() {
  test('every guess, for every seat, keeps the face-up card with its holder and moves nothing else', () {
    var guesses = 0;
    // Nothing more follows: over the guesses, the holder holds the card
    // and its share of the rest, the same share as anyone's.
    var holderExtra = 0.0, holderExpected = 0.0;
    for (final (i, game) in openings(60).indexed) {
      for (var viewer = 0; viewer < 3; viewer++) {
        final view = game.viewFor(viewer);
        expect(view.faceUp, game.faceUp, reason: 'everyone saw it');
        expect(view.firstBidder, game.firstBidder);
        final sampler = DdzSampler(view);
        final random = Random(i * 3 + viewer);
        final holder = game.firstBidder, rank = rankOfId(game.faceUp!);
        final left = view.cardCount.unseen[rank] - (holder == viewer ? 0 : 1);
        final pool = view.cardCount.unseen.fold(0, (a, b) => a + b) - (holder == viewer ? 0 : 1);
        for (var k = 0; k < 40; k++) {
          final hands = sampler.deal(random);
          expect(hands, hasLength(4), reason: 'the kitty is guessed in the auction');
          expectBothRules(game, viewer, hands, 'deal $i, viewer $viewer');
          if (holder != viewer) {
            holderExtra += hands[holder][rank] - 1;
            holderExpected += left * 16 / pool;
          }
          guesses++;
        }
      }
    }
    expect(guesses, greaterThanOrEqualTo(7000));
    expect(
      holderExtra,
      closeTo(holderExpected, holderExpected * 0.08 + 10),
      reason: "the holder's other cards are no likelier to match the face-up card than anyone's",
    );
  });

  test("the coach's weighed guesses and the range job keep both rules too", () {
    for (final (i, game) in openings(24).indexed) {
      final viewer = (game.firstBidder + 1 + i % 2) % 3;
      final view = game.viewFor(viewer);
      final pool = DealPool(DdzSampler(view), Random(i), size: 60, policy: const HeuristicPolicy());
      final random = Random(i + 1);
      for (var k = 0; k < 30; k++) {
        expectBothRules(game, viewer, pool.draw(random), 'pool, deal $i');
      }
      final holder = game.firstBidder, rank = rankOfId(game.faceUp!);
      final other = 3 - viewer - holder;
      final mine = countsOfIds(game.hands[viewer])[rank];
      final ofHolder = ddzRange(view, holder, random: Random(i), pool: 400).ranks[rank];
      expect(ofHolder.chance(1), 1.0, reason: 'deal $i: the holder has the face-up rank for sure');
      final ofOther = ddzRange(view, other, random: Random(i), pool: 400).ranks[rank];
      expect(
        ofOther.chance(deckCountOf(rank) - mine),
        0.0,
        reason: 'deal $i: the other seat can never hold every copy left: one is the face-up card',
      );
    }
  });

  test("a room's views keep both rules: rebuilt seat views, the online jobs' views, the spectators' rebuilt for "
      'a seat, after a deal and after one dealt again', () {
    var guesses = 0, redealt = 0;
    for (var g = 0; g < 16; g++) {
      final rules = DdzRules.standard.copyWith(bidding: g.isEven ? BiddingStyle.points : BiddingStyle.callRob);
      final runner = DoudizhuRunner(rules, Random(70 + g))..startRound(1, [g.isOdd, false, true]);
      for (var deal = 0; deal < 2; deal++) {
        if (deal == 1) {
          // Everyone passes: the deal is thrown in and dealt again, a new card face up.
          while (!runner.redealt) {
            final s = runner.seatToAct!;
            runner.act(
              s,
              ddzOnlineMoveText(s, rules.bidding == BiddingStyle.points ? const DdzBid(0) : const DdzCall(false)),
            );
          }
          redealt++;
        }
        final game = runner.game;
        final spectators = runner.spectatorView(seesBots: true);
        for (var seat = 0; seat < 3; seat++) {
          final seatView = runner.seatView(seat);
          expect(ddzSeatViewFrom(spectators, seat), seatView, reason: 'the spectators\' view rebuilt for seat $seat');
          final rebuilt = DdzWireView.read(seatView).replay()!;
          expect(rebuilt.faceUp, game.faceUp);
          expect(rebuilt.firstBidder, game.firstBidder);
          for (var s = 0; s < 3; s++) {
            expect(rebuilt.visibleIn(s), game.visibleIn(s), reason: 'seat $seat sees seat $s\'s face-up card');
          }
          final view = seat == runner.seatToAct ? ddzOnlineJobView(seatView) : rebuilt.viewFor(seat);
          final sampler = DdzSampler(view);
          final random = Random(g * 10 + deal * 3 + seat);
          for (var k = 0; k < 40; k++) {
            expectBothRules(game, seat, sampler.deal(random), 'room $g, deal $deal, seat $seat');
            guesses++;
          }
        }
      }
    }
    expect(redealt, 16);
    expect(guesses, 16 * 2 * 3 * 40);
  });
}
