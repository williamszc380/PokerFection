import '../../../../games/blackjack/app/blackjack_grading.dart';
import '../../../../games/blackjack/blackjack.dart';
import 'blackjack_strings.dart';

/// Blackjack in Chinese, with the words of the casino table (要牌, 停牌...).
class BlackjackStringsZh extends BlackjackStrings {
  const BlackjackStringsZh();

  @override
  String get pickLabel => '基本策略';

  @override
  String? tagLabel(String tag) => tag == 'count' ? '算牌' : null;

  @override
  String get dealer => '庄家';
  @override
  String get dealerSeat => '庄家';

  @override
  String action(BlackjackAction action) => switch (action) {
    BlackjackAction.hit => '要牌',
    BlackjackAction.stand => '停牌',
    BlackjackAction.double => '加倍',
    BlackjackAction.split => '分牌',
    BlackjackAction.surrender => '投降',
    BlackjackAction.insurance => '保险',
    BlackjackAction.noInsurance => '不买保险',
    BlackjackAction.keepPlaying => '继续',
  };

  @override
  String get evenMoney => '平赔';
  @override
  String softTotal(int total) => '软$total';
  @override
  String get bust => '爆牌';
  @override
  String get blackjackHand => '黑杰克';
  @override
  String totalsFromTo(int low, int high) => '$low–$high点';
  @override
  String totalOrLess(int total) => '$total点或以下';

  @override
  String outcome(HandOutcome outcome) => switch (outcome) {
    HandOutcome.pending => '进行中',
    HandOutcome.blackjack => '黑杰克',
    HandOutcome.win => '赢',
    HandOutcome.push => '平局',
    HandOutcome.lose => '输',
    HandOutcome.bust => '爆牌',
    HandOutcome.dealerBlackjack => '庄家黑杰克',
    HandOutcome.surrender => '已投降',
  };

  @override
  String get insured => '已买保险';
  @override
  String get countToggle => '算牌';
  @override
  String runningCount(String count) => '计数 $count';
  @override
  String trueCount(String count) => '真数 $count';
  @override
  String cardsLeft(int cards) => '剩$cards张';
  @override
  String round(int n) => '第$n局';

  @override
  String get presetLabel => '牌桌';
  @override
  String preset(BlackjackPreset preset) => switch (preset) {
    BlackjackPreset.standard => '标准',
    BlackjackPreset.vegasStrip => '拉斯维加斯大道',
    BlackjackPreset.downtown => '拉斯维加斯市区',
    BlackjackPreset.atlanticCity => '大西洋城',
    BlackjackPreset.european => '欧式',
    BlackjackPreset.singleDeck => '单副牌',
  };
  @override
  String get decks => '副数';
  @override
  String get dealerHitsSoft17 => '庄家软17要牌';
  @override
  String get blackjackPays => '黑杰克赔率';
  @override
  String get doubleLabel => '加倍';
  @override
  String doubleRule(DoubleRule rule) => switch (rule) {
    DoubleRule.anyTwo => '任意两张',
    DoubleRule.nineToEleven => '9–11',
    DoubleRule.tenToEleven => '10–11',
  };
  @override
  String get doubleAfterSplit => '分牌后加倍';
  @override
  String get surrenderLabel => '投降';
  @override
  String surrenderRule(Surrender rule) => switch (rule) {
    Surrender.none => '不可',
    Surrender.late => '晚投降',
    Surrender.early => '早投降',
  };
  @override
  String get holeCard => '暗牌';
  @override
  String get noHoleCardLossLabel => '庄家黑杰克';
  @override
  String noHoleCardLoss(NoHoleCardLoss rule) => switch (rule) {
    NoHoleCardLoss.allBets => '输全部注',
    NoHoleCardLoss.originalBetsOnly => '只输原注',
  };
  @override
  String get resplitAces => 'A可再分';
  @override
  String get continuousShuffle => '连续洗牌';
  @override
  String get penetration => '发牌深度';
  @override
  String coachMode(CoachMode mode) => switch (mode) {
    CoachMode.fresh => '新牌靴',
    CoachMode.seen => '已见牌',
  };

  @override
  String get hardTotals => '硬牌';
  @override
  String get softTotals => '软牌';
  @override
  String get pairs => '对子';
  @override
  String get dealerShows => '庄家';
  @override
  String chartLetter(ChartCode code) => switch (code) {
    ChartCode.hit => '要',
    ChartCode.stand => '停',
    ChartCode.doubleOrHit => '倍',
    ChartCode.doubleOrStand => '倍停',
    ChartCode.split => '分',
    ChartCode.surrenderOrHit => '降要',
    ChartCode.surrenderOrStand => '降停',
    ChartCode.surrenderOrSplit => '降分',
  };
  @override
  String chartMeaning(ChartCode code) => switch (code) {
    ChartCode.hit => '要牌',
    ChartCode.stand => '停牌',
    ChartCode.doubleOrHit => '加倍，不能则要牌',
    ChartCode.doubleOrStand => '加倍，不能则停牌',
    ChartCode.split => '分牌',
    ChartCode.surrenderOrHit => '投降，不能则要牌',
    ChartCode.surrenderOrStand => '投降，不能则停牌',
    ChartCode.surrenderOrSplit => '投降，不能则分牌',
  };
  @override
  String get chartFailed => '无法生成策略表。';

