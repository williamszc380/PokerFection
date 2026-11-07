import '../bots/bot.dart';
import '../engine/events.dart';
import '../engine/hand_evaluator.dart';
import '../engine/rules.dart';
import '../gto/preflop/preflop_charts.dart';
import '../gto/hand_read.dart';
import '../gto/spot_strategy.dart';
import '../online/protocol.dart' show CloseReason, JoinError;
import '../online/peer_status.dart' show PeerPhase, PeerStatus, PeerTrouble;
import '../ui/table_controller.dart' show OnlineNotice, PlaybackSpeed;
import '../app/app_settings.dart' show BoardStyle, StoneStyle;
import 'strings.dart';

class StringsZh extends S {
  const StringsZh();

  @override
  String get play => '开始游戏';
  @override
  String get settings => '设置';

  @override
  String get holdem => '德州扑克';
  @override
  String get gomoku => '五子棋';
  @override
  String get bigTwo => '锄大地';
  @override
  String get fightTheLandlord => '斗地主';
  @override
  String get blackjack => '二十一点';
  @override
  String get soon => '即将推出';
  @override
  String get general => '通用';
  @override
  String get cardsAndTable => '牌与牌桌';
  @override
  String get boardAndStones => '棋盘与棋子';
  @override
  String get boardColor => '棋盘';
  @override
  String get stoneLook => '棋子';
  @override
  String boardStyle(BoardStyle style) => switch (style) {
        BoardStyle.lightWood => '浅色木纹',
        BoardStyle.darkWood => '深色木纹',
        BoardStyle.green => '绿色',
        BoardStyle.gray => '灰色',
      };
  @override
  String stoneStyle(StoneStyle style) => switch (style) {
        StoneStyle.glossy => '光泽',
        StoneStyle.flat => '扁平',
      };

  @override
  String get handRankings => '牌型大小';
  @override
  String oneIn(String x) => '$x 分之 1';
  @override
  String get rankingOddsNote => '用 7 张牌（你的 2 张加公共牌 5 张）最终组成每种牌型的概率。';
  @override
  String get invite => '邀请';
  @override
  String get copyInviteLink => '复制邀请链接';
  @override
  String get noInvite => '剪贴板里没有邀请或房间号。';
  @override
  String get inviteThisComputer => '这个服务器在这台电脑上，只有这台电脑能加入。';
  @override
  String get pasteBlocked => '此页面无法读取剪贴板：请直接粘贴到输入框中（Ctrl+V）。';
  @override
  String get roomCodeOrLink => '房间号或邀请链接';
  @override
  String get emptyToCreate => '留空则创建房间。';
  @override
  String get joinRoom => '加入房间';
  @override
  String get notACode => '这不是房间号或邀请链接。';
  @override
  String get royalFlush => '皇家同花顺';
  @override
  String handCategory(HandCategory category) => switch (category) {
        HandCategory.highCard => '高牌',
        HandCategory.pair => '一对',
        HandCategory.twoPair => '两对',
        HandCategory.trips => '三条',
        HandCategory.straight => '顺子',
        HandCategory.flush => '同花',
        HandCategory.fullHouse => '葫芦',
        HandCategory.quads => '四条',
        HandCategory.straightFlush => '同花顺',
      };

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
  String get simple => '简单';
  @override
  String get advanced => '进阶';
  @override
  String get freePlay => '自由对局';
  @override
  String get editTable => '编辑牌桌';
  @override
  String get multiplayer => '多人';
  @override
  String get guides => '指南';
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
  String get preflop => '翻牌前';
  @override
  String get postflop => '翻牌后';
  @override
  String get cancel => '取消';
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
  String get checkFold => '过牌/弃牌';
  @override
  String get callAny => '跟任何注';
  @override
  String get playsAtYourTurn => '轮到你时自动执行';
  @override
  String get potWord => '底池';

