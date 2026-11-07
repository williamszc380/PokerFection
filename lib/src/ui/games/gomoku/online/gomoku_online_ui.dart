/// Gomoku's online part on the app's side (registered in
/// online_game_uis.dart): the solo game's board, tags and buttons on the
/// room's game screen, its setup's rows as the host's rules, the bots the
/// host's device plays and a spectator's coach (the Best move list), all
/// from the room's view (see gomoku_view_codec.dart).
library;

import 'package:flutter/material.dart';

import '../../../../games/gomoku/app/gomoku_analysis.dart';
import '../../../../games/gomoku/app/gomoku_jobs.dart' show GomokuBotOutput;
import '../../../../games/gomoku/app/gomoku_online_jobs.dart';
import '../../../../games/gomoku/gomoku.dart';
import '../../../../games/gomoku/online/gomoku_runner.dart';
import '../../../../games/gomoku/online/gomoku_view_codec.dart';
import '../../../../kit/coach_answer.dart';
import '../../../../online/games/game_runner.dart';
import '../../../kit/help.dart';
import '../../../kit/l10n/game_strings.dart';
import '../../../kit/l10n/kit_strings.dart';
import '../../../kit/setup_kit.dart';
import '../../../online/online_game_ui.dart';
import '../../../online/runner_client.dart';
import '../l10n/gomoku_strings.dart';
import 'gomoku_online_strings.dart';
import 'gomoku_online_table.dart';

/// Gomoku's online part.
// ignore: unnecessary_nullable_for_final_variable_declarations
final OnlineGameUi? gomokuOnlineUi = GomokuOnlineUi();

/// Gomoku in a room, on this device.
class GomokuOnlineUi extends OnlineGameUi {
  GomokuOnlineUi([OnlineGame? online]) : online = online ?? gomokuOnline!;

  @override
  final OnlineGame online;

  @override
  GameStrings strings(BuildContext context) => GomokuStrings.of(context);

  /// Nothing is hidden: every seat's view is the spectators' with its seat.
  @override
  Map<String, Object?>? seatViewFrom(Map<String, Object?> spectatorView, int seat) =>
      gomokuSeatViewFrom(spectatorView, seat);

  @override
  OnlineJob<Object?, Object?> botJob(Map<String, Object?> seatView, String level, {required int seed}) => OnlineJob(
    const GomokuOnlineBotJob(),
    GomokuOnlineBotInput(view: seatView, level: KitLevel.values.byName(level), seed: seed),
  );

  @override
  String botMove(Object? output) => (output! as GomokuBotOutput).move;

  /// The Easy bot's move, quick enough to run here (it looks only a move
  /// or two ahead), when the bot's job failed.
  @override
  String fallbackMove(Map<String, Object?> seatView, {required int seed}) {
    final view = GomokuOnlineView.fromJson(seatView);
    final seat = view.you ?? view.seatToAct ?? 0;
    return GomokuBot(
      BotLevel.easy,
      maxTime: const Duration(milliseconds: 60),
    ).chooseMove(view.game.viewFor(view.colorOf(seat))).notation;
  }

  @override
  OnlineJob<Object?, Object?> coachJob(Map<String, Object?> seatView, {required int seed}) =>
      OnlineJob(const GomokuOnlineCoachJob(), GomokuOnlineCoachInput(view: seatView, seed: seed));

  /// The solo coach's answer; a forced pass (Renju) is always listed, as
  /// every game's Pass.
  @override
  CoachAnswer toAnswer(Object? output) {
    final answer = gomokuAnswer(output! as GomokuAnalysis);
    final pass = GomokuMove.pass.notation;
    return answer.rates(pass) ? answer.withListed({pass}) : answer;
  }

  @override
  Widget table(BuildContext context, RunnerClient c) => GomokuOnlineTable(runner: c);

  /// No hand: the stones are played on the board.
  @override
  Widget? bottom(BuildContext context, RunnerClient c) => null;

  @override
  Widget actions(BuildContext context, RunnerClient c) => GomokuOnlineActions(runner: c);

  /// The solo setup's Rule and Board rows (19×19 greyed out under Renju),
  /// and who plays Black.
  @override
  Widget rulesForm(
    BuildContext context,
    Map<String, Object?> rules, {
    required bool enabled,
    required ValueChanged<Map<String, Object?>> onChange,
  }) {
    final g = GomokuStrings.of(context);
    final o = GomokuOnlineStrings.of(context);
    GomokuOnlineRules current;
    try {
      current = GomokuOnlineRules.fromJson(rules);
    } on FormatException {
      current = const GomokuOnlineRules();
    }
    final game = current.rules;
    void change(GomokuOnlineRules next) {
      if (next != current) onChange(next.toJson());
    }

    return Column(
      key: const ValueKey('gomoku rules'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SetupSection(
          label: g.rule,
          help: TermsHelpButton(
            title: g.rule,
            terms: [
              for (final t in const [
                GomokuTerm.freestyle,
                GomokuTerm.standard,
                GomokuTerm.renju,
                GomokuTerm.overline,
                GomokuTerm.forbiddenMove,
              ])
                g.entry(t),
            ],
          ),
          child: ChoiceRow<WinRule>(
            key: const ValueKey('gomoku rule'),
            values: WinRule.values,
            selected: game.winRule,
            label: g.ruleName,
            enabled: (_) => enabled,
            // Renju is played on 15×15 only.
            onChanged: (rule) => change(
              current.copyWith(
                rules: GomokuRules(size: rule == WinRule.renju ? 15 : game.size, winRule: rule),
              ),
            ),
          ),
        ),
        SetupSection(
          label: g.board,
          child: ChoiceRow<int>(
            key: const ValueKey('gomoku board size'),
            values: const [15, 19],
            selected: game.size,
            label: g.boardSize,
            enabled: (size) => enabled && (size == 15 || game.winRule != WinRule.renju),
            onChanged: (size) => change(
              current.copyWith(
                rules: GomokuRules(size: size, winRule: game.winRule),
              ),
            ),
          ),
        ),
        SetupSection(
          label: o.black,
          help: TermsHelpButton(title: o.blackHelp.term, terms: [o.blackHelp, g.entry(GomokuTerm.firstMove)]),
          child: ChoiceRow<GomokuBlackRule>(
            key: const ValueKey('gomoku black'),
            values: GomokuBlackRule.values,
            selected: current.black,
            label: o.blackRule,
            enabled: (_) => enabled,
            onChanged: (black) => change(current.copyWith(black: black)),
          ),
        ),
      ],
    );
  }

  @override
  String moveLabel(BuildContext context, String move) => GomokuStrings.of(context).moveName(move);

  /// "You win" / "You lose" for a player, "Ann wins" for a spectator, or
  /// "Draw".
  @override
  String resultText(BuildContext context, RunnerClient c) {
    final k = KitStrings.of(context);
    final winner = c.over?.result['winner'];
    if (winner is! int) return k.draw;
    final you = c.you;
    if (you != null) return winner == you ? k.youWin : k.youLose;
    return k.wins(c.nameOf(winner));
  }
}
