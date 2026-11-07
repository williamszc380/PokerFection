/// Seeded random numbers that come out the same on the Dart VM and in
/// JavaScript.
///
/// `dart:math`'s `Random(seed)` is not promised to give the same sequence on
/// every platform, and JavaScript numbers hold only 53-bit integers. This
/// generator is xorshift128 (Marsaglia, "Xorshift RNGs", 2003), which needs
/// only 32-bit shifts and xors, so a test seeded on Windows replays exactly
/// in a browser.
library;

/// Multiplies two 32-bit unsigned numbers and keeps the low 32 bits, without
/// ever forming a product above 2^53 (JavaScript's `Math.imul`).
int imul32(int a, int b) {
  final al = a & 0xffff;
  final ah = (a >> 16) & 0xffff;
  return (al * b + (((ah * b) & 0xffff) << 16)) & 0xffffffff;
}

/// Scrambles a 32-bit number (the "lowbias32" mixer by Chris Wellons), used
/// to turn one seed into several unrelated starting words.
int mix32(int x) {
  x &= 0xffffffff;
  x ^= x >> 16;
  x = imul32(x, 0x7feb352d);
  x ^= x >> 15;
  x = imul32(x, 0x846ca68b);
  x ^= x >> 16;
  return x & 0xffffffff;
}

/// A small, fast, seeded random number generator for the engine.
class GameRandom {
  /// Starts the sequence for [seed]. Any int works, including negative ones.
  GameRandom(int seed) {
    final lo = seed & 0xffffffff;
    final hi = (seed ~/ 4294967296) & 0xffffffff;
    _x = mix32(lo ^ 0x9e3779b9);
    _y = mix32(hi ^ _x ^ 0x243f6a88);
    _z = mix32(_y ^ 0xb7e15162);
    _w = mix32(_z ^ lo ^ 0x6a09e667);
    if ((_x | _y | _z | _w) == 0) _w = 1;
  }

  GameRandom._copy(GameRandom o) : _x = o._x, _y = o._y, _z = o._z, _w = o._w;

  late int _x, _y, _z, _w;

  /// An independent generator that continues exactly as this one would.
  GameRandom copy() => GameRandom._copy(this);

  /// The next number in 0 .. 2^32 - 1.
  int nextUint32() {
    var t = _x ^ ((_x << 11) & 0xffffffff);
    t ^= t >> 8;
    _x = _y;
    _y = _z;
    _z = _w;
    _w = (_w ^ (_w >> 19) ^ t) & 0xffffffff;
    return _w;
  }

  /// A number in 0 .. [max] - 1 ([max] at most 2^20, plenty for cards).
  int nextInt(int max) => (nextUint32() * max) ~/ 4294967296;

  /// A number in [0, 1).
  double nextDouble() => nextUint32() / 4294967296;

  /// A fresh seed for a child generator, so separate jobs can each get their
  /// own reproducible stream.
  int nextSeed() => nextUint32();

  /// Shuffles [list] in place (Fisher–Yates).
  void shuffle<T>(List<T> list) {
    for (var i = list.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
  }
}
