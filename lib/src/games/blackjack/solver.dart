/// Exact expected values of every play, for one hand against one upcard,
/// given the cards that are still unseen.
///
/// Method ("composition-dependent combinatorial analysis"):
/// - Standing: the dealer's outcome chances for the unseen cards minus
///   the cards the player drew ([DealerGraph]), scored against the
///   player's total.
/// - Hitting: for each rank still unseen, its exact chance (count left /
///   cards left), times the value of the new hand played on as well as
///   possible (stand or hit again), recursively. Hands that reach the same
///   set of drawn cards share one memo entry, so a hand is solved in a few
///   thousand steps.
/// - Doubling: one card, stand, twice the stake. Surrender: half the bet.
/// - Splitting: see [EvCalculator] for the method and its approximation.
///
/// Dealer blackjack. In a hole card game the dealer has already peeked
/// when the player acts, so values are conditional on "no dealer
/// blackjack". The solver computes joint values (outcome and no
/// blackjack): drawing a card first and the hole card last is the same
/// as the real order, because every order of unseen cards is equally
/// likely. Dividing by the no-blackjack chance at the end gives the
/// conditional values. Without a hole card the dealer's blackjack is just
/// another outcome: every bet loses to it, or only the original bet (in
/// which case the game plays exactly like a hole card game).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'action.dart';
import 'cards.dart';
import 'dealer.dart';
import 'rules.dart';

/// What the solver needs to know about the hand being decided.
class HandSpot {
  /// A hand of [hard] points (aces as 1), with an ace or not, of
  /// [cardCount] cards. [pairRank] is the rank index of a two-card pair
  /// (-1 otherwise). [splitHand]: the hand came from a split;
  /// [splitAces]: from splitting aces. [handsAtSeat]: how many hands the
  /// seat has now (splits are limited by [BlackjackRules.maxHands]).
  /// [originalHand]: the seat's first hand (the one that carries the
  /// original bet when only original bets lose to a dealer blackjack).
  const HandSpot({
    required this.hard,
    required this.hasAce,
    required this.cardCount,
    this.pairRank = -1,
    this.splitHand = false,
    this.splitAces = false,
    this.handsAtSeat = 1,
    this.originalHand = true,
  });

  /// The spot for these [cards].
  factory HandSpot.ofCards(
    List<Card> cards, {
    bool splitHand = false,
    bool splitAces = false,
    int handsAtSeat = 1,
    bool originalHand = true,
  }) {
    var hard = 0;
    var ace = false;
    for (final c in cards) {
      hard += c.points;
      if (c.rank == aceIndex) ace = true;
    }
    return HandSpot(
      hard: hard,
      hasAce: ace,
      cardCount: cards.length,
      pairRank: cards.length == 2 && cards[0].rank == cards[1].rank ? cards[0].rank : -1,
      splitHand: splitHand,
      splitAces: splitAces,
      handsAtSeat: handsAtSeat,
      originalHand: originalHand,
    );
  }

  /// Hard points, aces counted as 1.
  final int hard;

  /// The hand holds at least one ace.
  final bool hasAce;

  /// Cards in the hand.
  final int cardCount;

  /// Rank index of a two-card pair, or -1.
  final int pairRank;

  /// The hand came from a split (no blackjack, no surrender, doubling
  /// only with double after split).
  final bool splitHand;

  /// The hand came from splitting aces.
  final bool splitAces;

  /// Hands the seat holds now, this one included.
  final int handsAtSeat;

  /// The seat's first hand.
  final bool originalHand;

  /// The hand's total.
  HandTotal get total => totalOf(hard, hasAce);

  /// A two-card 21 that didn't come from a split.
  bool get isBlackjack => cardCount == 2 && !splitHand && hasAce && hard == 11;
}

/// A playing strategy the solver can follow instead of playing perfectly,
/// used to measure basic strategy (and the bots) exactly.
abstract interface class PlayPolicy {
  /// Picks one of the actions whose bits are set in [allowed] for a hand
  /// of [total] with [cardCount] cards against [upcard] (rank index).
  /// [pairRank] is the rank of a splittable pair or -1. After the first
  /// decision only stand and hit are offered.
  BlackjackAction choose(HandTotal total, int cardCount, int pairRank, int upcard, int allowed);
}

