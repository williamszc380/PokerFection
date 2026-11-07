import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/kit/game_keys.dart';
import 'package:pokerfection/src/ui/games.dart';

void main() {
  test("each new game's GameId names the same key as GameKeys, in Home's order", () {
    final newGames = GameId.values.where((id) => id != GameId.holdem);
    expect([for (final id in newGames) id.key], GameKeys.all);
  });

  test("Hold'em has no key: it keeps its own names", () {
    expect(() => GameId.holdem.key, throwsUnsupportedError);
  });
}
