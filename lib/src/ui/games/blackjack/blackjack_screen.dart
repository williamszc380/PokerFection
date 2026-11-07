import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_settings.dart';
import '../../../games/blackjack/app/blackjack_record.dart';
import '../../../games/blackjack/blackjack.dart';
import '../../../l10n/strings.dart';
import '../../kit/coach_panel.dart';
import '../../kit/game_scaffold.dart';
import '../../kit/kit_scope.dart';
import '../../kit/l10n/kit_strings.dart';
import '../../kit/range_sheet.dart';
import '../../table_controller.dart' show PlaybackSpeed;
import 'blackjack_coach_view.dart';
import 'blackjack_controller.dart';
import 'blackjack_table.dart';
import 'l10n/blackjack_strings.dart';

/// A game of blackjack: one shoe against the dealer, betting 1 a round.
/// The felt on the left (or on top, upright), the panel with the coach and
/// the buttons on the right: Deal between rounds; Hit, Stand, Double, Split
/// and Surrender in a round (greyed out when not allowed), with Insurance /
/// No insurance or Surrender / Keep playing above them when the round
/// offers them. Keys: H S D P R, I N for insurance, K to keep playing,
/// Enter or Space to deal.
class BlackjackScreen extends StatefulWidget {
  const BlackjackScreen({super.key, this.settings = const BlackjackSettings(), this.random});

  final BlackjackSettings settings;

  /// Where shoe seeds come from (null: Random.secure); tests pass a fixed one.
  final Random? random;

  @override
  State<BlackjackScreen> createState() => _BlackjackScreenState();
}

class _BlackjackScreenState extends State<BlackjackScreen> {
  BlackjackController? _controller;

  /// The move under the mouse in the coach list: its button is outlined.
  /// (One click on a row lights the button brighter: TurnController.chosen.)
  final _preview = ValueNotifier<String?>(null);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final scope = KitScope.of(context);
    final settings = AppSettings.of(context);
    final b = BlackjackStrings.of(context);
    final controller = BlackjackController(
      settings: widget.settings,
      jobs: scope.newJobs(),
      lastGames: scope.lastGames,
      playerName: S.of(context).you,
      dealerName: b.dealerSeat,
      speed: () => settings.speed,
      random: widget.random,
    );
    // A move made ends any preview of the one before (the row under the
    // mouse belonged to the position before it).
    var moves = 0;
    controller.addListener(() {
      final now = controller.started ? controller.record.moves.length : 0;
      if (now != moves) _preview.value = null;
      moves = now;
    });
    _controller = controller;
    unawaited(controller.newGame());
  }

  @override
  void dispose() {
    _controller?.dispose();
    _preview.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    final b = BlackjackStrings.of(context);
    final k = KitStrings.of(context);
    final s = S.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final started = controller.started;
        final status = started
            ? [
                k.net(betsText(controller.play.net)),
                // A sideways phone's status line has room for the net only.
                if (controller.play.rounds > 0 && MediaQuery.sizeOf(context).height >= 400)
                  b.round(controller.play.rounds),
              ].join(' · ')
            : null;
        void move(BlackjackAction action) => _play(controller, action);
        return GameScaffold(
          title: s.blackjack,
          strings: b,
          controller: controller,
          table: BlackjackTableView(
            play: started ? controller.play : null,
            showCount: controller.showCount,
            dealing: controller.dealing,
            flipInstantly: controller.speed == PlaybackSpeed.instant,
            // ☰ Show cards (Training only): the hole card face up from the
            // deal. The coach and the grades never see it.
            showHoleCard: controller.showOpponentCards,
            // Training: a tap on the dealer opens the dealer's range.
            dealerWrap: (dealer) =>
                RangeTap(controller: controller, seat: dealerSeat, look: blackjackRangeLook(b), child: dealer),
          ),
          panel: BlackjackPanel(controller: controller, preview: _preview),
          status: status,
          // Between rounds the player's only move is the deal: the panel
          // says how the round just played ended rather than "Your turn",
          // once the dealer's cards are all down ("Dealer…" until then).
          // While the opening cards fly in, the buttons wait, so it says
          // "Dealer…" then too, never "Your turn" over greyed buttons.
          headline: (context) => !started
              ? null
              : controller.dealing.busy
              ? s.thinking(b.dealer)
              : controller.betweenRounds && !controller.isOver
              ? switch (controller.play.round) {
                  final round? => roundResultText(b, round),
                  null => null,
                }
              : null,
          look: blackjackCoachLook(
            strings: b,
            controller: controller,
            deal: k.deal,
            // The kit ends a hover after the frame in which its row went
            // away, which may be the frame this screen closed in.
            onPreview: (move) {
              if (mounted) _preview.value = move;
            },
          ),
          newGameLabel: k.newShoe,
          opponentCards: true,
          menuItems: [
            GameMenuItem(
              icon: Icons.calculate,
              label: b.countToggle,
              checked: controller.showCount,
              // With a continuous shuffler every round starts from a full
              // shoe: there is nothing to count.
              enabled: started && !controller.rules.continuousShuffle,
              onTap: () => controller.showCount = !controller.showCount,
            ),
          ],
          shortcuts: {
            const SingleActivator(LogicalKeyboardKey.keyH): () => move(BlackjackAction.hit),
            const SingleActivator(LogicalKeyboardKey.keyS): () => move(BlackjackAction.stand),
            const SingleActivator(LogicalKeyboardKey.keyD): () => move(BlackjackAction.double),
            const SingleActivator(LogicalKeyboardKey.keyP): () => move(BlackjackAction.split),
            const SingleActivator(LogicalKeyboardKey.keyR): () => move(BlackjackAction.surrender),
            const SingleActivator(LogicalKeyboardKey.keyI): () => move(BlackjackAction.insurance),
            const SingleActivator(LogicalKeyboardKey.keyN): () => move(BlackjackAction.noInsurance),
            const SingleActivator(LogicalKeyboardKey.keyK): () => move(BlackjackAction.keepPlaying),
            const SingleActivator(LogicalKeyboardKey.enter): () => _next(controller),
            const SingleActivator(LogicalKeyboardKey.space): () => _next(controller),
          },
        );
      },
    );
  }

  /// Plays [action] if it is allowed now (a key for a greyed button does nothing).
  static void _play(BlackjackController controller, BlackjackAction action) {
    if (!controller.started || controller.preparing || controller.isOver || controller.dealing.busy) return;
    final hand = controller.play.handToPlay;
    if (hand == null) return;
    final move = handMove(hand, action);
    if (controller.play.legalMoves().contains(move)) controller.humanMove(move);
  }

  /// Enter and Space: the next round, or a new shoe once this one is over.
  static void _next(BlackjackController controller) {
    if (!controller.started || controller.preparing || controller.dealing.busy) return;
    if (controller.isOver) {
      unawaited(controller.newGame());
    } else if (controller.betweenRounds) {
      controller.humanMove(dealMove);
    }
  }
}

