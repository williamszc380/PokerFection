/// Blackjack's online part on the app's side (registered in
/// online_game_uis.dart): the room's felt, the seated player's buttons, the
/// host's rules, the bots the host's device plays and a spectator's coach.
/// It reuses the solo game's pieces, so the game looks and plays the same
/// at a room's table: the felt's cards and pills, the cards flying in from
/// the shoe, the decision buttons (greyed out when not allowed, the offer
/// above them), the setup's rule rows, and the coach's answers.
library;

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';

import '../../../../games/blackjack/app/blackjack_grading.dart';
import '../../../../games/blackjack/app/blackjack_online_jobs.dart';
import '../../../../games/blackjack/app/blackjack_record.dart';
import '../../../../games/blackjack/blackjack.dart';
import '../../../../games/blackjack/online/blackjack_runner.dart';
import '../../../../games/blackjack/online/blackjack_view_codec.dart';
import '../../../../kit/coach_answer.dart';
import '../../../../online/games/game_runner.dart';
import '../../../kit/l10n/game_strings.dart';
import '../../../online/online_game_ui.dart';
import '../../../online/runner_client.dart';
import '../blackjack_screen.dart' show BlackjackActionButton;
import '../blackjack_setup.dart' show blackjackRuleRows;
import '../blackjack_table.dart' show betsText;
import '../l10n/blackjack_strings.dart';
import 'blackjack_online_table.dart';

/// Blackjack's online part (null until a game has one, as the registry
/// expects of every game's).
// ignore: unnecessary_nullable_for_final_variable_declarations
final OnlineGameUi? blackjackOnlineUi = BlackjackOnlineUi();

/// Blackjack at a room's table, on this device.
///
/// The basic strategy chart (about a second to build) is built once per
/// rules on this device, by the first job that needs it (a Hard bot, the
/// coach), which hands it back; it is kept here and goes with every job
/// after, since each job starts in a fresh worker (see
/// blackjack_online_jobs.dart).
class BlackjackOnlineUi extends OnlineGameUi {
  BlackjackOnlineUi();

  @override
  OnlineGame get online => const BlackjackOnline();

  /// The charts built on this device, by rules (BlackjackRules.strategyKey).
  final Map<String, BasicStrategyChart> _charts = {};

  /// Each game's felt playback, shared by its table and its buttons.
  final Expando<BlackjackFeltPlayback> _playbacks = Expando();

  /// The latest coach answer offered even money (its insurance row says so).
  bool _evenMoney = false;

  BlackjackFeltPlayback _playback(RunnerClient c) => _playbacks[c] ??= BlackjackFeltPlayback();

  BasicStrategyChart? _chartFor(Map<String, Object?> view) {
    try {
      return _charts[BlackjackRules.fromJson(view['rules']).strategyKey];
    } on Object {
      return null;
    }
  }

  void _keep(BasicStrategyChart? chart) {
    if (chart != null) _charts[chart.rules.strategyKey] = chart;
  }

  @override
  GameStrings strings(BuildContext context) => BlackjackStrings.of(context);

  @override
  Map<String, Object?>? seatViewFrom(Map<String, Object?> spectatorView, int seat) =>
      blackjackSeatViewFrom(spectatorView, seat);

  @override
  OnlineJob<Object?, Object?> botJob(Map<String, Object?> seatView, String level, {required int seed}) => OnlineJob(
    const BlackjackOnlineBotJob(),
    BlackjackOnlineInput(
      view: seatView,
      level: BotLevel.values.asNameMap()[level] ?? BotLevel.medium,
      chart: _chartFor(seatView),
    ),
  );

  @override
  String botMove(Object? output) {
    final out = output! as BlackjackOnlineBotOutput;
    _keep(out.chart);
    return out.move;
  }

