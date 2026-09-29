import 'package:flutter/material.dart';

import '../app/app_settings.dart';
import '../engine/cards.dart';
import '../game/table_session.dart';
import '../l10n/strings.dart';
import 'format.dart';
import 'strategy_panel.dart';
import 'widgets/card_view.dart' show SuitIcon;

/// Every scored hand of the session, newest first, each expandable into its
/// individual decisions.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.session});

  final TableSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hands = session.history.where((h) => h.decisions.isNotEmpty).toList().reversed.toList();
    final scores = session.points.toList();
    final muted = theme.textTheme.bodySmall?.copyWith(color: Colors.white60);
    final s = S.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(s.history)),
      body: hands.isEmpty
          ? Center(child: Text(s.noScoresYet))
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Wrap(
                          spacing: 28,
                          runSpacing: 8,
                          children: [
                            _stat(theme, s.decisions, '${scores.length}'),
                            _stat(
                              theme,
                              s.averageScore,
                              scores.isEmpty
                                  ? '–'
                                  : (scores.fold(0, (sum, p) => sum + p) / scores.length).toStringAsFixed(0),
                            ),
                            // Every decision loses EV, scored or not.
                            _stat(theme, s.evLoss,
                                '${session.history.fold(0.0, (sum, h) => sum + h.evLost).toStringAsFixed(2)} BB'),
                            _stat(theme, s.net, formatSignedBb(session.heroNet)),
                          ],
                        ),
                      ),
                    ),
                    for (final hand in hands)
                      Card(
                        child: ExpansionTile(
                          title: Row(
                            children: [
                              Text(s.handNumber(hand.handNumber), style: theme.textTheme.titleSmall),
                              const SizedBox(width: 10),
                              MiniCards(cards: hand.holeCards),
                              const SizedBox(width: 8),
                              Text(hand.position.label, style: muted),
                            ],
                          ),
                          subtitle: Text(
                            '${hand.advanced ? s.advanced : s.simple} · '
                            '${s.score(hand.averageScore!.round())} · '
                            '${s.evLoss} ${hand.evLost.toStringAsFixed(2)} BB'
                            '${hand.result == null ? '' : ' · ${formatSignedBb(hand.result!)}'}',
                            style: muted,
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          children: [
                            for (final d in hand.decisions) DecisionView(record: d),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _stat(ThemeData theme, String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60)),
          Text(value, style: theme.textTheme.titleMedium),
        ],
      );
}

/// Color for a score from 0 to 100, matching the grades.
Color scoreColor(double score) => score >= 85
    ? const Color(0xFF2E7D32)
    : score >= 65
        ? const Color(0xFF558B2F)
        : score >= 45
            ? const Color(0xFFF9A825)
            : score >= 25
                ? const Color(0xFFEF6C00)
                : const Color(0xFFC62828);

/// Always shown at the table (Guess the GTO mode): the average score, then
/// the last scored hands as squares, newest on the right (as many as fit,
/// up to 10). Tap a square for that hand's decisions, or "All" for the
/// full history.
class RecentScores extends StatelessWidget {
  const RecentScores({super.key, required this.session});

  final TableSession session;

  static const _box = 30.0, _gap = 4.0;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60);
    final scored = session.history.where((h) => h.decisions.isNotEmpty).toList();
    final scores = session.points.toList();
    final average = scores.isEmpty ? null : scores.fold(0, (sum, p) => sum + p) / scores.length;
    return Container(
      height: 42,
      color: const Color(0xFF0E1316),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Text(S.of(context).average, style: muted),
          const SizedBox(width: 6),
          _ScoreBox(score: average, size: _box),
          const SizedBox(width: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final fit = ((constraints.maxWidth + _gap) / (_box + _gap)).floor().clamp(0, 10);
                final shown = scored.sublist(scored.length - fit.clamp(0, scored.length));
                return Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (final hand in shown)
                      Padding(
                        padding: const EdgeInsets.only(left: _gap),
                        child: _ScoreBox(
                          score: hand.averageScore,
                          advanced: hand.advanced,
                          size: _box,
                          onTap: () => showDialog<void>(
                            context: context,
                            builder: (_) => HandDetailsDialog(hand: hand),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => HistoryScreen(session: session)),
            ),
            child: Text(S.of(context).all),
          ),
        ],
      ),
    );
  }
}

/// One score in a colored square ("–" before there is one).
class _ScoreBox extends StatelessWidget {
  const _ScoreBox({required this.score, required this.size, this.onTap, this.advanced = false});

  final double? score;

  /// A hand played in advanced training: outlined in white.
  final bool advanced;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = score;
    return Material(
      color: s == null ? Colors.white12 : scoreColor(s),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(5),
        side: advanced ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Text(
              s == null ? '–' : '${s.round()}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }
}

/// One hand's scored decisions, in a dialog.
class HandDetailsDialog extends StatelessWidget {
  const HandDetailsDialog({super.key, required this.hand});

  final HandRecord hand;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AlertDialog(
      title: Row(
        children: [
          Text('${s.handNumber(hand.handNumber)}  '),
          MiniCards(cards: hand.holeCards),
          Text('  ${hand.position.label}', style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [for (final d in hand.decisions) DecisionView(record: d)],
          ),
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.close))],
    );
  }
}

class DecisionView extends StatelessWidget {
  const DecisionView({super.key, required this.record});

  final DecisionRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(s.street(record.street), style: theme.textTheme.labelLarge),
              const SizedBox(width: 8),
              if (record.board.isNotEmpty) MiniCards(cards: record.board),
              const Spacer(),
              Text('${s.score(record.points)}  '),
              GradeChip(grade: record.score.grade),
            ],
          ),
          const SizedBox(height: 6),
          StrategyComparison(spot: record.spot, mix: record.mix, played: record.played),
          const Divider(height: 20),
        ],
      ),
    );
  }
}

/// Cards written small, like "A♠ K♦", with drawn suit symbols.
class MiniCards extends StatelessWidget {
  const MiniCards({super.key, required this.cards});

  final List<PlayingCard> cards;

  @override
  Widget build(BuildContext context) {
    final style = AppSettings.of(context).cardFaces;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final card in cards)
          Container(
            margin: const EdgeInsets.only(right: 3),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(color: style.face(card.suit), borderRadius: BorderRadius.circular(3)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  card.rankLabel,
                  style: TextStyle(
                    color: style.ink(card.suit),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                SuitIcon(
                  suit: card.suit,
                  size: 10,
                  color: style.ink(card.suit),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
