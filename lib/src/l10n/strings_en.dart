import '../bots/bot.dart';
import '../engine/events.dart';
import '../engine/hand_evaluator.dart';
import '../engine/rules.dart';
import '../gto/preflop/preflop_charts.dart';
import '../gto/hand_read.dart';
import '../gto/spot_strategy.dart';
import '../online/protocol.dart' show CloseReason, JoinError;
import '../online/room_host.dart' show InternetAccess;
import '../ui/table_controller.dart' show OnlineNotice, PlaybackSpeed;
import 'strings.dart';

class StringsEn extends S {
  const StringsEn();

  @override
  String get play => 'Play';
  @override
  String get settings => 'Settings';

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
  String get copyBrowserLink => 'Copy browser link';
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
  String get solo => 'Solo';
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
  String get mainMenu => 'Main Menu';
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
  String solvingTable(int percent) => 'Solving… $percent%';
  @override
  String get solvingDecision => 'Solving…';
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
        null => 'No GTO answer',
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
  String get cantHostInBrowser => 'Rooms are hosted in the app (Windows, Android, iPhone). Here you can join one.';
  @override
  String get websiteCantJoin =>
      "This website can't reach a room on someone's device: open the browser address from the invite instead.";
  @override
  String get roomNotNearby => 'No room with that code on this network: ask the host for the invite.';
  @override
  String sameWifi(bool yes) => yes ? 'Same Wi-Fi: yes' : 'Same Wi-Fi: no network';
  @override
  String internetStatus(InternetAccess access) => switch (access) {
        InternetAccess.checking => 'Internet: checking…',
        InternetAccess.ready => 'Internet: ready',
        _ => 'Internet: not available',
      };
  @override
  String get internetByHand => 'Internet: set by hand';
  @override
  String internetHelp({
    required InternetAccess access,
    required int port,
    String? address,
    String? byHand,
    required bool windows,
    required bool phone,
  }) =>
      [
        switch (access) {
          InternetAccess.checking => 'The app is asking your router to let friends on the internet in.',
          InternetAccess.ready => 'Your router opened port $port: friends on the internet can join with the invite.',
          InternetAccess.noRouter => 'No router answered the automatic setup (UPnP is off, or the router has none).',
          InternetAccess.refused => 'Your router refused to open the port.',
          InternetAccess.notPublic => 'Your router has no public address of its own: the internet provider shares '
              'one (CGNAT), or another router sits in front of it.',
          InternetAccess.byHand => "On iPhone and iPad the app can't set up the router.",
        },
        if (access != InternetAccess.ready)
          "To open it by hand: in your router's settings, forward TCP port $port to ${address ?? 'this device'}. "
              "Then type the router's public IP under Public address in the lobby: invites carry it.",
        if (byHand != null)
          "Set by hand: invites carry $byHand. The app can't check it: ask a friend outside to open "
              'http://$byHand/health.',
        'Same Wi-Fi always works.',
        if (windows) 'The first time, Windows Firewall asks whether PokerFection may use the network: allow it.',
        'Some internet providers (shared addresses, CGNAT) and mobile data make playing over the internet impossible '
            'without an outside server.',
        if (phone)
          'Keep the app open on screen while you host: the room stops when the app closes or goes to the background. '
              "On mobile data, friends on the internet usually can't join.",
      ].join('\n\n');
  @override
  String get publicAddress => 'Public address';
  @override
  String get notPublicAddress => 'Type your public IP, like 203.0.113.7';
  @override
  String publicAddressHelp({required int port, String? address, required bool windows}) => [
        "For a router that can't open the port by itself (UPnP off). Open it by hand once: in the router's "
            'settings page or app, find Port forwarding and forward TCP port $port to '
            '${windows ? 'this PC' : 'this device'}${address == null ? '' : ', $address'}.',
        "Then type your public IP here. The router's app or status page shows it (WAN or Internet IP address), "
            'or search "what is my IP". If the router leads another port outside to $port, add it: '
            '203.0.113.7:47500.',
        "Invites then carry it, and so does the browser link. The app can't check it: ask a friend outside to "
            'open http://<public IP>:$port/health. Most public IPs change from time to time: check it before you '
            'play.',
      ].join('\n\n');
  @override
  String get connecting => 'Connecting…';
  @override
  String joinError(JoinError? error) => switch (error) {
        JoinError.upgrade => 'Update the app to play',
        JoinError.roomNotFound => 'Room not found',
        JoinError.tableFull => 'Table full',
        JoinError.rateLimited => 'Too many tries: wait a minute',
        JoinError.serverFull => 'Server full: try later',
        JoinError.internal => 'Server error',
        JoinError.roomGone => 'The room has closed',
        JoinError.seatGone => 'You were away too long: join again',
        JoinError.removed => 'The host removed you from the room',
        null => "Can't reach the server",
      };
  @override
  String room(String code) => 'Room $code';
  @override
  String get copied => 'Copied';
  @override
  String get shareCode => 'On the same Wi-Fi the code is enough; send the invite to the others.';
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
  String get allowSeeCards => "Players Can See Others' Cards";
  @override
  String get seeCards => 'See Cards';
  @override
  String seeCardsQuestion(String name) => "See $name's cards? Everyone is told.";
  @override
  String helpNotice(String? name) => name == null ? 'You used GTO help' : '$name used GTO help';
  @override
  String peekNotice(String? name, String? target) => switch ((name, target)) {
        (null, final t?) => "You looked at $t's cards",
        (final n?, null) => '$n looked at your cards',
        (final n?, final t?) => "$n looked at $t's cards",
        (null, null) => 'You looked at your cards',
      };
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
  String get lobby => 'Lobby';
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
        GlossaryTerm.host => 'Host',
        GlossaryTerm.hosting => 'Hosting',
        GlossaryTerm.onlineBots => 'Bots',
        GlossaryTerm.timeLimit => 'Time',
        GlossaryTerm.helpLevel => 'Help',
        GlossaryTerm.seeCards => 'See cards',
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
            'spot: the same hand, up to that decision. Drills (main menu) deals the spots that are due again, the '
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
        GlossaryTerm.host => 'The player who made the room: it runs on their device. The host sets up the table, the '
            'help and the time, starts the game, and plays the bots. The host can remove a player: tap their seat in '
            "the lobby or ☰ > Edit Table, then Remove. They go at once (if they're in a hand, when it ends) and can't "
            'join the room again. If the host leaves, the room closes.',
        GlossaryTerm.hosting => "Create Room runs the room on your device: the game goes through the host's app, with "
            'no outside server. Friends on the same Wi-Fi join with the code or the invite; friends elsewhere join with '
            'the invite once your router lets them in (the app tries to set that up: see Internet in the lobby). '
            "Friends without the app open the invite's browser address (when the app has the web version). The room "
            "ends when the host leaves or closes the app. The browser version can't host a room, only join one.",
        GlossaryTerm.onlineBots => 'A new room has only the host: the other seats are empty. Friends who join take an '
            'empty seat, and the host can add bots (each with a play style) or take them away. A hand is dealt to the '
            'seats taken, so it needs at least 2 players; with fewer the game waits. Joining, leaving, adding or '
            'taking away a bot during the game counts from the next hand, and a player who leaves leaves an empty seat.',
        GlossaryTerm.timeLimit => "How long each player has to decide. When time runs out, the server checks if it's "
            'free, else folds. Off: no limit.',
        GlossaryTerm.helpLevel => 'The help everyone at the table gets, set by the host: None (like Free Play), '
            "Simple or Advanced (like GTO Training). Online, other players' cards stay hidden. Your choices show "
            "at once and GTO's answer joins them when it is solved (Solving…). Moves go as soon as you pick "
            'them: the score shows without holding the table, and a move made before the answer is scored when it comes. '
            'Everyone is told when a player presses Show GTO.',
        GlossaryTerm.seeCards => "When the host allows it, tap another player's seat during a hand and pick See Cards: "
            'their cards show face up for you until the hand ends. Everyone at the table is told who looked at whose cards.',
        GlossaryTerm.rebuys => 'What happens to a player who loses all their chips, set by the host. Rebuys on: they '
            'choose Rebuy (the starting stack again, from the next hand) or Leave; bots rebuy by themselves. Rebuys '
            "off: they're out (their seat says Out) and watch the game, from the table or the Lobby, or leave. When "
            "only one player has chips and nobody can rebuy, the game is over: everyone is back in the room's lobby, "
            'and the host presses Start for a new game with fresh stacks. With Reset Stacks Every Hand nobody runs out.',
        GlossaryTerm.sitOut => "☰ > Sit Out: from the next hand you aren't dealt in, but you keep your seat and chips "
            "and watch the table. ☰ > I'm Back deals you in again from the next hand. With fewer than 2 players dealt "
            "in, the game waits. A player whose connection is down for a whole hand sits out until they're back.",
        GlossaryTerm.chat => 'Everyone in the room can chat: in the lobby, and during the game from ☰ > Chat (also '
            "while out of chips). New messages show for a moment at the top of the table, then fade; ☰ > Chat has the "
            'whole conversation and the quick messages (one tap sends one). Up to 256 characters a message, and at '
            'most 4 messages every 8 seconds. The room keeps the last 64 messages: players who join or come back see '
            'them.',
        GlossaryTerm.away => 'A player whose connection drops keeps their seat for 2 minutes. Meanwhile the server checks '
            'or folds for them after 3 s (after a whole hand away, they sit out until they are back), and the game waits '
            'if fewer than 2 can play. Their app reconnects by itself and '
            'catches up with the hand; one that was closed can rejoin from Play Online. While the host is away the bots '
            'check or fold; when the host is gone for 2 minutes (or closes the app), the room closes.',
      };
}