/// Values of the five play actions for one hand (stand, hit, double,
/// split, surrender), NaN where the action is not allowed.
typedef PlayValues = Map<BlackjackAction, double>;

/// The play actions the solver values, in [BlackjackAction] index order.
const List<BlackjackAction> playActions = [
  BlackjackAction.stand,
  BlackjackAction.hit,
  BlackjackAction.double,
  BlackjackAction.split,
  BlackjackAction.surrender,
];

/// Exact expected values (in bets) for one upcard and one set of unseen
/// cards. One calculator can answer many hands; it keeps the dealer
/// outcome chances it has worked out (they depend only on which cards are
/// gone) and the values of hands it has met.
///
/// Splitting. An exact value for splitting (with resplits) needs every
/// way the extra hands can be dealt, which is far too much work for a
/// phone. This calculator uses the approach of published combinatorial
/// analyzers: each split hand is valued as a hand that starts with the
/// pair card, with the shoe missing only the pair cards dealt so far
/// (the other hands' other cards are not yet known when a hand is played
/// first, and for later hands their effect is ignored), played with the
/// best strategy for that hand. Resplitting is followed exactly as a
/// chain of "the next card is another pair card or not" events, with the
/// chance of a pair card falling as pair cards leave. Against Wizard of
/// Odds' combinatorial results (whose house edges are optimal play with
/// a full shoe each round) the house edges agree within 0.01% (see
/// test/games/blackjack/house_edge_test.dart and the report in the tool).
class EvCalculator {
  /// A calculator for [rules], an [upcard] (rank index) and the cards the
  /// player hasn't seen ([unseen]: the shoe after the cards dealt so far,
  /// the dealer's hole card included, the upcard not). With a [policy],
  /// hands are played by it instead of perfectly.
  EvCalculator(this.rules, Composition unseen, this.upcard, {this.policy})
    : _root = Int32List.fromList(unseen.counts),
      _rootTotal = unseen.total,
      _graph = DealerGraph.of(upcard, rules.dealerHitsSoft17),
      _loseAll = !rules.holeCard && rules.noHoleCardLoss == NoHoleCardLoss.allBets {
    _work = Float64List(_graph.nodeCount);
  }

  /// The table rules.
  final BlackjackRules rules;

  /// The dealer's upcard (rank index).
  final int upcard;

  /// A strategy to follow instead of perfect play, or null.
  final PlayPolicy? policy;

  final Int32List _root;
  final int _rootTotal;
  final DealerGraph _graph;
  final bool _loseAll;
  late final Float64List _work;

  // Cards taken out of the unseen set by the hand being examined.
  final Int32List _rem = Int32List(rankCount);
  int _remTotal = 0;
  int _remKey = 0;

  // Key weights: 32 per rank, 10 ranks = 2^50, exact in JavaScript too.
  static const List<int> _weights = [
    1,
    32,
    1024,
    32768,
    1048576,
    33554432,
    1073741824,
    34359738368,
    1099511627776,
    35184372088832,
  ];

  final Map<int, Float64List> _dealerCache = {};
  final Map<String, Map<int, double>> _memos = {};
  final Int32List _counts = Int32List(rankCount);

  /// Dealer outcome lists worked out so far (for timing reports).
  int get dealerEvaluations => _dealerCache.length;

  void _take(int r) {
    _rem[r]++;
    _remTotal++;
    _remKey += _weights[r];
  }

  void _put(int r) {
    _rem[r]--;
    _remTotal--;
    _remKey -= _weights[r];
  }

  int _avail(int r) => _root[r] - _rem[r];

  int get _left => _rootTotal - _remTotal;

  Float64List _dealer() {
    final cached = _dealerCache[_remKey];
    if (cached != null) return cached;
    for (var r = 0; r < rankCount; r++) {
      _counts[r] = _avail(r);
    }
    final out = Float64List(dealerOutcomeCount);
    _graph.outcomes(_counts, _left, out, _work);
    _dealerCache[_remKey] = out;
    return out;
  }

  /// The chance the hole card gives the dealer blackjack, for the cards
  /// unseen right now (inside the recursion, after the player's draws).
  double _pBj() {
    final left = _left;
    if (left <= 0) return 0;
    if (upcard == aceIndex) return _avail(tenIndex) / left;
    if (upcard == tenIndex) return _avail(aceIndex) / left;
    return 0;
  }

