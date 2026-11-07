import 'dart:typed_data';

/// The last few solves, by everything that goes into them (the spot and
/// the players' ranges), so the same spot again is answered at once: a
/// replayed or drilled hand, or the same situation coming up at the table.
/// A solve still running (or waiting its turn) is shared too. The least
/// recently used are dropped first.
class SolveCache<T> {
  SolveCache(this.keep);

  /// How many solves are kept.
  final int keep;
  final Map<SolveKey, Future<T>> _solves = {};

  int get length => _solves.length;

  /// Whether a solve for [key] is kept (done, running or waiting).
  bool contains(SolveKey key) => _solves.containsKey(key);

  /// The solve for [key], starting it with [solve] if it isn't kept. When it
  /// is, [kept] is called first: the caller's chance to say it wants it too
  /// (a waiting solve can become more urgent: see the solve queue's join).
  Future<T> get(SolveKey key, Future<T> Function() solve, {void Function()? kept}) {
    final found = _solves.remove(key);
    if (found != null) {
      _solves[key] = found; // now the most recently used
      kept?.call();
      return found;
    }
    final future = solve();
    _solves[key] = future;
    // A failed solve isn't kept (nor one dropped from the queue, which fails
    // with SolveCancelled).
    future.then((_) {}, onError: (Object _) {
      if (identical(_solves[key], future)) _solves.remove(key);
    });
    while (_solves.length > keep) {
      _solves.remove(_solves.keys.first);
    }
    return future;
  }

  /// Forgets the solve for [key] now, rather than when its error arrives:
  /// for a solve taken off the queue, so the next request starts it again.
  void forget(SolveKey key) => _solves.remove(key);
}

/// What a solve depends on: the spot (as text) and the ranges, copied so
/// later changes to the caller's arrays can't change the key.
class SolveKey {
  SolveKey(this.spot, Iterable<Float64List> ranges)
      : ranges = [for (final r in ranges) Float64List.fromList(r)],
        hashCode = Object.hash(spot, Object.hashAll([for (final r in ranges) Object.hashAll(r)]));

  final String spot;
  final List<Float64List> ranges;

  @override
  final int hashCode;

  @override
  bool operator ==(Object other) {
    if (other is! SolveKey || other.hashCode != hashCode || other.spot != spot) return false;
    if (other.ranges.length != ranges.length) return false;
    for (var k = 0; k < ranges.length; k++) {
      final a = ranges[k], b = other.ranges[k];
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
    }
    return true;
  }
}
