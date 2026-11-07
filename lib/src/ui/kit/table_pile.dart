import 'dart:math';

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import 'card_flights.dart';
import 'cards.dart';
import 'l10n/kit_strings.dart';

/// One turn of a deal, for the pile and its history: a seat's play, its
/// pass, or a turn with only words (Fight the Landlord's bids).
@immutable
class PilePlay {
  const PilePlay({
    required this.seat,
    this.cards = const [],
    this.pass = false,
    this.label,
    this.trick = 0,
    this.heading,
  });

  final int seat;

  /// The cards played; empty for a pass or a turn of words.
  final List<CardFace> cards;
  final bool pass;

  /// The play's kind ("Pair", "Straight"), or a turn's words ("Bid 2").
  final String? label;

  /// The trick it belongs to, counted from 0: the history marks where each
  /// begins.
  final int trick;

  /// The history's heading over this turn's group, in place of "Trick n":
  /// turns that are not a trick (Fight the Landlord's bids: "Bidding") get
  /// a heading of their own. A new heading starts wherever the trick or
  /// this changes.
  final String? heading;

  bool get hasCards => cards.isNotEmpty;
}

/// The middle of a card table: the plays of the deal piled up a little
/// messily, as cards land on a real table. Each play lies at a small offset
/// and tilt of its own (seeded by its place in the deal, so it never moves
/// on a redraw), so the earlier plays stay in sight underneath, darker; the
/// latest lies on top, bright and lit: the play to beat. Under the pile, the
/// latest play's kind and who made it ("Pair · Ana").
///
/// Tapping the pile opens the deal's history ([PileHistory]): every play
/// and pass in order. Before the first card is played but after a turn of
/// words (a bid), the middle is an empty spot that opens the history all
/// the same, so who bid what can be checked during the auction.
///
/// Each card of play i is a flight place ([flightTag]): a game flies a play
/// to `TablePile.flightTag(i, k)` (i its index in [plays], k the card's in
/// the play), and the play shows when its cards land.
class TablePile extends StatefulWidget {
  const TablePile({
    super.key,
    required this.plays,
    required this.names,
    this.cardWidth = 44,
    this.toBeat = true,
    this.shown = 6,
    this.passLabel,
    this.seed = 0,
    this.onTap,
    this.showLabel = true,
  });

  /// Every turn of the deal so far, in order (passes and words included:
  /// the history shows them; the pile draws only the plays).
  final List<PilePlay> plays;

  /// Each seat's name (the player's own is "Player").
  final List<String> names;
  final double cardWidth;

  /// The latest play is the one to beat (lit); false once everyone else has
  /// passed on it (its maker leads next), when it is darkened like the rest.
  final bool toBeat;

  /// How many plays the pile keeps in sight (the latest and those under it).
  final int shown;

  /// The game's word for a pass in the history (null: the kit's "Pass").
  final String? passLabel;

  /// Another deal's pile lies differently (the deal's seed).
  final int seed;

  /// What a tap does (null: opens the history).
  final VoidCallback? onTap;

  /// Whether the words under the pile show ("Pair · Kai"). A felt with
  /// room only for the cards (the end of a deal on a sideways phone, every
  /// hand face up round the pile) leaves them out: the history says them.
  final bool showLabel;

  /// The flight tag of card [card] of play [play].
  static Object flightTag(int play, int card) => ('pile', play, card);

  /// How far each play strays from the middle, as shares of a card's width
  /// (sideways, up or down), and how much it may turn (radians: 10°):
  /// enough for the plays under a five-card one to peek out.
  static const strayX = 0.7, strayY = 0.32, maxTurn = 0.18;

  /// Where play [index] lies: its offset from the pile's middle and its
  /// tilt, the same every time for the same deal. Each play strays the
  /// golden angle (137.5°) round from the one before, give or take a
  /// little, so a play rarely lands right on the one under it and both
  /// stay in sight.
  static ({Offset offset, double angle}) mess(int index, double cardWidth, {int seed = 0}) {
    final random = Random((seed * 7919 + index * 104729 + 17) & 0x7fffffff);
    double next() => random.nextDouble() * 2 - 1;
    final direction = index * 2.39996 + seed + next() * 0.4;
    final reach = 0.65 + 0.35 * random.nextDouble();
    return (
      offset: Offset(cos(direction) * strayX * reach * cardWidth, sin(direction) * strayY * reach * cardWidth),
      angle: next() * maxTurn,
    );
  }

