import '../../../../games/doudizhu/doudizhu.dart';
import 'doudizhu_strings.dart';

/// 斗地主, in the words players use (地主, 农民, 底牌, 炸弹, 王炸, 春天).
class LandlordStringsZh extends LandlordStrings {
  const LandlordStringsZh();

  @override
  String get pickLabel => 'GTO';

  @override
  String get landlord => '地主';
  @override
  String get peasant => '农民';
  @override
  String get kitty => '底牌';
  @override
  String get cantBeat => '要不起';
  @override
  String get everyonePassed => '都不叫';
  @override
  String firstToBid(String name, BiddingStyle style) => '$name先叫';
  @override
  String get spring => '春天';
  @override
  String get antiSpring => '反春';
  @override
  String cardsLeft(int n) => '$n张';

  @override
  String get play => '出牌';
  @override
  String get pass => '不出';
  @override
  String get clear => '重选';
  @override
  String get noBid => '不叫';
  @override
  String bid(int points) => '$points分';
  @override
  String get call => '叫地主';
  @override
  String get noCall => '不叫';
  @override
  String get rob => '抢地主';
  @override
  String get noRob => '不抢';

  @override
  String kind(PlayType type) => switch (type) {
    PlayType.solo => '单张',
    PlayType.pair => '对子',
    PlayType.trio => '三张',
    PlayType.trioSolo => '三带一',
    PlayType.trioPair => '三带二',
    PlayType.straight => '顺子',
    PlayType.pairStraight => '连对',
    PlayType.airplane => '飞机',
    PlayType.airplaneSolos => '飞机带单',
    PlayType.airplanePairs => '飞机带对',
    PlayType.fourTwoSolos => '四带二',
    PlayType.fourTwoPairs => '四带两对',
    PlayType.bomb => '炸弹',
    PlayType.rocket => '王炸',
  };

  @override
  String joker({required bool big}) => big ? '大王' : '小王';

  @override
  String jokerShort({required bool big}) => big ? '大' : '小';

  @override
  String rangeKind(String kind) => switch (kind) {
    'pair' => '对子',
    'trio' => '三张',
    'straight' => '顺子',
    'pairs' => '连对',
    'airplane' => '飞机',
    'bomb' => '炸弹',
    'rocket' => '王炸',
    _ => kind,
  };

  @override
  String rangeKindInfo(String kind) => switch (kind) {
    'pair' => '两张同点数的牌。炸弹也能拆成对子。',
    'trio' => '三张同点数的牌，可以单出，也可以带一张或一对。',
    'straight' => '5张或更多连着的点数，3到A。按前5张显示。',
    'pairs' => '3对或更多连着的对子，3到A。按前3对显示。',
    'airplane' => '2个或更多连着的三张，3到A。按前2个三张显示。',
    'bomb' => '四张同点数。能管其他任何牌型，并且翻倍。',
    'rocket' => '大王和小王。什么都能管，并且翻倍。',
    _ => kind,
  };

  @override
  String reason(DdzReason reason) => switch (reason) {
    DdzReason.goesOut => '出完',
    DdzReason.finishesNext => '下一手出完',
    DdzReason.partnerWinning => '队友的牌最大',
    DdzReason.keepsBomb => '留着炸弹',
    DdzReason.breaksBomb => '拆了炸弹',
    DdzReason.usesBomb => '炸弹：翻倍',
    DdzReason.usesRocket => '王炸：翻倍',
    DdzReason.leadsSmallForPartner => '出小牌给队友走',
    DdzReason.opponentsCantBeat => '对手管不上',
    DdzReason.keepsHighCards => '留着2和王',
    DdzReason.breaksGroup => '拆牌',
    DdzReason.shedsMany => '一次走很多牌',
    DdzReason.stopsOpponent => '顶住快出完的对手',
    DdzReason.opponentCanFollow => '对手能接',
    DdzReason.takesLead => '抢回出牌权',
    DdzReason.leadsWeakGroup => '先走小牌',
    DdzReason.waits => '先不出',
    DdzReason.strongHand => '牌好',
    DdzReason.weakHand => '牌差',
    DdzReason.holdsRocket => '有王炸',
    DdzReason.holdsBomb => '有炸弹',
  };

  @override
  String get sureWin => '必胜';
  @override
  String get sureLoss => '必输';
  @override
  String get cardCounter => '记牌器';
  @override
  String get partner => '队友';

  @override
  String presetName(String preset) => switch (preset) {
    'standard' => '经典',
    'app' => '叫抢',
    'beginner' => '新手',
    _ => preset,
  };
  @override
  String get bidding => '叫地主';
  @override
  String biddingStyle(BiddingStyle style) => switch (style) {
    BiddingStyle.points => '叫分',
    BiddingStyle.callRob => '叫抢',
  };
  @override
  String get allPass => '都不叫时';
  @override
  String allPassRule(AllPassRule rule) => switch (rule) {
    AllPassRule.redeal => '重新发牌',
    AllPassRule.firstBidderLandlord => '首叫当地主',
  };
  @override
  String get fourWithTwo => '四带二';
  @override
  String get fourWithTwoInfo => '四张一样的牌带两张单牌或两对。不是炸弹。';
  @override
  String get rocketAsKickers => '王炸可当带牌';
  @override
  String get rocketAsKickersInfo => '大小王可以一起当四带二或飞机的带牌。';
  @override
  String get kittyShown => '亮底牌';
  @override
  String get bombsDouble => '炸弹翻倍';
  @override
  String get springDoubles => '春天翻倍';
  @override
  String get maxMultiplier => '封顶倍数';
  @override
  String get noLimit => '不封顶';
  @override
  String get customizeSeats => '分别设置';

