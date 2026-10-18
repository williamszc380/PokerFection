import 'package:flutter/widgets.dart';

import '../app/app_settings.dart';
import '../bots/bot.dart';
import '../engine/events.dart';
import '../engine/hand_evaluator.dart';
import '../engine/rules.dart';
import '../gto/preflop/preflop_charts.dart';
import '../gto/hand_read.dart';
import '../gto/spot_strategy.dart';
import '../game/history.dart' show HandNote;
import '../online/protocol.dart' show CloseReason, HelpLevel, JoinError;
import '../online/peer_status.dart' show PeerStatus;
import '../ui/table_controller.dart' show OnlineNotice, PlaybackSpeed;
import 'strings_en.dart';
import 'strings_es.dart';
import 'strings_zh.dart';

/// Glossary sections, in the order shown.
enum GlossarySection { modes, positions, amounts, actions, hand, strategy, scoring, rules, styles, online }

/// The units of a wait, shortest first (see formatWait).
enum WaitUnit { minutes, hours, days, weeks, months, years }

/// Glossary entries, by section.
enum GlossaryTerm {
  training(GlossarySection.modes),
  play(GlossarySection.modes),
  drills(GlossarySection.modes),
  utg(GlossarySection.positions),
  utg1(GlossarySection.positions),
  lj(GlossarySection.positions),
  hj(GlossarySection.positions),
  co(GlossarySection.positions),
  btn(GlossarySection.positions),
  sb(GlossarySection.positions),
  bb(GlossarySection.positions),
  inPosition(GlossarySection.positions),
  headsUp(GlossarySection.positions),
  bigBlinds(GlossarySection.amounts),
  ante(GlossarySection.amounts),
  pot(GlossarySection.amounts),
  stack(GlossarySection.amounts),
  allIn(GlossarySection.amounts),
  raiseTo(GlossarySection.amounts),
  betSizes(GlossarySection.amounts),
  fold(GlossarySection.actions),
  check(GlossarySection.actions),
  call(GlossarySection.actions),
  betRaise(GlossarySection.actions),
  open(GlossarySection.actions),
  limp(GlossarySection.actions),
  threeBet(GlossarySection.actions),
  preActions(GlossarySection.actions),
  holeCards(GlossarySection.hand),
  preflop(GlossarySection.hand),
  streets(GlossarySection.hand),
  board(GlossarySection.hand),
  showdown(GlossarySection.hand),
  gto(GlossarySection.strategy),
  solver(GlossarySection.strategy),
  range(GlossarySection.strategy),
  rangeGrid(GlossarySection.strategy),
  charts(GlossarySection.strategy),
  equity(GlossarySection.strategy),
  ev(GlossarySection.strategy),
  mixedStrategy(GlossarySection.strategy),
  rng(GlossarySection.strategy),
  potOdds(GlossarySection.strategy),
  evLoss(GlossarySection.scoring),
  mixMatch(GlossarySection.scoring),
  score(GlossarySection.scoring),
  grades(GlossarySection.scoring),
  noLimit(GlossarySection.rules),
  minBet(GlossarySection.rules),
  minRaise(GlossarySection.rules),
  houseRule(GlossarySection.rules),
  incompleteRaise(GlossarySection.rules),
  reopen(GlossarySection.rules),
  splitPot(GlossarySection.rules),
  styleGto(GlossarySection.styles),
  tag(GlossarySection.styles),
  lag(GlossarySection.styles),
  station(GlossarySection.styles),
  nit(GlossarySection.styles),
  roomCode(GlossarySection.online),
  host(GlossarySection.online),
  hosting(GlossarySection.online),
  onlineBots(GlossarySection.online),
  timeLimit(GlossarySection.online),
  helpLevel(GlossarySection.online),
  seeCards(GlossarySection.online),
  rebuys(GlossarySection.online),
  sitOut(GlossarySection.online),
  chat(GlossarySection.online),
  away(GlossarySection.online);

  const GlossaryTerm(this.section);
  final GlossarySection section;
}

/// Every text the app shows, in one language. Get it with [S.of].
///
/// Labels are kept short and use standard poker terms; the glossary (the
/// "?" buttons) explains them.
abstract class S {
  const S();

  static S of(BuildContext context) => forLanguage(AppSettings.of(context).language);

  static S forLanguage(AppLanguage language) => switch (language) {
        AppLanguage.english => const StringsEn(),
        AppLanguage.spanish => const StringsEs(),
        AppLanguage.chinese => const StringsZh(),
      };

