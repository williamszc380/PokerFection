import 'package:flutter/widgets.dart';

import '../../../../app/app_settings.dart';
import '../../../../games/big_two/big_two.dart';
import '../../../kit/l10n/game_strings.dart';
import 'big_two_strings_en.dart';
import 'big_two_strings_es.dart';
import 'big_two_strings_zh.dart';

/// Big Two's glossary entries, in the order the glossary lists them.
enum BigTwoTerm {
  single,
  pair,
  triple,
  fiveCard,
  straight,
  flush,
  fullHouse,
  fourOfAKind,
  straightFlush,
  bomb,
  sameType,
  pass,
  lead,
  startingCard,
  suitOrder,
  lastCard,
  lockout,
  dragon,
  topTwo,
  penalty,
  pusoyScoring,
  doubling,
  handPlan,
  unbeatable,
  cardCounter,
  match,
}

/// Big Two's own words in English, Spanish and Chinese: the buttons, move
/// and combination names, the coach's reasons, the setup's labels, the
/// guides, the glossary and the rules. The kit reads it through
/// [GameStrings]; enums become text through exhaustive switches, so a new
/// value stops compilation until all three languages have it.
abstract class BigTwoStrings implements GameStrings {
  const BigTwoStrings();

  static BigTwoStrings forLanguage(AppLanguage language) => switch (language) {
    AppLanguage.english => const BigTwoStringsEn(),
    AppLanguage.spanish => const BigTwoStringsEs(),
    AppLanguage.chinese => const BigTwoStringsZh(),
  };

  static BigTwoStrings of(BuildContext context) => forLanguage(AppSettings.of(context).language);

  // ---- the table and the panel ----

  /// The panel's buttons.
  String get play;
  String get pass;
  String get clear;

  /// The headline while a pass the player can't avoid plays itself.
  String get cantBeat;

  /// Who goes first (the step every deal opens with, then the note in the
  /// middle of the felt until the first play): "Kai starts: 3♦", or with no
  /// card (a chosen leader) "Kai starts". [name] is the seat's name, the
  /// player's seat included ("Player starts: 3♦"), as Fight the Landlord's
  /// "Player bids first".
  String starts(String name, String? card);

  /// The headline while two players' low cards are being called, before
  /// anyone is named: "Who starts?".
  String get whoStarts;

  /// ☰'s toggle and the counter's title.
  String get cardCounter;

  /// The counter: the high cards still out, and the highest card out.
  String get stillOut;
  String get highestOut;

  /// The hand plan's title and its summary: "5 plays · 2 unbeatable".
  String get handPlan;
  String planSummary(int plays, int unbeatable);

  /// A combination's name: "Pair", "Full house".
  String kind(PlayKind kind);

  /// A coach reason as a few words.
  String reason(CoachReason reason);

  /// The badge on a proven win.
  String get sureWin;

  // ---- setup ----

  String preset(BigTwoPreset preset);
  String get cardsEach;
  String get straights;
  String straightName(StraightRule rule);
  String get flushes;
  String flushOrder(FlushOrder order);
  String get bombs;
  String get sameFiveType;
  String get passLockout;
  String get lastCardRule;
  String get dragonWins;
  String get noTopTwoFinish;
  String get scoring;
  String scoringName(BigTwoScoring scoring);
  String get doubleTwosLeft;
  String get doubleBombLeft;
  String get customizeSeats;

  /// Under the setup's "Play to" when the target is scaled: the target at
  /// the table chosen ("At this table: to 45").
  String scaledTarget(int points);

  // ---- an opponent's range (the sheet a tap on a bot opens, Training) ----

  /// Holding at least [n] 2s: "2s: 1+".
  String twosHeld(int n);

  // ---- the Hand ranks guide ----

  /// The guide's title (also its Guides button).
  String get handRanks;
  String get suitsLowToHigh;
  String get ranksLowToHigh;
  String get smallPlays;
  String get fiveCardHands;

  /// One line under each combination.
  String kindHint(PlayKind kind);
  String get lowestStraight;
  String get highestStraight;
  String flushHint(FlushOrder order);
  String get bombsHint;
  String get sameTypeHint;

  // ---- the glossary ----

  String term(BigTwoTerm term);
  String definition(BigTwoTerm term);

  GameTerm entry(BigTwoTerm term) => GameTerm(this.term(term), definition(term));

  /// Every term, with each straight order after Straight, each flush order
  /// after Flush, and the presets after the rule switches.
  @override
  List<GameTerm> get glossary => [
    for (final t in BigTwoTerm.values) ...[
      entry(t),
      if (t == BigTwoTerm.straight)
        for (final rule in allStraights) straightEntry(rule),
      if (t == BigTwoTerm.flush)
        for (final order in FlushOrder.values) flushEntry(order),
      if (t == BigTwoTerm.topTwo)
        for (final preset in BigTwoPreset.values) presetEntry(preset),
    ],
  ];