  /// The Easy bot's rule, inline; Stand (or turning an offer down) if even
  /// that can't be worked out.
  @override
  String fallbackMove(Map<String, Object?> seatView, {required int seed}) {
    try {
      final view = blackjackViewFromWire(seatView);
      return handMove(view.turn!.hand, BlackjackBot(BotLevel.easy).chooseAction(view));
    } on Object {
      final legal = wireLegalMoves(seatView);
      for (final letter in const ['S', 'N', 'K']) {
        final move = legal.where((m) => m.endsWith(':$letter')).firstOrNull;
        if (move != null) return move;
      }
      return legal.firstOrNull ?? '0:S';
    }
  }

  @override
  OnlineJob<Object?, Object?> coachJob(Map<String, Object?> seatView, {required int seed}) =>
      OnlineJob(const BlackjackOnlineCoachJob(), BlackjackOnlineInput(view: seatView, chart: _chartFor(seatView)));

  /// As the solo game's coach list shows it, with a fresh shoe (basic
  /// strategy's view of the cards): every legal decision, the best first.
  @override
  CoachAnswer toAnswer(Object? output) {
    final out = output! as BlackjackOnlineCoachOutput;
    _keep(out.chart);
    _evenMoney = out.coach.evenMoney;
    return blackjackAnswer(out.coach, CoachMode.fresh);
  }

  @override
  Widget table(BuildContext context, RunnerClient c) => BlackjackOnlineTable(client: c, playback: _playback(c));

  /// None: the seated player's cards are on the felt, their seat given a
  /// little more room than the others.
  @override
  Widget? bottom(BuildContext context, RunnerClient c) => null;

  @override
  Widget actions(BuildContext context, RunnerClient c) => BlackjackOnlineActions(client: c, playback: _playback(c));

  @override
  Widget rulesForm(
    BuildContext context,
    Map<String, Object?> rules, {
    required bool enabled,
    required ValueChanged<Map<String, Object?>> onChange,
  }) {
    final BlackjackRules table;
    try {
      table = BlackjackRules.fromJson(rules);
    } on FormatException {
      return const SizedBox.shrink();
    }
    final rows = blackjackRuleRows(context, table, enabled: enabled, onChanged: (r) => onChange(r.toJson()));
    return Column(
      key: const ValueKey('blackjack rules'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [...rows.left, ...rows.right],
    );
  }

  @override
  String moveLabel(BuildContext context, String move) {
    final b = BlackjackStrings.of(context);
    final parsed = parseHandMove(move);
    if (parsed == null) return move;
    if (parsed.action == BlackjackAction.insurance && _evenMoney) return b.evenMoney;
    return b.action(parsed.action);
  }

  /// "Dealer…" while the felt still plays the dealer's cards out: the
  /// result waits for the felt, as the felt's own result does.
  @override
  String? heldResultText(BuildContext context, RunnerClient c) =>
      _playback(c).busy ? '${BlackjackStrings.of(context).dealer}…' : null;

  @override
  Listenable tablePlayback(BuildContext context, RunnerClient c) => _playback(c);

  /// A seated player's own round as in the solo game ("Win +1", "Win ·
  /// Bust"); a spectator's, the dealer's total and every seat's result
  /// ("Dealer · 20 · Ann +1 · Ben −1").
  @override
  String resultText(BuildContext context, RunnerClient c) {
    final b = BlackjackStrings.of(context);
    final felt = FeltView.of(c.view ?? const {});
    final you = c.you;
    if (you != null && you < felt.seats.length && you < felt.nets.length) {
      final outcomes = [
        for (final hand in felt.seats[you])
          if (hand.outcome case final outcome?) b.outcome(outcome),
      ];
      final net = felt.nets[you].toDouble();
      return [outcomes.join(' · '), if (net != 0) betsText(net)].join(' ');
    }
    final dealer = felt.dealer.map(Card.parse).toList();
    final dealerText = dealer.length == 2 && handTotal(dealer).value == 21
        ? b.blackjackHand
        : b.total(handTotal(dealer));
    return [
      '${b.dealer} · $dealerText',
      for (var s = 0; s < felt.nets.length; s++) '${c.nameOf(s)} ${betsText(felt.nets[s].toDouble())}',
    ].join(' · ');
  }
}

/// The seated player's buttons, as in the solo game: the round's offer
/// (Insurance / No insurance, Surrender / Keep playing) above the five
/// decisions while it stands, Hit and Stand filled, Double, Split and
/// Surrender outlined. Greyed out unless it is this player's turn and the
/// decision is allowed, and while the cards are dealt or the dealer plays.
/// Keys: H S D P R, I N for insurance, K to keep playing.
class BlackjackOnlineActions extends StatelessWidget {
  const BlackjackOnlineActions({super.key, required this.client, required this.playback});

