// Problems found in review, written as the specification they break:
// a grade must say something about the move, not about the coach's seed.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_analysis.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_grading.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_jobs.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_record.dart';
import 'package:pokerfection/src/kit/jobs/job_registry.dart';
import 'package:pokerfection/src/kit/jobs/jobs_core.dart';

void main() {
  test('at the full desktop budget, coaching the same position with another seed moves no grade by more than one step', () {
    const coach = BigTwoCoachJob();
    final spots = coach.checkInputs();
    final unstable = <String>[];
    // Two of the cross-platform check's positions (Taiwan rules, 4 and 3 players).
    for (final spot in [spots[6], spots[10]]) {
      final scale = bigTwoScale(BigTwoRecord.replayJson(spot.record).rules);
      final grades = <String, List<String>>{};
      for (final seed in [7919, 15838, 23757, 31676]) {
        final input = BigTwoCoachInput(record: spot.record, seat: spot.seat, seed: seed);
        final reply = jsonDecode(
          runJobRequest(encodeRequest(1, coach, input, platform: JobPlatform.desktop), kitJobs),
        ) as Map<String, Object?>;
        final answer = bigTwoAnswer(BigTwoReport.fromJson(reply['out']), scale);
        for (final line in answer.lines) {
          grades.putIfAbsent(line.move, () => []).add(scale.mark(answer, line.move)!.grade.name);
        }
      }
      for (final MapEntry(key: move, value: seen) in grades.entries) {
        final steps = seen.map((g) => ['best', 'good', 'inaccuracy', 'mistake', 'blunder'].indexOf(g));
        if (steps.reduce((a, b) => a > b ? a : b) - steps.reduce((a, b) => a < b ? a : b) > 1) {
          unstable.add('$move: $seen');
        }
      }
    }
    expect(unstable, isEmpty, reason: 'the same move, graded from four seeds of the same coach');
  });
}
