import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/gto/solve_cache.dart';

void main() {
  test('the same spot and ranges reuse the solve; anything else solves again', () async {
    final cache = SolveCache<int>(2);
    var solves = 0;
    Future<int> solve() async => ++solves;
    final range = Float64List.fromList([0.5, 1, 0]);

    expect(await cache.get(SolveKey('a', [range]), solve), 1);
    // A copy of the same numbers is the same key, and changing the caller's
    // array afterwards doesn't change what was kept.
    final copy = Float64List.fromList(range);
    range[0] = 0.25;
    expect(await cache.get(SolveKey('a', [copy]), solve), 1);
    expect(await cache.get(SolveKey('a', [range]), solve), 2);
    expect(await cache.get(SolveKey('b', [copy]), solve), 3);
    // Only the last two are kept.
    expect(await cache.get(SolveKey('a', [copy]), solve), 4);
    expect(cache.length, 2);
  });

  test('a failed solve is not kept', () async {
    final cache = SolveCache<int>(4);
    final key = SolveKey('a', [Float64List(3)]);
    await expectLater(cache.get(key, () async => throw StateError('no')), throwsStateError);
    expect(await cache.get(key, () async => 7), 7);
  });
}
