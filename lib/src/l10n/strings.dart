import 'package:flutter/widgets.dart';

import '../app/app_settings.dart';
import '../bots/bot.dart';
import '../engine/events.dart';
import '../engine/hand_evaluator.dart';
import '../engine/rules.dart';
import '../gto/preflop/preflop_charts.dart';
import '../gto/spot_strategy.dart';
import '../ui/table_controller.dart' show PlaybackSpeed;
import 'strings_en.dart';
import 'strings_es.dart';
import 'strings_zh.dart';

/// Glossary sections, in the order shown.
enum GlossarySection { modes, positions, amounts, actions, hand, strategy, scoring, rules, styles }

/// Glossary entries, by section.
enum GlossaryTerm {
  training(GlossarySection.modes),
  play(GlossarySection.modes),
  utg(GlossarySection.positions),
  utg1(GlossarySection.positions),
  lj(GlossarySection.positions),
  hj(GlossarySection.positions),
  co(GlossarySection.positions),
  btn(GlossarySection.positions),
  sb(GlossarySection.positions),
  bb(GlossarySection.positions),
  inPosition(GlossarySection.positions),
  headsUp(GlossarySection.positions),
  bigBlinds(GlossarySection.amounts),
  ante(GlossarySection.amounts),
  pot(GlossarySection.amounts),
  stack(GlossarySection.amounts),
  allIn(GlossarySection.amounts),
  raiseTo(GlossarySection.amounts),
  betSizes(GlossarySection.amounts),
  fold(GlossarySection.actions),
  check(GlossarySection.actions),
  call(GlossarySection.actions),
  betRaise(GlossarySection.actions),
  open(GlossarySection.actions),
  limp(GlossarySection.actions),
  threeBet(GlossarySection.actions),
  holeCards(GlossarySection.hand),
  preflop(GlossarySection.hand),
  streets(GlossarySection.hand),
  board(GlossarySection.hand),
  showdown(GlossarySection.hand),
  gto(GlossarySection.strategy),
  solver(GlossarySection.strategy),
  range(GlossarySection.strategy),
  rangeGrid(GlossarySection.strategy),
  charts(GlossarySection.strategy),
  equity(GlossarySection.strategy),
  ev(GlossarySection.strategy),
  mixedStrategy(GlossarySection.strategy),
  rng(GlossarySection.strategy),
  potOdds(GlossarySection.strategy),
  evLoss(GlossarySection.scoring),
  mixMatch(GlossarySection.scoring),
  score(GlossarySection.scoring),
  grades(GlossarySection.scoring),
  noLimit(GlossarySection.rules),
  minBet(GlossarySection.rules),
  minRaise(GlossarySection.rules),
  houseRule(GlossarySection.rules),
  incompleteRaise(GlossarySection.rules),
  reopen(GlossarySection.rules),
  splitPot(GlossarySection.rules),
  styleGto(GlossarySection.styles),
  tag(GlossarySection.styles),
  lag(GlossarySection.styles),
  station(GlossarySection.styles),
  nit(GlossarySection.styles);

  const GlossaryTerm(this.section);
  final GlossarySection section;
}

/// Every text the app shows, in one language. Get it with [S.of].
///
/// Labels are kept short and use standard poker terms; the glossary (the
/// "?" buttons) explains them.
abstract class S {
  const S();

  static S of(BuildContext context) => forLanguage(AppSettings.of(context).language);

  static S forLanguage(AppLanguage language) => switch (language) {
        AppLanguage.english => const StringsEn(),
        AppLanguage.spanish => const StringsEs(),
        AppLanguage.chinese => const StringsZh(),
      };

  // Main menu and settings.
  String get play;
  String get settings;

  // Preflop Charts.
  String get preflopCharts;
  String get spot;
  String chartSpot(ChartSpot spot);

  /// Who made the raise faced in [spot]: the opener, or the 3-bettor.
  String chartVillain(ChartSpot spot);

  /// Calls (of any amount), in the charts' key.
  String get callWord;

  /// How many of all starting hands get to a spot.
  String inRange(int percent);
  String get glossary;
  String get animations;
  String get sound;
  String get cardBack;
  String get cardFaces;
  String get twoColors;
  String get fourColors;

