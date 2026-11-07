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

class StringsEn extends S {
  const StringsEn();

  @override
  String get play => 'Play';
  @override
  String get settings => 'Settings';

  @override
  String get holdem => "Hold'em";
  @override
  String get gomoku => 'Gomoku';
  @override
  String get bigTwo => 'Big Two';
  @override
  String get fightTheLandlord => 'Fight the Landlord';
  @override
  String get blackjack => 'Blackjack';
  @override
  String get soon => 'Soon';
  @override
  String get general => 'General';
  @override
  String get cardsAndTable => 'Cards & Table';
  @override
  String get boardAndStones => 'Board & Stones';
  @override
  String get boardColor => 'Board';
  @override
  String get stoneLook => 'Stones';
  @override
  String boardStyle(BoardStyle style) => switch (style) {
        BoardStyle.lightWood => 'Light Wood',
        BoardStyle.darkWood => 'Dark Wood',
        BoardStyle.green => 'Green',
        BoardStyle.gray => 'Gray',
      };
  @override
  String stoneStyle(StoneStyle style) => switch (style) {
        StoneStyle.glossy => 'Glossy',
        StoneStyle.flat => 'Flat',
      };

  @override
  String get handRankings => 'Hand Rankings';
  @override
  String oneIn(String x) => '1 in $x';
  @override
  String get rankingOddsNote => 'Odds of ending with each hand using 7 cards: your 2 and the 5 on the board.';
  @override
  String get invite => 'Invite';
  @override
  String get copyInviteLink => 'Copy invite link';
  @override
  String get noInvite => 'No invite or room code on the clipboard.';
  @override
  String get inviteThisComputer => 'This server runs on this computer, so only this computer can join.';
  @override
  String get pasteBlocked => "This page can't read the clipboard: paste into the box (Ctrl+V).";
  @override
  String get roomCodeOrLink => 'Room code or invite link';
  @override
  String get emptyToCreate => 'Leave empty to create a room.';
  @override
  String get joinRoom => 'Join Room';
  @override
  String get notACode => "That isn't a room code or invite link.";
  @override
  String get royalFlush => 'Royal Flush';
  @override
  String handCategory(HandCategory category) => switch (category) {
        HandCategory.highCard => 'High Card',
        HandCategory.pair => 'Pair',
        HandCategory.twoPair => 'Two Pair',
        HandCategory.trips => 'Three of a Kind',
        HandCategory.straight => 'Straight',
        HandCategory.flush => 'Flush',
        HandCategory.fullHouse => 'Full House',
        HandCategory.quads => 'Four of a Kind',
        HandCategory.straightFlush => 'Straight Flush',
      };

  @override
  String get preflopCharts => 'Preflop Charts';
  @override
  String get spot => 'Spot';
  @override
  String chartSpot(ChartSpot spot) => switch (spot) {
        ChartSpot.open => 'Open',
        ChartSpot.vsOpen => 'vs Open',
        ChartSpot.vs3bet => 'vs 3-Bet',
      };
  @override
  String chartVillain(ChartSpot spot) => spot == ChartSpot.vs3bet ? '3-Bettor' : 'Opener';
  @override
  String get callWord => 'Call';
  @override
  String inRange(int percent) => 'In range: $percent%';
  @override
  String get glossary => 'Glossary';
  @override
  String get animations => 'Animations';
  @override
  String get sound => 'Sound';
  @override
  String get cardBack => 'Card Back';
  @override
  String get cardFaces => 'Card Faces';
  @override
  String get twoColors => '2 Colors';
  @override
  String get fourColors => '4 Colors';
  @override
  String get coloredCards => 'Colored';
  @override
  String get tableColor => 'Table';
  @override
  String speed(PlaybackSpeed speed) => switch (speed) {
        PlaybackSpeed.normal => 'Normal',
        PlaybackSpeed.fast => 'Fast',
        PlaybackSpeed.instant => 'Instant',
      };

  @override
  String get newGame => 'New Game';
  @override
  String get training => 'GTO Training';
  @override
  String get simple => 'Simple';
  @override
  String get advanced => 'Advanced';
  @override
  String get freePlay => 'Free Play';
  @override
  String get players => 'Players';
  @override
  String get editTable => 'Edit Table';
  @override
  String get multiplayer => 'Multiplayer';
  @override
  String get guides => 'Guides';
  @override
  String get stack => 'Stack';
  @override
  String get opponentStyles => 'Opponent Play Styles';
  @override
  String get random => 'Random';
  @override
  String style(BotStyle style) => switch (style) {
        BotStyle.tag => 'TAG',
        BotStyle.lag => 'LAG',
        BotStyle.station => 'Station',
        BotStyle.nit => 'Nit',
        BotStyle.gto => 'GTO',
      };
  @override
  String get showStyles => 'Show Play Styles';
  @override
  String get showCards => 'Show Cards';
  @override
  String get customizeSeats => 'Customize Opponents';
  @override
  String get you => 'Player';
  @override
  String get position => 'Position';
  @override
  String get rotate => 'Rotate';
  @override
  String get resetStacks => 'Reset Stacks Every Hand';
  @override
  String get preflop => 'Preflop';
  @override
  String get postflop => 'Postflop';
  @override
  String get cancel => 'Cancel';
  @override
  String get rules => 'Rules';
  @override
  String get minRaise => 'Min-Raise';
  @override
  String raiseRule(RaiseRule rule) => switch (rule) {
        RaiseRule.standard => 'Standard',
        RaiseRule.bigBlind => '1 BB (House Rule)',
      };
  @override
  String get ante => 'Ante';
  @override
  String get noAnte => 'None';
  @override
  String get start => 'Start';

