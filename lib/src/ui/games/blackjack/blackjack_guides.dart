import 'package:flutter/material.dart';

import '../../../games/blackjack/app/blackjack_jobs.dart';
import '../../../games/blackjack/app/blackjack_record.dart';
import '../../../games/blackjack/blackjack.dart';
import '../../../kit/game_keys.dart';
import '../../../kit/jobs/jobs.dart';
import '../../../kit/jobs/jobs_core.dart';
import '../../../l10n/strings.dart';
import '../../kit/guide_kit.dart';
import '../../kit/help.dart';
import '../../kit/kit_scope.dart';
import 'l10n/blackjack_strings.dart';

/// Guides > Rules (also ☰ Rules in a game).
class BlackjackRulesGuide extends StatelessWidget {
  const BlackjackRulesGuide({super.key});

  @override
  Widget build(BuildContext context) =>
      GuidePage(title: S.of(context).rules, sections: BlackjackStrings.of(context).rulesSections);
}

/// The colour of a chart cell, and its letters' colour: red to hit, gold to
/// stand, blue to double (light blue: else stand), green to split, grey to
/// surrender.
(Color, Color) chartColors(ChartCode code) => switch (code) {
  ChartCode.hit => (const Color(0xFFC62828), Colors.white),
  ChartCode.stand => (const Color(0xFFFBC02D), Colors.black),
  ChartCode.doubleOrHit => (const Color(0xFF1565C0), Colors.white),
  ChartCode.doubleOrStand => (const Color(0xFF64B5F6), Colors.black),
  ChartCode.split => (const Color(0xFF2E7D32), Colors.white),
  ChartCode.surrenderOrHit => (const Color(0xFF9E9E9E), Colors.black),
  ChartCode.surrenderOrStand => (const Color(0xFFBDBDBD), Colors.black),
  ChartCode.surrenderOrSplit => (const Color(0xFF757575), Colors.white),
};

/// Guides > Basic strategy: the chart for a table's rules, made by the
/// `blackjack.chart` job (about a second; a bar runs meanwhile). The rules
/// bar on top starts at the last game's rules (Standard before any game);
/// changing a rule makes that table's chart. Hard totals, soft totals and
/// pairs against the dealer's 2 to ace, in coloured cells with the letters
/// of the player's language, then the legend.
class BlackjackStrategyGuide extends StatefulWidget {
  const BlackjackStrategyGuide({super.key, this.rules});

  /// The rules to show first (null: the last game's, or Standard).
  final BlackjackRules? rules;

  @override
  State<BlackjackStrategyGuide> createState() => _BlackjackStrategyGuideState();
}

