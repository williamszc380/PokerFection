import '../bots/bot.dart';
import '../engine/events.dart';
import '../engine/hand_evaluator.dart';
import '../engine/rules.dart';
import '../gto/preflop/preflop_charts.dart';
import '../gto/spot_strategy.dart';
import '../ui/table_controller.dart' show PlaybackSpeed;
import 'strings.dart';

class StringsEn extends S {
  const StringsEn();

  @override
  String get play => 'Play';
  @override
  String get settings => 'Settings';

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
  String get freePlay => 'Free Play';
  @override
  String get players => 'Players';
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
  String get betSizes => 'Bet Sizes';
  @override
  String get preflop => 'Preflop';
  @override
  String get postflop => 'Postflop';
  @override
  String get add => 'Add';
  @override
  String get resetDefaults => 'Reset';
  @override
  String get cancel => 'Cancel';
  @override
  String get preflopSizePrompt => 'Raise size (× the bet)';
  @override
  String get postflopSizePrompt => 'Raise size (× the pot)';
  @override
  String between(String low, String high) => '$low to $high';
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
  String get newStylesDealt => 'New random play styles.';
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
  String get potWord => 'pot';

  @override
  String potOdds(int percent) => 'Pot Odds $percent%';
  @override
  String get showGto => 'Show GTO';
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
  String unavailable(Unavailable reason) => switch (reason) {
        Unavailable.checkIsFree => 'Check is free',
        Unavailable.raisingNotAllowed => "Can't raise",
        Unavailable.belowMinBet => 'Below the min-bet',
        Unavailable.belowMinRaise => 'Below the min-raise',
        Unavailable.nearlyAllIn => 'Nearly all-in: use All-in',
        Unavailable.sameAmount => 'Same as a smaller size',
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
      };

  @override
  String term(GlossaryTerm term) => positionTerms[term] ?? switch (term) {
        GlossaryTerm.training => 'GTO Training',
        GlossaryTerm.play => 'Free Play',
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
        _ => term.name,
      };

  @override
  String definition(GlossaryTerm term) => switch (term) {
        GlossaryTerm.training => 'At every decision, set how often you think GTO folds, calls or raises (and '
            "how much), tick what you'll play, then see GTO's answer and your score. Preflop, the bots play "
            'GTO so your spots come from GTO play; their styles apply after the flop.',
        GlossaryTerm.play => 'Play against the bots without scores, like a real game.',
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
        GlossaryTerm.betSizes => 'Your bet and raise choices, the same at every decision. Preflop they are '
            'multiples of the bet you face: first in, 2× is a raise to 2 BB; against an open to 2.5 BB, 3× is '
            'a raise to 7.5 BB. Postflop they are multiples of the pot: 0.5× pot is half the pot (after calling, when facing a bet). '
            'Sizes not allowed in a spot are greyed out; one that is nearly all-in is covered by All-in. More '
            'sizes take longer to solve.',
        GlossaryTerm.fold => 'Give up the hand and the chips already in the pot.',
        GlossaryTerm.check => 'Pass without betting (only when nobody has bet).',
        GlossaryTerm.call => 'Match the current bet.',
        GlossaryTerm.betRaise => 'Put in chips first (bet) or more than the current bet (raise).',
        GlossaryTerm.open => 'The first raise before the flop.',
        GlossaryTerm.limp => 'Calling the big blind before the flop instead of raising.',
        GlossaryTerm.threeBet => 'The next raises before the flop: the big blind counts as the first bet and '
            'the open as the second, so the re-raise is the 3-bet, and so on.',
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
        GlossaryTerm.score => '0 to 100: half for the match, half for losing little EV. What counts is how often '
            'you fold, check or call, and raise; raise sizes count only 10%.',
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
      };
}