  @override
  String get combinations => '牌型';
  @override
  String get beats => '能管';
  @override
  String get example => '例子';
  @override
  String kindRule(PlayType type) => switch (type) {
    PlayType.solo => '比它小的单张。大小王最大。',
    PlayType.pair => '比它小的对子。两张王不算对子。',
    PlayType.trio => '比它小的三张。',
    PlayType.trioSolo => '比它小的三带一，只比三张。',
    PlayType.trioPair => '比它小的三带二，只比三张。',
    PlayType.straight => '同样长、比它小的顺子。5张起，3到A。',
    PlayType.pairStraight => '同样长、比它小的连对。3对起。',
    PlayType.airplane => '同样长、比它小的飞机。2个三张起。',
    PlayType.airplaneSolos => '同样长、比它小的。每个三张带一张。',
    PlayType.airplanePairs => '同样长、比它小的。每个三张带一对。',
    PlayType.fourTwoSolos => '比它小的四带二。不是炸弹。',
    PlayType.fourTwoPairs => '比它小的四带两对。不是炸弹。',
    PlayType.bomb => '除了更大的炸弹和王炸，都能管。翻倍。',
    PlayType.rocket => '什么都能管。翻倍。',
  };

  @override
  String term(LandlordTerm term) => switch (term) {
    LandlordTerm.landlord => '地主',
    LandlordTerm.peasants => '农民',
    LandlordTerm.kitty => '底牌',
    LandlordTerm.faceUpCard => '明牌',
    LandlordTerm.bidding => '叫分',
    LandlordTerm.callRob => '叫抢',
    LandlordTerm.multiplier => '倍数',
    LandlordTerm.bomb => '炸弹',
    LandlordTerm.rocket => '王炸',
    LandlordTerm.spring => '春天',
    LandlordTerm.cardCounter => '记牌器',
    LandlordTerm.match => '比赛',
  };

  @override
  String definition(LandlordTerm term) => switch (term) {
    LandlordTerm.landlord => '叫牌赢的人。拿底牌、先出牌，一个人打另外两个。输赢都是双倍。',
    LandlordTerm.peasants => '地主的两个对手。任何一个农民先出完，两个农民一起赢。',
    LandlordTerm.kitty => '发完牌剩下的3张。地主拿进手里。',
    LandlordTerm.faceUpCard => '发牌时翻开一张明牌，拿到的人先叫。出牌前大家都能看到它。',
    LandlordTerm.bidding => '叫1分、2分、3分或不叫。叫得最高的当地主，分数就是底分。叫3分直接当地主。',
    LandlordTerm.callRob => '多数App的叫法：有人叫地主后，其他人可以各抢一次。每抢一次翻倍，最后抢的人当地主。',
    LandlordTerm.multiplier => '底分乘的倍数：每出一个炸弹或王炸×2，春天也×2。',
    LandlordTerm.bomb => '四张一样的牌。能管其他任何牌型，并且翻倍。',
    LandlordTerm.rocket => '大王和小王一起出。什么都能管，并且翻倍。',
    LandlordTerm.spring => '农民一张牌都没出地主就出完，或地主只出过一手农民就赢了（反春）。翻倍。',
    LandlordTerm.cardCounter => '每种点数还有几张在别人手里。',
    LandlordTerm.match => '每局的分数累加：农民各得或各输底分乘倍数，地主是两倍。先到目标分的人结束比赛，总分最高的赢。总是3个人玩，所以目标分不随人数变。',
  };

  @override
  List<(String, String)> get rulesSections => const [
    ('目标', '三个人：一个地主对两个农民。谁先把牌出完，谁那一方就赢。'),
    ('发牌', '一副牌加大小王：每人17张，留3张底牌。发牌时翻开一张明牌，拿到的人先叫。从小到大：3 4 5 6 7 8 9 10 J Q K A 2、小王、大王。不分花色。'),
    ('叫地主', '轮流叫比上家高的分（1、2、3分）或不叫。有人叫3分，或叫分后连续两人不叫，叫牌结束。叫得最高的当地主，拿起底牌并亮给大家看。都不叫就重新发牌。'),
    ('出牌', '地主先出任意牌型。下家出同样牌型、同样张数、更大的牌，或者不出。炸弹和王炸能管其他牌型。连续两家不出，最后出牌的人重新出。这一轮不出，下一轮还可以出。'),
    ('计分', '每个农民输赢底分乘倍数，地主输赢双倍。每个炸弹或王炸翻倍，春天也翻倍。每局的分数累加：先到目标分（打到）的人结束比赛，总分最高的赢。'),
    ('玩法', '开局前可以选：叫抢、都不叫时怎么办、四带二、王炸当带牌、不亮底牌、封顶倍数。'),
  ];
}
