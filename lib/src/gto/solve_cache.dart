import 'dart:typed_data';

/// The last few solves, by everything that goes into them (the spot and
/// the players' ranges), so the same spot again is answered at once: a
/// replayed or drilled hand, or the same situation coming up at the table.
/// A solve still running is shared too. The least recently used are
/// dropped first.
class SolveCache<T> {
  SolveCache(this.keep);

  /// How many solves are kept.
  final int keep;
  final Map<SolveKey, Future<T>> _solves = {};

  int get length => _solves.length;

  /// The solve for [key], starting it with [solve] if it isn't kept.
  Future<T> get(SolveKey key, Future<T> Function() solve) {
    final kept = _solves.remove(key);
    if (kept != null) {
      _solves[key] = kept; // now the most recently used
      return kept;
    }
    final future = solve();
    _solves[key] = future;
    // A failed solve isn't kept.
    future.then((_) {}, onError: (Object _) {
      if (identical(_solves[key], future)) _solves.remove(key);
    });
    while (_solves.length > keep) {
      _solves.remove(_solves.keys.first);
    }
    return future;
  }
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
