/// The coach: rates every move of a decision by playing it out.
///
/// Fight the Landlord hides cards, so there is no single right answer to
/// compute directly. The coach uses the same idea as the poker solver's
/// sampling of hands: it deals the cards it can't see in many ways that fit
/// everything known (sampler.dart), plays each candidate move on each deal
/// and plays the rest of the deal out, then averages the team's results.
/// - Most deals are played out with the rule-of-thumb player (policy.dart):
///   fast and decent, so thousands fit in a fraction of a second.
/// - Once few cards are left, each deal is solved exactly instead
///   (solver.dart), so endgames get perfect answers per deal.
/// - When the hidden cards are all known (the landlord holds only shown
///   kitty cards, say), each move is solved exactly. A peasant's win is
///   then proven; a loss only when the landlord could win without seeing
///   how the peasants' cards are split (see [DdzBlindLandlordCheck]).
/// - Moves that are clearly worse stop getting deals early (sequential
///   halving), so the budget goes where the choice is close. The moves
///   that lasted longest rank first: a move dropped early keeps its rough
///   early average and never outranks one that survived it.
///
/// "GTO" is the app's label for this in the hidden-card games: the coach's
/// moves are its best estimate, not a proven equilibrium (the two peasants
/// can't share their cards, so none is known for this game).
library;

import 'dart:math';

import 'cards.dart';
import 'game.dart';
import 'hand_plan.dart';
import 'play_gen.dart';
import 'plays.dart';
import 'policy.dart';
import 'sampler.dart';
import 'sim.dart';
import 'solver.dart';
import 'view.dart';

/// What the coach maximises.
enum DdzObjective {
  /// The chance the seat's side wins the deal.
  winChance,

  /// The points the seat expects to win (bombs and spring count).
  points,
}

/// How much work one analysis may do. The defaults answer a decision in
/// well under a second on a PC; the app can lower them on phones.
class DdzBudget {
  const DdzBudget({
    this.rollouts = 2400,
    this.maxTime,
    this.maxCandidates = 20,
    this.exactCards = 16,
    this.solverNodes = 20000,
    this.exactNodeBudget = 300000,
    this.objective = DdzObjective.winChance,
    this.poolSize = 300,
    this.mismatch = 0.3,
    this.doubleDummy = false,
  });

  /// Deals played out in total, over all candidate moves. Work, not time,
  /// so the same seed always gives the same answer.
  final int rollouts;

  /// Optional time limit; stops early (and then answers can vary).
  final Duration? maxTime;

  /// Moves rated at most; the rest (rare: leads with many kicker choices)
  /// are left out after a quick rule-of-thumb sort.
  final int maxCandidates;

  /// Deals with at most this many cards left in all hands are solved
  /// exactly instead of played out.
  final int exactCards;

  /// The exact solver gives up on a deal after this many positions and
  /// plays it out instead.
  final int solverNodes;

  /// Positions the exact solver may search in one analysis, all deals
  /// together; past it, deals are played out. Keeps endgames as fast as
  /// the rest of the deal.
  final int exactNodeBudget;

  final DdzObjective objective;

  /// Guessed deals weighed against the history per analysis; the play-outs
  /// draw from them by weight (see [DealPool]).
  final int poolSize;

  /// How much less likely a guess becomes for each past move it doesn't
  /// explain (see [dealWeight]); 1 turns the inference off.
  final double mismatch;

  /// Whether the play-outs' safety checks see the guessed hands (see
  /// [DdzSituation.hands]).
  final bool doubleDummy;

  /// The Medium bot's budget.
  static const medium = DdzBudget(rollouts: 360, maxCandidates: 8, exactCards: 12);

  /// The Hard bot's budget.
  static const hard = DdzBudget(rollouts: 1600, maxCandidates: 16, exactCards: 16);

