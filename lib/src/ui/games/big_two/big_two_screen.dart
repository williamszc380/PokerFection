import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';

import '../../../app/app_settings.dart';
import '../../../games/big_two/app/big_two_match.dart';
import '../../../games/big_two/app/big_two_record.dart';
import '../../../games/big_two/big_two.dart';
import '../../../l10n/strings.dart';
import '../../kit/cards.dart';
import '../../kit/coach_panel.dart' show ChosenRing;
import '../../kit/felt.dart';
import '../../kit/game_scaffold.dart';
import '../../kit/kit_scope.dart';
import '../../kit/l10n/kit_strings.dart';
import '../../kit/range_sheet.dart';
import '../../table_controller.dart' show PlaybackSpeed;
import 'big_two_coach_view.dart';
import 'big_two_controller.dart';
import 'big_two_opening.dart';
import 'big_two_range_view.dart';
import 'big_two_table.dart';
import 'l10n/big_two_strings.dart';

/// A game of Big Two against bots, on the kit's scaffold: the felt with the
/// seats and the plays piled in the middle (tap: the deal's history), the
/// player's hand fanned under it (cards dragged into the player's own
/// order, the Sort button above its left end), cards flying from the hand
/// or a bot's seat to the pile, and the panel: Play (greyed out until the
/// picked cards make a legal play), Pass and Clear, with the coach's moves,
/// the hand plan and (☰ Card counter) the counter in Training.
///
/// The coach list: a tap on a row picks its cards (Pass: lights the Pass
/// button), a double tap plays it; Pass is always listed when it is legal.
/// In Training, ☰ Show cards turns the bots' hands face up (the coach never
/// sees them), and a tap on a bot opens its range: what it could hold,
/// from what the player has seen. With a target (the setup's Play to) the
/// deals make a match: the totals in the status line (a tap: the
/// scoreboard), the scores between deals, New match at the end.
///
/// Each deal opens with who goes first (big_two_opening.dart): for about
/// two seconds at Normal speed the felt shows it and the headline names
/// the starter ("Kai starts: 3♦"), nobody moving meanwhile; then the
/// middle keeps "Kai starts: 3♦" until the first play.
///
/// Keys: Enter plays the pick or the lit Pass (or deals again after a
/// deal), P passes, Esc clears the pick, S presses the Sort button.
class BigTwoScreen extends StatefulWidget {
  const BigTwoScreen({super.key, required this.setup, this.controller});

  final BigTwoSetup setup;

  /// A controller made outside (tests); otherwise the screen makes one
  /// with the jobs and records of the nearest KitScope.
  final BigTwoController? controller;

  @override
  State<BigTwoScreen> createState() => _BigTwoScreenState();
}

class _BigTwoScreenState extends State<BigTwoScreen> {
  late final BigTwoController controller;
  PlaybackSpeed _speed = PlaybackSpeed.normal;

