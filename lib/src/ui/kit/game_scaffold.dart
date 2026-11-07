import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';
import 'card_flights.dart';
import 'coach_panel.dart';
import 'guide_kit.dart';
import 'help.dart';
import 'l10n/game_strings.dart';
import 'l10n/kit_strings.dart';
import 'match_view.dart';
import 'move_feedback.dart';
import 'turn_controller.dart';

/// An extra item of a game's ☰ menu (Card counter, Count, Sort).
class GameMenuItem {
  const GameMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.checked,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Greyed out when false (never hidden).
  final bool enabled;

  /// A toggle (☰ Count): a check mark at the end of the item while true;
  /// null: not a toggle.
  final bool? checked;
}

/// Every new game's screen: a slim top bar (the game's name, the coach
/// chip, ☰), the table, and the panel (status, the grade of the last move,
/// the coach's moves, the game's buttons).
///
/// Sideways (phones, PCs): the table on the left with a card game's hand
/// under it, as wide as the table, and the panel down the whole right side.
/// Upright (browsers only): the table, the hand, then the panel. When the
/// screen under the bar is less than 340 tall, or the panel itself less
/// than 240 (upright, under the table and the hand), the panel is compact:
/// the grade joins the status line, the coach shows 3 moves (up to 5 when
/// they fit), and Think longer is an icon at the end of the status line.
///
/// Cards the game flies (TurnController.flights) are drawn over the table
/// and the hand.
///
/// While the game prepares (TurnController.preparing: Blackjack's chart),
/// the game's buttons and keys are greyed out and a thin bar runs.
///
/// The coach list works the same in every game: a tap on a row selects its
/// move, a double tap plays it, and Enter plays a choice selected that way
/// (TurnController.chosen) before the game's own Enter. With a match
/// (TurnController.match) the status line shows the deal and the totals
/// (a tap opens the scoreboard), the scoreboard shows between deals, and
/// once the match is over the button is New match.
class GameScaffold extends StatelessWidget {
  const GameScaffold({
    super.key,
    required this.title,
    required this.strings,
    required this.controller,
    required this.table,
    required this.panel,
    this.bottom,
    this.coachExtras = const [],
    this.status,
    this.menuItems = const [],
    this.shortcuts = const {},
    this.look = const CoachLook(),
    this.newGameLabel,
    this.squareTable = false,
    this.headline,
    this.opponentCards = false,
    this.matchPlay = false,
  });

  /// The game's name.
  final String title;
  final GameStrings strings;
  final TurnController controller;

  /// The board, or the felt with the seats and played cards.
  final Widget table;

  /// The game's action buttons, always at the bottom of the panel.
  final Widget panel;

  /// Card games: the player's hand, under the table and as wide as it.
  final Widget? bottom;

  /// Widgets under the coach's moves (a card counter...).
  final List<Widget> coachExtras;

  /// More for the status line's second line: "×4", "Net +3.5 bets".
  final String? status;

  /// The game's own ☰ items, after New game.
  final List<GameMenuItem> menuItems;

  /// Keys: Enter = confirm or next, the game's letters (H S D P...). Enter
  /// starts the next deal (or game) by itself once one is over.
  final Map<ShortcutActivator, VoidCallback> shortcuts;

  /// How the coach list and the feedback show moves.
  final CoachLook look;

  /// ☰'s first item and the button after a game (null: New Game; Blackjack:
  /// New shoe).
  final String? newGameLabel;

  /// Upright: the table as tall as it is wide (Gomoku's board).
  final bool squareTable;

  /// The game's own words for the status line's first part, asked on every
  /// rebuild; null (or a null answer): the kit's ("Your turn", "Ana…", "You
  /// win", "Draw"). Fight the Landlord: "Everyone passed" for a deal thrown
  /// in; Blackjack: the last round's result while the next waits for Deal.
  final String? Function(BuildContext context)? headline;

  /// The opponents hold hidden cards: ☰ has Show cards (Training only,
  /// greyed out in Free Play; TurnController.showOpponentCards).
  final bool opponentCards;

  /// The game can play a match: ☰ has Scores (greyed out when this game
  /// has no target).
  final bool matchPlay;

  /// [look] with what every game shares filled in where the game gives
  /// nothing: a tap selects a choice (TurnController.choose), a double tap
  /// plays the row's move, and the chosen choice's row is lit. A tap first
  /// drops the choice lit before, so a row of cards never leaves a Pass lit.
  CoachLook get coachLook {
    final select = look.onSelect ?? controller.choose;
    return look.copyWith(
      onSelect: (move) {
        controller.choose(null);
        select(move);
      },
      onPlay: look.onPlay ?? (move) => controller.playFromCoach(move),
      selected: () => look.selected ?? controller.chosen,
    );
  }