  @override
  String potOdds(int percent) => '底池赔率 $percent%';
  @override
  String get showGto => '显示 GTO';
  @override
  String get approxMultiway => '近似答案：多人底池';
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
  String mistakeReason(MistakeKind kind, SpotActionKind gto, String amount) {
    final move = switch (gto) {
      SpotActionKind.fold => '弃牌',
      SpotActionKind.check => '过牌',
      SpotActionKind.call => '跟注',
      SpotActionKind.raise => '加注到 $amount',
      SpotActionKind.allIn => '全下',
    };
    return switch (kind) {
      MistakeKind.tooTight => '太紧：GTO 在这里$move。',
      MistakeKind.tooLoose => '太松：GTO 在这里$move。',
      MistakeKind.tooPassive => '太被动：GTO 在这里$move。',
      MistakeKind.tooAggressive => '太激进：GTO 在这里$move。',
      MistakeKind.wrongSize => '方向对了，尺度不对：GTO $move。',
    };
  }
  @override
  String mistakeWhy(Reason r, String hand) => switch (r.kind) {
        ReasonKind.behind =>
          '对手 ${r.percent}% 的牌比你大${r.threat == null ? '' : '，大多是${_threats(r.threat!)}'}。',
        ReasonKind.ahead => '你的牌比对手 ${r.percent}% 的牌大。',
        ReasonKind.potOdds => '跟注只需要 ${r.odds}% 的胜率，而你比对手 ${r.percent}% 的牌大。',
        ReasonKind.potOddsPreflop => '跟注只需要 ${r.odds}% 的胜率。',
        ReasonKind.flushDraw => '你有同花听牌。',
        ReasonKind.straightDraw => '你有顺子听牌。',
        ReasonKind.bluff => '作为诈唬：加注能让更好的牌弃牌。',
        ReasonKind.keepWorseIn => '加注会让更差的牌弃牌；不加注能留住它们。',
        ReasonKind.strongStart => '$hand 属于前 ${r.percent}% 的起手牌。',
        ReasonKind.weakStart => '$hand 属于最差的 ${r.percent}% 起手牌。',
      };