  /// A copy with some values changed.
  DdzBudget copyWith({
    int? rollouts,
    Duration? maxTime,
    int? maxCandidates,
    int? exactCards,
    DdzObjective? objective,
    int? poolSize,
    double? mismatch,
    bool? doubleDummy,
  }) => DdzBudget(
    rollouts: rollouts ?? this.rollouts,
    maxTime: maxTime ?? this.maxTime,
    maxCandidates: maxCandidates ?? this.maxCandidates,
    exactCards: exactCards ?? this.exactCards,
    solverNodes: solverNodes,
    exactNodeBudget: exactNodeBudget,
    objective: objective ?? this.objective,
    poolSize: poolSize ?? this.poolSize,
    mismatch: mismatch ?? this.mismatch,
    doubleDummy: doubleDummy ?? this.doubleDummy,
  );
}

/// Short reasons the app turns into one-line explanations (in the player's
/// language). A candidate can have several.
enum DdzReason {
  /// Plays your last cards.
  goesOut,

  /// Leaves one play (or only safe plays) to finish.
  finishesNext,

  /// Passing lets your partner's play win the trick.
  partnerWinning,

  /// Doesn't spend or break up your bomb or rocket.
  keepsBomb,

  /// Breaks up your bomb or rocket (plays some of its cards without the
  /// rest).
  breaksBomb,

  /// Spends a bomb (doubles the stake).
  usesBomb,

  /// Spends the rocket (doubles the stake).
  usesRocket,

  /// Your partner has one card left: lead your smallest solo.
  leadsSmallForPartner,

  /// Nobody on the other side can beat it (from the card count).
  opponentsCantBeat,

  /// Keeps your 2s or jokers for later.
  keepsHighCards,

  /// Breaks up a pair, trio or chain of your plan.
  breaksGroup,

  /// Gets rid of five or more cards at once.
  shedsMany,

  /// An opponent is close to going out: this stops them.
  stopsOpponent,

  /// An opponent with one or two cards could follow this.
  opponentCanFollow,

  /// Beats an opponent's play and takes the lead.
  takesLead,

  /// Gets rid of your weakest group while you have the lead.
  leadsWeakGroup,

  /// Waits instead of spending cards on this trick.
  waits,

  // Bidding.

  /// The hand is strong enough to play alone.
  strongHand,

  /// The hand is too weak to play alone.
  weakHand,

  /// You hold the rocket.
  holdsRocket,

  /// You hold a bomb.
  holdsBomb,
}

/// One rated move.
class DdzCandidate {
  DdzCandidate({
    required this.move,
    required this.winChance,
    required this.expectedPoints,
    required this.samples,
    required this.proven,
    required this.reasons,
  });

  final DdzMove move;

  /// Chance (0 to 1) that the seat's side wins after this move.
  final double winChance;

  /// Points the seat expects to win after this move (negative: lose).
  final double expectedPoints;

  /// Deals this move was played on.
  final int samples;

  /// True when the result is certain: [winChance] is then exactly 0 or 1.
  /// That needs the hidden cards all known and the endgame solved exactly,
  /// and the winning side able to play the winning line with what it can
  /// see. A peasant's win always qualifies (both peasants can then work out
  /// every hand); a peasant's loss only when the landlord wins without
  /// seeing how the peasants' cards are split. A win chance of 0 that isn't
  /// proven means the landlord wins only if he guesses that split right.
  final bool proven;

  /// Why this move is good or bad, best first.
  final List<DdzReason> reasons;

  @override
  String toString() =>
      '$move: win ${(winChance * 100).toStringAsFixed(1)}%, ${expectedPoints.toStringAsFixed(2)} pts (n=$samples${proven ? ', proven' : ''}) ${reasons.map((r) => r.name).join(',')}';
}

/// The coach's answer for one decision.
class DdzAnalysis {
  DdzAnalysis({
    required this.seat,
    required this.candidates,
    required this.legalMoveCount,
    required this.rollouts,
    required this.elapsed,
    required this.cardCount,
    required this.objective,
  });

  final int seat;

  /// Rated moves, best first.
  final List<DdzCandidate> candidates;

  /// How many legal moves there were (more than [candidates] when some
  /// were left out of a big lead).
  final int legalMoveCount;

  /// Deals played out or solved.
  final int rollouts;
  final Duration elapsed;

