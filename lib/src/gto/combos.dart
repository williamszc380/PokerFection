import 'dart:typed_data';

import 'hand_classes.dart';

/// Number of two-card combinations (52 choose 2).
const comboCount = 1326;

/// The two cards (0-51) of each combination; the lower card first.
final Int32List comboLow = _table.$1;
final Int32List comboHigh = _table.$2;

/// Starting-hand class (0-168) of each combination.
final Int32List comboClass = _table.$3;

final Int32List _indexOf = _table.$4;

/// Index (0-1325) of the combination made of cards [a] and [b].
int comboIndex(int a, int b) => _indexOf[a * 52 + b];

final (Int32List, Int32List, Int32List, Int32List) _table = () {
  final low = Int32List(comboCount), high = Int32List(comboCount), cls = Int32List(comboCount);
  final index = Int32List(52 * 52)..fillRange(0, 52 * 52, -1);
  var i = 0;
  for (var a = 0; a < 52; a++) {
    for (var b = a + 1; b < 52; b++) {
      low[i] = a;
      high[i] = b;
      cls[i] = handClassIndex(a >> 2, b >> 2, suited: (a & 3) == (b & 3));
      index[a * 52 + b] = i;
      index[b * 52 + a] = i;
      i++;
    }
  }
  return (low, high, cls, index);
}();
