import '../../../../games/gomoku/gomoku.dart';
import 'gomoku_strings.dart';

/// Gomoku in Chinese (the terms Chinese gomoku players use: 活四, 冲四,
/// 活三, 四三, 禁手, 长连...).
class GomokuStringsZh extends GomokuStrings {
  const GomokuStringsZh();

  @override
  String get pickLabel => '最佳着法';

  @override
  String get you => '玩家';

  @override
  String color(Stone stone) => switch (stone) {
    Stone.black => '黑棋',
    Stone.white => '白棋',
  };

  @override
  String get place => '落子';

  @override
  String get pass => '弃权';

  @override
  String winsIn(int moves) => '$moves步胜';

  @override
  String losesIn(int moves) => '$moves步负';

  @override
  String reason(MoveReason reason) => switch (reason) {
    MoveReason.makesFive => '成五',
    MoveReason.makesOpenFour => '活四',
    MoveReason.makesDoubleFour => '双四',
    MoveReason.makesFourThree => '四三',
    MoveReason.makesFour => '冲四',
    MoveReason.makesDoubleThree => '双三',
    MoveReason.makesOpenThree => '活三',
    MoveReason.blocksFour => '挡住冲四',
    MoveReason.blocksOpenThree => '防住活三',
    MoveReason.blocksFourThree => '抢占对方四三点',
    MoveReason.blocksDoubleThree => '抢占对方双三点',
    MoveReason.startsForcedWin => '必胜',
    MoveReason.missesForcedWin => '错过必胜',
    MoveReason.allowsForcedWin => '让对方必胜',
    MoveReason.ignoresFour => '没挡冲四',
    MoveReason.ignoresOpenThree => '没防活三',
    MoveReason.mustPass => '只能弃权',
  };

  @override
  String get rule => '规则';

  @override
  String get board => '棋盘';

  @override
  String get random => '随机';

  @override
  String ruleName(WinRule rule) => switch (rule) {
    WinRule.freestyle => '无禁手',
    WinRule.standard => '标准',
    WinRule.renju => '连珠',
  };

  @override
  String get threats => '棋型';

  @override
  String figureTitle(GomokuFigure figure) => switch (figure) {
    GomokuFigure.five => '五连',
    GomokuFigure.openFour => '活四',
    GomokuFigure.four => '冲四',
    GomokuFigure.openThree => '活三',
    GomokuFigure.brokenThree => '跳三',
    GomokuFigure.fourThree => '四三',
    GomokuFigure.doubleThree => '双三',
    GomokuFigure.doubleFour => '双四',
    GomokuFigure.vcf => 'VCF',
    GomokuFigure.forbiddenThree => '禁手：双三',
    GomokuFigure.forbiddenFour => '禁手：双四',
    GomokuFigure.forbiddenOverline => '禁手：长连',
  };

  @override
  String figureCaption(GomokuFigure figure) => switch (figure) {
    GomokuFigure.five => '五子连成一线即胜。',
    GomokuFigure.openFour => '两个成五点（圆点），挡不住。',
    GomokuFigure.four => '只有一个成五点（圆点），必须马上挡。',
    GomokuFigure.openThree => '任一圆点都能成活四：现在就要挡住一头。',
    GomokuFigure.brokenThree => '中间有空的活三：下在圆点就成活四。',
    GomokuFigure.fourThree => '白棋必须在圆点挡冲四，之后活三变成活四。',
    GomokuFigure.doubleThree => '同时形成两个活三：白棋只能挡一个。',
    GomokuFigure.doubleFour => '同时形成两个冲四（圆点）：白棋只能挡一个。',
    GomokuFigure.vcf => '黑棋只用冲四取胜：每步都逼白棋应（2、4、6），直到第7手成五。',
    GomokuFigure.forbiddenThree => '连珠：黑棋不能下在×（双三）。',
    GomokuFigure.forbiddenFour => '连珠：黑棋不能下在×（双四）。',
    GomokuFigure.forbiddenOverline => '连珠：黑棋不能下在×（六子连线）。',
  };