  @override
  String handsPlayed(int hands) => hands == 1 ? '1 hand' : '$hands hands';
  @override
  String get showAllCards => 'Show Cards';
  @override
  String get hideAllCards => 'Hide Cards';
  @override
  String get ranges => 'Ranges';
  @override
  String get history => 'History';
  @override
  String get shuffleStyles => 'Shuffle Play Styles';
  @override
  String get showRange => 'Range';
  @override
  String get changeStyle => 'Play Style';
  @override
  String get showTheirCards => 'Show Cards';
  @override
  String get hideTheirCards => 'Hide Cards';

  @override
  String get fold => 'Fold';
  @override
  String get check => 'Check';
  @override
  String call(String amount) => 'Call $amount';
  @override
  String raiseTo(String amount, String? size) => 'Raise to $amount${size == null ? '' : ' ($size)'}';
  @override
  String allIn(String amount) => 'All-in $amount';
  @override
  String get allInBadge => 'All-in';
  @override
  String get raiseAnySize => 'Raise';
  @override
  String get checkFold => 'Check/Fold';
  @override
  String get callAny => 'Call Any';
  @override
  String get playsAtYourTurn => 'Plays at your turn';
  @override
  String get potWord => 'pot';

  @override
  String potOdds(int percent) => 'Pot Odds $percent%';
  @override
  String get showGto => 'Show GTO';
  @override
  String get approxMultiway => 'Approximate answer: multiway pot';
  @override
  String get randomize => 'RNG';
  @override
  String get playRandomized => 'Play RNG';
  @override
  String get continueHand => 'Continue';
  @override
  String score(int score) => 'Score $score';
  @override
  String evLossAndMatch(String evLoss, int match) => 'EV Loss $evLoss · Match $match%';
  @override
  String youPlay(String action) => action;
  @override
  String randomized(String action) => 'RNG: $action';
  @override
  String get solvingDecision => 'Solving…';
  @override
  String lateGrade(DecisionGrade grade, Street street) => switch (street) {
        Street.preflop => '${this.grade(grade)} preflop',
        Street.flop => '${this.grade(grade)} on the flop',
        Street.turn => '${this.grade(grade)} on the turn',
        Street.river => '${this.grade(grade)} on the river',
      };
  @override
  String thinking(String name) => '$name…';
  @override
  String get nextHand => 'Next Hand';
  @override
  String get evenHand => '±0 BB';
  @override
  String noAnswer(NoAnswer? reason) => switch (reason) {
        NoAnswer.multiway => 'No GTO answer: multiway pot',
        NoAnswer.leftSolvedLines => 'No GTO answer: off the solved lines',
        NoAnswer.solveFailed => 'No GTO answer: the solver failed',
        NoAnswer.notNeeded || null => 'No GTO answer',
      };
  @override
  String mistakeReason(MistakeKind kind, SpotActionKind gto, String amount) {
    final move = switch (gto) {
      SpotActionKind.fold => 'folds',
      SpotActionKind.check => 'checks',
      SpotActionKind.call => 'calls',
      SpotActionKind.raise => 'raises to $amount',
      SpotActionKind.allIn => 'goes all-in',
    };
    return switch (kind) {
      MistakeKind.tooTight => 'Too tight: GTO $move here.',
      MistakeKind.tooLoose => 'Too loose: GTO $move here.',
      MistakeKind.tooPassive => 'Too passive: GTO $move here.',
      MistakeKind.tooAggressive => 'Too aggressive: GTO $move here.',
      MistakeKind.wrongSize => 'Right move, wrong size: GTO $move.',
    };
  }
  @override
  String mistakeWhy(Reason r, String hand) => switch (r.kind) {
        ReasonKind.behind =>
          '${r.percent}% of their hands beat yours${r.threat == null ? '' : ', mostly ${_threats(r.threat!)}'}.',
        ReasonKind.ahead => 'Your hand beats ${r.percent}% of theirs.',
        ReasonKind.potOdds => 'A call only needs to win ${r.odds}% of the time, and you beat ${r.percent}% of their hands.',
        ReasonKind.potOddsPreflop => 'A call only needs to win ${r.odds}% of the time.',
        ReasonKind.flushDraw => 'You have a flush draw.',
        ReasonKind.straightDraw => 'You have a straight draw.',
        ReasonKind.bluff => 'As a bluff: a raise makes better hands fold.',
        ReasonKind.keepWorseIn => 'Worse hands would fold to a raise; this keeps them in.',
        ReasonKind.strongStart => '$hand is in the top ${r.percent}% of starting hands.',
        ReasonKind.weakStart => '$hand is in the bottom ${r.percent}% of starting hands.',
      };

