/// Big Two played as a match: deals one after another, each deal's points
/// added to running totals, until one total reaches the target.
///
/// What counts follows the scoring the table chose:
/// - Penalty scoring (Pagat's standard): each loser's penalty is added to
///   their total, the winner adds nothing, and once someone reaches the
///   target the lowest total wins. Denexa's Big Two rules: "Gameplay
///   continues until one player reaches a predetermined score (such as 100
///   points), and whichever player has the lowest score at that point is
///   the winner" (https://www.denexa.com/blog/big-two). Pagat gives the
///   penalties but names no target, so 100 is the standard here.
/// - Pusoy Dos scoring: only the winner scores (1, doubled for each 2 in
///   their last play), and the highest total wins. Wikipedia's Pusoy dos:
///   "players may want to play until one player reaches a certain number
///   of wins, depending on player count"
///   (https://en.wikipedia.org/wiki/Pusoy_dos). It names no number; 10 is
///   the standard here: at four players it lasts about as many deals as a
///   penalty match to 100 (about 20, measured with
///   tool/games/big_two_match_length.dart).
///
/// "Scale with players" keeps a match about as long, in deals, as the
/// standard four-player one: the target is multiplied by
/// [bigTwoTargetScale], measured with bots for each table size.
library;

import 'dart:math';

import '../../../kit/match.dart';
import '../big_two.dart';

/// The points each seat adds to its match total for the deal that ended
/// with [result]: the penalties under penalty scoring (0 for the winner),
/// the winner's points under Pusoy Dos scoring (0 for the others).
List<int> bigTwoDealPoints(BigTwoRules rules, BigTwoResult result) => switch (rules.scoring) {
  BigTwoScoring.penalty => [...result.penalties],
  BigTwoScoring.pusoyDos => [for (final s in result.scores) max(0, s)],
};

/// Who wins a match under [scoring]: the lowest total of penalties, or the
/// highest total of points won.
MatchWinner bigTwoMatchWinner(BigTwoScoring scoring) => switch (scoring) {
  BigTwoScoring.penalty => MatchWinner.lowest,
  BigTwoScoring.pusoyDos => MatchWinner.highest,
};

/// The setup's target choices under [scoring], smallest first.
List<int> bigTwoTargetChoices(BigTwoScoring scoring) => switch (scoring) {
  BigTwoScoring.penalty => const [50, 100, 150, 200],
  BigTwoScoring.pusoyDos => const [5, 10, 15, 20],
};

/// The standard match under [scoring]: to 100 penalty points (Denexa), or
/// to 10 points won (see the library comment), not scaled.
MatchTarget bigTwoStandardTarget(BigTwoScoring scoring) => MatchTarget(
  points: switch (scoring) {
    BigTwoScoring.penalty => 100,
    BigTwoScoring.pusoyDos => 10,
  },
);

/// How much a target is multiplied at [rules]' table so a match lasts about
/// as many deals as at the standard table (four players, 13 cards each).
///
/// Measured with tool/games/big_two_match_length.dart (400 deals of Easy
/// bots and 150 of Medium bots per table, the factor the average of the
/// two): under penalty scoring fewer players pay less per deal (a two-player
/// deal of 13 cards has one loser, usually with few cards left), so their
/// target comes down; under Pusoy Dos scoring fewer players each win more
/// often, so their target goes up.
double bigTwoTargetScale(BigTwoRules rules) {
  final penalty = rules.scoring == BigTwoScoring.penalty;
  return switch ((rules.players, rules.cardsEach)) {
    (4, _) => 1.0,
    (3, _) => penalty ? 0.95 : 1.45,
    (_, 13) => penalty ? 0.45 : 1.65,
    (_, 17) => penalty ? 0.6 : 1.9,
    _ => penalty ? 0.8 : 2.0,
  };
}

/// The target a match at [rules]' table plays to, from the setup's
/// [choice]: null for No limit; the chosen points, or with "Scale with
/// players" the points times [bigTwoTargetScale], rounded to a multiple of
/// 5 for penalties (never under 5) and to a whole point for Pusoy Dos
/// (never under 1).
int? bigTwoMatchTarget(MatchTarget choice, BigTwoRules rules) {
  final points = choice.points;
  if (points == null) return null;
  if (!choice.scale) return points;
  final scaled = points * bigTwoTargetScale(rules);
  return switch (rules.scoring) {
    BigTwoScoring.penalty => max(5, (scaled / 5).round() * 5),
    BigTwoScoring.pusoyDos => max(1, scaled.round()),
  };
}

/// A new match at [rules]' table to the target [choice] gives, or null for
/// No limit.
MatchScore? bigTwoStartMatch(MatchTarget choice, BigTwoRules rules) {
  final target = bigTwoMatchTarget(choice, rules);
  if (target == null) return null;
  return MatchScore(target: target, winner: bigTwoMatchWinner(rules.scoring), seats: rules.players);
}
