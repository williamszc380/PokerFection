import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_settings.dart';
import '../../../games/doudizhu/app/doudizhu_record.dart';
import '../../../games/doudizhu/doudizhu.dart';
import '../../../l10n/strings.dart';
import '../../kit/coach_panel.dart';
import '../../kit/felt.dart';
import '../../kit/game_scaffold.dart';
import '../../kit/kit_scope.dart';
import '../../kit/l10n/kit_strings.dart';
import '../../kit/range_sheet.dart';
import 'doudizhu_coach_view.dart';
import 'doudizhu_controller.dart';
import 'doudizhu_range_view.dart';
import 'doudizhu_table.dart';
import 'l10n/doudizhu_strings.dart';

/// A game of Fight the Landlord on the kit's scaffold: the felt with the
/// deal's plays piled in the middle and both bots' hands under their names,
/// the player's hand fanned under it, the coach hidden until its chip is on
/// (a fresh game's default), and the panel with the status (whose turn, the
/// multiplier "×4", the match's deal and totals, or the session's net with
/// no match), the coach's moves, the card counter and the buttons: the bids
/// during the auction, then Pass, Clear and Play (greyed out unless the
/// picked cards can be played).
///
/// In Training, ☰ Show cards turns the bots' hands up, and tapping a bot's
/// seat opens its range. A tap on a coach row selects its move, a double
/// tap plays it. ☰ Scores opens the match's scoreboard.
class LandlordScreen extends StatefulWidget {
  const LandlordScreen({super.key, this.choice = const LandlordChoice(), this.controller});

  final LandlordChoice choice;

  /// A game already running (tests); the screen then neither starts nor
  /// disposes of it.
  @visibleForTesting
  final LandlordController? controller;

  @override
  State<LandlordScreen> createState() => _LandlordScreenState();
}