  // Main menu and settings.
  String get play;
  String get settings;

  // Hand rankings.
  String get handRankings;
  String get royalFlush;

  /// Online invites: the button, the message to send (with the link that
  /// opens the app, and the code), copying and pasting it.
  String get invite;
  ///
  /// [appLink] opens the app at the room; [wifiPage] and [internetPage] open
  /// the web version at it (on the same Wi-Fi, from elsewhere), when the
  /// host serves it.
  String get copyInviteLink;
  String get noInvite;
  String get inviteThisComputer;

  /// The page may not read the clipboard (a browser on a host's http page).
  String get pasteBlocked;

  /// Play Online: the code box (a code or an invite link; empty to create a
  /// room), the join button, and a code that isn't one.
  String get roomCodeOrLink;
  String get emptyToCreate;
  String get joinRoom;
  String get notACode;

  /// How often a hand comes: "1 in 38.5".
  String oneIn(String x);

  /// What the odds on the Hand Rankings screen count.
  String get rankingOddsNote;
  String handCategory(HandCategory category);

  // Preflop Charts.
  String get preflopCharts;
  String get spot;
  String chartSpot(ChartSpot spot);

  /// Who made the raise faced in [spot]: the opener, or the 3-bettor.
  String chartVillain(ChartSpot spot);

  /// Calls (of any amount), in the charts' key.
  String get callWord;

  /// How many of all starting hands get to a spot.
  String inRange(int percent);
  String get glossary;
  String get animations;
  String get sound;
  String get cardBack;
  String get cardFaces;
  String get twoColors;
  String get fourColors;

  /// Cards filled with their suit's color.
  String get coloredCards;
  String get tableColor;
  String speed(PlaybackSpeed speed);

  // Game setup.
  String get newGame;
  String get training;

  /// The two levels of GTO Training.
  String get simple;
  String get advanced;
  String get freePlay;
  String get players;

  /// The ☰ item (and sheet) for changing the table: players, stacks, styles.
  String get editTable;

  /// Main menu: Play opens Solo and Multiplayer; Guides opens the guides.
  String get solo;
  String get multiplayer;
  String get guides;
  String get stack;
  String get opponentStyles;
  String get random;
  String style(BotStyle style);
  String get showStyles;
  String get showCards;
  String get customizeSeats;
  String get you;
  String get position;
  String get rotate;
  String get resetStacks;
  String get preflop;
  String get postflop;
  String get cancel;
  String get rules;
  String get minRaise;
  String raiseRule(RaiseRule rule);
  String get ante;
  String get noAnte;
  String get start;

  // At the table.
  String handsPlayed(int hands);
  String get showAllCards;
  String get hideAllCards;
  String get ranges;
  String get history;
  String get shuffleStyles;
  String get mainMenu;
  String get showRange;
  String get changeStyle;
  String get showTheirCards;
  String get hideTheirCards;

  // Actions ([amount] and [size] already formatted, e.g. "7.5 BB", "3×").
  String get fold;
  String get check;
  String call(String amount);
  String raiseTo(String amount, String? size);
  String allIn(String amount);

  /// Under a player with no chips left.
  String get allInBadge;
  String get raiseAnySize;

  /// The pre-actions, picked while another player acts (see
  /// GlossaryTerm.preActions), and the line under them.
  String get checkFold;
  String get callAny;
  String get playsAtYourTurn;

  /// The word for the pot in sizes ("0.5× pot").
  String get potWord;

  /// A size after the flop, as a multiple of the pot: 0.5 -> "0.5× pot",
  /// 1 -> "1× pot" (like "2.5×" before the flop).
  String potShare(double share) => '${number(share)}× $potWord';

  /// A raise size before the flop: 2.5 -> "2.5×".
  String multiple(double multiple) => '${number(multiple)}×';

