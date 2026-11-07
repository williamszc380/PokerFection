// ignore_for_file: avoid_print

// How long a Fight the Landlord match lasts at each target: bots play deal
// after deal, each deal's points (the bid times the doublings, the landlord
// winning or losing double) go to the running totals, and a match ends when
// a total reaches the target. It prints the points a deal moves and, per
// target, how many deals a match takes (thrown-in deals count: they are
// dealt again and score nothing). The setup's targets come from this.
//
//   dart run tool/games/doudizhu_match_length.dart              (Easy bots, 400 matches)
//   dart run tool/games/doudizhu_match_length.dart --medium 40  (Medium bots, 40 matches)
import 'dart:math';

import 'package:pokerfection/src/games/doudizhu/app/doudizhu_record.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/kit/game_record.dart';

void main(List<String> args) {
  final medium = args.contains('--medium');
  final numbers = [for (final a in args) ?int.tryParse(a)];
  final matches = numbers.firstOrNull ?? (medium ? 40 : 400);
  final level = medium ? DdzLevel.medium : DdzLevel.easy;
  const targets = [20, 25, 30, 40, 50, 100];
  final random = Random(1);

  // One long run of deals; each target's matches are cut from it. Enough
  // deals for [matches] matches at the largest target.
  final deals = <List<int>>[];
  var thrownIn = 0, dealSeed = 1, done = 0;
  var totals = [0, 0, 0];
  final clock = Stopwatch()..start();
  while (done < matches) {
    final points = _playDeal(dealSeed++, level, random);
    if (points == null) thrownIn++;
    final d = points ?? const [0, 0, 0];
    deals.add(d);
    totals = [for (var s = 0; s < 3; s++) totals[s] + d[s]];
    if (totals.any((t) => t >= targets.last)) {
      done++;
      totals = [0, 0, 0];
    }
    if (deals.length % 20000 == 0) print('  ${deals.length} deals, $done matches, ${clock.elapsed.inSeconds} s');
  }

  final played = deals.where((d) => d.any((p) => p != 0)).toList();
  final lord = [for (final d in played) d.map((p) => p.abs()).reduce(max)];
  lord.sort();
  print('${level.name} bots: ${deals.length} deals, $thrownIn thrown in');
  print('landlord swing per deal: mean ${_mean(lord).toStringAsFixed(1)}, '
      'median ${lord[lord.length ~/ 2]}, 90th ${lord[(lord.length * 0.9).floor()]}, max ${lord.last}');
  for (final target in targets) {
    final lengths = _matchLengths(deals, target).take(matches).toList()..sort();
    print('to $target: ${lengths.length} matches, deals mean ${_mean(lengths).toStringAsFixed(1)}, '
        'median ${lengths[lengths.length ~/ 2]}, 10th ${lengths[(lengths.length * 0.1).floor()]}, '
        '90th ${lengths[(lengths.length * 0.9).floor()]}');
  }
}

/// The deals each match takes, matches played back to back over [deals].
List<int> _matchLengths(List<List<int>> deals, int target) {
  final out = <int>[];
  var totals = [0, 0, 0], n = 0;
  for (final d in deals) {
    n++;
    totals = [for (var s = 0; s < 3; s++) totals[s] + d[s]];
    if (totals.any((t) => t >= target)) {
      out.add(n);
      totals = [0, 0, 0];
      n = 0;
    }
  }
  return out;
}

double _mean(List<int> xs) => xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;

/// One deal played by three bots: each seat's points, or null when it was
/// thrown in.
List<int>? _playDeal(int seed, DdzLevel level, Random random) {
  final record = ddzNewRecord(
    seed: seed,
    rules: DdzRules.standard,
    seats: const [
      SeatSpec(human: false, name: 'A'),
      SeatSpec(human: false, name: 'B'),
      SeatSpec(human: false, name: 'C'),
    ],
    // The face-up card decides who bids first, as in the app.
  );
  final game = ddzReplay(record);
  final bot = DdzBot(level, random: random, budget: level == DdzLevel.easy ? null : DdzBudget.medium);
  while (game.phase == DdzPhase.bidding || game.phase == DdzPhase.playing) {
    ddzApply(game, ddzMoveTextFor(game, bot.chooseMove(game.viewFor(game.toAct))));
  }
  return game.result?.points;
}