  /// Below this height of the screen under the bar, the panel is compact: a
  /// 592x360 phone's 316 has no room for the whole grade card above the
  /// coach's moves.
  static const compactBelow = 340.0;

  /// ... and below this height of the panel itself.
  static const compactPanelBelow = 240.0;

  @override
  Widget build(BuildContext context) {
    final short = MediaQuery.sizeOf(context).height < 500;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Scaffold(
        backgroundColor: const Color(0xFF0B0F12),
        appBar: AppBar(
          backgroundColor: const Color(0xFF12171B),
          // Phones are played sideways: keep the bar slim when height is short.
          toolbarHeight: short ? 44 : null,
          // Back is in ☰ (the game is saved after every move).
          automaticallyImplyLeading: false,
          titleSpacing: 12,
          title: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(title, maxLines: 1)),
          actions: [_CoachChip(controller: controller, label: strings.pickLabel), _menu(context)],
        ),
        body: CallbackShortcuts(
          bindings: {
            if (!shortcuts.keys.any(_isEnter) && controller.started && controller.isOver)
              const SingleActivator(LogicalKeyboardKey.enter): () => _again()
            else if (!shortcuts.keys.any(_isEnter) && controller.chosen != null)
              const SingleActivator(LogicalKeyboardKey.enter): () => controller.playChosen(),
            // Nobody moves until the game is ready (the keys would throw).
            if (!controller.preparing)
              for (final MapEntry(key: key, value: action) in shortcuts.entries)
                // Enter plays the choice lit from the coach list first.
                key: _isEnter(key) ? () => controller.playChosen() || _run(action) : action,
          },
          child: Focus(
            autofocus: true,
            child: SafeArea(
              top: false,
              child: CardFlightLayer(flights: controller.flights, child: LayoutBuilder(builder: _layout)),
            ),
          ),
        ),
      ),
    );
  }

  static bool _isEnter(ShortcutActivator activator) =>
      activator is SingleActivator && activator.trigger == LogicalKeyboardKey.enter;

  static bool _run(VoidCallback action) {
    action();
    return true;
  }

  /// After a game or deal: the next deal, or a new game.
  void _again() => controller.between ? controller.nextRound() : controller.newGame();

  Widget _layout(BuildContext context, BoxConstraints constraints) => split(
        constraints: constraints,
        table: table,
        bottom: bottom,
        squareTable: squareTable,
        panel: (compact) => _Panel(scaffold: this, compact: compact),
      );

  /// The hand's height under a sideways table, for [height] under the bar.
  static double handHeight(double height) => (height * 0.32).clamp(80.0, 160.0);

  /// The split of a game's screen (and its review's) in [constraints]:
  /// sideways, the table with the hand under it on the left and the panel
  /// down the whole right side; upright, the table, the hand, the panel.
  /// [panel] is told whether it must be compact.
  static Widget split({
    required BoxConstraints constraints,
    required Widget table,
    Widget? bottom,
    bool squareTable = false,
    required Widget Function(bool compact) panel,
  }) {
    final w = constraints.maxWidth, h = constraints.maxHeight;
    if (w >= h) {
      // The panel keeps the whole height: the hand is under the table only.
      final compact = h < compactBelow;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: bottom == null
                ? table
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: table),
                      SizedBox(key: const ValueKey('hand area'), height: handHeight(h), child: bottom),
                    ],
                  ),
          ),
          SizedBox(
            width: (w * 0.34).clamp(280.0, 420.0),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Color(0xFF12171B),
                border: Border(left: BorderSide(color: Colors.white12)),
              ),
              child: panel(compact),
            ),
          ),
        ],
      );
    }
    // Upright (a browser): the table, the hand, then the panel.
    final tableHeight = squareTable ? w.clamp(0.0, h * 0.55) : h * 0.42;
    final hand = bottom == null ? 0.0 : h * 0.22;
    final compact = h < compactBelow || h - tableHeight - hand < compactPanelBelow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: tableHeight, child: table),
        if (bottom != null) SizedBox(key: const ValueKey('hand area'), height: hand, child: bottom),
        Expanded(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: Color(0xFF12171B),
              border: Border(top: BorderSide(color: Colors.white12)),
            ),
            child: panel(compact),
          ),
        ),
      ],
    );
  }

  Widget _menu(BuildContext context) {
    final s = S.of(context);
    final k = KitStrings.of(context);
    return PopupMenuButton<VoidCallback>(
      icon: const Icon(Icons.menu),
      onSelected: (action) => action(),
      // The actions use the screen's context: the menu's is gone once it closes.
      itemBuilder: (_) {
        PopupMenuItem<VoidCallback> item(
          IconData icon,
          String text,
          VoidCallback action, {
          bool enabled = true,
          bool? checked,
        }) =>
            PopupMenuItem(
              value: action,
              enabled: enabled,
              height: 40,
              mouseCursor: WidgetStateMouseCursor.clickable,
              child: Semantics(
                checked: checked,
                child: Row(
                  children: [
                    Icon(icon, size: 20),
                    const SizedBox(width: 12),
                    Expanded(child: Text(text)),
                    // A toggle: the check mark while on, its room kept while off.
                    if (checked != null) ...[
                      const SizedBox(width: 12),
                      SizedBox.square(
                        dimension: 20,
                        child: checked ? const Icon(Icons.check, size: 20, key: ValueKey('checked')) : null,
                      ),
                    ],
                  ],
                ),
              ),
            );
        final terms = [for (final t in KitTerm.values) k.entry(t), ...strings.glossary];
        return [
          item(Icons.refresh, newGameLabel ?? s.newGame, () => controller.newGame()),
          for (final extra in menuItems)
            item(extra.icon, extra.label, extra.onTap, enabled: extra.enabled, checked: extra.checked),
          if (opponentCards)
            item(
              Icons.style_outlined,
              k.showCards,
              () => controller.showOpponentCards = !controller.showOpponentCards,
              // Training only: greyed out in Free Play, never hidden.
              enabled: controller.training && controller.started,
              checked: controller.showOpponentCards,
            ),
          if (matchPlay)
            item(
              Icons.leaderboard_outlined,
              k.scores,
              () => showScoreboard(context, controller),
              enabled: controller.match != null,
            ),
          const PopupMenuDivider(),
          item(Icons.menu_book_outlined, s.rules, () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => GuidePage(title: s.rules, sections: strings.rulesSections)),
            );
          }),
          item(Icons.help_outline, s.glossary, () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => GameGlossaryScreen(title: s.glossary, terms: terms)),
            );
          }),
          // Back to the game's menu, without asking: the game is already saved.
          item(Icons.logout, s.leave, () => Navigator.of(context).maybePop()),
        ];
      },
    );
  }
}

