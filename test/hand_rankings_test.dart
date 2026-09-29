import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/main.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/engine/cards.dart';
import 'package:pokerfection/src/engine/hand_evaluator.dart';
import 'package:pokerfection/src/ui/hand_rankings_screen.dart';

import 'widget_test.dart' show setScreen;

void main() {
  test('each example hand beats the next one', () {
    final hands = [
      'As Ks Qs Js Ts', '9h 8h 7h 6h 5h', 'Qc Qd Qh Qs 7d', 'Kh Kd Ks 7c 7h', 'Ad Jd 8d 6d 2d',
      'Tc 9d 8s 7h 6c', '8c 8d 8h Ks 3d', 'Jh Jc 4s 4d As', 'Th Tc Ad 7s 3h', 'Ah Qd 9c 6s 2h',
    ].map((h) => evaluateHand(parseCards(h))).toList();
    for (var i = 0; i + 1 < hands.length; i++) {
      expect(hands[i] > hands[i + 1], isTrue, reason: 'hand ${i + 1}');
    }
  });

  testWidgets('the main menu opens the hand rankings', (tester) async {
    setScreen(tester, const Size(1280, 900));
    await tester.pumpWidget(PokerFectionApp(settings: AppSettings()));
    await tester.tap(find.text('Hand Rankings'));
    await tester.pumpAndSettle();
    expect(find.byType(HandRankingsScreen), findsOneWidget);
    expect(find.text('Royal Flush'), findsOneWidget);
    expect(find.text('High Card'), findsOneWidget);
  });
}