  /// The chance the dealer has (or will make) blackjack, from the unseen
  /// cards as given. 0 unless the upcard is an ace or ten-value card.
  double get dealerBlackjackChance => _pBj();

  double _stand(int total, double stake) {
    final p = _dealer();
    var v = p[dealerBust];
    if (total >= 17) {
      for (var t = 17; t <= 21; t++) {
        if (total > t) {
          v += p[t - 17];
        } else if (total < t) {
          v -= p[t - 17];
        }
      }
    } else {
      v -= p[0] + p[1] + p[2] + p[3] + p[4];
    }
    if (_loseAll) v -= p[dealerBlackjack];
    return v * stake;
  }

  double _bust(double stake) => _loseAll ? -stake : -stake * (1 - _pBj());

  Map<int, double> _memo(int startHard, bool startAce, int baseKey) =>
      _memos.putIfAbsent('$startHard,$startAce,$baseKey', () => <int, double>{});

  double _node(int hard, bool ace, Map<int, double> memo) {
    final cached = memo[_remKey];
    if (cached != null) return cached;
    final t = totalOf(hard, ace);
    final stand = _stand(t.value, 1);
    double v;
    if (t.value >= 21) {
      v = stand;
    } else {
      final pol = policy;
      if (pol != null) {
        final hits =
            pol.choose(t, 3, -1, upcard, BlackjackAction.stand.bit | BlackjackAction.hit.bit) == BlackjackAction.hit;
        v = hits ? _hit(hard, ace, memo) : stand;
      } else {
        final h = _hit(hard, ace, memo);
        v = h > stand ? h : stand;
      }
    }
    memo[_remKey] = v;
    return v;
  }

  double _hit(int hard, bool ace, Map<int, double> memo) {
    final left = _left;
    if (left <= 0) return _stand(totalOf(hard, ace).value, 1);
    var v = 0.0;
    for (var r = 0; r < rankCount; r++) {
      final a = _avail(r);
      if (a <= 0) continue;
      final h = hard + rankPoints(r);
      _take(r);
      v += a / left * (h > 21 ? _bust(1) : _node(h, ace || r == aceIndex, memo));
      _put(r);
    }
    return v;
  }

  double _double(int hard, bool ace) {
    final left = _left;
    if (left <= 0) return double.nan;
    var v = 0.0;
    for (var r = 0; r < rankCount; r++) {
      final a = _avail(r);
      if (a <= 0) continue;
      final h = hard + rankPoints(r);
      _take(r);
      v += a / left * (h > 21 ? _bust(2) : _stand(totalOf(h, ace || r == aceIndex).value, 2));
      _put(r);
    }
    return v;
  }

  /// Raw values (joint with "no dealer blackjack" unless every bet loses
  /// to one) of the five play actions, in [playActions] order, NaN when
  /// not allowed. The hand is [spot]; its cards beyond [startHard] /
  /// [startAce] are already taken out (as in the house edge sweep) or
  /// [startHard] is the whole hand (as for the coach). [baseKey] is the
  /// removal key of cards that are gone but not in this hand.
  Float64List _rawValues(HandSpot spot, int startHard, bool startAce, int baseKey) {
    final out = Float64List(5)..fillRange(0, 5, double.nan);
    final t = spot.total;
    final memo = _memo(startHard, startAce, baseKey);
    final oneCardOnly = spot.splitAces && !rules.hitSplitAces;
    out[0] = _stand(t.value, 1);
    if (t.value < 21 && !oneCardOnly) out[1] = _hit(spot.hard, spot.hasAce, memo);
    if (canDouble(spot)) out[2] = _double(spot.hard, spot.hasAce);
    if (canSplit(spot)) out[3] = _split(spot.pairRank, spot.handsAtSeat);
    if (canSurrender(spot)) out[4] = _surrenderRaw();
    return out;
  }

  double _surrenderRaw() {
    final p = _pBj();
    if (rules.surrender == Surrender.early) {
      // Early: half the bet whatever the dealer has. In the joint basis
      // (where the dealer-blackjack loss is added afterwards) that is
      // -0.5 + p, so that "raw - p" is -0.5.
      return _loseAll ? -0.5 : -0.5 + p;
    }
    // Late: half back only if the dealer has no blackjack.
    return _loseAll ? -0.5 * (1 - p) - p : -0.5 * (1 - p);
  }