  @override
  String reason(CoachReason r) {
    final up = BlackjackStrings.upcard(r.upcard);
    final hand = r.soft ? '软${r.total}' : '${r.total}';
    final pct = BlackjackStrings.percent(r.chance ?? 0);
    final play = r.action == null ? '' : action(r.action!);
    final chart = r.basicAction == null ? '' : action(r.basicAction!);
    return switch (r.kind) {
      ReasonKind.standMadeHand => '17点以上：停牌',
      ReasonKind.cantBust => '11点以下：不会爆牌',
      ReasonKind.dealerBustsOften => '庄家明牌$up常爆牌',
      ReasonKind.dealerStrong => '庄家明牌$up多半能到17点以上',
      ReasonKind.doubleStrong => '$hand对$up：加倍',
      ReasonKind.doubleSoft => '$hand对$up：加倍',
      ReasonKind.splitAces => '一对A总要分',
      ReasonKind.splitEights => '一对8总要分',
      ReasonKind.neverSplitTens => '一对10永远不分',
      ReasonKind.neverSplitFives => '一对5永远不分',
      ReasonKind.splitVsWeak => '对弱牌$up要分',
      ReasonKind.noSplitVsStrong => '对$up不要分',
      ReasonKind.surrenderSaves => '赢面太小：投降',
      ReasonKind.softCantBust => '软牌：不会爆牌',
      ReasonKind.softStand => '软牌点数够好：停牌',
      ReasonKind.insuranceBad => '10点牌占$pct：保险亏',
      ReasonKind.insuranceGood => '10点牌占$pct：保险赚',
      ReasonKind.countDeviation => '真数${BlackjackStrings.signed(r.trueCount ?? 0, decimals: 1)}：$play（策略表：$chart）',
      ReasonKind.exactCardsPlay => '这几张牌：$play（策略表：$chart）',
      ReasonKind.bustRisk => '爆牌几率$pct',
      ReasonKind.tooRisky => '对$up风险太大',
      ReasonKind.dealerBustsLess => '庄家明牌$up爆牌没你想的多',
      ReasonKind.betterPlay => '$play更好',
    };
  }

  @override
  String term(BlackjackTerm term) => switch (term) {
    BlackjackTerm.blackjack => '黑杰克',
    BlackjackTerm.hit => '要牌',
    BlackjackTerm.stand => '停牌',
    BlackjackTerm.double => '加倍',
    BlackjackTerm.split => '分牌',
    BlackjackTerm.surrender => '投降',
    BlackjackTerm.insurance => '保险',
    BlackjackTerm.evenMoney => '平赔',
    BlackjackTerm.soft => '软牌',
    BlackjackTerm.bust => '爆牌',
    BlackjackTerm.push => '平局',
    BlackjackTerm.holeCard => '暗牌',
    BlackjackTerm.dealerStart => '庄家两张牌',
    BlackjackTerm.noHoleCardLoss => '庄家黑杰克',
    BlackjackTerm.soft17 => '软17',
    BlackjackTerm.doubleAfterSplit => '分牌后加倍',
    BlackjackTerm.resplitAces => 'A可再分',
    BlackjackTerm.shoe => '牌靴',
    BlackjackTerm.penetration => '发牌深度',
    BlackjackTerm.continuousShuffle => '连续洗牌',
    BlackjackTerm.basicStrategy => '基本策略',
    BlackjackTerm.runningCount => '计数',
    BlackjackTerm.trueCount => '真数',
    BlackjackTerm.freshShoe => '新牌靴',
    BlackjackTerm.cardsSeen => '已见牌',
    BlackjackTerm.bets => '注',
  };

