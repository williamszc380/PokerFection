import 'dart:math';
import 'dart:typed_data';

import '../../engine/actions.dart';
import '../../engine/events.dart';
import '../../engine/poker_hand.dart';
import '../hand_classes.dart';
import '../spot_strategy.dart';
import 'preflop_advisor.dart';
import 'preflop_solver.dart';
import 'preflop_tree.dart';

/// Solves the user's subgame: the game from [PreflopSpec.history] on,
/// starting from everyone's range there (players x 169 weights, or null
/// when nobody has acted yet except by folding).
typedef PreflopSubgameSolve = Future<PreflopSolution> Function(PreflopSpec spec, Float64List? ranges);

/// Follows one hand before the flop and answers "what does GTO do here?".
///
/// The bots' strategies come from the solved whole game, the
/// "blueprint", where everyone chooses from a small menu. At each of the
/// user's decisions a subgame is solved, starting from everyone's range at
/// that point, in which the user may take every legal action: the user's
/// answer comes from it, and so do the bots' replies to whatever the user
/// chooses (until the user's next decision).
class PreflopTracker {
  PreflopTracker({
    required this.blueprint,
    required this.solveSubgame,
    required this.heroSeat,
    this.handNumber,
  });

  /// The whole game, solved with the bots' menu for everyone.
  final PreflopAdvisor blueprint;
  final PreflopSubgameSolve solveSubgame;

  /// The user's seat.
  final int heroSeat;

  /// The hand this tracker follows ([PokerHand.handNumber]), when known.
  /// Its answers belong to that hand only: another hand at the same point
  /// of the betting may hold other cards and stacks.
  final int? handNumber;

  /// The user's subgames in this hand, by how many preflop actions came
  /// before them.
  final Map<int, PreflopAdvisor> _subgames = {};
  final Map<int, Future<PreflopAdvisor>> _pending = {};

  /// Subgames let go by [dropSubgames]: a walk that would enter one can't
  /// be followed any more.
  final Set<int> _dropped = {};

  /// Why there's no answer (the solve failed), if there isn't one. Once set,
  /// no more subgames are solved in this hand: each starts from the ranges
  /// the earlier ones give, and without one of those its answer would be
  /// wrong rather than missing.
  NoAnswer? unavailable;

  /// Starts solving the user's subgame if it's their turn before the flop
  /// (at most once per decision). Completes when it is solved, or at once
  /// when the hand has no more answers ([unavailable]).
  Future<void> prepare(PokerHand hand) async {
    if (unavailable != null) return;
    if (hand.isOver || hand.street != Street.preflop || hand.toAct != heroSeat) return;
    final history = historyOf(hand);
    final k = history.length;
    if (_subgames.containsKey(k)) return;
    final pending = _pending[k] ??= _solve(hand, history);
    try {
      final subgame = await pending;
      if (!_dropped.contains(k)) _subgames[k] = subgame;
    } on _OffTheSolvedLines {
      // Someone made a move the solved game doesn't have (online, a person can).
      unavailable ??= NoAnswer.leftSolvedLines;
    } on Object {
      unavailable ??= NoAnswer.solveFailed;
    } finally {
      _pending.remove(k);
    }
  }

  /// Lets go of the solved subgames (and those being solved) except the
  /// ones in [keep], each known by how many preflop actions came before it
  /// (see [historyOf]): they take memory, up to ~100 MB each at 8 players.
  /// The answers kept stay right. Anything that would need a dropped
  /// subgame gets no answer, never one worked out without it: once one is
  /// dropped, no more subgames or streets are solved in this hand
  /// ([unavailable] becomes [NoAnswer.notNeeded], which nobody is shown),
  /// and ranges and moves past it read as off the solved lines. So with an
  /// answer after the flop still to come, keep every subgame: its ranges
  /// start from all of them.
  void dropSubgames({Set<int> keep = const {}}) {
    for (final k in [..._subgames.keys, ..._pending.keys]) {
      if (keep.contains(k)) continue;
      _subgames.remove(k);
      _dropped.add(k);
    }
    if (_dropped.isNotEmpty) unavailable ??= NoAnswer.notNeeded;
  }

  /// Whether following [hand] would enter a subgame let go of.
  bool _trimmedAt(PokerHand hand) {
    if (_dropped.isEmpty) return false;
    final k = historyOf(hand).length;
    return _dropped.any((d) => d <= k);
  }

  /// Whether the user's current decision is still being solved.
  bool isSolving(PokerHand hand) {
    if (hand.street != Street.preflop || hand.toAct != heroSeat || unavailable != null) return false;
    return !_subgames.containsKey(historyOf(hand).length);
  }

