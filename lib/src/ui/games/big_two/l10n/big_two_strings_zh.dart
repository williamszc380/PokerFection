import '../../../../games/big_two/big_two.dart';
import 'big_two_strings.dart';

/// Big Two in Chinese (锄大地 / 大老二), with the words players use: 单张,
/// 对子, 三条, 顺子, 同花, 葫芦, 铁支, 同花顺, 过, 报单.
class BigTwoStringsZh extends BigTwoStrings {
  const BigTwoStringsZh();

  @override
  String get pickLabel => 'GTO';

  @override
  String get play => '出牌';
  @override
  String get pass => '过';
  @override
  String get cantBeat => '要不起';
  @override
  String starts(String name, String? card) => '$name先出${card == null ? '' : '：$card'}';
  @override
  String get whoStarts => '谁先出？';
  @override
  String get clear => '重选';
  @override
  String get cardCounter => '记牌器';
  @override
  String get stillOut => '未出';
  @override
  String get highestOut => '场上最大';
  @override
  String get handPlan => '拆牌';
  @override
  String planSummary(int plays, int unbeatable) => '$plays 手出完 · $unbeatable 手最大';
  @override
  String kind(PlayKind kind) => switch (kind) {
    PlayKind.pass => '过',
    PlayKind.single => '单张',
    PlayKind.pair => '对子',
    PlayKind.triple => '三条',
    PlayKind.straight => '顺子',
    PlayKind.flush => '同花',
    PlayKind.fullHouse => '葫芦',
    PlayKind.fourOfAKind => '铁支',
    PlayKind.straightFlush => '同花顺',
  };
  @override
  String reason(CoachReason reason) => switch (reason) {
    CoachReason.goesOut => '出完',
    CoachReason.sureWin => '必胜',
    CoachReason.cantBeBeaten => '无人能压',
    CoachReason.shedsFive => '一次出五张',
    CoachReason.shedsLowest => '出掉最小的牌',
    CoachReason.keepsTwo => '留着2',
    CoachReason.usesTwo => '用掉一张2',
    CoachReason.breaksPair => '拆对子',
    CoachReason.breaksTriple => '拆三条',
    CoachReason.breaksFour => '拆铁支',
    CoachReason.followsPlan => '符合拆牌',
    CoachReason.addsPlays => '多了手数',
    CoachReason.blocksLastCard => '顶住报单',
    CoachReason.lastCardDanger => '可能放走报单',
    CoachReason.passKeepsHand => '不拆牌',
    CoachReason.opponentNearlyOut => '有人快出完',
  };
  @override
  String get sureWin => '必胜';

  @override
  String preset(BigTwoPreset preset) => switch (preset) {
    BigTwoPreset.standard => '标准',
    BigTwoPreset.hongKong => '香港',
    BigTwoPreset.taiwan => '台湾',
    BigTwoPreset.pusoyDos => '菲律宾',
  };
  @override
  String get cardsEach => '每人张数';
  @override
  String get straights => '顺子';
  @override
  String straightName(StraightRule rule) => switch (rule.name) {
    'hongKong' => '香港',
    'taiwan' => '台湾',
    'twoHigh' => 'J-Q-K-A-2',
    _ => '标准',
  };
  @override
  String get flushes => '同花';
  @override
  String flushOrder(FlushOrder order) => switch (order) {
    FlushOrder.suitFirst => '先比花色',
    FlushOrder.rankFirst => '先比点数',
    FlushOrder.allRanks => '同扑克',
  };
  @override
  String get bombs => '炸弹';
  @override
  String get sameFiveType => '五张须同型';
  @override
  String get passLockout => '过了不能再出';
  @override
  String get lastCardRule => '报单规则';
  @override
  String get dragonWins => '一条龙直接赢';
  @override
  String get noTopTwoFinish => '最大的2不能收尾';
  @override
  String get scoring => '计分';
  @override
  String scoringName(BigTwoScoring scoring) => switch (scoring) {
    BigTwoScoring.penalty => '罚分',
    BigTwoScoring.pusoyDos => '赢家计分',
  };
  @override
  String get doubleTwosLeft => '剩2翻倍';
  @override
  String get doubleBombLeft => '剩炸弹翻倍';
  @override
  String get customizeSeats => '分别设置';
  @override
  String scaledTarget(int points) => '本桌：打到$points分';
  @override
  String twosHeld(int n) => '2：$n张+';