  /// The card counter, for the app.
  final DdzCardCount cardCount;
  final DdzObjective objective;

  /// The coach's choice.
  DdzCandidate get best => candidates.first;

  /// The rating of [move], or null when it wasn't rated.
  DdzCandidate? candidateFor(DdzMove move) {
    for (final c in candidates) {
      if (c.move == move) return c;
    }
    return null;
  }

  /// How much worse [move] is than the best, in the objective's unit (win
  /// chance 0 to 1, or points), for grading. Null when not rated. Never
  /// below 0: a move dropped early by sequential halving can show a higher
  /// rough average than [best] (from fewer deals), and that is no reason
  /// to call the best move a mistake.
  double? lossOf(DdzMove move) {
    final c = candidateFor(move);
    if (c == null) return null;
    final d = objective == DdzObjective.winChance
        ? best.winChance - c.winChance
        : best.expectedPoints - c.expectedPoints;
    return max(0, d);
  }
}

/// Rates decisions. Stateless apart from its settings; [analyze] takes the
/// random source, so a seed repeats an analysis exactly.
class DdzCoach {
  const DdzCoach({this.budget = const DdzBudget(), this.policy = const HeuristicPolicy()});

  final DdzBudget budget;
  final HeuristicPolicy policy;

  /// Rates every legal move of [view] (it must be the seat's turn).
  ///
  /// A big lead can have more legal moves than [DdzBudget.maxCandidates],
  /// and the ones a quick sort leaves out get no rating. [include] is a
  /// legal move rated even so: the app grades a move the player made that
  /// the first answer left out by asking again with it included. Throws
  /// [ArgumentError] when [include] isn't legal.
  DdzAnalysis analyze(DdzView view, {Random? random, DdzBudget? budget, DdzMove? include}) {
    final b = budget ?? this.budget;
    final rnd = random ?? Random(0);
    if (!view.myTurn) throw StateError('Not seat ${view.seat}\'s turn');
    if (include != null && !view.legalMoves.contains(include)) {
      throw ArgumentError.value(include, 'include', 'not a legal move');
    }
    // Bidding rates every legal bid anyway.
    return view.phase == DdzPhase.bidding ? _analyzeBid(view, b, rnd) : _analyzePlay(view, b, rnd, include);
  }

  // ---------------------------------------------------------------- play

