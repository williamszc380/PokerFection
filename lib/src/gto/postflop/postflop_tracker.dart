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
/// streets.
///
/// The solver plays two players. When more see the flop with the user, the
/// answers are approximate ([approximate]): the user plays heads-up against
/// "the field", one opponent holding whichever of the opponents' hands is
/// best (see [strongestOfField]). The opponents' actions between two of the
/// user's make one move of the field: a bet or raise if anyone bet or
/// raised, else a call if anyone called, a check if all checked, a fold if
/// all folded. Each opponent's own range narrows by how often the field
/// makes the move they made. Of the greedy ways tried (tool/multiway_bench
/// .dart, against exact three-player river solves), this one gave up the
/// least. Once only one opponent is left, play carries on heads-up.
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

  /// Seats of the two players the solve plays: first to act after the flop,
  /// then last. [field] stands for all the opponents at once.
  List<int>? _seats;

  /// The field in [_seats]: every opponent at once (see the class comment).
  static const field = -2;

  /// Whether the answers are approximate: more than two players saw the
  /// flop, and the user plays against the field.
  bool get approximate => _seats?.contains(field) ?? false;

  /// Against the field: each opponent's range, for solving and for showing.
  final Map<int, Float64List> _opponents = {}, _opponentsShown = {};

  /// Each player's weight on every combination (0-1325).
  List<Float64List>? _ranges;

  /// The same for showing: with every raise counted as raising at any size,
  /// which reads much more clearly (see [_narrowBy]).
  List<Float64List>? _shown;
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
      // Everyone still in, in the order they act after the flop.
      final first = hand.toAct!;
      final live = [
        for (var k = 0; k < hand.playerCount; k++)
          if (!hand.isFolded((first + k) % hand.playerCount)) (first + k) % hand.playerCount,
      ];
      if (live.length > 2) {
        if (!live.contains(heroSeat)) {
          unavailable = NoAnswer.multiway;
          return;
        }
        for (final seat in live) {
          if (seat == heroSeat) continue;
          final classes = preflop.rangeOf(hand, seat), anySize = preflop.rangeOf(hand, seat, anySize: true);
          if (classes == null || anySize == null) {
            unavailable = NoAnswer.leftSolvedLines;
            return;
          }
          _opponents[seat] = _byCombo(classes);
          _opponentsShown[seat] = _byCombo(anySize);
        }
        // The user acts last against the field only when everyone acts before them.
        _seats = live.last == heroSeat ? [field, heroSeat] : [heroSeat, field];
      } else {
        _seats = live;
      }
      final ranges = <Float64List>[], shown = <Float64List>[];
      for (final seat in _seats!) {
        if (seat == field) {
          // Worked out for each street below.
          ranges.add(Float64List(comboCount));
          shown.add(Float64List(comboCount));
          continue;
        }
        final classes = preflop.rangeOf(hand, seat), anySize = preflop.rangeOf(hand, seat, anySize: true);
        if (classes == null || anySize == null) {
          unavailable = NoAnswer.leftSolvedLines;
          return;
        }
        ranges.add(_byCombo(classes));
        shown.add(_byCombo(anySize));
      }
      _ranges = ranges;
      _shown = shown;
    } else {
      // Narrow the ranges with what each player did on the street just played.
      await _pending;
      if (!_narrow(hand, _street!)) {
        unavailable = NoAnswer.leftSolvedLines;
        return;
      }
    }
    if (approximate && !_fieldForStreet(hand)) return;
    _street = hand.street;
    // The field covers the biggest stack still in.
    int stackOf(int seat) => seat == field
        ? [for (final s in _opponents.keys) if (!hand.isFolded(s)) hand.stackOf(s)].reduce(max)
        : hand.stackOf(seat);
    final spec = _spec = PostflopSpec(
      board: [for (final c in hand.board) c.index],
      pot: hand.potTotal,
      stacks: [stackOf(_seats![0]), stackOf(_seats![1])],
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

  static Float64List _byCombo(Float64List classes) =>
      Float64List.fromList([for (var c = 0; c < comboCount; c++) classes[comboClass[c]]]);

  /// Against the field, at the start of a street: the field's range from
  /// the opponents still in; with only one left, heads-up against them from
  /// now on. False if there is nothing to solve.
  bool _fieldForStreet(PokerHand hand) {
    final left = [for (final s in _opponents.keys) if (!hand.isFolded(s)) s];
    if (left.isEmpty) return false;
    final user = _seats!.indexOf(heroSeat), fieldIndex = 1 - user;
    if (left.length == 1) {
      final opponent = left.single;
      final ranges = [_ranges![user], _opponents[opponent]!], shown = [_shown![user], _opponentsShown[opponent]!];
      final userFirst = _actsBefore(hand, heroSeat, opponent);
      _seats = userFirst ? [heroSeat, opponent] : [opponent, heroSeat];
      _ranges = userFirst ? ranges : ranges.reversed.toList();
      _shown = userFirst ? shown : shown.reversed.toList();
      _opponents.clear();
      _opponentsShown.clear();
      return true;
    }
    _ranges![fieldIndex] = strongestOfField([for (final c in hand.board) c.index], [for (final s in left) _opponents[s]!]);
    return true;
  }

  /// Whether [a] acts before [b] on this street.
  static bool _actsBefore(PokerHand hand, int a, int b) {
    final first = hand.toAct!, n = hand.playerCount;
    return (a - first + n) % n < (b - first + n) % n;
  }

  /// Against the field: the street's actions as moves of the heads-up game
  /// between the user and the field (see the class comment). A bet the user
  /// faces before their first move, when they act first in that game,
  /// counts as them having checked to it. With [finish], the opponents'
  /// actions since the user's last move make the field's move too (when the
  /// street is over, or it is the user's turn). Null if the actions can't be
  /// followed.
  ({List<({PostflopDecision node, int action, List<int> seats})> steps, PostflopNode node})? _fieldPath(
      PokerHand hand, Street street, PostflopSolution solution,
      {required bool finish}) {
    final user = _seats!.indexOf(heroSeat);
    PostflopNode node = solution.tree.root;
    final steps = <({PostflopDecision node, int action, List<int> seats})>[];
    final pending = <ActionTaken>[];
    bool raised(ActionTaken e) => e.kind == ActionKind.bet || e.kind == ActionKind.raise;

    bool fieldMoves() {
      if (pending.isEmpty) return true;
      var at = node;
      if (at is! PostflopDecision) return false;
      if (at.player == user) {
        // Players before the user acted first: checks change nothing.
        if (!pending.any(raised)) {
          pending.clear();
          return true;
        }
        final check = at.actions.indexWhere((a) => a.move == PostflopMove.check);
        if (check < 0) return false;
        final next = at.children[check];
        if (next is! PostflopDecision) return false;
        at = next;
      }
      final bets = [for (final e in pending) if (raised(e)) e];
      final calls = [for (final e in pending) if (e.kind == ActionKind.call) e];
      final checks = [for (final e in pending) if (e.kind == ActionKind.check) e];
      final by = bets.isNotEmpty ? [bets.last] : (calls.isNotEmpty ? calls : (checks.isNotEmpty ? checks : pending));
      final i = matchAction(at, by.first);
      if (i < 0) return false;
      steps.add((node: at, action: i, seats: [for (final e in by) e.seat]));
      node = at.children[i];
      pending.clear();
      return true;
    }

    for (final e in hand.log) {
      if (e is! ActionTaken || e.street != street) continue;
      if (e.seat != heroSeat) {
        pending.add(e);
        continue;
      }
      if (!fieldMoves()) return null;
      final at = node;
      if (at is! PostflopDecision || at.player != user) return null;
      final i = matchAction(at, e);
      if (i < 0) return null;
      steps.add((node: at, action: i, seats: [heroSeat]));
      node = at.children[i];
    }
    if (finish && !fieldMoves()) return null;
    return (steps: steps, node: node);
  }

  bool _narrow(PokerHand hand, Street street) {
    final solution = _solution;
    if (solution == null) return false;
    if (approximate) {
      final path = _fieldPath(hand, street, solution, finish: true);
      if (path == null) return false;
      final user = _seats!.indexOf(heroSeat);
      for (final step in path.steps) {
        for (final seat in step.seats) {
          if (seat == heroSeat) {
            _narrowBy(_ranges![user], solution, step.node, step.action);
            _narrowBy(_shown![user], solution, step.node, step.action, anySize: true);
          } else if (_opponents.containsKey(seat)) {
            _narrowBy(_opponents[seat]!, solution, step.node, step.action);
            _narrowBy(_opponentsShown[seat]!, solution, step.node, step.action, anySize: true);
          }
        }
      }
      return true;
    }
    // A player the solve plays folded: nothing more to answer.
    if (_seats!.any(hand.isFolded)) return false;
    PostflopNode node = solution.tree.root;
    for (final e in hand.log) {
      if (e is! ActionTaken || e.street != street) continue;
      final p = _seats!.indexOf(e.seat);
      if (node is! PostflopDecision || node.player != p) return false;
      final i = matchAction(node, e);
      if (i < 0) return false;
      _narrowBy(_ranges![p], solution, node, i);
      _narrowBy(_shown![p], solution, node, i, anySize: true);
      node = node.children[i];
    }
    return true;
  }

  /// Keeps in [range] how often each combination takes action [i] at [node].
  /// With [anySize], betting or raising at any size (all-in included) counts
  /// as the same action: the solver splits its bets between sizes of nearly
  /// the same EV almost at random, so for showing a range the size only
  /// adds noise.
  static void _narrowBy(Float64List range, PostflopSolution solution, PostflopDecision node, int i,
      {bool anySize = false}) {
    final n = solution.hands.length;
    final alike = anySize
        ? [for (var a = 0; a < node.actions.length; a++) if (_choice(node.actions[a].move) == _choice(node.actions[i].move)) a]
        : [i];
    for (var c = 0; c < comboCount; c++) {
      final compact = solution.hands.compact[c];
      if (compact < 0) {
        range[c] = 0;
        continue;
      }
      var frequency = 0.0;
      for (final a in alike) {
        frequency += solution.strategy[node.offset + a * n + compact];
      }
      range[c] *= frequency;
    }
  }

  /// Fold, check or call, or bet or raise (any size, all-in included).
  static int _choice(PostflopMove move) => switch (move) {
        PostflopMove.fold => 0,
        PostflopMove.check || PostflopMove.call => 1,
        PostflopMove.bet || PostflopMove.raise || PostflopMove.allIn => 2,
      };

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
    if (approximate) {
      // Only the user's decisions, against the field.
      if (toAct != heroSeat) return null;
      final node = _fieldPath(hand, hand.street, solution, finish: true)?.node;
      return node is PostflopDecision && node.player == _seats!.indexOf(heroSeat) ? node : null;
    }
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

  /// [seat]'s range right now, for showing: their range at the start of the
  /// street, narrowed by what they did on it so far (once the street is
  /// solved), with every bet or raise counted as any size.
  Float64List? currentRange(PokerHand hand, int seat) {
    final seats = _seats, shown = _shown;
    if (unavailable != null || seats == null || shown == null) return null;
    if (approximate) {
      final start = seat == heroSeat ? shown[seats.indexOf(heroSeat)] : _opponentsShown[seat];
      if (start == null) return null;
      final range = Float64List.fromList(start);
      final solution = _solution;
      if (solution == null || hand.street != _street) return range;
      for (final step in _fieldPath(hand, hand.street, solution, finish: false)?.steps ?? const []) {
        if (step.seats.contains(seat)) _narrowBy(range, solution, step.node, step.action, anySize: true);
      }
      return range;
    }
    if (!seats.contains(seat)) return null;
    final p = seats.indexOf(seat);
    final range = Float64List.fromList(shown[p]);
    final solution = _solution;
    if (solution == null || hand.street != _street) return range;
    PostflopNode node = solution.tree.root;
    for (final e in hand.log) {
      if (e is! ActionTaken || e.street != hand.street) continue;
      if (node is! PostflopDecision) break;
      final i = matchAction(node, e);
      if (i < 0) break;
      if (node.player == p) _narrowBy(range, solution, node, i, anySize: true);
      node = node.children[i];
    }
    return range;
  }

  /// Against the field: the decision an opponent's move would be the field's
  /// move at (for snapping their bets to the solved sizes).
  PostflopDecision? _fieldNode(PokerHand hand) {
    final solution = _solution;
    if (unavailable != null || solution == null || hand.street != _street) return null;
    var node = _fieldPath(hand, hand.street, solution, finish: false)?.node;
    if (node is! PostflopDecision) return null;
    final fieldIndex = _seats!.indexOf(field);
    if (node.player != fieldIndex) {
      // The user acts first in the heads-up game: as if they had checked.
      final check = node.actions.indexWhere((a) => a.move == PostflopMove.check);
      if (check < 0) return null;
      node = node.children[check];
    }
    return node is PostflopDecision && node.player == fieldIndex ? node : null;
  }

  /// [action] with its bet size moved to the nearest size the solver has, so
  /// bots with human styles keep the hand on the solved lines.
  PlayerAction snap(PokerHand hand, PlayerAction action) {
    if (action.type != ActionType.raise) return action;
    final node = approximate ? _fieldNode(hand) : _decision(hand);
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