  @override
  String definition(BlackjackTerm term) => switch (term) {
    BlackjackTerm.blackjack => '头两张牌是一张A和一张10点牌。赔3比2（有些牌桌赔6比5），除非庄家也是黑杰克。',
    BlackjackTerm.hit => '再要一张牌。',
    BlackjackTerm.stand => '不再要牌；轮到下一手牌或庄家。',
    BlackjackTerm.double => '下注加倍，只再拿一张牌。',
    BlackjackTerm.split => '把一对牌分成两手，每手各下一注。每手再发第二张牌，分别打完。',
    BlackjackTerm.surrender => '放弃这手牌，收回一半下注。晚投降在庄家查看是否黑杰克之后，早投降在之前。',
    BlackjackTerm.insurance => '庄家明牌是A时，另下半注。庄家是黑杰克则赔2比1。只有剩下的牌中10点牌超过三分之一时才划算。',
    BlackjackTerm.evenMoney => '在3比2的牌桌上自己拿到黑杰克时买保险：不管庄家是什么牌，都按1比1赔付。',
    BlackjackTerm.soft => 'A算作11点的一手牌，例如A-6（软17）。再要一张不会爆牌：A会变回1点。',
    BlackjackTerm.bust => '超过21点。这手牌立即输掉，即使庄家后来也爆牌。',
    BlackjackTerm.push => '与庄家点数相同：退回下注。',
    BlackjackTerm.holeCard => '庄家扣着的那张牌。明牌是10点牌或A时，庄家在你行动前先查看是否黑杰克。没有暗牌（欧式牌桌）时，庄家的第二张牌在你打完后才发。',
    BlackjackTerm.dealerStart => '庄家明牌和暗牌的点数之和。17–21点：庄家停牌（在庄家软17要牌的牌桌，软17还要牌）。12–16点：庄家必须要牌，硬牌可能爆牌。11点或以下：庄家要牌，下一张不会爆牌。训练模式中点一下庄家，就能看到根据你见过的牌算出的概率。',
    BlackjackTerm.noHoleCardLoss => '没有暗牌时，庄家可能在你加倍或分牌之后才翻出黑杰克。多数牌桌这时收走你所有的注（输全部注）；有些只收原注（只输原注），对10点牌或A加倍、分牌的风险就小一些。',
    BlackjackTerm.soft17 => 'A算作11点的17点。有些牌桌规定庄家软17要牌，玩家每注约多输0.2%。',
    BlackjackTerm.doubleAfterSplit => '分牌后的每手牌也可以加倍。',
    BlackjackTerm.resplitAces => '分开的A又拿到A时，可以再分。',
    BlackjackTerm.shoe => '发牌用的牌盒：1到8副牌混洗在一起。',
    BlackjackTerm.penetration => '切牌卡出现、重新洗牌之前发出多少牌。这里一个牌靴就是一局游戏。',
    BlackjackTerm.continuousShuffle => '洗牌机每局之后把牌放回，记牌没有用。一局游戏为50手。',
    BlackjackTerm.basicStrategy => '按牌桌规则、假设牌靴是满的，每个点数对庄家每张明牌的最佳打法。就是教练标出的打法和攻略里的策略表。',
    BlackjackTerm.runningCount => '算牌（Hi-Lo）：每见到一张2到6加1，每见到一张10点牌或A减1。计数高说明剩下的10点牌和A多，对你有利。',
    BlackjackTerm.trueCount => '计数除以剩下的副数：改变打法看的是它。',
    BlackjackTerm.freshShoe => '教练假设牌靴是满的，只去掉这一手看到的牌：即基本策略。按策略表评分。',
    BlackjackTerm.cardsSeen => '教练用洗牌以来见过的所有牌，像完美的算牌者一样。它的最佳打法与策略表不同时标为“算牌”，并按它评分。',
    BlackjackTerm.bets => '教练的数字：每种打法平均赢或输多少，以注计。−0.05表示长期输掉下注的5%。',
  };

  @override
  List<(String, String)> get rulesSections => const [
    ('目标', '赢过庄家：点数比庄家更接近21点，但不能超过。你独自对庄家，每手下注1。'),
    ('牌的点数', '2到10按面值计，J、Q、K算10点，A算11点或1点。A算作11点的牌是软牌。'),
    ('发牌', '你和庄家各发两张牌；庄家有一张扣着（暗牌）。明牌是10点牌或A时，庄家在你行动前先查看是否黑杰克。没有暗牌时，庄家的第二张牌在你打完后才发。'),
    ('你的选择', '要牌：再拿一张。停牌：不再要牌。加倍：下注加倍，只拿一张。分牌：一对分成两手，各下一注。投降：放弃这手牌，收回一半下注（牌桌允许时）。'),
    ('保险', '庄家明牌是A时，可以花半注买保险；庄家是黑杰克则赔2比1。在3比2的牌桌上自己是黑杰克时就是平赔：无论如何按1比1赔付。'),
    ('庄家', '庄家16点以下必须要牌，17点停牌。在庄家软17要牌的牌桌上，软17也要牌。'),
    ('赔付', '赢了赔1比1。黑杰克赔3比2（有些牌桌赔6比5）。点数相同为平局，退回下注。超过21点立即输。'),
    ('牌靴', '牌从1到8副牌的牌靴里发出。切牌卡出现时牌靴结束：这就是一局。使用连续洗牌机时，一局为50手。'),
  ];
}
