import 'kit_strings.dart';

class KitStringsZh extends KitStrings {
  const KitStringsZh();

  @override
  String get trainingMode => '训练';
  @override
  String get lastGame => '上一局';
  @override
  String get thinkLonger => '深入分析';
  @override
  String get yourTurn => '轮到你';
  @override
  String get youWin => '你赢了';
  @override
  String get youLose => '你输了';
  @override
  String get draw => '平局';
  @override
  String wins(String name) => '$name赢了';
  @override
  String get nextDeal => '下一局';
  @override
  String get deal => '发牌';
  @override
  String get newShoe => '换牌靴';
  @override
  String get level => '难度';
  @override
  String kitLevel(KitLevel level) => switch (level) {
        KitLevel.easy => '简单',
        KitLevel.medium => '中等',
        KitLevel.hard => '困难',
      };
  @override
  String get bots => '电脑';
  @override
  String get custom => '自定义';
  @override
  String get coach => '教练';
  @override
  String winChance(String pct) => '胜率 $pct';
  @override
  String pointsValue(String x) => '$x 分';
  @override
  String betsValue(String x) => '$x 注';
  @override
  String net(String x) => '净 $x';
  @override
  String moveNumber(int n) => '第$n手';
  @override
  String get pass => '过';
  @override
  String trick(int n) => '第$n轮';
  @override
  String get allCards => '所有手牌';
  @override
  String handOrder(HandOrder order) => switch (order) {
        HandOrder.rank => '点数',
        HandOrder.suit => '花色',
        HandOrder.own => '排序',
      };
  @override
  String get showCards => '显示手牌';
  @override
  String get visibleToAll => '所有人都能看到这张牌';
  @override
  String rangeTitle(String name, int cards) => '$name · $cards 张';
  @override
  String get rangeRanks => '可能的手牌';
  @override
  String get rangeCombos => '可能的牌型';
  @override
  String get rangeWorking => '计算中…';
  @override
  String get rangeFailed => '无法计算。请再点一次座位。';
  @override
  String get rangeNone => '现在没有范围可计算。';
  @override
  String rangeSamples(int n) => '基于 $n 种可能的牌局，只用你看到的信息。';
  @override
  String get playTo => '打到';
  @override
  String get noLimit => '不限';
  @override
  String get scaleWithPlayers => '随人数调整';
  @override
  String get scores => '比分';
  @override
  String get total => '总分';
  @override
  String get newMatch => '新比赛';
  @override
  String dealNumber(int n) => '第$n局';
  @override
  String target(int points) => '目标 $points';
  @override
  String get youWinMatch => '你赢得比赛';
  @override
  String winsMatch(String name) => '$name赢得比赛';
  @override
  String matchTie(List<String> names) => '平局：${names.join('、')}';
  @override
  String term(KitTerm term) => switch (term) {
        KitTerm.training => '训练',
        KitTerm.freePlay => '自由对局',
        KitTerm.coach => '教练',
        KitTerm.grades => '评级',
        KitTerm.score => '得分',
        KitTerm.level => '难度',
        KitTerm.lastGame => '上一局',
        KitTerm.showCards => '显示手牌',
        KitTerm.range => '范围',
        KitTerm.playTo => '打到',
      };
  @override
  String definition(KitTerm term) => switch (term) {
        KitTerm.training => '你的每一步都与教练对比评级并打分。开局前选择。',
        KitTerm.freePlay => '不评级，没有教练。开局前选择。',
        KitTerm.coach => '显示当前局面的最佳着法及各自的价值。顶部的按钮可显示或隐藏。',
        KitTerm.grades => '最佳、良好、不精确、失误、严重失误：一步比教练的最佳选择损失多少。',
        KitTerm.score => '每步评级 0 到 100 分：毫无损失为 100 分。面板显示你的平均分。',
        KitTerm.level => '电脑的水平。',
        KitTerm.lastGame => '你最近的一局，每步后自动保存，可逐步回顾。',
        KitTerm.showCards => '仅限训练：对手的牌正面朝上，方便学习。教练和评级从不使用它们。在菜单里。',
        KitTerm.range => '根据你看到的牌，对手可能拿着什么：每个点数有 1 张以上、2 张以上、3 张以上或 4 张的概率，'
            '以及每种牌型的概率。点对手的座位查看。',
        KitTerm.playTo => '一场比赛打很多局，分数累加，直到有人达到这个总分。'
            '随人数调整：人多时提高目标（人少时降低），人多时比赛不会更早结束。',
      };
}
