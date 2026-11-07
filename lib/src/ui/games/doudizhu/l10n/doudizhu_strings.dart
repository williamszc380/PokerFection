import 'package:flutter/widgets.dart';

import '../../../../app/app_settings.dart';
import '../../../../games/doudizhu/doudizhu.dart';
import '../../../kit/l10n/game_strings.dart';
import 'doudizhu_strings_en.dart';
import 'doudizhu_strings_es.dart';
import 'doudizhu_strings_zh.dart';

/// The glossary entries of Fight the Landlord, in order.
enum LandlordTerm {
  landlord,
  peasants,
  kitty,

  /// The card dealt face up: whoever gets it bids first (Pagat; 明牌).
  faceUpCard,
  bidding,
  callRob,
  multiplier,
  bomb,
  rocket,
  spring,
  cardCounter,
  match,
}

/// Fight the Landlord's own words in English, Spanish and Chinese: the
/// coach's label, the buttons, move labels, the coach's reasons, setup,
/// guides, the glossary and the rules. Words are the ones players use:
/// 地主, 农民, 底牌, 炸弹, 王炸, 春天 in Chinese.
abstract class LandlordStrings implements GameStrings {
  const LandlordStrings();

  static LandlordStrings forLanguage(AppLanguage language) => switch (language) {
    AppLanguage.english => const LandlordStringsEn(),
    AppLanguage.spanish => const LandlordStringsEs(),
    AppLanguage.chinese => const LandlordStringsZh(),
  };

  static LandlordStrings of(BuildContext context) => forLanguage(AppSettings.of(context).language);

  // ---- the table ----
  String get landlord;
  String get peasant;
  String get kitty;

  /// The headline while a pass the player can't avoid plays itself
  /// (要不起: nothing in hand beats the table).
  String get cantBeat;

  /// The multiplier as the status line shows it: "×4".
  String multiplier(int x) => '×$x';
  String get everyonePassed;

  /// Who opens the auction, named once the face-up card has landed in
  /// their seat (the step that opens every deal): "Ana bids first", or
  /// "Ana calls first" under call and rob.
  String firstToBid(String name, BiddingStyle style);
  String get spring;
  String get antiSpring;
  String cardsLeft(int n);

  // ---- the buttons and move labels ----
  String get play;
  String get pass;
  String get clear;
  String get noBid;
  String bid(int points);
  String get call;
  String get noCall;
  String get rob;
  String get noRob;

  /// A kind of play: "Pair", "Airplane + singles", "Rocket".
  String kind(PlayType type);

  /// A joker's name in a move's text (other ranks are their card labels).
  String joker({required bool big});

  // ---- the coach ----
  String reason(DdzReason reason);
  String get sureWin;
  String get sureLoss;
  String get cardCounter;
  String get partner;

  // ---- an opponent's range (DdzRangeJob's notation) ----

  /// A kind of combination in a range, as a heading: 'pair' → "Pairs",
  /// 'pairs' → "Pair straights", 'rocket' → "Rocket".
  String rangeKind(String kind);

  /// What one of each kind is, for the range's "?".
  String rangeKindInfo(String kind);

  /// A joker in the range's grid, short (a column is about 30 px on a
  /// sideways phone): "LJ" / "BJ", 小 / 大.
  String jokerShort({required bool big});

  // ---- setup ----
  String presetName(String preset);
  String get bidding;
  String biddingStyle(BiddingStyle style);
  String get allPass;
  String allPassRule(AllPassRule rule);
  String get fourWithTwo;

  /// What a four with two is (the setup switch's "?").
  String get fourWithTwoInfo;
  String get rocketAsKickers;

  /// What the "Rocket as kickers" switch allows (its "?").
  String get rocketAsKickersInfo;
  String get kittyShown;
  String get bombsDouble;
  String get springDoubles;
  String get maxMultiplier;
  String get noLimit;
  String get customizeSeats;

  // ---- guides ----
  String get combinations;

  /// What a kind of play beats, one short line read after [beats]
  /// ("Beats: A lower pair."): a lower one of its kind, and the kind's
  /// limits (length, what counts).
  String kindRule(PlayType type);

  /// "Beats" (the guide's column).
  String get beats;
  String get example;

  // ---- glossary ----
  String term(LandlordTerm term);
  String definition(LandlordTerm term);
  GameTerm entry(LandlordTerm t) => GameTerm(term(t), definition(t));

  @override
  String? tagLabel(String tag) => null;

  @override
  List<GameTerm> get glossary => [for (final t in LandlordTerm.values) entry(t)];

  @override
  List<String> samples() => [
    pickLabel,
    landlord,
    peasant,
    kitty,
    cantBeat,
    everyonePassed,
    for (final style in BiddingStyle.values) firstToBid('Ana', style),
    spring,
    antiSpring,
    cardsLeft(5),
    play,
    pass,
    clear,
    noBid,
    for (final b in [1, 2, 3]) bid(b),
    call,
    noCall,
    rob,
    noRob,
    for (final t in PlayType.values) ...[kind(t), kindRule(t)],
    joker(big: false),
    joker(big: true),
    jokerShort(big: false),
    jokerShort(big: true),
    for (final k in const ['pair', 'trio', 'straight', 'pairs', 'airplane', 'bomb', 'rocket']) ...[
      rangeKind(k),
      rangeKindInfo(k),
    ],
    for (final r in DdzReason.values) reason(r),
    sureWin,
    sureLoss,
    cardCounter,
    partner,
    for (final p in DdzRules.presets.keys) presetName(p),
    bidding,
    for (final b in BiddingStyle.values) biddingStyle(b),
    allPass,
    for (final a in AllPassRule.values) allPassRule(a),
    fourWithTwo,
    fourWithTwoInfo,
    rocketAsKickers,
    rocketAsKickersInfo,
    kittyShown,
    bombsDouble,
    springDoubles,
    maxMultiplier,
    noLimit,
    customizeSeats,
    combinations,
    beats,
    example,
    for (final t in LandlordTerm.values) ...[term(t), definition(t)],
    for (final (title, body) in rulesSections) ...[title, body],
  ];
}