  @override
  void initState() {
    super.initState();
    final scope = KitScope.of(context);
    controller =
        widget.controller ??
        BigTwoController(setup: widget.setup, jobs: scope.newJobs(), lastGames: scope.lastGames, speed: () => _speed);
    if (!controller.started) controller.newGame();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _speed = AppSettings.of(context).speed;
    // The scoreboard and the status name the player's seat this way.
    controller.youName = S.of(context).you;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final k = KitStrings.of(context);
    final strings = BigTwoStrings.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final coachOn = c.started && c.training && c.coachVisible && !c.isOver;
        final report = coachOn ? c.report : null;
        final net = c.net;
        final rangeLook = bigTwoRangeLook(strings);
        return GameScaffold(
          title: s.bigTwo,
          strings: strings,
          controller: c,
          opponentCards: true,
          matchPlay: true,
          look: bigTwoLook(
            strings,
            onHover: (move) => c.preview = move,
            onSelect: c.selectMove,
            selected: c.selectedMove,
          ),
          // Who goes first while the felt shows it; a pass the player can't
          // avoid says so while it plays itself.
          headline: (context) => c.started && c.openingPlaying && c.opening != null
              ? (c.openingNamed
                    ? bigTwoOpeningText(strings, c.rules, c.opening!, BigTwoTable.seatNames(context, c.record.seats))
                    : strings.whoStarts)
              : c.cantBeat
              ? strings.cantBeat
              : null,
          // The session's points, unless a match keeps the score.
          status: c.started && c.match != null
              ? null
              : k.net(k.pointsValue(net > 0 ? '+$net' : (net < 0 ? '−${-net}' : '0'))),
          table: c.started
              ? BigTwoOpeningStage(
                  id: c.openingDeal,
                  playing: c.openingPlaying,
                  length: c.openingLength,
                  from: c.openingProgress,
                  builder: (context, opening) => BigTwoTable(
                    state: c.state,
                    names: BigTwoTable.seatNames(context, c.record.seats),
                    strings: strings,
                    toAct: c.seatToAct,
                    seed: c.record.seed,
                    handsUp: c.showOpponentCards,
                    points: c.match != null && c.isOver ? bigTwoDealPoints(c.rules, c.state.result) : null,
                    seatWrap: (seat, child) => RangeTap(controller: c, seat: seat, look: rangeLook, child: child),
                    opening: opening,
                  ),
                )
              : const FeltArea(),
          bottom: c.started ? _HandStrip(controller: c) : null,
          panel: _Buttons(controller: c, strings: strings),
          coachExtras: [
            if (report != null && report.plan.isNotEmpty) BigTwoPlanView(report: report, strings: strings),
            if (coachOn && c.counterOn) BigTwoCounterView(counter: c.counter, strings: strings),
          ],
          menuItems: [
            GameMenuItem(
              icon: Icons.fact_check_outlined,
              label: strings.cardCounter,
              // A toggle: the kit's check mark while it is on.
              checked: c.counterOn,
              onTap: () => c.counterOn = !c.counterOn,
              // A coach extra: greyed out in Free Play.
              enabled: c.started && c.training,
            ),
          ],
          shortcuts: {
            const SingleActivator(LogicalKeyboardKey.enter): () {
              if (c.isOver) {
                c.between ? c.nextRound() : c.newGame();
              } else {
                c.playSelected();
              }
            },
            const SingleActivator(LogicalKeyboardKey.keyP): c.passTurn,
            const SingleActivator(LogicalKeyboardKey.escape): c.clearSelection,
            const SingleActivator(LogicalKeyboardKey.keyS): c.sortTap,
          },
        );
      },
    );
  }
}

/// The panel's buttons: Pass, Clear, Play, in Fight the Landlord's order
/// (the filled Play on the right, where each game's main action sits), so a
/// player switching between the two climbing games finds them in the same
/// places. Greyed out (never hidden) when
/// they can't be used: Play until the picked cards make a legal play,
/// Pass when passing isn't allowed (leading) or it isn't the player's
/// turn, Clear with nothing picked.
class _Buttons extends StatelessWidget {
  const _Buttons({required this.controller, required this.strings});

  final BigTwoController controller;
  final BigTwoStrings strings;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    Widget fit(String text) => FittedBox(fit: BoxFit.scaleDown, child: Text(text, maxLines: 1));
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            // Lit while Pass is picked from the coach list.
            child: ChosenRing(
              lit: c.passChosen,
              child: OutlinedButton(
                key: const ValueKey('pass'),
                onPressed: c.canPass ? c.passTurn : null,
                child: fit(strings.pass),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 3,
            child: TextButton(
              key: const ValueKey('clear'),
              onPressed: c.canClear ? c.clearSelection : null,
              child: fit(strings.clear),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 4,
            child: FilledButton(
              key: const ValueKey('play'),
              onPressed: c.canPlay ? c.playSelected : null,
              child: fit(strings.play),
            ),
          ),
        ],
      ),
    );
  }
}