  // ---- the presets explained: the setup's "?", the glossary, the Rules guide ----
  //
  // What each preset, straight order and flush order does is read from the
  // engine (the runs, the suits, which switches are on) and put in words
  // here, so the explanations can't drift from the rules the game plays.

  /// The straight orders, as the setup offers them.
  static const allStraights = [StraightRule.pagat, StraightRule.hongKong, StraightRule.taiwan, StraightRule.twoHigh];

  /// A preset's glossary title: "Hong Kong rules".
  String presetTerm(BigTwoPreset preset);

  /// The first line of a preset's entry: which game it is.
  String presetIntro(BigTwoPreset preset);

  /// "Suits: ♦ < ♣ < ♥ < ♠."
  String suitsLine(String suits);

  /// Who starts: the lowest card dealt, with [card] (the 3♦ or 3♣) named
  /// only as the card that starts when every card is dealt. Two players
  /// leave cards out, so the 3♦ may never be dealt and the engine starts
  /// with the lowest card that was.
  String startLine(String card, {required bool mustPlay});

  /// "Straights: A-2-3-4-5 lowest, 10-J-Q-K-A highest."
  String straightsLine(String lowest, String highest);
  String get noBombs;
  String get lockoutOn;
  String get lockoutOff;
  String get lastCardOn;
  String get dragonOn;

  /// "Nobody may go out on a lone 2♠."
  String topTwoOn(String card);

  /// "Scoring: Penalty."
  String scoringLine(String name);

  /// A straight order's glossary title: "Hong Kong straights".
  String straightTerm(StraightRule rule);

  /// "Low to high: A-2-3-4-5 < 2-3-4-5-6 < … < 10-J-Q-K-A."
  String runsLowToHigh(String runs);

  /// "Not straights: J-Q-K-A-2, Q-K-A-2-3."
  String notStraights(String runs);

  /// Which card's suit breaks a tie between two equal straights, shown on
  /// [card] in the example [run] (see [straightTieOf]).
  String straightTie(StraightTieBreak tieBreak, {required String card, required String run});

  /// [straightTie] for [rule], with an example run [rule] really counts.
  ///
  /// A run that goes past the 2 (A-2-3-4-5, else 2-3-4-5-6) shows the
  /// difference best: its top card is not its highest card. An order with
  /// neither (J-Q-K-A-2 straights) gets its own top run.
  String straightTieOf(StraightRule rule) {
    final order = rule.order;
    final start = order.contains(11)
        ? 11
        : order.contains(12)
        ? 12
        : order.last;
    final ranks = [for (var k = 0; k < 5; k++) (start + k) % 13];
    final rank = switch (rule.tieBreak) {
      StraightTieBreak.sequenceTop => ranks.last,
      StraightTieBreak.highestCard => ranks.reduce((a, b) => a > b ? a : b),
    };
    return straightTie(rule.tieBreak, card: Ranks.labels[rank], run: runText(start));
  }

  /// A flush order's glossary title: "Flushes: rank first".
  String flushTerm(FlushOrder order);

  /// "Presets: Standard, Pusoy Dos." ([presets] never empty; see [noPreset]).
  String usedBy(List<String> presets);
  String get noPreset;

  /// The title of the entry that lists a rule in every preset.
  String get byPreset;
  String get on;
  String get off;

  /// "Standard: Off": a label and its value.
  String labelled(String label, String value);

  /// "Source: Pagat, Big Two." for one or more [names].
  String source(List<String> names);
  String sourceName(BigTwoSource source);

  /// The Rules guide's comparison of the presets, and its list of sources.
  String get presetsCompared;
  String get sourcesTitle;

  /// A rule's place in the presets as a "?" entry: the preset names with
  /// [value] for each ("Taiwan: On"), then the rule's [sources].
  GameTerm byPresetEntry(String Function(BigTwoRules rules) value, {List<BigTwoSource> sources = const []}) => GameTerm(
    byPreset,
    [
      for (final p in BigTwoPreset.values) labelled(preset(p), value(BigTwoRules.preset(p))),
      if (sources.isNotEmpty) source([for (final s in sources) sourceName(s)]),
    ].join('\n'),
  );

  String onOff(bool value) => value ? on : off;