  DdzAnalysis _analyzePlay(DdzView view, DdzBudget b, Random rnd, DdzMove? include) {
    final watch = Stopwatch()..start();
    final sampler = DdzSampler(view);
    final legal = view.legalMoves;
    final situation = situationOf(view, sampler.count);
    var moves = [for (final m in legal) m is DdzPlay ? m.play : null];
    // The included move (null stands for a pass) survives every cut.
    final kept = include is DdzPlay ? include.play : null;
    List<Play?> prune(List<Play?> all) {
      final cut = _prune(situation, all, b.maxCandidates);
      return include == null || cut.contains(kept) ? cut : [...cut, kept];
    }

    // A known endgame rates every move; otherwise big leads are cut down.
    // (Only a peasant can know every hand: the landlord never sees how the
    // peasants' cards are split.)
    final peasant = view.landlord != null && view.seat != view.landlord;
    final known = peasant && sampler.isUnique && _cardsLeft(view) <= 26;
    if (moves.length > (known ? 64 : b.maxCandidates)) moves = prune(moves);

    var n = moves.length;
    var wins = List<double>.filled(n, 0);
    var points = List<double>.filled(n, 0);
    var samples = List<int>.filled(n, 0);
    // How many halving rounds each move took part in: the finalists rank
    // above moves dropped earlier, whatever their averages say.
    var survived = List<int>.filled(n, 0);
    var proven = List<bool>.filled(n, false);
    var solvedKnown = false;
    var rollouts = 0;
    final seat = view.seat;

    if (known) {
      // Every hidden card is known: solve each move exactly.
      final sim = sampler.sim(rnd);
      final solver = DdzEndgameSolver(nodeLimit: b.exactNodeBudget);
      // A sixth of the exact budget keeps the worst known endgame near
      // 0.4 s in JavaScript; past it a loss is simply left unproven.
      final blind = DdzBlindLandlordCheck(nodeLimit: b.exactNodeBudget ~/ 6);
      // What the landlord knows of the peasants' cards: the ones everyone
      // has seen in their hands (the face-up card).
      final seen = [
        for (var s = 0; s < 3; s++) countsOfIds(view.visibleIn(s)),
      ];
      var allSolved = true;
      for (var i = 0; i < n; i++) {
        final s = sim.copy()..apply(moves[i]);
        // The move may play a seen card: what is left of it in the hand.
        final known = [
          for (var seat = 0; seat < 3; seat++)
            [for (var r = 0; r < Rank.count; r++) min(seen[seat][r], s.hands[seat][r])],
        ];
        final lordWins = solver.landlordWins(s);
        if (lordWins == null || solver.totalNodes > b.exactNodeBudget * 2) {
          allSolved = false;
          break;
        }
        // The solver let the landlord see every card. The peasants' win
        // holds (they do see every hand); the landlord's needs checking
        // against the splits of the peasants' cards he can't tell apart.
        proven[i] = !lordWins || blind.landlordWins(s.copy(), known: known) == true;
        _decide(s, lordWins);
        wins[i] = s.wonBy(seat) ? 1 : 0;
        points[i] = _pointsOf(s, seat);
        samples[i] = 1;
        rollouts++;
      }
      solvedKnown = allSolved;
    }

    if (!solvedKnown) {
      if (moves.length > b.maxCandidates + (include == null ? 0 : 1)) moves = prune(moves);
      n = moves.length;
      wins = List<double>.filled(n, 0);
      points = List<double>.filled(n, 0);
      samples = List<int>.filled(n, 0);
      survived = List<int>.filled(n, 0);
      proven = List<bool>.filled(n, false);
      // Sequential halving: equal deals for every surviving move per round,
      // then keep the better half.
      var alive = List<int>.generate(n, (i) => i);
      final rounds = n <= 1 ? 1 : (log(n) / ln2).ceil();
      final perRound = b.rollouts ~/ rounds;
      final deadline = b.maxTime;
      final pool = DealPool(sampler, rnd, size: b.poolSize, policy: policy, mismatch: b.mismatch);
      // The exact solver is switched off for the rest of the analysis once
      // it has given up twice (the endgame is bigger than it looks) or used
      // its share of the work.
      var exactAborts = 0;
      var exactNodes = 0;
      outer:
      for (var round = 0; round < rounds; round++) {
        final deals = max(1, perRound ~/ alive.length);
        for (final i in alive) {
          survived[i]++;
        }
        for (var d = 0; d < deals; d++) {
          if (deadline != null && watch.elapsed > deadline && rollouts > 0) break outer;
          final base = simFromHands(view, pool.draw(rnd));
          final solver = exactAborts < 2 && exactNodes < b.exactNodeBudget && _cardsLeft(view) <= b.exactCards + 4
              ? DdzEndgameSolver(nodeLimit: b.solverNodes)
              : null;
          for (final i in alive) {
            final s = base.copy()..apply(moves[i]);
            if (!_finish(s, solver, b)) exactAborts++;
            wins[i] += s.wonBy(seat) ? 1 : 0;
            points[i] += _pointsOf(s, seat);
            samples[i]++;
            rollouts++;
          }
          if (solver != null) exactNodes += solver.totalNodes;
        }
        if (alive.length <= 1) continue;
        double score(int i) => samples[i] == 0
            ? double.negativeInfinity
            : (b.objective == DdzObjective.winChance ? wins[i] : points[i]) / samples[i];
        double other(int i) => samples[i] == 0
            ? double.negativeInfinity
            : (b.objective == DdzObjective.winChance ? points[i] : wins[i]) / samples[i];
        // Ties are broken as the final ranking breaks them (the other
        // measure, then the bigger play), so a tie never drops the move
        // that would have ranked first: going out beats an equally sure
        // small lead.
        alive.sort((x, y) {
          var d = score(y).compareTo(score(x));
          if (d == 0) d = other(y).compareTo(other(x));
          if (d == 0) d = (moves[y]?.size ?? 0) - (moves[x]?.size ?? 0);
          return d != 0 ? d : x - y;
        });
        if (round < rounds - 1) alive = alive.sublist(0, (alive.length + 1) ~/ 2);
      }
    }

    final rated = <(DdzCandidate, int)>[
      for (var i = 0; i < n; i++)
        (
          DdzCandidate(
            move: moves[i] == null ? const DdzPass() : DdzPlay(moves[i]!),
            winChance: samples[i] == 0 ? 0 : wins[i] / samples[i],
            expectedPoints: samples[i] == 0 ? 0 : points[i] / samples[i],
            samples: samples[i],
            proven: proven[i],
            reasons: reasonsFor(situation, moves[i]),
          ),
          survived[i],
        ),
    ];
    // Moves that lasted more halving rounds first; within a round's
    // leavers (or the finalists), by value. Each group's averages are the
    // ones it was judged on, so this is the order halving decided.
    rated.sort((x, y) {
      final d = y.$2.compareTo(x.$2);
      return d != 0 ? d : _compareCandidates(x.$1, y.$1, b.objective);
    });
    final candidates = [for (final r in rated) r.$1];
    return DdzAnalysis(
      seat: seat,
      candidates: candidates,
      legalMoveCount: legal.length,
      rollouts: rollouts,
      elapsed: watch.elapsed,
      cardCount: sampler.count,
      objective: b.objective,
    );
  }