  static String _threats(HandCategory c) => switch (c) {
        HandCategory.highCard => '更大的高牌',
        HandCategory.pair => '更大的对子',
        HandCategory.twoPair => '两对',
        HandCategory.trips => '三条',
        HandCategory.straight => '顺子',
        HandCategory.flush => '同花',
        HandCategory.fullHouse => '葫芦',
        HandCategory.quads => '四条',
        HandCategory.straightFlush => '同花顺',
      };
  @override
  String unavailable(Unavailable reason) => switch (reason) {
        Unavailable.checkIsFree => '可以免费过牌',
        Unavailable.raisingNotAllowed => '不能加注',
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
  String get playOnline => '在线对战';
  @override
  String get yourName => '你的名字';
  @override
  String get enterName => '请输入名字';
  @override
  String get createRoom => '创建房间';
  @override
  String get roomCode => '房间码';
  @override
  String get join => '加入';
  @override
  String get server => '服务器';
  @override
  String get serverHint => '留空：房间运行在房主的设备上。';
  @override
  String get startingRoom => '正在开启房间…';
  @override
  String get cantStartRoom => '无法在这台设备上开启房间。';
  @override
  String get cantHostInBrowser => '这个浏览器不能主持房间。可以在这里加入房间，或在应用中主持。';
  @override
  String get roomNotNearby => '找不到房间：请检查房间号和网络连接。';
  @override
  String get noDirectRoute => '无法从这个网络直接连接到房主。请换一个网络（例如用 Wi-Fi 代替移动数据），或在同一 Wi-Fi 下游戏。';
  @override
  String get cantReachServer => '无法连接到服务器';
  @override
  String get wsOnWebsite => '此网站无法使用 ws:// 服务器。请使用 wss://，或清空服务器。';
  @override
  String sameWifi(bool yes) => yes ? '同一 Wi-Fi：可以' : '同一 Wi-Fi：没有网络';
  @override
  String get sameWifiAppOnly => '同一 Wi-Fi：仅限应用';
  @override
  String internetStatus(PeerStatus status) => switch (status.phase) {
        PeerPhase.starting => '互联网：连接中…',
        PeerPhase.ready => '互联网：就绪',
        PeerPhase.unavailable => switch (status.trouble) {
            PeerTrouble.codeTaken => '互联网：不可用（繁忙：请新建房间）',
            PeerTrouble.unsupported => '互联网：此设备上不可用',
            _ => '互联网：不可用（无连接）',
          },
      };
  @override
  String internetHelp({required PeerStatus status, required bool windows, required bool phone, bool browser = false}) => [
        if (status.phase == PeerPhase.unavailable)
          switch (status.trouble) {
            PeerTrouble.codeTaken => '配对服务无法为这个房间分配名称。请为其他地方的朋友新建一个房间。',
            PeerTrouble.unsupported => '这个版本的应用无法通过互联网连接。',
            _ => '无法连接到配对服务（没有网络？）。应用会继续尝试。',
          },
        '任何地方的朋友都可以用房间号或邀请加入。',
        '一个免费的公共配对服务帮设备互相找到对方，之后游戏在设备之间直接进行，并且加密。',
        if (browser) '有些网络（常见于移动数据）无法直接连接。没有互联网时，只有在应用中主持的房间才能在同一 Wi-Fi 下连接。' else '有些网络（常见于移动数据）无法直接连接。同一 Wi-Fi 下总能连上，即使没有互联网。',
        if (browser) '主持期间请保持此标签页打开：关闭标签页，房间也会关闭。',
        if (windows) '第一次时，Windows 防火墙会询问 PokerFection 能否使用网络：请允许。',
        if (phone) '主持期间请让应用保持在屏幕上：应用关闭或进入后台时，房间会停止。',
      ].join('\n\n');
  @override
  String get connecting => '正在连接…';
  @override
  String joinError(JoinError? error) => switch (error) {
        JoinError.upgrade => '请更新应用后再玩',
        JoinError.roomNotFound => '找不到房间',
        JoinError.roomFull => '房间已满',
        JoinError.rateLimited => '尝试太多次：请等一分钟',
        JoinError.serverFull => '服务器已满：请稍后再试',
        JoinError.internal => '服务器出错',
        JoinError.roomGone => '房间已关闭',
        JoinError.seatGone => '离开太久：请重新加入',
        JoinError.removed => '房主已将你移出房间',
        null => '无法连接到房间',
      };
  @override
  String room(String code) => '房间 $code';
  @override
  String get copied => '已复制';
  @override
  String get shareCode => '朋友用这个房间号或邀请加入。';
  @override
  String get host => '房主';
  @override
  String get botBadge => '机器人';
  @override
  String get awayBadge => '暂离';
  @override
  String get leftBadge => '已离开';
  @override
  String get nextHandBadge => '下一手';
  @override
  String get help => '辅助';
  @override
  String get noHelp => '无';
  @override
  String get timeLimit => '时限';
  @override
  String turnLimit(int seconds) => seconds == 0 ? '不限' : '$seconds 秒';
  @override
  String secondsLeft(int seconds) => '$seconds 秒';
  @override
  String get waitingForHost => '等待房主…';
  @override
  String get joinNextHand => '你将在下一手入座。';
  @override
  String nextHandIn(int seconds) => '下一手 $seconds 秒后开始';
  @override
  String onlineNotice(OnlineNotice notice) => switch (notice) {
        OnlineNotice.timesUp => '时间到',
        OnlineNotice.refused => '不允许：请重新选择',
        OnlineNotice.outOfSync => '不同步',
      };
  @override
  String get hostAway => '房主暂离：机器人只会过牌或弃牌。';
  @override
  String get connectionLost => '连接已断开';
  @override
  String get reconnecting => '正在重新连接…';
  @override
  String rejoinRoom(String code) => '回到房间 $code';
  @override
  String closed(CloseReason? reason) => switch (reason) {
        CloseReason.roomClosed => '房主关闭了房间。',
        CloseReason.serverRestart => '服务器已重启。',
        CloseReason.replaced => '你的座位已转到另一个窗口。',
        CloseReason.roomError => '房间因出错而关闭。',
        CloseReason.idle => '房间已关闭：很久没有发牌了。',
        CloseReason.removed => '房主已将你移出房间。',
        null => '房间已关闭。',
      };
  @override
  String get closeRoom => '关闭房间';
  @override
  String get tableSettings => '牌桌';
  @override
  String get fromNextHand => '更改从下一手开始生效。';
  @override
  String get leave => '离开';
  @override
  String get leaveTable => '离开牌桌？';
  @override
  String leaveWarning({required bool host}) => host ? '房间将对所有人关闭。' : '从下一手起你的座位将空出。';
  @override
  String get seats => '座位数';
  @override
  String get emptySeat => '空座位';
  @override
  String get addBot => '添加机器人';
  @override
  String get removeBot => '移除';
  @override
  String get leavingBadge => '下一手离开';
  @override
  String get needPlayers => '一手牌至少需要 2 名玩家：邀请朋友或添加机器人。';
  @override
  String get waitingForPlayers => '等待玩家（至少 2 名）';
  @override
  String get joinGame => '加入游戏';
  @override
  String get leaveSeat => '离座';
  @override
  String get spectators => '观众';
  @override
  String get spectatorsSeeBots => '观众可看机器人的牌';
  @override
  String get seatList => '座位';
  @override
  String get game => '游戏';
  @override
  String get endGame => '结束游戏';
  @override
  String get nextGameBadge => '下一局';
  @override
  String get updateToWatch => '更新应用后观看';
  @override
  String get leaveRoom => '离开房间';
  @override
  String get leaveRoomQuestion => '离开房间？';
  @override
  String get closeRoomQuestion => '关闭房间？';
  @override
  String get leaveSeatQuestion => '离开座位？';
  @override
  String get leaveSeatWarning => '先打完这一手。';
  @override
  String get pickGame => '选择游戏';
  @override
  String get waitingForGame => '等待房主选择游戏';
  @override
  String get seatsAfterGame => '选好游戏后出现座位。';
  @override
  String inRoom(String code) => '你在房间 $code 中。';
  @override
  String get leaveSeatWarningRound => '先打完这一局。';
  @override
  String needSeats(int n) => '这个游戏需要 $n 名玩家：邀请朋友或添加机器人。';
  @override
  String get people => '成员';
  @override
  String get playingNow => '在玩';
  @override
  String get pickGameOnHome => '在主页选择游戏。';
  @override
  String get onlineSoon => '即将联机';
  @override
  String get sit => '坐下';
  @override
  String get openTable => '打开牌桌';
  @override
  String get endGameFirst => '请先结束当前游戏。';
  @override
  String roomSetupNote(String code) => '房间 $code：将为房间里的所有人打开这个游戏。';
  @override
  String get about => '关于';
  @override
  String versionNumber(String version) => '版本 $version';
  @override
  String buildCommits(int commits, {required bool changed}) =>
      changed ? '构建：$commits 次提交（含本地改动）' : '构建：$commits 次提交';
  @override
  String get devBuild => '构建：开发版';
  @override
  String madeBy(String name) => '作者：$name';
  @override
  String gamesList(String list) => '游戏：$list';
  @override
  String onlineRooms(int protocol) => '点对点在线房间（协议 v$protocol）';
  @override
  String runningOn(String platform) => '运行于 $platform';
  @override
  String get showMyCards => '亮出我的牌';
  @override
  String showNotice(String? name, String cards) => name == null ? '你亮牌：$cards' : '$name 亮牌：$cards';
  @override
  String helpNotice(String? name) => name == null ? '你使用了 GTO 辅助' : '$name 使用了 GTO 辅助';
  @override
  String get rulesChanged => '房主更改了规则（从下一手开始）。';
  @override
  String get rebuys => '重新买入';
  @override
  String get outBadge => '出局';
  @override
  String outOfChips({required bool rebuys}) => rebuys ? '你的筹码输光了。' : '你的筹码输光了：观战直到本局游戏结束。';
  @override
  String rebuy(String stack) => '重新买入 $stack';
  @override
  String get lobby => '房间';
  @override
  String get watch => '观战';
  @override
  String gameOver(String? winner, {bool you = false}) =>
      you ? '游戏结束：你赢了！' : (winner == null ? '游戏结束' : '游戏结束：$winner 获胜');
  @override
  String get sitOut => '留座离桌';
  @override
  String get imBack => '我回来了';
  @override
  String get sittingOutBadge => '留座离桌';
  @override
  String get sitOutNextHand => '从下一手起你留座离桌。';
  @override
  String get youSitOut => '你正在留座离桌：不会给你发牌。';
  @override
  String get removePlayer => '移出';
  @override
  String removePlayerQuestion(String name) => '将 $name 移出房间？';
  @override
  String get removePlayerWarning => '对方将无法再加入这个房间。如果正在一手牌中，会在这手牌结束时离开。';
  @override
  String removedNotice(String name) => '$name 已被移出房间';
  @override
  String get chat => '聊天';
  @override
  String get chatHint => '消息';
  @override
  String get send => '发送';
  @override
  String get noMessages => '还没有消息';
  @override
  String get chatTooFast => '太快了：请稍等';
  @override
  String get drills => '错题练习';
  @override
  String drillsDue(int due) => due == 0 ? '错题练习' : '错题练习（$due 个待复习）';
  @override
  String savedToDrills(String wait, {required bool again}) =>
      again ? '已在错题练习中：$wait后再练' : '已存入错题练习：$wait后首次复习';
  @override
  String drillQueued(String wait, {required bool? right}) => switch (right) {
        true => '✓ 下次复习：$wait后',
        false => '$wait后再练',
        null => '未评分：下次复习在$wait后',
      };
  @override
  String drillSpot(String grade, int due) => '已存局面（$grade）· $due 个待复习';
  @override
  String randomHands(String? next) =>
      next == null ? '还没有存下的错题。正在发随机牌局。' : '全部完成！下次复习在$next后。正在发随机牌局。';
  @override
  String get noSavedMistakes => '还没有存下的错题';
  @override
  String get playRandomHands => '玩随机牌局';
  @override
  String get savedSpots => '已存局面';
  @override
  String get dueNow => '现在复习';
  @override
  String reviewIn(String wait) => '$wait后';
  @override
  String waitTime(int count, WaitUnit unit) => switch (unit) {
        WaitUnit.minutes => '$count 分钟',
        WaitUnit.hours => '$count 小时',
        WaitUnit.days => '$count 天',
        WaitUnit.weeks => '$count 周',
        WaitUnit.months => '$count 个月',
        WaitUnit.years => '$count 年',
      };

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
        GlossarySection.online => '在线',
      };

