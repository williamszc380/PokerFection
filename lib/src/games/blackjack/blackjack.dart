/// Blackjack: the rules and presets, the shoe, the round, each seat's
/// view, the bots, the exact solver, the basic strategy charts and the
/// coach. Pure Dart with no Flutter and no platform libraries, so it runs
/// in a worker and in the browser (JavaScript or WebAssembly) alike.
///
/// The app needs only this library:
/// - [BlackjackRules] and [BlackjackPreset]: the table (Standard by
///   default).
/// - [BlackjackTable] / [Shoe] / [BlackjackRound]: deal a round, read
///   `turn` and `legalActions()`, `apply` actions, then `result(seat)`.
/// - [BlackjackView]: what one seat may know (`round.viewFor(seat)`).
/// - [BlackjackBot]: a computer player at [BotLevel] easy, medium or hard.
/// - [BlackjackCoach]: values every legal action (FRESH and SEEN), picks
///   the best, explains and grades.
/// - [BasicStrategyChart]: the chart for any rules, and its house edge.
library;

export 'action.dart' show BlackjackAction;
export 'bot.dart';
export 'cards.dart';
export 'coach.dart';
export 'count.dart';
export 'dealer.dart' show dealerOutcomes, dealer17, dealerBust, dealerBlackjack, dealerOutcomeCount, DealerGraph;
export 'random.dart' show GameRandom;
export 'round.dart';
export 'rules.dart';
export 'shoe.dart';
export 'solver.dart';
export 'strategy.dart';