  final RunnerClient client;
  final BlackjackFeltPlayback playback;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) {
        final b = BlackjackStrings.of(context);
        final c = client;
        final view = c.view ?? const <String, Object?>{};
        final turn = wireTurn(view);
        final mine = c.myTurn && turn != null && turn.seat == c.you && !playback.busy;
        final legal = mine ? wireLegalMoves(view).toSet() : const <String>{};
        final hand = turn?.hand ?? 0;
        final phase = view['phase'];
        final playing = phase == RoundPhase.playing.name;
        void play(BlackjackAction action) {
          final move = handMove(hand, action);
          if (legal.contains(move)) c.move(move);
        }

        Widget button(BlackjackAction action, {bool strong = false, String? label, bool offer = false}) {
          final move = handMove(hand, action);
          final allowed = (offer || playing) && legal.contains(move);
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: BlackjackActionButton(
                key: ValueKey('${offer ? 'offer' : 'action'} ${action.name}'),
                label: label ?? b.action(action),
                strong: strong,
                onPressed: allowed ? () => c.move(move) : null,
              ),
            ),
          );
        }

        final evenMoney = phase == RoundPhase.insurance.name && _evenMoney(view, c.you);
        final offer = switch (phase) {
          'insurance' => [
            button(BlackjackAction.insurance, label: evenMoney ? b.evenMoney : null, offer: true),
            button(BlackjackAction.noInsurance, offer: true),
          ],
          'earlySurrender' => [
            button(BlackjackAction.surrender, offer: true),
            button(BlackjackAction.keepPlaying, offer: true),
          ],
          _ => null,
        };
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyH): () => play(BlackjackAction.hit),
            const SingleActivator(LogicalKeyboardKey.keyS): () => play(BlackjackAction.stand),
            const SingleActivator(LogicalKeyboardKey.keyD): () => play(BlackjackAction.double),
            const SingleActivator(LogicalKeyboardKey.keyP): () => play(BlackjackAction.split),
            const SingleActivator(LogicalKeyboardKey.keyR): () => play(BlackjackAction.surrender),
            const SingleActivator(LogicalKeyboardKey.keyI): () => play(BlackjackAction.insurance),
            const SingleActivator(LogicalKeyboardKey.keyN): () => play(BlackjackAction.noInsurance),
            const SingleActivator(LogicalKeyboardKey.keyK): () => play(BlackjackAction.keepPlaying),
          },
          child: Focus(
            autofocus: true,
            child: Column(
              key: const ValueKey('blackjack actions'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (offer != null) Row(key: const ValueKey('offer'), children: offer),
                Row(children: [button(BlackjackAction.hit, strong: true), button(BlackjackAction.stand, strong: true)]),
                Row(
                  children: [
                    button(BlackjackAction.double),
                    button(BlackjackAction.split),
                    button(BlackjackAction.surrender),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The insurance on offer to [you] is even money: their blackjack at a
  /// 3:2 table (as BlackjackView.offersEvenMoney).
  static bool _evenMoney(Map<String, Object?> view, int? you) {
    final felt = FeltView.of(view);
    if (you == null || you >= felt.seats.length || felt.seats[you].length != 1) return false;
    return felt.seats[you].single.isBlackjack && felt.rules?.payout == BlackjackPayout.threeToTwo;
  }
}
