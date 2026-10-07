import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/gto/raise_sizes.dart';

void main() {
  test('every Fibonacci number of big blinds from the min-raise up to all-in', () {
    // 100 BB, first in (min-raise to 2 BB).
    expect(raiseSizes(minTo: 200, allInTo: 10000, bigBlind: 100), [200, 300, 500, 800, 1300, 2100, 3400, 5500, 8900]);
    // Facing an open to 2.5 BB (min-raise to 4 BB).
    expect(raiseSizes(minTo: 400, allInTo: 10000, bigBlind: 100), [500, 800, 1300, 2100, 3400, 5500, 8900]);
    // Facing a 3-bet to 10 BB after opening to 2.5 BB (min-raise to 17.5 BB).
    expect(raiseSizes(minTo: 1750, allInTo: 10000, bigBlind: 100), [2100, 3400, 5500, 8900]);
    // A flop bet with 97.5 BB behind (min-bet 1 BB).
    expect(raiseSizes(minTo: 100, allInTo: 9750, bigBlind: 100), [100, 200, 300, 500, 800, 1300, 2100, 3400, 5500, 8900]);
    // Exactly 89 BB: that's all-in, not a size.
    expect(raiseSizes(minTo: 200, allInTo: 8900, bigBlind: 100), [200, 300, 500, 800, 1300, 2100, 3400, 5500]);
    // Too short for any size: all-in only.
    expect(raiseSizes(minTo: 200, allInTo: 200, bigBlind: 100), isEmpty);
  });

  test('all-in counts only what someone still in can call', () {
    expect(coveredAllIn(30000, [10000, 5000]), 10000);
    expect(coveredAllIn(8000, [10000, 5000]), 8000);
  });

  test('bots round to the nearest 0.5 BB', () {
    expect(roundToHalfBb(1725, 100), 1750);
    expect(roundToHalfBb(1720, 100), 1700);
    expect(roundToHalfBb(250.0, 100), 250);
  });
}
