import 'package:flutter/material.dart' hide Card;

import '../../../games/big_two/app/big_two_record.dart';
import '../../../games/big_two/app/big_two_rules_codec.dart';
import '../../../kit/game_keys.dart';
import '../../../games/big_two/big_two.dart';
import '../../../l10n/strings.dart';
import '../../kit/cards.dart';
import '../../kit/guide_kit.dart';
import '../../kit/help.dart';
import '../../kit/kit_scope.dart';
import '../../kit/setup_kit.dart';
import '../../widgets/card_view.dart' show SuitIcon;
import '../../../app/app_settings.dart';
import 'big_two_coach_view.dart';
import 'l10n/big_two_strings.dart';

/// Guides > Rules (and ☰ Rules): the rules as short titled sections, then
/// the presets side by side (what Standard, Hong Kong, Taiwan and Pusoy Dos
/// each set), and the sources each follows.
class BigTwoRulesGuide extends StatelessWidget {
  const BigTwoRulesGuide({super.key});

  @override
  Widget build(BuildContext context) {
    final t = BigTwoStrings.of(context);
    final theme = Theme.of(context);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(text, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary)),
    );
    return GuidePage(
      title: S.of(context).rules,
      sections: t.rulesSections,
      children: [
        heading(t.presetsCompared),
        const BigTwoPresetTable(),
        heading(t.sourcesTitle),
        for (final preset in BigTwoPreset.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              t.labelled(
                t.preset(preset),
                [for (final s in BigTwoSources.ofPreset(preset)) t.sourceName(s)].join('; '),
              ),
            ),
          ),
        const SizedBox(height: 8),
        for (final source in BigTwoSource.documents)
          Padding(
            key: ValueKey('source ${source.name}'),
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '${t.sourceName(source)}\n${source.url}',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
      ],
    );
  }
}

/// The presets side by side, one column each, read from the engine's
/// rules: the suits and the starting card, the lowest and highest straight,
/// how flushes compare, each rule switch (✓ on, – off) and the scoring. A
/// value that differs from the standard game's stands out in the accent
/// colour, so the differences read at a glance.
class BigTwoPresetTable extends StatelessWidget {
  const BigTwoPresetTable({super.key});

  /// The table's rows: a label and each preset's value, from its rules.
  static List<(String, String Function(BigTwoRules))> rows(BigTwoStrings t) {
    String tick(bool on) => on ? '✓' : '–';
    return [
      (t.suitsLowToHigh, (r) => [for (final s in r.suitOrder) s.symbol].join('<')),
      (t.term(BigTwoTerm.startingCard), (r) => Card.of(Ranks.three, r.suitOrder.first).label),
      (t.lowestStraight, (r) => BigTwoStrings.runText(r.straights.order.first)),
      (t.highestStraight, (r) => BigTwoStrings.runText(r.straights.order.last)),
      (t.flushes, (r) => t.flushOrder(r.flushOrder)),
      (t.bombs, (r) => tick(r.bombs)),
      (t.sameFiveType, (r) => tick(r.fiveCardSameType)),
      (t.passLockout, (r) => tick(r.passLockout)),
      (t.lastCardRule, (r) => tick(r.lastCardRule)),
      (t.dragonWins, (r) => tick(r.dragonWins)),
      (t.noTopTwoFinish, (r) => tick(r.noTopSingleFinish)),
      (t.scoring, (r) => t.scoringName(r.scoring)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = BigTwoStrings.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final presets = [for (final p in BigTwoPreset.values) BigTwoRules.preset(p)];
    final standard = BigTwoRules.standard();
    Widget cell(String text, {bool bold = false, Color? color, TextAlign align = TextAlign.center}) {
      Widget words = Text(
        text,
        textAlign: align,
        style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.w700 : null, color: color),
      );
      // One word ("Penalización", "10-J-Q-K-A") shrinks to its column
      // rather than break in the middle.
      if (!text.contains(' ') && align == TextAlign.center) {
        words = FittedBox(fit: BoxFit.scaleDown, child: words);
      }
      return Padding(padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5), child: words);
    }

    return Table(
      key: const ValueKey('preset table'),
      columnWidths: const {0: FlexColumnWidth(1.3)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: const TableBorder(horizontalInside: BorderSide(color: Colors.white12)),
      children: [
        TableRow(
          children: [const SizedBox.shrink(), for (final p in BigTwoPreset.values) cell(t.preset(p), bold: true)],
        ),
        for (final (label, value) in rows(t))
          TableRow(
            children: [
              cell(label, align: TextAlign.start, color: Colors.white70),
              for (final rules in presets)
                cell(
                  value(rules),
                  color: value(rules) == value(standard) ? null : accent,
                  bold: value(rules) != value(standard),
                ),
            ],
          ),
      ],
    );
  }
}

/// Guides > Hand ranks: what can be played, from low to high, with cards
/// drawn as set in Settings: the suit order and the ranks, singles, pairs
/// and triples, then the five-card hands, the lowest and highest straight,
/// and how flushes (and bombs) compare. A preset row on top shows any
/// preset's order; it starts on [rules], or with none given on the last
/// game's rules (the standard ones until a game is saved).
class BigTwoHandRanksGuide extends StatefulWidget {
  const BigTwoHandRanksGuide({super.key, this.rules});

