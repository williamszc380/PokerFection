import '../bots/bot.dart';
import '../engine/events.dart';
import '../engine/hand_evaluator.dart';
import '../engine/rules.dart';
import '../gto/preflop/preflop_charts.dart';
import '../gto/spot_strategy.dart';
import '../ui/table_controller.dart' show PlaybackSpeed;
import 'strings.dart';

class StringsZh extends S {
  const StringsZh();

  @override
  String get play => '开始游戏';
  @override
  String get settings => '设置';

  @override
  String get preflopCharts => '翻前范围表';
  @override
  String get spot => '局面';
  @override
  String chartSpot(ChartSpot spot) => switch (spot) {
        ChartSpot.open => '开池',
        ChartSpot.vsOpen => '面对开池',
        ChartSpot.vs3bet => '面对 3-bet',
      };
  @override
  String chartVillain(ChartSpot spot) => spot == ChartSpot.vs3bet ? '3-bet 者' : '开池者';
  @override
  String get callWord => '跟注';
  @override
  String inRange(int percent) => '范围内：$percent%';
  @override
  String get glossary => '术语表';
  @override
  String get animations => '动画';
  @override
  String get sound => '音效';
  @override
  String get cardBack => '牌背';
  @override
  String get cardFaces => '牌面';
  @override
  String get twoColors => '双色';
  @override
  String get fourColors => '四色';
  @override
  String get coloredCards => '彩色牌';
  @override
  String get tableColor => '牌桌';
  @override
  String speed(PlaybackSpeed speed) => switch (speed) {
        PlaybackSpeed.normal => '正常',
        PlaybackSpeed.fast => '快速',
        PlaybackSpeed.instant => '即时',
      };

  @override
  String get newGame => '新游戏';
  @override
  String get training => 'GTO 训练';
  @override
  String get freePlay => '自由对局';
  @override
  String get players => '玩家人数';
  @override
  String get stack => '筹码';
  @override
  String get opponentStyles => '对手风格';
  @override
  String get random => '随机';
  @override
  String style(BotStyle style) => switch (style) {
        BotStyle.tag => 'TAG',
        BotStyle.lag => 'LAG',
        BotStyle.station => '跟注站',
        BotStyle.nit => '极紧',
        BotStyle.gto => 'GTO',
      };
  @override
  String get showStyles => '显示打法风格';
  @override
  String get showCards => '显示手牌';
  @override
  String get customizeSeats => '自定义对手';
  @override
  String get you => '玩家';
  @override
  String get position => '位置';
  @override
  String get rotate => '轮转';
  @override
  String get resetStacks => '每手重置筹码';
  @override
  String get betSizes => '下注尺度';
  @override
  String get preflop => '翻牌前';
  @override
  String get postflop => '翻牌后';
  @override
  String get add => '添加';
  @override
  String get resetDefaults => '恢复默认';
  @override
  String get cancel => '取消';
  @override
  String get preflopSizePrompt => '加注尺度（下注的倍数）';
  @override
  String get postflopSizePrompt => '加注尺度（底池的倍数）';
  @override
  String between(String low, String high) => '$low 到 $high';
  @override
  String get rules => '规则';
  @override
  String get minRaise => '最小加注';
  @override
  String raiseRule(RaiseRule rule) => switch (rule) {
        RaiseRule.standard => '标准',
        RaiseRule.bigBlind => '1 BB（家庭规则）',
      };
  @override
  String get ante => '前注';
  @override
  String get noAnte => '无';
  @override
  String get start => '开始';

  @override
  String handsPlayed(int hands) => '$hands 手';
  @override
  String get showAllCards => '显示手牌';
  @override
  String get hideAllCards => '隐藏手牌';
  @override
  String get ranges => '范围';
  @override
  String get history => '历史';
  @override
  String get shuffleStyles => '打乱打法风格';
  @override
  String get newStylesDealt => '已随机更换打法风格。';
  @override
  String get mainMenu => '主菜单';
  @override
  String get showRange => '范围';
  @override
  String get changeStyle => '打法风格';
  @override
  String get showTheirCards => '显示手牌';
  @override
  String get hideTheirCards => '隐藏手牌';

