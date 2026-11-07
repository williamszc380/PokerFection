/// High card's online part on the app's side (see test/server/fake_runner.dart),
/// drawn with plain widgets: what a game agent's `<key>_online_ui.dart`
/// provides, for the room service's and the game screen's tests.
library;

import 'package:flutter/material.dart';
import 'package:pokerfection/src/kit/coach_answer.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/kit/jobs/jobs_core.dart';
import 'package:pokerfection/src/online/games/game_runner.dart';
import 'package:pokerfection/src/ui/kit/l10n/game_strings.dart';
import 'package:pokerfection/src/ui/online/online_game_ui.dart';
import 'package:pokerfection/src/ui/online/runner_client.dart';

import '../server/fake_runner.dart';

/// The bot: raises with a ten or better (its level is ignored).
class HighCardBotJob extends GameJob<Map<String, Object?>, String> {
  const HighCardBotJob();

  /// Every move it was asked for, with its seed.
  static final List<(Map<String, Object?>, int)> asked = [];

  @override
  String get name => 'highcard.onlineBot';
  @override
  Object? encodeInput(Map<String, Object?> input) => input;
  @override
  Map<String, Object?> decodeInput(Object? json) => (json! as Map).cast<String, Object?>();
  @override
  Object? encodeOutput(String output) => {'mv': output};
  @override
  String decodeOutput(Object? json) => (json! as Map)['mv']! as String;

  @override
  String run(Map<String, Object?> input, JobContext context) {
    final view = (input['view']! as Map).cast<String, Object?>();
    asked.add((view, input['seed']! as int));
    final seat = view['you']! as int;
    return '$seat:${highCardRank(view['card']! as String) >= 8 ? 'raise' : 'fold'}';
  }
}

/// The coach: raising is worth the card's rank, folding nothing.
class HighCardCoachJob extends GameJob<Map<String, Object?>, Map<String, Object?>> {
  const HighCardCoachJob();

  static int runs = 0;

  @override
  String get name => 'highcard.onlineCoach';
  @override
  Object? encodeInput(Map<String, Object?> input) => input;
  @override
  Map<String, Object?> decodeInput(Object? json) => (json! as Map).cast<String, Object?>();
  @override
  Object? encodeOutput(Map<String, Object?> output) => output;
  @override
  Map<String, Object?> decodeOutput(Object? json) => (json! as Map).cast<String, Object?>();

  @override
  Map<String, Object?> run(Map<String, Object?> input, JobContext context) {
    runs++;
    final view = (input['view']! as Map).cast<String, Object?>();
    final seat = view['you']! as int, rank = highCardRank(view['card']! as String);
    final raise = (rank - 6) / 6;
    return {
      'lines': [
        {'mv': '$seat:raise', 'v': raise},
        {'mv': '$seat:fold', 'v': 0.0},
      ]..sort((a, b) => (b['v']! as double).compareTo(a['v']! as double)),
    };
  }
}

/// The two jobs, for Jobs.inline(extra: …).
final highCardJobs = <String, GameJob<Object?, Object?>>{
  'highcard.onlineBot': const HighCardBotJob(),
  'highcard.onlineCoach': const HighCardCoachJob(),
};

/// New jobs on the same thread, with High card's.
Jobs highCardInlineJobs() => Jobs.inline(extra: highCardJobs);

class _HighCardStrings implements GameStrings {
  const _HighCardStrings();
  @override
  String get pickLabel => 'Best move';
  @override
  String? tagLabel(String tag) => null;
  @override
  List<GameTerm> get glossary => const [GameTerm('High card', 'The highest card wins.')];
  @override
  List<(String, String)> get rulesSections => const [
    ('High card', 'Raise or fold once; the highest card raised wins.'),
  ];
  @override
  List<String> samples() => const ['Best move'];
}

/// High card's online part.
class HighCardUi extends OnlineGameUi {
  HighCardUi([HighCardGame? game]) : online = game ?? HighCardGame();

  @override
  final OnlineGame online;

  @override
  GameStrings strings(BuildContext context) => const _HighCardStrings();

  @override
  Map<String, Object?>? seatViewFrom(Map<String, Object?> spectatorView, int seat) =>
      highCardSeatViewFrom(spectatorView, seat);

  @override
  OnlineJob<Object?, Object?> botJob(Map<String, Object?> seatView, String level, {required int seed}) =>
      OnlineJob(const HighCardBotJob(), {'view': seatView, 'level': level, 'seed': seed});

  @override
  String botMove(Object? output) => output! as String;

  @override
  String fallbackMove(Map<String, Object?> seatView, {required int seed}) => '${seatView['you']}:fold';

  @override
  OnlineJob<Object?, Object?> coachJob(Map<String, Object?> seatView, {required int seed}) =>
      OnlineJob(const HighCardCoachJob(), {'view': seatView, 'seed': seed});

  @override
  CoachAnswer toAnswer(Object? output) {
    final lines = ((output! as Map)['lines']! as List).cast<Map<Object?, Object?>>();
    return CoachAnswer(
      unit: ValueUnit.points,
      lines: [for (final l in lines) CoachLine(move: l['mv']! as String, value: (l['v']! as num).toDouble())],
    );
  }

  /// Every seat in a row: name, card (face down when this view hasn't it)
  /// and whose turn.
  @override
  Widget table(BuildContext context, RunnerClient c) {
    final view = c.view ?? const {};
    final hands = view['hands'] is Map ? view['hands']! as Map : const {};
    final shown = view['shown'] is Map ? view['shown']! as Map : const {};
    final n = view['n'] is int ? view['n']! as int : 0;
    String? cardOf(int s) =>
        shown['$s'] as String? ?? hands['$s'] as String? ?? (s == c.you ? view['card'] as String? : null);
    return Center(
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (var s = 0; s < n; s++)
            Container(
              key: ValueKey('hc seat $s'),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: c.turn?.seat == s ? Colors.amber : Colors.white24),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(c.nameOf(s)),
                  Text(cardOf(s) ?? '??', key: ValueKey('hc card $s')),
                  if (c.seatInfo(s)?.score case final score?) Text('$score'),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget? bottom(BuildContext context, RunnerClient c) =>
      Center(child: Text('${c.view?['card'] ?? ''}', key: const ValueKey('hc my card')));

  @override
  Widget actions(BuildContext context, RunnerClient c) {
    final you = c.you;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton(
          key: const ValueKey('hc raise'),
          onPressed: c.myTurn ? () => c.move('$you:raise') : null,
          child: const Text('Raise'),
        ),
        OutlinedButton(
          key: const ValueKey('hc fold'),
          onPressed: c.myTurn ? () => c.move('$you:fold') : null,
          child: const Text('Fold'),
        ),
      ],
    );
  }

  @override
  Widget rulesForm(
    BuildContext context,
    Map<String, Object?> rules, {
    required bool enabled,
    required ValueChanged<Map<String, Object?>> onChange,
  }) => SwitchListTile(
    key: const ValueKey('hc pad'),
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: const Text('Padding'),
    value: rules['pad'] != null,
    onChanged: enabled ? (on) => onChange(on ? {'pad': 10} : {}) : null,
  );

  @override
  String moveLabel(BuildContext context, String move) => move.endsWith('raise') ? 'Raise' : 'Fold';

  @override
  String resultText(BuildContext context, RunnerClient c) {
    final winner = c.over?.result['winner'];
    return winner is int ? '${c.nameOf(winner)} wins' : 'Nobody raised';
  }
}
