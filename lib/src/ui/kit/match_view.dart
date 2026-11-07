import 'package:flutter/material.dart';

import '../../kit/match.dart';
import 'help.dart';
import 'kit_sheet.dart';
import 'l10n/game_strings.dart';
import 'l10n/kit_strings.dart';
import 'setup_kit.dart';
import 'turn_controller.dart';

/// The setup's match choice: "Play to" with the game's [choices] (the
/// standard one first chosen by the game) and No limit, then "Scale with
/// players" (greyed out under No limit), with "?".
class MatchTargetRow extends StatelessWidget {
  const MatchTargetRow({
    super.key,
    required this.value,
    required this.choices,
    required this.onChanged,
    this.terms = const [],
    this.enabled = true,
  });

  final MatchTarget value;

  /// The targets offered, smallest first (Big Two: 50, 100, 150, 200).
  final List<int> choices;
  final ValueChanged<MatchTarget> onChanged;

  /// More "?" entries after the kit's (the game's own scoring rules).
  final List<GameTerm> terms;

  /// Off: the choices and the switch greyed out (a guest sees the host's
  /// match), the "?" still there to read.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final k = KitStrings.of(context);
    return SetupSection(
      label: k.playTo,
      help: TermsHelpButton(title: k.playTo, terms: [k.entry(KitTerm.playTo), ...terms]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ChoiceRow<int?>(
            key: const ValueKey('play to'),
            values: [...choices, null],
            selected: value.points,
            label: (points) => points == null ? k.noLimit : '$points',
            enabled: (_) => enabled,
            onChanged: (points) => onChanged(value.copyWith(points: () => points)),
          ),
          const SizedBox(height: 4),
          SwitchRow(
            key: const ValueKey('scale with players'),
            label: k.scaleWithPlayers,
            value: value.scale,
            enabled: enabled && value.points != null,
            onChanged: (scale) => onChanged(value.copyWith(scale: scale)),
          ),
        ],
      ),
    );
  }
}

/// The match on one line for the panel's status: "Deal 3 · You 12 · To
/// 100"; [compact] (a sideways phone's narrow panel), without the deal's
/// number, so the target still fits: "You 12 · To 100". Null without a
/// match.
String? matchStatus(BuildContext context, TurnController c, {bool compact = false}) {
  final match = c.match;
  if (match == null) return null;
  final k = KitStrings.of(context);
  final you = [
    for (var s = 0; s < match.seats; s++)
      if (c.isHuman(s)) s,
  ].firstOrNull;
  // The deal on the table: the one being played, or the one just over.
  final deal = match.deals.length + (c.isOver ? 0 : 1);
  return [
    if (!compact) k.dealNumber(deal < 1 ? 1 : deal),
    if (you != null) '${c.seatName(you)} ${totalText(match.totals[you])}',
    k.target(match.target),
  ].join(' · ');
}

/// Opens the scoreboard: every deal's points, the totals, the target.
Future<void> showScoreboard(BuildContext context, TurnController c) {
  final match = c.match;
  if (match == null) return Future.value();
  return KitSheet.open(context, _ScoreboardSheet(controller: c));
}

class _ScoreboardSheet extends StatelessWidget {
  const _ScoreboardSheet({required this.controller});

  final TurnController controller;

  @override
  Widget build(BuildContext context) {
    final k = KitStrings.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final match = controller.match;
        if (match == null) return const SizedBox.shrink();
        return KitSheet(
          key: const ValueKey('scoreboard'),
          title: '${k.scores} · ${k.target(match.target)}',
          help: TermsHelpButton(title: k.playTo, terms: [k.entry(KitTerm.playTo)]),
          child: MatchTable(
            match: match,
            names: [for (var s = 0; s < match.seats; s++) controller.seatName(s)],
            humans: {
              for (var s = 0; s < match.seats; s++)
                if (controller.isHuman(s)) s,
            },
            over: controller.matchOver,
          ),
        );
      },
    );
  }
}

/// A deal's points with their sign ("+6", "−3", "0").
String dealText(int points) => points > 0 ? '+$points' : (points < 0 ? '−${-points}' : '0');

/// A total, with a real minus when below zero.
String totalText(int points) => points < 0 ? '−${-points}' : '$points';

/// The scoreboard: the seats from first place to last, each with every
/// deal's points (the latest on the right, scrolling sideways when they
/// don't fit) and the total; the leaders' totals in gold, with a trophy
/// once the match is [over]. [compact]: only the last deal and the total
/// (the panel between deals).
class MatchTable extends StatelessWidget {
  const MatchTable({
    super.key,
    required this.match,
    required this.names,
    this.humans = const {},
    this.over = false,
    this.compact = false,
  });

  final MatchScore match;
  final List<String> names;

  /// The player's seats (their names in bold).
  final Set<int> humans;
  final bool over;
  final bool compact;

  static const _gold = Color(0xFFFFD54F);
  static const _numbers = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

  @override
  Widget build(BuildContext context) {
    final k = KitStrings.of(context);
    final order = match.standings;
    final leaders = match.leaders.toSet();
    final rowHeight = compact ? 24.0 : 28.0;
    final deals = match.deals;
    Widget cell(String text, {double? width, TextStyle? style, Alignment align = Alignment.centerRight, Key? key}) =>
        SizedBox(
          key: key,
          width: width,
          height: rowHeight,
          child: Align(
            alignment: align,
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: _numbers.merge(style)),
          ),
        );
    const head = TextStyle(fontSize: 11, color: Colors.white54);
    // Left: place and name; middle: the deals; right: the total.
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        cell('', align: Alignment.centerLeft),
        for (final s in order)
          SizedBox(
            height: rowHeight,
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: over && leaders.contains(s)
                      ? const Icon(Icons.emoji_events, size: 16, color: _gold, key: ValueKey('match winner'))
                      : Text('${match.placeOf(s)}', style: head.copyWith(fontSize: 12)),
                ),
                Flexible(
                  child: Text(
                    names[s],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: humans.contains(s) ? FontWeight.w700 : FontWeight.w400),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    final dealWidth = compact ? 70.0 : 34.0;
    final shownDeals = compact
        ? (deals.isEmpty ? <int>[] : [deals.length - 1])
        : [for (var d = 0; d < deals.length; d++) d];
    final middle = Row(
      children: [
        for (final d in shownDeals)
          Column(
            children: [
              cell(compact ? k.dealNumber(d + 1) : '${d + 1}', width: dealWidth, style: head),
              for (final s in order)
                cell(
                  dealText(deals[d][s]),
                  width: dealWidth,
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                ),
            ],
          ),
      ],
    );
    final right = Column(
      children: [
        cell(k.total, width: 56, style: head),
        for (final s in order)
          cell(
            totalText(match.totals[s]),
            key: ValueKey('total $s'),
            width: 56,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: leaders.contains(s) ? _gold : null),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // The names keep at least 90 px; the deals take what they need of
        // the rest and scroll when they don't fit; the totals keep the right edge.
        final room = (constraints.maxWidth - 90 - 56).clamp(0.0, double.infinity);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            SizedBox(
              width: (dealWidth * shownDeals.length).clamp(0.0, room),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                // The latest deal in sight: the list starts from its right end.
                reverse: true,
                child: middle,
              ),
            ),
            right,
          ],
        );
      },
    );
  }
}