  @override
  String get handRanks => '牌型';
  @override
  String get suitsLowToHigh => '花色（从小到大）';
  @override
  String get ranksLowToHigh => '点数（从小到大）';
  @override
  String get smallPlays => '单张、对子、三条';
  @override
  String get fiveCardHands => '五张牌型（从小到大）';
  @override
  String kindHint(PlayKind kind) => switch (kind) {
    PlayKind.pass => '这一轮不出牌。',
    PlayKind.single => '任意一张。先比点数，再比花色。',
    PlayKind.pair => '两张同点数。比较其中较大的一张。',
    PlayKind.triple => '三张同点数。',
    PlayKind.straight => '五张连续点数，花色不同。',
    PlayKind.flush => '五张同一花色。',
    PlayKind.fullHouse => '三条加一对。比较三条。',
    PlayKind.fourOfAKind => '四张同点数加任意一张。比较四张。',
    PlayKind.straightFlush => '五张连续且同一花色。',
  };
  @override
  String get lowestStraight => '最小的顺子';
  @override
  String get highestStraight => '最大的顺子';
  @override
  String flushHint(FlushOrder order) => switch (order) {
    FlushOrder.suitFirst => '两副同花：先比花色，再比最大的一张。',
    FlushOrder.rankFirst => '两副同花：先比最大的一张，再比它的花色。',
    FlushOrder.allRanks => '两副同花：像扑克一样从大到小逐张比较，最后比花色。',
  };
  @override
  String get bombsHint => '炸弹：铁支和同花顺也能压任何单张、对子或三条。';
  @override
  String get sameTypeHint => '五张牌只能被同类型更大的五张或炸弹压。';

