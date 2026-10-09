import 'dart:typed_data';

/// [count] rounded up to a whole number of SIMD lanes (4 numbers), so the
/// layout is the same as in native builds.
int roundUpToLanes(int count) => (count + 3) & ~3;

/// 32-bit numbers ([f]).
class Vec {
  Vec(int length) : f = Float32List(roundUpToLanes(length));

  final Float32List f;

  int get length => f.length;
}

/// `v[at..at+length) = value`.
void vFill(Vec v, int at, int length, double value) => v.f.fillRange(at, at + length, value);

/// `to[at..] += from[from..]`.
void vAdd(Vec to, int at, Vec from, int fromAt, int length) {
  final t = to.f, s = from.f;
  for (var k = 0; k < length; k++) {
    t[at + k] += s[fromAt + k];
  }
}

/// `to[at..] += value`.
void vAddScalar(Vec to, int at, int length, double value) {
  final t = to.f;
  for (var k = at; k < at + length; k++) {
    t[k] += value;
  }
}

/// `to[at..] += scale * from[fromAt..]`.
void vAddScaled(Vec to, int at, Vec from, int fromAt, int length, double scale) {
  final t = to.f, s = from.f;
  for (var k = 0; k < length; k++) {
    t[at + k] += s[fromAt + k] * scale;
  }
}

/// `to[at..] = scale * from[fromAt..]`.
void vScale(Vec to, int at, Vec from, int fromAt, int length, double scale) {
  final t = to.f, s = from.f;
  for (var k = 0; k < length; k++) {
    t[at + k] = s[fromAt + k] * scale;
  }
}

/// `to[at..] *= scale * from[fromAt..]`.
void vMultiplyScaled(Vec to, int at, Vec from, int fromAt, int length, double scale) {
  final t = to.f, s = from.f;
  for (var k = 0; k < length; k++) {
    t[at + k] *= s[fromAt + k] * scale;
  }
}

/// The sum of `a[aAt..] * b[bAt..]`.
double vDot(Vec a, int aAt, Vec b, int bAt, int length) {
  final x = a.f, y = b.f;
  var sum = 0.0;
  for (var k = 0; k < length; k++) {
    sum += x[aAt + k] * y[bAt + k];
  }
  return sum;
}

/// A child's reach: `child = reach * (strategy + extra)`, with [extra] a
/// number, or the vector [tremble] (at [trembleAt]) when given. Returns the
/// child's total.
double vChildReach(Vec reach, int reachAt, Vec strategy, int strategyAt, double extra, Vec? tremble, int trembleAt,
    Vec child, int childAt, int length) {
  final r = reach.f, s = strategy.f, c = child.f;
  var sum = 0.0;
  if (tremble == null) {
    for (var k = 0; k < length; k++) {
      final v = r[reachAt + k] * (s[strategyAt + k] + extra);
      c[childAt + k] = v;
      sum += v;
    }
  } else {
    final t = tremble.f;
    for (var k = 0; k < length; k++) {
      final v = r[reachAt + k] * (s[strategyAt + k] + t[trembleAt + k]);
      c[childAt + k] = v;
      sum += v;
    }
  }
  return sum;
}

/// After walking an action: its values are `childValues`; copies them to
/// [actionValues] and adds them, times the action's [strategy], to [node].
void vTakeAction(Vec childValues, int childAt, Vec actionValues, int actionAt, Vec node, int nodeAt, Vec strategy,
    int strategyAt, int length) {
  final c = childValues.f, a = actionValues.f, n = node.f, s = strategy.f;
  for (var k = 0; k < length; k++) {
    final v = c[childAt + k];
    a[actionAt + k] = v;
    n[nodeAt + k] += s[strategyAt + k] * v;
  }
}

/// Regret matching: each hand plays each of [actions] (vectors [stride]
/// apart) in proportion to its positive regret, or all equally if none.
void vRegretMatch(Vec regrets, int at, Vec strategy, int strategyAt, int actions, int stride) {
  final r = regrets.f, s = strategy.f;
  for (var c = 0; c < stride; c++) {
    var total = 0.0;
    for (var i = 0; i < actions; i++) {
      final x = r[at + i * stride + c];
      if (x > 0) total += x;
    }
    for (var i = 0; i < actions; i++) {
      final x = r[at + i * stride + c];
      s[strategyAt + i * stride + c] = total > 0 ? (x > 0 ? x / total : 0) : 1 / actions;
    }
  }
}

/// Each hand's [sums] over [actions] scaled to add up to 1 (all equal if
/// they are all zero), into [average].
void vNormalize(Vec sums, int at, Vec average, int averageAt, int actions, int stride) {
  final r = sums.f, s = average.f;
  for (var c = 0; c < stride; c++) {
    var total = 0.0;
    for (var i = 0; i < actions; i++) {
      total += r[at + i * stride + c];
    }
    for (var i = 0; i < actions; i++) {
      s[averageAt + i * stride + c] = total > 0 ? r[at + i * stride + c] / total : 1 / actions;
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
  final r = regrets.f, m = sums.f, a = actionValues.f, v = nodeValues.f, re = reach.f, s = strategy.f;
  for (var i = 0; i < actions; i++) {
    final base = i * stride;
    for (var c = 0; c < stride; c++) {
      final index = at + base + c;
      final old = r[index];
      r[index] = old * (old > 0 ? positive : negative) + a[actionAt + base + c] - v[nodeAt + c];
      m[index] = m[index] * keep + re[reachAt + c] * s[strategyAt + base + c];
    }
  }
}