  /// Whether [spot] may double under the rules.
  bool canDouble(HandSpot spot) =>
      spot.cardCount == 2 &&
      spot.total.value < 21 &&
      rules.doubling.allows(spot.hard, spot.hasAce) &&
      (!spot.splitHand || rules.doubleAfterSplit) &&
      (!spot.splitAces || rules.hitSplitAces);

  /// Whether [spot] may split under the rules.
  bool canSplit(HandSpot spot) =>
      spot.pairRank >= 0 &&
      spot.cardCount == 2 &&
      spot.handsAtSeat < rules.maxHands &&
      (!spot.splitAces || rules.resplitAces);

  /// Whether [spot] may surrender under the rules (the first two cards of
  /// an unsplit hand).
  bool canSurrender(HandSpot spot) => rules.surrender != Surrender.none && spot.cardCount == 2 && !spot.splitHand;

  // ---- Splitting -----------------------------------------------------

  /// The value of splitting a pair of rank [p] when the seat has
  /// [handsAtSeat] hands (this one included). Each hand is valued on the
  /// unseen cards minus the pair cards dealt so far; see the class notes.
  double _split(int p, int handsAtSeat) {
    final baseKey = _remKey;
    final nonPair = <int, double>{};
    final pair = <int, double>{};
    final chain = <int, double>{};
    final canResplitRank = p != aceIndex || rules.resplitAces;

    // The chance the next card is another p once e more p's are gone.
    double q(int e) {
      final a = _avail(p) - e;
      final left = _left - e;
      return a <= 0 || left <= 0 ? 0 : a / left;
    }

    double vNonPair(int e) => nonPair[e] ??= _splitHandNonPair(p, e, baseKey);
    double vPair(int e) => pair[e] ??= _splitHandPair(p, e, baseKey);

    // pending: hands holding one p, waiting for a second card;
    // total: hands at the seat; e: extra p's dealt from the shoe.
    double f(int pending, int total, int e) {
      if (pending == 0) return 0;
      final key = pending * 1000 + total * 10 + e;
      final cached = chain[key];
      if (cached != null) return cached;
      final qp = q(e);
      double v;
      if (canResplitRank && total < rules.maxHands) {
        v = (qp > 0 ? qp * f(pending + 1, total + 1, e + 1) : 0) + (1 - qp) * (vNonPair(e) + f(pending - 1, total, e));
      } else {
        v =
            (qp > 0 ? qp * (vPair(e + 1) + f(pending - 1, total, e + 1)) : 0) +
            (1 - qp) * (vNonPair(e) + f(pending - 1, total, e));
      }
      chain[key] = v;
      return v;
    }

    return f(2, handsAtSeat + 1, 0);
  }

  /// A split hand: the pair card [p] plus a second card that is not a [p],
  /// with [e] other p's gone.
  double _splitHandNonPair(int p, int e, int baseKey) {
    for (var i = 0; i < e; i++) {
      _take(p);
    }
    final left = _left;
    final others = left - _avail(p);
    var v = 0.0;
    if (others > 0) {
      final memo = _memo(rankPoints(p), p == aceIndex, baseKey + e * _weights[p]);
      for (var r = 0; r < rankCount; r++) {
        if (r == p) continue;
        final a = _avail(r);
        if (a <= 0) continue;
        _take(r);
        v += a / others * _splitHandValue(p, r, memo);
        _put(r);
      }
    }
    for (var i = 0; i < e; i++) {
      _put(p);
    }
    return v;
  }

  /// A split hand that drew a pair card it can't split again: [e] p's
  /// gone, its own second p among them.
  double _splitHandPair(int p, int e, int baseKey) {
    for (var i = 0; i < e - 1; i++) {
      _take(p);
    }
    final memo = _memo(rankPoints(p), p == aceIndex, baseKey + (e - 1) * _weights[p]);
    _take(p);
    final v = _splitHandValue(p, p, memo);
    _put(p);
    for (var i = 0; i < e - 1; i++) {
      _put(p);
    }
    return v;
  }