  static String _threats(HandCategory c) => switch (c) {
        HandCategory.highCard => 'higher cards',
        HandCategory.pair => 'better pairs',
        HandCategory.twoPair => 'two pairs',
        HandCategory.trips => 'three of a kind',
        HandCategory.straight => 'straights',
        HandCategory.flush => 'flushes',
        HandCategory.fullHouse => 'full houses',
        HandCategory.quads => 'four of a kind',
        HandCategory.straightFlush => 'straight flushes',
      };
  @override
  String unavailable(Unavailable reason) => switch (reason) {
        Unavailable.checkIsFree => 'Check is free',
        Unavailable.raisingNotAllowed => "Can't raise",
        Unavailable.notSolved => 'Not in the solved game',
      };
  @override
  String grade(DecisionGrade grade) => switch (grade) {
        DecisionGrade.best => 'Best',
        DecisionGrade.good => 'Good',
        DecisionGrade.inaccuracy => 'Inaccuracy',
        DecisionGrade.mistake => 'Mistake',
        DecisionGrade.blunder => 'Blunder',
      };
  @override
  String get columnYou => 'Player';
  @override
  String get columnGto => 'GTO';
  @override
  String get columnEvLoss => 'EV Loss';

  @override
  String get average => 'Avg';
  @override
  String get all => 'All';
  @override
  String get noScoresYet => 'No scores yet.';
  @override
  String get decisions => 'Decisions';
  @override
  String get averageScore => 'Avg Score';
  @override
  String get evLoss => 'EV Loss';
  @override
  String get net => 'Net';
  @override
  String handNumber(int number) => '#$number';
  @override
  String street(Street street) => switch (street) {
        Street.preflop => 'Preflop',
        Street.flop => 'Flop',
        Street.turn => 'Turn',
        Street.river => 'River',
      };
  @override
  String get close => 'Close';
  @override
  String get ok => 'OK';
  @override
  String get fullGlossary => 'Glossary';

  @override
  String get yourRange => 'Your Range';
  @override
  String get shareOfRange => 'Share of Range';
  @override
  String get frequency => 'Frequency';
  @override
  String get noRange => 'No range here.';

  @override
  String wins(String name, String amount, {required bool you}) => '$name ${you ? 'win' : 'wins'} $amount';
  @override
  String split(String names, String amount) => '$names split $amount';
  @override
  String get mainPot => 'Main pot';
  @override
  String sidePot(int number) => 'Side pot $number';
  @override
  String listNames(List<String> names) =>
      names.length < 2 ? names.join() : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  @override
  String hand(HandValue value) {
    final r0 = rankSymbols[value.rankAt(0)], r1 = rankSymbols[value.rankAt(1)];
    return switch (value.category) {
      HandCategory.straightFlush => value.rankAt(0) == 12 ? 'Royal Flush' : 'Straight Flush, $r0 high',
      HandCategory.quads => 'Quads, ${r0}s',
      HandCategory.fullHouse => 'Full House, ${r0}s over ${r1}s',
      HandCategory.flush => 'Flush, $r0 high',
      HandCategory.straight => 'Straight, $r0 high',
      HandCategory.trips => 'Trips, ${r0}s',
      HandCategory.twoPair => 'Two Pair, ${r0}s and ${r1}s',
      HandCategory.pair => 'Pair of ${r0}s',
      HandCategory.highCard => '$r0 High',
    };
  }

