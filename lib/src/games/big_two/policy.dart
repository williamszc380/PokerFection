/// A fast rule-of-thumb player: the Easy bot, and the policy the coach
/// uses to play out each sampled deal to the end.
///
/// It scores every legal move with a few habits good players teach:
/// shed cards (five-card hands clear the most), play low and keep high
/// cards, don't split pairs and triples, keep your 2s until they matter,
/// fight harder when someone is close to going out, and never hand the
/// next player their last card with a low single. It looks only at the
/// mover's own hand and public facts, so it is safe to run on a guessed
/// deal.
library;

import 'dart:typed_data';

import 'plays.dart';
import 'random.dart';
import 'state.dart';

/// The heuristic player. [noise] adds a random amount up to that size to
/// each move's score, making play less predictable (the Easy bot uses more,
/// the coach's play-outs a little, for variety between samples).
class HeuristicPolicy {
  /// A policy with this much random noise per move score.
  const HeuristicPolicy({this.noise = 0, this.weights = PolicyWeights.standard});

  /// Size of the random term added to each move's score.
  final double noise;

  /// How much each habit counts.
  final PolicyWeights weights;

  /// Picks a move for the player to act in [s].
  Play choose(BigTwoState s, GameRandom rng) {
    final legal = s.legalMoves();
    if (legal.length == 1) return legal.first;
    return chooseFrom(s, legal, rng);
  }

  /// Picks one of [legal] for the player to act in [s].
  Play chooseFrom(BigTwoState s, List<Play> legal, GameRandom rng) {
    final ctx = PolicyContext(s, weights);
    var best = legal.first;
    var bestScore = double.negativeInfinity;
    for (final p in legal) {
      var v = ctx.score(p);
      if (noise > 0) v += (rng.nextDouble() * 2 - 1) * noise;
      if (v > bestScore) {
        bestScore = v;
        best = p;
      }
    }
    return best;
  }
}

/// The facts the heuristic needs about the mover's position, worked out
/// once per decision. Public so the coach can reuse the same judgement for
/// its explanations.
class PolicyContext {
  /// Reads [s] from the point of view of the player to act.
  PolicyContext(BigTwoState s, [this.w = PolicyWeights.standard])
      : seat = s.toMove,
        leading = s.current == null,
        hand = Uint8List.sublistView(s.handMasks, s.toMove * 13, s.toMove * 13 + 13),
        myCount = s.countOf(s.toMove),
        nextCount = s.countOf(s.nextSeat(s.toMove)) {
    var minOpp = 99;
    for (var i = 0; i < s.players; i++) {
      if (i != seat && s.countOf(i) < minOpp) minOpp = s.countOf(i);
    }
    minOpponent = minOpp;
    urgent = minOpp <= w.urgentOpponent || myCount <= w.urgentSelf;
    final played = s.playedMasks;
    for (var r = 0; r < 13; r++) {
      final unseen = 15 & ~hand[r] & ~played[r];
      _unseen[r] = unseen;
    }
    for (var r = 12; r >= 0 && topUnseenSingle < 0; r--) {
      final m = _unseen[r];
      if (m != 0) topUnseenSingle = r * 4 + _highBit(m);
    }
    for (var r = 12; r >= 0 && topUnseenPair < 0; r--) {
      final m = _unseen[r];
      if (popCount4[m] >= 2) topUnseenPair = r * 4 + _highBit(m);
    }
    for (var r = 12; r >= 0; r--) {
      if (hand[r] != 0) {
        myHighest = r * 4 + _highBit(hand[r]);
        break;
      }
    }
  }

  /// The weights in use.
  final PolicyWeights w;

  /// The seat to act.
  final int seat;

  /// True when the seat leads (no play to beat).
  final bool leading;

  /// The mover's 13 rank masks.
  final Uint8List hand;

  /// Cards the mover holds.
  final int myCount;

  /// Cards the next seat holds.
  final int nextCount;

  /// Fewest cards held by any opponent.
  late final int minOpponent;

  /// True when someone is close to going out or the mover is: high cards
  /// should be spent now rather than saved.
  late final bool urgent;

  /// The highest single the mover cannot see (-1 if none).
  int topUnseenSingle = -1;

  /// The key of the highest pair the unseen cards could make (-1 if none).
  int topUnseenPair = -1;

  /// The mover's highest card.
  int myHighest = -1;

  final _unseen = Uint8List(13);

  static int _highBit(int m) => m >= 8 ? 3 : (m >= 4 ? 2 : (m >= 2 ? 1 : 0));

  /// How many rank groups [p] splits (takes some, but not all, of a rank).
  int breaks(Play p) {
    var n = 0;
    var i = 0;
    final codes = p.codes;
    while (i < codes.length) {
      final r = codes[i] >> 2;
      var used = 0;
      while (i < codes.length && codes[i] >> 2 == r) {
        used++;
        i++;
      }
      if (used < popCount4[hand[r]]) n++;
    }
    return n;
  }

  /// How many cards of [p] come from ranks the mover holds only one of.
  int singlesUsed(Play p) {
    var n = 0;
    for (final c in p.codes) {
      if (popCount4[hand[c >> 2]] == 1) n++;
    }
    return n;
  }

  /// True when no cards the mover can't see could beat [p] (singles and
  /// pairs only; bigger plays are not checked here).
  bool unbeatable(Play p) {
    if (p.size == 1) return p.codes[0] > topUnseenSingle;
    if (p.size == 2) return p.key > topUnseenPair;
    return false;
  }

