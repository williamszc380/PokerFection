import 'dart:async';
import 'dart:typed_data';

import 'package:pokerfection/src/gto/hand_classes.dart';
import 'package:pokerfection/src/gto/postflop/postflop_solver.dart';
import 'package:pokerfection/src/gto/postflop/postflop_tracker.dart';
import 'package:pokerfection/src/gto/postflop/postflop_tree.dart';
import 'package:pokerfection/src/gto/preflop/preflop_advisor.dart';
import 'package:pokerfection/src/gto/preflop/preflop_solver.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tracker.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tree.dart';

/// Stand-ins for solves, for tests about which lines a hand follows rather
/// than what GTO plays on them: a "solution" with the real tree, where
/// every hand takes each action equally often. Built at once, with no
/// solving, so a test can play hundreds of hands.
PreflopSolution evenPreflop(PreflopSpec spec) {
  final tree = PreflopTree(spec);
  final strategy = Float32List(tree.storageSize);
  for (final node in tree.decisions) {
    final share = 1 / node.actions.length;
    strategy.fillRange(node.offset, node.offset + node.actions.length * handClassCount, share);
  }
  return PreflopSolution(tree, strategy, Float32List(tree.storageSize)..fillRange(0, tree.storageSize, double.nan));
}

PostflopSolution evenPostflop(PostflopSpec spec) {
  final hands = PostflopHands(spec.board);
  final tree = PostflopTree(spec, hands: hands.length);
  final strategy = Float32List(tree.storageSize);
  for (final node in tree.decisions) {
    final share = 1 / node.actions.length;
    strategy.fillRange(node.offset, node.offset + node.actions.length * hands.length, share);
  }
  return PostflopSolution(
      tree, hands, strategy, Float32List(tree.storageSize)..fillRange(0, tree.storageSize, double.nan));
}

/// The whole game of [spec], even (see [evenPreflop]).
PreflopAdvisor evenBlueprint(PreflopSpec spec) => PreflopAdvisor(evenPreflop(spec));

/// One solve asked for and held until the test lets it finish.
class HeldSolve<T> {
  HeldSolve(this.spec, this._make);

  /// A PreflopSpec (a subgame) or a PostflopSpec (a street).
  final Object spec;
  final T Function() _make;
  final _done = Completer<T>();
  Future<T> get future => _done.future;
  bool get finished => _done.isCompleted;

  void complete() => _done.complete(_make());
  void fail() => _done.completeError(StateError('The solve failed'));
}

/// Solves for the trackers that finish only when the test says so, in
/// any order: each is an even solution (see [evenPreflop]).
class HeldSolves {
  final List<HeldSolve<PreflopSolution>> subgames = [];
  final List<HeldSolve<PostflopSolution>> streets = [];

  Future<PreflopSolution> subgame(PreflopSpec spec, Float64List? ranges) {
    final held = HeldSolve(spec, () => evenPreflop(spec));
    subgames.add(held);
    return held.future;
  }

  Future<PostflopSolution> street(PostflopSpec spec, List<Float64List> ranges) {
    final held = HeldSolve(spec, () => evenPostflop(spec));
    streets.add(held);
    return held.future;
  }

  PreflopSubgameSolve get solveSubgame => subgame;
  PostflopSolve get solveStreet => street;

  /// Finishes every solve still held.
  void completeAll() {
    for (final s in [...subgames, ...streets]) {
      if (!s.finished) s.complete();
    }
  }
}

/// Solves that finish as soon as they're asked for (even ones).
Future<PreflopSolution> instantSubgame(PreflopSpec spec, Float64List? ranges) async => evenPreflop(spec);
Future<PostflopSolution> instantStreet(PostflopSpec spec, List<Float64List> ranges) async => evenPostflop(spec);
