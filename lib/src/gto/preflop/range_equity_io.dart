import 'dart:typed_data';

import '../hand_classes.dart';
import '../vectors.dart';
import 'preflop_equity.dart';

const _h = handClassCount;

/// Four hands per SIMD number: 169 hands take 43.
const _lanes = (_h + 3) ~/ 4;

/// Each starting hand's equity (and closeness) against a weighted range,
/// the preflop solver's most frequent sum. The table is kept by opponent
/// hand, in 32-bit numbers, so each opponent hand in the range adds its
/// whole column four hands at a time.
class RangeEquity {
  RangeEquity(PreflopEquity equity)
      : _values = _columns(equity.values),
        _closeness = _columns(equity.closeness);

  /// `columns[opponent * 43 + k]`: the table's entries for hands 4k to 4k+3 against `opponent`.
  static Float32x4List _columns(Float64List table) {
    final columns = Float32x4List(_h * _lanes);
    final entries = Float32List.view(columns.buffer);
    for (var o = 0; o < _h; o++) {
      for (var x = 0; x < _h; x++) {
        entries[o * _lanes * 4 + x] = table[x * _h + o];
      }
    }
    return columns;
  }

  final Float32x4List _values;
  final Float32x4List _closeness;

  /// Writes, for every hand, its equity against the range whose weights
  /// start at `range[from]` (unnormalized: weighted by the range) into
  /// `out[at + hand]`, and with [close], its closeness into `close[at + hand]`.
  void against(Vec range, int from, Vec out, Vec? close, int at) {
    final weights = range.f, values = _values, sum = out.x;
    final s0 = at >> 2;
    for (var k = 0; k < _lanes; k++) {
      sum[s0 + k] = Float32x4.zero();
    }
    if (close == null) {
      for (var o = 0; o < _h; o++) {
        final w = weights[from + o];
        if (w <= 0) continue;
        final weight = Float32x4.splat(w);
        final column = o * _lanes;
        for (var k = 0; k < _lanes; k++) {
          sum[s0 + k] += values[column + k] * weight;
        }
      }
      return;
    }
    final closeness = _closeness, closeSum = close.x;
    for (var k = 0; k < _lanes; k++) {
      closeSum[s0 + k] = Float32x4.zero();
    }
    for (var o = 0; o < _h; o++) {
      final w = weights[from + o];
      if (w <= 0) continue;
      final weight = Float32x4.splat(w);
      final column = o * _lanes;
      for (var k = 0; k < _lanes; k++) {
        sum[s0 + k] += values[column + k] * weight;
        closeSum[s0 + k] += closeness[column + k] * weight;
      }
    }
  }
}
