import 'dart:math';
import 'dart:typed_data';

import '../../engine/actions.dart';
import '../../engine/events.dart';
import '../../engine/poker_hand.dart';
import '../../engine/rules.dart';
import '../action_menu.dart';
import '../combos.dart';
import '../preflop/preflop_advisor.dart' show drawAction;
import '../preflop/preflop_tracker.dart';
import '../spot_strategy.dart';
import 'postflop_solver.dart';
import 'postflop_tree.dart';

/// Solves one street given both players' ranges (first to act first).
typedef PostflopSolve = Future<PostflopSolution> Function(PostflopSpec spec, List<Float64List> ranges);

/// Follows one hand after the flop and answers "what does GTO do here?".
///
/// When a street starts, it solves that street in the background, starting
/// from both players' ranges: their preflop ranges, narrowed by how often
/// the solved strategy takes the actions they actually took on earlier
/// streets. Only heads-up pots are covered.
class PostflopTracker {
  PostflopTracker({
    required this.preflop,
    required this.solve,
    required this.bigBlind,
    this.raiseRule = RaiseRule.standard,
    this.heroSeat = -1,
    this.sizes = PostflopSpec.defaultHeroSizes,
  });

  final PreflopTracker preflop;
  final PostflopSolve solve;
  final int bigBlind;
  final RaiseRule raiseRule;

  /// The user's seat (-1 if no user plays): they get every size of [sizes].
  final int heroSeat;
  final List<double> sizes;

  /// Seats of the two players: first to act after the flop, then last.
  List<int>? _seats;

  /// Each player's weight on every combination (0-1325).
  List<Float64List>? _ranges;
  Street? _street;
  PostflopSpec? _spec;
  Future<PostflopSolution>? _pending;
  PostflopSolution? _solution;

  /// Why there are no GTO answers after the flop in this hand, if there aren't.
  NoAnswer? unavailable;

  /// Whether the current street's answers are still being worked out.
  bool get solving => _pending != null && _solution == null && unavailable == null;

  /// Completes when the current street is solved.
  Future<void> get ready async {
    final pending = _pending;
    if (pending != null && unavailable == null) await pending;
  }

  /// Call after every action: when a new street begins, starts solving it.
  Future<void> update(PokerHand hand) async {
    if (unavailable != null || hand.street == Street.preflop || hand.street == _street) return;
    if (hand.isOver || hand.toAct == null) {
      _street = hand.street; // no more betting (someone is all-in): nothing to solve
      return;
    }
    if (_street == null) {
      final live = [for (var s = 0; s < hand.playerCount; s++) if (!hand.isFolded(s)) s];
      if (live.length != 2) {
        unavailable = NoAnswer.multiway;
        return;
      }
      final first = hand.toAct!;
      _seats = [first, live.firstWhere((s) => s != first)];
      final ranges = <Float64List>[];
      for (final seat in _seats!) {
        final classes = preflop.rangeOf(hand, seat);
        if (classes == null) {
          unavailable = NoAnswer.leftSolvedLines;
          return;
        }
        ranges.add(Float64List.fromList([for (var c = 0; c < comboCount; c++) classes[comboClass[c]]]));
      }
      _ranges = ranges;
    } else {
      // Narrow the ranges with what each player did on the street just played.
      await _pending;
      if (!_narrow(hand, _street!)) {
        unavailable = NoAnswer.leftSolvedLines;
        return;
      }
    }
    _street = hand.street;
    final spec = _spec = PostflopSpec(
      board: [for (final c in hand.board) c.index],
      pot: hand.potTotal,
      stacks: [hand.stackOf(_seats![0]), hand.stackOf(_seats![1])],
      bigBlind: bigBlind,
      raiseRule: raiseRule,
      hero: _seats!.indexOf(heroSeat),
      heroSizes: sizes,
    );
    _solution = null;
    _pending = solve(spec, [Float64List.fromList(_ranges![0]), Float64List.fromList(_ranges![1])])
        .then((solution) {
      if (identical(_spec, spec)) _solution = solution;
      return solution;
    });
  }