  @override
  String term(GlossaryTerm term) => positionTerms[term] ?? switch (term) {
        GlossaryTerm.training => 'GTO 训练',
        GlossaryTerm.play => '自由对局',
        GlossaryTerm.drills => '错题练习',
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
        GlossaryTerm.preActions => '预选操作',
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
        GlossaryTerm.roomCode => '房间码',
        GlossaryTerm.roomStays => '留在房间',
        GlossaryTerm.host => '房主',
        GlossaryTerm.hosting => '主持房间',
        GlossaryTerm.onlineBots => '机器人',
        GlossaryTerm.timeLimit => '时限',
        GlossaryTerm.helpLevel => '辅助',
        GlossaryTerm.roomGame => '游戏',
        GlossaryTerm.spectators => '观众',
        GlossaryTerm.seeBots => '机器人的牌',
        GlossaryTerm.rebuys => '重新买入',
        GlossaryTerm.sitOut => '留座离桌',
        GlossaryTerm.chat => '聊天',
        GlossaryTerm.away => '暂离',
        _ => term.name,
      };

  @override
  String definition(GlossaryTerm term) => switch (term) {
        GlossaryTerm.training => '与机器人对战，向 GTO 学习。简单：正常打牌；出现失误或严重失误时会显示 GTO 的答案，'
            '随时可以用“显示 GTO”查看。进阶：在每个决策点设定你认为 GTO 弃牌、跟注、加注（以及加注多少）的频率，'
            '然后查看 GTO 的答案和你的得分。在设置游戏时选择。翻牌前机器人按 GTO 打法行动；翻牌后才按'
            '它们各自的风格行动。',
        GlossaryTerm.play => '与机器人对战，不计分，就像真实牌局。',
        GlossaryTerm.drills => '你在 GTO 训练（简单或进阶）中的每个失误或严重失误都会存为一个局面：同一手牌，直到那个决策。'
            '“错题练习”会重新发出到期的局面，最逾期的先来，并像简单训练一样给你的打法评分；打完之前不能用“显示 GTO”。'
            '打对了（良好或更好），这个局面会越来越晚才回来：1 小时、1 天、3 天、1 周，之后每次约延长 2.5 倍。'
            '打错了（或在训练中再犯同样的失误），10 分钟后再练。局面无论练得多熟都会保留，最多 256 个：存满时先移除最熟的。'
            '没有到期的局面时，错题练习会在随机牌桌上发随机牌局，其中的失误也会加入错题练习。“☰ > 已存局面”列出全部局面。',
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
        GlossaryTerm.betSizes => '翻牌前后都用同一个规则给出加注尺度：以大盲计的斐波那契数，1、2、3、5、8、13、21、34、55 BB 等'
            '（加注到的总额），从最小加注一直到全下。100 BB 第一个入池时：2、3、5、8、13、21、34、55 和 89 BB，另加“全下”。'
            '全下按仍在牌局中的玩家最多能跟的数额计算。翻牌前每个尺度也显示为下注的倍数，翻牌后显示为底池的倍数。',
        GlossaryTerm.fold => '放弃这手牌以及已经投入底池的筹码。',
        GlossaryTerm.check => '不下注，把行动交给下一位（只能在没人下注时）。',
        GlossaryTerm.call => '跟上当前的下注额。',
        GlossaryTerm.betRaise => '先投入筹码（下注），或投入比当前下注更多的筹码（加注）。',
        GlossaryTerm.open => '翻牌前的第一次加注。',
        GlossaryTerm.limp => '翻牌前只跟大盲注而不加注。',
        GlossaryTerm.threeBet => '翻牌前的后续加注：大盲注算第一注，开池算第二注，所以再加注就是 3-bet，依此类推。',
        GlossaryTerm.preActions => '其他玩家行动时，可以预先勾选你的操作：过牌/弃牌（能免费过牌就过牌，否则弃牌）、过牌（有人下注就取消）、'
            '跟注所示金额（下注额变化就取消）或跟任何注。轮到你时立即执行；再点一次可取消。只在本条街有效。简单训练中照样评分；'
            '进阶训练没有此功能（需要设置百分比）。在线游戏时能让牌局更快。',
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
        GlossaryTerm.evLoss => '与 GTO 自己的混合策略相比，你的百分比损失了多少 BB。EV 损失一栏是每个行动与最佳行动的差距。',
        GlossaryTerm.mixMatch => '你的百分比与 GTO 的接近程度：100% 表示完全一致。',
        GlossaryTerm.score => '0 到 100 分。简单：每次行动 100 分，每损失 0.01 BB 扣 1 分。进阶：一半看匹配度，'
            '一半看 EV 损失是否小；关键是弃牌、过牌或跟注、加注的频率，加注尺度只占 10%。历史记录中，白色边框'
            '表示进阶模式下的手牌。',
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
        GlossaryTerm.roomCode => '标识在线房间的五个字符。朋友在“在线对战”中用它加入。',
        GlossaryTerm.host => '创建房间的玩家：房间运行在其设备上。房主选择游戏，设置牌桌、辅助和时限，开始游戏，并操控机器人。'
            '房主可以移出任何人：在房间里（牌桌上是“☰ > 房间”）点击其名字，再选“移出”。对方立即离开（如果正在一手牌中，'
            '则在这手结束时），并且无法再加入这个房间。房主按“关闭房间”或退出应用时，房间结束。',
        GlossaryTerm.roomStays => '你在房间里时，房间的成员和聊天会一直停在每个界面的右侧：玩游戏、看指南或改设置，你都还在房间里。'
            '“离开房间”让你退出；房主的“关闭房间”会为所有人结束房间。',
        GlossaryTerm.roomGame => '房主像平时一样选游戏：在主页点一个游戏，再点“开始游戏”。房间里的所有人都会来到它的牌桌，座位就在那里：'
            '点“坐下”占一个座位。换一个游戏会让所有人回到观看。灰色的：暂时还不能在线玩。',
        GlossaryTerm.spectators => '每个人进入房间时都是观众，可以看到每位真人玩家的牌和打法风格。“教练”显示当前行动者的最佳打法。'
            '“加入游戏”会为下一轮占一个座位。',
        GlossaryTerm.seeBots => '由房主决定：观众也能看到机器人的牌，从下一轮开始。',
        GlossaryTerm.hosting => '“创建房间”会在你的设备上开启房间：游戏通过房主的应用进行，不需要我们的游戏服务器。朋友用房间号'
            '或邀请加入：同一 Wi-Fi 下即使没有互联网也可以；在其他地方，一个免费的公共配对服务帮设备互相找到对方，之后游戏在'
            '设备之间直接进行，并且加密（有些网络，常见于移动数据，无法直接连接）。没有应用的朋友可以通过邀请在浏览器中玩。'
            '房主按“关闭房间”或退出应用时，房间结束。也可以在浏览器中主持：这时所有人都通过互联网加入，关闭标签页房间就会关闭。',
        GlossaryTerm.onlineBots => '新房间还没有游戏；房主选好游戏后才出现座位，全都是空的。“加入游戏”会坐到空座位上'
            '（或机器人的座位：机器人让座），房主可以添加机器人（各有打法风格）或将其移除。每手牌只发给有人的座位，'
            '所以至少需要 2 名玩家；人数不够时游戏会等待。一手牌进行中加入、离开、添加或移除机器人都从下一手开始生效。',
        GlossaryTerm.timeLimit => '每位玩家做决定的时间。时间到时，能过牌就自动过牌，否则弃牌。不限：没有时间限制。',
        GlossaryTerm.helpLevel => '房主为全桌选择的辅助：无（像自由对战）、简单或进阶（像 GTO 训练）。'
            '在线时，其他玩家的牌保持隐藏。你的选项会立即显示，GTO 的答案计算完成后加入（计算中…）。'
            '选择后行动立即发出：评分显示时牌桌不会暂停；在答案出来前做出的行动会在答案出来后评分。'
            '有玩家按下“显示 GTO”时，所有人都会收到通知。',
        GlossaryTerm.rebuys => '玩家输光全部筹码后怎么办，由房主设置。开启重新买入：玩家选择“重新买入”（从下一手起再拿到初始筹码）'
            '或“离开”；机器人会自动重新买入。关闭重新买入：玩家出局（座位显示“出局”），可以在牌桌或房间里观战，也可以离开。'
            '只剩一名玩家有筹码、且没有人能重新买入时，游戏结束：所有人回到房间，房主按“开始”用新的筹码开始新一局。'
            '开启“每手重置筹码”时，没有人会输光。',
        GlossaryTerm.sitOut => '“☰ > 留座离桌”：从下一手起不给你发牌，但你保留座位和筹码，并可以观战。'
            '“☰ > 我回来了”从下一手起重新给你发牌。拿到牌的玩家少于 2 个时，游戏会等待。'
            '连接断开整整一手牌的玩家会留座离桌，直到他回来。',
        GlossaryTerm.chat => '房间里的所有人都可以聊天：在房间里，以及游戏中在“房间”标签或“☰ > 聊天”里（输光筹码观战时也可以）。新消息会在牌桌上方'
            '显示片刻，然后淡出；“☰ > 聊天”里有完整的对话和快捷消息（点一下就发送）。每条消息最多 256 个字符，每 8 秒最多 '
            '4 条。房间会保留最近 64 条消息：加入或回来的玩家都能看到。',
        GlossaryTerm.away => '连接断开的玩家会保留座位 2 分钟。在此期间，服务器会在 3 秒后替他过牌或弃牌（整整一手牌都不在的话，'
            '他会留座离桌，直到回来）；能玩的人少于 2 个时，'
            '游戏会等待。他的应用会自动重新连接并跟上这手牌；应用关掉了的话，可以在“在线对战”里回到房间。房主暂离时，'
            '机器人只会过牌或弃牌。在应用里主持的房间会一直等房主回来；在自己的服务器上，房主离开 2 分钟房间就会关闭。',
      };
}
