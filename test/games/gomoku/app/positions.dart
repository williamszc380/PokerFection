/// Games and positions the app tests share.
library;

import 'package:pokerfection/src/games/gomoku/gomoku.dart';

/// Whole games Easy and Medium played (each ends in five).
const sampleGames = [
  (GomokuRules.freestyle, 'h8 g7 g8 f8 i5 e9 h6 d10 c11 e10 f10 e11 e12 c9 f12 b8 a7 b10 e7 b9 b7 d9 f9 a9'),
  (GomokuRules.freestyle, 'h8 f6 i7 j6 j8 k8 h6 k9 k7 i9 h7 h5 j7 l7 g7'),
  (GomokuRules.standard, 'h8 f8 g9 f10 f9 e9 g7 d8 g8 g11 c7 h12'),
  (GomokuRules.renju, 'h8 f6 i7 j6 j8 k8 h6 k9 h5 h4 g5 f4 h7 h9 g7 j7 g6 k7 g8 g9 g4'),
  (GomokuRules.freestyle19, 'j10 h8 k9 l8 l10 i10 j8 m11 j7 j6 i9 h9 k7 h6 h10 g11 l6'),
];

/// A Renju game (from renju_test.dart) where Black must now pass: every
/// empty point left is forbidden to it.
const stuckRenju =
    'h6 k4 i5 k9 h13 m3 f14 a11 g7 b11 d2 h2 b3 l2 m6 f8 a9 n7 b9 g1 a13 j10 k13 n8 b13 e6 g15 o3 k5 m15 '
    'b12 n15 a15 o11 m7 d4 m9 m4 j15 k10 f4 c9 e4 a7 i6 n10 h1 d15 o2 o15 k11 b5 k12 i3 e2 j9 i13 a6 i14 m1 '
    'n2 f10 j3 i8 b15 c10 f2 b1 g10 l14 o13 g11 o14 m13 b8 a8 d9 l4 n14 f7 g4 j1 a5 b10 e12 l8 c13 a10 h11 c15 '
    'j7 e3 f6 e1 m2 d5 d8 e5 o12 f1 m14 g14 b14 b7 h9 i1 a2 j2 n4 g12 m12 j12 i11 g2 n5 l3 o1 c6 c2 m8 c4 h12 '
    'h7 l13 l7 c14 e14 h4 n13 a4 e9 k7 o5 g8 f12 i10 f13 d3 o10 o9 n9 d14 o6 l12 h14 a3 a1 f15 e8 g13 j14 j5 '
    'l1 c11 e13 c3 h3 a14 o8 e7 i2 i15 l6 g9 k1 g5 c5 b2 n12 o4 i4 n1 d11 k2 l9 i7 g3 k14 d1 n11 j13 m11 d6 j4 '
    'k15 i12 l15 d13 o7 e15 c1 d12 i9 b6 f11 b4 c8 n6 h10 g6 j8 h15 l10 c12 h5 j11 e10 m10 d10 a12 c7 f5 n3 f9 '
    'j6 f3 k3 l11 m5 l5';

/// Black's four-three at i8 (the coach's tests): a forced win in 3.
/// Black f8 g8 h8 i9 i10, White e8 a1 a15 o1 o15, Black to move.
const fourThree = 'f8 e8 g8 a1 h8 a15 i9 o1 i10 o15';

/// White's four d10-g10, closed at c10: Black must block at h10.
/// Black c10 h3 j3 l3, White d10 e10 f10 g10, Black to move.
const mustBlock = 'c10 d10 h3 e10 j3 f10 l3 g10';
