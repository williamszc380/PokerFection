/// Nim's jobs (see nim.dart), apart from its controller: pure Dart, so
/// tool/games/game_worker_check.dart can build them into a web worker too
/// and prove the whole path (native, JavaScript, WebAssembly) with a game
/// that is always there.
library;

import 'package:pokerfection/src/kit/jobs/jobs_core.dart';

typedef Json = Map<String, Object?>;

/// Stones left in a Nim record.
int nimLeft(Json record) =>
    ((record['rules']! as Json)['pile']! as int) -
    [for (final m in record['moves']! as List) int.parse(m as String)].fold(0, (a, b) => a + b);

/// The coach: every take, best first; input {record, seat, top?, include?, deep?, fail?}.
class NimCoachJob extends GameJob<Json, List<Object?>> {
  const NimCoachJob();

  @override
  String get name => 'nim.coach';

  @override
  Object? encodeInput(Json input) => input;
  @override
  Json decodeInput(Object? json) => json! as Json;
  @override
  Object? encodeOutput(List<Object?> output) => output;
  @override
  List<Object?> decodeOutput(Object? json) => json! as List<Object?>;

  @override
  List<Object?> run(Json input, JobContext context) {
    if (input['fail'] == true) throw StateError('the coach broke');
    final record = input['record']! as Json;
    final take = (record['rules']! as Json)['take']! as int;
    final left = nimLeft(record);
    double value(int k) => left - k == 0 ? 1.0 : 0.9 - 0.06 * ((left - k) % (take + 1));
    final moves = [for (var k = 1; k <= take && k <= left; k++) k]..sort((a, b) => value(b).compareTo(value(a)));
    final top = input['top'] as int? ?? moves.length;
    final include = input['include'] as String?;
    final rated = [
      for (final (i, k) in moves.indexed)
        if (i < top || '$k' == include) k,
    ];
    return [
      for (final k in rated)
        {
          'move': '$k',
          'value': value(k),
          'reasons': [if (input['deep'] == true) 'deep', if (left - k == 0) 'last'],
        },
    ];
  }

  @override
  List<Json> examples() => [
        {
          'record': {'rules': {'pile': 7, 'take': 3}, 'moves': <String>[]},
          'seat': 0,
        },
      ];

  /// Piles of 1 to 12 with takes of 2 to 4, some with a move made: the
  /// cross-platform check (its values are fractions, as real coaches' are).
  @override
  List<Json> checkInputs() => [
        for (final record in _nimPositions()) {'record': record, 'seat': 0, 'deep': nimLeft(record).isEven},
      ];
}

List<Json> _nimPositions() => [
      for (var pile = 1; pile <= 12; pile++)
        for (final take in [2, 3, 4])
          {
            'rules': {'pile': pile, 'take': take},
            'moves': pile > 4 ? ['1'] : <String>[],
          },
    ];

/// The bot: the winning take when there is one, else 1; input {record, seat, fail?}.
class NimBotJob extends GameJob<Json, String> {
  const NimBotJob();

  @override
  String get name => 'nim.bot';

  @override
  Object? encodeInput(Json input) => input;
  @override
  Json decodeInput(Object? json) => json! as Json;
  @override
  Object? encodeOutput(String output) => output;
  @override
  String decodeOutput(Object? json) => json! as String;

  @override
  String run(Json input, JobContext context) {
    if (input['fail'] == true) throw StateError('the bot broke');
    final record = input['record']! as Json;
    final take = (record['rules']! as Json)['take']! as int;
    final win = nimLeft(record) % (take + 1);
    return '${win == 0 ? 1 : win}';
  }

  @override
  List<Json> checkInputs() => [
        for (final record in _nimPositions()) {'record': record, 'seat': 1},
      ];
}

/// Nim's jobs, to give Jobs.inline(extra:) or a ManualBackend.
final Map<String, GameJob<Object?, Object?>> nimJobs = {
  for (final job in <GameJob<Object?, Object?>>[const NimCoachJob(), const NimBotJob()]) job.name: job,
};

