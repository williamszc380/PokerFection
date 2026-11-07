import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_jobs.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_range.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_record.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/kit/game_record.dart';
import 'package:pokerfection/src/kit/jobs/job_registry.dart';
import 'package:pokerfection/src/kit/jobs/jobs_core.dart';
import 'package:pokerfection/src/kit/range.dart';

/// The range job run here, as the app's worker runs it (through JSON).
OpponentRange rangeOf(GameRecord position, int seat, {int seed = 1}) {
  const job = DdzRangeJob();
  final input = DdzRangeInput(record: position.jobJson(), viewer: 0, seat: seat, seed: seed);
  final reply = runJobRequest(encodeRequest(1, job, input, platform: JobPlatform.test), kitJobs);
  return job.decodeOutput((jsonDecode(reply) as Map)['out']);
}

GameRecord recordOf(Map<String, Object?> deal, {List<String> moves = const []}) => GameRecord(
  game: 'doudizhu',
  version: ddzRecordVersion,
  seed: 1,
  rules: DdzRules.standard.toJson(),
  seats: const [
    SeatSpec(human: true, name: 'Player'),
    SeatSpec(human: false, name: 'Ana'),
    SeatSpec(human: false, name: 'Ben'),
  ],
  deal: deal,
  moves: moves,
);

double rank(OpponentRange r, String code, [int n = 1]) => r.ranks.firstWhere((x) => x.rank == code).chance(n);
ComboChance kind(OpponentRange r, String k) => r.combos.firstWhere((c) => c.kind == k);

