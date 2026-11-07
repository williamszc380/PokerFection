// Big Two as a match: what each deal adds to the totals, who wins, the
// standard targets, and the target scaled for the table.
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_match.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/kit/match.dart';

BigTwoRules penalty({int players = 4, int? cards}) => BigTwoRules.standard(players: players, cardsEach: cards);
BigTwoRules pusoy({int players = 4, int? cards}) =>
    BigTwoRules.standard(players: players, cardsEach: cards).copyWith(scoring: BigTwoScoring.pusoyDos);

void main() {
  const result = BigTwoResult(
    winner: 2,
    cardsLeft: [5, 11, 0, 13],
    penalties: [5, 22, 0, 39],
    scores: [-5, -22, 66, -39],
  );

  test('under penalty scoring each loser adds their penalty and the winner nothing; the lowest total wins', () {
    expect(bigTwoDealPoints(penalty(), result), [5, 22, 0, 39]);
    expect(bigTwoMatchWinner(BigTwoScoring.penalty), MatchWinner.lowest);
  });

  test('under Pusoy Dos scoring only the winner adds their points; the highest total wins', () {
    const won = BigTwoResult(winner: 1, cardsLeft: [3, 0, 4, 2], penalties: [0, 0, 0, 0], scores: [0, 2, 0, 0]);
    expect(bigTwoDealPoints(pusoy(), won), [0, 2, 0, 0]);
    expect(bigTwoMatchWinner(BigTwoScoring.pusoyDos), MatchWinner.highest);
  });

  test('the standard match: to 100 penalty points (Denexa), to 10 points won under Pusoy Dos', () {
    expect(bigTwoStandardTarget(BigTwoScoring.penalty), const MatchTarget(points: 100));
    expect(bigTwoStandardTarget(BigTwoScoring.pusoyDos), const MatchTarget(points: 10));
    expect(bigTwoTargetChoices(BigTwoScoring.penalty), contains(100));
    expect(bigTwoTargetChoices(BigTwoScoring.pusoyDos), contains(10));
  });

  test('without scaling the target is the one chosen, at any table; No limit plays no match', () {
    for (final rules in [penalty(), penalty(players: 3), penalty(players: 2, cards: 13)]) {
      expect(bigTwoMatchTarget(const MatchTarget(points: 150), rules), 150);
      expect(bigTwoMatchTarget(const MatchTarget(), rules), isNull);
      expect(bigTwoStartMatch(const MatchTarget(scale: true), rules), isNull);
    }
  });

  test('scaled, four players keep the target; fewer pay less per deal, so theirs comes down', () {
    const scaled = MatchTarget(points: 100, scale: true);
    expect(bigTwoMatchTarget(scaled, penalty()), 100);
    expect(bigTwoMatchTarget(scaled, penalty(players: 3)), 95);
    expect(bigTwoMatchTarget(scaled, penalty(players: 2, cards: 13)), 45);
    expect(bigTwoMatchTarget(scaled, penalty(players: 2, cards: 17)), 60);
    expect(bigTwoMatchTarget(scaled, penalty(players: 2, cards: 21)), 80);
    expect(bigTwoMatchTarget(const MatchTarget(points: 50, scale: true), penalty(players: 2, cards: 13)), 25);
  });

  test('scaled under Pusoy Dos, fewer players each win more often, so their target goes up', () {
    const scaled = MatchTarget(points: 10, scale: true);
    expect(bigTwoMatchTarget(scaled, pusoy()), 10);
    expect(bigTwoMatchTarget(scaled, pusoy(players: 3)), 15);
    expect(bigTwoMatchTarget(scaled, pusoy(players: 2, cards: 13)), 17);
    expect(bigTwoMatchTarget(scaled, pusoy(players: 2, cards: 21)), 20);
  });

  test('a new match counts every seat from 0 to the table\'s target', () {
    final match = bigTwoStartMatch(const MatchTarget(points: 100, scale: true), penalty(players: 2, cards: 13))!;
    expect(match.target, 45);
    expect(match.seats, 2);
    expect(match.winner, MatchWinner.lowest);
    expect(match.totals, [0, 0]);
    expect(match.add([0, 50]).isOver, isTrue);
  });
}