  /// The rules to start on; null: the last game's.
  final BigTwoRules? rules;

  @override
  State<BigTwoHandRanksGuide> createState() => _BigTwoHandRanksGuideState();
}

class _BigTwoHandRanksGuideState extends State<BigTwoHandRanksGuide> {
  late BigTwoRules _rules = widget.rules ?? BigTwoRules.standard();

  /// A preset was picked: the last game's rules, loading meanwhile, no
  /// longer replace it.
  var _touched = false;

  @override
  void initState() {
    super.initState();
    if (widget.rules == null) _loadLast();
  }

  Future<void> _loadLast() async {
    final last = await KitScope.of(context).lastGames
        .load(GameKeys.bigTwo, version: bigTwoRecordVersion, validate: BigTwoRecord.validate);
    if (!mounted || _touched || last == null) return;
    setState(() => _rules = BigTwoRecord.rulesOf(last));
  }

  @override
  Widget build(BuildContext context) {
    final t = BigTwoStrings.of(context);
    final rules = _rules;
    final examples = BigTwoHandExamples(rules);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
    return GuidePage(
      title: t.handRanks,
      children: [
        PresetRow<BigTwoPreset>(
          key: const ValueKey('presets'),
          label: S.of(context).rules,
          presets: BigTwoPreset.values,
          selected: BigTwoRulesCodec.presetOf(rules),
          name: t.preset,
          help: BigTwoPresetsHelp(title: S.of(context).rules),
          onChanged: (preset) => setState(() {
            _touched = true;
            _rules = BigTwoRules.preset(preset, players: rules.players);
          }),
        ),
        heading(t.suitsLowToHigh),
        _SuitOrder(rules: rules),
        heading(t.ranksLowToHigh),
        Text(Ranks.labels.join('  '), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        heading(t.smallPlays),
        for (final kind in const [PlayKind.single, PlayKind.pair, PlayKind.triple])
          _KindRow(name: t.kind(kind), hint: t.kindHint(kind), cards: examples.of(kind)),
        heading(t.fiveCardHands),
        for (final kind in BigTwoHandExamples.fiveCardKinds)
          _KindRow(name: t.kind(kind), hint: t.kindHint(kind), cards: examples.of(kind)),
        heading(t.straights),
        _KindRow(name: t.lowestStraight, cards: examples.lowestStraight),
        _KindRow(name: t.highestStraight, cards: examples.highestStraight),
        heading(t.flushes),
        Text(t.flushHint(rules.flushOrder)),
        if (rules.bombs) ...[heading(t.bombs), Text(t.bombsHint)],
        if (rules.fiveCardSameType) ...[heading(t.sameFiveType), Text(t.sameTypeHint)],
      ],
    );
  }
}

/// Example cards of every kind of play under some rules: valid
/// combinations of that kind (the guide's test checks them with the
/// engine), with suits from the rules' order.
class BigTwoHandExamples {
  BigTwoHandExamples(this.rules);