class _BlackjackStrategyGuideState extends State<BlackjackStrategyGuide> {
  late final Jobs _jobs;
  BlackjackRules? _rules;
  BasicStrategyChart? _chart;
  JobHandle<BasicStrategyChart>? _job;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    final scope = KitScope.of(context);
    _jobs = scope.newJobs();
    if (widget.rules case final rules?) {
      _show(rules);
    } else {
      _loadLast(scope);
    }
  }

  Future<void> _loadLast(KitScope scope) async {
    BlackjackRules rules = const BlackjackRules();
    try {
      final record = await scope.lastGames.load(GameKeys.blackjack, version: blackjackRecordVersion);
      if (record != null) rules = BlackjackRules.fromJson(record.rules);
    } on Object {
      // Unreadable: Standard.
    }
    if (mounted && _rules == null) _show(rules);
  }

  /// Makes the chart for [rules] (the previous request, if still running, is cancelled).
  void _show(BlackjackRules rules) {
    _job?.cancel();
    final job = _jobs.start(const BlackjackChartJob(), rules, kind: JobKind.guide);
    setState(() {
      _rules = rules;
      _job = job;
      _failed = false;
      if (_chart?.rules.strategyKey != rules.strategyKey) _chart = null;
    });
    job.result.then(
      (chart) {
        if (mounted && _job == job) setState(() => _chart = chart);
      },
      onError: (Object error) {
        if (mounted && _job == job && error is! JobCancelled) setState(() => _failed = true);
      },
    );
  }

  @override
  void dispose() {
    _jobs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = BlackjackStrings.of(context);
    final rules = _rules;
    final chart = _chart;
    return GuidePage(
      title: b.pickLabel,
      children: [
        if (rules != null) _RulesBar(rules: rules, onChanged: _show),
        const SizedBox(height: 8),
        if (_failed)
          Text(b.chartFailed, key: const ValueKey('chart failed'))
        else if (chart == null)
          const LinearProgressIndicator(key: ValueKey('chart progress'), minHeight: 2)
        else ...[
          _ChartTable(
            title: b.hardTotals,
            rows: [
              for (var t = 5; t <= 20; t++) ('$t', [for (final u in _columns) chart.hard(t, u)]),
            ],
          ),
          _ChartTable(
            title: b.softTotals,
            rows: [
              for (var t = 13; t <= 20; t++) ('A,${t - 11}', [for (final u in _columns) chart.soft(t, u)]),
            ],
          ),
          _ChartTable(
            title: b.pairs,
            rows: [
              for (final r in _pairRanks)
                (
                  '${BlackjackStrings.upcard(r)},${BlackjackStrings.upcard(r)}',
                  [for (final u in _columns) chart.pair(r, u)],
                ),
            ],
          ),
          const SizedBox(height: 12),
          _Legend(strings: b),
        ],
      ],
    );
  }

  /// The dealer's upcards as charts print them: 2 to 10, then the ace.
  static const _columns = [1, 2, 3, 4, 5, 6, 7, 8, 9, aceIndex];

  /// The pairs in the same order: 2,2 to 10,10, then A,A.
  static const _pairRanks = [1, 2, 3, 4, 5, 6, 7, 8, 9, aceIndex];
}

/// The rules the chart is for: a preset, then the rules that change it.
class _RulesBar extends StatelessWidget {
  const _RulesBar({required this.rules, required this.onChanged});

  final BlackjackRules rules;
  final ValueChanged<BlackjackRules> onChanged;

  @override
  Widget build(BuildContext context) {
    final b = BlackjackStrings.of(context);
    BlackjackPreset? preset;
    for (final p in BlackjackPreset.values) {
      if (BlackjackRules.preset(p).strategyKey == rules.strategyKey) preset = p;
    }
    Widget help(BlackjackTerm term) => TermsHelpButton(title: b.term(term), terms: [b.entry(term)], all: b.glossary);
    return Wrap(
      key: const ValueKey('rules bar'),
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _Pick<BlackjackPreset?>(
          key: const ValueKey('preset'),
          label: b.presetLabel,
          value: preset,
          values: [...BlackjackPreset.values, if (preset == null) null],
          text: (p) => p == null ? '—' : b.preset(p),
          onChanged: (p) {
            if (p != null) onChanged(BlackjackRules.preset(p));
          },
        ),
        _Pick<int>(
          key: const ValueKey('decks'),
          label: b.decks,
          value: rules.decks,
          values: {1, 2, 6, 8, rules.decks}.toList()..sort(),
          text: (d) => '$d',
          onChanged: (d) => onChanged(rules.copyWith(decks: d)),
        ),
        _Toggle(
          key: const ValueKey('h17'),
          label: b.dealerHitsSoft17,
          value: rules.dealerHitsSoft17,
          onChanged: (v) => onChanged(rules.copyWith(dealerHitsSoft17: v)),
        ),
        _Toggle(
          key: const ValueKey('das'),
          label: b.doubleAfterSplit,
          value: rules.doubleAfterSplit,
          onChanged: (v) => onChanged(rules.copyWith(doubleAfterSplit: v)),
        ),
        _Pick<DoubleRule>(
          key: const ValueKey('double'),
          label: b.doubleLabel,
          value: rules.doubling,
          values: DoubleRule.values,
          text: b.doubleRule,
          onChanged: (r) => onChanged(rules.copyWith(doubling: r)),
        ),
        _Pick<Surrender>(
          key: const ValueKey('surrender'),
          label: b.surrenderLabel,
          value: rules.surrender,
          values: Surrender.values,
          text: b.surrenderRule,
          onChanged: (r) => onChanged(rules.copyWith(surrender: r)),
        ),
        _Toggle(
          key: const ValueKey('hole card'),
          label: b.holeCard,
          value: rules.holeCard,
          onChanged: (v) => onChanged(rules.copyWith(holeCard: v)),
        ),
        _Pick<NoHoleCardLoss>(
          key: const ValueKey('no hole card loss'),
          label: b.noHoleCardLossLabel,
          value: rules.noHoleCardLoss,
          values: NoHoleCardLoss.values,
          text: b.noHoleCardLoss,
          // Only a table without a hole card has the rule.
          enabled: !rules.holeCard,
          onChanged: (r) => onChanged(rules.copyWith(noHoleCardLoss: r)),
        ),
        help(BlackjackTerm.basicStrategy),
      ],
    );
  }
}

