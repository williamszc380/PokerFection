// The range numbers checked against an independent count: at the start of a
// deal, before anyone has shown anything, an opponent's hand is a uniform draw
// from the cards the player can't see, so each rank's chance is hypergeometric.
// And a bid the player has seen is part of what they know.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_range.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_record.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_jobs.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_range.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_record.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/kit/game_record.dart';
import 'package:pokerfection/src/kit/seats.dart';

double _choose(int n, int k) {
  if (k < 0 || k > n) return 0;
  var r = 1.0;
  for (var i = 0; i < k; i++) {
    r = r * (n - i) / (i + 1);
  }
  return r;
}

/// P(at least k of K special in n drawn from N).
double _atLeast(int N, int K, int n, int k) {
  var p = 0.0;
  for (var j = k; j <= min(K, n); j++) {
    p += _choose(K, j) * _choose(N - K, n - j) / _choose(N, n);
  }
  return p;
}

void main() {
  test('big two: start of a 4-player deal, the player holding the 3d: hypergeometric', () {
    final rules = BigTwoRules.standard();
    final seats = [
      const SeatSpec(human: true, name: 'Player'),
      for (final name in ['Ana', 'Ben', 'Kai']) SeatSpec(human: false, level: KitLevel.easy, name: name),
    ];
    var checked = 0;
    for (var seed = 1; seed < 200 && checked < 3; seed++) {
      final record = BigTwoRecord.deal(rules: rules, seats: seats, seed: seed);
      final state = BigTwoRecord.replay(record);
      if (state.toMove != 0) continue;
      checked++;
      final view = state.viewFor(0);
      final mine = List<int>.filled(13, 0);
      for (final code in view.handCodes) {
        mine[rules.cardOf(code).rank]++;
      }
      final range = bigTwoRange(view, 1 + seed % 3, seed: seed, samples: 2000);
      for (final (i, rc) in range.ranks.indexed) {
        for (var k = 1; k <= 4; k++) {
          final exact = _atLeast(39, 4 - mine[i], 13, k);
          expect(rc.chance(k), closeTo(exact, 0.05), reason: 'seed $seed rank ${rc.rank} at least $k');
        }
      }
      // Independent Monte Carlo for "any pair" and "any 2".
      final unseen = <int>[]; // ranks of unseen cards
      for (var r = 0; r < 13; r++) {
        for (var k = 0; k < 4 - mine[r]; k++) {
          unseen.add(r);
        }
      }
      final rng = Random(99);
      var pairs = 0, twos = 0;
      const n = 50000;
      for (var t = 0; t < n; t++) {
        unseen.shuffle(rng);
        final c = List<int>.filled(13, 0);
        for (final r in unseen.take(13)) {
          c[r]++;
        }
        if (c.any((x) => x >= 2)) pairs++;
        if (c[12] >= 1) twos++;
      }
      double kind(String k) => range.combos.firstWhere((c) => c.kind == k).chance;
      expect(kind('pair'), closeTo(pairs / n, 0.03), reason: 'seed $seed pair');
      expect(kind('twos:1'), closeTo(twos / n, 0.05), reason: 'seed $seed 2s');
    }
    expect(checked, 3);
  });

  test('doudizhu: auction start, before any bid: hypergeometric over the unseen cards, the face-up card with its '
      'holder', () {
    final holders = <int>{};
    for (final seed in [1, 2, 3, 4, 5, 6]) {
      final view = ddzReplay(ddzSampleGame(seed).upTo(0)).viewFor(0);
      final mine = countsOfIds(view.hand);
      final seat = 1 + seed % 2;
      final range = ddzRange(view, seat, random: Random(seed), pool: 1500);
      expect(range.cards, 17);
      // Everyone saw the face-up card dealt to the first bidder: when that
      // is another seat, 36 cards are shared out at random, not 37.
      final holder = view.firstBidder, up = rankOfId(view.faceUp!);
      holders.add(holder);
      final pool = holder == 0 ? 37 : 36;
      final drawn = holder == seat ? 16 : 17;
      for (final (i, rc) in range.ranks.indexed) {
        final copies = i >= 13 ? 1 : 4;
        final unseen = copies - mine[i] - (holder != 0 && i == up ? 1 : 0);
        for (var k = 1; k <= copies; k++) {
          final need = holder == seat && i == up ? k - 1 : k;
          final exact = need <= 0 ? 1.0 : _atLeast(pool, unseen, drawn, need);
          expect(rc.chance(k), closeTo(exact, 0.06), reason: 'seed $seed rank ${rc.rank} at least $k');
        }
      }
    }
    expect(holders, {0, 1, 2}, reason: 'the seeds cover the face-up card in every seat');
  });

  test('doudizhu: a bid of 2 seen in the auction raises the bidder\'s chance of the big joker and the 2s', () {
    final game = DdzGame.deal(random: Random(11), firstBidder: 1);
    GameRecord rec(List<String> moves) => GameRecord(
      game: 'doudizhu',
      version: ddzRecordVersion,
      seed: 1,
      rules: DdzRules.standard.toJson(),
      seats: const [
        SeatSpec(human: true, name: 'Player'),
        SeatSpec(human: false, name: 'Ana'),
        SeatSpec(human: false, name: 'Ben'),
      ],
      deal: ddzDealOf(game),
      moves: moves,
    );
    final before = ddzReplay(rec(const [])).viewFor(0);
    final after = ddzReplay(rec(['1:${const DdzBid(2).encode()}'])).viewFor(0);
    expect(after.landlord, isNull, reason: 'the auction goes on');
    final a = ddzRange(before, 1, random: Random(5), pool: 1500);
    final b = ddzRange(after, 1, random: Random(5), pool: 1500);
    double p(r, String code) => r.ranks.firstWhere((x) => x.rank == code).chance(1) as double;
    // A bid of 2 says the hand is strong (bidFor >= 2: jokers, 2s, bombs),
    // so the chance of the big joker or a 2 should go up.
    expect(p(b, 'BJ') + p(b, '2'), greaterThan(p(a, 'BJ') + p(a, '2') + 0.05),
        reason: 'the range should take the bid into account');
  });
}