  /// Opens the deal's history over the screen.
  static Future<void> showHistory(
    BuildContext context, {
    required List<PilePlay> plays,
    required List<String> names,
    String? passLabel,
  }) => showDialog<void>(
    context: context,
    builder: (_) => PileHistory(plays: plays, names: names, passLabel: passLabel),
  );

  @override
  State<TablePile> createState() => _TablePileState();
}

class _TablePileState extends State<TablePile> {
  var _hovered = false;

  /// The room under the pile for the latest play's words.
  static const _labelHeight = 18.0;

  @override
  Widget build(BuildContext context) {
    final plays = widget.plays;
    final onTable = [
      for (var i = 0; i < plays.length; i++)
        if (plays[i].hasCards) i,
    ];
    if (onTable.isEmpty) {
      if (plays.isEmpty) return const SizedBox.shrink();
      // Only words so far: an empty spot, a card's size, to tap.
      final cw = widget.cardWidth;
      return _tappable(context, Size(cw * 2, cw * cardAspectRatio), const SizedBox.expand());
    }
    final shown = onTable.sublist(max(0, onTable.length - widget.shown));
    final latest = shown.last;
    final cw = widget.cardWidth, ch = cw * cardAspectRatio;
    final most = shown.map((i) => plays[i].cards.length).reduce(max);
    final labelHeight = widget.showLabel ? _labelHeight : 0.0;
    final natural = Size(
      cw * (1 + 0.5 * (most - 1)) + 2 * TablePile.strayX * cw + cw * 0.4,
      ch + 2 * TablePile.strayY * cw + ch * 0.2 + labelHeight,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.constrain(natural);
        final middle = Offset(size.width / 2, (size.height - labelHeight) / 2);
        // A pile given less room than it would take strays less.
        final squeeze = Offset(
          (size.width / natural.width).clamp(0.3, 1.0),
          (size.height / natural.height).clamp(0.3, 1.0),
        );
        final flights = CardFlights.maybeOf(context);
        // A long play (a Fight the Landlord airplane) overlaps more to fit.
        double step(int n) => n <= 1
            ? 0
            : (min(
                cw * 0.5,
                (size.width - cw - 2 * TablePile.strayX * cw * squeeze.dx) / (n - 1),
              )).clamp(cw * 0.12, cw * 0.5);
        Widget play(int i) {
          final cards = plays[i].cards;
          final s = step(cards.length);
          final width = cw + s * (cards.length - 1);
          final (offset: stray, :angle) = TablePile.mess(i, cw, seed: widget.seed);
          final offset = Offset(stray.dx * squeeze.dx, stray.dy * squeeze.dy);
          final top = i == latest;
          Widget group = SizedBox(
            width: width,
            height: ch,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var k = 0; k < cards.length; k++)
                  Positioned(
                    left: k * s,
                    child: GameCardView(width: cw, face: cards[k], flightTag: TablePile.flightTag(i, k)),
                  ),
              ],
            ),
          );
          if (!top || !widget.toBeat) {
            // Darker, not see-through: the cards under it don't show through.
            group = ColorFiltered(
              colorFilter: ColorFilter.mode(
                top ? const Color(0xFFB8B8B8) : const Color(0xFF8A8A8A),
                BlendMode.modulate,
              ),
              child: group,
            );
          } else {
            // The play to beat: a warm glow round it, once its cards are
            // down (not round their empty places while they fly in).
            final bare = group;
            Widget glow(bool lit) => DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(cw * 0.12),
                boxShadow: lit ? const [BoxShadow(color: Color(0x80FFE082), blurRadius: 10, spreadRadius: 1)] : null,
              ),
              child: bare,
            );
            group = flights == null
                ? glow(true)
                : ListenableBuilder(
                    listenable: flights,
                    builder: (context, _) => glow(!flights.isLanding(TablePile.flightTag(i, 0))),
                  );
          }
          return Positioned(
            key: ValueKey('pile play $i'),
            left: middle.dx + offset.dx - width / 2,
            top: middle.dy + offset.dy - ch / 2,
            child: Transform.rotate(angle: angle, child: group),
          );
        }

        final last = plays[latest];
        final name = last.seat < widget.names.length ? widget.names[last.seat] : '';
        final words = [?last.label, name].where((w) => w.isNotEmpty).join(' · ');
        Widget label = Text(
          words,
          key: const ValueKey('pile label'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: widget.toBeat ? Colors.white : Colors.white60),
        );
        // The words wait for the cards they name.
        if (flights != null) {
          label = ListenableBuilder(
            listenable: flights,
            builder: (context, child) =>
                Opacity(opacity: flights.isLanding(TablePile.flightTag(latest, 0)) ? 0 : 1, child: child),
            child: label,
          );
        }
        return _tappable(
          context,
          size,
          Stack(
            clipBehavior: Clip.none,
            children: [
              for (final i in shown) play(i),
              // The words may run a little past a narrow pile.
              if (widget.showLabel)
                Positioned(left: -cw, right: -cw, bottom: 0, height: _labelHeight, child: Center(child: label)),
            ],
          ),
        );
      },
    );
  }

  /// The pile's spot, [size] big, holding [child]: lit under the mouse
  /// with a hand cursor, and a tap opens the history.
  Widget _tappable(BuildContext context, Size size, Widget child) {
    return Semantics(
      button: true,
      label: S.of(context).history,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          key: const ValueKey('pile'),
          behavior: HitTestBehavior.opaque,
          onTap:
              widget.onTap ??
              () => TablePile.showHistory(
                context,
                plays: widget.plays,
                names: widget.names,
                passLabel: widget.passLabel,
              ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: size.width,
            height: size.height,
            decoration: BoxDecoration(
              color: _hovered ? Colors.white.withValues(alpha: 0.07) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _hovered ? Colors.white24 : Colors.transparent),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The deal's history: every turn in order, each with the seat's name and
/// its cards drawn small (or its pass, or its words), under a heading where
/// each trick begins ("Trick n", or the turn's own [PilePlay.heading]). The newest is at the bottom, in sight when it opens.
/// Closed by ✕, Esc, or a tap outside.
class PileHistory extends StatelessWidget {
  const PileHistory({super.key, required this.plays, required this.names, this.passLabel});

  final List<PilePlay> plays;
  final List<String> names;
  final String? passLabel;

  /// The cards' width in the history.
  static const cardWidth = 22.0;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final k = KitStrings.of(context);
    final rows = <Widget>[];
    for (var i = 0; i < plays.length; i++) {
      final turn = plays[i];
      final before = i == 0 ? null : plays[i - 1];
      if (before == null || turn.trick != before.trick || turn.heading != before.heading) {
        rows.add(_TrickHeading(turn.heading ?? k.trick(turn.trick + 1)));
      }
      rows.add(
        _Turn(
          key: ValueKey('history $i'),
          name: turn.seat < names.length ? names[turn.seat] : '',
          turn: turn,
          passLabel: passLabel ?? k.pass,
        ),
      );
    }
    return Dialog(
      key: const ValueKey('pile history'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      backgroundColor: const Color(0xFF161C21),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.history,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Semantics(
                    label: s.close,
                    child: IconButton(
                      key: const ValueKey('close history'),
                      icon: const Icon(Icons.close),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              // Upside down, so it opens at the newest turn.
              child: ListView(
                reverse: true,
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: rows.reversed.toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrickHeading extends StatelessWidget {
  const _TrickHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      child: Row(
        children: [
          Text(
            text,
            style: const TextStyle(fontSize: 11, color: Color(0xFFFFE082), fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          const Expanded(child: Divider(height: 1, color: Colors.white24)),
        ],
      ),
    );
  }
}

/// One turn: the name, then the cards small and the play's kind, or the
/// pass, or the turn's words.
class _Turn extends StatelessWidget {
  const _Turn({super.key, required this.name, required this.turn, required this.passLabel});

  final String name;
  final PilePlay turn;
  final String passLabel;

  @override
  Widget build(BuildContext context) {
    const cw = PileHistory.cardWidth;
    final cards = turn.cards;
    final quiet = const TextStyle(fontSize: 13, color: Colors.white60);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: SizedBox(
        height: cw * cardAspectRatio + 2,
        child: Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            if (cards.isNotEmpty) ...[
              // As wide as the cards (smaller if the row is too narrow), the
              // play's kind right after them.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: cw + cw * 0.5 * (cards.length - 1),
                    height: cw * cardAspectRatio,
                    child: Stack(
                      children: [
                        for (var k = 0; k < cards.length; k++)
                          Positioned(
                            left: k * cw * 0.5,
                            child: GameCardView(width: cw, face: cards[k]),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (turn.label case final label?) ...[
                const SizedBox(width: 8),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: quiet.copyWith(fontSize: 12)),
              ],
            ] else
              Expanded(
                child: Text(
                  turn.pass ? passLabel : turn.label ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: turn.pass ? quiet.copyWith(fontStyle: FontStyle.italic) : quiet,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