  @override
  String term(BigTwoTerm term) => switch (term) {
    BigTwoTerm.single => '单张',
    BigTwoTerm.pair => '对子',
    BigTwoTerm.triple => '三条',
    BigTwoTerm.fiveCard => '五张牌型',
    BigTwoTerm.straight => '顺子',
    BigTwoTerm.flush => '同花',
    BigTwoTerm.fullHouse => '葫芦',
    BigTwoTerm.fourOfAKind => '铁支',
    BigTwoTerm.straightFlush => '同花顺',
    BigTwoTerm.bomb => '炸弹',
    BigTwoTerm.sameType => sameFiveType,
    BigTwoTerm.pass => '过',
    BigTwoTerm.lead => '自由出牌',
    BigTwoTerm.startingCard => '首出牌',
    BigTwoTerm.suitOrder => '花色大小',
    BigTwoTerm.lastCard => '报单规则',
    BigTwoTerm.lockout => '过了不能再出',
    BigTwoTerm.dragon => '一条龙',
    BigTwoTerm.topTwo => '最大的2不能收尾',
    BigTwoTerm.penalty => '罚分',
    BigTwoTerm.pusoyScoring => '赢家计分',
    BigTwoTerm.doubling => '翻倍',
    BigTwoTerm.handPlan => '拆牌',
    BigTwoTerm.unbeatable => '最大',
    BigTwoTerm.cardCounter => '记牌器',
    BigTwoTerm.match => '比赛',
  };
  @override
  String definition(BigTwoTerm term) => switch (term) {
    BigTwoTerm.single => '一张牌。更大的单张能压：先比点数，再比花色。',
    BigTwoTerm.pair => '两张同点数的牌。较大一张更大的对子赢。',
    BigTwoTerm.triple => '三张同点数的牌。点数大的赢。',
    BigTwoTerm.fiveCard => '顺子、同花、葫芦、铁支（加一张）、同花顺，从小到大。只有五张牌能压五张牌。',
    BigTwoTerm.straight => '五张连续点数，花色不全相同。哪些顺子有效及其大小由规则决定（见设置中的顺子）。',
    BigTwoTerm.flush => '五张同花色但不连续。两副同花怎么比由规则决定（见设置中的同花）。',
    BigTwoTerm.fullHouse => '三条加一对。比较三条的点数。',
    BigTwoTerm.fourOfAKind => '四张同点数加任意第五张。单出四张不算牌型。',
    BigTwoTerm.straightFlush => '五张连续且同一花色：最大的五张牌型。',
    BigTwoTerm.bomb => '开启炸弹时，铁支和同花顺也能压任何单张、对子或三条。',
    BigTwoTerm.sameType => sameTypeHint,
    BigTwoTerm.pass => '这一轮不出牌。下次轮到你还可以出，除非开启了过了不能再出。',
    BigTwoTerm.lead => '其他人都过后，最后出牌的人开始新一轮，可以出任何牌型。',
    BigTwoTerm.startingCard => '发出的最小的牌（标准玩法是方块3）。拿到的人先出，且第一手必须包含它。出牌前大家都能看到它。两人玩时，从最小的牌往上叫，直到有人拿着为止，所以另一人手里没有更小的牌。',
    BigTwoTerm.suitOrder => '点数相同时比花色。标准：方块 < 梅花 < 红桃 < 黑桃。台湾：梅花 < 方块 < 红桃 < 黑桃。菲律宾：梅花 < 黑桃 < 红桃 < 方块。',
    BigTwoTerm.lastCard => '下家只剩一张牌（报单）时，你出单张必须出手里最大的一张。也可以过，或出两张以上。',
    BigTwoTerm.lockout => '过了之后，要等新一轮开始才能再出牌。',
    BigTwoTerm.dragon => '13张手牌里3到2每个点数各一张。开启一条龙直接赢时，立刻赢下这一局。',
    BigTwoTerm.topTwo => '最后一张牌不能是单出的最大的牌（标准玩法是黑桃2）。',
    BigTwoTerm.penalty => '每个输家按剩余张数付分：9张以内每张1分，10张或以上每张2分，一张没出每张3分。赢家全收。',
    BigTwoTerm.pusoyScoring => '只有赢家得分：1分，最后一手每有一张2就翻一倍。',
    BigTwoTerm.doubling => '罚分时，输家手里每剩一张2，罚分翻一倍；剩铁支或同花顺再翻一倍。',
    BigTwoTerm.handPlan => '把手牌出完所需的最少手数。别人压不住的牌能拿回出牌权，其余每手都需要你自己出牌。',
    BigTwoTerm.unbeatable => '你没见过的牌都压不住这手，出完后你继续出牌。',
    BigTwoTerm.cardCounter => '还没出过的2、A、K，以及场上最大的牌。',
    BigTwoTerm.match =>
      '每局得分累加，直到有人达到目标分。罚分：输家累加罚分，总分最低者赢（通常打到100分）。赢家计分：赢家累加得分，总分最高者赢。'
          '按人数调整：目标分随人数变化，让一场比赛的局数和四人时差不多（约20局）。',
  };

  @override
  List<(String, String)> get rulesSections => const [
    ('目标', '最先出完手里所有的牌。'),
    ('牌', '点数从小到大：3 4 5 6 7 8 9 10 J Q K A 2。点数相同比花色：标准玩法 方块 < 梅花 < 红桃 < 黑桃，所以方块3最小，黑桃2最大。'),
    ('发牌', '四人每人13张。三人每人17张，最后一张亮牌发出，由拿到最小牌的人收下，大家都知道在谁手里。两人每人17张（或13、21张），其余不用。'),
    ('首出', '拿到发出的最小的牌（全部发完时是方块3）的人先出，第一手必须包含这张牌。出牌前大家都能看到它。两人玩时，从最小的牌往上叫，直到有人拿着为止。'),
    ('牌型', '单张、对子、三条，或五张牌型：顺子、同花、葫芦、铁支（加一张）、同花顺，从小到大。'),
    ('出牌', '按逆时针轮流。出同样张数且更大的牌压上家，或者过。其他人都过后，最后出牌的人开始新一轮，出什么都可以。'),
    ('计分', '罚分：每个输家剩9张以内每张1分，10张或以上每张2分，一张没出每张3分，赢家全收。赢家计分：赢家得1分，最后一手每有一张2翻一倍。'),
    ('比赛', '每局得分累加，直到有人达到目标分：罚分时总分最低者赢，赢家计分时总分最高者赢。'),
    ('玩法', '香港：A-2-3-4-5是最大的顺子，同花先比点数，拿到一条龙直接赢，不能以单张黑桃2收尾。台湾：梅花3先出，炸弹压一切，五张须同型。菲律宾：梅花3先出，花色 梅花 < 黑桃 < 红桃 < 方块，只有赢家得分。'),
  ];