  Future<PreflopAdvisor> _solve(PokerHand hand, List<PreflopAction> history) async {
    final spec = specAt(hand, heroSeat: heroSeat, history: history);
    // Folds (or nothing) so far: every player still in has their full
    // range, and the solve can be shared (and done ahead of time).
    final onlyFolds = history.every((a) => a.move == PreflopMove.fold);
    Float64List? ranges;
    if (!onlyFolds) {
      final walk = _walk(hand);
      if (walk == null) throw const _OffTheSolvedLines();
      ranges = Float64List(hand.playerCount * handClassCount)..fillRange(0, hand.playerCount * handClassCount, 1);
      for (var seat = 0; seat < hand.playerCount; seat++) {
        // A folded player's range doesn't matter; it stays full.
        if (hand.isFolded(seat)) continue;
        final p = PreflopAdvisor.orderOf(hand, seat);
        ranges.setRange(p * handClassCount, (p + 1) * handClassCount, walk.rangeOf(p));
      }
    }
    return PreflopAdvisor(await solveSubgame(spec, ranges));
  }

  /// Every preflop action of [hand] so far, in the solver's terms. Its
  /// length is how a decision's subgame is known (see [dropSubgames]).
  static List<PreflopAction> historyOf(PokerHand hand) => [
        for (final e in hand.log)
          if (e is ActionTaken && e.street == Street.preflop) PreflopAdvisor.treeAction(e),
      ];

  /// [hand]'s preflop game from where it is now: its stacks and blinds,
  /// with [history] (by default every preflop action so far, see
  /// [historyOf]) already played. With [heroSeat], it is the user's
  /// subgame there; without, just the betting so far, which is all
  /// [PreflopTree.botMenuAt] needs.
  static PreflopSpec specAt(PokerHand hand, {int? heroSeat, List<PreflopAction>? history}) =>
      PreflopAdvisor.specFor(
        stacksBySeat: [for (var s = 0; s < hand.playerCount; s++) hand.startingStackOf(s)],
        buttonSeat: hand.buttonSeat,
        smallBlind: hand.smallBlind,
        bigBlind: hand.bigBlind,
        ante: hand.ante,
        raiseRule: hand.raiseRule,
        heroSeat: heroSeat,
        history: history ?? historyOf(hand),
      );

  /// Where the hand is in the solved games: every preflop action so far
  /// (with the game and decision it was taken at), then the game and node
  /// it is at now. Null once the hand has left the solved lines.
  ///
  /// A subgame ends when the user folds; the others play on in the
  /// blueprint, as long as the hand still fits it.
  _Walk? _walk(PokerHand hand) {
    if (_trimmedAt(hand)) return null;
    final walk = _walkThrough(hand, useSubgames: true);
    if (walk != null && (walk.node is PreflopDecision || hand.street != Street.preflop || hand.isOver)) return walk;
    return _walkThrough(hand, useSubgames: false) ?? walk;
  }

  _Walk? _walkThrough(PokerHand hand, {required bool useSubgames}) {
    var game = blueprint;
    PreflopNode node = game.tree.root;
    final steps = <_Step>[];
    void enterSubgame() {
      final subgame = useSubgames ? _subgames[steps.length] : null;
      if (subgame == null) return;
      game = subgame;
      node = subgame.tree.root;
    }

    for (final e in hand.log) {
      if (e is! ActionTaken || e.street != Street.preflop) continue;
      enterSubgame();
      final at = node;
      if (at is! PreflopDecision || PreflopAdvisor.orderOf(hand, e.seat) != at.player) return null;
      final i = PreflopAdvisor.matchAction(at, e);
      if (i < 0) return null;
      steps.add(_Step(game, at, i));
      node = at.children[i];
    }
    enterSubgame();
    return _Walk(steps, game, node);
  }

  /// The GTO answer for the user's decision, once its subgame is solved.
  SpotStrategy? spotFor(PokerHand hand) {
    if (hand.street != Street.preflop || hand.toAct != heroSeat) return null;
    final subgame = _subgames[historyOf(hand).length];
    if (subgame == null) return null;
    final root = subgame.tree.root;
    return root is PreflopDecision ? subgame.spotAt(root, hand) : null;
  }

  /// The solved whole game's answer for whoever acts (online, a spectator's
  /// coach): the blueprint's menu, not a subgame's, so it costs no solve
  /// beyond the whole game. Null once the hand has left the solved lines,
  /// or when this device doesn't know the actor's cards.
  SpotStrategy? blueprintSpotFor(PokerHand hand) {
    final seat = hand.toAct;
    if (hand.street != Street.preflop || seat == null) return null;
    final walk = _walk(hand);
    final node = walk?.node;
    if (node is! PreflopDecision || node.player != PreflopAdvisor.orderOf(hand, seat)) return null;
    return walk!.game.spotAt(node, hand);
  }

