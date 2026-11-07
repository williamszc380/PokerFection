/// Gomoku: the rules, the game state, the bots and the coach. Pure Dart
/// with no Flutter and no platform libraries, so it runs in a worker, on
/// the server and in the browser (JavaScript or WebAssembly) alike.
///
/// The app needs only this library:
/// - [GomokuRules] and [WinRule]: the variant (Freestyle by default).
/// - [GomokuGame]: an immutable position; `play`, `legalMoves`, `result`.
/// - [GomokuBot]: a computer player at [BotLevel] easy, medium or hard.
/// - [GomokuCoach]: ranks moves, proves wins, explains and grades moves.
library;

export 'bot.dart' show BotLevel, BotStats, GomokuBot;
export 'coach.dart' show CoachBudget, GomokuAnalysis, GomokuCoach, MoveAnalysis, MoveGrade, MoveReason;
export 'game.dart' show GomokuGame, GomokuMove, GomokuResult, GomokuView;
export 'rules.dart' show GomokuRules, Stone, WinRule;