  bool _narrow(PokerHand hand, Street street) {
    final solution = _solution;
    if (solution == null) return false;
    final n = solution.hands.length;
    PostflopNode node = solution.tree.root;
    for (final e in hand.log) {
      if (e is! ActionTaken || e.street != street) continue;
      final p = _seats!.indexOf(e.seat);
      if (node is! PostflopDecision || node.player != p) return false;
      final i = matchAction(node, e);
      if (i < 0) return false;
      final range = _ranges![p];
      for (var c = 0; c < comboCount; c++) {
        final compact = solution.hands.compact[c];
        range[c] = compact < 0 ? 0 : range[c] * solution.strategy[node.offset + i * n + compact];
      }
      node = node.children[i];
    }
    return true;
  }

  /// The tree action matching [e]. A size the tree doesn't have is mapped
  /// to the nearest one it has.
  static int matchAction(PostflopDecision node, ActionTaken e) {
    final raised = e.kind == ActionKind.bet || e.kind == ActionKind.raise;
    var nearest = -1, allIn = -1;
    var best = double.infinity;
    for (var i = 0; i < node.actions.length; i++) {
      final a = node.actions[i];
      switch (a.move) {
        case PostflopMove.fold when e.kind == ActionKind.fold:
        case PostflopMove.check when e.kind == ActionKind.check:
        case PostflopMove.call when e.kind == ActionKind.call:
          return i;
        case PostflopMove.allIn:
          allIn = i;
        case PostflopMove.bet || PostflopMove.raise when raised:
          final distance = (log(a.to) - log(e.streetBet)).abs();
          if (distance < best) {
            best = distance;
            nearest = i;
          }
        default:
          break;
      }
    }
    if (!raised) return -1;
    return e.isAllIn ? (allIn >= 0 ? allIn : nearest) : (nearest >= 0 ? nearest : allIn);
  }

  /// The decision the current street is at, if it is solved.
  PostflopDecision? _decision(PokerHand hand) {
    final solution = _solution;
    final toAct = hand.toAct;
    if (unavailable != null || solution == null || hand.street != _street || toAct == null) return null;
    PostflopNode node = solution.tree.root;
    for (final e in hand.log) {
      if (e is! ActionTaken || e.street != hand.street) continue;
      if (node is! PostflopDecision || node.player != _seats!.indexOf(e.seat)) return null;
      final i = matchAction(node, e);
      if (i < 0) return null;
      node = node.children[i];
    }
    return node is PostflopDecision && node.player == _seats!.indexOf(toAct) ? node : null;
  }