  /// A move for the bot to act, drawn from the solved strategy; null once
  /// the hand has left the solved lines.
  PlayerAction? sample(PokerHand hand, Random random) {
    if (hand.street != Street.preflop || hand.toAct == null || hand.toAct == heroSeat) return null;
    final walk = _walk(hand);
    final node = walk?.node;
    if (node is! PreflopDecision || node.player != PreflopAdvisor.orderOf(hand, hand.toAct!)) return null;
    return walk!.game.sampleAt(node, hand, random);
  }

  /// How likely [seat] is to hold each starting hand (169 weights, 0-1),
  /// given how everyone played so far, if they all followed the solved
  /// strategies; null once the hand has left the solved lines. With
  /// [anySize], a raise counts as raising at any size (see [_Walk.rangeOf]).
  Float64List? rangeOf(PokerHand hand, int seat, {bool anySize = false}) =>
      _walk(hand)?.rangeOf(PreflopAdvisor.orderOf(hand, seat), anySize: anySize);
}

/// The hand left the solved lines before the user's decision: there is no
/// subgame to solve.
class _OffTheSolvedLines implements Exception {
  const _OffTheSolvedLines();
}

/// [move] (a bot's own idea, or one drawn from an older solve than the
/// hand's latest) as a move of [menu], the bots' menu where it acts (see
/// [PreflopTree.botMenuAt]). The hand then stays on the lines that every
/// solve of it has, so later decisions in it can still be answered:
///  - a raise goes to the nearest raise size on the menu, at its exact
///    amount, or all-in when the menu has no raise (and an all-in stays
///    all-in when it can): the same reading the solved game gives a size
///    it doesn't have (see PreflopAdvisor.matchAction). With neither on
///    the menu, it becomes a call if there is one, else a check or fold;
///  - a call the menu lacks (a limp, one cold call too many) becomes a fold;
///  - a fold with nothing to call is a check.
/// Checks, and folds facing a bet, are always on the menu. A move on the
/// menu stays as it is, and an empty menu changes nothing.
PlayerAction fitToMenu(PlayerAction move, List<PreflopAction> menu, LegalActions legal) {
  if (menu.isEmpty) return move;
  bool has(PreflopMove m) => menu.any((a) => a.move == m);
  switch (move.type) {
    case ActionType.fold:
      return legal.canCheck ? const PlayerAction.check() : move;
    case ActionType.check:
      return move;
    case ActionType.call:
      return has(PreflopMove.call) || !legal.canCall ? move : const PlayerAction.fold();
    case ActionType.raise:
      final sizes = [
        if (legal.canRaise)
          for (final a in menu)
            if (a.move == PreflopMove.raise) a.raiseTo.clamp(legal.minRaiseTo, legal.maxRaiseTo),
      ];
      final allIn = legal.canRaise && has(PreflopMove.allIn);
      if (allIn && (sizes.isEmpty || move.amount >= legal.maxRaiseTo)) return PlayerAction.raiseTo(legal.maxRaiseTo);
      if (sizes.isEmpty) {
        if (legal.canCheck) return const PlayerAction.check();
        return has(PreflopMove.call) ? const PlayerAction.call() : const PlayerAction.fold();
      }
      double distance(int to) => (log(to) - log(move.amount)).abs();
      var best = sizes.first;
      for (final to in sizes.skip(1)) {
        if (distance(to) < distance(best)) best = to;
      }
      return PlayerAction.raiseTo(best);
  }
}

class _Step {
  _Step(this.game, this.node, this.action);
  final PreflopAdvisor game;
  final PreflopDecision node;
  final int action;
}

class _Walk {
  _Walk(this.steps, this.game, this.node);
  final List<_Step> steps;

  /// The game and node the hand is at now.
  final PreflopAdvisor game;
  final PreflopNode node;

  /// Player [p]'s range: how often each starting hand takes every action
  /// they took. With [anySize], raising at any size (all-in included) counts
  /// as the same action: the solver splits its raises between sizes of
  /// nearly the same EV almost at random, so for showing a range the size
  /// only adds noise.
  Float64List rangeOf(int p, {bool anySize = false}) {
    final weights = Float64List(handClassCount)..fillRange(0, handClassCount, 1);
    for (final step in steps) {
      if (step.node.player != p) continue;
      final actions = step.node.actions;
      final alike = anySize
          ? [for (var a = 0; a < actions.length; a++) if (_choice(actions[a].move) == _choice(actions[step.action].move)) a]
          : [step.action];
      for (var h = 0; h < handClassCount; h++) {
        var frequency = 0.0;
        for (final a in alike) {
          frequency += step.game.solution.frequency(step.node, a, h);
        }
        weights[h] *= frequency;
      }
    }
    return weights;
  }

  /// Fold, check or call, or raise (any size, all-in included).
  static int _choice(PreflopMove move) => switch (move) {
        PreflopMove.fold => 0,
        PreflopMove.check || PreflopMove.call => 1,
        PreflopMove.raise || PreflopMove.allIn => 2,
      };
}
