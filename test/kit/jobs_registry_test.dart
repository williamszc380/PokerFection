import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/kit/game_keys.dart';
import 'package:pokerfection/src/kit/jobs/job_registry.dart';
import 'package:pokerfection/src/kit/jobs/jobs_core.dart';

void main() {
  test("every registered job is named '<game key>.<what>', once", () {
    for (final MapEntry(key: name, value: job) in kitJobs.entries) {
      expect(job.name, name);
      final key = name.split('.').first;
      expect(GameKeys.all, contains(key), reason: '$name starts with a game key and a dot');
      expect(name.length, greaterThan(key.length + 1), reason: name);
    }
  });

  test('two jobs with the same name stop the registry instead of one silently replacing the other', () {
    final named = jobsByName([const _Named('gomoku.coach'), const _Named('gomoku.bot')]);
    expect(named.keys, ['gomoku.coach', 'gomoku.bot']);
    expect(
      () => jobsByName([const _Named('big_two.coach'), const _Named('big_two.coach')]),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('big_two.coach'))),
    );
  });

  test('the game keys are the folders and job prefixes the design names', () {
    expect(GameKeys.all, ['gomoku', 'big_two', 'doudizhu', 'blackjack']);
  });

  test('every example runs through the request and reply with no cap, and twice gives the same output', () {
    for (final job in kitJobs.values) {
      for (final (i, input) in job.examples().indexed) {
        Object? run() {
          final reply = jsonDecode(runJobRequest(encodeRequest(i, job, input, platform: JobPlatform.desktop), kitJobs))
              as Map<String, Object?>;
          expect(reply['err'], isNull, reason: '${job.name} example $i');
          return job.normalize(reply['out']);
        }

        final first = run();
        expect(run(), first, reason: '${job.name} example $i repeats exactly');
        expect(() => job.decodeOutput(first), returnsNormally, reason: '${job.name} example $i decodes');
      }
    }
  });
}

/// A job that is only a name.
class _Named extends GameJob<Object?, Object?> {
  const _Named(this.name);

  @override
  final String name;
  @override
  Object? encodeInput(Object? input) => input;
  @override
  Object? decodeInput(Object? json) => json;
  @override
  Object? encodeOutput(Object? output) => output;
  @override
  Object? decodeOutput(Object? json) => json;
  @override
  Object? run(Object? input, JobContext context) => input;
}
