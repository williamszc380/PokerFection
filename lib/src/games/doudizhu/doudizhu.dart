/// Fight the Landlord (Dou Dizhu): everything the app needs, in one import.
///
/// Pure Dart with no Flutter, dart:io or isolates, so it runs the same on
/// every platform and inside the app's worker pool (web included).
/// - [DdzGame]: a deal (auction, play, score); [DdzGame.viewFor] gives
///   what one seat may know.
/// - [DdzRules]: the rule switches, with presets.
/// - [DdzBot]: computer players (Easy, Medium, Hard).
/// - [DdzCoach]: rates every move of a decision ("GTO" in the app).
/// - [DdzCardCount]: the card counter.
/// - [DdzDealOrder]: how the deal goes round the table, for the step that
///   shows who bids first.
library;

export 'bot.dart';
export 'cards.dart';
export 'coach.dart';
export 'deal_order.dart';
export 'game.dart';
export 'play_gen.dart' show leadPlays, beatingPlays, canBeat;
export 'plays.dart';
export 'rules.dart';
export 'view.dart';
