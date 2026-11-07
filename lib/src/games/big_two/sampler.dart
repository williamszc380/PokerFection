/// Guessing the hidden hands: deals the cards a player can't see to the
/// other seats in ways that fit everything public.
///
/// This is the "determinization" step of information-set Monte Carlo
/// (Cowling, Powley and Whitehouse, "Information Set Monte Carlo Tree
/// Search", 2012): the coach solves many such guessed deals and averages.
/// What a guess must respect:
/// - the viewer's own hand and every card played are never dealt;
/// - each seat gets exactly as many cards as it holds;
/// - a card everyone has seen that is still in a hand (the starting card
///   until it is played, a three-player deal's face-up card) goes to its
///   holder ([BigTwoView.visibleCards]), and so does the card the taker
///   of a three-player deal's 52nd card must hold ([BigTwoView.knownCards]);
/// - with the last-card rule, a seat that had to play its highest single
///   holds nothing higher than that card;
/// - in a two-player deal no card below the starting card was dealt at
///   all (the lowest card dealt starts).
///
/// Passes carry no hard information: Pagat lets a player pass even when
/// they could beat the play, so a pass never rules a card out.
library;

import 'random.dart';
import 'rules.dart';
import 'state.dart';

/// Deals the unknown cards of one [BigTwoView] at random, consistently with
/// what the viewer knows.
class DealSampler {
  /// Prepares to sample for [view].
  DealSampler(this.view) : rules = view.rules {
    final n = rules.players;
    _need = List<int>.filled(n + 1, 0);
    _bound = List<int>.filled(n + 1, 52);
    _fixed = List.generate(n, (_) => <int>[]);
    for (final v in view.knownCards) {
      if (v.seat != view.seat) _fixed[v.seat].add(v.code);
    }
    for (var s = 0; s < n; s++) {
      if (s == view.seat) continue;
      _need[s] = view.counts[s] - _fixed[s].length;
      _bound[s] = view.bounds[s];
      if (_bound[s] < 52) _bounded = true;
    }
    // The known cards are already left out of the unknown ones. In a
    // two-player game the starting card is the lowest card dealt, so every
    // card below it, once it is known, is out of play.
    final deadBelow = (rules.players == 2 && view.startCode >= 0) ? view.startCode : 0;
    _pool = [
      for (final c in view.unknownCodes())
        if (c >= deadBelow) c,
    ];
    var needTotal = 0;
    for (var s = 0; s < n; s++) {
      needTotal += _need[s];
    }
    _need[n] = _pool.length - needTotal; // the unused cards (two players only)
    if (_need[n] < 0) throw StateError('View is inconsistent: more hidden cards than unknown cards');
    _hiddenSeats = [for (var s = 0; s <= n; s++) if (s != view.seat && _need[s] > 0) s];
  }

  /// The view being sampled for.
  final BigTwoView view;

  /// Its rules.
  final BigTwoRules rules;

  late final List<int> _need;
  late final List<int> _bound;
  late final List<List<int>> _fixed;
  late final List<int> _pool;
  late final List<int> _hiddenSeats;
  bool _bounded = false;

  /// The cards being dealt out (engine codes), for tests and card counting.
  List<int> get pool => List.unmodifiable(_pool);

  /// One guessed deal: engine codes for every seat (the viewer's own seat
  /// holds their real hand).
  List<List<int>> sample(GameRandom rng) {
    final cards = List<int>.of(_pool);
    if (_bounded) {
      // Rejection first, which is exactly uniform when it succeeds.
      for (var attempt = 0; attempt < 20; attempt++) {
        rng.shuffle(cards);
        final hands = _split(cards);
        if (_respectsBounds(hands)) return hands;
      }
      return _nestedDeal(rng);
    }
    rng.shuffle(cards);
    return _split(cards);
  }

  /// A guessed deal as a playable state.
  BigTwoState sampleState(GameRandom rng) => BigTwoState.fromView(view, sample(rng));

  List<List<int>> _split(List<int> cards) {
    final n = rules.players;
    final hands = List.generate(n, (s) => s == view.seat ? List<int>.of(view.handCodes) : List<int>.of(_fixed[s]));
    var i = 0;
    for (final s in _hiddenSeats) {
      if (s == n) continue; // unused cards are simply left over
      for (var k = 0; k < _need[s]; k++) {
        hands[s].add(cards[i++]);
      }
    }
    return hands;
  }

  bool _respectsBounds(List<List<int>> hands) {
    for (var s = 0; s < rules.players; s++) {
      if (s == view.seat || _bound[s] >= 52) continue;
      for (final c in hands[s]) {
        if (c >= _bound[s] && !_fixed[s].contains(c)) return false;
      }
    }
    return true;
  }

  // Fills the most constrained seats first, each from the cards it may
  // hold. Bounds are nested (a seat may hold every card below its bound), so
  // this always succeeds for a consistent view; it is close to, but not
  // exactly, uniform, which is why it is only the fallback.
  List<List<int>> _nestedDeal(GameRandom rng) {
    final n = rules.players;
    final hands = List.generate(n, (s) => s == view.seat ? List<int>.of(view.handCodes) : List<int>.of(_fixed[s]));
    final seats = [for (final s in _hiddenSeats) s]..sort((a, b) {
        final c = _bound[a].compareTo(_bound[b]);
        return c != 0 ? c : a.compareTo(b);
      });
    final left = List<int>.of(_pool);
    for (final s in seats) {
      final eligible = [for (final c in left) if (c < _bound[s]) c];
      rng.shuffle(eligible);
      final take = eligible.sublist(0, _need[s]);
      if (s < n) hands[s].addAll(take);
      for (final c in take) {
        left.remove(c);
      }
    }
    return hands;
  }
}