  /// The value of a two-card split hand [p], [r] (r already taken out),
  /// played on (or not, for split aces with one card each).
  double _splitHandValue(int p, int r, Map<int, double> memo) {
    final hard = rankPoints(p) + rankPoints(r);
    final ace = p == aceIndex || r == aceIndex;
    final t = totalOf(hard, ace);
    final stand = _stand(t.value, 1);
    if (p == aceIndex && !rules.hitSplitAces) return stand;
    if (t.value >= 21) return stand;
    final dbl = rules.doubleAfterSplit && rules.doubling.allows(hard, ace);
    final pol = policy;
    if (pol != null) {
      final allowed = BlackjackAction.stand.bit | BlackjackAction.hit.bit | (dbl ? BlackjackAction.double.bit : 0);
      switch (pol.choose(t, 2, -1, upcard, allowed)) {
        case BlackjackAction.hit:
          return _hit(hard, ace, memo);
        case BlackjackAction.double:
          return _double(hard, ace);
        default:
          return stand;
      }
    }
    var best = math.max(stand, _hit(hard, ace, memo));
    if (dbl) best = math.max(best, _double(hard, ace));
    return best;
  }

  // ---- Public answers ----------------------------------------------

  /// The values of the play actions for [spot] (whose cards are not among
  /// the unseen cards), in bets of this hand's own bet:
  /// - hole card game: given the dealer has no blackjack (the dealer has
  ///   peeked by the time a player acts);
  /// - no hole card: the dealer's later blackjack included.
  /// Actions not allowed are missing.
  PlayValues playValues(HandSpot spot) {
    _reset();
    final raw = _rawValues(spot, spot.hard, spot.hasAce, 0);
    final p = _pBj();
    final out = <BlackjackAction, double>{};
    for (var i = 0; i < 5; i++) {
      if (raw[i].isNaN) continue;
      out[playActions[i]] = _report(raw[i], p, spot.originalHand);
    }
    return out;
  }

  double _report(double raw, double p, bool original) {
    if (rules.holeCard) return p >= 1 ? 0 : raw / (1 - p);
    if (_loseAll) return raw;
    return raw - (original ? p : 0);
  }

  /// The value of [spot] before the dealer has checked for blackjack (the
  /// insurance and early surrender phases): a dealer blackjack costs the
  /// bet (a push with a blackjack of your own); otherwise the hand is
  /// played as well as possible (surrender included only if
  /// [withSurrender]).
  double valueBeforePeek(HandSpot spot, {bool withSurrender = true}) {
    _reset();
    final p = _pBj();
    if (spot.isBlackjack) return rules.payout.multiplier * (1 - p);
    final raw = _rawValues(spot, spot.hard, spot.hasAce, 0);
    var best = double.negativeInfinity;
    for (var i = 0; i < 5; i++) {
      if (raw[i].isNaN || (i == 4 && !withSurrender)) continue;
      best = math.max(best, raw[i]);
    }
    return _loseAll ? best : best - p;
  }

  /// The value of an insurance bet (half the original bet, paying 2 to 1)
  /// in original bets: 0.5 × (3p − 1) where p is the chance of a dealer
  /// blackjack. Positive only when more than a third of the unseen cards
  /// are tens.
  double insuranceValue() => 0.5 * (3 * _pBj() - 1);

  void _reset() {
    // Values in the memos depend on the hand being solved, so they are
    // only shared within one public call; the dealer cache stays.
    _memos.clear();
  }

  // ---- Initial deals (house edge, charts) ---------------------------

  /// Values of every play for the initial two-card hand [c1], [c2] (rank
  /// indexes still among the unseen cards), as expected results of the
  /// whole round before the dealer checks for blackjack (blackjack losses
  /// and pushes included), in [playActions] order (NaN where not
  /// allowed). A player blackjack has only "stand": its payout.
  /// Values of different starting hands share this calculator's memo.
  Float64List initialValues(int c1, int c2) {
    _take(c1);
    _take(c2);
    final p0 = _pBj();
    final spot = HandSpot(
      hard: rankPoints(c1) + rankPoints(c2),
      hasAce: c1 == aceIndex || c2 == aceIndex,
      cardCount: 2,
      pairRank: c1 == c2 ? c1 : -1,
    );
    Float64List out;
    if (spot.isBlackjack) {
      out = Float64List(5)..fillRange(0, 5, double.nan);
      out[0] = rules.payout.multiplier * (1 - p0);
    } else {
      out = _rawValues(spot, 0, false, 0);
      for (var i = 0; i < 5; i++) {
        if (out[i].isNaN || _loseAll) continue;
        out[i] -= p0;
      }
    }
    _put(c2);
    _put(c1);
    return out;
  }
}