  @override
  String term(GomokuTerm term) => switch (term) {
    GomokuTerm.bestMove => '最佳着法',
    GomokuTerm.provenWin => 'N步胜',
    GomokuTerm.five => '五连',
    GomokuTerm.openFour => '活四',
    GomokuTerm.four => '冲四',
    GomokuTerm.openThree => '活三',
    GomokuTerm.brokenThree => '跳三',
    GomokuTerm.fourThree => '四三',
    GomokuTerm.doubleThree => '双三',
    GomokuTerm.doubleFour => '双四',
    GomokuTerm.vcf => 'VCF',
    GomokuTerm.overline => '长连',
    GomokuTerm.forbiddenMove => '禁手',
    GomokuTerm.freestyle => '无禁手',
    GomokuTerm.standard => '标准',
    GomokuTerm.renju => '连珠',
    GomokuTerm.firstMove => '先手优势',
  };

  @override
  String definition(GomokuTerm term) => switch (term) {
    GomokuTerm.bestMove => '教练的推荐：它评价最高的一手。已证明的必胜总是排在最前。棋盘上会给教练的前几手标上数字。',
    GomokuTerm.provenWin => '教练已证明必胜：无论对方怎么下，你在N手之内成五。“N步负”：对方有必胜。',
    GomokuTerm.five => '五颗棋子横、竖或斜连成一线：获胜。',
    GomokuTerm.openFour => '两端都空的四连。挡不住：下一手就成五。',
    GomokuTerm.four => '再下一手就能成五的四颗棋子。对方必须马上挡住那个点。',
    GomokuTerm.openThree => '能变成活四的三连。必须应对，否则会输。',
    GomokuTerm.brokenThree => '中间隔一个空点的活三。填上空点就成活四。',
    GomokuTerm.fourThree => '一手同时形成冲四和活三。对方挡住冲四后，活三变成活四：获胜。',
    GomokuTerm.doubleThree => '一手同时形成两个活三。连珠规则下黑棋禁止。',
    GomokuTerm.doubleFour => '一手同时形成两个冲四：只能挡住一个。连珠规则下黑棋禁止。',
    GomokuTerm.vcf => '连续冲四取胜：只用冲四，每步都逼对方挡，直到成五。',
    GomokuTerm.overline => '六子或更多连成一线。无禁手规则下获胜；标准规则下不算，连珠规则下黑棋也不算。',
    GomokuTerm.forbiddenMove => '连珠规则：黑棋在此会形成双三、双四或长连的点。黑棋不能下在这里，除非同时成五。用×标出。',
    GomokuTerm.freestyle => '五子或更多连成一线即胜，双方都一样。',
    GomokuTerm.standard => '恰好五子连线才胜。长连不算，对局继续。',
    GomokuTerm.renju => '比赛规则：黑棋有禁手，必须恰好成五；白棋五子或更多都算胜。',
    GomokuTerm.firstMove => '黑棋先走，优势很大：无禁手规则下，完美的下法黑棋必胜。白棋更难下。连珠的禁手削弱了这个优势，但黑棋仍占优。',
  };

  @override
  List<(String, String)> get rulesSections => const [
    ('对局', '双方轮流在空点上落一子，黑棋先走。棋子落下后不再移动，也不会被吃掉。'),
    ('获胜', '先在横、竖或斜方向连成五子的一方获胜。'),
    ('无禁手', '五子或更多连成一线即胜。'),
    ('标准', '恰好五子才胜。六子或更多（长连）不算胜，对局继续。'),
    ('连珠', '黑棋必须恰好成五，且不能下出双三、双四或长连：这些点是禁手（×），除非这一手同时成五。白棋没有禁手，五子或更多都算胜。如果所有空点都是禁手，黑棋只能弃权。'),
    ('和棋', '棋盘下满仍无人成五，判为和棋。'),
    ('坐标', '列用字母从左往右，行用数字从下往上：h8是天元。'),
  ];
}
