import 'dart:typed_data';

/// [count] rounded up to a whole number of SIMD lanes (4 numbers).
int roundUpToLanes(int count) => (count + 3) & ~3;

/// 32-bit numbers, [f] one at a time and [x] four at a time (the same memory).
class Vec {
  factory Vec(int length) {
    final x = Float32x4List(roundUpToLanes(length) >> 2);
    return Vec._(x, Float32List.view(x.buffer));
  }

  Vec._(this.x, this.f);

  final Float32x4List x;
  final Float32List f;

  int get length => f.length;
}

/// `v[at..at+length) = value`.
void vFill(Vec v, int at, int length, double value) {
  final x = v.x, s = Float32x4.splat(value);
  for (var k = at >> 2, end = (at + length) >> 2; k < end; k++) {
    x[k] = s;
  }
}

/// `to[at..] += from[from..]`.
void vAdd(Vec to, int at, Vec from, int fromAt, int length) {
  final t = to.x, s = from.x;
  final t0 = at >> 2, s0 = fromAt >> 2;
  for (var k = 0; k < length >> 2; k++) {
    t[t0 + k] += s[s0 + k];
  }
}

/// `to[at..] += value`.
void vAddScalar(Vec to, int at, int length, double value) {
  final t = to.x, s = Float32x4.splat(value);
  for (var k = at >> 2, end = (at + length) >> 2; k < end; k++) {
    t[k] += s;
  }
}

/// `to[at..] += scale * from[fromAt..]`.
void vAddScaled(Vec to, int at, Vec from, int fromAt, int length, double scale) {
  final t = to.x, s = from.x, c = Float32x4.splat(scale);
  final t0 = at >> 2, s0 = fromAt >> 2;
  for (var k = 0; k < length >> 2; k++) {
    t[t0 + k] += s[s0 + k] * c;
  }
}

/// `to[at..] = scale * from[fromAt..]`.
void vScale(Vec to, int at, Vec from, int fromAt, int length, double scale) {
  final t = to.x, s = from.x, c = Float32x4.splat(scale);
  final t0 = at >> 2, s0 = fromAt >> 2;
  for (var k = 0; k < length >> 2; k++) {
    t[t0 + k] = s[s0 + k] * c;
  }
}

/// `to[at..] *= scale * from[fromAt..]`.
void vMultiplyScaled(Vec to, int at, Vec from, int fromAt, int length, double scale) {
  final t = to.x, s = from.x, c = Float32x4.splat(scale);
  final t0 = at >> 2, s0 = fromAt >> 2;
  for (var k = 0; k < length >> 2; k++) {
    t[t0 + k] *= s[s0 + k] * c;
  }
}

/// The sum of `a[aAt..] * b[bAt..]`.
double vDot(Vec a, int aAt, Vec b, int bAt, int length) {
  final x = a.x, y = b.x;
  final x0 = aAt >> 2, y0 = bAt >> 2;
  var sum = Float32x4.zero();
  for (var k = 0; k < length >> 2; k++) {
    sum += x[x0 + k] * y[y0 + k];
  }
  return sum.x + sum.y + sum.z + sum.w;
}

/// A child's reach: `child = reach * (strategy + extra)`, with [extra] a
/// number, or the vector [tremble] (at [trembleAt]) when given. Returns the
/// child's total.
double vChildReach(Vec reach, int reachAt, Vec strategy, int strategyAt, double extra, Vec? tremble, int trembleAt,
    Vec child, int childAt, int length) {
  final r = reach.x, s = strategy.x, c = child.x;
  final r0 = reachAt >> 2, s0 = strategyAt >> 2, c0 = childAt >> 2;
  var sum = Float32x4.zero();
  if (tremble == null) {
    final e = Float32x4.splat(extra);
    for (var k = 0; k < length >> 2; k++) {
      final v = r[r0 + k] * (s[s0 + k] + e);
      c[c0 + k] = v;
      sum += v;
    }
  } else {
    final t = tremble.x, t0 = trembleAt >> 2;
    for (var k = 0; k < length >> 2; k++) {
      final v = r[r0 + k] * (s[s0 + k] + t[t0 + k]);
      c[c0 + k] = v;
      sum += v;
    }
  }
  return sum.x + sum.y + sum.z + sum.w;
}