  /// Cards filled with their suit's color.
  String get coloredCards;
  String get tableColor;
  String speed(PlaybackSpeed speed);

  // Game setup.
  String get newGame;
  String get training;
  String get freePlay;
  String get players;
  String get stack;
  String get opponentStyles;
  String get random;
  String style(BotStyle style);
  String get showStyles;
  String get showCards;
  String get customizeSeats;
  String get you;
  String get position;
  String get rotate;
  String get resetStacks;
  String get betSizes;
  String get preflop;
  String get postflop;
  String get add;
  String get resetDefaults;
  String get cancel;
  String get preflopSizePrompt;
  String get postflopSizePrompt;
  String between(String low, String high);
  String get rules;
  String get minRaise;
  String raiseRule(RaiseRule rule);
  String get ante;
  String get noAnte;
  String get start;

  // At the table.
  String handsPlayed(int hands);
  String get showAllCards;
  String get hideAllCards;
  String get ranges;
  String get history;
  String get shuffleStyles;
  String get newStylesDealt;
  String get mainMenu;
  String get showRange;
  String get changeStyle;
  String get showTheirCards;
  String get hideTheirCards;

  // Actions ([amount] and [size] already formatted, e.g. "7.5 BB", "3×").
  String get fold;
  String get check;
  String call(String amount);
  String raiseTo(String amount, String? size);
  String allIn(String amount);

  /// Under a player with no chips left.
  String get allInBadge;
  String get raiseAnySize;

  /// The word for the pot in sizes ("0.5× pot").
  String get potWord;

  /// A size after the flop, as a multiple of the pot: 0.5 -> "0.5× pot",
  /// 1 -> "1× pot" (like "2.5×" before the flop).
  String potShare(double share) => '${number(share)}× $potWord';

  /// A raise size before the flop: 2.5 -> "2.5×".
  String multiple(double multiple) => '${number(multiple)}×';

  /// 2.0 -> "2", 2.5 -> "2.5", 2.25 -> "2.25".
  static String number(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

  // The decision panel.
  String potOdds(int percent);
  String get randomize;
  String get playRandomized;
  String get continueHand;
  String score(int score);
  String evLossAndMatch(String evLoss, int match);
  String youPlay(String action);
  String randomized(String action);
  String solvingTable(int percent);
  String get solvingDecision;
  String thinking(String name);
  String get nextHand;
  String get evenHand;
  String noAnswer(NoAnswer? reason);
  String unavailable(Unavailable reason);
  String grade(DecisionGrade grade);
  String get columnYou;
  String get columnGto;
  String get columnEvLoss;

  // Scores and history.
  String get average;
  String get all;
  String get noScoresYet;
  String get decisions;
  String get averageScore;
  String get evLoss;
  String get net;
  String handNumber(int number);
  String street(Street street);
  String get close;
  String get ok;
  String get fullGlossary;

  // Ranges.
  String get yourRange;
  String get shareOfRange;
  String get frequency;
  String get noRange;

  // Results at the table.
  String wins(String name, String amount, {required bool you});
  String split(String names, String amount);
  String get mainPot;
  String sidePot(int number);
  String listNames(List<String> names);
  String hand(HandValue value);

  // Glossary.
  String section(GlossarySection section);
  String term(GlossaryTerm term);
  String definition(GlossaryTerm term);
}

/// Position names are the same in every language.
const positionTerms = {
  GlossaryTerm.utg: 'UTG',
  GlossaryTerm.utg1: 'UTG+1',
  GlossaryTerm.lj: 'LJ',
  GlossaryTerm.hj: 'HJ',
  GlossaryTerm.co: 'CO',
  GlossaryTerm.btn: 'BTN',
  GlossaryTerm.sb: 'SB',
  GlossaryTerm.bb: 'BB',
};

/// Card ranks as players write them: 2-9, T, J, Q, K, A (0 = deuce).
const rankSymbols = ['2', '3', '4', '5', '6', '7', '8', '9', 'T', 'J', 'Q', 'K', 'A'];

extension StringsContext on BuildContext {
  /// The texts in the app's language.
  S get s => S.of(this);
}
