/// The "?" of a setup row sits right beside what it explains, as on every
/// other row: on a wide setup the Training / Free Play row's "?" must not
/// drift off to the far edge of the column.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/ui/kit/help.dart';
import 'package:pokerfection/src/ui/kit/setup_kit.dart';

import 'shots.dart';

void main() {
  testWidgets('Training / Free Play: its "?" sits right after the two choices, on a wide column too', (tester) async {
    await pumpShot(
      tester,
      Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 520, child: ModeRow(training: true, onChanged: (_) {})),
        ),
      ),
      size: const Size(1280, 800),
    );
    await tester.pumpAndSettle();
    // The row draws its two choices as a ChoiceRow (setup_kit.dart).
    final choices = tester.getRect(find.byType(ChoiceRow<bool>));
    final free = tester.getRect(find.text('Free Play'));
    final help = tester.getRect(find.byType(TermsHelpButton));
    expect(help.left, greaterThanOrEqualTo(free.right), reason: 'the "?" comes after the last choice');
    expect(help.left - choices.right, lessThan(24), reason: 'choices end at ${choices.right}, "?" starts at ${help.left}');
    expect(help.left, lessThan(400), reason: 'not at the far edge of the 520 px column');
  });
}
