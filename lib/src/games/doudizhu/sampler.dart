/// Guessing the hidden cards: deals of the unseen cards that fit what one
/// seat knows.
///
/// This is the "determinization" of perfect-information Monte Carlo
/// (Whitehouse, Powley and Cowling studied it on Dou Di Zhu:
/// https://eprints.whiterose.ac.uk/75050/1/EnsDetMagic.pdf). Each guess
/// respects every hard fact: the seat's own cards, the cards played, each
/// hand's size, and the cards everyone has seen that are still in a hand
/// (DdzView.visibleIn): the face-up card goes to the seat it was dealt to,
/// never to the kitty or the other seat, and the shown kitty cards the
/// landlord hasn't played stay in the landlord's hand. The rest is shared
/// out at random, so every consistent deal is equally likely.
library;

import 'dart:math';

import 'cards.dart';
import 'game.dart';
import 'plays.dart';
import 'policy.dart';
import 'sim.dart';
import 'view.dart';

/// Deals guesses of the hidden cards for one view.
class DdzSampler {
  DdzSampler(this.view) : count = DdzCardCount.of(view) {
    final unknown = count.unknown;
    _pool = [
      for (var r = 0; r < Rank.count; r++)
        for (var i = 0; i < unknown[r]; i++) r,
    ];
    final lord = view.landlord;
    for (var s = 0; s < 3; s++) {
      if (s == view.seat) continue;
      final known = count.knownInHand[s].fold<int>(0, (a, b) => a + b);
      _need[s] = view.handSizes[s] - known;
    }
    if (lord == null) _kittyNeed = _pool.length - _need[(view.seat + 1) % 3] - _need[(view.seat + 2) % 3];
    final total = _need.fold<int>(0, (a, b) => a + b) + _kittyNeed;
    if (total != _pool.length) {
      throw StateError('The view is inconsistent: ${_pool.length} unknown cards for $total places');
    }
  }

  final DdzView view;

  /// The card counter this sampler deals from.
  final DdzCardCount count;

  late final List<int> _pool;
  final List<int> _need = [0, 0, 0];
  int _kittyNeed = 0;

  /// Whether only one deal fits (the hidden cards are all known), so a
  /// solve of it is exact, not a guess.
  bool get isUnique {
    var holders = 0;
    for (var s = 0; s < 3; s++) {
      if (_need[s] > 0) holders++;
    }
    if (_kittyNeed > 0) holders++;
    return holders <= 1;
  }

  /// One guess: each seat's rank counts (the viewer's real hand included),
  /// and during the auction the kitty's counts as the fourth entry.
  List<List<int>> deal(Random random) {
    final pool = _pool;
    // Partial Fisher-Yates: shuffle, then cut in seat order.
    for (var i = pool.length - 1; i > 0; i--) {
      final j = random.nextInt(i + 1);
      final t = pool[i];
      pool[i] = pool[j];
      pool[j] = t;
    }
    final hands = [for (var s = 0; s < 4; s++) List<int>.filled(Rank.count, 0)];
    hands[view.seat] = view.counts;
    var k = 0;
    for (var s = 0; s < 3; s++) {
      if (s == view.seat) continue;
      final h = hands[s];
      final known = count.knownInHand[s];
      for (var r = 0; r < Rank.count; r++) {
        h[r] += known[r];
      }
      for (var i = 0; i < _need[s]; i++) {
        h[pool[k++]]++;
      }
    }
    for (var i = 0; i < _kittyNeed; i++) {
      hands[3][pool[k++]]++;
    }
    return hands;
  }

  /// A guess as a ready-to-play [DdzSim] (play phase only).
  DdzSim sim(Random random) {
    final hands = deal(random);
    return simFromHands(view, hands.sublist(0, 3));
  }
}

/// The play phase of [view] with the given (guessed) hands.
DdzSim simFromHands(DdzView view, List<List<int>> hands) {
  var passes = 0;
  if (view.current != null) {
    for (var i = view.history.length - 1; i >= 0 && view.history[i].move is DdzPass; i--) {
      passes++;
    }
  }
  return DdzSim(
    rules: view.rules,
    hands: hands,
    landlord: view.landlord!,
    toAct: view.toAct,
    stake: view.stake,
    bombs: view.bombs,
    current: view.current,
    currentPlayer: view.currentPlayer ?? -1,
    passes: passes,
    playsBySeat: [...view.playsBySeat],
  );
}