/// The player's hand under the table (never under the panel): one fan
/// (BigTwoHandView) taking the whole width, so even 21 cards keep their
/// corners readable on a sideways phone. A tap picks or unpicks a card (one
/// tap per card); dragging a card moves it to a new place in the hand; the
/// Sort button above the fan's left end sorts it by rank or by suit. A
/// coach move under the mouse fades the cards it doesn't use. A card
/// everyone has seen (the starting card until it is played, a three-player
/// deal's face-up card) carries the eye. Played cards fly from here to the
/// pile. After the deal the hand stays to see, its cards and its Sort
/// button greyed out of reach.
class _HandStrip extends StatelessWidget {
  const _HandStrip({required this.controller});

  final BigTwoController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final hand = c.hand;
    final preview = c.preview;
    final previewCards = preview == null ? null : bigTwoMoveCards(preview).toSet();
    final live = !c.isOver;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 6),
      child: BigTwoHandView(
        cards: hand,
        selected: c.selected,
        dimmed: {
          if (previewCards != null)
            for (final card in hand)
              if (!previewCards.contains(card)) card,
        },
        visible: c.visibleInHand,
        onToggle: live ? c.toggle : null,
        onReorder: live ? c.reorder : null,
        sortOrder: c.sortOrder,
        onSort: live ? c.sortTap : null,
      ),
    );
  }
}

/// A hand of cards, fanned across the width it gets (the kit's HandFan):
/// a gentle arc, each card tilted a little more toward the ends and
/// overlapping its neighbour, so any deal, up to 21 cards, fits under the
/// table. Every card keeps at least [showing] of its width in view, so its
/// corner ("10") reads: the cards get smaller rather than overlap more.
/// [selected] cards pop up, [dimmed] ones fade, [visible] ones (cards
/// everyone at the table has seen) carry the eye; [onToggle] (null: look
/// only) picks a card, [onReorder] (null: they stay put) takes a card
/// dragged to a new place. With a [sortOrder] the hand carries its Sort
/// button just above its left end, greyed out without [onSort].
class BigTwoHandView extends StatelessWidget {
  const BigTwoHandView({
    super.key,
    required this.cards,
    this.selected = const {},
    this.dimmed = const {},
    this.visible = const {},
    this.onToggle,
    this.onReorder,
    this.sortOrder,
    this.onSort,
  });

  /// The cards in the order they lie, left to right.
  final List<Card> cards;
  final Set<Card> selected;
  final Set<Card> dimmed;

  /// The cards of the hand everyone at the table can see (BigTwoTableFacts
  /// .visibleIn): the eye on their corner, the kit's label under the mouse
  /// or on a long press.
  final Set<Card> visible;
  final ValueChanged<Card>? onToggle;

  /// The card at `from` in [cards] was dragged to `to` (its place once
  /// moved, see moveCard).
  final void Function(int from, int to)? onReorder;

  /// What the Sort button shows (the order the hand is in); null: no button.
  final HandOrder? sortOrder;

  /// A tap on the Sort button; null: greyed out.
  final VoidCallback? onSort;

  /// The least share of each card in view, enough for a corner's whole
  /// "10" (it reaches about 45% across the card; at 35% a 10 read as "1"):
  /// 21 cards still come out about 27 px wide, their ranks over 10 px
  /// tall, in the ~276 px a sideways phone leaves the hand.
  static const showing = 0.46;

  /// The widest the hand's cards are drawn.
  static const maxCardWidth = 76.0;

  @override
  Widget build(BuildContext context) {
    return HandFan(
      key: const ValueKey('hand'),
      cards: [for (final card in cards) bigTwoFace(card)],
      selected: {
        for (final (i, card) in cards.indexed)
          if (selected.contains(card)) i,
      },
      dimmed: {
        for (final (i, card) in cards.indexed)
          if (dimmed.contains(card)) i,
      },
      visibleToAll: {
        for (final (i, card) in cards.indexed)
          if (visible.contains(card)) i,
      },
      onToggle: onToggle == null ? null : (i) => onToggle!(cards[i]),
      onReorder: onReorder,
      sortOrder: sortOrder,
      onSort: onSort,
      maxCardWidth: maxCardWidth,
      showing: showing,
    );
  }
}