/// After walking an action: its values are `childValues`; copies them to
/// [actionValues] and adds them, times the action's [strategy], to [node].
void vTakeAction(Vec childValues, int childAt, Vec actionValues, int actionAt, Vec node, int nodeAt, Vec strategy,
    int strategyAt, int length) {
  final c = childValues.x, a = actionValues.x, n = node.x, s = strategy.x;
  final c0 = childAt >> 2, a0 = actionAt >> 2, n0 = nodeAt >> 2, s0 = strategyAt >> 2;
  for (var k = 0; k < length >> 2; k++) {
    final v = c[c0 + k];
    a[a0 + k] = v;
    n[n0 + k] += s[s0 + k] * v;
  }
}

/// Regret matching: each hand plays each of [actions] (vectors [stride]
/// apart) in proportion to its positive regret, or all equally if none.
void vRegretMatch(Vec regrets, int at, Vec strategy, int strategyAt, int actions, int stride) {
  final r = regrets.x, s = strategy.x;
  final lanes = stride >> 2, r0 = at >> 2, s0 = strategyAt >> 2;
  final zero = Float32x4.zero(), uniform = Float32x4.splat(1 / actions);
  for (var k = 0; k < lanes; k++) {
    var total = zero;
    for (var i = 0; i < actions; i++) {
      total += r[r0 + i * lanes + k].max(zero);
    }
    final some = total.greaterThan(zero);
    for (var i = 0; i < actions; i++) {
      s[s0 + i * lanes + k] = some.select(r[r0 + i * lanes + k].max(zero) / total, uniform);
    }
  }
}

/// Each hand's [sums] over [actions] scaled to add up to 1 (all equal if
/// they are all zero), into [average].
void vNormalize(Vec sums, int at, Vec average, int averageAt, int actions, int stride) {
  final r = sums.x, s = average.x;
  final lanes = stride >> 2, r0 = at >> 2, s0 = averageAt >> 2;
  final zero = Float32x4.zero(), uniform = Float32x4.splat(1 / actions);
  for (var k = 0; k < lanes; k++) {
    var total = zero;
    for (var i = 0; i < actions; i++) {
      total += r[r0 + i * lanes + k];
    }
    final some = total.greaterThan(zero);
    for (var i = 0; i < actions; i++) {
      s[s0 + i * lanes + k] = some.select(r[r0 + i * lanes + k] / total, uniform);
    }
  }
}

/// Discounted CFR's update of one decision's [regrets] and [sums]
/// (strategy sums, same layout) at [at], for [actions] vectors [stride]
/// apart: regrets are discounted (by [positive] or [negative]) and gain
/// each action's value over the decision's ([nodeValues]); sums are kept
/// by [keep] and gain the player's [reach] times the [strategy].
void vUpdate(Vec regrets, Vec sums, int at, Vec actionValues, int actionAt, Vec nodeValues, int nodeAt, Vec reach,
    int reachAt, Vec strategy, int strategyAt, int actions, int stride,
    {required double positive, required double negative, required double keep}) {
  final r = regrets.x, m = sums.x, a = actionValues.x, v = nodeValues.x, re = reach.x, s = strategy.x;
  final lanes = stride >> 2;
  final p = Float32x4.splat(positive), q = Float32x4.splat(negative), kp = Float32x4.splat(keep);
  final zero = Float32x4.zero();
  final v0 = nodeAt >> 2, re0 = reachAt >> 2;
  for (var i = 0; i < actions; i++) {
    final r0 = (at >> 2) + i * lanes, a0 = (actionAt >> 2) + i * lanes, s0 = (strategyAt >> 2) + i * lanes;
    for (var k = 0; k < lanes; k++) {
      final old = r[r0 + k];
      r[r0 + k] = old * old.greaterThan(zero).select(p, q) + a[a0 + k] - v[v0 + k];
      m[r0 + k] = m[r0 + k] * kp + re[re0 + k] * s[s0 + k];
    }
  }
}
