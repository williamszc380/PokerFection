import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/kit/seats.dart';

void main() {
  test('mixSeed gives these exact numbers, on every platform (checked natively and in JavaScript)', () {
    expect(mixSeed(0, 0, 0), 859548357);
    expect(mixSeed(1, 0, 0), 450913222);
    expect(mixSeed(0, 1, 0), 783154077);
    expect(mixSeed(0, 0, 1), 1308123718);
    expect(mixSeed(123456789, 7, 2), 1930993357);
    expect(mixSeed(2147483647, 300, 99), 345160639);
    expect(mixSeed(-1, 5, 3), 577590625);
  });

  test('every move and seat of a game gets its own seed, 0 to 2^31 − 1', () {
    final seeds = {
      for (var move = 0; move < 200; move++)
        for (final seat in [0, 1, 2, 3, 99]) mixSeed(424242, move, seat),
    };
    expect(seeds, hasLength(200 * 5));
    expect(seeds.every((s) => s >= 0 && s < 1 << 31), isTrue);
  });

  test('a fresh game seed is 31 random bits', () {
    final seeds = {for (var i = 0; i < 50; i++) freshGameSeed()};
    expect(seeds.length, greaterThan(45));
    expect(seeds.every((s) => s >= 0 && s < 1 << 31), isTrue);
    expect(freshGameSeed(Random(1)), freshGameSeed(Random(1)), reason: 'tests can fix it');
  });

  test('eight bot names and three levels', () {
    expect(kitBotNames, ['Ana', 'Ben', 'Kai', 'Lin', 'Mia', 'Raj', 'Sam', 'Yuki']);
    expect(KitLevel.values.map((l) => l.name), ['easy', 'medium', 'hard']);
  });
}