  @override
  String get playOnline => 'Play Online';
  @override
  String get yourName => 'Your Name';
  @override
  String get enterName => 'Enter a name';
  @override
  String get createRoom => 'Create Room';
  @override
  String get roomCode => 'Room Code';
  @override
  String get join => 'Join';
  @override
  String get server => 'Server';
  @override
  String get serverHint => "Empty: rooms run on the host's device.";
  @override
  String get startingRoom => 'Starting the room…';
  @override
  String get cantStartRoom => "Can't start a room on this device.";
  @override
  String get cantHostInBrowser => "This browser can't host a room. Join one here, or host in the app.";
  @override
  String get roomNotNearby => "Can't find the room: check the code and your internet.";
  @override
  String get noDirectRoute => "Can't connect directly to the host from this network. Try another network (Wi-Fi "
      'instead of mobile data), or play on the same Wi-Fi.';
  @override
  String get cantReachServer => "Can't reach the server";
  @override
  String get wsOnWebsite => "This website can't use a ws:// server. Use wss://, or clear the server.";
  @override
  String sameWifi(bool yes) => yes ? 'Same Wi-Fi: yes' : 'Same Wi-Fi: no network';
  @override
  String get sameWifiAppOnly => 'Same Wi-Fi: app only';
  @override
  String internetStatus(PeerStatus status) => switch (status.phase) {
        PeerPhase.starting => 'Internet: connecting…',
        PeerPhase.ready => 'Internet: ready',
        PeerPhase.unavailable => switch (status.trouble) {
            PeerTrouble.codeTaken => 'Internet: not available (busy: create a new room)',
            PeerTrouble.unsupported => 'Internet: not available on this device',
            _ => 'Internet: not available (no connection)',
          },
      };
  @override
  String internetHelp({required PeerStatus status, required bool windows, required bool phone, bool browser = false}) => [
        if (status.phase == PeerPhase.unavailable)
          switch (status.trouble) {
            PeerTrouble.codeTaken => "The meeting service couldn't give this room a name. Create a new room for "
                'friends elsewhere.',
            PeerTrouble.unsupported => "This version of the app can't connect over the internet.",
            _ => "The meeting service can't be reached (no internet?). The app keeps trying.",
          },
        'Friends anywhere can join with the code or the invite.',
        'A free public meeting service introduces the devices. Then the game goes device to device, encrypted.',
        if (browser)
          "Some networks (often mobile data) can't connect directly. Same Wi-Fi without internet works only when "
              'the room is hosted in the app.'
        else
          "Some networks (often mobile data) can't connect directly. Same Wi-Fi always works, even without internet.",
        if (browser) 'Keep this tab open while you host: the room closes with the tab.',
        if (windows) 'The first time, Windows Firewall asks whether PokerFection may use the network: allow it.',
        if (phone)
          'Keep the app open on screen while you host: the room stops when the app closes or goes to the background.',
      ].join('\n\n');
  @override
  String get connecting => 'Connecting…';
  @override
  String joinError(JoinError? error) => switch (error) {
        JoinError.upgrade => 'Update the app to play',
        JoinError.roomNotFound => 'Room not found',
        JoinError.roomFull => 'Room full',
        JoinError.rateLimited => 'Too many tries: wait a minute',
        JoinError.serverFull => 'Server full: try later',
        JoinError.internal => 'Server error',
        JoinError.roomGone => 'The room has closed',
        JoinError.seatGone => 'You were away too long: join again',
        JoinError.removed => 'The host removed you from the room',
        null => "Can't reach the room",
      };
  @override
  String room(String code) => 'Room $code';
  @override
  String get copied => 'Copied';
  @override
  String get shareCode => 'Friends join with this code or the invite.';
  @override
  String get host => 'Host';
  @override
  String get botBadge => 'Bot';
  @override
  String get awayBadge => 'Away';
  @override
  String get leftBadge => 'Left';
  @override
  String get nextHandBadge => 'Next hand';
  @override
  String get help => 'Help';
  @override
  String get noHelp => 'None';
  @override
  String get timeLimit => 'Time';
  @override
  String turnLimit(int seconds) => seconds == 0 ? 'Off' : '$seconds s';
  @override
  String secondsLeft(int seconds) => '$seconds s';
  @override
  String get waitingForHost => 'Waiting for the host…';
  @override
  String get joinNextHand => 'You sit down at the next hand.';
  @override
  String nextHandIn(int seconds) => 'Next hand in $seconds s';
  @override
  String onlineNotice(OnlineNotice notice) => switch (notice) {
        OnlineNotice.timesUp => "Time's up",
        OnlineNotice.refused => 'Not allowed: choose again',
        OnlineNotice.outOfSync => 'Out of sync',
      };
  @override
  String get hostAway => 'The host is away: the bots check or fold.';
  @override
  String get connectionLost => 'Connection lost';
  @override
  String get reconnecting => 'Reconnecting…';
  @override
  String rejoinRoom(String code) => 'Rejoin Room $code';
  @override
  String closed(CloseReason? reason) => switch (reason) {
        CloseReason.roomClosed => 'The host closed the room.',
        CloseReason.serverRestart => 'The server restarted.',
        CloseReason.replaced => 'Your seat moved to another window.',
        CloseReason.roomError => 'The room closed after an error.',
        CloseReason.idle => 'The room closed: no hand for a long while.',
        CloseReason.removed => 'The host removed you from the room.',
        null => 'The room closed.',
      };
  @override
  String get closeRoom => 'Close Room';
  @override
  String get tableSettings => 'Table';
  @override
  String get fromNextHand => 'Changes apply from the next hand.';
  @override
  String get leave => 'Leave';
  @override
  String get leaveTable => 'Leave the table?';
  @override
  String leaveWarning({required bool host}) =>
      host ? 'The room closes for everyone.' : 'Your seat is empty from the next hand.';
  @override
  String get seats => 'Seats';
  @override
  String get emptySeat => 'Empty seat';
  @override
  String get addBot => 'Add Bot';
  @override
  String get removeBot => 'Remove';
  @override
  String get leavingBadge => 'Leaves next hand';
  @override
  String get needPlayers => 'A hand needs 2 players: invite a friend or add a bot.';
  @override
  String get waitingForPlayers => 'Waiting for players (2 needed)';
  @override
  String get joinGame => 'Join game';
  @override
  String get leaveSeat => 'Leave seat';
  @override
  String get spectators => 'Spectators';
  @override
  String get spectatorsSeeBots => "Spectators see bots' cards";
  @override
  String get seatList => 'Seats';
  @override
  String get game => 'Game';
  @override
  String get endGame => 'End game';
  @override
  String get nextGameBadge => 'Next game';
  @override
  String get updateToWatch => 'Update the app to watch';
  @override
  String get leaveRoom => 'Leave Room';
  @override
  String get leaveRoomQuestion => 'Leave the room?';
  @override
  String get closeRoomQuestion => 'Close the room?';
  @override
  String get leaveSeatQuestion => 'Leave your seat?';
  @override
  String get leaveSeatWarning => 'You finish this hand first.';
  @override
  String get pickGame => 'Pick a game';
  @override
  String get waitingForGame => 'Waiting for the host to pick a game';
  @override
  String get seatsAfterGame => 'Seats appear once a game is picked.';
  @override
  String inRoom(String code) => "You're in room $code.";
  @override
  String get leaveSeatWarningRound => 'You finish this round first.';
  @override
  String needSeats(int n) => 'This game needs $n players: invite a friend or add a bot.';
  @override
  String get people => 'People';
  @override
  String get playingNow => 'Playing';
  @override
  String get pickGameOnHome => 'Pick a game on Home.';
  @override
  String get onlineSoon => 'Online soon';
  @override
  String get sit => 'Sit';
  @override
  String get openTable => 'Open Table';
  @override
  String get endGameFirst => 'End the game in play first.';
  @override
  String roomSetupNote(String code) => 'Room $code: this opens the game for everyone in it.';
  @override
  String get about => 'About';
  @override
  String versionNumber(String version) => 'Version $version';
  @override
  String buildCommits(int commits, {required bool changed}) =>
      changed ? 'Build: $commits commits + local changes' : 'Build: $commits commits';
  @override
  String get devBuild => 'Build: development';
  @override
  String madeBy(String name) => 'Made by $name';
  @override
  String gamesList(String list) => 'Games: $list';
  @override
  String onlineRooms(int protocol) => 'Online rooms, peer to peer (protocol v$protocol)';
  @override
  String runningOn(String platform) => 'Running on $platform';
  @override
  String get showMyCards => 'Show My Cards';
  @override
  String showNotice(String? name, String cards) => name == null ? 'You show $cards' : '$name shows $cards';
  @override
  String helpNotice(String? name) => name == null ? 'You used GTO help' : '$name used GTO help';
  @override
  String get rulesChanged => 'The host changed the rules (from the next hand).';
  @override
  String get rebuys => 'Rebuys';
  @override
  String get outBadge => 'Out';
  @override
  String outOfChips({required bool rebuys}) =>
      rebuys ? "You're out of chips." : "You're out of chips: you watch until the game ends.";
  @override
  String rebuy(String stack) => 'Rebuy $stack';
  @override
  String get lobby => 'Room';
  @override
  String get watch => 'Watch';
  @override
  String gameOver(String? winner, {bool you = false}) =>
      you ? 'Game over: you win!' : (winner == null ? 'Game over' : 'Game over: $winner wins');
  @override
  String get sitOut => 'Sit Out';
  @override
  String get imBack => "I'm Back";
  @override
  String get sittingOutBadge => 'Sitting out';
  @override
  String get sitOutNextHand => 'You sit out from the next hand.';
  @override
  String get youSitOut => "You're sitting out: you aren't dealt in.";
  @override
  String get removePlayer => 'Remove';
  @override
  String removePlayerQuestion(String name) => 'Remove $name?';
  @override
  String get removePlayerWarning => "They can't join this room again. If they're in a hand, they leave when it ends.";
  @override
  String removedNotice(String name) => '$name was removed';
  @override
  String get chat => 'Chat';
  @override
  String get chatHint => 'Message';
  @override
  String get send => 'Send';
  @override
  String get noMessages => 'No messages yet';
  @override
  String get chatTooFast => 'Too fast: wait a moment';
  @override
  String get drills => 'Drills';
  @override
  String drillsDue(int due) => due == 0 ? 'Drills' : 'Drills ($due due)';
  @override
  String savedToDrills(String wait, {required bool again}) =>
      again ? 'Already in your drills: back in $wait' : 'Saved to your drills: first review in $wait';
  @override
  String drillQueued(String wait, {required bool? right}) => switch (right) {
        true => '✓ Next review in $wait',
        false => 'Back in $wait',
        null => 'Not graded: next review in $wait',
      };
  @override
  String drillSpot(String grade, int due) => 'Saved spot ($grade) · $due due';
  @override
  String randomHands(String? next) => next == null
      ? 'No saved mistakes yet. Dealing new random hands.'
      : 'All caught up! Next review in $next. Dealing new random hands.';
  @override
  String get noSavedMistakes => 'No saved mistakes yet';
  @override
  String get playRandomHands => 'Play random hands';
  @override
  String get savedSpots => 'Saved Spots';
  @override
  String get dueNow => 'Due now';
  @override
  String reviewIn(String wait) => 'In $wait';
  @override
  String waitTime(int count, WaitUnit unit) => switch (unit) {
        WaitUnit.minutes => '$count min',
        WaitUnit.hours => '$count h',
        WaitUnit.days => count == 1 ? '1 day' : '$count days',
        WaitUnit.weeks => count == 1 ? '1 week' : '$count weeks',
        WaitUnit.months => count == 1 ? '1 month' : '$count months',
        WaitUnit.years => count == 1 ? '1 year' : '$count years',
      };