  static int _cardsLeft(DdzView view) => view.handSizes.fold(0, (a, b) => a + b);

  /// Plays [s] to the end: exactly when small enough, else with the policy.
  /// Returns false when the exact solver gave up on it.
  bool _finish(DdzSim s, DdzEndgameSolver? solver, DdzBudget b) {
    var ok = true;
    while (!s.over) {
      if (solver != null && s.sizes[0] + s.sizes[1] + s.sizes[2] <= b.exactCards) {
        final lordWins = solver.landlordWins(s);
        if (lordWins != null) {
          _decide(s, lordWins);
          return ok;
        }
        solver = null;
        ok = false;
      }
      s.apply(policy.choose(simSituation(s, doubleDummy: b.doubleDummy)));
    }
    return ok;
  }

  static double _pointsOf(DdzSim s, int seat) => s.pointsFor(seat).toDouble();

  /// Marks the solver's verdict as the result without playing the line
  /// out. The points then count the bombs played so far, and a spring when
  /// the losing side hasn't played yet (bombs the winning line might still
  /// play are not counted).
  static void _decide(DdzSim s, bool lordWins) {
    if (s.over) return;
    s.winner = lordWins ? s.landlord : (s.landlord + 1) % 3;
  }

  /// Keeps the [keep] most promising moves by the rule-of-thumb player:
  /// its own choice, passing, and the moves leaving the best hand plan.
  List<Play?> _prune(DdzSituation s, List<Play?> moves, int keep) {
    final choice = policy.choose(s);
    final scored = <(Play?, double)>[];
    for (final m in moves) {
      double v;
      if (m == null) {
        v = planHand(s.hand, s.rules).score - 3;
      } else {
        final rest = List<int>.of(s.hand);
        for (final r in m.ranks) {
          rest[r]--;
        }
        v = m.size == s.handSizes[s.seat] ? 1e9 : handScore(rest);
        if (m.isBombLike) v -= 10;
      }
      if (m == choice) v = 1e12;
      scored.add((m, v));
    }
    scored.sort((a, b) {
      final d = b.$2.compareTo(a.$2);
      return d != 0 ? d : moves.indexOf(a.$1) - moves.indexOf(b.$1);
    });
    return [for (final e in scored.take(keep)) e.$1];
  }

  static void _sortCandidates(List<DdzCandidate> c, DdzObjective objective) =>
      c.sort((a, b) => _compareCandidates(a, b, objective));

