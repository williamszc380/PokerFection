/// The app's theme gives every clickable Material control the hand under
/// the mouse (Flutter's own default is the hand in a browser only, the
/// plain arrow on Windows), and a greyed-out one the arrow.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/ui/games.dart';
import 'package:pokerfection/src/ui/home_screen.dart';

import 'shots.dart';

void main() {
  testWidgets("the theme's buttons, switches, checkboxes, sliders and menus show the hand; greyed out, the arrow",
      (tester) async {
    var on = false;
    final controls = <String, Widget>{
      'filled': FilledButton(onPressed: () {}, child: const Text('filled')),
      'tonal': FilledButton.tonal(onPressed: () {}, child: const Text('tonal')),
      'outlined': OutlinedButton(onPressed: () {}, child: const Text('outlined')),
      'text': TextButton(onPressed: () {}, child: const Text('text')),
      'elevated': ElevatedButton(onPressed: () {}, child: const Text('elevated')),
      'icon': IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
      'segments': SegmentedButton<int>(
        segments: const [ButtonSegment(value: 0, label: Text('A')), ButtonSegment(value: 1, label: Text('B'))],
        selected: const {0},
        onSelectionChanged: (_) {},
      ),
      'switch': Switch(value: on, onChanged: (v) => on = v),
      'checkbox': Checkbox(value: on, onChanged: (v) {}),
      'slider': SizedBox(width: 120, child: Slider(value: 0.5, onChanged: (_) {})),
      'menu': PopupMenuButton<int>(
        icon: const Icon(Icons.menu),
        itemBuilder: (_) => const [PopupMenuItem(value: 1, child: Text('item'))],
      ),
      'disabled': const FilledButton(onPressed: null, child: Text('disabled')),
    };
    await pumpShot(
      tester,
      Scaffold(
        body: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final MapEntry(:key, :value) in controls.entries) KeyedSubtree(key: ValueKey(key), child: value)],
        ),
      ),
      size: const Size(1000, 400),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(999, 399));
    addTearDown(mouse.removePointer);
    Future<MouseCursor?> cursorOn(Finder finder) async {
      await mouse.moveTo(tester.getCenter(finder));
      await tester.pump();
      return RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);
    }

    for (final name in controls.keys) {
      expect(
        await cursorOn(find.byKey(ValueKey(name))),
        name == 'disabled' ? SystemMouseCursors.basic : SystemMouseCursors.click,
        reason: name,
      );
    }
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(await cursorOn(find.text('item')), SystemMouseCursors.click, reason: "the menu's items");
  });

  testWidgets("Home's tiles: the hand on a game that opens, the arrow on one greyed out; the language button too",
      (tester) async {
    await pumpShot(tester, const HomeScreen(), size: const Size(1280, 800));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    Future<MouseCursor?> cursorOn(Finder finder) async {
      await mouse.moveTo(tester.getCenter(finder));
      await tester.pump();
      return RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);
    }

    for (final game in games) {
      expect(
        await cursorOn(find.byKey(ValueKey('game ${game.id.name}'))),
        game.ready ? SystemMouseCursors.click : SystemMouseCursors.basic,
        reason: '${game.id.name}${game.ready ? '' : ': Soon'}',
      );
    }
    expect(await cursorOn(find.byIcon(Icons.language)), SystemMouseCursors.click);
  });
}