  @override
  String get fold => '弃牌';
  @override
  String get check => '过牌';
  @override
  String call(String amount) => '跟注 $amount';
  @override
  String raiseTo(String amount, String? size) => '加注到 $amount${size == null ? '' : '（$size）'}';
  @override
  String allIn(String amount) => '全下 $amount';
  @override
  String get allInBadge => '全下';
  @override
  String get raiseAnySize => '加注';
  @override
  String get potWord => '底池';

  @override
  String potOdds(int percent) => '底池赔率 $percent%';
  @override
  String get showGto => '显示 GTO';
  @override
  String get notScored => '不计分';
  @override
  String get randomize => '随机';
  @override
  String get playRandomized => '随机出手';
  @override
  String get continueHand => '继续';
  @override
  String score(int score) => '得分 $score';
  @override
  String evLossAndMatch(String evLoss, int match) => 'EV 损失 $evLoss · 匹配度 $match%';
  @override
  String youPlay(String action) => action;
  @override
  String randomized(String action) => '随机：$action';
  @override
  String solvingTable(int percent) => '计算中… $percent%';
  @override
  String get solvingDecision => '计算中…';
  @override
  String thinking(String name) => '$name…';
  @override
  String get nextHand => '下一手';
  @override
  String get evenHand => '±0 BB';
  @override
  String noAnswer(NoAnswer? reason) => switch (reason) {
        NoAnswer.multiway => '无 GTO 答案：多人底池',
        NoAnswer.leftSolvedLines => '无 GTO 答案：超出求解路线',
        NoAnswer.solveFailed => '无 GTO 答案：求解失败',
        null => '无 GTO 答案',
      };
  @override
  String unavailable(Unavailable reason) => switch (reason) {
        Unavailable.checkIsFree => '可以免费过牌',
        Unavailable.raisingNotAllowed => '不能加注',
        Unavailable.belowMinBet => '低于最小下注',
        Unavailable.belowMinRaise => '低于最小加注',
        Unavailable.nearlyAllIn => '接近全下：请选全下',
        Unavailable.sameAmount => '与较小尺度相同',
        Unavailable.notSolved => '不在求解范围内',
      };
  @override
  String grade(DecisionGrade grade) => switch (grade) {
        DecisionGrade.best => '最佳',
        DecisionGrade.good => '良好',
        DecisionGrade.inaccuracy => '不精确',
        DecisionGrade.mistake => '失误',
        DecisionGrade.blunder => '严重失误',
      };
  @override
  String get columnYou => '玩家';
  @override
  String get columnGto => 'GTO';
  @override
  String get columnEvLoss => 'EV 损失';

  @override
  String get average => '平均';
  @override
  String get all => '全部';
  @override
  String get noScoresYet => '还没有得分。';
  @override
  String get decisions => '决策数';
  @override
  String get averageScore => '平均得分';
  @override
  String get evLoss => 'EV 损失';
  @override
  String get net => '净输赢';
  @override
  String handNumber(int number) => '#$number';
  @override
  String street(Street street) => switch (street) {
        Street.preflop => '翻牌前',
        Street.flop => '翻牌',
        Street.turn => '转牌',
        Street.river => '河牌',
      };
  @override
  String get close => '关闭';
  @override
  String get ok => '确定';
  @override
  String get fullGlossary => '术语表';

  @override
  String get yourRange => '你的范围';
  @override
  String get shareOfRange => '占范围比例';
  @override
  String get frequency => '频率';
  @override
  String get noRange => '暂无范围。';