  /// Best first: by the objective, then the other measure; a loss the
  /// landlord must guess his way to ranks above a proven one; then bigger
  /// plays (finish sooner) and the move tried most.
  static int _compareCandidates(DdzCandidate a, DdzCandidate b, DdzObjective objective) {
    final primary = objective == DdzObjective.winChance
        ? b.winChance.compareTo(a.winChance)
        : b.expectedPoints.compareTo(a.expectedPoints);
    if (primary != 0) return primary;
    if (a.proven != b.proven && a.winChance == 0 && b.winChance == 0) return a.proven ? 1 : -1;
    final secondary = objective == DdzObjective.winChance
        ? b.expectedPoints.compareTo(a.expectedPoints)
        : b.winChance.compareTo(a.winChance);
    if (secondary != 0) return secondary;
    // Equal results: finish sooner (more cards at once), then the move
    // that was tried most.
    final sizes = _sizeOf(b.move).compareTo(_sizeOf(a.move));
    if (sizes != 0) return sizes;
    final tried = b.samples.compareTo(a.samples);
    return tried != 0 ? tried : a.move.encode().compareTo(b.move.encode());
  }

  static int _sizeOf(DdzMove m) => m is DdzPlay ? m.play.size : 0;

  // ------------------------------------------------------------- bidding

  DdzAnalysis _analyzeBid(DdzView view, DdzBudget b, Random rnd) {
    final watch = Stopwatch()..start();
    final est = estimateBidding(view, rnd, deals: max(40, b.rollouts ~/ 6));
    final reasons = _bidReasons(view.counts, est);
    final candidates = <DdzCandidate>[];
    for (final m in view.legalMoves) {
      final (stakeIfLord, becomesLord) = switch (m) {
        DdzBid(:final points) => (points, points > 0),
        DdzCall(:final yes) => (1, yes),
        DdzRob(:final yes) => (view.stake * 2, yes),
        _ => (0, false),
      };
      final peasantStake = max(1, view.stake);
      candidates.add(
        DdzCandidate(
          move: m,
          winChance: becomesLord ? est.landlordWin : est.peasantWin,
          expectedPoints: becomesLord
              ? stakeIfLord * est.landlordPointsPerStake
              : peasantStake * est.peasantPointsPerStake,
          samples: est.deals,
          proven: false,
          reasons: becomesLord ? reasons : [if (reasons.first == DdzReason.weakHand) DdzReason.weakHand],
        ),
      );
    }
    // Bids are judged on points: playing alone at a higher stake only pays
    // when the hand wins often enough.
    _sortCandidates(candidates, DdzObjective.points);
    return DdzAnalysis(
      seat: view.seat,
      candidates: candidates,
      legalMoveCount: view.legalMoves.length,
      rollouts: est.deals * 2,
      elapsed: watch.elapsed,
      cardCount: DdzCardCount.of(view),
      objective: DdzObjective.points,
    );
  }

  /// Plays sampled deals with this seat as the landlord (taking a random
  /// kitty) and as a peasant (the next seat taking it), all with the
  /// rule-of-thumb player, to see how the hand does either way.
  BidEstimate estimateBidding(DdzView view, Random rnd, {int deals = 200}) {
    final sampler = DdzSampler(view);
    final seat = view.seat;
    var lordWins = 0, lordPoints = 0.0, peasantWins = 0, peasantPoints = 0.0;
    for (var d = 0; d < deals; d++) {
      final hands = sampler.deal(rnd);
      final kitty = hands[3];
      // As landlord.
      final mine = [for (var r = 0; r < Rank.count; r++) hands[seat][r] + kitty[r]];
      final asLord = DdzSim(
        rules: view.rules,
        hands: [for (var s = 0; s < 3; s++) s == seat ? mine : List<int>.of(hands[s])],
        landlord: seat,
        toAct: seat,
        stake: 1,
      );
      _finish(asLord, null, budget);
      if (asLord.wonBy(seat)) lordWins++;
      lordPoints += asLord.pointsFor(seat);
      // As a peasant: the next seat that could still win the auction.
      final lord = (seat + 1 + d % 2) % 3;
      final theirs = [for (var r = 0; r < Rank.count; r++) hands[lord][r] + kitty[r]];
      final asPeasant = DdzSim(
        rules: view.rules,
        hands: [for (var s = 0; s < 3; s++) s == lord ? theirs : List<int>.of(hands[s])],
        landlord: lord,
        toAct: lord,
        stake: 1,
      );
      _finish(asPeasant, null, budget);
      if (asPeasant.wonBy(seat)) peasantWins++;
      peasantPoints += asPeasant.pointsFor(seat);
    }
    return BidEstimate(
      deals: deals,
      landlordWin: lordWins / deals,
      landlordPointsPerStake: lordPoints / deals,
      peasantWin: peasantWins / deals,
      peasantPointsPerStake: peasantPoints / deals,
    );
  }

