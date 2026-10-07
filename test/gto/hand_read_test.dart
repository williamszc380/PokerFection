import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/engine/cards.dart';
import 'package:pokerfection/src/engine/hand_evaluator.dart';
import 'package:pokerfection/src/gto/combos.dart';
import 'package:pokerfection/src/gto/hand_read.dart';
import 'package:pokerfection/src/gto/spot_strategy.dart';

void main() {
  test('a mistake gets its reason: what beats the hand, a draw, the pot odds', () {
    final hearts = parseCards('2h').first.suit;
    // They only ever hold two hearts: on three hearts, every hand of theirs is a flush.
    final flushes = Float64List.fromList([
      for (var c = 0; c < comboCount; c++) comboLow[c] & 3 == hearts && comboHigh[c] & 3 == hearts ? 1.0 : 0.0,
    ]);
    final read = readHand(parseCards('Qs Js'), parseCards('Ah Kh 9h'), flushes)!;
    expect(read.beaten, 1);
    expect(read.threat, HandCategory.flush);
    expect(reasonFor(MistakeKind.tooLoose, read: read), (kind: ReasonKind.behind, percent: 100, odds: 0, threat: HandCategory.flush));

    final draw = readHand(parseCards('5h 4h'), parseCards('Ah Kh 9c'), Float64List(comboCount)..fillRange(0, comboCount, 1))!;
    expect(draw.flushDraw, isTrue);
    expect(reasonFor(MistakeKind.tooTight, read: draw)?.kind, ReasonKind.flushDraw);
    // Facing a bet, folding too much: the price of a call says why.
    expect(reasonFor(MistakeKind.tooTight, read: draw, odds: 0.25)?.odds, 25);
    // Before the flop: how good the starting hand is.
    expect(reasonFor(MistakeKind.tooLoose, percentile: 0.95)?.kind, ReasonKind.weakStart);
    expect(reasonFor(MistakeKind.tooTight, percentile: 0.08)?.percent, 8);
    expect(reasonFor(MistakeKind.wrongSize, read: read), isNull);
  });
}
