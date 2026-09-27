import 'dart:math';

import 'package:flutter/material.dart';

import '../engine/events.dart';
import '../game/table_session.dart';
import '../gto/hand_classes.dart';
import '../gto/range_info.dart';
import '../l10n/strings.dart';
import 'glossary.dart';

/// One player's range at a time, sized to fit the screen: an opponent's
/// (as far as you can tell) or your own (as your opponents see it),
/// assuming everyone has played GTO so far.
class RangeScreen extends StatefulWidget {
  const RangeScreen({super.key, required this.session, this.only});

  final TableSession session;

  /// Show just this seat's range.
  final int? only;

  @override
  State<RangeScreen> createState() => _RangeScreenState();
}

class _RangeScreenState extends State<RangeScreen> {
  bool _share = false;
  int? _seat;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final hand = session.hand;
    final s = S.of(context);
    final only = widget.only;
    final seats = hand == null
        ? <int>[]
        : only != null
        ? [only]
        : [
            for (var s = 0; s < hand.playerCount; s++)
              if (s != TableSession.heroSeat && !hand.isFolded(s)) s,
            TableSession.heroSeat,
          ];
    final seat = seats.contains(_seat) ? _seat! : (seats.isEmpty ? null : seats.first);
    String name(int seat) => seat == TableSession.heroSeat ? s.you : session.players[seat].name;

    final range = seat == null ? null : session.rangeOf(seat);
    final Widget grid = range == null
        ? Center(child: Text(s.noRange))
        : RangeGrid(range: range, share: _share, highlight: seat == null ? null : _knownHand(seat));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          only == null
              ? s.ranges
              : only == TableSession.heroSeat
              ? s.yourRange
              : name(only),
        ),
        actions: const [
          HelpButton(section: GlossarySection.strategy, terms: [GlossaryTerm.range, GlossaryTerm.rangeGrid]),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // On top: the range / frequency toggle, and whose range (when showing everyone's).
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(value: false, label: Text(s.frequency)),
                      ButtonSegment(value: true, label: Text(s.shareOfRange)),
                    ],
                    selected: {_share},
                    showSelectedIcon: false,
                    onSelectionChanged: (v) => setState(() => _share = v.single),
                  ),
                  if (only == null && seats.length > 1)
                    for (final other in seats)
                      ChoiceChip(
                        label: Text(name(other)),
                        selected: other == seat,
                        onSelected: (_) => setState(() => _seat = other),
                      ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(child: grid),
            ],
          ),
        ),
      ),
    );
  }

  /// The starting hand [seat] holds, when the user can see it: their own,
  /// or an opponent's that is shown (face up in training, or at showdown).
  int? _knownHand(int seat) {
    final session = widget.session, hand = session.hand;
    if (hand == null) return null;
    final shown = seat == TableSession.heroSeat ||
        session.revealedSeats.contains(seat) ||
        hand.log.any((e) => e is HandsRevealed && e.cards.containsKey(seat));
    if (!shown) return null;
    final cards = hand.holeCards(seat);
    return handClassOf(cards[0], cards[1]);
  }
}

/// All 169 starting hands in a 13 x 13 grid (aces top left, suited hands
/// above the diagonal), each cell brighter the more it is in the range. As
/// big as fits in the space given.
class RangeGrid extends StatelessWidget {
  const RangeGrid({super.key, required this.range, required this.share, this.highlight});

  final RangeInfo range;

  /// A starting hand (0-168) to outline: the one the player really holds.
  final int? highlight;

  /// Show each hand's share of the range instead of how often it plays this way.
  final bool share;

  @override
  Widget build(BuildContext context) {
    var maxShare = 0.0;
    if (share) {
      for (var h = 0; h < handClassCount; h++) {
        final s = range.shareOf(h);
        if (s > maxShare) maxShare = s;
      }
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxHeight.isFinite
            ? (constraints.maxWidth < constraints.maxHeight ? constraints.maxWidth : constraints.maxHeight)
            : constraints.maxWidth;
        final cell = (side / 13 - 1).clamp(10.0, 60.0);
        return Align(
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var row = 0; row < 13; row++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [for (var col = 0; col < 13; col++) _cell(row, col, cell, maxShare)],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _cell(int row, int col, double size, double maxShare) {
    final rowRank = 12 - row, colRank = 12 - col;
    final h = row == col
        ? handClassIndex(rowRank, rowRank, suited: false)
        : handClassIndex(rowRank, colRank, suited: col > row);
    final value = share ? (maxShare == 0 ? 0.0 : range.shareOf(h) / maxShare) : range.frequency[h];
    final label = share
        ? '${(range.shareOf(h) * 100).toStringAsFixed(range.shareOf(h) >= 0.1 ? 0 : 1)}%'
        : '${(range.frequency[h] * 100).round()}%';
    final color = Color.lerp(const Color(0xFF20262A), const Color(0xFF2E9D57), value.clamp(0.0, 1.0))!;
    final held = h == highlight;
    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.all(0.5),
      alignment: Alignment.center,
      // The hand the player really holds: outlined in gold.
      decoration: BoxDecoration(
        color: color,
        border: held ? Border.all(color: const Color(0xFFFFC107), width: max(2, size * 0.08)) : null,
        boxShadow: held ? const [BoxShadow(color: Color(0xAAFFC107), blurRadius: 8)] : null,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(1),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                handClassName(h),
                style: TextStyle(fontSize: size * 0.3, fontWeight: FontWeight.w700, height: 1.1),
              ),
              if (size >= 30)
                Text(
                  label,
                  style: TextStyle(fontSize: size * 0.22, color: Colors.white70, height: 1.1),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
