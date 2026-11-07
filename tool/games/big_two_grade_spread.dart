// How steady Big Two's grades are: over the coach job's 30 check
// positions, each coached from four seeds, how many moves change grade by
// two steps or more between seeds, how often the pick changes, and how the
// grades spread. Used to set bigTwoStepErrors (big_two_grading.dart).
// It counts grades, not time, so it may run at any point.
//
//   dart run tool/games/big_two_grade_spread.dart          (desktop budget)
//   dart run tool/games/big_two_grade_spread.dart phone    (phone budget)

// ignore_for_file: avoid_print
import 'package:pokerfection/src/games/big_two/app/big_two_grading.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_jobs.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_record.dart';
import 'package:pokerfection/src/kit/jobs/jobs_core.dart';

void main(List<String> args) {
  const coach = BigTwoCoachJob();
  final spots = coach.checkInputs();
  final platform = args.isNotEmpty && args.first == 'phone' ? JobPlatform.phone : JobPlatform.desktop;
  var moves = 0, swings = 0, pickChanges = 0;
  final tally = <String, int>{};
  for (final (p, spot) in spots.indexed) {
    final scale = bigTwoScale(BigTwoRecord.replayJson(spot.record).rules);
    final grades = <String, List<int>>{};
    final picks = <String>{};
    for (final seed in [7919, 15838, 23757, 31676]) {
      final input = BigTwoCoachInput(record: spot.record, seat: spot.seat, seed: seed);
      final report = coach.run(input, JobContext(platform: platform));
      final answer = bigTwoAnswer(report, scale);
      picks.add(report.pick.move);
      for (final m in report.moves) {
        final g = scale.mark(answer, m.move)!.grade;
        grades.putIfAbsent(m.move, () => []).add(g.index);
        tally[g.name] = (tally[g.name] ?? 0) + 1;
      }
    }
    if (picks.length > 1) pickChanges++;
    for (final MapEntry(key: m, value: g) in grades.entries) {
      moves++;
      final lo = g.reduce((a, b) => a < b ? a : b), hi = g.reduce((a, b) => a > b ? a : b);
      if (hi - lo > 1) {
        swings++;
        print('spot $p $m $g');
      }
    }
  }
  print('moves $moves, swings of 2+ steps $swings, positions whose pick changed $pickChanges/${spots.length}');
  print('grades: $tally');
}