  /// The heuristic value of playing [p] now; higher is better.
  double score(Play p) {
    if (p.isPass) {
      var v = urgent ? w.passUrgent : w.pass;
      if (minOpponent == 1) v -= w.passOneCard;
      return v;
    }
    if (p.size == myCount) return 1000;
    final low = p.size == 5 ? p.codes.first >> 2 : p.topCode >> 2;
    var v = p.size * w.size;
    v -= (urgent ? w.lowUrgent : w.low) * low;
    v -= w.breaks * breaks(p);
    if (!urgent) {
      v -= w.two * p.twos;
      v -= w.ace * _aces(p);
    }
    if (leading && p.size == 5) v += w.singlesUsed * singlesUsed(p);
    final top = unbeatable(p);
    if (p.size == 1 && p.codes[0] != myHighest) {
      if (nextCount == 1) {
        v -= w.lastCard;
      } else if (leading && minOpponent == 1 && !top) {
        v -= w.oneCardLead;
      }
    }
    if (top) {
      final rest = myCount - p.size;
      if (rest <= 5 && _restIsOnePlay(p)) {
        v += w.finish;
      } else if (myCount <= w.controlHand) {
        v += w.control;
      }
    }
    return v;
  }

  static int _aces(Play p) {
    var n = 0;
    for (final c in p.codes) {
      if (c >> 2 == 11) n++;
    }
    return n;
  }

  bool _restIsOnePlay(Play p) {
    final rest = Uint8List.fromList(hand);
    for (final c in p.codes) {
      rest[c >> 2] &= ~(1 << (c & 3));
    }
    final codes = codesIn(rest);
    if (codes.isEmpty) return true;
    if (codes.length > 5) return false;
    final r0 = codes.first >> 2;
    if (codes.length <= 3) return codes.every((c) => c >> 2 == r0);
    return codes.length == 5 && _anyFive(codes);
  }

  // A five-card group with a pair-or-better structure is enough for this
  // quick check; straights and flushes are rarer and are caught by the
  // coach's search instead.
  static bool _anyFive(List<int> codes) {
    final counts = <int, int>{};
    for (final c in codes) {
      counts[c >> 2] = (counts[c >> 2] ?? 0) + 1;
    }
    final g = counts.values.toList()..sort();
    return g.length == 2 && (g[1] == 3 || g[1] == 4);
  }
}

/// The weights of the heuristic's habits. The defaults were tuned by
/// matches of one variant against three copies of the current best, 20,000
/// deals per variant: passing less (-3.75 rather than -2.5) alone raised the
/// win rate from 25% to 38%.
class PolicyWeights {
  /// A set of weights; see each field.
  const PolicyWeights({
    this.pass = -3.75,
    this.passUrgent = -6,
    this.passOneCard = 0,
    this.size = 1.5,
    this.low = 0.45,
    this.lowUrgent = 0.15,
    this.breaks = 2.5,
    this.two = 3.0,
    this.ace = 0,
    this.singlesUsed = 1.0,
    this.lastCard = 20,
    this.oneCardLead = 0,
    this.finish = 50,
    this.control = 0.75,
    this.controlHand = 6,
    this.urgentOpponent = 2,
    this.urgentSelf = 4,
  });

  /// The defaults.
  static const standard = PolicyWeights();

  /// Value of passing when a play is possible.
  final double pass;

  /// Value of passing when someone is close to going out.
  final double passUrgent;

  /// Extra cost of passing when an opponent has one card left.
  final double passOneCard;

  /// Value per card shed.
  final double size;

  /// Cost per rank of the play's height (keep high cards).
  final double low;

  /// The same, when urgent.
  final double lowUrgent;

  /// Cost per pair, triple or four split.
  final double breaks;

  /// Cost per 2 spent, when not urgent.
  final double two;

  /// Cost per ace spent, when not urgent.
  final double ace;

  /// Bonus per lone card a five-card lead clears.
  final double singlesUsed;

  /// Cost of a single other than your highest before a player on one card.
  final double lastCard;

  /// Cost of leading a beatable single while any opponent has one card.
  final double oneCardLead;

  /// Bonus for an unbeatable play that leaves one play to finish.
  final double finish;

  /// Bonus for an unbeatable play with a small hand.
  final double control;

  /// Hand size at or below which [control] applies.
  final int controlHand;

  /// An opponent with this many cards or fewer makes the position urgent.
  final int urgentOpponent;

  /// Holding this many cards or fewer makes the position urgent.
  final int urgentSelf;

  /// A copy with some weights changed, for tuning.
  PolicyWeights copyWith({
    double? pass,
    double? passUrgent,
    double? passOneCard,
    double? size,
    double? low,
    double? lowUrgent,
    double? breaks,
    double? two,
    double? ace,
    double? singlesUsed,
    double? lastCard,
    double? oneCardLead,
    double? finish,
    double? control,
    int? controlHand,
    int? urgentOpponent,
    int? urgentSelf,
  }) =>
      PolicyWeights(
        pass: pass ?? this.pass,
        passUrgent: passUrgent ?? this.passUrgent,
        passOneCard: passOneCard ?? this.passOneCard,
        size: size ?? this.size,
        low: low ?? this.low,
        lowUrgent: lowUrgent ?? this.lowUrgent,
        breaks: breaks ?? this.breaks,
        two: two ?? this.two,
        ace: ace ?? this.ace,
        singlesUsed: singlesUsed ?? this.singlesUsed,
        lastCard: lastCard ?? this.lastCard,
        oneCardLead: oneCardLead ?? this.oneCardLead,
        finish: finish ?? this.finish,
        control: control ?? this.control,
        controlHand: controlHand ?? this.controlHand,
        urgentOpponent: urgentOpponent ?? this.urgentOpponent,
        urgentSelf: urgentSelf ?? this.urgentSelf,
      );
}
