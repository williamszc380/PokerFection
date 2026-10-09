import 'dart:typed_data';

import '../hand_classes.dart';
import '../vectors.dart';
import 'preflop_equity.dart';

const _h = handClassCount;

/// Each starting hand's equity (and closeness) against a weighted range,
/// the preflop solver's most frequent sum, skipping the hands the range
/// doesn't hold.
class RangeEquity {
  RangeEquity(this._equity);

  final PreflopEquity _equity;
  final Int32List _nonZeroIndex = Int32List(_h);
  final Float64List _nonZeroValue = Float64List(_h);

  /// Writes, for every hand, its equity against the range whose weights
  /// start at `range[from]` (unnormalized: weighted by the range) into
  /// `out[at + hand]`, and with [close], its closeness into `close[at + hand]`.
  void against(Vec range, int from, Vec out, Vec? close, int at) {
    final indices = _nonZeroIndex, weights = _nonZeroValue, r = range.f, o = out.f;
    var count = 0;
    for (var x = 0; x < _h; x++) {
      final w = r[from + x];
      if (w > 0) {
        indices[count] = x;
        weights[count++] = w;
      }
    }
    final values = _equity.values, closeness = _equity.closeness;
    for (var x = 0; x < _h; x++) {
      final row = x * _h;
      var e = 0.0, cl = 0.0;
      if (close == null) {
        for (var k = 0; k < count; k++) {
          e += values[row + indices[k]] * weights[k];
        }
      } else {
        for (var k = 0; k < count; k++) {
          final index = row + indices[k];
          final w = weights[k];
          e += values[index] * w;
          cl += closeness[index] * w;
        }
        close.f[at + x] = cl;
      }
      o[at + x] = e;
    }
  }
}