void main() {
  group('the combinations one hand can make', () {
    test('pairs, trios, straights by their first five, pair straights, airplanes, bombs and the rocket', () {
      // 33 444 5555 6 7 8 + both jokers.
      final counts = countsOfRanks(parseRanks('33 444 5555 678 BR'));
      final combos = ddzRangeCombos(counts);
      expect(combos['pair'], {'33', '44', '55'}, reason: 'a bomb splits into pairs too');
      expect(combos['trio'], {'444', '555'});
      expect(combos['straight'], {'34567', '45678'});
      expect(combos['pairs'], {'334455'});
      expect(combos['airplane'], {'444555'});
      expect(combos['bomb'], {'5555'});
      expect(combos['rocket'], {'BR'});
    });

    test('no 2 or joker in a straight, and one joker is no rocket', () {
      final combos = ddzRangeCombos(countsOfRanks(parseRanks('TJQKA2 B')));
      expect(combos['straight'], {'TJQKA'});
      expect(combos['rocket'], isEmpty);
      expect(combos['pair'], isEmpty);
    });
  });

  group('the range job', () {
    test('is registered with the game\'s jobs, in the app\'s worker too', () {
      expect(doudizhuJobs.map((j) => j.name), contains('doudizhu.range'));
      expect(kitJobs['doudizhu.range'], isA<DdzRangeJob>());
    });

    test('names every rank, lowest first, with the jokers once each, and every kind in order', () {
      final game = ddzSampleGame(1);
      final r = rangeOf(game.upTo(0), 1);
      expect(r.ranks.map((x) => x.rank), ['3', '4', '5', '6', '7', '8', '9', 'T', 'J', 'Q', 'K', 'A', '2', 'SJ', 'BJ']);
      expect(r.ranks.last.atLeast, hasLength(1), reason: 'one big joker in the deck');
      expect(r.ranks.first.atLeast, hasLength(4));
      expect(r.combos.map((c) => c.kind), ddzRangeKinds);
      expect(r.cards, 17);
      expect(r.samples, greaterThan(50));
    });

    test('a rank the player holds all four of is never in the opponent\'s hand', () {
      for (var seed = 1; seed < 60; seed++) {
        final game = DdzGame.deal(random: Random(seed), firstBidder: 0);
        final mine = countsOfIds(game.hands[0]);
        final four = [for (var r = 0; r <= Rank.two; r++) if (mine[r] == 4) r].firstOrNull;
        if (four == null) continue;
        final record = recordOf(ddzDealOf(game));
        final r = rangeOf(record, 2);
        expect(rank(r, ddzRangeRank(four)), 0);
        expect(kind(r, 'bomb').examples.map((e) => e.$1), isNot(contains(Rank.chars[four] * 4)));
        return;
      }
      fail('no deal gave the player four of a kind');
    });

    test('works only from the player\'s view: the same range whatever the bots really hold', () {
      final game = DdzGame.deal(random: Random(7), firstBidder: 0);
      final deal = ddzDealOf(game);
      final hands = [for (final h in deal['hands']! as List) [...(h as List).cast<int>()]];
      // The bots' hands swapped, and two cards traded with the kitty: the
      // player sees exactly the same table.
      final kitty = [...(deal['kitty']! as List).cast<int>()];
      final swapped = {
        ...deal,
        'hands': [hands[0], [kitty[0], ...hands[2].skip(1)], hands[1]],
        'kitty': [hands[2][0], kitty[1], kitty[2]],
      };
      expect(jsonEncode(rangeOf(recordOf(deal), 1).toJson()), jsonEncode(rangeOf(recordOf(swapped), 1).toJson()));
    });

    test('the kitty cards the landlord shows and hasn\'t played are surely in their hand', () {
      final game = DdzGame.deal(random: Random(3), firstBidder: 1);
      // Seat 1 bids 3 and becomes the landlord; the standard rules show the kitty.
      final record = recordOf(ddzDealOf(game), moves: ['1:${const DdzBid(3).encode()}']);
      final kitty = countsOfIds(ddzReplay(record).kitty);
      final r = rangeOf(record, 1);
      expect(r.cards, 20);
      for (var rk = 0; rk < Rank.count; rk++) {
        if (kitty[rk] > 0) expect(rank(r, ddzRangeRank(rk), kitty[rk]), 1, reason: Rank.label(rk));
      }
    });

    test('the same input gives the same range (its seed), and the chances read as chances', () {
      final position = ddzSampleGame(2).upTo(12);
      final a = rangeOf(position, 2, seed: 5), b = rangeOf(position, 2, seed: 5);
      expect(jsonEncode(a.toJson()), jsonEncode(b.toJson()));
      for (final x in a.ranks) {
        for (var n = 1; n < x.atLeast.length; n++) {
          expect(x.atLeast[n], lessThanOrEqualTo(x.atLeast[n - 1]), reason: 'at least ${n + 1} ≤ at least $n');
        }
      }
      final expected = a.ranks.fold<double>(0, (sum, x) => sum + x.expected);
      expect(expected, closeTo(a.cards, 0.01), reason: 'the expected cards add up to the hand');
    });

    test('a hand known for sure is one deal, every chance 0% or 100%', () {
      // A finished deal a bot won: the other bot holds every card the
      // player hasn't seen.
      for (var seed = 1; seed < 40; seed++) {
        final game = ddzSampleGame(seed);
        final end = ddzReplay(game);
        final out = [1, 2].where((s) => end.hands[s].isEmpty).firstOrNull;
        if (out == null) continue;
        final other = 3 - out;
        final r = rangeOf(game, other);
        expect(r.samples, 1);
        final held = countsOfIds(end.hands[other]);
        for (var rk = 0; rk < Rank.count; rk++) {
          expect(rank(r, ddzRangeRank(rk)), held[rk] > 0 ? 1 : 0, reason: Rank.label(rk));
        }
        return;
      }
      fail('no bot won a sample deal');
    });

    test('its examples run, and its check inputs cover the auction, the lead and late play', () {
      const job = DdzRangeJob();
      for (final input in job.examples()) {
        expect(job.run(input, JobContext(platform: JobPlatform.test)).cards, greaterThan(0));
      }
      expect(job.checkInputs().length, greaterThanOrEqualTo(9));
    });

    test('stops early when its time runs out, still with a range', () {
      final view = ddzReplay(ddzSampleGame(1).upTo(10)).viewFor(0);
      final r = ddzRange(view, 1, random: Random(1), pool: 100000, deadline: Duration.zero);
      expect(r.samples, inInclusiveRange(1, 20), reason: 'the 20 guesses it always weighs, by their worth');
      expect(r.cards, view.handSizes[1]);
    });

    test('counts its deals by what they are worth, never more than it weighed', () {
      // Mid-deal the guesses weigh unevenly (some explain the plays badly):
      // the sheet's "from N possible deals" is their effective number.
      final counts = <int>[];
      for (final seed in [1, 3, 4]) {
        final game = ddzSampleGame(seed);
        final view = ddzReplay(game.upTo(game.moves.length * 2 ~/ 3)).viewFor(0);
        if (view.landlord == null) continue;
        final r = ddzRange(view, view.landlord == 0 ? 1 : view.landlord!, random: Random(seed), pool: 400);
        expect(r.samples, inInclusiveRange(1, 400), reason: 'seed $seed');
        counts.add(r.samples);
      }
      expect(counts.any((n) => n < 400), isTrue, reason: 'uneven weights count for fewer deals: $counts');
      final start = ddzReplay(ddzSampleGame(1).upTo(0)).viewFor(0);
      expect(ddzRange(start, 1, random: Random(1), pool: 400).samples, 400,
          reason: 'before any bid every guess weighs the same, so each counts in full');
    });

    test('refuses the player\'s own seat', () {
      final view = ddzReplay(ddzSampleGame(1).upTo(0)).viewFor(0);
      expect(() => ddzRange(view, 0, random: Random(1), pool: 10), throwsArgumentError);
    });
  });

  group('the face-up card in a range', () {
    /// A deal whose face-up card seat 1 got, so seat 1 opens the auction.
    DdzGame seatOneUp() {
      for (var seed = 0;; seed++) {
        final g = DdzGame.deal(random: Random(seed));
        if (g.firstBidder == 1) return g;
      }
    }

    /// The face-up card's rank is at 100% in its holder's range; in the
    /// other seat's range, never more of it than the cards nobody has seen.
    void expectPlaced(GameRecord position, DdzGame game) {
      final up = game.faceUp!;
      final code = ddzRangeRank(rankOfId(up));
      final unknown = ddzReplay(position).viewFor(0).cardCount.unknown[rankOfId(up)];
      expect(rank(rangeOf(position, 1), code), 1, reason: 'seat 1 was dealt it face up');
      expect(rank(rangeOf(position, 2), code, unknown + 1), 0, reason: 'seat 2 never holds it');
    }

    test("the holder has its rank at 100% before any bid, and the other seat's range never counts that card", () {
      final game = seatOneUp();
      expectPlaced(recordOf(ddzDealOf(game)), game);
    });

    test('in play too: the other seat took the landlord and the kitty, the card stays with its holder', () {
      final game = seatOneUp();
      final position = recordOf(ddzDealOf(game), moves: ['1:${const DdzBid(0).encode()}', '2:${const DdzBid(3).encode()}']);
      expect(ddzReplay(position).landlord, 2);
      expectPlaced(position, game);
    });
  });
}