  @override
  String section(GlossarySection section) => switch (section) {
        GlossarySection.modes => 'Modes',
        GlossarySection.positions => 'Positions',
        GlossarySection.amounts => 'Amounts',
        GlossarySection.actions => 'Actions',
        GlossarySection.hand => 'The Hand',
        GlossarySection.strategy => 'Strategy',
        GlossarySection.scoring => 'Scoring',
        GlossarySection.rules => 'Rules',
        GlossarySection.styles => 'Play Styles',
        GlossarySection.online => 'Online',
      };

  @override
  String term(GlossaryTerm term) => positionTerms[term] ?? switch (term) {
        GlossaryTerm.training => 'GTO Training',
        GlossaryTerm.play => 'Free Play',
        GlossaryTerm.drills => 'Drills',
        GlossaryTerm.inPosition => 'IP / OOP',
        GlossaryTerm.headsUp => 'Heads-up',
        GlossaryTerm.bigBlinds => 'BB',
        GlossaryTerm.ante => 'Ante',
        GlossaryTerm.pot => 'Pot',
        GlossaryTerm.stack => 'Stack',
        GlossaryTerm.allIn => 'All-in',
        GlossaryTerm.raiseTo => 'Raise to',
        GlossaryTerm.betSizes => 'Bet sizes',
        GlossaryTerm.fold => 'Fold',
        GlossaryTerm.check => 'Check',
        GlossaryTerm.call => 'Call',
        GlossaryTerm.betRaise => 'Bet / Raise',
        GlossaryTerm.open => 'Open',
        GlossaryTerm.limp => 'Limp',
        GlossaryTerm.threeBet => '3-bet / 4-bet',
        GlossaryTerm.preActions => 'Pre-actions',
        GlossaryTerm.holeCards => 'Hole cards',
        GlossaryTerm.preflop => 'Preflop',
        GlossaryTerm.streets => 'Flop / Turn / River',
        GlossaryTerm.board => 'Board',
        GlossaryTerm.showdown => 'Showdown',
        GlossaryTerm.gto => 'GTO',
        GlossaryTerm.solver => 'Solver',
        GlossaryTerm.range => 'Range',
        GlossaryTerm.rangeGrid => 'Range grid',
        GlossaryTerm.charts => 'Preflop charts',
        GlossaryTerm.equity => 'Equity',
        GlossaryTerm.ev => 'EV',
        GlossaryTerm.mixedStrategy => 'Mixed strategy',
        GlossaryTerm.rng => 'RNG',
        GlossaryTerm.potOdds => 'Pot odds',
        GlossaryTerm.evLoss => 'EV loss',
        GlossaryTerm.mixMatch => 'Match',
        GlossaryTerm.score => 'Score',
        GlossaryTerm.grades => 'Grades',
        GlossaryTerm.solving => 'Solving…',
        GlossaryTerm.noLimit => 'No-Limit',
        GlossaryTerm.minBet => 'Min-bet',
        GlossaryTerm.minRaise => 'Min-raise',
        GlossaryTerm.houseRule => 'House rule',
        GlossaryTerm.incompleteRaise => 'Incomplete raise',
        GlossaryTerm.reopen => 'Reopen the action',
        GlossaryTerm.splitPot => 'Split pot',
        GlossaryTerm.styleGto => 'GTO',
        GlossaryTerm.tag => 'TAG',
        GlossaryTerm.lag => 'LAG',
        GlossaryTerm.station => 'Station',
        GlossaryTerm.nit => 'Nit',
        GlossaryTerm.roomCode => 'Room code',
        GlossaryTerm.roomStays => 'Staying in a room',
        GlossaryTerm.host => 'Host',
        GlossaryTerm.hosting => 'Hosting',
        GlossaryTerm.onlineBots => 'Bots',
        GlossaryTerm.timeLimit => 'Time',
        GlossaryTerm.helpLevel => 'Help',
        GlossaryTerm.roomGame => 'Game',
        GlossaryTerm.spectators => 'Spectators',
        GlossaryTerm.seeBots => "Bots' cards",
        GlossaryTerm.rebuys => 'Rebuys',
        GlossaryTerm.sitOut => 'Sit out',
        GlossaryTerm.chat => 'Chat',
        GlossaryTerm.away => 'Away',
        _ => term.name,
      };

