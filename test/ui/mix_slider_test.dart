import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/ui/widgets/mix_slider.dart';

/// Shows a slider 326 px wide: 300 px between the end insets, so 1% = 3 px.
/// Returns the shares as the slider last set them.
Future<List<int> Function()> _pump(WidgetTester tester, List<double> shares, {required int upper}) async {
  var current = shares;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 326,
            child: StatefulBuilder(
              builder: (context, setState) => MixSlider(
                colors: [for (var i = 0; i < shares.length; i++) Colors.primaries[i]],
                shares: current,
                upper: upper,
                onChanged: (s) => setState(() => current = s),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return () => [for (final s in current) s.round()];
}

/// Where a handle at [percent] is: above the bar, or below it.
Offset _at(WidgetTester tester, double percent, {bool below = false}) {
  final rect = tester.getRect(find.byType(MixSlider));
  return Offset(rect.left + 13 + percent * 3, rect.center.dy + (below ? 11 : -11));
}

void main() {
  testWidgets('moving check off 100% uncovers the first raise, then the next', (tester) async {
    // Fold 0%, check 100%, two raise sizes and all-in at 0%; fold and check above the bar.
    final shares = await _pump(tester, [0, 100, 0, 0, 0], upper: 2);
    await tester.dragFrom(_at(tester, 100), const Offset(-90, 0));
    await tester.pump();
    expect(shares(), [0, 70, 30, 0, 0]);
    // Below the bar, the first raise's handle is the one on top at 100%.
    await tester.dragFrom(_at(tester, 100, below: true), const Offset(-30, 0));
    await tester.pump();
    expect(shares(), [0, 70, 20, 10, 0]);
    await tester.dragFrom(_at(tester, 100, below: true), const Offset(-15, 0));
    await tester.pump();
    expect(shares(), [0, 70, 20, 5, 5]);
  });

  testWidgets('handles push the ones in their way, and let go when dragged back', (tester) async {
    final shares = await _pump(tester, [0, 70, 20, 10], upper: 2);
    // Fold's handle, from 0% to 80%: pushes check's (at 70%) along.
    final gesture = await tester.startGesture(_at(tester, 0));
    await gesture.moveBy(const Offset(120, 0));
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump();
    expect(shares(), [80, 0, 10, 10]);
    // Back to 50%, still in the same drag: check's handle returns to 70%.
    await gesture.moveBy(const Offset(-90, 0));
    await tester.pump();
    expect(shares(), [50, 20, 20, 10]);
    await gesture.up();
    // Check's handle, from 70% to 95%, pushes the raise's (at 90%) below the bar.
    await tester.dragFrom(_at(tester, 70), const Offset(75, 0));
    await tester.pump();
    expect(shares(), [50, 45, 0, 5]);
  });

  testWidgets("the handles below the bar can't push the ones above", (tester) async {
    final shares = await _pump(tester, [10, 60, 20, 10], upper: 2);
    // The raise's handle, from 90% to 30%: stops at check's (70%).
    await tester.dragFrom(_at(tester, 90, below: true), const Offset(-180, 0));
    await tester.pump();
    expect(shares(), [10, 60, 0, 30]);
  });

  testWidgets('stacked handles: the earlier part is on top and gets picked up', (tester) async {
    // Fold and check both at 0%: dragging from there moves fold's handle.
    final shares = await _pump(tester, [0, 0, 100], upper: 2);
    await tester.dragFrom(_at(tester, 0), const Offset(60, 0));
    await tester.pump();
    expect(shares(), [20, 0, 80]);
  });

  testWidgets('a drag away from every handle changes nothing', (tester) async {
    final shares = await _pump(tester, [0, 100, 0], upper: 2);
    await tester.dragFrom(_at(tester, 50), const Offset(60, 0));
    await tester.pump();
    expect(shares(), [0, 100, 0]);
  });
}