  /// "Strong" means the hand expects more points alone than as a peasant.
  static List<DdzReason> _bidReasons(List<int> counts, BidEstimate est) => [
    est.landlordPointsPerStake > est.peasantPointsPerStake ? DdzReason.strongHand : DdzReason.weakHand,
    if (counts[Rank.littleJoker] > 0 && counts[Rank.bigJoker] > 0) DdzReason.holdsRocket,
    if ([for (var r = 0; r <= Rank.two; r++) counts[r]].contains(4)) DdzReason.holdsBomb,
  ];

  // ------------------------------------------------------------- reasons

  /// Short reasons for playing [move] (null = pass) in situation [s].
  List<DdzReason> reasonsFor(DdzSituation s, Play? move) {
    final out = <DdzReason>[];
    final hand = s.hand;
    final size = s.handSizes[s.seat];
    final current = s.current;
    final fromPartner = current != null && !s.isLandlord && s.currentPlayer == s.partner;
    final holdsBomb = _bombRanks(hand).isNotEmpty;
    final minOpp = s.minOpponentSize;

    if (move == null) {
      if (fromPartner) out.add(DdzReason.partnerWinning);
      if (current != null && canBeat(hand, current, s.rules)) {
        if (holdsBomb && !_canBeatWithoutBombs(hand, current, s)) out.add(DdzReason.keepsBomb);
        if (hand[Rank.two] + hand[Rank.littleJoker] + hand[Rank.bigJoker] > 0) out.add(DdzReason.keepsHighCards);
        if (!fromPartner) out.add(DdzReason.waits);
      }
      return out;
    }
    if (move.size == size) return [DdzReason.goesOut];
    final rest = List<int>.of(hand);
    for (final r in move.ranks) {
      rest[r]--;
    }
    final plan = planHand(rest, s.rules);
    final afterSituation = DdzSituation(
      seat: s.seat,
      landlord: s.landlord,
      hand: rest,
      handSizes: [for (var i = 0; i < 3; i++) i == s.seat ? size - move.size : s.handSizes[i]],
      current: null,
      currentPlayer: -1,
      unseen: s.unseen,
      rules: s.rules,
    );
    final unsafe = plan.plays.where((p) => opponentsMightBeat(p, afterSituation)).length;
    if (plan.turns == 1 || unsafe == 0) out.add(DdzReason.finishesNext);
    if (move.isRocket) out.add(DdzReason.usesRocket);
    if (move.isBomb) out.add(DdzReason.usesBomb);
    if (!move.isBombLike && holdsBomb) {
      // Kept only if every bomb (and the rocket) is still whole after the
      // move; taking cards out of one is breaking it, not keeping it.
      final kept = _bombRanks(rest);
      out.add(_bombRanks(hand).every(kept.contains) ? DdzReason.keepsBomb : DdzReason.breaksBomb);
    }
    if (current == null && !s.isLandlord && s.handSizes[s.partner] == 1 && move.type == PlayType.solo) {
      var lowest = 0;
      while (hand[lowest] == 0) {
        lowest++;
      }
      if (move.rank == lowest) out.add(DdzReason.leadsSmallForPartner);
    }
    if (!opponentsMightBeat(move, s)) out.add(DdzReason.opponentsCantBeat);
    final opponentBehind = current != null && s.currentPlayer >= 0 && !_sameTeam(s, s.currentPlayer);
    if (opponentBehind && minOpp <= 3) out.add(DdzReason.stopsOpponent);
    if (current == null &&
        minOpp <= 2 &&
        move.size <= minOpp &&
        (move.type == PlayType.solo || move.type == PlayType.pair) &&
        opponentsMightBeat(move, s)) {
      out.add(DdzReason.opponentCanFollow);
    }
    if (move.size >= 5) out.add(DdzReason.shedsMany);
    final before = planHand(hand, s.rules);
    if (!move.isBombLike && !before.plays.contains(move)) out.add(DdzReason.breaksGroup);
    if (current == null && before.plays.isNotEmpty) {
      final normal = before.plays.where((p) => !p.isBombLike).toList();
      if (normal.isNotEmpty) {
        final weakest = normal.reduce(
          (a, b) => groupValue(a.type, a.rank, a.length) <= groupValue(b.type, b.rank, b.length) ? a : b,
        );
        if (weakest == move) out.add(DdzReason.leadsWeakGroup);
      }
    }
    if (opponentBehind && !out.contains(DdzReason.stopsOpponent)) out.add(DdzReason.takesLead);
    if (move.ranks.every((r) => r < Rank.two) && hand[Rank.two] + hand[Rank.littleJoker] + hand[Rank.bigJoker] > 0) {
      if (current != null) out.add(DdzReason.keepsHighCards);
    }
    return out;
  }