  final BigTwoRules rules;

  /// The five-card hands from low to high.
  static const fiveCardKinds = [
    PlayKind.straight,
    PlayKind.flush,
    PlayKind.fullHouse,
    PlayKind.fourOfAKind,
    PlayKind.straightFlush,
  ];

  /// The suit of strength [i] (0 the lowest) under the rules.
  Suit _suit(int i) => rules.suitOrder[i];

  Card _card(int rank, int suit) => Card.of(rank, _suit(suit));

  /// Example cards for [kind] (none for a pass), lowest first.
  List<Card> of(PlayKind kind) => switch (kind) {
    PlayKind.pass => const [],
    // The highest card of all: the 2 of the top suit.
    PlayKind.single => [_card(Ranks.two, 3)],
    PlayKind.pair => [_card(4, 0), _card(4, 2)], // 7 7
    PlayKind.triple => [_card(6, 1), _card(6, 2), _card(6, 3)], // 9 9 9
    PlayKind.straight => [_card(0, 0), _card(1, 2), _card(2, 1), _card(3, 3), _card(4, 0)], // 3-7
    PlayKind.flush => [
      for (final r in const [1, 5, 7, 8, 10]) _card(r, 2),
    ], // 4 8 10 J K
    PlayKind.fullHouse => [_card(2, 0), _card(2, 3), _card(5, 0), _card(5, 1), _card(5, 3)], // 55 888
    PlayKind.fourOfAKind => [_card(0, 1), for (var s = 0; s < 4; s++) _card(8, s)], // 3 JJJJ
    PlayKind.straightFlush => [for (var r = 2; r < 7; r++) _card(r, 3)], // 5-9
  };

  /// The run starting at [start] (see StraightRule), suits mixed.
  List<Card> _run(int start) => [for (var k = 0; k < 5; k++) _card((start + k) % 13, k.isEven ? 0 : 2)];

  List<Card> get lowestStraight => _run(rules.straights.order.first);
  List<Card> get highestStraight => _run(rules.straights.order.last);
}

/// The four suits from low to high, as card symbols with "<" between.
class _SuitOrder extends StatelessWidget {
  const _SuitOrder({required this.rules});

  final BigTwoRules rules;

  @override
  Widget build(BuildContext context) {
    final style = AppSettings.of(context).cardFaces;
    return Row(
      key: const ValueKey('suit order'),
      children: [
        for (final (i, suit) in rules.suitOrder.indexed) ...[
          if (i > 0) const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('<')),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: style.face(bigTwoFace(Card.of(0, suit)).suit),
              borderRadius: BorderRadius.circular(4),
            ),
            child: SuitIcon(
              suit: bigTwoFace(Card.of(0, suit)).suit,
              size: 20,
              color: style.ink(bigTwoFace(Card.of(0, suit)).suit),
            ),
          ),
        ],
      ],
    );
  }
}

/// A kind of play: its name, example cards, and one line under them.
class _KindRow extends StatelessWidget {
  const _KindRow({required this.name, required this.cards, this.hint});

  final String name;
  final List<Card> cards;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Align(
            alignment: Alignment.centerLeft,
            child: TrickRow(cards: [for (final card in cards) bigTwoFace(card)], cardWidth: 36),
          ),
          if (hint case final text?)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(text, style: const TextStyle(color: Colors.white70)),
            ),
        ],
      ),
    );
  }
}

/// The "?" beside a Rules preset row: what each preset sets (the suits and
/// who starts, which straights rank lowest and highest, how flushes compare,
/// bombs, passing, the dragon, the top 2, the scoring), then the suit order
/// and the starting card, with the sources each preset follows.
class BigTwoPresetsHelp extends StatelessWidget {
  const BigTwoPresetsHelp({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final t = BigTwoStrings.of(context);
    return TermsHelpButton(
      key: const ValueKey('presets help'),
      title: title,
      terms: [
        for (final preset in BigTwoPreset.values) t.presetEntry(preset),
        t.entry(BigTwoTerm.suitOrder),
        t.entry(BigTwoTerm.startingCard),
      ],
      all: t.glossary,
    );
  }
}
