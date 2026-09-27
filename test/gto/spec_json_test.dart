import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/engine/rules.dart';
import 'package:pokerfection/src/gto/postflop/postflop_tree.dart';
import 'package:pokerfection/src/gto/preflop/preflop_tree.dart';

// The web version sends specs to its solver worker as JSON (web_workers.dart).
void main() {
  test('preflop specs survive the trip to the web worker', () {
    final spec = PreflopSpec(
      stacks: [4000, 10000, 1500, 8000],
      ante: 10,
      raiseRule: RaiseRule.values.last,
      raiseMultiples: const [2.2, 3.0],
      history: const [PreflopAction(PreflopMove.fold), PreflopAction(PreflopMove.raise, 250)],
      hero: 2,
    );
    final copy = PreflopSpec.fromJson(jsonDecode(jsonEncode(spec.toJson())) as Map<String, Object?>);
    expect(copy.key, spec.key);
    expect(copy.toJson(), spec.toJson());
  });

  test('postflop specs survive the trip to the web worker', () {
    final spec = PostflopSpec(
      board: const [0, 13, 26, 39],
      pot: 550,
      stacks: const [9000, 7000],
      bigBlind: 100,
      raiseRule: RaiseRule.values.last,
      hero: 1,
      heroSizes: const [0.5, 1.2],
      botBetSizes: const [0.4],
      botRaiseSizes: const [0.9],
    );
    final copy = PostflopSpec.fromJson(jsonDecode(jsonEncode(spec.toJson())) as Map<String, Object?>);
    expect(copy.toJson(), spec.toJson());
  });
}