  /// The ranks of the bombs in [hand], with the little joker standing for
  /// the rocket.
  static List<int> _bombRanks(List<int> hand) => [
    for (var r = 0; r <= Rank.two; r++)
      if (hand[r] == 4) r,
    if (hand[Rank.littleJoker] > 0 && hand[Rank.bigJoker] > 0) Rank.littleJoker,
  ];

  static bool _sameTeam(DdzSituation s, int other) => other == s.seat || (other != s.landlord && !s.isLandlord);

  static bool _canBeatWithoutBombs(List<int> hand, Play current, DdzSituation s) {
    for (final p in beatingPlays(hand, current, s.rules)) {
      if (!p.isBombLike) return true;
    }
    return false;
  }
}

/// How a hand does as landlord and as a peasant, from sampled play-outs.
class BidEstimate {
  const BidEstimate({
    required this.deals,
    required this.landlordWin,
    required this.landlordPointsPerStake,
    required this.peasantWin,
    required this.peasantPointsPerStake,
  });
  final int deals;

  /// Chance of winning as the landlord.
  final double landlordWin;

  /// Average points as landlord per point of stake (×2 for the landlord,
  /// bombs and spring included).
  final double landlordPointsPerStake;

  /// Chance of winning as a peasant.
  final double peasantWin;
  final double peasantPointsPerStake;
}

/// The policy's view of a seat's decision, from a [DdzView].
DdzSituation situationOf(DdzView view, [DdzCardCount? count]) {
  final c = count ?? DdzCardCount.of(view);
  return DdzSituation(
    seat: view.seat,
    landlord: view.landlord ?? -1,
    hand: view.counts,
    handSizes: view.handSizes,
    current: view.current,
    currentPlayer: view.currentPlayer ?? -1,
    unseen: c.unseen,
    rules: view.rules,
  );
}

/// The policy's view of the seat to act in a [DdzSim]. With [doubleDummy]
/// its safety checks see the other hands (see [DdzSituation.hands]).
DdzSituation simSituation(DdzSim s, {bool doubleDummy = false}) {
  final seat = s.toAct;
  return DdzSituation(
    seat: seat,
    landlord: s.landlord,
    hand: s.hands[seat],
    handSizes: s.sizes,
    current: s.current,
    currentPlayer: s.currentPlayer,
    unseen: s.unseenBy(seat),
    rules: s.rules,
    hands: doubleDummy ? s.hands : null,
  );
}
