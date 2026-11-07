// How long a Big Two match lasts at each table size: plays seeded deals
// between bots for every player count and deal size the setup offers, then
// replays matches on those deals (each match a run of consecutive deals)
// and prints the average number of deals until a total reaches the target.
// Penalty scoring adds each loser's penalty (lowest total wins); Pusoy Dos
// scoring adds the winner's points (highest total wins).
//
// It is how bigTwoTargetScale in lib/src/games/big_two/app/big_two_match.dart
// was chosen: the factor that makes a match at each table last about as
// many deals as the standard four-player match to the same target.
//
//   dart run tool/games/big_two_match_length.dart --deals 400 --level easy
//
// ignore_for_file: avoid_print
import 'package:pokerfection/src/games/big_two/app/big_two_match.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/kit/match.dart';

void main(List<String> args) {
  String opt(String name, String fallback) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
  }

  final deals = int.parse(opt('deals', '400'));
  final level = BotLevel.values.byName(opt('level', 'easy'));
  for (final scoring in BigTwoScoring.values) {
    final target = bigTwoStandardTarget(scoring).points!;
    print('${scoring.name}, target $target (scaled: the target bigTwoTargetScale gives):');
    for (final (players, cards) in const [(4, 13), (3, 17), (2, 13), (2, 17), (2, 21)]) {
      final rules = BigTwoRules.standard(players: players, cardsEach: cards).copyWith(scoring: scoring);
      final points = [for (var d = 0; d < deals; d++) _deal(rules, 7000 + d, level)];
      final scaled = bigTwoMatchTarget(MatchTarget(points: target, scale: true), rules)!;
      final perSeat = points.expand((p) => p).fold(0, (a, b) => a + b) / (deals * players);
      print(
        '  ${players}p x$cards: ${perSeat.toStringAsFixed(2)} pts/seat/deal; '
        'to $target: ${_length(points, target).toStringAsFixed(1)} deals; '
        'to $scaled (x${bigTwoTargetScale(rules).toStringAsFixed(2)}): ${_length(points, scaled).toStringAsFixed(1)} deals',
      );
    }
  }
}

/// One seeded deal between [level] bots: the points each seat adds to its
/// match total (see bigTwoDealPoints).
List<int> _deal(BigTwoRules rules, int seed, BotLevel level) {
  final state = BigTwoState.deal(rules, seed: seed);
  final bots = [for (var s = 0; s < rules.players; s++) BigTwoBot(level, seed: seed * 7 + s)];
  while (!state.isOver) {
    state.apply(bots[state.toMove].chooseMove(state.viewFor(state.toMove)));
  }
  return bigTwoDealPoints(rules, state.result);
}

/// The average number of deals a match to [target] lasts, starting at every
/// deal of [points] in turn (wrapping round).
double _length(List<List<int>> points, int target) {
  var sum = 0;
  for (var start = 0; start < points.length; start++) {
    final totals = List<int>.filled(points.first.length, 0);
    var n = 0;
    while (totals.every((t) => t < target)) {
      final deal = points[(start + n) % points.length];
      for (var s = 0; s < totals.length; s++) {
        totals[s] += deal[s];
      }
      n++;
    }
    sum += n;
  }
  return sum / points.length;
}
