import 'package:flutter/widgets.dart';

import '../../../../app/app_settings.dart';
import '../../../../games/blackjack/app/blackjack_grading.dart';
import '../../../../games/blackjack/blackjack.dart';
import '../../../kit/l10n/game_strings.dart';
import 'blackjack_strings_en.dart';
import 'blackjack_strings_es.dart';
import 'blackjack_strings_zh.dart';

/// Blackjack's glossary entries (☰ Glossary and the "?" buttons).
enum BlackjackTerm {
  blackjack,
  hit,
  stand,
  double,
  split,
  surrender,
  insurance,
  evenMoney,
  soft,
  bust,
  push,
  holeCard,
  dealerStart,
  noHoleCardLoss,
  soft17,
  doubleAfterSplit,
  resplitAces,
  shoe,
  penetration,
  continuousShuffle,
  basicStrategy,
  runningCount,
  trueCount,
  freshShoe,
  cardsSeen,
  bets,
}

/// Blackjack's own words in English, Spanish and Chinese: the coach's label,
/// the actions, hand totals and outcomes, the setup's rule names, the chart's
/// letters, the coach's reasons, the glossary and the rules. Each language
/// gives the words; this class builds the samples and the glossary from
/// them, so every language has the same texts.
abstract class BlackjackStrings implements GameStrings {
  const BlackjackStrings();

  static BlackjackStrings forLanguage(AppLanguage language) => switch (language) {
    AppLanguage.english => const BlackjackStringsEn(),
    AppLanguage.spanish => const BlackjackStringsEs(),
    AppLanguage.chinese => const BlackjackStringsZh(),
  };

  static BlackjackStrings of(BuildContext context) => forLanguage(AppSettings.of(context).language);

  // ---- the table ----

  /// The dealer at the table ("Dealer · 17").
  String get dealer;

  /// The dealer as the seat that wins a shoe the player ends behind, as the
  /// kit's "{name} wins" puts it: "Dealer wins", "Gana la banca", "庄家赢了".
  String get dealerSeat;

  /// A decision as its button reads: Hit, Stand, Double...
  String action(BlackjackAction action);

  /// Insurance when it is even money (a blackjack at a 3:2 table).
  String get evenMoney;

  /// "Soft" before a total: "Soft 17".
  String softTotal(int total);

  /// A total over 21.
  String get bust;

  /// A two-card 21 (the hand, not the game).
  String get blackjackHand;

  /// The dealer's range: a span of two-card totals ("17–21", "12–16点").
  String totalsFromTo(int low, int high);

  /// The dealer's range: two-card totals up to [total] ("11 or less").
  String totalOrLess(int total);

  /// How a hand ended, as its badge reads.
  String outcome(HandOutcome outcome);

  /// The seat bought insurance.
  String get insured;

  /// ☰ Count's label (the running count and cards left on the table).
  String get countToggle;

  /// The running count: "Count +4".
  String runningCount(String count);

  /// The true count: "True +1.5".
  String trueCount(String count);

  /// Cards still in the shoe.
  String cardsLeft(int cards);

  /// The round of the shoe: "Round 4".
  String round(int n);

  // ---- setup ----

  String get presetLabel;
  String preset(BlackjackPreset preset);
  String get decks;
  String get dealerHitsSoft17;
  String get blackjackPays;
  String get doubleLabel;
  String doubleRule(DoubleRule rule);
  String get doubleAfterSplit;
  String get surrenderLabel;
  String surrenderRule(Surrender rule);
  String get holeCard;

  /// What the dealer's blackjack takes without a hole card: the label,
  /// then each rule ("All bets", "Original bet").
  String get noHoleCardLossLabel;
  String noHoleCardLoss(NoHoleCardLoss rule);
  String get resplitAces;
  String get continuousShuffle;
  String get penetration;
  String coachMode(CoachMode mode);

  // ---- the Basic strategy guide ----

  String get hardTotals;
  String get softTotals;
  String get pairs;

  /// The header of the upcard columns.
  String get dealerShows;

  /// A chart cell's letters: en H S D Ds P Rh Rs Rp, zh 要 停 倍...
  String chartLetter(ChartCode code);

  /// What a chart letter means: "Double, else hit".
  String chartMeaning(ChartCode code);

  /// The guide's error when the chart could not be made.
  String get chartFailed;

  // ---- the coach ----

  /// A coach reason in a few words, numbers filled in.
  String reason(CoachReason reason);

  // ---- glossary ----

  String term(BlackjackTerm term);
  String definition(BlackjackTerm term);

  GameTerm entry(BlackjackTerm term) => GameTerm(this.term(term), definition(term));

  @override
  List<GameTerm> get glossary => [for (final t in BlackjackTerm.values) entry(t)];

  // ---- built from the words above ----

  /// A total as players say it: "17", "Soft 17", "Bust" (over 21).
  String total(HandTotal total) => total.isBust
      ? bust
      : total.soft
      ? softTotal(total.value)
      : '${total.value}';

  /// An upcard (a rank index) as cards show it: A, 2 to 10.
  static String upcard(int rank) => rank == aceIndex
      ? 'A'
      : rank == tenIndex
      ? '10'
      : '${rank + 1}';

  /// A chance as a whole percentage: "62%".
  static String percent(double chance) => '${(chance * 100).round()}%';

  /// A count with its sign: "+3", "−1.5" (a real minus), "0".
  static String signed(num v, {int decimals = 0}) {
    final text = v.abs().toStringAsFixed(decimals);
    if (double.parse(text) == 0) return text;
    return v < 0 ? '−$text' : '+$text';
  }

  @override
  List<String> samples() => [
    pickLabel,
    tagLabel('count')!,
    dealer,
    for (final a in BlackjackAction.values) action(a),
    evenMoney,
    softTotal(17),
    bust,
    blackjackHand,
    totalsFromTo(17, 21),
    totalOrLess(11),
    for (final o in HandOutcome.values) outcome(o),
    insured,
    countToggle,
    runningCount('+4'),
    trueCount('+1.5'),
    cardsLeft(180),
    round(4),
    presetLabel,
    for (final p in BlackjackPreset.values) preset(p),
    decks,
    dealerHitsSoft17,
    blackjackPays,
    doubleLabel,
    for (final r in DoubleRule.values) doubleRule(r),
    doubleAfterSplit,
    surrenderLabel,
    for (final r in Surrender.values) surrenderRule(r),
    holeCard,
    noHoleCardLossLabel,
    for (final r in NoHoleCardLoss.values) noHoleCardLoss(r),
    resplitAces,
    continuousShuffle,
    penetration,
    for (final m in CoachMode.values) coachMode(m),
    hardTotals,
    softTotals,
    pairs,
    dealerShows,
    for (final c in ChartCode.values) ...[chartLetter(c), chartMeaning(c)],
    chartFailed,
    for (final r in sampleReasons) reason(r),
    for (final t in BlackjackTerm.values) ...[term(t), definition(t)],
    for (final (title, body) in rulesSections) ...[title, body],
  ];

  /// One reason of every kind, with numbers, for [samples] and the tests.
  static final List<CoachReason> sampleReasons = [
    for (final kind in ReasonKind.values)
      CoachReason(
        kind,
        total: 16,
        soft: false,
        upcard: tenIndex,
        trueCount: 2.5,
        action: BlackjackAction.stand,
        basicAction: BlackjackAction.hit,
        chance: 0.62,
      ),
  ];
}