  /// The GTO answer for the player to act, or null (not solved yet, or not
  /// covered). For the user: every choice of their menu (see [actionMenu]),
  /// the ones not allowed here greyed out. For a bot: the choices it has.
  SpotStrategy? spotFor(PokerHand hand) {
    final node = _decision(hand);
    if (node == null) return null;
    final solution = _solution!;
    final spec = solution.tree.spec;
    final cards = hand.holeCards(hand.toAct!);
    final combo = comboIndex(cards[0].index, cards[1].index);
    final handName = [for (final c in cards) '${c.rankLabel}${c.suitSymbol}'].join(' ');
    double frequency(int i) => solution.frequency(node, i, combo);
    double value(int i) {
      final v = solution.value(node, i, combo);
      // Relative to folding now: add back what this player already bet on the street.
      return v.isNaN ? double.nan : (v + node.bets[node.player]) / bigBlind;
    }

    if (node.player == spec.hero) {
      return answerFor(
        actionMenu(hand, preflopSizes: const [], postflopSizes: spec.heroSizes),
        handName: handName,
        indexOf: (choice) => node.actions.indexWhere((a) => switch (choice.kind) {
              SpotActionKind.fold => a.move == PostflopMove.fold,
              SpotActionKind.check => a.move == PostflopMove.check,
              SpotActionKind.call => a.move == PostflopMove.call,
              SpotActionKind.raise =>
                (a.move == PostflopMove.bet || a.move == PostflopMove.raise) && a.to == choice.amount,
              SpotActionKind.allIn => a.move == PostflopMove.allIn,
            }),
        frequency: frequency,
        value: value,
      );
    }
    final legal = hand.legalActions();
    return SpotStrategy.normalized(
      handName: handName,
      actions: [
        for (final a in node.actions)
          switch (a.move) {
            PostflopMove.fold => const SpotAction(kind: SpotActionKind.fold, amount: 0, action: PlayerAction.fold()),
            PostflopMove.check =>
              const SpotAction(kind: SpotActionKind.check, amount: 0, action: PlayerAction.check()),
            PostflopMove.call =>
              SpotAction(kind: SpotActionKind.call, amount: legal.toCall, action: const PlayerAction.call()),
            PostflopMove.bet || PostflopMove.raise => SpotAction(
                kind: SpotActionKind.raise,
                amount: a.to,
                action: PlayerAction.raiseTo(a.to.clamp(legal.minRaiseTo, legal.maxRaiseTo)),
                potShare: a.potShare,
              ),
            PostflopMove.allIn => SpotAction(
                kind: SpotActionKind.allIn,
                amount: legal.maxRaiseTo,
                action: PlayerAction.raiseTo(legal.maxRaiseTo),
              ),
          },
      ],
      frequencies: [for (var i = 0; i < node.actions.length; i++) frequency(i)],
      evs: [for (var i = 0; i < node.actions.length; i++) value(i)],
    );
  }

  /// A move drawn from the GTO strategy for the player to act, or null.
  PlayerAction? sample(PokerHand hand, Random random) {
    final spot = spotFor(hand);
    return spot == null ? null : drawAction(spot, random);
  }

  /// [seat]'s range right now: their range at the start of the street,
  /// narrowed by what they did on it so far (once the street is solved).
  Float64List? currentRange(PokerHand hand, int seat) {
    final seats = _seats, ranges = _ranges;
    if (unavailable != null || seats == null || ranges == null || !seats.contains(seat)) return null;
    final p = seats.indexOf(seat);
    final range = Float64List.fromList(ranges[p]);
    final solution = _solution;
    if (solution == null || hand.street != _street) return range;
    final n = solution.hands.length;
    PostflopNode node = solution.tree.root;
    for (final e in hand.log) {
      if (e is! ActionTaken || e.street != hand.street) continue;
      if (node is! PostflopDecision) break;
      final i = matchAction(node, e);
      if (i < 0) break;
      if (node.player == p) {
        for (var c = 0; c < comboCount; c++) {
          final compact = solution.hands.compact[c];
          range[c] = compact < 0 ? 0 : range[c] * solution.strategy[node.offset + i * n + compact];
        }
      }
      node = node.children[i];
    }
    return range;
  }

  /// [action] with its bet size moved to the nearest size the solver has, so
  /// bots with human styles keep the hand on the solved lines.
  PlayerAction snap(PokerHand hand, PlayerAction action) {
    if (action.type != ActionType.raise) return action;
    final node = _decision(hand);
    if (node == null) return action;
    final legal = hand.legalActions();
    var best = action.amount;
    var distance = double.infinity;
    for (final a in node.actions) {
      if (a.move != PostflopMove.bet && a.move != PostflopMove.raise && a.move != PostflopMove.allIn) continue;
      final to = a.move == PostflopMove.allIn ? legal.maxRaiseTo : a.to.clamp(legal.minRaiseTo, legal.maxRaiseTo);
      final d = (log(to) - log(action.amount)).abs();
      if (d < distance) {
        distance = d;
        best = to;
      }
    }
    return PlayerAction.raiseTo(best);
  }
}