  @override
  String presetTerm(BigTwoPreset preset) => switch (preset) {
    BigTwoPreset.standard => '标准规则',
    BigTwoPreset.hongKong => '香港规则',
    BigTwoPreset.taiwan => '台湾规则',
    BigTwoPreset.pusoyDos => '菲律宾规则',
  };
  @override
  String presetIntro(BigTwoPreset preset) => switch (preset) {
    BigTwoPreset.standard => 'Pagat 记载的标准玩法。',
    BigTwoPreset.hongKong => '香港的锄大地。',
    BigTwoPreset.taiwan => '台湾的大老二。各资料对它的顺子说法不一。',
    BigTwoPreset.pusoyDos => '菲律宾的 Pusoy Dos。',
  };
  @override
  String suitsLine(String suits) => '花色：$suits。';
  @override
  String startLine(String card, {required bool mustPlay}) =>
      mustPlay ? '发出的最小的牌先出（全部发完时是$card），第一手必须包含它。' : '拿到发出的最小的牌（全部发完时是$card）的人先出，出什么都可以。';
  @override
  String straightsLine(String lowest, String highest) => '顺子：$lowest最小，$highest最大。';
  @override
  String get noBombs => '没有炸弹。';
  @override
  String get lockoutOn => '过了之后，要等下一轮才能再出。';
  @override
  String get lockoutOff => '过了也可以再出。';
  @override
  String get lastCardOn => '有报单规则。';
  @override
  String get dragonOn => '拿到一条龙直接赢。';
  @override
  String topTwoOn(String card) => '不能以单张$card收尾。';
  @override
  String scoringLine(String name) => '计分：$name。';
  @override
  String straightTerm(StraightRule rule) => switch (rule.name) {
    'hongKong' => '香港顺子',
    'taiwan' => '台湾顺子',
    'twoHigh' => 'J-Q-K-A-2顺子',
    _ => '标准顺子',
  };
  @override
  String runsLowToHigh(String runs) => '从小到大：$runs。';
  @override
  String notStraights(String runs) => '不算顺子：$runs。';
  @override
  String straightTie(StraightTieBreak tieBreak, {required String card, required String run}) => switch (tieBreak) {
    StraightTieBreak.sequenceTop => '同样的顺子：比顺子顶端那张的花色（$run比$card）。',
    StraightTieBreak.highestCard => '同样的顺子：比最大那张的花色（$run比$card）。',
  };
  @override
  String flushTerm(FlushOrder order) => switch (order) {
    FlushOrder.suitFirst => '同花：先比花色',
    FlushOrder.rankFirst => '同花：先比点数',
    FlushOrder.allRanks => '同花：同扑克',
  };
  @override
  String usedBy(List<String> presets) => '采用的规则：${presets.join('、')}。';
  @override
  String get noPreset => '没有预设规则采用。';
  @override
  String get byPreset => '各地规则';
  @override
  String get on => '开';
  @override
  String get off => '关';
  @override
  String labelled(String label, String value) => '$label：$value';
  @override
  String source(List<String> names) => '来源：${names.join('；')}。';
  @override
  String sourceName(BigTwoSource source) => switch (source) {
    BigTwoSource.pagat => 'Pagat《Big Two》',
    BigTwoSource.pagatHongKong => 'Pagat《Big Two》香港玩法',
    BigTwoSource.pagatPhilippines => 'Pagat《Big Two》菲律宾玩法',
    BigTwoSource.pagatIndonesia => 'Pagat《Big Two》印尼玩法',
    BigTwoSource.wikipedia => '英文维基百科《Big two》',
    BigTwoSource.zhWikipedia => '中文维基百科《大老二》',
    BigTwoSource.charlesworth => 'Charlesworth，arXiv:1808.10442',
    BigTwoSource.denexa => 'Denexa，Big Two',
    BigTwoSource.wikipediaPusoy => '维基百科，Pusoy dos',
  };
  @override
  String get presetsCompared => '各地规则对比';
  @override
  String get sourcesTitle => '来源';
}
