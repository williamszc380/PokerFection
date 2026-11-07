import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_guides.dart';

import '../../../kit/shots.dart';

void main() {
  setUpAll(loadShotFonts);

  test('every example of the Combinations guide is read by the engine as the kind it shows', () {
    expect(landlordExamples.keys, unorderedEquals(PlayType.values), reason: 'every kind has an example');
    for (final MapEntry(key: type, value: ranks) in landlordExamples.entries) {
      final readings = classifyPlay(parseRanks(ranks));
      expect(readings.map((p) => p.type), contains(type), reason: '$ranks is a ${type.name}');
      expect(landlordExample(type).type, type);
    }
  });

  test('each example beats a lower one of its kind, and the bomb and rocket beat other kinds', () {
    final pair = landlordExample(PlayType.pair);
    final lowerPair = classifyPlay(parseRanks('55')).single;
    expect(pair.beats(lowerPair), isTrue);
    for (final type in PlayType.values) {
      if (type == PlayType.bomb || type == PlayType.rocket) continue;
      expect(landlordExample(PlayType.bomb).beats(landlordExample(type)), isTrue, reason: 'bomb over ${type.name}');
    }
    expect(landlordExample(PlayType.rocket).beats(landlordExample(PlayType.bomb)), isTrue);
  });

  testWidgets('the guide shows every kind, with its cards', (tester) async {
    await pumpShot(
      tester,
      const LandlordCombinationsGuide(),
      size: const Size(1280, 800),
      language: AppLanguage.chinese,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rank order')), findsOneWidget);
    for (final type in PlayType.values) {
      await tester.scrollUntilVisible(find.byKey(ValueKey('kind ${type.name}')), 200);
      expect(find.byKey(ValueKey('kind ${type.name}')), findsOneWidget);
    }
  });
}