  @override
  String wins(String name, String amount, {required bool you}) => you ? '你赢得 $amount' : '$name 赢得 $amount';
  @override
  String split(String names, String amount) => '$names 平分 $amount';
  @override
  String get mainPot => '主池';
  @override
  String sidePot(int number) => '边池 $number';
  @override
  String listNames(List<String> names) =>
      names.length < 2 ? names.join() : '${names.sublist(0, names.length - 1).join('、')} 和 ${names.last}';
  @override
  String hand(HandValue value) {
    final r0 = rankSymbols[value.rankAt(0)], r1 = rankSymbols[value.rankAt(1)];
    return switch (value.category) {
      HandCategory.straightFlush => value.rankAt(0) == 12 ? '皇家同花顺' : '同花顺（$r0 高）',
      HandCategory.quads => '四条 $r0',
      HandCategory.fullHouse => '葫芦（$r0 带 $r1）',
      HandCategory.flush => '同花（$r0 高）',
      HandCategory.straight => '顺子（$r0 高）',
      HandCategory.trips => '三条 $r0',
      HandCategory.twoPair => '两对（$r0 和 $r1）',
      HandCategory.pair => '一对 $r0',
      HandCategory.highCard => '高牌 $r0',
    };
  }

  @override
  String section(GlossarySection section) => switch (section) {
        GlossarySection.modes => '模式',
        GlossarySection.positions => '位置',
        GlossarySection.amounts => '数额',
        GlossarySection.actions => '行动',
        GlossarySection.hand => '牌局',
        GlossarySection.strategy => '策略',
        GlossarySection.scoring => '评分',
        GlossarySection.rules => '规则',
        GlossarySection.styles => '打法风格',
      };

  @override
  String term(GlossaryTerm term) => positionTerms[term] ?? switch (term) {
        GlossaryTerm.training => 'GTO 训练',
        GlossaryTerm.play => '自由对局',
        GlossaryTerm.inPosition => 'IP / OOP',
        GlossaryTerm.headsUp => '单挑',
        GlossaryTerm.bigBlinds => 'BB',
        GlossaryTerm.ante => '前注',
        GlossaryTerm.pot => '底池',
        GlossaryTerm.stack => '筹码量',
        GlossaryTerm.allIn => '全下',
        GlossaryTerm.raiseTo => '加注到',
        GlossaryTerm.betSizes => '下注尺度',
        GlossaryTerm.fold => '弃牌',
        GlossaryTerm.check => '过牌',
        GlossaryTerm.call => '跟注',
        GlossaryTerm.betRaise => '下注 / 加注',
        GlossaryTerm.open => '开池',
        GlossaryTerm.limp => '溜入',
        GlossaryTerm.threeBet => '3-bet / 4-bet',
        GlossaryTerm.holeCards => '底牌',
        GlossaryTerm.preflop => '翻牌前',
        GlossaryTerm.streets => '翻牌 / 转牌 / 河牌',
        GlossaryTerm.board => '公共牌',
        GlossaryTerm.showdown => '摊牌',
        GlossaryTerm.gto => 'GTO',
        GlossaryTerm.solver => '求解器',
        GlossaryTerm.range => '范围',
        GlossaryTerm.rangeGrid => '范围表',
        GlossaryTerm.charts => '翻前范围表',
        GlossaryTerm.equity => '权益（胜率）',
        GlossaryTerm.ev => 'EV（期望值）',
        GlossaryTerm.mixedStrategy => '混合策略',
        GlossaryTerm.rng => '随机（RNG）',
        GlossaryTerm.potOdds => '底池赔率',
        GlossaryTerm.evLoss => 'EV 损失',
        GlossaryTerm.mixMatch => '匹配度',
        GlossaryTerm.score => '得分',
        GlossaryTerm.grades => '评级',
        GlossaryTerm.noLimit => '无限注',
        GlossaryTerm.minBet => '最小下注',
        GlossaryTerm.minRaise => '最小加注',
        GlossaryTerm.houseRule => '家庭规则',
        GlossaryTerm.incompleteRaise => '不完整加注',
        GlossaryTerm.reopen => '重新开放行动',
        GlossaryTerm.splitPot => '平分底池',
        GlossaryTerm.styleGto => 'GTO',
        GlossaryTerm.tag => 'TAG',
        GlossaryTerm.lag => 'LAG',
        GlossaryTerm.station => '跟注站',
        GlossaryTerm.nit => '极紧',
        _ => term.name,
      };

