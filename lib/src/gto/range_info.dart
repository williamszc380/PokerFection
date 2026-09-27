import 'dart:typed_data';

import 'combos.dart';
import 'hand_classes.dart';

/// A player's range by starting hand, for display.
class RangeInfo {
  RangeInfo._(this.frequency, this.combos);

  /// From weights per starting hand (0-1). Combinations using [dead] cards
  /// (the board, the viewer's own cards) are left out.
  factory RangeInfo.fromClasses(Float64List classWeights, Set<int> dead) {
    final combos = _possibleCombos(dead);
    return RangeInfo._(
      Float64List.fromList([for (var h = 0; h < handClassCount; h++) combos[h] == 0 ? 0 : classWeights[h]]),
      combos,
    );
  }

  /// From weights per two-card combination (0-1325).
  factory RangeInfo.fromCombos(Float64List comboWeights, Set<int> dead) {
    final sums = Float64List(handClassCount);
    for (var c = 0; c < comboCount; c++) {
      if (dead.contains(comboLow[c]) || dead.contains(comboHigh[c])) continue;
      sums[comboClass[c]] += comboWeights[c];
    }
    final combos = _possibleCombos(dead);
    return RangeInfo._(
      Float64List.fromList([for (var h = 0; h < handClassCount; h++) combos[h] == 0 ? 0 : sums[h] / combos[h]]),
      combos,
    );
  }

  static Int32List _possibleCombos(Set<int> dead) {
    final combos = Int32List(handClassCount);
    for (var c = 0; c < comboCount; c++) {
      if (!dead.contains(comboLow[c]) && !dead.contains(comboHigh[c])) combos[comboClass[c]]++;
    }
    return combos;
  }

  /// For each starting hand: how often the player holds it and plays this
  /// way (0-1), averaged over its possible combinations.
  final Float64List frequency;

  /// For each starting hand: how many of its combinations are possible.
  final Int32List combos;

  /// Weighted number of combinations in the range.
  double get weight {
    var w = 0.0;
    for (var h = 0; h < handClassCount; h++) {
      w += frequency[h] * combos[h];
    }
    return w;
  }

  /// Share of all possible hands that play this way.
  double get share {
    var possible = 0;
    for (final c in combos) {
      possible += c;
    }
    return possible == 0 ? 0 : weight / possible;
  }

  /// Chance that the player holds starting hand [h], given the range.
  double shareOf(int h) {
    final w = weight;
    return w == 0 ? 0 : frequency[h] * combos[h] / w;
  }
}