/// An on/off rule as a chip that lights when on.
class _Toggle extends StatelessWidget {
  const _Toggle({super.key, required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => FilterChip(
    label: Text(label),
    selected: value,
    visualDensity: VisualDensity.compact,
    // Material shows the hand only on the web; the UI wants it everywhere.
    mouseCursor: WidgetStateMouseCursor.clickable,
    onSelected: onChanged,
  );
}

/// A rule with several values: "Decks: 6 ▾", a menu of the values.
class _Pick<T> extends StatelessWidget {
  const _Pick({
    super.key,
    required this.label,
    required this.value,
    required this.values,
    required this.text,
    this.enabled = true,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> values;
  final String Function(T value) text;

  /// False: greyed out (the other rules leave it nothing to change).
  final bool enabled;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final grey = enabled ? null : Theme.of(context).disabledColor;
    return PopupMenuButton<T>(
      enabled: enabled,
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final v in values)
          PopupMenuItem(value: v, height: 36, mouseCursor: SystemMouseCursors.click, child: Text(text(v))),
      ],
      // The menu button's own ink lights it under the mouse; the hand
      // cursor is ours (Material shows one only on the web).
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$label: ${text(value)}', style: TextStyle(color: grey)),
              Icon(Icons.arrow_drop_down, size: 18, color: grey),
            ],
          ),
        ),
      ),
    );
  }
}

/// One table of the chart: a row label, then a coloured cell per upcard.
class _ChartTable extends StatelessWidget {
  const _ChartTable({required this.title, required this.rows});

  final String title;
  final List<(String label, List<ChartCode> codes)> rows;

  static const cell = Size(28, 22);

  @override
  Widget build(BuildContext context) {
    final b = BlackjackStrings.of(context);
    final theme = Theme.of(context);
    Widget box(Widget child, {Color? color}) => Container(
      width: cell.width,
      height: cell.height,
      margin: const EdgeInsets.all(1),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
      child: child,
    );
    const small = TextStyle(fontSize: 11, color: Colors.white70);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary)),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 40,
                      child: Text(b.dealerShows, style: small, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    for (final u in _BlackjackStrategyGuideState._columns)
                      box(Text(BlackjackStrings.upcard(u), style: small.copyWith(fontWeight: FontWeight.w700))),
                  ],
                ),
                for (final (label, codes) in rows)
                  Row(
                    key: ValueKey('$title $label'),
                    children: [
                      SizedBox(
                        width: 40,
                        child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                      for (final code in codes)
                        box(
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              b.chartLetter(code),
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: chartColors(code).$2),
                            ),
                          ),
                          color: chartColors(code).$1,
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What each letter means.
class _Legend extends StatelessWidget {
  const _Legend({required this.strings});

  final BlackjackStrings strings;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      key: const ValueKey('legend'),
      spacing: 12,
      runSpacing: 6,
      children: [
        for (final code in ChartCode.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 30,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: chartColors(code).$1, borderRadius: BorderRadius.circular(3)),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    strings.chartLetter(code),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: chartColors(code).$2),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(strings.chartMeaning(code), style: const TextStyle(fontSize: 13)),
            ],
          ),
      ],
    );
  }
}