  @override
  String definition(GlossaryTerm term) => switch (term) {
        GlossaryTerm.training => '在每个决策点，设定你认为 GTO 弃牌、跟注、加注（以及加注多少）的频率，勾选你要打的'
            '行动，然后查看 GTO 的答案和你的得分。翻牌前机器人按 GTO 打法行动，让你的局面都来自 GTO 对局；翻牌后'
            '才按它们各自的风格行动。',
        GlossaryTerm.play => '与机器人对战，不计分，就像真实牌局。',
        GlossaryTerm.utg => '枪口位：翻牌前第一个行动。',
        GlossaryTerm.utg1 => 'UTG 之后的座位。',
        GlossaryTerm.lj => 'Lojack：按钮位之前第三个座位。',
        GlossaryTerm.hj => 'Hijack：按钮位之前第二个座位。',
        GlossaryTerm.co => '关煞位（Cutoff）：按钮位前一个座位。',
        GlossaryTerm.btn => '按钮位（庄家）：翻牌后最后行动，是最好的位置。单挑时按钮位同时下小盲注。',
        GlossaryTerm.sb => '小盲位：发牌前下半个大盲注；翻牌后第一个行动。',
        GlossaryTerm.bb => '大盲位：发牌前下一个大盲注；翻牌前最后行动。',
        GlossaryTerm.inPosition => '有利位置（IP）：翻牌后你在对手之后行动。不利位置（OOP）：你先行动。最后行动是一种优势。',
        GlossaryTerm.headsUp => '只有两名玩家，无论是在牌桌上还是在底池中。',
        GlossaryTerm.bigBlinds => '大盲注，筹码和下注的单位：100 BB 的筹码就是 100 个大盲注。',
        GlossaryTerm.ante => '发牌前每位玩家都要下的少量强制注。',
        GlossaryTerm.pot => '目前为止下注的全部筹码。“0.5× 底池”的加注就是底池的一半。',
        GlossaryTerm.stack => '玩家拥有的筹码。两名玩家之间只能赢走较小的那份筹码（有效筹码）。',
        GlossaryTerm.allIn => '押上你的全部筹码。',
        GlossaryTerm.raiseTo => '加注后你的总下注额，包括你之前已经投入的部分。',
        GlossaryTerm.betSizes => '你的下注和加注选项，每个决策点都一样。翻牌前按你面对的下注的倍数计算：第一个入池时，'
            '2× 就是加注到 2 BB；面对 2.5 BB 的开池，3× 就是加注到 7.5 BB。翻牌后按底池的倍数计算：0.5× 底池就是半个底池'
            '（面对下注时按跟注后的底池）。当前不允许的尺度会变灰；接近全下的尺度由“全下”代替。尺度越多，计算越久。',
        GlossaryTerm.fold => '放弃这手牌以及已经投入底池的筹码。',
        GlossaryTerm.check => '不下注，把行动交给下一位（只能在没人下注时）。',
        GlossaryTerm.call => '跟上当前的下注额。',
        GlossaryTerm.betRaise => '先投入筹码（下注），或投入比当前下注更多的筹码（加注）。',
        GlossaryTerm.open => '翻牌前的第一次加注。',
        GlossaryTerm.limp => '翻牌前只跟大盲注而不加注。',
        GlossaryTerm.threeBet => '翻牌前的后续加注：大盲注算第一注，开池算第二注，所以再加注就是 3-bet，依此类推。',
        GlossaryTerm.holeCards => '你的两张私有手牌。',
        GlossaryTerm.preflop => '发出公共牌之前的下注轮。',
        GlossaryTerm.streets => '公共牌：先一次发三张，再发一张，最后再发一张，每次之后都有一轮下注。',
        GlossaryTerm.board => '桌面上的公共牌。',
        GlossaryTerm.showdown => '最后一轮下注后，剩下的玩家亮牌，牌最大的获胜。',
        GlossaryTerm.gto => '博弈论最优（Game Theory Optimal）：一种长期无法被击败的策略，无论对手怎么打。求解器能找到它（或接近它）。',
        GlossaryTerm.solver => '计算 GTO 策略的程序。本应用的求解器是近似 GTO：它简化了一些部分，比如后续街的下注。',
        GlossaryTerm.range => '玩家在某个局面下可能持有的所有手牌，以及每手牌的可能性。',
        GlossaryTerm.rangeGrid => '所有 169 种起手牌组成的 13 × 13 表格：对子在对角线上，同花在上方，不同花在下方。'
            '占范围比例：越亮的格子在范围中占比越大。频率：每手牌以这种方式打的频率。',
        GlossaryTerm.charts => '其他人都弃牌时，GTO 在翻牌前如何玩每手起手牌：第一个入池（开池）、面对加注（面对开池），'
            '或开池后面对再加注（面对 3-bet）。颜色把每手牌分成加注、跟注和弃牌；深色的牌不会走到这里，'
            '只填了一部分的牌只是有时会走到这里。点一手牌可以看它的数字。',
        GlossaryTerm.equity => '如果剩下的牌全部发完且不再下注，你能分到的底池份额。',
        GlossaryTerm.ev => '期望值：一个行动平均赢或输多少 BB。',
        GlossaryTerm.mixedStrategy => '同一手牌有时用不同方式打，比如 60% 跟注、40% 加注。GTO 经常这样做以保持难以预测。',
        GlossaryTerm.rng => '随机数生成器：按你设定的百分比让随机来选择行动，就像 GTO 的混合打法。',
        GlossaryTerm.potOdds => '你需要跟注的金额与可赢得的底池之比。当你的权益高于这个比例时，跟注就有利可图。',
        GlossaryTerm.evLoss => '与最佳行动相比，你的百分比损失了多少 BB。',
        GlossaryTerm.mixMatch => '你的百分比与 GTO 的接近程度：100% 表示完全一致。',
        GlossaryTerm.score => '0 到 100 分：一半看匹配度，一半看 EV 损失是否小。关键是弃牌、过牌或跟注、加注的频率；'
            '加注尺度只占 10%。使用“显示 GTO”的决策不计分。',
        GlossaryTerm.grades => '按 EV 损失评定（加注尺度占 10%）：最佳（不超过 0.02 BB）、良好（0.08）、不精确（0.25）、失误（0.75）、严重失误（更多）。',
        GlossaryTerm.noLimit => '这里使用的下注方式：你可以下注或加注任意数额，最多为你的全部筹码。',
        GlossaryTerm.minBet => '允许的最小下注：一个大盲注。',
        GlossaryTerm.minRaise => '允许的最小加注。标准规则：至少为本街上一次下注或加注的大小（面对 10 的下注，至少加注'
            '到 20；10 被加注到 30 之后，下一次加注至少到 50）。',
        GlossaryTerm.houseRule => '牌桌约定的非标准规则，例如允许任何至少 1 BB 的加注。',
        GlossaryTerm.incompleteRaise => '不足一次完整最小加注的全下。这是允许的，但不会重新开放行动：已经行动过的玩家只能跟注或弃牌。',
        GlossaryTerm.reopen => '一次完整的加注让本街已经行动过的每个人都可以再次加注。',
        GlossaryTerm.splitPot => '牌力相同的玩家平分底池。无法整除时，多出的筹码给按钮位左边第一位赢家。',
        GlossaryTerm.styleGto => '按求解器的近似最优策略行动。',
        GlossaryTerm.tag => '紧凶：玩的牌少，但下注和加注都很凶。',
        GlossaryTerm.lag => '松凶：玩很多牌，施加大量压力。',
        GlossaryTerm.station => '跟注站：跟注太多，很少加注。',
        GlossaryTerm.nit => '非常紧：只等强牌。',
      };
}