/// The panel's buttons: Deal between rounds; in a round the five decisions,
/// greyed out when not allowed, and the round's offer (insurance or early
/// surrender) above them while it stands. All of them are greyed out while
/// the cards are being dealt or the dealer plays (BlackjackDealing.busy).
class BlackjackPanel extends StatelessWidget {
  const BlackjackPanel({super.key, required this.controller, required this.preview});

  final BlackjackController controller;

  /// The coach row under the mouse: that button is outlined.
  final ValueListenable<String?> preview;

  @override
  Widget build(BuildContext context) {
    final b = BlackjackStrings.of(context);
    final k = KitStrings.of(context);
    if (!controller.started) return const SizedBox.shrink();
    final play = controller.play;
    return ValueListenableBuilder<String?>(
      valueListenable: preview,
      builder: (context, previewed, _) {
        final busy = controller.dealing.busy;
        if (play.betweenRounds) {
          return Padding(
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('deal'),
                onPressed: busy || controller.isOver ? null : () => controller.humanMove(dealMove),
                icon: const Icon(Icons.style),
                label: Text(k.deal),
              ),
            ),
          );
        }
        final round = play.round!;
        final hand = round.turn!.hand;
        final legal = play.legalMoves().toSet();
        final playing = round.phase == RoundPhase.playing;
        // The five decisions are greyed out while an offer stands; the
        // offer's own buttons answer it.
        Widget button(BlackjackAction action, {bool strong = false, String? label, bool offer = false}) {
          final move = handMove(hand, action);
          final allowed = !busy && (offer || playing) && legal.contains(move);
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: BlackjackActionButton(
                key: ValueKey('${offer ? 'offer' : 'action'} ${action.name}'),
                label: label ?? b.action(action),
                strong: strong,
                lit: previewed == move,
                chosen: allowed && controller.chosen == move,
                onPressed: allowed ? () => controller.humanMove(move) : null,
              ),
            ),
          );
        }

        final view = round.viewFor(playerSeat);
        final offer = switch (round.phase) {
          RoundPhase.insurance => [
            button(BlackjackAction.insurance, label: view.offersEvenMoney ? b.evenMoney : null, offer: true),
            button(BlackjackAction.noInsurance, offer: true),
          ],
          RoundPhase.earlySurrender => [
            button(BlackjackAction.surrender, offer: true),
            button(BlackjackAction.keepPlaying, offer: true),
          ],
          _ => null,
        };
        return Padding(
          padding: const EdgeInsets.fromLTRB(5, 4, 5, 6),
          child: Column(
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
        );
      },
    );
  }
}

/// One decision's button: filled for Hit and Stand, outlined for the rest,
/// with a gold edge while the coach's row for it is under the mouse, and a
/// bright ring while that row is selected ([chosen]: a double click on the
/// row, Enter or the button itself makes it). Greyed out (and inert)
/// without [onPressed]. The room's table (blackjack_online_ui.dart) uses
/// the same buttons, so the game looks and plays the same online.
class BlackjackActionButton extends StatelessWidget {
  const BlackjackActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.strong = false,
    this.lit = false,
    this.chosen = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool strong;
  final bool lit;
  final bool chosen;

  /// An outlined button's fill while it is chosen (see build).
  static const chosenFill = Color(0xFF1F2A2F);

  @override
  Widget build(BuildContext context) {
    final text = FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1));
    final side = lit ? const BorderSide(color: Color(0xFFFFD54F), width: 2) : null;
    final style = ButtonStyle(
      visualDensity: VisualDensity.compact,
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 6)),
      minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
      side: side == null ? null : WidgetStatePropertyAll(side),
      // The ring's glow is drawn behind the button: an outlined button,
      // clear inside, would be washed out by it, so it gets a solid fill.
      backgroundColor: chosen && !strong ? const WidgetStatePropertyAll(chosenFill) : null,
    );
    return ChosenRing(
      lit: chosen,
      // The buttons are 36 tall and fully rounded.
      radius: 18,
      child: strong
          ? FilledButton.tonal(onPressed: onPressed, style: style, child: text)
          : OutlinedButton(onPressed: onPressed, style: style, child: text),
    );
  }
}