class _LandlordScreenState extends State<LandlordScreen> {
  LandlordController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    if (widget.controller case final given?) {
      _controller = given;
      return;
    }
    final scope = KitScope.of(context);
    final settings = AppSettings.of(context);
    _controller = LandlordController(
      jobs: scope.newJobs(),
      lastGames: scope.lastGames,
      choice: widget.choice,
      speed: () => settings.speed,
    )..newGame();
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    final s = LandlordStrings.of(context);
    // The player's seat in this language, wherever the kit names seats.
    controller.playerName = S.of(context).you;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final counterOn = controller.started && (controller.record.extra['counter'] as bool? ?? true);
        return GameScaffold(
          title: S.of(context).fightTheLandlord,
          strings: s,
          controller: controller,
          table: controller.started
              ? LandlordTable(
                  felt: LandlordFelt.of(controller),
                  strings: s,
                  seatTap: (seat, child) =>
                      RangeTap(controller: controller, seat: seat, look: landlordRangeLook(s), child: child),
                )
              : const FeltArea(),
          bottom: LandlordHand.of(controller),
          panel: LandlordButtons(controller: controller, strings: s),
          look: landlordLook(controller, s),
          opponentCards: true,
          matchPlay: true,
          headline: (_) => _headline(controller, s),
          status: _status(context, controller, s),
          coachExtras: [
            if (controller.started) LandlordTeamLine(controller: controller, strings: s),
            if (controller.started && counterOn)
              LandlordCardCounter(
                count: controller.game.viewFor(LandlordController.you).cardCount,
                strings: s,
                help: [s.entry(LandlordTerm.cardCounter)],
              ),
          ],
          menuItems: [
            GameMenuItem(
              icon: counterOn ? Icons.check_box_outlined : Icons.check_box_outline_blank,
              label: s.cardCounter,
              enabled: controller.started,
              onTap: () => controller.setExtra('counter', !counterOn),
            ),
          ],
          shortcuts: {
            // Enter plays the picked cards, or deals again once a deal is over.
            const SingleActivator(LogicalKeyboardKey.enter): () => controller.isOver
                ? (controller.between ? controller.nextRound() : controller.newGame())
                : controller.playSelection(),
            const SingleActivator(LogicalKeyboardKey.escape): controller.clearSelection,
          },
        );
      },
    );
  }

  /// The headline the game sets: while the deal opens, who bids first
  /// once the face-up card has landed (the felt's middle says it too, until
  /// the first bid); a thrown-in deal is nobody's win ("Everyone passed",
  /// not "Draw"); and a pass the player can't avoid says so while it plays
  /// itself. Null: the kit's own (whose turn, who won).
  static String? _headline(LandlordController c, LandlordStrings s) {
    if (!c.started) return null;
    if (c.dealing case final d?) {
      final named = d.landed && d.game.faceUp != null;
      return named ? s.firstToBid(c.seatName(d.order.firstBidder), c.rules.bidding) : null;
    }
    if (c.thrownIn) return s.everyonePassed;
    return c.cantBeat ? s.cantBeat : null;
  }

  /// The status line's second part: the multiplier, a spring when there
  /// was one, and with no match the session's net (a match shows its
  /// totals itself).
  static String? _status(BuildContext context, LandlordController c, LandlordStrings s) {
    if (!c.started) return null;
    final k = KitStrings.of(context);
    final result = c.game.result;
    final net = c.sessionNet;
    final parts = [
      if (c.totalMultiplier case final x?) s.multiplier(x),
      if (result != null && result.spring) s.spring,
      if (result != null && result.antiSpring) s.antiSpring,
      if (c.match == null && (c.deals > 1 || result != null)) k.net(net > 0 ? '+$net' : (net < 0 ? '−${-net}' : '0')),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

/// The game's buttons. During the auction: No bid and the bids (points),
/// or Call / No call, Rob / No rob; the coach's advice is tagged "GTO"
/// when the coach is on. In play: Pass, Clear and Play. Buttons that can't
/// be used now are greyed out, never hidden. A choice selected from the
/// coach list (TurnController.chosen) has its button ringed: a press, a
/// double tap on the row or Enter plays it.
class LandlordButtons extends StatelessWidget {
  const LandlordButtons({super.key, required this.controller, required this.strings});

  final LandlordController controller;
  final LandlordStrings strings;

  @override
  Widget build(BuildContext context) {
    if (!controller.started) return const SizedBox(height: 48);
    final game = controller.game;
    // Not while the deal still opens (nobody is to act meanwhile).
    final yours = controller.playerToMove;
    final legal = yours ? game.legalMoves() : const <DdzMove>[];
    final coach = controller.training && controller.coachVisible ? controller.coach : null;
    final pick = coach == null ? null : ddzParseMove(coach.pick, controller.rules).move;
    final s = strings;

    Widget button(String label, DdzMove? move, {VoidCallback? onPressed, bool primary = false, Key? key}) {
      final enabled = onPressed != null || (move != null && legal.contains(move));
      final action =
          onPressed ?? (move == null ? null : () => controller.humanMove(ddzMoveText(LandlordController.you, move)));
      final advised = move != null && pick == move && enabled;
      final lit = move != null && enabled && controller.chosen == ddzMoveText(LandlordController.you, move);
      final style = ButtonStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 6)),
        // Ringed (chosen from the coach list), an outlined button gets the
        // panel's own colour behind it, so the ring's glow shows round it
        // rather than through it.
        backgroundColor: lit && !primary ? const WidgetStatePropertyAll(Color(0xFF12171B)) : null,
        visualDensity: VisualDensity.compact,
        side: advised
            ? WidgetStatePropertyAll(BorderSide(color: Theme.of(context).colorScheme.primary, width: 2))
            : null,
      );
      final text = FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1));
      final b = primary
          ? FilledButton(key: key, onPressed: enabled ? action : null, style: style, child: text)
          : OutlinedButton(key: key, onPressed: enabled ? action : null, style: style, child: text);
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: ChosenRing(lit: lit, radius: 20, child: advised ? _Advised(label: s.pickLabel, child: b) : b),
        ),
      );
    }

    final List<Widget> buttons;
    if (game.phase == DdzPhase.bidding) {
      buttons = switch (game.rules.bidding) {
        BiddingStyle.points => [
          button(s.noBid, const DdzBid(0), key: const ValueKey('bid 0')),
          for (var b = 1; b <= 3; b++) button(s.bid(b), DdzBid(b), key: ValueKey('bid $b'), primary: true),
        ],
        BiddingStyle.callRob when game.isRobbing => [
          button(s.noRob, const DdzRob(false), key: const ValueKey('rob 0')),
          button(s.rob, const DdzRob(true), key: const ValueKey('rob 1'), primary: true),
        ],
        BiddingStyle.callRob => [
          button(s.noCall, const DdzCall(false), key: const ValueKey('call 0')),
          button(s.call, const DdzCall(true), key: const ValueKey('call 1'), primary: true),
        ],
      };
    } else {
      final canPlay = controller.selectedMove != null;
      buttons = [
        button(s.pass, const DdzPass(), key: const ValueKey('pass')),
        button(
          s.clear,
          null,
          key: const ValueKey('clear'),
          onPressed: controller.selected.isEmpty && controller.chosen == null ? null : controller.clearSelection,
        ),
        button(
          s.play,
          null,
          key: const ValueKey('play'),
          primary: true,
          onPressed: canPlay ? controller.playSelection : null,
        ),
      ];
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(5, 8, 5, 6),
      child: SizedBox(
        height: 38,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: buttons),
      ),
    );
  }
}

/// A button the coach advises: a small "GTO" tag on its top edge.
class _Advised extends StatelessWidget {
  const _Advised({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: child),
        Positioned(
          top: -9,
          right: 4,
          child: IgnorePointer(
            child: Container(
              key: const ValueKey('advised'),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(6)),
              child: Text(
                label,
                style: const TextStyle(fontSize: 10, color: Colors.black, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