/// How well a guessed deal explains what the other players did.
///
/// Rebuilds every seat's hand at each of its past decisions (the guessed
/// hand plus the cards it has played since), asks the rule-of-thumb player
/// what it would have done there, and multiplies [mismatch] (0 to 1) into
/// the weight for every move that doesn't fit: a guess that gives a player
/// a 9 they didn't use against an 8 is less likely than one that doesn't.
/// Bids are checked the same way against the rule-of-thumb bid. This is
/// the Bayesian guessing of hidden hands that DeltaDou uses
/// (https://ijcai.org/proceedings/2019/176), with a hand-made player model
/// instead of a trained one. Kickers are ignored: a different kicker is
/// still the same decision. With [mismatch] = 1 every guess weighs 1.
double dealWeight(DdzView view, DdzCardCount count, List<List<int>> hands, HeuristicPolicy policy, double mismatch) {
  if (mismatch >= 1 || view.landlord == null) return 1;
  final lord = view.landlord!;
  final start = [
    for (var s = 0; s < 3; s++) [for (var r = 0; r < Rank.count; r++) hands[s][r] + count.playedBy[s][r]],
  ];
  var weight = 1.0;

  // The auction: did each bid fit the hand?
  final kitty = view.kitty == null ? null : countsOfIds(view.kitty!);
  var high = 0;
  for (final a in view.history) {
    final m = a.move;
    if (m is DdzPlay || m is DdzPass) break;
    if (a.seat == view.seat || (a.seat == lord && kitty == null)) {
      if (m is DdzBid && m.points > high) high = m.points;
      continue;
    }
    final atBid = a.seat == lord
        ? [for (var r = 0; r < Rank.count; r++) start[a.seat][r] - kitty![r]]
        : start[a.seat];
    final want = policy.bidFor(atBid);
    final fits = switch (m) {
      DdzBid(:final points) => points > 0 ? want >= points : want <= high,
      DdzCall(:final yes) => (want >= 1) == yes,
      DdzRob(:final yes) => (want >= 3) == yes,
      _ => true,
    };
    if (m is DdzBid && m.points > high) high = m.points;
    if (!fits) weight *= mismatch;
  }

  // The play: did each move fit the hand?
  final sim = DdzSim(rules: view.rules, hands: start, landlord: lord, toAct: lord, stake: view.stake);
  for (final a in view.history) {
    final m = a.move;
    final Play? actual;
    if (m is DdzPlay) {
      actual = m.play;
    } else if (m is DdzPass) {
      actual = null;
    } else {
      continue;
    }
    if (sim.over || sim.toAct != a.seat) break; // can't happen with a real history
    if (a.seat != view.seat) {
      final choice = policy.choose(DdzSituation(
        seat: a.seat,
        landlord: lord,
        hand: sim.hands[a.seat],
        handSizes: sim.sizes,
        current: sim.current,
        currentPlayer: sim.currentPlayer,
        unseen: sim.unseenBy(a.seat),
        rules: view.rules,
      ));
      final same = choice == null
          ? actual == null
          : actual != null && choice.type == actual.type && choice.rank == actual.rank && choice.length == actual.length;
      if (!same) weight *= mismatch;
    }
    sim.apply(actual);
  }
  return weight;
}

/// How well a guessed deal explains the bids seen so far while the auction
/// is still on (no landlord yet, so [dealWeight] doesn't weigh it): each
/// other seat's bid, call or rob is checked against the rule-of-thumb bid
/// for its guessed 17 cards, exactly as [dealWeight] checks them once a
/// landlord is named, and [mismatch] is multiplied in for each that doesn't
/// fit. A bot that bids 2 then holds the strong cards a bid of 2 promises
/// (jokers, 2s, bombs). Past the auction it is [dealWeight].
double auctionWeight(DdzView view, DdzCardCount count, List<List<int>> hands, HeuristicPolicy policy, double mismatch) {
  if (view.landlord != null) return dealWeight(view, count, hands, policy, mismatch);
  if (mismatch >= 1) return 1;
  var weight = 1.0;
  var high = 0;
  for (final a in view.history) {
    final m = a.move;
    if (m is DdzPlay || m is DdzPass) break;
    if (a.seat != view.seat) {
      // Nothing is played before the landlord is named: the guessed hand
      // is the hand the seat bid with.
      final want = policy.bidFor(hands[a.seat]);
      final fits = switch (m) {
        DdzBid(:final points) => points > 0 ? want >= points : want <= high,
        DdzCall(:final yes) => (want >= 1) == yes,
        DdzRob(:final yes) => (want >= 3) == yes,
        _ => true,
      };
      if (!fits) weight *= mismatch;
    }
    if (m is DdzBid && m.points > high) high = m.points;
  }
  return weight;
}

/// A pool of guessed deals with their [dealWeight]s, drawn from by weight.
/// Weighing a fixed pool once per analysis keeps the cost of the inference
/// to a few hundred replays, however many play-outs follow.
class DealPool {
  DealPool(DdzSampler sampler, Random random,
      {required int size, required HeuristicPolicy policy, double mismatch = 0.3}) {
    for (var i = 0; i < size; i++) {
      final hands = sampler.deal(random).sublist(0, 3);
      final w = dealWeight(sampler.view, sampler.count, hands, policy, mismatch);
      _deals.add(hands);
      _total += w;
      _cumulative.add(_total);
    }
  }

  final List<List<List<int>>> _deals = [];
  final List<double> _cumulative = [];
  double _total = 0;

  /// The largest share of the total weight one deal holds: near 1 means
  /// the history pins the hidden cards down (or surprised the model).
  double get topShare {
    var top = 0.0, prev = 0.0;
    for (final c in _cumulative) {
      if (c - prev > top) top = c - prev;
      prev = c;
    }
    return _total == 0 ? 1 : top / _total;
  }

  /// A deal picked with chance proportional to its weight (a fresh copy,
  /// since play-outs change the hands).
  List<List<int>> draw(Random random) {
    final x = random.nextDouble() * _total;
    var lo = 0, hi = _cumulative.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_cumulative[mid] > x) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return [for (final h in _deals[lo]) List<int>.of(h)];
  }
}
