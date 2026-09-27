import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/engine/cards.dart';
import 'package:pokerfection/src/gto/hand_classes.dart';
import 'package:pokerfection/src/gto/preflop/preflop_equity.dart';

PreflopEquity loadEquity() =>
    PreflopEquity.fromBytes(ByteData.sublistView(File('assets/preflop_equity.bin').readAsBytesSync()));

int cls(String cards) {
  final c = parseCards(cards);
  return handClassOf(c[0], c[1]);
}

void main() {
  test('169 starting hands covering all 1326 combinations', () {
    final names = {for (var i = 0; i < handClassCount; i++) handClassName(i)};
    expect(names, hasLength(169));
    var combos = 0;
    for (var i = 0; i < handClassCount; i++) {
      expect(handClassCards(i), hasLength(handClassCombos(i)));
      combos += handClassCombos(i);
    }
    expect(combos, 1326);
    expect(handClassName(cls('As Kd')), 'AKo');
    expect(handClassName(cls('Kd Ad')), 'AKs');
    expect(handClassName(cls('7c 7h')), '77');
  });

  test('equity table matches well-known matchups', () {
    final eq = loadEquity();
    // Published all-in odds, within Monte Carlo noise.
    expect(eq.of(cls('As Ah'), cls('Ks Kh')), closeTo(0.82, 0.01));
    expect(eq.of(cls('Qs Qh'), cls('As Ks')), closeTo(0.54, 0.01));
    expect(eq.of(cls('Qs Qh'), cls('As Kd')), closeTo(0.57, 0.01));
    expect(eq.of(cls('2s 2h'), cls('As Kd')), closeTo(0.525, 0.01));
    expect(eq.of(cls('As Ah'), cls('7c 2d')), closeTo(0.875, 0.01));
    expect(eq.of(cls('Ks Kh'), cls('Ks Qs')), greaterThan(0.6));
  });

  test('equity table is consistent both ways', () {
    final eq = loadEquity();
    for (var h = 0; h < handClassCount; h++) {
      expect(eq.of(h, h), 0.5);
      for (var o = 0; o < handClassCount; o++) {
        expect(eq.of(h, o) + eq.of(o, h), closeTo(1, 1e-6));
      }
    }
  });
}
