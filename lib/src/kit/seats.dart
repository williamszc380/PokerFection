/// Bots' levels and names, and the seeds every game derives from its one
/// game seed.
library;

import 'dart:math';

/// How strong the bots play (each game maps it to its engine's level).
enum KitLevel { easy, medium, hard }

/// The bots' names, given out in this order.
const kitBotNames = ['Ana', 'Ben', 'Kai', 'Lin', 'Mia', 'Raj', 'Sam', 'Yuki'];

/// A new game's seed: 31 random bits, the one random thing in a game.
/// Everything else (bots, the coach) gets its seed from [mixSeed], so a
/// saved game replays exactly.
int freshGameSeed([Random? random]) => (random ?? Random.secure()).nextInt(1 << 31);

/// The seed for move [moveIndex] by [seat] of the game with [gameSeed] (the
/// coach uses seat 99). Always the same number on every platform: a fixed
/// mixer (MurmurHash3's finalizer) using only 32-bit steps, so JavaScript's
/// numbers give the same results as the apps'. (`Object.hash` is seeded
/// afresh on every run, and `Random()` differs, so neither is used.)
/// The result is 0 to 2^31 − 1.
int mixSeed(int gameSeed, int moveIndex, int seat) {
  var h = _finish((gameSeed & _mask) ^ 0x9e3779b9);
  h = _finish(h ^ ((moveIndex + 0x7f4a7c15) & _mask));
  h = _finish(h ^ ((seat + 0x632be5ab) & _mask));
  return h & 0x7fffffff;
}

const _mask = 0xffffffff;

int _finish(int h) {
  h &= _mask;
  h ^= h >>> 16;
  h = _mul32(h, 0x85ebca6b);
  h ^= h >>> 13;
  h = _mul32(h, 0xc2b2ae35);
  h ^= h >>> 16;
  return h;
}

/// a × b modulo 2^32, in halves so no step passes 2^53 (exact in JavaScript).
int _mul32(int a, int b) {
  final low = (a & 0xffff) * b;
  final high = (((a >>> 16) * b) & 0xffff) << 16;
  return (low + high) & _mask;
}
