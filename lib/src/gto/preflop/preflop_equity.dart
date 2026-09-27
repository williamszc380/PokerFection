import 'dart:typed_data';

import '../hand_classes.dart';

/// All-in equity between starting hands, read from assets/preflop_equity.bin
/// (made by tool/generate_preflop_equity.dart).
class PreflopEquity {
  PreflopEquity(this.values)
      : assert(values.length == handClassCount * handClassCount),
        closeness = Float64List.fromList([for (final e in values) e * (1 - e)]);

  factory PreflopEquity.fromBytes(ByteData bytes) {
    const count = handClassCount * handClassCount;
    if (bytes.lengthInBytes != count * 4) {
      throw FormatException('Expected ${count * 4} bytes, got ${bytes.lengthInBytes}');
    }
    return PreflopEquity(Float64List.fromList([
      for (var i = 0; i < count; i++) bytes.getFloat32(i * 4, Endian.little),
    ]));
  }

  /// `values[hand * 169 + opponent]`: how often `hand` beats `opponent` when
  /// both go all-in before the flop, counting ties as half.
  final Float64List values;

  /// `e * (1 - e)` for each matchup: largest when the matchup is close. Used
  /// to model the edge of acting last after the flop.
  final Float64List closeness;

  double of(int hand, int opponent) => values[hand * handClassCount + opponent];
}