  /// What a preset sets, line by line, read from its rules.
  GameTerm presetEntry(BigTwoPreset preset) {
    final r = BigTwoRules.preset(preset);
    final start = Card.of(Ranks.three, r.suitOrder.first);
    final top = Card.of(Ranks.two, r.suitOrder.last);
    return GameTerm(
      presetTerm(preset),
      [
        presetIntro(preset),
        suitsLine(suitsText(r)),
        startLine(start.label, mustPlay: r.mustPlayStartCard),
        straightsLine(runText(r.straights.order.first), runText(r.straights.order.last)),
        flushHint(r.flushOrder),
        r.bombs ? bombsHint : noBombs,
        if (r.fiveCardSameType) sameTypeHint,
        r.passLockout ? lockoutOn : lockoutOff,
        if (r.lastCardRule) lastCardOn,
        if (r.dragonWins) dragonOn,
        if (r.noTopSingleFinish) topTwoOn(top.label),
        scoringLine(scoringName(r.scoring)),
        source([for (final s in BigTwoSources.ofPreset(preset)) sourceName(s)]),
      ].join('\n'),
    );
  }

  /// Which runs a straight order counts, from low to high, which it doesn't,
  /// how ties break, the presets that use it, and its source.
  GameTerm straightEntry(StraightRule rule) {
    final order = rule.order;
    final shown = order.length <= 6
        ? [for (final start in order) runText(start)]
        : [
            runText(order[0]),
            runText(order[1]),
            '…',
            for (final start in order.sublist(order.length - 3)) runText(start),
          ];
    final users = [
      for (final p in BigTwoPreset.values)
        if (BigTwoRules.preset(p).straights == rule) preset(p),
    ];
    return GameTerm(
      straightTerm(rule),
      [
        runsLowToHigh(shown.join(' < ')),
        notStraights(
          [
            for (var start = 0; start < 13; start++)
              if (!order.contains(start)) runText(start),
          ].join(', '),
        ),
        straightTieOf(rule),
        users.isEmpty ? noPreset : usedBy(users),
        source([for (final s in BigTwoSources.ofStraights(rule)) sourceName(s)]),
      ].join('\n'),
    );
  }

  /// How a flush order compares two flushes, the presets that use it, and
  /// its source.
  GameTerm flushEntry(FlushOrder order) {
    final users = [
      for (final p in BigTwoPreset.values)
        if (BigTwoRules.preset(p).flushOrder == order) preset(p),
    ];
    return GameTerm(
      flushTerm(order),
      [
        flushHint(order),
        users.isEmpty ? noPreset : usedBy(users),
        source([for (final s in BigTwoSources.ofFlushes(order)) sourceName(s)]),
      ].join('\n'),
    );
  }

  /// The run of five ranks starting at [start] (see StraightRule):
  /// "10-J-Q-K-A". A word joiner after each dash keeps a run on one line
  /// (a list of runs breaks between them, never inside one).
  static String runText(int start) => [for (var k = 0; k < 5; k++) Ranks.labels[(start + k) % 13]].join('-\u2060');

  /// The suits from low to high: "♦ < ♣ < ♥ < ♠".
  static String suitsText(BigTwoRules rules) => [for (final s in rules.suitOrder) s.symbol].join(' < ');

  @override
  String? tagLabel(String tag) => null;

  @override
  List<String> samples() => [
    pickLabel,
    play,
    pass,
    clear,
    cantBeat,
    starts('Ana', '3♦'),
    starts('Ana', null),
    whoStarts,
    cardCounter,
    stillOut,
    highestOut,
    handPlan,
    planSummary(5, 2),
    for (final k in PlayKind.values) kind(k),
    for (final r in CoachReason.values) reason(r),
    sureWin,
    for (final p in BigTwoPreset.values) preset(p),
    cardsEach,
    straights,
    for (final r in const [StraightRule.pagat, StraightRule.hongKong, StraightRule.taiwan, StraightRule.twoHigh])
      straightName(r),
    flushes,
    for (final o in FlushOrder.values) flushOrder(o),
    bombs,
    sameFiveType,
    passLockout,
    lastCardRule,
    dragonWins,
    noTopTwoFinish,
    scoring,
    for (final s in BigTwoScoring.values) scoringName(s),
    doubleTwosLeft,
    doubleBombLeft,
    customizeSeats,
    scaledTarget(45),
    for (var n = 1; n <= 3; n++) twosHeld(n),
    handRanks,
    suitsLowToHigh,
    ranksLowToHigh,
    smallPlays,
    fiveCardHands,
    for (final k in PlayKind.values) kindHint(k),
    lowestStraight,
    highestStraight,
    for (final o in FlushOrder.values) flushHint(o),
    bombsHint,
    sameTypeHint,
    for (final t in BigTwoTerm.values) ...[term(t), definition(t)],
    for (final (title, body) in rulesSections) ...[title, body],
    for (final p in BigTwoPreset.values) ...[presetTerm(p), presetIntro(p)],
    for (final r in allStraights) straightTerm(r),
    for (final o in FlushOrder.values) flushTerm(o),
    for (final s in BigTwoSource.values) sourceName(s),
    noBombs,
    lockoutOn,
    lockoutOff,
    lastCardOn,
    dragonOn,
    noPreset,
    byPreset,
    on,
    off,
    presetsCompared,
    sourcesTitle,
  ];
}