/// The coach chip: shows or hides the coach; greyed out in Free Play.
class _CoachChip extends StatelessWidget {
  const _CoachChip({required this.controller, required this.label});

  final TurnController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    final on = controller.training && controller.coachVisible;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: FilterChip(
        key: const ValueKey('coach chip'),
        label: Text(label, maxLines: 1, softWrap: false),
        selected: on,
        showCheckmark: false,
        avatar: Icon(on ? Icons.visibility : Icons.visibility_off, size: 16),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        mouseCursor: WidgetStateMouseCursor.clickable,
        onSelected: controller.training && controller.started ? (v) => controller.coachVisible = v : null,
      ),
    );
  }
}

/// The panel: status, feedback, the coach's moves (scrolling), the buttons.
class _Panel extends StatelessWidget {
  const _Panel({required this.scaffold, required this.compact});

  final GameScaffold scaffold;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final controller = scaffold.controller;
    final s = S.of(context);
    final k = KitStrings.of(context);
    if (!controller.started) return const SizedBox.shrink();
    final mark = controller.training ? controller.lastMark : null;
    // The scale's unit (the feedback prefers the mark's own, MoveMark.unit).
    final unit = controller.scale.unit;
    final markIndex = mark == null ? null : controller.marks.lastIndexWhere((m) => m != null);
    final average = controller.averageScore;
    final match = matchStatus(context, controller, compact: compact);
    final score = controller.training && average != null ? s.score(average) : null;
    // Compact, the line is short: the game's own words (Fight the Landlord's
    // ×2) and the match's totals and target come before the average score,
    // which is the one cut off.
    final second = (compact ? [?scaffold.status, ?match, ?score] : [?match, ?score, ?scaffold.status]).join(' · ');
    // A tap on the status's second line opens the scoreboard.
    final scores = match == null ? null : () => showScoreboard(context, controller);
    final showCoach = controller.training &&
        controller.coachVisible &&
        !controller.isOver &&
        (controller.coach != null || controller.coachThinking);
    Widget? coach({double? fit}) => showCoach
        ? CoachList(
            answer: controller.coach,
            strings: scaffold.strings,
            look: scaffold.coachLook,
            fitHeight: fit,
            dense: compact,
            thinking: controller.coachThinking,
            canThinkLonger: controller.canThinkLonger,
            onThinkLonger: compact ? null : controller.thinkLonger,
          )
        : null;
    final buttons = controller.isOver
        ? Padding(
            padding: const EdgeInsets.all(8),
            child: FilledButton(
              key: const ValueKey('again'),
              onPressed: scaffold._again,
              child: Text(
                controller.between
                    ? k.nextDeal
                    : controller.matchOver
                        ? k.newMatch
                        : scaffold.newGameLabel ?? s.newGame,
              ),
            ),
          )
        : controller.preparing
            // Greyed out, not hidden, until the game is ready.
            ? IgnorePointer(child: ExcludeFocus(child: Opacity(opacity: 0.38, child: scaffold.panel)))
            : scaffold.panel;
    // The compact panel has no room for Think longer under the moves.
    final thinkIcon = compact && showCoach
        ? ThinkLongerButton(
            enabled: controller.canThinkLonger,
            onPressed: controller.thinkLonger,
            label: k.thinkLonger,
            iconOnly: true,
          )
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(10, compact ? 4 : 8, 10, compact ? 2 : 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              LayoutBuilder(
                // Compact: the second line follows the first on its row; the
                // first ("Your turn", "Ana…", "You win") is short and keeps
                // its whole width.
                builder: (context, constraints) => Row(
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: constraints.maxWidth * (compact ? 0.6 : 1)),
                      child: Text(
                        _headline(context),
                        key: const ValueKey('status'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (compact && second.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(child: _secondLine(second, onTap: scores)),
                    ] else if (thinkIcon != null)
                      const Spacer(),
                    ?thinkIcon,
                  ],
                ),
              ),
              if (!compact && second.isNotEmpty) _secondLine(second, onTap: scores),
              // Compact: the last grade folds into the status line.
              if (compact && mark != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: MoveFeedback(
                    mark: mark,
                    unit: unit,
                    strings: scaffold.strings,
                    look: scaffold.look,
                    inline: true,
                    moveIndex: markIndex,
                  ),
                ),
            ],
          ),
        ),
        if (!compact && mark != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: MoveFeedback(
              mark: mark,
              unit: unit,
              strings: scaffold.strings,
              look: scaffold.look,
              moveIndex: markIndex,
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, area) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (controller.preparing) const LinearProgressIndicator(minHeight: 2),
                  // Compact: as many moves as fit without scrolling, 3 to 5
                  // (5 in a board game's panel on a 592x360 phone; fewer with
                  // reason lines), the listed ones (Pass) always among them.
                  ?coach(fit: compact ? area.maxHeight : null),
                  // Between deals (and at the end of the match): the scores.
                  if (controller.isOver && controller.match != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: MatchTable(
                        key: const ValueKey('panel scores'),
                        match: controller.match!,
                        names: [for (var i = 0; i < controller.match!.seats; i++) controller.seatName(i)],
                        humans: {
                          for (var i = 0; i < controller.match!.seats; i++)
                            if (controller.isHuman(i)) i,
                        },
                        over: controller.matchOver,
                        compact: true,
                      ),
                    ),
                  ...scaffold.coachExtras,
                ],
              ),
            ),
          ),
        ),
        buttons,
      ],
    );
  }

  static Widget _secondLine(String text, {VoidCallback? onTap}) {
    final line = Text(
      text,
      key: const ValueKey('status 2'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: Color(0xFFFFE082), fontSize: 13),
    );
    if (onTap == null) return line;
    // The match's line opens the scoreboard: lit, with the hand, under the mouse.
    return InkWell(
      key: const ValueKey('open scores'),
      borderRadius: BorderRadius.circular(4),
      mouseCursor: WidgetStateMouseCursor.clickable,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: line),
          const Padding(
            padding: EdgeInsets.only(left: 3),
            child: Icon(Icons.leaderboard_outlined, size: 14, color: Color(0xFFFFE082)),
          ),
        ],
      ),
    );
  }

  /// The game's own words, else "Your turn", "Ana…", or the result.
  String _headline(BuildContext context) {
    final controller = scaffold.controller;
    final k = KitStrings.of(context);
    // The match's end says who won it, over any deal's words; a shared best
    // total is a tie, never an outright win.
    if (controller.matchOver) {
      final won = controller.match!.leaders;
      if (won.length > 1) return k.matchTie([for (final s in won) controller.seatName(s)]);
      if (won.any(controller.isHuman)) return k.youWinMatch;
      if (won.isNotEmpty) return k.winsMatch(controller.seatName(won.single));
    }
    if (scaffold.headline?.call(context) case final words?) return words;
    if (controller.isOver) {
      final winners = controller.winners;
      if (winners.isEmpty) return k.draw;
      if (winners.any(controller.isHuman)) return k.youWin;
      if (winners.length == 1) return k.wins(controller.seatName(winners.single));
      return k.youLose;
    }
    final seat = controller.preparing ? null : controller.seatToAct;
    if (seat == null) return '';
    if (controller.isHuman(seat)) return k.yourTurn;
    return S.of(context).thinking(controller.seatName(seat));
  }
}
