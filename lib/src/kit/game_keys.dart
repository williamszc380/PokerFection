/// The four new games' keys. One key names a game everywhere: its folders
/// (`lib/src/games/<key>/`, `lib/src/ui/games/<key>/`), its jobs
/// (`<key>.coach`), its saved most recent game (`last_<key>.json`) and
/// `GameRecord.game`. Kept as plain strings so pure Dart code (the worker,
/// the engines' glue) can use them without the app's `GameId`.
abstract final class GameKeys {
  static const gomoku = 'gomoku';
  static const bigTwo = 'big_two';
  static const doudizhu = 'doudizhu';
  static const blackjack = 'blackjack';

  /// Every key, in the Home screen's order.
  static const all = [gomoku, bigTwo, doudizhu, blackjack];
}