  /// 2.0 -> "2", 2.5 -> "2.5", 2.25 -> "2.25".
  static String number(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

  // The decision panel.
  String potOdds(int percent);

  /// Fills in GTO's answer before playing.
  String get showGto;

  /// After the flop with more than two players: GTO's answer is approximate.
  String get approxMultiway;
  String get randomize;
  String get playRandomized;
  String get continueHand;
  String score(int score);
  String evLossAndMatch(String evLoss, int match);
  String youPlay(String action);
  String randomized(String action);
  String solvingTable(int percent);
  String get solvingDecision;
  String thinking(String name);
  String get nextHand;
  String get evenHand;
  String noAnswer(NoAnswer? reason);
  String unavailable(Unavailable reason);

  /// Why a play was a mistake, in a few words, with GTO's choice instead
  /// ([amount] for a raise): "Too tight: GTO calls here."
  String mistakeReason(MistakeKind kind, SpotActionKind gto, String amount);

  /// The reason behind GTO's choice (see [reasonFor]) for the user's [hand]:
  /// "62% of their hands beat yours, mostly flushes."
  String mistakeWhy(Reason reason, String hand);
  String grade(DecisionGrade grade);
  String get columnYou;
  String get columnGto;
  String get columnEvLoss;

  // Scores and history.
  String get average;
  String get all;
  String get noScoresYet;
  String get decisions;
  String get averageScore;
  String get evLoss;
  String get net;
  String handNumber(int number);
  String street(Street street);
  String get close;
  String get ok;
  String get fullGlossary;

  // Ranges.
  String get yourRange;
  String get shareOfRange;
  String get frequency;
  String get noRange;

  // Results at the table.
  String wins(String name, String amount, {required bool you});
  String split(String names, String amount);
  String get mainPot;
  String sidePot(int number);
  String listNames(List<String> names);
  String hand(HandValue value);

  // Online.
  String get playOnline;
  String get yourName;
  String get enterName;
  String get createRoom;
  String get roomCode;
  String get join;
  String get server;

  /// Under the server field: what an empty one means.
  String get serverHint;

  /// Hosting a room on this device: starting it, failing to, and why this
  /// browser can't (no direct connections: Create Room greyed out).
  String get startingRoom;
  String get cantStartRoom;
  String get cantHostInBrowser;

  /// Joining with just a code found the room nowhere it could look (not on
  /// this network, and the meeting service couldn't be asked).
  String get roomNotNearby;

  /// Joining (or getting a dropped connection back) failed because the
  /// host answered but this device can't connect to it directly from its
  /// network (no relay): what to try.
  String get noDirectRoute;

  /// Creating or joining a room on a server set by hand that can't be
  /// reached.
  String get cantReachServer;

  /// On the website (https), a ws:// server set by hand: the browser won't
  /// connect to it from a secure page.
  String get wsOnWebsite;

  /// The ways into a room hosted here: the same network, and the internet
  /// (direct connections through the meeting service, see PeerStatus,
  /// with a short reason when not available); and the "?" next to them,
  /// which says how it works and, when not available, why ([status]);
  /// with what to mind on [windows], a [phone] or in a [browser] tab. A
  /// room hosted in a browser has no way in on the same Wi-Fi of its own
  /// ([sameWifiAppOnly], greyed out).
  String sameWifi(bool yes);
  String get sameWifiAppOnly;
  String internetStatus(PeerStatus status);
  String internetHelp({required PeerStatus status, required bool windows, required bool phone, bool browser = false});
  String get connecting;

  /// Why creating or joining failed (null: the room can't be reached).
  String joinError(JoinError? error);

  /// The room's name, from its code: "Room K7QXA".
  String room(String code);
  String get copied;
  String get shareCode;
  String get host;

  /// Under a seat: a bot plays it, the player is away (their connection
  /// dropped) or left, someone sits down next hand.
  String get botBadge;
  String get awayBadge;
  String get leftBadge;
  String get nextHandBadge;
  String get help;
  String get noHelp;
  String helpLevel(HelpLevel level) => switch (level) {
        HelpLevel.none => noHelp,
        HelpLevel.simple => simple,
        HelpLevel.advanced => advanced,
      };
  String get timeLimit;

  /// A time limit choice: 0 is none.
  String turnLimit(int seconds);
  String secondsLeft(int seconds);
  String get waitingForHost;
  String get joinNextHand;
  String nextHandIn(int seconds);
  String onlineNotice(OnlineNotice notice);
  String get hostAway;
  String get connectionLost;

  /// The connection dropped: getting it back.
  String get reconnecting;

  /// Play Online: back to the room the app was in when it closed.
  String rejoinRoom(String code);

  /// Why the room ended for this player.
  String closed(CloseReason? reason);
  String get closeRoom;

  /// Online, from ☰: the help and time the host can change during the game.
  String get tableSettings;
  String get fromNextHand;
  String get leave;
  String get leaveTable;
  String leaveWarning({required bool host});

  /// Seats nobody has, and the host's bots: adding one (with its style),
  /// taking it away, and the badge of one that leaves at the next hand.
  String get seats;
  String get emptySeat;
  String get addBot;
  String get removeBot;
  String get leavingBadge;

  /// A hand needs at least 2 players: in the lobby by Start, and at the
  /// table while the game waits.
  String get needPlayers;
  String get waitingForPlayers;

  /// Looking at another player's cards: the host's setting, the seat's
  /// button, and the question first (everyone is told).
  String get allowSeeCards;
  String get seeCards;
  String seeCardsQuestion(String name);

  /// What everyone at the table is told: a player pressed Show GTO, or
  /// looked at someone's cards (a null name is the user).
  String helpNotice(String? name);
  String peekNotice(String? name, String? target);
  String note(HandNote note) => switch (note) {
        HandNote(shown: final cards?) =>
          showNotice(note.name, [for (final c in cards) '${c.rankLabel}${c.suitSymbol}'].join(' ')),
        HandNote(peek: true) => peekNotice(note.name, note.target),
        _ => helpNotice(note.name),
      };

  /// After a hand: the button to show the user's cards to everyone, and
  /// the notice ([name] null: the user).
  String get showMyCards;
  String showNotice(String? name, String cards);
  String get rulesChanged;

  /// Out of chips: the room's rule, the seat's badge, and what the user
  /// can do: Rebuy for [stack] (or Leave) with rebuys, else watch (the
  /// room's Lobby, and back to Watch). Once one player has every chip,
  /// the game is over: who won ([winner]; null when nobody is left).
  String get rebuys;
  String get outBadge;
  String outOfChips({required bool rebuys});
  String rebuy(String stack);
  String get lobby;
  String get watch;
  String gameOver(String? winner, {bool you = false});

  /// Sitting out (see GlossaryTerm.sitOut): ☰'s Sit Out and I'm Back, the
  /// seat's badge, and what the user is told: they sit out from the next
  /// hand (still in the one on screen), or they sit out now.
  String get sitOut;
  String get imBack;
  String get sittingOutBadge;
  String get sitOutNextHand;
  String get youSitOut;

  /// The host removes a player (their seat in the lobby or ☰ > Edit
  /// Table): the choice, the question first, and what everyone else is
  /// told ([name] was removed).
  String get removePlayer;
  String removePlayerQuestion(String name);
  String get removePlayerWarning;
  String removedNotice(String name);

  /// The room's chat: its name, the box to type in, Send, an empty chat,
  /// and why sending is greyed out for a moment (too many messages at once).
  String get chat;
  String get chatHint;
  String get send;
  String get noMessages;
  String get chatTooFast;

  /// Mistake drills (see GlossaryTerm.drills): the main menu's button with
  /// how many spots are due; what the table says when a mistake is saved
  /// ([again]: the same spot was saved before; [wait] like "10 min"); and
  /// once a spot is played again, when it is back ([right]: played right,
  /// or wrong; null: it couldn't be graded).
  String get drills;
  String drillsDue(int due);
  String savedToDrills(String wait, {required bool again});
  String drillQueued(String wait, {required bool? right});

  /// Above the choices: a saved spot ([grade] as it was saved, [due] spots
  /// due), or random hands, with when the next spot is due ([next]; null:
  /// none is saved yet).
  String drillSpot(String grade, int due);
  String randomHands(String? next);

  /// Drills with nothing saved yet, and the button that deals random hands.
  String get noSavedMistakes;
  String get playRandomHands;

  /// Every saved spot (☰), and when each is due.
  String get savedSpots;
  String get dueNow;
  String reviewIn(String wait);

  /// A wait, short: "10 min", "1 h", "3 days".
  String waitTime(int count, WaitUnit unit);

  // Glossary.
  String section(GlossarySection section);
  String term(GlossaryTerm term);
  String definition(GlossaryTerm term);
}

/// Position names are the same in every language.
const positionTerms = {
  GlossaryTerm.utg: 'UTG',
  GlossaryTerm.utg1: 'UTG+1',
  GlossaryTerm.lj: 'LJ',
  GlossaryTerm.hj: 'HJ',
  GlossaryTerm.co: 'CO',
  GlossaryTerm.btn: 'BTN',
  GlossaryTerm.sb: 'SB',
  GlossaryTerm.bb: 'BB',
};

/// Card ranks as players write them: 2-9, T, J, Q, K, A (0 = deuce).
const rankSymbols = ['2', '3', '4', '5', '6', '7', '8', '9', 'T', 'J', 'Q', 'K', 'A'];

extension StringsContext on BuildContext {
  /// The texts in the app's language.
  S get s => S.of(this);
}