  @override
  String definition(GlossaryTerm term) => switch (term) {
        GlossaryTerm.training => "Play against the bots and learn from GTO. Simple: play normally; after a "
            "Mistake or a Blunder, GTO's answer shows, and Show GTO shows it any time. Advanced: at every "
            "decision, set how often you think GTO folds, calls or raises (and how much), then see GTO's "
            'answer and your score. Pick one when setting up the game. Preflop, the bots play GTO; '
            'their styles apply after the flop.',
        GlossaryTerm.play => 'Play against the bots without scores, like a real game.',
        GlossaryTerm.drills => 'Every Mistake or Blunder you make in GTO Training (Simple or Advanced) is saved as a '
            'spot: the same hand, up to that decision. Drills deals the spots that are due again, the '
            'most overdue first, and grades your play like Simple training; Show GTO waits until you have played. '
            'Played right (Good or better), a spot comes back later each time: in 1 h, 1 day, 3 days, 1 week, then '
            "about 2.5 times longer. Played wrong (or the same mistake again in training), it's back in 10 min. "
            'Spots stay however well you know them, up to 256: then the ones you know best go first. With nothing '
            'due, Drills deals random hands at random tables, and their mistakes join your drills. ☰ > Saved Spots '
            'lists them all.',
        GlossaryTerm.utg => 'Under the gun: first to act before the flop.',
        GlossaryTerm.utg1 => 'The seat after UTG.',
        GlossaryTerm.lj => 'Lojack: three seats before the button.',
        GlossaryTerm.hj => 'Hijack: two seats before the button.',
        GlossaryTerm.co => 'Cutoff: the seat just before the button.',
        GlossaryTerm.btn => 'Button (dealer): acts last after the flop, the best seat. Heads-up, the button '
            'also posts the small blind.',
        GlossaryTerm.sb => 'Small blind: posts half a big blind before the deal; acts first after the flop.',
        GlossaryTerm.bb => 'Big blind: posts one big blind before the deal; acts last before the flop.',
        GlossaryTerm.inPosition => 'In position (IP): you act after your opponent after the flop. Out of '
            'position (OOP): you act first. Acting last is an advantage.',
        GlossaryTerm.headsUp => 'Only two players, at the table or in the pot.',
        GlossaryTerm.bigBlinds => 'Big blinds, the unit for stacks and bets: a 100 BB stack is 100 big blinds.',
        GlossaryTerm.ante => 'A small forced bet every player posts before the deal.',
        GlossaryTerm.pot => 'All the chips bet so far. A "0.5× pot" raise is half the size of the pot.',
        GlossaryTerm.stack => "A player's chips. Only the smaller of two stacks can be won between them "
            '(the effective stack).',
        GlossaryTerm.allIn => 'Betting all your chips (also shoving or jamming).',
        GlossaryTerm.raiseTo => 'Your total bet after the raise, including what you had already put in.',
        GlossaryTerm.betSizes => 'Your raise choices follow one rule, before and after the flop: the Fibonacci '
            'numbers in big blinds, 1, 2, 3, 5, 8, 13, 21, 34, 55 BB and so on (the total you raise to), from the '
            'min-raise up to all-in. With 100 BB first in: 2, 3, 5, 8, 13, 21, 34, 55 and 89 BB, plus All-in. '
            'All-in counts what someone still in the hand can call. Each size also shows as × the bet before the '
            'flop and × pot after it.',
        GlossaryTerm.fold => 'Give up the hand and the chips already in the pot.',
        GlossaryTerm.check => 'Pass without betting (only when nobody has bet).',
        GlossaryTerm.call => 'Match the current bet.',
        GlossaryTerm.betRaise => 'Put in chips first (bet) or more than the current bet (raise).',
        GlossaryTerm.open => 'The first raise before the flop.',
        GlossaryTerm.limp => 'Calling the big blind before the flop instead of raising.',
        GlossaryTerm.threeBet => 'The next raises before the flop: the big blind counts as the first bet and '
            'the open as the second, so the re-raise is the 3-bet, and so on.',
        GlossaryTerm.preActions => 'While another player acts, tick your play in advance: Check/Fold (checks if '
            "it's free, else folds), Check (cancelled if someone bets), Call the amount shown (cancelled if the bet "
            'changes) or Call Any. It plays the moment your turn comes; tap it again to cancel. It lasts until the '
            'street ends. In Simple training the play is still scored; Advanced training has none (it needs '
            'percentages). Online they make the game faster.',
        GlossaryTerm.holeCards => 'Your two private cards.',
        GlossaryTerm.preflop => 'The betting before any shared cards are dealt.',
        GlossaryTerm.streets => 'The shared cards: three at once, then one, then one more, each followed by a '
            'round of betting.',
        GlossaryTerm.board => 'The shared cards on the table.',
        GlossaryTerm.showdown => 'After the last bet, the players left show their cards; the best hand wins.',
        GlossaryTerm.gto => "Game Theory Optimal: a strategy that can't be beaten in the long run, whatever "
            'the opponents do. Solvers find it (or get close).',
        GlossaryTerm.solver => "A program that works out GTO strategies. This app's solver is near-GTO: it "
            'simplifies some parts, such as the betting on later streets.',
        GlossaryTerm.range => 'All the hands a player could have in a spot, and how likely each one is.',
        GlossaryTerm.rangeGrid => 'All 169 kinds of starting hands in a 13 × 13 table: pairs on the diagonal, '
            'suited hands above it, offsuit below. Share of Range: brighter cells make up more of the range. '
            'Frequency: how often each hand is played this way.',
        GlossaryTerm.charts => 'What GTO does with each starting hand before the flop when everyone else folds: '
            'first in (Open), facing a raise (vs Open), or facing a re-raise after opening (vs 3-Bet). Colors '
            'split each hand into Raise, Call and Fold; a dark hand never gets there, a partly filled one only '
            'sometimes. Tap a hand for its numbers.',
        GlossaryTerm.equity => 'Your share of the pot if all the remaining cards were dealt with no more betting.',
        GlossaryTerm.ev => 'Expected value: how many BB an action wins or loses on average.',
        GlossaryTerm.mixedStrategy => 'Playing the same hand in different ways some of the time, such as '
            'calling 60% and raising 40%. GTO often does this to stay unpredictable.',
        GlossaryTerm.rng => 'Random number generator: let chance pick your action from your percentages, the '
            'way GTO mixes its play.',
        GlossaryTerm.potOdds => 'What you must call compared with the pot you could win. Calling pays when '
            'your equity is higher than this share.',
        GlossaryTerm.evLoss => "How many BB your percentages give up compared with GTO's own mix. The EV Loss column shows "
            'each action against the best one.',
        GlossaryTerm.mixMatch => "How close your percentages are to GTO's: 100% means identical.",
        GlossaryTerm.score => '0 to 100. Simple: each play scores 100, minus a point per 0.01 BB it gives up. '
            'Advanced: half for the match, half for losing little EV; what counts is how often you fold, check '
            'or call, and raise, and raise sizes count only 10%. In the history, a white border marks Advanced '
            'hands.',
        GlossaryTerm.grades => 'By EV loss (raise sizes count 10%): Best (up to 0.02 BB), Good (0.08), Inaccuracy (0.25), '
            'Mistake (0.75), Blunder (more).',
        GlossaryTerm.solving => "GTO's answer for this decision is still being worked out. Play on: your move "
            "is graded when the answer is ready, and Show GTO shows it as soon as it comes.",
        GlossaryTerm.noLimit => 'The betting used here: you can bet or raise any amount, up to all your chips.',
        GlossaryTerm.minBet => 'The smallest bet allowed: one big blind.',
        GlossaryTerm.minRaise => 'The smallest raise allowed. Standard: at least the size of the last bet or '
            'raise on the street (facing a bet of 10, raise to 20 or more; after 10 is raised to 30, the next '
            'raise is to at least 50).',
        GlossaryTerm.houseRule => 'A rule a table agrees on instead of the standard one, such as allowing any '
            'raise of at least 1 BB.',
        GlossaryTerm.incompleteRaise => "An all-in for less than a full min-raise. It's allowed, but it doesn't "
            'reopen the action: players who already acted can only call or fold.',
        GlossaryTerm.reopen => 'A full raise lets everyone who already acted on the street raise again.',
        GlossaryTerm.splitPot => "Tied hands share the pot. When it doesn't divide evenly, the odd chip goes to "
            'the first winner left of the button.',
        GlossaryTerm.styleGto => "Plays the solver's near-optimal strategy.",
        GlossaryTerm.tag => 'Tight-aggressive: plays few hands, but bets and raises them hard.',
        GlossaryTerm.lag => 'Loose-aggressive: plays many hands and puts on lots of pressure.',
        GlossaryTerm.station => 'Calling station: calls too often and rarely raises.',
        GlossaryTerm.nit => 'Very tight: waits for premium hands.',
        GlossaryTerm.roomCode => 'Five letters that name an online room. Friends join with it from Play Online.',
        GlossaryTerm.host => 'The player who made the room: it runs on their device. The host picks the game, sets up '
            'the table, the help and the time, starts the game, and plays the bots. The host can remove anyone: tap '
            "their name in the room (at the table, ☰ > Room), then Remove. They go at once (if they're in a hand, when "
            "it ends) and can't join the room again. The room ends when the host presses Close Room or quits the app.",
        GlossaryTerm.roomStays => "While you're in a room, its people and its chat stay on the right of every screen: "
            "play, read the guides or change settings, and you're still in it. Leave Room takes you out; the host's "
            'Close Room ends it for everyone.',
        GlossaryTerm.roomGame => "The host picks the game as usual: a game on Home, then Play. Everyone in the room goes "
            "to its table, where the seats are: Sit takes one. Picking another game sends everyone back to watching. "
            'Greyed out: not playable online yet.',
        GlossaryTerm.spectators => "Everyone enters a room as a spectator and sees every person's cards and the play "
            'styles. Coach shows the best play for whoever acts. Join game takes a seat for the next round.',
        GlossaryTerm.seeBots => "The host's choice: spectators also see the bots' cards, from the next round.",
        GlossaryTerm.hosting => "Create Room runs the room on your device: the game goes through the host's app, with "
            'no game server of ours. Friends join with the code or the invite: on the same Wi-Fi even without '
            'internet; from anywhere else, a free public meeting service introduces the devices, then the game goes '
            "device to device, encrypted (some networks, often mobile data, can't connect directly). Friends without "
            'the app play in a browser from the invite. The room ends when the host presses Close Room or quits the '
            'app. A browser can host too: everyone then joins over the internet, and the room closes with the tab.',
        GlossaryTerm.onlineBots => 'A new room has no game; once the host picks one, its seats appear, all empty. Join game takes an '
            "empty seat (or a bot's: the bot gives way), and the host can add bots (each with a play style) or take "
            'them away. A hand is dealt to the seats taken, so it needs at least 2 players; with fewer the game waits. '
            'Joining, leaving, adding or taking away a bot during a hand counts from the next hand.',
        GlossaryTerm.timeLimit => "How long each player has to decide. When time runs out, the server checks if it's "
            'free, else folds. Off: no limit.',
        GlossaryTerm.helpLevel => 'The help everyone at the table gets, set by the host: None (like Free Play), '
            "Simple or Advanced (like GTO Training). Online, other players' cards stay hidden. Your choices show "
            "at once and GTO's answer joins them when it is solved (Solving…). Moves go as soon as you pick "
            'them: the score shows without holding the table, and a move made before the answer is scored when it comes. '
            'Everyone is told when a player presses Show GTO.',
        GlossaryTerm.rebuys => 'What happens to a player who loses all their chips, set by the host. Rebuys on: they '
            'choose Rebuy (the starting stack again, from the next hand) or Leave; bots rebuy by themselves. Rebuys '
            "off: they're out (their seat says Out) and watch the game, from the table or the Room, or leave. When "
            "only one player has chips and nobody can rebuy, the game is over: everyone is back in the room, "
            'and the host presses Start for a new game with fresh stacks. With Reset Stacks Every Hand nobody runs out.',
        GlossaryTerm.sitOut => "☰ > Sit Out: from the next hand you aren't dealt in, but you keep your seat and chips "
            "and watch the table. ☰ > I'm Back deals you in again from the next hand. With fewer than 2 players dealt "
            "in, the game waits. A player whose connection is down for a whole hand sits out until they're back.",
        GlossaryTerm.chat => 'Everyone in the room can chat: in the room, and during the game in its Room tab or ☰ > Chat (also '
            "while out of chips). New messages show for a moment at the top of the table, then fade; ☰ > Chat has the "
            'whole conversation and the quick messages (one tap sends one). Up to 256 characters a message, and at '
            'most 4 messages every 8 seconds. The room keeps the last 64 messages: players who join or come back see '
            'them.',
        GlossaryTerm.away => 'A player whose connection drops keeps their seat for 2 minutes. Meanwhile the server checks '
            'or folds for them after 3 s (after a whole hand away, they sit out until they are back), and the game waits '
            'if fewer than 2 can play. Their app reconnects by itself and '
            'catches up with the hand; one that was closed can rejoin from Play Online. While the host is away the bots '
            'check or fold. A room hosted in the app waits for its host; on a server of your own it closes when the '
            'host is gone for 2 minutes.',
      };
}
